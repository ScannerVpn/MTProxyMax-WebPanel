#!/usr/bin/env python3
"""
MTProxyMax Web Panel — Lightweight REST API + Static Server

Based on MTProxyMax by SamNet Technologies
Original: https://github.com/SamNet-dev/MTProxyMax

Copyright (c) 2026 ScannerVpn
License: MIT
"""
import http.server
import json
import os
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path

INSTALL_DIR = os.environ.get("INSTALL_DIR", "/opt/mtproxymax")
MTMAX = os.path.join(INSTALL_DIR, "mtproxymax")
PORTAL_WWW = os.path.join(INSTALL_DIR, "webpanel", "www")
SETTINGS_FILE = os.path.join(INSTALL_DIR, "settings.conf")
SECRETS_FILE = os.path.join(INSTALL_DIR, "secrets.conf")
STATS_DIR = os.path.join(INSTALL_DIR, "relay_stats")

# Simple token auth
AUTH_TOKEN = os.environ.get("MTPANEL_TOKEN", "")


def run_cmd(cmd, timeout=15):
    """Run a shell command and return stdout."""
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, env={**os.environ, "LC_ALL": "C"}
        )
        return r.stdout.strip(), r.returncode
    except subprocess.TimeoutExpired:
        return "Command timed out", 1
    except Exception as e:
        return str(e), 1


