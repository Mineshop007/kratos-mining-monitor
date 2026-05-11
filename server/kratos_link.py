#!/usr/bin/env python3
"""
Kratos Link — Home Network Bridge  v1.4
Run this on any PC/Mac/Pi on the same network as your miners.
It discovers ALL miner types (BitAxe, NerdAxe, LuckyMiner, Avalon, Antminer…)
and bridges them to the Kratos app via secure relay.

Usage:
  python3 kratos_link.py --generate-key          # get a new key
  python3 kratos_link.py --key YOUR_KEY           # start bridge

Download: https://kratos.mineshop.eu/link
"""

import asyncio, json, logging, sys, socket, ipaddress, argparse, secrets, ssl, os, ast, tempfile, stat, time
from typing import Optional
import aiohttp, websockets

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
log = logging.getLogger('kratos-link')

# Bridge connects via WSS (encrypted, Cloudflare-proxied).
# Uses ssl_no_verify so Python websockets doesn't struggle with CF cert checks.
BRIDGE_VERSION     = '1.4'
UPDATE_URL         = 'https://kratos.mineshop.eu/relay/bridge-version.json'
PRIMARY_RELAY_URL  = 'wss://kratos.mineshop.eu'
FALLBACK_RELAY_URL = 'wss://soloblocks.io'
RELAY_URL          = PRIMARY_RELAY_URL
RELAY_URLS         = [PRIMARY_RELAY_URL, FALLBACK_RELAY_URL]
DISCOVERY_TIMEOUT  = 2.0   # seconds per host
CGMINER_TIMEOUT    = 1.5
RECONNECT_DELAYS   = [5, 10, 20, 40, 60]
PRIMARY_RETRY_EVERY = 600  # seconds
REDISCOVER_EVERY   = 120   # seconds
UPDATE_EVERY       = 86400 # seconds
BRIDGE_CAPABILITIES = ['esp_miner', 'cgminer_tcp', 'avalon_http', 'fluminer_http']


def _version_tuple(version: str) -> tuple:
    parts = []
    for part in str(version).split('.'):
        try:
            parts.append(int(part))
        except ValueError:
            parts.append(0)
    return tuple(parts)


