#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  MTProxyMax + Web Panel — One-Line Installer
#
#  Based on MTProxyMax by SamNet Technologies
#  Original: https://github.com/SamNet-dev/MTProxyMax
#
#  Web Panel by ScannerVpn
#  https://github.com/ScannerVpn/MTProxyMax-WebPanel
#
#  License: MIT
# ═══════════════════════════════════════════════════════════════
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/mtproxymax"
WEBPANEL_DIR="${INSTALL_DIR}/webpanel"
WEBPANEL_REPO="https://github.com/ScannerVpn/MTProxyMax-WebPanel.git"
MTMAX_REPO="https://github.com/SamNet-dev/MTProxyMax.git"

log_info()    { echo -e "  ${CYAN}[i]${NC} $1"; }
log_success() { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "  ${RED}[✗]${NC} $1" >&2; }

# Check root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    echo -e "  ${YELLOW}Try: sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ScannerVpn/MTProxyMax-WebPanel/main/install.sh)\"${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║   MTProxyMax + Web Panel Installer v1.0.0    ║"
echo "  ║   SamNet Technologies + ScannerVpn           ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Step 1: Install MTProxyMax if not installed ──
if [ ! -f "${INSTALL_DIR}/mtproxymax" ]; then
    log_info "MTProxyMax not found. Installing MTProxyMax first..."
    echo ""

    # Install dependencies
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq curl git docker.io python3 2>/dev/null || true
    elif command -v yum &>/dev/null; then
        yum install -y -q curl git docker python3 2>/dev/null || true
    fi

    # Install Docker if not present
    if ! command -v docker &>/dev/null; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh 2>/dev/null
        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
    fi

    # Clone and install MTProxyMax
    log_info "Downloading MTProxyMax..."
    TMPDIR=$(mktemp -d)
    git clone --depth 1 "$MTMAX_REPO" "$TMPDIR/mtproxymax" 2>/dev/null

    if [ -f "$TMPDIR/mtproxymax/mtproxymax.sh" ]; then
        mkdir -p "$INSTALL_DIR"
        cp "$TMPDIR/mtproxymax/mtproxymax.sh" "${INSTALL_DIR}/mtproxymax"
        chmod +x "${INSTALL_DIR}/mtproxymax"
        ln -sf "${INSTALL_DIR}/mtproxymax" /usr/local/bin/mtproxymax 2>/dev/null || true
        log_success "MTProxyMax installed"
    else
        log_error "Failed to download MTProxyMax"
        rm -rf "$TMPDIR"
        exit 1
    fi
    rm -rf "$TMPDIR"

    # Run MTProxyMax install if settings don't exist
    if [ ! -f "${INSTALL_DIR}/settings.conf" ]; then
        log_info "Running MTProxyMax initial setup..."
        "${INSTALL_DIR}/mtproxymax" install 2>/dev/null || true
    fi
else
    log_success "MTProxyMax already installed"
fi

# ── Step 2: Install Web Panel ──
echo ""
log_info "Installing Web Panel..."

# Create webpanel directory structure
mkdir -p "${WEBPANEL_DIR}/www/static"

# Try to download from GitHub
TMPDIR=$(mktemp -d)
if git clone --depth 1 "$WEBPANEL_REPO" "$TMPDIR/webpanel-repo" 2>/dev/null; then
    # Copy server files
    if [ -d "$TMPDIR/webpanel-repo/server" ]; then
        cp -r "$TMPDIR/webpanel-repo/server/"* "${WEBPANEL_DIR}/" 2>/dev/null || true
    elif [ -f "$TMPDIR/webpanel-repo/server.py" ]; then
        cp "$TMPDIR/webpanel-repo/server.py" "${WEBPANEL_DIR}/server.py"
    fi

    # Copy web files
    if [ -d "$TMPDIR/webpanel-repo/www" ]; then
        cp -r "$TMPDIR/webpanel-repo/www/"* "${WEBPANEL_DIR}/www/" 2>/dev/null || true
    elif [ -d "$TMPDIR/webpanel-repo/webpanel/www" ]; then
        cp -r "$TMPDIR/webpanel-repo/webpanel/www/"* "${WEBPANEL_DIR}/www/" 2>/dev/null || true
    fi

    log_success "Web Panel downloaded from GitHub"
else
    log_warn "GitHub download failed, generating files locally..."
    _generate_webpanel_files