def load_settings():
    """Parse settings.conf into dict."""
    settings = {}
    if not os.path.isfile(SETTINGS_FILE):
        return settings
    with open(SETTINGS_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                val = val.strip().strip("'\"")
                settings[key.strip()] = val
    return settings


def load_secrets():
    """Parse secrets.conf into list of dicts."""
    secrets = []
    if not os.path.isfile(SECRETS_FILE):
        return secrets
    with open(SECRETS_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) >= 8:
                secrets.append({
                    "label": parts[0],
                    "secret": parts[1],
                    "created": parts[2],
                    "enabled": parts[3],
                    "max_conns": parts[4],
                    "max_ips": parts[5],
                    "quota": parts[6],
                    "expires": parts[7],
                    "notes": parts[8] if len(parts) > 8 else "",
                    "ad_tag": parts[9] if len(parts) > 9 else "",
                })
    return secrets


def load_upstreams():
    """Parse upstreams.conf into list of dicts."""
    upstreams = []
    fpath = os.path.join(INSTALL_DIR, "upstreams.conf")
    if not os.path.isfile(fpath):
        return upstreams
    with open(fpath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) >= 8:
                upstreams.append({
                    "name": parts[0], "type": parts[1],
                    "addr": parts[2], "user": parts[3],
                    "pass": parts[4], "weight": parts[5],
                    "iface": parts[6], "enabled": parts[7],
                })
    return upstreams


def get_proxy_status():
    """Check Docker container status."""
    out, rc = run_cmd("docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^mtproxymax$' && echo running || echo stopped")
    return out.strip()


def get_traffic_stats():
    """Get cumulative traffic from stats files."""
    stats = {"bytes_in": 0, "bytes_out": 0, "connections": 0}
    tf = os.path.join(STATS_DIR, "cumulative_traffic")
    if os.path.isfile(tf):
        with open(tf) as f:
            line = f.read().strip()
            if "|" in line:
                parts = line.split("|")
                try:
                    stats["bytes_in"] = int(parts[0])
                    stats["bytes_out"] = int(parts[1])
                except (ValueError, IndexError):
                    pass
    # Try live connections
    out, _ = run_cmd("ss -tn state established 2>/dev/null | grep -c ':443 ' || echo 0")
    try:
        stats["connections"] = int(out.strip())
    except ValueError:
        pass
    return stats


def get_per_user_traffic():
    """Get per-user cumulative traffic."""
    result = {}
    tf = os.path.join(STATS_DIR, "user_traffic")
    if os.path.isfile(tf):
        with open(tf) as f:
            for line in f:
                line = line.strip()
                if "|" in line:
                    parts = line.split("|")
                    if len(parts) >= 3:
                        try:
                            result[parts[0]] = {
                                "bytes_in": int(parts[1]),
                                "bytes_out": int(parts[2]),
                            }
                        except (ValueError, IndexError):
                            pass
    return result


def get_system_stats():
    """Get CPU/RAM/disk stats."""
    stats = {}
    # CPU usage
    out, _ = run_cmd("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | head -1")
    try:
        stats["cpu_percent"] = float(out)
    except (ValueError, TypeError):
        stats["cpu_percent"] = 0.0

    # RAM
    out, _ = run_cmd("free -m | awk '/Mem:/{printf \"%d %d %d\", $2, $3, $7}'")
    parts = out.split()
    if len(parts) >= 3:
        try:
            stats["ram_total_mb"] = int(parts[0])
            stats["ram_used_mb"] = int(parts[1])
            stats["ram_available_mb"] = int(parts[2])
            stats["ram_percent"] = round((int(parts[1]) / int(parts[0])) * 100, 1) if int(parts[0]) > 0 else 0
        except (ValueError, IndexError):
            stats["ram_total_mb"] = 0
            stats["ram_used_mb"] = 0
            stats["ram_available_mb"] = 0
            stats["ram_percent"] = 0
    else:
        stats["ram_total_mb"] = 0
        stats["ram_used_mb"] = 0
        stats["ram_available_mb"] = 0
        stats["ram_percent"] = 0

    # Disk
    out, _ = run_cmd("df -BM / | awk 'NR==2{printf \"%d %d %d\", $2, $3, $4}'")
    parts = out.split()
    if len(parts) >= 3:
        try:
            stats["disk_total_mb"] = int(parts[0])
            stats["disk_used_mb"] = int(parts[1])
            stats["disk_free_mb"] = int(parts[2])
            stats["disk_percent"] = round((int(parts[1]) / int(parts[0])) * 100, 1) if int(parts[0]) > 0 else 0
        except (ValueError, IndexError):
            stats["disk_total_mb"] = 0
            stats["disk_used_mb"] = 0
            stats["disk_free_mb"] = 0
            stats["disk_percent"] = 0
    else:
        stats["disk_total_mb"] = 0
        stats["disk_used_mb"] = 0
        stats["disk_free_mb"] = 0
        stats["disk_percent"] = 0

    return stats


def get_uptime():
    """Get container uptime in seconds."""
    out, _ = run_cmd(
        "docker inspect --format '{{.State.StartedAt}}' mtproxymax 2>/dev/null"
    )
    if out and "T" in out:
        try:
            from datetime import datetime, timezone
            started = datetime.fromisoformat(out.replace("Z", "+00:00"))
            return int((datetime.now(timezone.utc) - started).total_seconds())
        except Exception:
            pass
    return 0


def get_container_logs(lines=50):
    """Get recent Docker container logs."""
    out, _ = run_cmd(f"docker logs --tail {lines} mtproxymax 2>&1")
    return out


def handle_api(path, method, body):
    """Route API requests."""
    data = {}

    # ── Dashboard ──
    if path == "/api/dashboard":
        settings = load_settings()
        secrets = load_secrets()
        user_traffic = get_per_user_traffic()
        traffic = get_traffic_stats()
        sys_stats = get_system_stats()
        active = sum(1 for s in secrets if s["enabled"] == "true")
        disabled = len(secrets) - active
        data = {
            "status": get_proxy_status(),
            "uptime": get_uptime(),
            "port": settings.get("PROXY_PORT", "443"),
            "domain": settings.get("PROXY_DOMAIN", "cloudflare.com"),
            "engine_version": "telemt 3.x",
            "traffic": traffic,
            "secrets": {"active": active, "disabled": disabled, "total": len(secrets)},
            "system": sys_stats,
            "concurrency": settings.get("PROXY_CONCURRENCY", "8192"),
        }

    # ── Secrets ──
    elif path == "/api/secrets" and method == "GET":
        secrets = load_secrets()
        user_traffic = get_per_user_traffic()
        for s in secrets:
            ut = user_traffic.get(s["label"], {"bytes_in": 0, "bytes_out": 0})
            s["traffic_in"] = ut["bytes_in"]
            s["traffic_out"] = ut["bytes_out"]
        data = {"secrets": secrets}

    elif path == "/api/secrets" and method == "POST":
        label = body.get("label", "")
        if not label:
            return {"error": "Label is required"}, 400
        out, rc = run_cmd(f"{MTMAX} secret add {label}", timeout=10)
        if rc != 0:
            return {"error": out}, 400
        # Parse link from output
        link = ""
        for line in out.split("\n"):
            if "tg://proxy" in line:
                link = line.strip()
                break
        data = {"success": True, "message": out, "link": link}

    elif path.startswith("/api/secrets/") and method == "DELETE":
        label = path.split("/")[-1]
        out, rc = run_cmd(f"{MTMAX} secret remove {label}", timeout=10)
        if rc != 0 and "not found" not in out.lower():
            return {"error": out}, 400
        data = {"success": True, "message": f"Secret '{label}' removed"}

    elif path.startswith("/api/secrets/") and path.endswith("/toggle") and method == "POST":
        label = path.split("/")[3]
        # Read current state to decide enable/disable
        secrets = load_secrets()
        current_enabled = None
        for s in secrets:
            if s["label"] == label:
                current_enabled = s["enabled"]
                break
        if current_enabled is None:
            return {"error": f"Secret '{label}' not found"}, 404
        action = "disable" if current_enabled == "true" else "enable"
        out, rc = run_cmd(f"{MTMAX} secret {action} {label}", timeout=10)
        data = {"success": True, "message": out}

    elif path.startswith("/api/secrets/") and path.endswith("/limits") and method == "POST":
        label = path.split("/")[3]
        max_conns = body.get("max_conns", "")
        max_ips = body.get("max_ips", "")
        quota = body.get("quota", "")
        expires = body.get("expires", "")
        cmd = f"{MTMAX} secret setlimits {label}"
        if max_conns:
            cmd += f" {max_conns}"
        else:
            cmd += " 0"
        if max_ips:
            cmd += f" {max_ips}"
        else:
            cmd += " 0"
        if quota:
            cmd += f" {quota}"
        else:
            cmd += " 0"
        if expires:
            cmd += f" {expires}"
        else:
            cmd += " 0"
        out, rc = run_cmd(cmd, timeout=10)
        data = {"success": True, "message": out}

    elif path.startswith("/api/secrets/") and path.endswith("/rotate") and method == "POST":
        label = path.split("/")[3]
        out, rc = run_cmd(f"{MTMAX} secret rotate {label}", timeout=10)
        link = ""
        for line in out.split("\n"):
            if "tg://proxy" in line:
                link = line.strip()
                break
        data = {"success": True, "message": out, "link": link}

    elif path.startswith("/api/secrets/") and path.endswith("/link") and method == "GET":
        label = path.split("/")[3]
        out, rc = run_cmd(f"{MTMAX} secret link {label}", timeout=10)
        data = {"link": out}

    # ── Proxy Control ──
    elif path == "/api/proxy/start" and method == "POST":
        out, rc = run_cmd(f"{MTMAX} start", timeout=30)
        data = {"success": rc == 0, "message": out}

    elif path == "/api/proxy/stop" and method == "POST":
        out, rc = run_cmd(f"{MTMAX} stop", timeout=15)
        data = {"success": rc == 0, "message": out}

    elif path == "/api/proxy/restart" and method == "POST":
        out, rc = run_cmd(f"{MTMAX} restart", timeout=30)
        data = {"success": rc == 0, "message": out}

    elif path == "/api/proxy/logs":
        logs = get_container_logs(100)
        data = {"logs": logs}

    # ── Settings ──
    elif path == "/api/settings" and method == "GET":
        data = {"settings": load_settings()}

    elif path == "/api/settings" and method == "POST":
        # Update settings directly in settings.conf
        settings = load_settings()
        for key, val in body.items():
            safe_key = key.upper()
            settings[safe_key] = str(val)
        # Write back settings.conf
        try:
            lines = ["# MTProxyMax Settings — Web Panel Updated",
                     "# Generated: by Web Panel"]
            for k, v in settings.items():
                lines.append(f"{k}='{v}'")
            tmp = SETTINGS_FILE + ".tmp"
            with open(tmp, "w") as f:
                f.write("\n".join(lines) + "\n")
            import shutil
            shutil.move(tmp, SETTINGS_FILE)
            os.chmod(SETTINGS_FILE, 0o600)
            data = {"success": True, "message": "Settings updated"}
        except Exception as e:
            data = {"error": str(e)}, 500

    # ── Upstreams ──
    elif path == "/api/upstreams" and method == "GET":
        data = {"upstreams": load_upstreams()}

    elif path == "/api/upstreams" and method == "POST":
        name = body.get("name", "")
        stype = body.get("type", "direct")
        addr = body.get("addr", "")
        user = body.get("user", "")
        pw = body.get("pass", "")
        weight = body.get("weight", "10")
        out, rc = run_cmd(
            f"{MTMAX} upstream add {name} {stype} {addr} {user} {pw} {weight}", timeout=10
        )
        data = {"success": rc == 0, "message": out}

    elif path.startswith("/api/upstreams/") and method == "DELETE":
        name = path.split("/")[-1]
        out, rc = run_cmd(f"{MTMAX} upstream remove {name}", timeout=10)
        data = {"success": True, "message": out}

    # ── Traffic ──
    elif path == "/api/traffic":
        user_traffic = get_per_user_traffic()
        secrets = load_secrets()
        traffic_list = []
        for s in secrets:
            ut = user_traffic.get(s["label"], {"bytes_in": 0, "bytes_out": 0})
            traffic_list.append({
                "label": s["label"],
                "enabled": s["enabled"],
                "bytes_in": ut["bytes_in"],
                "bytes_out": ut["bytes_out"],
                "total": ut["bytes_in"] + ut["bytes_out"],
            })
        traffic_list.sort(key=lambda x: x["total"], reverse=True)
        data = {"traffic": traffic_list, "global": get_traffic_stats()}

    # ── Health ──
    elif path == "/api/health":
        out, rc = run_cmd(f"{MTMAX} status 2>&1", timeout=10)
        data = {"health": out, "healthy": rc == 0}

    # ── Install / Actions ──
    elif path == "/api/action" and method == "POST":
        action = body.get("action", "")
        args = body.get("args", "")
        allowed = [
            "doctor", "health_check", "dpi-inspect", "net-grade",
            "bbr", "shield", "syn-shield", "cover-shield", "tcp-fastpath",
            "cpu-tune", "ram-tune", "socket-boost", "tcp-boost", "tcp-clean",
            "tls-pad", "honeypot", "auto-heal", "lockdown", "maintenance",
            "geoblock", "ban", "unban",
        ]
        # Split action for commands like "bbr on"
        action_parts = action.split()
        base_action = action_parts[0] if action_parts else ""
        if base_action in allowed or base_action in ["set", "info", "config", "uptime"]:
            cmd = f"{MTMAX} {action}"
            if args:
                cmd += f" {args}"
            out, rc = run_cmd(cmd, timeout=20)
            data = {"success": rc == 0, "message": out}
        else:
            return {"error": f"Unknown action: {action}"}, 400

    else:
        return {"error": "Not found"}, 404

    return data, 200


class PanelHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler with API routing."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PORTAL_WWW, **kwargs)

    def log_message(self, format, *args):
        pass  # Suppress request logs

    def _check_auth(self):
        if not AUTH_TOKEN:
            return True
        token = self.headers.get("X-Auth-Token", "")
        if token == AUTH_TOKEN:
            return True
        auth_header = self.headers.get("Authorization", "")
        if auth_header.startswith("Bearer ") and auth_header[7:] == AUTH_TOKEN:
            return True
        return False

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path.startswith("/api/"):
            if not self._check_auth():
                self._send_json({"error": "Unauthorized"}, 401)
                return
            body, status = handle_api(path, "GET", {})
            self._send_json(body, status)
        else:
            # Serve static files
            if path == "/":
                self.path = "/index.html"
            super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        content_len = int(self.headers.get("Content-Length", 0))
        body = {}
        if content_len > 0:
            raw = self.rfile.read(content_len)
            try:
                body = json.loads(raw)
            except json.JSONDecodeError:
                body = {}

        result, status = handle_api(path, "POST", body)
        self._send_json(result, status)

    def do_DELETE(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if not self._check_auth():
            self._send_json({"error": "Unauthorized"}, 401)
            return

        result, status = handle_api(path, "DELETE", {})
        self._send_json(result, status)

    def _send_json(self, data, status=200):
        if isinstance(data, tuple):
            data, status = data
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Auth-Token, Authorization")
        self.end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8888
    host = sys.argv[2] if len(sys.argv) > 2 else "0.0.0.0"

    if not os.path.isdir(PORTAL_WWW):
        print(f"ERROR: Web panel directory not found: {PORTAL_WWW}")
        sys.exit(1)

    if not os.path.isfile(MTMAX):
        print(f"ERROR: mtproxymax not found at {MTMAX}")
        sys.exit(1)

    server = http.server.HTTPServer((host, port), PanelHandler)
    print(f"MTProxyMax Web Panel running on http://{host}:{port}")
    if AUTH_TOKEN:
        print(f"Authentication: enabled (token required)")
    else:
        print(f"Authentication: disabled (set MTPANEL_TOKEN for security)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
