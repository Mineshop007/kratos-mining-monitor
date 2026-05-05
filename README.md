# Kratos — Multi-Coin Mining Monitor & Control

[![License: MIT](https://img.shields.io/badge/License-MIT-00E676.svg)](LICENSE)
[![Platform: iOS · Android](https://img.shields.io/badge/Platform-iOS%20%C2%B7%20Android-00E676.svg)](#)
[![Built with Flutter](https://img.shields.io/badge/Flutter-3.41-00E676.svg)](https://flutter.dev)
[![Discord](https://img.shields.io/badge/Discord-Mineshop-5865F2.svg)](https://discord.gg/yWtYegkDJw)

> **Forge your fleet. Mine like a god.**
> Live mining monitor for BitAxe · NerdQ · Avalon · Antminer · Whatsminer · Goldshell · Lucky Miner. With Klaw the honey badger.

🌐 **Landing:** [kratos.mineshop.eu](https://kratos.mineshop.eu/)
📱 **App Store:** [apps.apple.com/app/id6762138440](https://apps.apple.com/app/id6762138440)
🤖 **Google Play:** *coming soon*

![Klaw mascot](https://kratos.mineshop.eu/klaw.png)

---

## What is it

A free, no-ads, no-tracking mining monitor for solo and pool miners. Cross-platform Flutter app talking directly to your miners' local APIs (ESP-Miner HTTP, cgminer TCP) — no cloud middleman, no telemetry, no IAPs.

**Real data only** is a hard invariant. Every numeric on screen is sourced from the miner's own API, a public blockchain explorer, or CoinGecko. We never invent values; missing data shows as a dash.

## Supported devices

| Family       | Notes                                       |
|--------------|---------------------------------------------|
| BitAxe       | Gamma · Ultra · GT (ESP-Miner HTTP)         |
| NerdQaxe++   | NerdAxe firmware                            |
| NerdOctaxe   | NerdAxe firmware                            |
| Avalon       | Nano · Mini · Q (cgminer TCP)               |
| Lucky Miner  | All models (ESP-Miner-compatible)           |
| Braiins / LuxOS | cgminer-compatible API                   |
| Antminer     | Bitmain — cgminer TCP                       |
| Whatsminer   | MicroBT — cgminer TCP                       |
| Goldshell    | All models — cgminer + web fallback         |

## Features

- **Volt** electro-green design language with Klaw the honey badger mascot
- **5-tab navigation:** Volt overview · Miners · Pools · Chat · Settings
- **Universal Best-Diff Tracker** with persistent per-miner records and milestone celebrations
- **Multi-coin** — BTC, LTC/DOGE, KAS, ALPH, CKB out of the box
- **LAN auto-discovery** via mDNS + subnet sweep + cgminer probe (~10 s)
- **Haptic feedback** on every accepted share, with intensity control
- **Falling-block celebration** on block-found events
- **Circuit Monitor** — group miners by breaker, real-time load %, alarm before trip
- **Energy Report CSV** export with kWh + cost + revenue
- **Health Score** per miner from real telemetry
- **Live Discord chat** bridged into the app (10 channels)
- **In-app FAQ** written for actual home miners
- **Pool-agnostic** — bring your own pool. Mineshop Solo Pool offered as a one-tap option, never default.

## Architecture

```
┌────────────────────────┐         ┌──────────────────────────┐
│   Kratos Flutter app   │ ◄────► │  Local miner APIs         │
│  (iOS · Android)       │         │  (ESP-Miner HTTP, cgminer)│
└────────────────────────┘         └──────────────────────────┘
            │
            │ HTTPS + WSS
            ▼
┌────────────────────────────────────────────────────────────┐
│  kratos.mineshop.eu                                        │
│   ├─ static landing (Volt + Klaw + 3D hero)                │
│   └─ /kratos/chat/  → kratos-chat-bridge (Python aiohttp)  │
└────────────────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────────┐
│  Discord Gateway (discord.py)                              │
│   ├─ #hangout · #bitaxe · #nerdq-octaxe · #avalon          │
│   ├─ #big-miners · #overclocking · #pools                  │
│   └─ #block-feed (read-only) · #help · #off-peak-heating   │
└────────────────────────────────────────────────────────────┘
```

The chat bridge service is self-contained at the same repo path under `server/` (Python 3.12 + aiohttp + discord.py, ~360 LOC). It is the only piece that requires server-side hosting; everything else runs entirely on-device.

## Build

```bash
git clone https://github.com/Mineshop007/kratos-mining-monitor.git
cd kratos-mining-monitor
flutter pub get
flutter run                                    # debug on connected device
flutter build ipa --release                    # iOS release
flutter build appbundle --release              # Android release
```

Tested with Flutter 3.41.x. Requires Xcode 16+ for iOS builds.

## Project layout

```
lib/
  main.dart                  # entry, theme + provider wiring
  theme/
    volt_theme.dart          # Volt palette + theme registry
  screens/
    home_screen.dart         # Volt overview + tile hub + 5-tab navigation
    miners_screen.dart       # Fleet view (list / grid)
    pools_screen.dart        # Best-diff hero + per-miner ranked list
    chat_screen.dart         # Discord-bridged in-app chat
    settings_screen.dart     # Theme picker, kWh, integrations
    discover_screen.dart     # LAN auto-discovery (mDNS + ping sweep)
    circuit_monitor_screen.dart  # Per-breaker load monitor
    faq_screen.dart          # In-app FAQ
    miner_detail_screen.dart # Per-miner detail + OC controls
    add_miner_screen.dart    # Manual miner add
    pool_editor_screen.dart  # Stratum URL / worker editor
    oc_screen.dart           # Voltage / frequency tuning
  services/
    miner_store.dart         # Fleet state + polling timers
    esp_miner_api.dart       # BitAxe / NerdAxe HTTP client
    cgminer_api.dart         # cgminer TCP client
    avalon_api.dart          # Avalon-specific cgminer extensions
    btc_price.dart           # Live BTC price
    coin_price_service.dart  # CoinGecko multi-coin
    notification_service.dart # Local notifications
    haptic_service.dart      # Per-platform haptics
    chat_service.dart        # Bridge client (REST + WebSocket)
    theme_service.dart       # Theme persistence
    best_diff_tracker.dart   # Per-miner all-time records
    circuit_service.dart     # Circuit definitions + load snapshots
    energy_report.dart       # CSV export
    health_score.dart        # Composite health metric
    lan_discovery.dart       # mDNS + subnet probe
  models/
    miner.dart               # Miner + MinerStats + MinerType
    coin.dart                # Coin + MiningAlgo
  widgets/
    miner_card.dart          # Fleet card (list + grid)
    miner_icon.dart          # Per-device 3D extruded glyph
    fleet_summary_bar.dart
    sparkline.dart
    klaw.dart                # Mascot + empty state + splash
    falling_block.dart       # Block-found celebration overlay
    health_badge.dart
    kratos_logo.dart

server/
  kratos_chat_bridge.py      # Discord bridge service (aiohttp + discord.py)
  channels.json              # In-app slug → Discord channel id map
  requirements.txt
  kratos-chat-bridge.service # systemd unit
```

## Contributing

PRs welcome. Discord (`#bug-reports`, `#install-help`) is the fastest path. Please:

- Run `flutter analyze` (zero errors, zero warnings before merge).
- Run `flutter test` (currently 13 tests; add to `test/widget_test.dart`).
- Honor the **no-fake-data invariant** — every number on screen must be traceable to a real source.

## Privacy

- All fleet data lives on-device (no cloud database).
- Outbound traffic limited to: your miners (LAN), CoinGecko (price), public blockchain explorers (block height/difficulty), `kratos.mineshop.eu` (chat bridge if you opt in).
- No analytics. No crash reporters. No third-party SDKs harvesting telemetry.
- Chat token is a 24-byte random; it is not linked to any account.

## Built by

[Mineshop](https://mineshop.eu) · Mining Hardware Limited · EU.
We sell the gear that powers it. The app is free because the hardware funds it.

## License

MIT — see [LICENSE](LICENSE).