fi
rm -rf "$TMPDIR"

# Verify files exist
if [ ! -f "${WEBPANEL_DIR}/server.py" ]; then
    log_error "server.py not found, generating locally..."
    _generate_webpanel_files
fi

chmod +x "${WEBPANEL_DIR}/server.py" 2>/dev/null || true

# ── Step 3: Generate auth token ──
WEBPANEL_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)
WEBPANEL_PORT=8888

# Save web panel settings
cat >> "${INSTALL_DIR}/settings.conf" << EOF

# Web Panel
WEBPANEL_ENABLED='true'
WEBPANEL_PORT='${WEBPANEL_PORT}'
WEBPANEL_TOKEN='${WEBPANEL_TOKEN}'
EOF

# ── Step 4: Create systemd service ──
cat > /etc/systemd/system/mtproxymax-webpanel.service << EOF
[Unit]
Description=MTProxyMax Web Panel
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=${WEBPANEL_DIR}
Environment=INSTALL_DIR=${INSTALL_DIR}
Environment=MTPANEL_TOKEN=${WEBPANEL_TOKEN}
ExecStart=$(command -v python3 || command -v python) ${WEBPANEL_DIR}/server.py ${WEBPANEL_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable mtproxymax-webpanel 2>/dev/null || true
systemctl start mtproxymax-webpanel 2>/dev/null || true

# ── Step 5: Get server IP ──
SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 3 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 3 https://icanhazip.com 2>/dev/null || \
            echo "YOUR_SERVER_IP")

# ── Summary ──
echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}   INSTALLATION COMPLETE${NC}"
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Web Panel URL:${NC}  ${CYAN}http://${SERVER_IP}:${WEBPANEL_PORT}${NC}"
echo -e "  ${BOLD}Auth Token:${NC}     ${YELLOW}${WEBPANEL_TOKEN}${NC}"
echo ""
echo -e "  ${DIM}Open the URL in your browser and enter the token to login${NC}"
echo ""
echo -e "  ${BOLD}Service Management:${NC}"
echo -e "  ${GREEN}systemctl start mtproxymax-webpanel${NC}    Start"
echo -e "  ${GREEN}systemctl stop mtproxymax-webpanel${NC}     Stop"
echo -e "  ${GREEN}systemctl restart mtproxymax-webpanel${NC}  Restart"
echo -e "  ${GREEN}systemctl status mtproxymax-webpanel${NC}   Status"
echo ""
echo -e "  ${BOLD}MTProxyMax:${NC}"
echo -e "  ${GREEN}mtproxymax${NC}                            Open TUI"
echo -e "  ${GREEN}mtproxymax status${NC}                     Check status"
echo ""

# ── Generate files function (fallback) ──
_generate_webpanel_files() {
    mkdir -p "${WEBPANEL_DIR}/www/static"

    cat > "${WEBPANEL_DIR}/server.py" << 'PYEOF'
#!/usr/bin/env python3
"""MTProxyMax Web Panel Server"""
import http.server, json, os, subprocess, sys, urllib.parse

INSTALL_DIR = os.environ.get("INSTALL_DIR", "/opt/mtproxymax")
MTMAX = os.path.join(INSTALL_DIR, "mtproxymax")
PORTAL_WWW = os.path.join(INSTALL_DIR, "webpanel", "www")
SETTINGS_FILE = os.path.join(INSTALL_DIR, "settings.conf")
SECRETS_FILE = os.path.join(INSTALL_DIR, "secrets.conf")
STATS_DIR = os.path.join(INSTALL_DIR, "relay_stats")
AUTH_TOKEN = os.environ.get("MTPANEL_TOKEN", "")

def run_cmd(cmd, timeout=15):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout, env={**os.environ, "LC_ALL": "C"})
        return r.stdout.strip(), r.returncode
    except: return "Error", 1

def load_settings():
    s = {}
    if not os.path.isfile(SETTINGS_FILE): return s
    with open(SETTINGS_FILE) as f:
        for l in f:
            l = l.strip()
            if not l or l.startswith("#") or "=" not in l: continue
            k, _, v = l.partition("="); s[k.strip()] = v.strip().strip("'\"")
    return s

