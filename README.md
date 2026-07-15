# MTProxyMax Web Panel

A modern, dark-themed web management panel for [MTProxyMax](https://github.com/SamNet-dev/MTProxyMax) — The Ultimate Telegram MTProto Proxy Manager.

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-brightgreen" alt="Version"/>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License"/>
  <img src="https://img.shields.io/badge/python-3.6+-yellow" alt="Python"/>
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey" alt="Platform"/>
</p>

---

## Features

- **Dashboard** — Real-time status, traffic, CPU/RAM/Disk monitoring, quick actions
- **Secret Management** — Add, remove, enable/disable, rotate, edit limits, generate proxy links
- **Traffic Monitor** — Per-user traffic breakdown with visual progress bars
- **Proxy Control** — Start/stop/restart, diagnostics, security shields (BBR, Shield, SYN, Lockdown)
- **Upstream Routing** — Add/remove proxy chains (SOCKS5/SOCKS4/Direct)
- **Settings** — Port, domain, concurrency, MSS, ad-tag, cert length, masking, SNI action
- **Container Logs** — Live log viewer
- **Token Authentication** — Secure access with auto-generated tokens
- **Auto-Refresh** — Dashboard updates every 10 seconds
- **Responsive Design** — Works on desktop and mobile browsers

## Screenshot

Dark glassmorphism theme with sidebar navigation, stat cards, progress bars, and modal dialogs.

## Installation

### Prerequisites

- Python 3.6+
- MTProxyMax installed at `/opt/mtproxymax`
- Docker (for proxy management)

### Quick Install

```bash
# Clone this repository
git clone https://github.com/ScannerVpn/MTProxyMax-WebPanel.git /opt/mtproxymax/webpanel

# Or copy files to MTProxyMax directory
cp -r webpanel /opt/mtproxymax/
```

### Via MTProxyMax CLI

```bash
# If integrated into MTProxyMax
mtproxymax webpanel install
mtproxymax webpanel start
```

### Manual Start

```bash
cd /opt/mtproxymax/webpanel
python3 server.py 8888
```

## Usage

Once started, access the web panel at:

```
http://<server-ip>:8888
```

If token authentication is enabled, enter the token displayed in the server startup logs.

### CLI Commands

```bash
mtproxymax webpanel install     # Install web panel
mtproxymax webpanel start       # Start web panel
mtproxymax webpanel stop        # Stop web panel
mtproxymax webpanel restart     # Restart web panel
mtproxymax webpanel port 8888   # Change port
mtproxymax webpanel token       # Generate new token
mtproxymax webpanel status      # Show status
```

### TUI Menu

Run `mtproxymax` and select `[w] Web Panel` from the main menu.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dashboard` | Dashboard data (status, traffic, system stats) |
| GET | `/api/secrets` | List all secrets with traffic |
| POST | `/api/secrets` | Create new secret |
| DELETE | `/api/secrets/{label}` | Remove secret |
| POST | `/api/secrets/{label}/toggle` | Enable/disable secret |
| POST | `/api/secrets/{label}/limits` | Update user limits |
| POST | `/api/secrets/{label}/rotate` | Rotate secret key |
| GET | `/api/secrets/{label}/link` | Get proxy link |
| POST | `/api/proxy/start` | Start proxy |
| POST | `/api/proxy/stop` | Stop proxy |
| POST | `/api/proxy/restart` | Restart proxy |
| GET | `/api/proxy/logs` | Get container logs |
| GET | `/api/settings` | Get settings |
| POST | `/api/settings` | Update settings |
| GET | `/api/upstreams` | List upstreams |
| POST | `/api/upstreams` | Add upstream |
| DELETE | `/api/upstreams/{name}` | Remove upstream |
| GET | `/api/traffic` | Traffic breakdown |
| GET | `/api/health` | Health check |
| POST | `/api/action` | Run diagnostic actions |

## Architecture

```
webpanel/
├── server.py              # Python REST API server (stdlib only, no dependencies)
├── www/
│   ├── index.html         # SPA frontend
│   └── static/
│       ├── style.css      # Dark glassmorphism theme
│       └── app.js         # Frontend application logic
```

## Security

- Token-based authentication (auto-generated on install)
- Tokens passed via `X-Auth-Token` header or `Authorization: Bearer` header
- All API endpoints require authentication when token is set
- Static files (HTML/CSS/JS) served without authentication
- Settings file permissions: `600` (owner read/write only)

## License

MIT License

## Credits

This project is a web management panel for **MTProxyMax**:

- **MTProxyMax** — [https://github.com/SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax)
- **Author:** SamNet Technologies
- **Engine:** telemt 3.x (Rust+Tokio)

Built with:
- Python 3 (stdlib http.server)
- Vanilla JavaScript (no frameworks)
- CSS3 (custom properties, grid, flexbox)

---

**Based on MTProxyMax by SamNet Technologies** — [https://github.com/SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax)
