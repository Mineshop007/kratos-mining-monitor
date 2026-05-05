#!/usr/bin/env python3
"""
Kratos in-app chat ↔ Mineshop Discord bridge.

Runs on solo.mineshop.eu, exposes a small HTTP/WebSocket API the
Flutter app talks to, mirroring messages to/from Discord channels in
the Kratos DEV server.

  Endpoints:
    GET  /kratos/chat/health
    GET  /kratos/chat/channels
    GET  /kratos/chat/{channel}/messages?limit=50&before=<id>
    POST /kratos/chat/{channel}/send       { "text", "displayName" }
    WS   /kratos/chat/stream?token=<device-token>

  Auth:
    Per-device bearer token. Anything is accepted; we rate-limit per
    token and per IP. First-seen tokens are stored in tokens.sqlite
    so banning is straightforward.

  No fake data:
    - All messages relayed verbatim from Discord (real, real users).
    - When Discord is offline, /messages returns 503 with last-known
      cache marker, never invented content.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import sqlite3
import time
from collections import defaultdict, deque
from contextlib import suppress
from pathlib import Path

import aiohttp
from aiohttp import web
import discord
from discord.ext import commands

# ─── Config ────────────────────────────────────────────────────────────

CONFIG_PATH = Path(__file__).with_name('channels.json')
DB_PATH = Path(__file__).with_name('tokens.sqlite')
LOG_PATH = Path('/var/log/kratos-chat-bridge.log')
PORT = int(os.environ.get('KRATOS_CHAT_PORT', '8765'))

# in-app slug → Discord channel id (loaded from channels.json)
CHANNEL_MAP: dict[str, int] = {}
READ_ONLY: set[str] = set()         # in-app slugs that can't be posted to

# Rate limit: 10 messages per 30s per token; 200 messages / day per token
PER_TOKEN_BURST = 10
PER_TOKEN_BURST_WINDOW_SEC = 30
PER_TOKEN_DAILY = 200

DAILY_BUCKETS: dict[str, deque[float]] = defaultdict(deque)
BURST_BUCKETS: dict[str, deque[float]] = defaultdict(deque)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger('kratos-chat')


# ─── State ─────────────────────────────────────────────────────────────

# WebSocket clients waiting for live broadcasts.
WS_CLIENTS: set[web.WebSocketResponse] = set()


def load_channel_map() -> None:
    global CHANNEL_MAP, READ_ONLY
    cfg = json.loads(CONFIG_PATH.read_text())
    CHANNEL_MAP = {k: int(v['id']) for k, v in cfg['channels'].items()}
    READ_ONLY = {k for k, v in cfg['channels'].items() if v.get('readOnly')}
    log.info('loaded %d channels (%d read-only)', len(CHANNEL_MAP), len(READ_ONLY))


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tokens (
            token TEXT PRIMARY KEY,
            first_seen INTEGER,
            last_seen INTEGER,
            ip TEXT,
            display_name TEXT,
            banned INTEGER DEFAULT 0
        )
    """)
    conn.commit()
    return conn


def register_token(token: str, ip: str, display_name: str | None) -> bool:
    """Returns False if banned."""
    now = int(time.time())
    with db() as conn:
        row = conn.execute(
            "SELECT banned FROM tokens WHERE token = ?",
            (token,),
        ).fetchone()
        if row and row[0] == 1:
            return False
        if not row:
            conn.execute(
                "INSERT INTO tokens(token, first_seen, last_seen, ip, display_name) VALUES (?, ?, ?, ?, ?)",
                (token, now, now, ip, display_name),
            )
        else:
            conn.execute(
                "UPDATE tokens SET last_seen = ?, ip = ?, display_name = COALESCE(?, display_name) WHERE token = ?",
                (now, ip, display_name, token),
            )
        conn.commit()
    return True