def load_secrets():
    secs = []
    if not os.path.isfile(SECRETS_FILE): return secs
    with open(SECRETS_FILE) as f:
        for l in f:
            l = l.strip()
            if not l or l.startswith("#"): continue
            p = l.split("|")
            if len(p) >= 8: secs.append({"label":p[0],"secret":p[1],"created":p[2],"enabled":p[3],"max_conns":p[4],"max_ips":p[5],"quota":p[6],"expires":p[7],"notes":p[8] if len(p)>8 else "","ad_tag":p[9] if len(p)>9 else ""})
    return secs

def get_status():
    o, _ = run_cmd("docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^mtproxymax$' && echo running || echo stopped")
    return o.strip()

def get_traffic():
    s = {"bytes_in":0,"bytes_out":0,"connections":0}
    tf = os.path.join(STATS_DIR, "cumulative_traffic")
    if os.path.isfile(tf):
        with open(tf) as f:
            l = f.read().strip()
            if "|" in l:
                p = l.split("|")
                try: s["bytes_in"]=int(p[0]); s["bytes_out"]=int(p[1])
                except: pass
    o, _ = run_cmd("ss -tn state established 2>/dev/null | grep -c ':443 ' || echo 0")
    try: s["connections"]=int(o.strip())
    except: pass
    return s

def get_uptime():
    o, _ = run_cmd("docker inspect --format '{{.State.StartedAt}}' mtproxymax 2>/dev/null")
    if o and "T" in o:
        try:
            from datetime import datetime, timezone
            st = datetime.fromisoformat(o.replace("Z","+00:00"))
            return int((datetime.now(timezone.utc)-st).total_seconds())
        except: pass
    return 0

