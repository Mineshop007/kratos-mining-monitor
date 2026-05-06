#!/usr/bin/env python3
"""
Kratos Link — Home Network Bridge
Run this on any PC/Mac/Pi on the same network as your miners.
It connects to the Kratos Relay and forwards commands to your miners.

Usage: python3 kratos_link.py --key YOUR_ACCESS_KEY
       python3 kratos_link.py --key YOUR_ACCESS_KEY --relay wss://kratos.mineshop.eu/relay

Download: https://kratos.mineshop.eu/link
"""

import asyncio
import json
import logging
import sys
import socket
import ipaddress
import argparse
import secrets
import time
from typing import Optional
import aiohttp
import websockets

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
)
log = logging.getLogger('kratos-link')

RELAY_URL = 'wss://kratos.mineshop.eu/relay'
DISCOVERY_PORTS = [80]  # ESP-Miner port
DISCOVERY_TIMEOUT = 1.5
RECONNECT_DELAY = 5


async def check_miner(session: aiohttp.ClientSession, ip: str) -> Optional[dict]:
    """Check if an IP hosts an ESP-Miner or cgminer device"""
    for port in DISCOVERY_PORTS:
        try:
            url = f'http://{ip}:{port}/api/system/info'
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=DISCOVERY_TIMEOUT)) as r:
                if r.status == 200:
                    data = await r.json(content_type=None)
                    return {
                        'ip': ip,
                        'port': port,
                        'type': 'esp_miner',
                        'model': data.get('boardVersion', data.get('deviceModel', 'Unknown')),
                        'hashrate': data.get('hashRate', 0),
                        'firmware': data.get('version', ''),
                    }
        except Exception:
            pass
    return None


async def discover_miners() -> list:
    """Scan local subnet for ESP-Miner devices"""
    log.info('Discovering miners on local network...')
    
    # Get local IP to determine subnet
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        log.warning('Could not determine local IP')
        return []
    
    # Scan /24 subnet
    network = ipaddress.IPv4Network(f'{local_ip}/24', strict=False)
    log.info(f'Scanning {network} ({len(list(network.hosts()))} hosts)...')
    
    miners = []
    connector = aiohttp.TCPConnector(limit=50)
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = [check_miner(session, str(host)) for host in network.hosts()]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        for r in results:
            if isinstance(r, dict):
                miners.append(r)
                log.info(f'  Found: {r["model"]} at {r["ip"]}:{r["port"]}')
    
    log.info(f'Discovery complete: {len(miners)} miners found')
    return miners


async def forward_command(cmd: dict, miners: list) -> dict:
    """Forward a command from app to the target miner"""
    target_ip = cmd.get('miner_ip')
    target_port = cmd.get('miner_port', 80)
    method = cmd.get('method', 'GET').upper()
    path = cmd.get('path', '/api/system/info')
    body = cmd.get('body')
    req_id = cmd.get('request_id', '')
    
    url = f'http://{target_ip}:{target_port}{path}'
    
    try:
        async with aiohttp.ClientSession() as session:
            kwargs = {
                'timeout': aiohttp.ClientTimeout(total=10),
                'headers': {'Content-Type': 'application/json'} if body else {},
            }
            if body:
                kwargs['json'] = body
            
            async with session.request(method, url, **kwargs) as r:
                try:
                    data = await r.json(content_type=None)
                except Exception:
                    data = {'raw': await r.text()}
                
                return {
                    'type': 'response',
                    'request_id': req_id,
                    'status': r.status,
                    'data': data,
                }
    except Exception as e:
        return {
            'type': 'response',
            'request_id': req_id,
            'status': 0,
            'error': str(e),
        }


async def run_bridge(key: str, relay_url: str):
    """Main bridge loop — connects to relay and handles commands"""
    ws_url = f'{relay_url}/bridge/{key}'
    miners = []
    
    # Initial discovery
    miners = await discover_miners()
    
    while True:
        log.info(f'Connecting to relay at {ws_url}')
        try:
            async with websockets.connect(
                ws_url,
                ping_interval=20,
                ping_timeout=10,
                open_timeout=10,
            ) as ws:
                log.info('✅ Connected to Kratos Relay')
                
                # Announce miners immediately
                await ws.send(json.dumps({
                    'type': 'miners',
                    'miners': miners,
                }))
                
                # Periodic re-discovery task
                async def rediscover():
                    nonlocal miners
                    while True:
                        await asyncio.sleep(120)  # re-scan every 2 min
                        miners = await discover_miners()
                        try:
                            await ws.send(json.dumps({'type': 'miners', 'miners': miners}))
                        except Exception:
                            break
                
                rediscover_task = asyncio.create_task(rediscover())
                
                try:
                    async for raw in ws:
                        try:
                            msg = json.loads(raw)
                        except Exception:
                            continue
                        
                        msg_type = msg.get('type')
                        
                        if msg_type == 'command':
                            log.info(f'Command: {msg.get("method","?")} {msg.get("path","?")} → {msg.get("miner_ip","?")}')
                            response = await forward_command(msg, miners)
                            await ws.send(json.dumps(response))
                        
                        elif msg_type == 'ping':
                            await ws.send(json.dumps({'type': 'pong'}))
                        
                        elif msg_type == 'rediscover':
                            miners = await discover_miners()
                            await ws.send(json.dumps({'type': 'miners', 'miners': miners}))
                
                finally:
                    rediscover_task.cancel()
        
        except websockets.exceptions.ConnectionClosed as e:
            log.warning(f'Connection closed: {e}. Reconnecting in {RECONNECT_DELAY}s...')
        except Exception as e:
            log.error(f'Error: {e}. Reconnecting in {RECONNECT_DELAY}s...')
        
        await asyncio.sleep(RECONNECT_DELAY)


def generate_key() -> str:
    return secrets.token_urlsafe(16)


def main():
    parser = argparse.ArgumentParser(
        description='Kratos Link — Bridge your miners to the Kratos app remotely',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 kratos_link.py --key mykey123
  python3 kratos_link.py --generate-key
  python3 kratos_link.py --key mykey123 --relay wss://kratos.mineshop.eu/relay
        """
    )
    parser.add_argument('--key', help='Access key (get from Kratos app → Settings → Remote Access)')
    parser.add_argument('--relay', default=RELAY_URL, help=f'Relay server URL (default: {RELAY_URL})')
    parser.add_argument('--generate-key', action='store_true', help='Generate a new random key')
    args = parser.parse_args()
    
    if args.generate_key:
        key = generate_key()
        print(f'\n🔑 Your Kratos Link key: {key}')
        print(f'   Enter this in Kratos → Settings → Remote Access → Add Key')
        print(f'   Then run: python3 kratos_link.py --key {key}\n')
        return
    
    if not args.key:
        print('Error: --key required. Get it from Kratos app → Settings → Remote Access')
        print('       Or generate one: python3 kratos_link.py --generate-key')
        sys.exit(1)
    
    print(f'''
╔══════════════════════════════════════╗
║         KRATOS LINK v1.0             ║
║   Remote Mining Monitor & Control   ║
╚══════════════════════════════════════╝
Key:   {args.key[:8]}...
Relay: {args.relay}

Press Ctrl+C to stop
''')
    
    try:
        asyncio.run(run_bridge(args.key, args.relay))
    except KeyboardInterrupt:
        print('\nKratos Link stopped.')


if __name__ == '__main__':
    main()