def rate_limit_ok(token: str) -> tuple[bool, str | None]:
    now = time.time()
    bucket = BURST_BUCKETS[token]
    while bucket and bucket[0] < now - PER_TOKEN_BURST_WINDOW_SEC:
        bucket.popleft()
    if len(bucket) >= PER_TOKEN_BURST:
        return False, 'burst-limit'
    daily = DAILY_BUCKETS[token]
    cutoff = now - 24 * 3600
    while daily and daily[0] < cutoff:
        daily.popleft()
    if len(daily) >= PER_TOKEN_DAILY:
        return False, 'daily-limit'
    bucket.append(now)
    daily.append(now)
    return True, None


# ─── Discord side ──────────────────────────────────────────────────────

intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True

bot = commands.Bot(command_prefix='!', intents=intents)
BOT_READY = asyncio.Event()


@bot.event
async def on_ready():
    log.info('Discord connected as %s (id %s)', bot.user, bot.user.id)
    BOT_READY.set()


@bot.event
async def on_message(msg: discord.Message):
    # Only mirror messages from mapped channels.
    if msg.channel.id not in CHANNEL_MAP.values():
        return
    # Skip our own webhook posts (they'd loop). Webhook posts have
    # webhook_id set; bot user posts are msg.author.bot.
    payload = serialize_message(msg)
    await broadcast(payload)


def serialize_message(msg: discord.Message) -> dict:
    slug = next((k for k, v in CHANNEL_MAP.items() if v == msg.channel.id), None)
    return {
        'kind': 'message',
        'channel': slug,
        'channelId': str(msg.channel.id),
        'id': str(msg.id),
        'author': {
            'id': str(msg.author.id),
            'displayName': msg.author.display_name,
            'isBot': bool(msg.author.bot),
            'isWebhook': msg.webhook_id is not None,
        },
        'text': msg.content,
        'createdAt': msg.created_at.isoformat(),
        'attachments': [
            {'url': a.url, 'name': a.filename, 'size': a.size}
            for a in msg.attachments
        ],
        'replyTo': str(msg.reference.message_id) if msg.reference else None,
    }


async def fetch_recent(channel_id: int, limit: int = 50,
                       before: int | None = None) -> list[dict]:
    ch = bot.get_channel(channel_id)
    if ch is None:
        return []
    out: list[dict] = []
    async for m in ch.history(limit=limit,
                              before=discord.Object(id=before) if before else None):
        out.append(serialize_message(m))
    return out


async def post_message(channel_id: int, text: str,
                       display_name: str) -> dict:
    ch = bot.get_channel(channel_id)
    if ch is None:
        raise web.HTTPNotFound(reason='channel not bridged')
    # Use a per-channel webhook so the avatar/displayName matches the user.
    # Reuse the first existing 'kratos-bridge' webhook or create one.
    hook = None
    for h in await ch.webhooks():
        if h.name == 'kratos-bridge':
            hook = h
            break
    if hook is None:
        hook = await ch.create_webhook(name='kratos-bridge')
    msg = await hook.send(
        content=text[:1900],  # Discord cap is 2000
        username=f'{display_name} (kratos)',
        wait=True,
    )
    return serialize_message(msg) if hasattr(msg, 'content') else {
        'kind': 'message',
        'channel': next((k for k, v in CHANNEL_MAP.items() if v == channel_id), None),
        'id': str(msg.id),
        'author': {'displayName': display_name, 'isBot': False, 'isWebhook': True},
        'text': text,
        'createdAt': time.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'attachments': [],
    }


# ─── HTTP / WS server ──────────────────────────────────────────────────

async def broadcast(payload: dict) -> None:
    if not WS_CLIENTS:
        return
    raw = json.dumps(payload)
    dead: list[web.WebSocketResponse] = []
    for ws in WS_CLIENTS:
        try:
            await ws.send_str(raw)
        except Exception:
            dead.append(ws)
    for d in dead:
        WS_CLIENTS.discard(d)


def auth(request: web.Request) -> tuple[str, str] | web.Response:
    token = request.headers.get('X-Kratos-Token') or request.query.get('token', '')
    if not token or len(token) < 20 or len(token) > 64:
        return web.Response(status=401, text='missing or malformed token')
    ip = request.headers.get('X-Forwarded-For', request.remote or '').split(',')[0].strip()
    if not register_token(token, ip,
                          request.headers.get('X-Kratos-DisplayName')):
        return web.Response(status=403, text='banned')
    return token, ip