def handle_api(path, method, body):
    if path=="/api/dashboard":
        st=load_settings(); secs=load_secrets(); tr=get_traffic()
        return {"status":get_status(),"uptime":get_uptime(),"port":st.get("PROXY_PORT","443"),"domain":st.get("PROXY_DOMAIN","cloudflare.com"),"engine_version":"telemt 3.x","traffic":tr,"secrets":{"active":sum(1 for s in secs if s["enabled"]=="true"),"disabled":len(secs)-sum(1 for s in secs if s["enabled"]=="true"),"total":len(secrets)},"concurrency":st.get("PROXY_CONCURRENCY","8192")},200
    elif path=="/api/secrets" and method=="GET":
        secs=load_secrets(); return {"secrets":secs},200
    elif path=="/api/secrets" and method=="POST":
        label=body.get("label","")
        if not label: return {"error":"Label required"},400
        o,rc=run_cmd(f"{MTMAX} secret add {label}",10)
        link=""
        for l in o.split("\n"):
            if "tg://proxy" in l: link=l.strip(); break
        return {"success":True,"message":o,"link":link},200
    elif path.startswith("/api/secrets/") and method=="DELETE":
        label=path.split("/")[-1]; run_cmd(f"{MTMAX} secret remove {label}",10)
        return {"success":True},200
    elif path.startswith("/api/secrets/") and path.endswith("/toggle") and method=="POST":
        label=path.split("/")[3]
        secs=load_secrets()
        ce=None
        for s in secs:
            if s["label"]==label: ce=s["enabled"]; break
        if ce is None: return {"error":"Not found"},404
        act="disable" if ce=="true" else "enable"
        o,_=run_cmd(f"{MTMAX} secret {act} {label}",10)
        return {"success":True,"message":o},200
    elif path.startswith("/api/secrets/") and path.endswith("/limits") and method=="POST":
        label=path.split("/")[3]
        mc=body.get("max_conns","0"); mi=body.get("max_ips","0"); q=body.get("quota","0"); ex=body.get("expires","0")
        o,_=run_cmd(f"{MTMAX} secret setlimits {label} {mc} {mi} {q} {ex}",10)
        return {"success":True,"message":o},200
    elif path.startswith("/api/secrets/") and path.endswith("/rotate") and method=="POST":
        label=path.split("/")[3]; o,_=run_cmd(f"{MTMAX} secret rotate {label}",10)
        link=""
        for l in o.split("\n"):
            if "tg://proxy" in l: link=l.strip(); break
        return {"success":True,"message":o,"link":link},200
    elif path.startswith("/api/secrets/") and path.endswith("/link") and method=="GET":
        label=path.split("/")[3]; o,_=run_cmd(f"{MTMAX} secret link {label}",10)
        return {"link":o},200
    elif path=="/api/proxy/start" and method=="POST":
        o,rc=run_cmd(f"{MTMAX} start",30); return {"success":rc==0,"message":o},200
    elif path=="/api/proxy/stop" and method=="POST":
        o,rc=run_cmd(f"{MTMAX} stop",15); return {"success":rc==0,"message":o},200
    elif path=="/api/proxy/restart" and method=="POST":
        o,rc=run_cmd(f"{MTMAX} restart",30); return {"success":rc==0,"message":o},200
    elif path=="/api/proxy/logs":
        o,_=run_cmd("docker logs --tail 100 mtproxymax 2>&1"); return {"logs":o},200
    elif path=="/api/settings" and method=="GET":
        return {"settings":load_settings()},200
    elif path=="/api/settings" and method=="POST":
        st=load_settings()
        for k,v in body.items(): st[k.upper()]=str(v)
        try:
            lines=[f"{k}='{v}'" for k,v in st.items()]
            with open(SETTINGS_FILE+".tmp","w") as f: f.write("\n".join(lines)+"\n")
            import shutil; shutil.move(SETTINGS_FILE+".tmp",SETTINGS_FILE)
            os.chmod(SETTINGS_FILE,0o600)
            return {"success":True},200
        except Exception as e: return {"error":str(e)},500
    elif path=="/api/upstreams" and method=="GET":
        ups=[]
        uf=os.path.join(INSTALL_DIR,"upstreams.conf")
        if os.path.isfile(uf):
            with open(uf) as f:
                for l in f:
                    l=l.strip()
                    if not l or l.startswith("#"): continue
                    p=l.split("|")
                    if len(p)>=8: ups.append({"name":p[0],"type":p[1],"addr":p[2],"user":p[3],"pass":p[4],"weight":p[5],"iface":p[6],"enabled":p[7]})
        return {"upstreams":ups},200
    elif path=="/api/upstreams" and method=="POST":
        n=body.get("name",""); t=body.get("type","direct"); a=body.get("addr",""); u=body.get("user",""); pw=body.get("pass",""); w=body.get("weight","10")
        o,rc=run_cmd(f"{MTMAX} upstream add {n} {t} {a} {u} {pw} {w}",10)
        return {"success":rc==0,"message":o},200
    elif path.startswith("/api/upstreams/") and method=="DELETE":
        n=path.split("/")[-1]; run_cmd(f"{MTMAX} upstream remove {n}",10)
        return {"success":True},200
    elif path=="/api/traffic":
        ut={}; tf=os.path.join(STATS_DIR,"user_traffic")
        if os.path.isfile(tf):
            with open(tf) as f:
                for l in f:
                    l=l.strip()
                    if "|" in l:
                        p=l.split("|")
                        if len(p)>=3:
                            try: ut[p[0]]={"bytes_in":int(p[1]),"bytes_out":int(p[2])}
                            except: pass
        secs=load_secrets(); tl=[]
        for s in secs:
            u=ut.get(s["label"],{"bytes_in":0,"bytes_out":0})
            tl.append({"label":s["label"],"enabled":s["enabled"],"bytes_in":u["bytes_in"],"bytes_out":u["bytes_out"],"total":u["bytes_in"]+u["bytes_out"]})
        tl.sort(key=lambda x:x["total"],reverse=True)
        return {"traffic":tl,"global":get_traffic()},200
    elif path=="/api/health":
        o,rc=run_cmd(f"{MTMAX} status 2>&1",10); return {"health":o,"healthy":rc==0},200
    elif path=="/api/action" and method=="POST":
        action=body.get("action",""); ap=action.split(); ba=ap[0] if ap else ""
        allowed=["doctor","health_check","dpi-inspect","net-grade","bbr","shield","syn-shield","cover-shield","tcp-fastpath","cpu-tune","ram-tune","socket-boost","tcp-boost","tcp-clean","tls-pad","honeypot","auto-heal","lockdown","maintenance"]
        if ba in allowed or ba in ["set","info","config","uptime"]:
            o,rc=run_cmd(f"{MTMAX} {action}",20); return {"success":rc==0,"message":o},200
        return {"error":f"Unknown: {action}"},400
    return {"error":"Not found"},404

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self,*a,**k): super().__init__(*a,directory=PORTAL_WWW,**k)
    def log_message(self,f,*a): pass
    def _auth(self):
        if not AUTH_TOKEN: return True
        t=self.headers.get("X-Auth-Token","")
        if t==AUTH_TOKEN: return True
        ah=self.headers.get("Authorization","")
        if ah.startswith("Bearer ") and ah[7:]==AUTH_TOKEN: return True
        return False
    def do_GET(self):
        p=urllib.parse.urlparse(self.path).path
        if p.startswith("/api/"):
            if not self._auth(): self._j({"error":"Unauthorized"},401); return
            d,s=handle_api(p,"GET",{}); self._j(d,s)
        else:
            if p=="/": self.path="/index.html"
            super().do_GET()
    def do_POST(self):
        p=urllib.parse.urlparse(self.path).path
        if not self._auth(): self._j({"error":"Unauthorized"},401); return
        cl=int(self.headers.get("Content-Length",0)); b={}
        if cl>0:
            try: b=json.loads(self.rfile.read(cl))
            except: b={}
        d,s=handle_api(p,"POST",b); self._j(d,s)
    def do_DELETE(self):
        p=urllib.parse.urlparse(self.path).path
        if not self._auth(): self._j({"error":"Unauthorized"},401); return
        d,s=handle_api(p,"DELETE",{}); self._j(d,s)
    def _j(self,d,s=200):
        if isinstance(d,tuple): d,s=d
        b=json.dumps(d,ensure_ascii=False).encode()
        self.send_response(s); self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",len(b)); self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers(); self.wfile.write(b)
    def do_OPTIONS(self):
        self.send_response(200); self.send_header("Access-Control-Allow-Origin","*")
        self.send_header("Access-Control-Allow-Methods","GET,POST,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers","Content-Type,X-Auth-Token,Authorization")
        self.end_headers()

