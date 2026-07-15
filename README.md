# MTProxyMax Web Panel

A modern, dark-themed web management panel for [MTProxyMax](https://github.com/SamNet-dev/MTProxyMax) — The Ultimate Telegram MTProto Proxy Manager.

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-brightgreen" alt="Version"/>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License"/>
  <img src="https://img.shields.io/badge/python-3.6+-yellow" alt="Python"/>
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey" alt="Platform"/>
</p>

---

## One-Line Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/ScannerVpn/MTProxyMax-WebPanel/main/install.sh)"
```

This will:
1. Install MTProxyMax (if not already installed)
2. Install Docker (if needed)
3. Install the Web Panel
4. Start the service automatically
5. Show you the URL and auth token

---

## Features

- **Dashboard** — Real-time status, traffic, connections monitoring
- **Secret Management** — Add, remove, enable/disable, rotate, edit limits, generate proxy links
- **Traffic Monitor** — Per-user traffic breakdown with visual progress bars
- **Proxy Control** — Start/stop/restart, diagnostics, security shields
- **Upstream Routing** — Add/remove proxy chains (SOCKS5/SOCKS4/Direct)
- **Settings** — Port, domain, concurrency, MSS, ad-tag, cert length, masking
- **Container Logs** — Live log viewer
- **Token Authentication** — Secure access with auto-generated tokens
- **Auto-Refresh** — Dashboard updates every 10 seconds
- **Responsive Design** — Works on desktop and mobile browsers
- **Dark Glassmorphism Theme** — Beautiful modern UI

## Manual Install

### Prerequisites

- Python 3.6+
- Docker
- MTProxyMax installed

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/ScannerVpn/MTProxyMax-WebPanel.git /opt/mtproxymax/webpanel

# 2. Install dependencies (if needed)
apt-get install -y python3

# 3. Start the web panel
cd /opt/mtproxymax/webpanel/server
python3 server.py 8888
```

## Usage

Once started, access the web panel at:

```
http://<server-ip>:8888
```

Enter the auth token displayed in the server startup logs.

### CLI Commands

```bash
# MTProxyMax commands
mtproxymax                      # Open TUI
mtproxymax status               # Check status
mtproxymax secret add <label>   # Add user

# Web Panel service
systemctl start mtproxymax-webpanel
systemctl stop mtproxymax-webpanel
systemctl restart mtproxymax-webpanel
systemctl status mtproxymax-webpanel
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dashboard` | Dashboard data |
| GET | `/api/secrets` | List secrets |
| POST | `/api/secrets` | Create secret |
| DELETE | `/api/secrets/{label}` | Remove secret |
| POST | `/api/secrets/{label}/toggle` | Toggle secret |
| POST | `/api/secrets/{label}/limits` | Update limits |
| POST | `/api/secrets/{label}/rotate` | Rotate secret |
| GET | `/api/secrets/{label}/link` | Get proxy link |
| POST | `/api/proxy/start` | Start proxy |
| POST | `/api/proxy/stop` | Stop proxy |
| POST | `/api/proxy/restart` | Restart proxy |
| GET | `/api/proxy/logs` | Get logs |
| GET | `/api/settings` | Get settings |
| POST | `/api/settings` | Update settings |
| GET | `/api/upstreams` | List upstreams |
| POST | `/api/upstreams` | Add upstream |
| DELETE | `/api/upstreams/{name}` | Remove upstream |
| GET | `/api/traffic` | Traffic data |
| GET | `/api/health` | Health check |
| POST | `/api/action` | Run action |

## Credits

This project is built on top of:

- **MTProxyMax** — [https://github.com/SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax)
- **Author:** SamNet Technologies
- **Engine:** telemt 3.x (Rust+Tokio)

Built with:
- Python 3 (stdlib http.server - zero dependencies)
- Vanilla JavaScript (no frameworks)
- CSS3 (custom properties, grid, flexbox)

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**Based on MTProxyMax by SamNet Technologies** — [https://github.com/SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax)