async def check_for_update() -> None:
    """Best-effort self update. Any failure is logged and the bridge continues."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(UPDATE_URL, timeout=aiohttp.ClientTimeout(total=10)) as r:
                if r.status != 200:
                    log.warning(f'Update check failed: HTTP {r.status}')
                    return
                manifest = await r.json(content_type=None)

            remote_version = str(manifest.get('version', '')).strip()
            remote_url = str(manifest.get('url', '')).strip()
            if not remote_version or not remote_url:
                log.warning('Update check failed: invalid manifest')
                return
            if _version_tuple(remote_version) <= _version_tuple(BRIDGE_VERSION):
                return

            log.info(f'Bridge update available: v{remote_version} (current v{BRIDGE_VERSION})')
            async with session.get(remote_url, timeout=aiohttp.ClientTimeout(total=30)) as r:
                if r.status != 200:
                    log.warning(f'Update download failed: HTTP {r.status}')
                    return
                source = await r.text()

        ast.parse(source)
        current_path = os.path.abspath(__file__)
        current_mode = stat.S_IMODE(os.stat(current_path).st_mode)
        fd, tmp_path = tempfile.mkstemp(prefix='kratos_link_', suffix='.py', dir='/tmp')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(source)
            os.chmod(tmp_path, current_mode)
            os.replace(tmp_path, current_path)
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except Exception:
                    pass
        log.info(f'Updated bridge to v{remote_version}; restarting…')
        os.execv(sys.executable, [sys.executable] + sys.argv)
    except Exception as e:
        log.warning(f'Update check failed: {e}')


async def update_loop() -> None:
    while True:
        await asyncio.sleep(UPDATE_EVERY)
        await check_for_update()

# ── Probe helpers ──────────────────────────────────────────────────────────────

async def probe_esp_miner(session: aiohttp.ClientSession, ip: str, port=80) -> Optional[dict]:
    """BitAxe / NerdAxe / LuckyMiner — ESP-Miner HTTP API on port 80"""
    paths = ['/api/system/info', '/api/system', '/']
    for path in paths:
        try:
            url = f'http://{ip}:{port}{path}'
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=DISCOVERY_TIMEOUT)) as r:
                if r.status != 200:
                    continue
                data = await r.json(content_type=None)
                if not isinstance(data, dict):
                    continue
                # Must have at least one miner-specific key
                if not any(k in data for k in ('hashRate', 'hashRate_1m', 'avgHashRate',
                                                'boardVersion', 'deviceModel', 'ASICModel',
                                                'hostname', 'version', 'uptimeSeconds')):
                    continue
                hostname = (data.get('hostname') or data.get('boardVersion') or
                            data.get('deviceModel') or data.get('ASICModel') or f'Miner@{ip}')
                return {
                    'ip': ip, 'port': port, 'protocol': 'esp_miner',
                    'model': str(hostname).strip(),
                    'hashrate': data.get('hashRate_1m') or data.get('hashRate') or data.get('avgHashRate') or 0,
                    'firmware': data.get('version', ''),
                }
        except Exception:
            pass
    return None


async def probe_cgminer_tcp(ip: str, port=4028) -> Optional[dict]:
    """LuckyMiner / Avalon / Antminer / Whatsminer — cgminer TCP API on port 4028"""
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(ip, port), timeout=CGMINER_TIMEOUT)
        writer.write(b'{"command":"summary"}\n')
        await writer.drain()
        buf = b''
        try:
            while True:
                chunk = await asyncio.wait_for(reader.read(4096), timeout=CGMINER_TIMEOUT)
                if not chunk:
                    break
                buf += chunk
                if b'SUMMARY' in buf:
                    break
        except asyncio.TimeoutError:
            pass
        writer.close()
        try:
            writer.close()
        except Exception:
            pass

        if not buf:
            return None
        raw = buf.decode('utf-8', errors='ignore').rstrip('\x00').strip()
        if not raw:
            return None
        data = json.loads(raw)
        summary = (data.get('SUMMARY') or [{}])[0]
        # Try to get model via devdetails command
        model = f'CGMiner@{ip}'
        try:
            reader2, writer2 = await asyncio.wait_for(
                asyncio.open_connection(ip, port), timeout=CGMINER_TIMEOUT)
            writer2.write(b'{"command":"devdetails"}\n')
            await writer2.drain()
            buf2 = b''
            try:
                while True:
                    chunk2 = await asyncio.wait_for(reader2.read(4096), timeout=CGMINER_TIMEOUT)
                    if not chunk2:
                        break
                    buf2 += chunk2
                    if b'DEVDETAILS' in buf2:
                        break
            except asyncio.TimeoutError:
                pass
            writer2.close()
            raw2 = buf2.decode('utf-8', errors='ignore').rstrip('\x00').strip()
            if raw2:
                d2 = json.loads(raw2)
                devs = (d2.get('DEVDETAILS') or [{}])
                if devs:
                    model = devs[0].get('Model') or devs[0].get('Name') or model
        except Exception:
            pass

        hashrate = summary.get('GHS 1m') or summary.get('GHS 5m') or summary.get('GHS av') or 0
        return {
            'ip': ip, 'port': port, 'protocol': 'cgminer_tcp',
            'model': model,
            'hashrate': float(hashrate) * 1000 if hashrate else 0,  # GH/s → MH/s
            'firmware': '',
        }
    except Exception:
        return None


async def probe_fluminer(session: aiohttp.ClientSession, ip: str, port=80) -> Optional[dict]:
    """FluMiner T3 — HTTP REST API on port 80, identified by /api/overview"""
    try:
        url = f'http://{ip}:{port}/api/overview'
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=DISCOVERY_TIMEOUT)) as r:
            if r.status != 200:
                return None
            data = await r.json(content_type=None)
            if not isinstance(data, dict) or data.get('code') != 0:
                return None
            inner = data.get('data', {})
            if not isinstance(inner, dict) or 'minerInfo' not in inner:
                return None
            info = inner['minerInfo']
            model = info.get('model', '')
            mac   = (info.get('macAddress') or info.get('wifiMacAddress') or '').lower()
            # Positive match: model == 'T3' or MAC starts with 70:69:79
            if model != 'T3' and not mac.startswith('70:69:79'):
                return None
            return {
                'ip': ip, 'port': port, 'protocol': 'fluminer_http',
                'model': f'FluMiner {model}' if model else 'FluMiner T3',
                'hashrate': 0,
                'firmware': info.get('minerVersion', ''),
            }
    except Exception:
        return None


async def check_host(session: aiohttp.ClientSession, ip: str) -> Optional[dict]:
    """Try all protocols concurrently for a single IP"""
    results = await asyncio.gather(
        probe_esp_miner(session, ip, 80),
        probe_fluminer(session, ip, 80),
        probe_cgminer_tcp(ip, 4028),
        return_exceptions=True
    )
    for r in results:
        if isinstance(r, dict):
            return r
    return None


_forced_subnet: str | None = None

async def discover_miners() -> list:
    log.info('Scanning local network for miners…')

    if _forced_subnet:
        network = ipaddress.IPv4Network(f'{_forced_subnet}.0/24', strict=False)
    else:
        # Try all private interfaces, pick first 192.168/10./172.16 found
        local_ip = None
        try:
            import netifaces  # optional
            for iface in netifaces.interfaces():
                addrs = netifaces.ifaddresses(iface).get(netifaces.AF_INET, [])
                for a in addrs:
                    ip = a.get('addr', '')
                    if any(ip.startswith(p) for p in ('192.168.', '10.', '172.')):
                        local_ip = ip
                        break
                if local_ip:
                    break
        except ImportError:
            pass
        if not local_ip:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.connect(('8.8.8.8', 80))
                local_ip = s.getsockname()[0]
                s.close()
            except Exception:
                log.warning('Cannot determine local IP')
                return []
        network = ipaddress.IPv4Network(f'{local_ip}/24', strict=False)
    hosts   = list(network.hosts())
    log.info(f'Subnet: {network}  ({len(hosts)} hosts, probing port 80 + 4028 concurrently)')

    miners = []
    connector = aiohttp.TCPConnector(limit=60, ssl=False)
    async with aiohttp.ClientSession(connector=connector) as session:
        # Scan in batches of 30 to avoid overwhelming home routers
        batch = 30
        for i in range(0, len(hosts), batch):
            tasks = [check_host(session, str(h)) for h in hosts[i:i+batch]]
            for result in await asyncio.gather(*tasks, return_exceptions=True):
                if isinstance(result, dict):
                    miners.append(result)
                    log.info(f'  ✅ Found: {result["model"]:30s}  {result["ip"]}:{result["port"]}  ({result["protocol"]})')

    log.info(f'Discovery done — {len(miners)} miner(s) found')
    return miners


# ── Command forwarding ────────────────────────────────────────────────────────

async def forward_command(cmd: dict) -> dict:
    ip, port = cmd.get('miner_ip'), cmd.get('miner_port', 80)
    method   = cmd.get('method', 'GET').upper()
    path     = cmd.get('path', '/api/system/info')
    body     = cmd.get('body')
    req_id   = cmd.get('request_id', '')
    protocol = cmd.get('protocol', 'esp_miner')

    # cgminer TCP commands
    if port == 4028 or protocol == 'cgminer_tcp':
        cgcmd = path.lstrip('/').replace('/', ',') or 'summary'
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(ip, port), timeout=8)
            writer.write(json.dumps({'command': cgcmd}).encode() + b'\n')
            await writer.drain()
            buf = b''
            try:
                while True:
                    chunk = await asyncio.wait_for(reader.read(8192), timeout=5)
                    if not chunk:
                        break
                    buf += chunk
            except asyncio.TimeoutError:
                pass
            writer.close()
            raw = buf.decode('utf-8', errors='ignore').rstrip('\x00')
            return {'type': 'response', 'request_id': req_id,
                    'status': 200, 'data': json.loads(raw) if raw else {}}
        except Exception as e:
            return {'type': 'response', 'request_id': req_id, 'status': 0, 'error': str(e)}

    # HTTP commands (ESP-Miner, Avalon HTTP, etc.)
    url = f'http://{ip}:{port}{path}'
    try:
        async with aiohttp.ClientSession() as session:
            kw = {'timeout': aiohttp.ClientTimeout(total=10)}
            if body:
                kw['json'] = body
                kw['headers'] = {'Content-Type': 'application/json'}
            async with session.request(method, url, **kw) as r:
                try:
                    data = await r.json(content_type=None)
                except Exception:
                    data = {'raw': await r.text()}
                return {'type': 'response', 'request_id': req_id, 'status': r.status, 'data': data}
    except Exception as e:
        return {'type': 'response', 'request_id': req_id, 'status': 0, 'error': str(e)}


# ── Relay bridge loop ─────────────────────────────────────────────────────────

def _relay_sequence(primary_url: str) -> list[str]:
    urls = [primary_url]
    for relay_url in RELAY_URLS:
        if relay_url not in urls:
            urls.append(relay_url)
    return urls


async def run_bridge(key: str, relay_url: str):
    await check_for_update()
    updater = asyncio.create_task(update_loop())
    # Use SSL without cert verification so WSS works without browser-style handshake
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    miners = await discover_miners()
    relay_urls = _relay_sequence(relay_url)
    active_relay = relay_url
    primary_failures = 0
    reconnect_attempt = 0
    last_primary_try = 0.0

    try:
        while True:
            if active_relay != relay_url and time.monotonic() - last_primary_try >= PRIMARY_RETRY_EVERY:
                active_relay = relay_url
                last_primary_try = time.monotonic()
                log.info(f'Retrying primary relay → {active_relay}')

            ws_url = f'{active_relay}/relay/bridge/{key}'
            ws_extra = {'ssl': ssl_ctx} if ws_url.startswith('wss://') else {}
            log.info(f'Connecting → {ws_url}')
            try:
                async with websockets.connect(ws_url, ping_interval=20, ping_timeout=10, open_timeout=10, **ws_extra) as ws:
                    log.info('✅ Bridge connected — sending hello and miner list to app…')
                    await ws.send(json.dumps({
                        'type': 'bridge_hello',
                        'version': BRIDGE_VERSION,
                        'capabilities': BRIDGE_CAPABILITIES,
                    }))
                    await ws.send(json.dumps({'type': 'miners', 'miners': miners}))
                    reconnect_attempt = 0
                    if active_relay == relay_url:
                        primary_failures = 0

                    async def rediscover_loop():
                        nonlocal miners
                        while True:
                            await asyncio.sleep(REDISCOVER_EVERY)
                            miners = await discover_miners()
                            try:
                                await ws.send(json.dumps({'type': 'miners', 'miners': miners}))
                            except Exception:
                                break

                    task = asyncio.create_task(rediscover_loop())
                    try:
                        async for raw in ws:
                            try:
                                msg = json.loads(raw)
                            except Exception:
                                continue
                            t = msg.get('type')
                            if t == 'command':
                                log.info(f'→ {msg.get("method","?")} {msg.get("path","?")} @ {msg.get("miner_ip","?")}')
                                resp = await forward_command(msg)
                                await ws.send(json.dumps(resp))
                            elif t == 'ping':
                                await ws.send(json.dumps({'type': 'pong'}))
                            elif t == 'rediscover':
                                miners = await discover_miners()
                                await ws.send(json.dumps({'type': 'miners', 'miners': miners}))
                    finally:
                        task.cancel()
            except websockets.exceptions.ConnectionClosed as e:
                log.warning(f'Connection closed: {e}')
            except Exception as e:
                log.error(f'Error: {e}')

            if active_relay == relay_url:
                primary_failures += 1
                if primary_failures >= 3 and len(relay_urls) > 1:
                    active_relay = relay_urls[1]
                    last_primary_try = time.monotonic()
                    log.warning(f'Primary relay failed {primary_failures} times; switching to fallback → {active_relay}')
            delay = RECONNECT_DELAYS[min(reconnect_attempt, len(RECONNECT_DELAYS) - 1)]
            reconnect_attempt += 1
            log.info(f'Retry in {delay}s')
            await asyncio.sleep(delay)
    finally:
        updater.cancel()


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description='Kratos Link — bridge your home miners to the Kratos app',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 kratos_link.py --generate-key
  python3 kratos_link.py --key mykey123
        """)
    parser.add_argument('--key',           help='Access key (paste into Kratos → Remote Access)')
    parser.add_argument('--relay',         default=RELAY_URL, help=f'Relay URL (default: {RELAY_URL})')
    parser.add_argument('--generate-key',  action='store_true', help='Generate and print a new key')
    parser.add_argument('--subnet',        default=None, help='Force subnet prefix e.g. 192.168.8')
    args = parser.parse_args()

    if args.generate_key:
        key = secrets.token_urlsafe(12)
        print(f"""
╔══════════════════════════════════════════╗
║         KRATOS LINK — NEW KEY            ║
╚══════════════════════════════════════════╝

  🔑  Your key:  {key}

  1. Open Kratos app → Settings → Remote Access
  2. Paste this key and tap Connect
  3. Then run:

     python3 kratos_link.py --key {key}

""")
        return

    if not args.key:
        print('\nError: --key required.\n')
        print('  Generate a key:  python3 kratos_link.py --generate-key')
        print('  Then run:        python3 kratos_link.py --key <your-key>\n')
        sys.exit(1)

    print(f"""
╔══════════════════════════════════════════╗
║         KRATOS LINK  v1.4                ║
╚══════════════════════════════════════════╝
  Key:   {args.key}
  Relay: {args.relay}

  Scanning your network for miners…
  (Leave this window open while using remote access)

  Press Ctrl+C to stop
""")
    global _forced_subnet
    _forced_subnet = args.subnet
    try:
        asyncio.run(run_bridge(args.key, args.relay))
    except KeyboardInterrupt:
        print('\nKratos Link stopped.')

if __name__ == '__main__':
    main()