if __name__=="__main__":
    port=int(sys.argv[1]) if len(sys.argv)>1 else 8888
    if not os.path.isdir(PORTAL_WWW): print(f"ERROR: {PORTAL_WWW} not found"); sys.exit(1)
    s=http.server.HTTPServer(("0.0.0.0",port),H)
    print(f"MTProxyMax Web Panel on http://0.0.0.0:{port}")
    try: s.serve_forever()
    except KeyboardInterrupt: s.shutdown()
PYEOF

    # Generate minimal index.html
    cat > "${WEBPANEL_DIR}/www/index.html" << 'HTMLEOF'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>MTProxyMax Web Panel</title><link rel="stylesheet" href="static/style.css"></head><body><div id="app"><aside class="sidebar" id="sidebar"><div class="sidebar-header"><div class="logo"><span class="logo-icon">⚡</span><span class="logo-text">MTProxyMax</span></div></div><nav class="sidebar-nav"><a href="#" class="nav-item active" data-page="dashboard"><span>📊</span><span>Dashboard</span></a><a href="#" class="nav-item" data-page="secrets"><span>🔐</span><span>Secrets</span></a><a href="#" class="nav-item" data-page="traffic"><span>📈</span><span>Traffic</span></a><a href="#" class="nav-item" data-page="proxy"><span>⚙️</span><span>Proxy</span></a><a href="#" class="nav-item" data-page="upstreams"><span>🔗</span><span>Upstreams</span></a><a href="#" class="nav-item" data-page="settings"><span>🛠️</span><span>Settings</span></a><a href="#" class="nav-item" data-page="logs"><span>📋</span><span>Logs</span></a></nav></aside><main class="main-content"><header class="topbar"><button class="menu-toggle" id="menuToggle">☰</button><div class="topbar-title" id="pageTitle">Dashboard</div><div class="topbar-actions"><span class="status-badge" id="statusBadge">—</span><button class="btn btn-sm" onclick="refreshAll()">↻</button></div></header><div class="page-container"><div class="page active" id="page-dashboard"><div class="stats-grid"><div class="stat-card"><div class="stat-label">Status</div><div class="stat-value" id="dash-status">—</div></div><div class="stat-card"><div class="stat-label">Traffic In</div><div class="stat-value accent-cyan" id="dash-traffic-in">—</div></div><div class="stat-card"><div class="stat-label">Traffic Out</div><div class="stat-value accent-green" id="dash-traffic-out">—</div></div><div class="stat-card"><div class="stat-label">Connections</div><div class="stat-value accent-yellow" id="dash-connections">—</div></div></div><div class="card mt-4"><div class="card-header"><h3>Quick Actions</h3></div><div class="card-body"><div class="action-buttons"><button class="btn btn-success" onclick="proxyAction('start')">▶ Start</button><button class="btn btn-danger" onclick="proxyAction('stop')">■ Stop</button><button class="btn btn-warning" onclick="proxyAction('restart')">↻ Restart</button><button class="btn btn-info" onclick="runAction('doctor')">🩺 Doctor</button></div></div></div></div></div></main></div><div class="modal-overlay hidden" id="modalOverlay" onclick="closeModal()"><div class="modal" onclick="event.stopPropagation()"><div class="modal-header"><h3 id="modalTitle">Result</h3><button class="btn btn-ghost btn-sm" onclick="closeModal()">✕</button></div><div class="modal-body" id="modalBody"></div><div class="modal-footer"><button class="btn btn-primary" onclick="closeModal()">Close</button></div></div></div><script src="static/app.js"></script></body></html>