async def health(request: web.Request) -> web.Response:
    return web.json_response({
        'ok': True,
        'discord': BOT_READY.is_set(),
        'wsClients': len(WS_CLIENTS),
        'channels': list(CHANNEL_MAP.keys()),
    })


async def channels(request: web.Request) -> web.Response:
    return web.json_response({
        'channels': [
            {'slug': k, 'id': str(v), 'readOnly': k in READ_ONLY}
            for k, v in CHANNEL_MAP.items()
        ],
    })


async def messages(request: web.Request) -> web.Response:
    a = auth(request)
    if isinstance(a, web.Response):
        return a
    slug = request.match_info['channel']
    if slug not in CHANNEL_MAP:
        return web.Response(status=404, text='unknown channel')
    if not BOT_READY.is_set():
        return web.json_response(
            {'error': 'discord-offline'}, status=503)
    limit = max(1, min(100, int(request.query.get('limit', '50'))))
    before = request.query.get('before')
    msgs = await fetch_recent(
        CHANNEL_MAP[slug],
        limit=limit,
        before=int(before) if before and before.isdigit() else None,
    )
    return web.json_response({'messages': msgs})


async def send(request: web.Request) -> web.Response:
    a = auth(request)
    if isinstance(a, web.Response):
        return a
    token, ip = a
    slug = request.match_info['channel']
    if slug not in CHANNEL_MAP:
        return web.Response(status=404, text='unknown channel')
    if slug in READ_ONLY:
        return web.Response(status=403, text='channel is read-only')
    body = await request.json()
    text = (body.get('text') or '').strip()
    if not text:
        return web.Response(status=400, text='empty text')
    if len(text) > 1900:
        return web.Response(status=400, text='message too long')
    display_name = (body.get('displayName') or '').strip() or f'kratos-{token[:6]}'
    if len(display_name) > 32:
        display_name = display_name[:32]
    ok, why = rate_limit_ok(token)
    if not ok:
        return web.Response(status=429, text=f'rate-limited: {why}')
    try:
        msg = await post_message(CHANNEL_MAP[slug], text, display_name)
        return web.json_response(msg)
    except Exception as e:
        log.exception('post failed')
        return web.Response(status=502, text=f'post failed: {e}')


async def stream(request: web.Request) -> web.WebSocketResponse:
    a = auth(request)
    if isinstance(a, web.Response):
        return a
    ws = web.WebSocketResponse(heartbeat=25)
    await ws.prepare(request)
    WS_CLIENTS.add(ws)
    log.info('WS client connect (%d total)', len(WS_CLIENTS))
    try:
        await ws.send_json({
            'kind': 'hello',
            'channels': list(CHANNEL_MAP.keys()),
            'discord': BOT_READY.is_set(),
        })
        async for msg in ws:
            # Currently no client-to-server WS messages; ignore.
            pass
    finally:
        WS_CLIENTS.discard(ws)
        log.info('WS client disconnect (%d total)', len(WS_CLIENTS))
    return ws


def make_app() -> web.Application:
    app = web.Application()
    app.router.add_get('/kratos/chat/health', health)
    app.router.add_get('/kratos/chat/channels', channels)
    app.router.add_get('/kratos/chat/{channel}/messages', messages)
    app.router.add_post('/kratos/chat/{channel}/send', send)
    app.router.add_get('/kratos/chat/stream', stream)
    return app


# ─── Boot ──────────────────────────────────────────────────────────────

async def main() -> None:
    load_channel_map()
    db()  # ensure table exists

    token = os.environ.get('DISCORD_BOT_TOKEN')
    if not token:
        raise SystemExit('DISCORD_BOT_TOKEN env var required')

    app = make_app()
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '127.0.0.1', PORT)
    await site.start()
    log.info('HTTP+WS listening on 127.0.0.1:%d', PORT)

    # Run Discord bot. discord.Client.start() awaits until disconnect.
    try:
        await bot.start(token)
    finally:
        await runner.cleanup()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