HTMLEOF

    cat > "${WEBPANEL_DIR}/www/static/style.css" << 'CSSEOF'
:root{--bg:#0a0e17;--bg-card:#111827;--bg-card-hover:#1a2332;--bg-sidebar:#0d1321;--bg-input:#1a2332;--border:#1e293b;--border-focus:#3b82f6;--text:#e2e8f0;--text-dim:#64748b;--text-muted:#475569;--accent:#3b82f6;--accent-hover:#2563eb;--cyan:#06b6d4;--green:#10b981;--yellow:#f59e0b;--red:#ef4444;--purple:#8b5cf6;--radius:12px;--radius-sm:8px;--shadow:0 4px 24px rgba(0,0,0,.3);--sidebar-width:240px;--topbar-height:56px;--transition:.2s ease}*{margin:0;padding:0;box-sizing:border-box}body{font-family:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);line-height:1.5;min-height:100vh}#app{display:flex;min-height:100vh}.sidebar{width:var(--sidebar-width);background:var(--bg-sidebar);border-right:1px solid var(--border);display:flex;flex-direction:column;position:fixed;top:0;left:0;height:100vh;z-index:100}.sidebar-header{padding:20px;border-bottom:1px solid var(--border)}.logo{display:flex;align-items:center;gap:10px}.logo-icon{font-size:24px}.logo-text{font-size:18px;font-weight:700}.sidebar-nav{flex:1;padding:12px 10px;overflow-y:auto}.nav-item{display:flex;align-items:center;gap:10px;padding:10px 14px;border-radius:var(--radius-sm);color:var(--text-dim);text-decoration:none;font-size:14px;font-weight:500;transition:all var(--transition);margin-bottom:2px}.nav-item:hover{background:var(--bg-card);color:var(--text)}.nav-item.active{background:rgba(59,130,246,.12);color:var(--accent)}.main-content{flex:1;margin-left:var(--sidebar-width);min-height:100vh;display:flex;flex-direction:column}.topbar{height:var(--topbar-height);background:var(--bg-sidebar);border-bottom:1px solid var(--border);display:flex;align-items:center;padding:0 24px;gap:16px;position:sticky;top:0;z-index:50}.menu-toggle{display:none;background:none;border:none;color:var(--text);font-size:20px;cursor:pointer}.topbar-title{font-size:16px;font-weight:600}.topbar-actions{margin-left:auto;display:flex;align-items:center;gap:12px}.status-badge{padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600}.status-badge.running{background:rgba(16,185,129,.15);color:var(--green)}.status-badge.stopped{background:rgba(239,68,68,.15);color:var(--red)}.page-container{padding:24px;flex:1}.page{display:none}.page.active{display:block}.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px}.stat-card{background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);padding:20px;transition:all var(--transition)}.stat-card:hover{border-color:var(--border-focus)}.stat-label{font-size:12px;font-weight:500;color:var(--text-dim);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px}.stat-value{font-size:28px;font-weight:700}.accent-cyan{color:var(--cyan)}.accent-green{color:var(--green)}.accent-yellow{color:var(--yellow)}.accent-purple{color:var(--purple)}.card{background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden}.mt-4{margin-top:16px}.card-header{padding:16px 20px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between}.card-header h3{font-size:15px;font-weight:600}.card-body{padding:20px}.btn{padding:8px 16px;border:1px solid var(--border);border-radius:var(--radius-sm);background:var(--bg-input);color:var(--text);font-size:13px;font-weight:500;cursor:pointer;transition:all var(--transition);display:inline-flex;align-items:center;gap:6px}.btn:hover{background:var(--bg-card-hover)}.btn-sm{padding:4px 10px;font-size:12px}.btn-primary{background:var(--accent);border-color:var(--accent);color:#fff}.btn-success{background:rgba(16,185,129,.15);border-color:var(--green);color:var(--green)}.btn-danger{background:rgba(239,68,68,.15);border-color:var(--red);color:var(--red)}.btn-warning{background:rgba(245,158,11,.15);border-color:var(--yellow);color:var(--yellow)}.btn-info{background:rgba(6,182,212,.15);border-color:var(--cyan);color:var(--cyan)}.btn-ghost{background:transparent;border-color:transparent;color:var(--text-dim)}.action-buttons{display:flex;flex-wrap:wrap;gap:8px}.hidden{display:none!important}.modal-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:1000;padding:20px}.modal{background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);width:100%;max-width:500px;max-height:80vh;overflow:hidden}.modal-header{padding:16px 20px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between}.modal-body{padding:20px;overflow-y:auto;max-height:60vh}.modal-footer{padding:12px 20px;border-top:1px solid var(--border);display:flex;justify-content:flex-end;gap:8px}.modal-body pre{background:var(--bg);padding:12px;border-radius:var(--radius-sm);font-family:monospace;font-size:12px;white-space:pre-wrap}@media(max-width:768px){.sidebar{transform:translateX(-100%)}.sidebar.open{transform:translateX(0)}.main-content{margin-left:0}.menu-toggle{display:block}.stats-grid{grid-template-columns:1fr 1fr}}
CSSEOF

    cat > "${WEBPANEL_DIR}/www/static/app.js" << 'JSEOF'
(function(){'use strict';const API='';let currentPage='dashboard';
async function api(p,o={}){try{const r=await fetch(API+p,{method:o.method||'GET',headers:{'Content-Type':'application/json'},body:o.body?JSON.stringify(o.body):undefined});return await r.json()}catch(e){return{error:e.message}}}
function fb(b){if(!b||b===0)return'0 B';const k=1024,s=['B','KB','MB','GB','TB'],i=Math.floor(Math.log(b)/Math.log(k));return parseFloat((b/Math.pow(k,i)).toFixed(2))+' '+s[i]}
function fd(s){if(!s||s<1)return'—';const d=Math.floor(s/86400),h=Math.floor((s%86400)/3600),m=Math.floor((s%3600)/60);return d>0?d+'d '+h+'h '+m+'m':h>0?h+'h '+m+'m':m>0?m+'m':Math.floor(s)+'s'}
function toast(m,t){const e=document.createElement('div');e.className='toast '+(t||'info');e.textContent=m;e.style.cssText='position:fixed;bottom:24px;right:24px;padding:12px 20px;border-radius:8px;font-size:13px;z-index:2000;background:'+(t==='error'?'#ef4444':t==='success'?'#10b981':'#3b82f6')+';color:#fff';document.body.appendChild(e);setTimeout(()=>e.remove(),3500)}
function showModal(t,c){document.getElementById('modalTitle').textContent=t;document.getElementById('modalBody').innerHTML=c;document.getElementById('modalOverlay').classList.remove('hidden')}
window.closeModal=function(){document.getElementById('modalOverlay').classList.add('hidden')};
document.querySelectorAll('.nav-item').forEach(i=>{i.addEventListener('click',function(e){e.preventDefault();navigateTo(this.dataset.page)})});
function navigateTo(p){currentPage=p;document.querySelectorAll('.nav-item').forEach(n=>n.classList.remove('active'));document.querySelector('.nav-item[data-page="'+p+'"]').classList.add('active');document.querySelectorAll('.page').forEach(pg=>pg.classList.remove('active'));const el=document.getElementById('page-'+p);if(el)el.classList.add('active');document.getElementById('pageTitle').textContent={dashboard:'Dashboard',secrets:'Secrets',traffic:'Traffic',proxy:'Proxy',upstreams:'Upstreams',settings:'Settings',logs:'Logs'}[p]||p;document.getElementById('sidebar').classList.remove('open');loadPageData(p)}
document.getElementById('menuToggle').addEventListener('click',()=>{document.getElementById('sidebar').classList.toggle('open')});
async function loadPageData(p){if(p==='dashboard')await loadDashboard();else if(p==='secrets')await loadSecrets();else if(p==='traffic')await loadTraffic();else if(p==='logs')await loadLogs()}
async function loadDashboard(){const d=await api('/api/dashboard');if(d.error)return;const r=d.status==='running';document.getElementById('dash-status').textContent=r?'Running':'Stopped';document.getElementById('dash-status').className='stat-value '+(r?'accent-green':'accent-red');document.getElementById('dash-traffic-in').textContent=fb(d.traffic.bytes_in);document.getElementById('dash-traffic-out').textContent=fb(d.traffic.bytes_out);document.getElementById('dash-connections').textContent=d.traffic.connections;const b=document.getElementById('statusBadge');b.textContent=r?'ONLINE':'OFFLINE';b.className='status-badge '+(r?'running':'stopped')}
async function loadSecrets(){const d=await api('/api/secrets');if(d.error)return;if(!d.secrets||!d.secrets.length){showModal('Secrets','<p>No secrets configured</p>');return}let h='<table style="width:100%;border-collapse:collapse;font-size:13px"><tr><th style="padding:8px;text-align:left;border-bottom:1px solid #1e293b">#</th><th style="padding:8px;text-align:left;border-bottom:1px solid #1e293b">Label</th><th style="padding:8px;text-align:left;border-bottom:1px solid #1e293b">Status</th><th style="padding:8px;text-align:left;border-bottom:1px solid #1e293b">Actions</th></tr>';d.secrets.forEach((s,i)=>{h+='<tr><td style="padding:8px;border-bottom:1px solid #1e293b">'+(i+1)+'</td><td style="padding:8px;border-bottom:1px solid #1e293b"><b>'+s.label+'</b></td><td style="padding:8px;border-bottom:1px solid #1e293b">'+(s.enabled==='true'?'<span style="color:#10b981">Active</span>':'<span style="color:#ef4444">Disabled</span>')+'</td><td style="padding:8px;border-bottom:1px solid #1e293b"><button class="btn btn-sm btn-info" onclick="showLink(\''+s.label+'\')">Link</button> <button class="btn btn-sm btn-warning" onclick="toggleSecret(\''+s.label+'\')">Toggle</button></td></tr>'});h+='</table>';showModal('Secrets ('+d.secrets.length+')',h)}
window.showLink=async function(l){const d=await api('/api/secrets/'+encodeURIComponent(l)+'/link');if(d.error){toast(d.error,'error');return}showModal('Link — '+l,'<pre style="word-break:break-all;background:#0a0e17;padding:12px;border-radius:8px;color:#06b6d4">'+d.link+'</pre>')}
window.toggleSecret=async function(l){const d=await api('/api/secrets/'+encodeURIComponent(l)+'/toggle',{method:'POST'});if(d.error)toast(d.error,'error');else{toast('Toggled','success');loadSecrets()}}
window.proxyAction=async function(a){toast('Sending '+a+'...','info');const d=await api('/api/proxy/'+a,{method:'POST'});if(d.error)toast(d.error,'error');else{toast(a+' done','success');setTimeout(loadDashboard,1500)}}
window.runAction=async function(a){toast('Running '+a+'...','info');const d=await api('/api/action',{method:'POST',body:{action:a}});if(d.error)toast(d.error,'error');else showModal('Result: '+a,'<pre>'+d.message+'</pre>')}
async function loadTraffic(){const d=await api('/api/traffic');if(d.error)return;showModal('Traffic','<p>Total In: '+fb(d.global.bytes_in)+' | Total Out: '+fb(d.global.bytes_out)+' | Connections: '+d.global.connections+'</p>')}
async function loadLogs(){const d=await api('/api/proxy/logs');if(d.error){toast(d.error,'error');return}showModal('Logs','<pre style="max-height:400px;overflow:auto;background:#0a0e17;padding:12px;border-radius:8px;font-size:11px">'+d.logs+'</pre>')}
window.refreshAll=function(){loadPageData(currentPage);toast('Refreshed','info')};
async function init(){await loadDashboard();setInterval(()=>{if(currentPage==='dashboard')loadDashboard()},10000)}
init()})();
JSEOF
}
