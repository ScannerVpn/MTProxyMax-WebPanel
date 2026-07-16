/* MTProxyMax Web Panel — Frontend Application */
(function(){
'use strict';

// ── Token Management ──
let AUTH_TOKEN = localStorage.getItem('mtp_auth_token') || '';

function getStoredToken() { return localStorage.getItem('mtp_auth_token') || ''; }
function setStoredToken(t) { localStorage.setItem('mtp_auth_token', t); AUTH_TOKEN = t; }
function clearStoredToken() { localStorage.removeItem('mtp_auth_token'); AUTH_TOKEN = ''; }

// ── Login / Logout ──
window.doLogin = function(e) {
    e.preventDefault();
    var token = document.getElementById('tokenInput').value.trim();
    if (!token) { alert('Enter token'); return; }
    setStoredToken(token);
    // Test the token
    api('/api/dashboard').then(function(d) {
        if (d.error && d.error === 'Unauthorized') {
            clearStoredToken();
            alert('Invalid token');
            return;
        }
        document.getElementById('loginScreen').style.display = 'none';
        document.getElementById('app').style.display = 'flex';
        loadDashboard();
        startAutoRefresh();
    });
};

window.doLogout = function() {
    clearStoredToken();
    document.getElementById('app').style.display = 'none';
    document.getElementById('loginScreen').style.display = 'flex';
    document.getElementById('tokenInput').value = '';
};

// ── Check if already logged in ──
function checkAuth() {
    if (getStoredToken()) {
        api('/api/dashboard').then(function(d) {
            if (d.error && d.error === 'Unauthorized') {
                clearStoredToken();
                showLogin();
            } else {
                document.getElementById('loginScreen').style.display = 'none';
                document.getElementById('app').style.display = 'flex';
                loadDashboard();
                startAutoRefresh();
            }
        });
    } else {
        showLogin();
    }
}

function showLogin() {
    document.getElementById('loginScreen').style.display = 'flex';
    document.getElementById('app').style.display = 'none';
}

// ── API Helper ──
async function api(path, opts) {
    opts = opts || {};
    var headers = { 'Content-Type': 'application/json' };
    var token = getStoredToken();
    if (token) headers['X-Auth-Token'] = token;
    try {
        var resp = await fetch(path, {
            method: opts.method || 'GET',
            headers: headers,
            body: opts.body ? JSON.stringify(opts.body) : undefined
        });
        return await resp.json();
    } catch(e) {
        return { error: e.message };
    }
}

// ── Formatters ──
function fb(b) {
    if (!b || b === 0) return '0 B';
    var k = 1024, s = ['B','KB','MB','GB','TB'], i = Math.floor(Math.log(b)/Math.log(k));
    return parseFloat((b/Math.pow(k,i)).toFixed(2)) + ' ' + s[i];
}

function fd(s) {
    if (!s || s < 1) return '—';
    var d = Math.floor(s/86400), h = Math.floor((s%86400)/3600), m = Math.floor((s%3600)/60);
    return d > 0 ? d+'d '+h+'h '+m+'m' : h > 0 ? h+'h '+m+'m' : m > 0 ? m+'m' : Math.floor(s)+'s';
}

// ── Toast ──
function toast(msg, type) {
    var el = document.createElement('div');
    el.className = 'toast ' + (type || 'info');
    el.textContent = msg;
    el.style.cssText = 'position:fixed;bottom:24px;right:24px;padding:12px 20px;border-radius:8px;font-size:13px;z-index:2000;color:#fff;background:' + (type==='error'?'#ef4444':type==='success'?'#10b981':'#3b82f6');
    document.body.appendChild(el);
    setTimeout(function(){ el.remove(); }, 3500);
}

// ── Modal ──
function showModal(title, content) {
    document.getElementById('modalTitle').textContent = title;
    document.getElementById('modalBody').innerHTML = content;
    document.getElementById('modalOverlay').classList.remove('hidden');
}
window.closeModal = function() { document.getElementById('modalOverlay').classList.add('hidden'); };
window.closeLinkModal = function() { document.getElementById('linkModalOverlay').classList.add('hidden'); };
window.closeLimitsModal = function() { document.getElementById('limitsModalOverlay').classList.add('hidden'); };

// ── Navigation ──
var currentPage = 'dashboard';

document.querySelectorAll('.nav-item').forEach(function(item) {
    item.addEventListener('click', function(e) {
        e.preventDefault();
        navigateTo(this.dataset.page);
    });
});

function navigateTo(page) {
    currentPage = page;
    document.querySelectorAll('.nav-item').forEach(function(n) { n.classList.remove('active'); });
    var nav = document.querySelector('.nav-item[data-page="'+page+'"]');
    if (nav) nav.classList.add('active');
    document.querySelectorAll('.page').forEach(function(p) { p.classList.remove('active'); });
    var el = document.getElementById('page-' + page);
    if (el) el.classList.add('active');
    document.getElementById('pageTitle').textContent = {dashboard:'Dashboard',secrets:'Secrets',traffic:'Traffic',proxy:'Proxy Control',upstreams:'Upstreams',settings:'Settings',logs:'Logs'}[page] || page;
    document.getElementById('sidebar').classList.remove('open');
    loadPageData(page);
}

document.getElementById('menuToggle').addEventListener('click', function() {
    document.getElementById('sidebar').classList.toggle('open');
});

// ── Page Loaders ──
function loadPageData(page) {
    if (page === 'dashboard') loadDashboard();
    else if (page === 'secrets') loadSecrets();
    else if (page === 'traffic') loadTraffic();
    else if (page === 'proxy') loadProxyStatus();
    else if (page === 'upstreams') loadUpstreams();
    else if (page === 'settings') loadSettings();
    else if (page === 'logs') loadLogs();
}

// ── Dashboard ──
async function loadDashboard() {
    var d = await api('/api/dashboard');
    if (d.error) return;
    var r = d.status === 'running';
    document.getElementById('dash-status').textContent = r ? 'Running' : 'Stopped';
    document.getElementById('dash-status').className = 'stat-value ' + (r ? 'accent-green' : 'accent-red');
    document.getElementById('dash-uptime').textContent = 'Uptime: ' + fd(d.uptime);
    var badge = document.getElementById('statusBadge');
    badge.textContent = r ? 'ONLINE' : 'OFFLINE';
    badge.className = 'status-badge ' + (r ? 'running' : 'stopped');
    document.getElementById('dash-traffic-in').textContent = fb(d.traffic.bytes_in);
    document.getElementById('dash-traffic-out').textContent = fb(d.traffic.bytes_out);
    document.getElementById('dash-connections').textContent = d.traffic.connections;
    document.getElementById('dash-secrets').textContent = d.secrets.active + ' / ' + d.secrets.total;
    if (d.system) {
        var cpu = d.system.cpu_percent || 0;
        document.getElementById('dash-cpu').textContent = cpu.toFixed(1) + '%';
        var cb = document.getElementById('dash-cpu-bar'); cb.style.width = cpu + '%'; cb.className = 'progress-fill' + (cpu > 90 ? ' danger' : cpu > 70 ? ' warn' : '');
        var ram = d.system.ram_percent || 0;
        document.getElementById('dash-ram').textContent = ram.toFixed(1) + '% (' + d.system.ram_used_mb + '/' + d.system.ram_total_mb + ' MB)';
        var rb = document.getElementById('dash-ram-bar'); rb.style.width = ram + '%'; rb.className = 'progress-fill' + (ram > 90 ? ' danger' : ram > 70 ? ' warn' : '');
        var disk = d.system.disk_percent || 0;
        document.getElementById('dash-disk').textContent = disk.toFixed(1) + '%';
        var db = document.getElementById('dash-disk-bar'); db.style.width = disk + '%'; db.className = 'progress-fill' + (disk > 90 ? ' danger' : disk > 70 ? ' warn' : '');
    }
    document.getElementById('dash-port').textContent = d.port;
    document.getElementById('dash-domain').textContent = d.domain;
    document.getElementById('dash-engine').textContent = d.engine_version;
    document.getElementById('dash-concurrency').textContent = d.concurrency;
}

// ── Secrets ──
function esc(s) { var d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }

async function loadSecrets() {
    var d = await api('/api/secrets');
    if (d.error) return;
    var tb = document.getElementById('secrets-tbody');
    if (!d.secrets || d.secrets.length === 0) {
        tb.innerHTML = '<tr><td colspan="10" style="text-align:center;color:#64748b;padding:20px">No secrets configured</td></tr>';
        return;
    }
    tb.innerHTML = d.secrets.map(function(s, i) {
        var en = s.enabled === 'true';
        var q = parseInt(s.quota) || 0;
        var badge = en ? '<span class="badge active">Active</span>' : '<span class="badge disabled">Off</span>';
        var exp = (s.expires && s.expires !== '0') ? s.expires.split('T')[0] : 'Never';
        return '<tr><td>'+(i+1)+'</td><td><b>'+esc(s.label)+'</b></td><td>'+badge+'</td><td>'+(s.max_conns==='0'?'∞':s.max_conns)+'</td><td>'+(s.max_ips==='0'?'∞':s.max_ips)+'</td><td>'+(q===0?'∞':fb(q))+'</td><td>'+exp+'</td><td>'+fb(s.traffic_in||0)+'</td><td>'+fb(s.traffic_out||0)+'</td><td><div class="action-buttons"><button class="btn btn-sm btn-info" onclick="showLink(\''+esc(s.label)+'\')">🔗</button><button class="btn btn-sm btn-warning" onclick="showEditLimits(\''+esc(s.label)+'\',\''+s.max_conns+'\',\''+s.max_ips+'\',\''+s.quota+'\',\''+s.expires+'\')">⚙</button><button class="btn btn-sm '+(en?'btn-danger':'btn-success')+'" onclick="toggleSecret(\''+esc(s.label)+'\')">'+(en?'⏸':'▶')+'</button><button class="btn btn-sm btn-warning" onclick="rotateSecret(\''+esc(s.label)+'\')">🔄</button><button class="btn btn-sm btn-danger" onclick="deleteSecret(\''+esc(s.label)+'\')">✕</button></div></td></tr>';
    }).join('');
}

window.showAddSecret = function() { document.getElementById('add-secret-form').classList.remove('hidden'); document.getElementById('new-secret-label').focus(); };
window.hideAddSecret = function() { document.getElementById('add-secret-form').classList.add('hidden'); document.getElementById('new-secret-label').value = ''; };

window.addSecret = async function() {
    var label = document.getElementById('new-secret-label').value.trim();
    if (!label) { toast('Enter a label', 'error'); return; }
    var d = await api('/api/secrets', { method: 'POST', body: { label: label } });
    if (d.error) { toast(d.error, 'error'); return; }
    hideAddSecret();
    toast('Secret "' + label + '" created', 'success');
    loadSecrets();
    if (d.link) showLinkModal('New Secret Link', d.link);
};

window.deleteSecret = async function(label) {
    if (!confirm('Delete "' + label + '"?')) return;
    var d = await api('/api/secrets/' + encodeURIComponent(label), { method: 'DELETE' });
    if (d.error) { toast(d.error, 'error'); return; }
    toast('Deleted', 'success'); loadSecrets();
};

window.toggleSecret = async function(label) {
    var d = await api('/api/secrets/' + encodeURIComponent(label) + '/toggle', { method: 'POST' });
    if (d.error) { toast(d.error, 'error'); return; }
    toast('Toggled', 'success'); loadSecrets();
};

window.rotateSecret = async function(label) {
    if (!confirm('Rotate "' + label + '"? Old key stops working.')) return;
    var d = await api('/api/secrets/' + encodeURIComponent(label) + '/rotate', { method: 'POST' });
    if (d.error) { toast(d.error, 'error'); return; }
    toast('Rotated', 'success'); loadSecrets();
    if (d.link) showLinkModal('New Link', d.link);
};

window.showLink = async function(label) {
    var d = await api('/api/secrets/' + encodeURIComponent(label) + '/link');
    if (d.error) { toast(d.error, 'error'); return; }
    showLinkModal('Link — ' + label, d.link);
};

function showLinkModal(title, link) {
    document.getElementById('linkModalTitle').textContent = title;
    var body = document.getElementById('linkModalBody');
    body.innerHTML = '';
    if (link) {
        var lines = link.split('\n').filter(function(l) { return l.trim(); });
        lines.forEach(function(line) {
            var trimmed = line.trim();
            if (trimmed) {
                var div = document.createElement('div');
                div.className = 'link-box';
                div.style.cssText = 'background:#0a0e17;padding:12px;border-radius:8px;font-family:monospace;font-size:12px;word-break:break-all;margin-bottom:10px;border:1px solid #1e293b;color:#06b6d4;cursor:pointer';
                div.textContent = trimmed;
                div.onclick = function() { navigator.clipboard.writeText(trimmed).then(function(){ toast('Copied!','success'); }); };
                var lbl = document.createElement('div');
                lbl.style.cssText = 'font-size:11px;color:#64748b;margin-bottom:4px;font-weight:600';
                lbl.textContent = trimmed.includes('tg://proxy') ? 'Telegram Deep Link' : 'HTTPS Web Link';
                body.appendChild(lbl);
                body.appendChild(div);
            }
        });
    }
    document.getElementById('linkModalOverlay').classList.remove('hidden');
}

window.showEditLimits = function(label, conns, ips, quota, expires) {
    document.getElementById('limits-label').value = label;
    document.getElementById('limits-conns').value = conns === '0' ? '' : conns;
    document.getElementById('limits-ips').value = ips === '0' ? '' : ips;
    document.getElementById('limits-quota').value = quota === '0' ? '' : fb(parseInt(quota) || 0);
    document.getElementById('limits-expires').value = (!expires || expires === '0') ? '' : expires.split('T')[0];
    document.getElementById('limitsModalOverlay').classList.remove('hidden');
};

window.saveLimits = async function() {
    var label = document.getElementById('limits-label').value;
    var body = {
        max_conns: document.getElementById('limits-conns').value || '0',
        max_ips: document.getElementById('limits-ips').value || '0',
        quota: document.getElementById('limits-quota').value || '0',
        expires: document.getElementById('limits-expires').value || '0'
    };
    var d = await api('/api/secrets/' + encodeURIComponent(label) + '/limits', { method: 'POST', body: body });
    if (d.error) { toast(d.error, 'error'); return; }
    toast('Limits updated', 'success'); closeLimitsModal(); loadSecrets();
};

// ── Traffic ──
async function loadTraffic() {
    var d = await api('/api/traffic');
    if (d.error) return;
    document.getElementById('traffic-total-in').textContent = fb(d.global.bytes_in);
    document.getElementById('traffic-total-out').textContent = fb(d.global.bytes_out);
    document.getElementById('traffic-active-conns').textContent = d.global.connections;
    var tb = document.getElementById('traffic-tbody');
    if (!d.traffic || d.traffic.length === 0) {
        tb.innerHTML = '<tr><td colspan="6" style="text-align:center;color:#64748b;padding:20px">No traffic data</td></tr>';
        return;
    }
    var mx = Math.max.apply(null, d.traffic.map(function(t){ return t.total; }).concat([1]));
    tb.innerHTML = d.traffic.map(function(t) {
        var total = t.bytes_in + t.bytes_out;
        var pct = Math.min((total / mx) * 100, 100);
        return '<tr><td><b>'+esc(t.label)+'</b></td><td>'+(t.enabled==='true'?'<span class="badge active">On</span>':'<span class="badge disabled">Off</span>')+'</td><td>'+fb(t.bytes_in)+'</td><td>'+fb(t.bytes_out)+'</td><td>'+fb(total)+'</td><td><div class="traffic-bar"><div class="traffic-bar-fill" style="width:'+pct+'%"></div></div></td></tr>';
    }).join('');
}

// ── Proxy Control ──
async function loadProxyStatus() {
    var d = await api('/api/dashboard');
    if (d.error) return;
    var r = d.status === 'running';
    document.getElementById('proxy-status-display').textContent = r ? '● Running' : '○ Stopped';
    document.getElementById('proxy-status-display').className = 'stat-value ' + (r ? 'accent-green' : 'accent-red');
}

window.proxyAction = async function(action) {
    toast('Sending ' + action + '...', 'info');
    var d = await api('/api/proxy/' + action, { method: 'POST' });
    if (d.error) { toast('Error: ' + d.error, 'error'); return; }
    toast(action + ' completed', 'success');
    setTimeout(function() { loadDashboard(); loadProxyStatus(); }, 1500);
};

window.runAction = async function(action) {
    toast('Running ' + action + '...', 'info');
    var d = await api('/api/action', { method: 'POST', body: { action: action } });
    if (d.error) { toast('Error: ' + d.error, 'error'); return; }
    showModal('Result: ' + action, '<pre>' + (d.message || 'Done') + '</pre>');
};

// ── Upstreams ──
async function loadUpstreams() {
    var d = await api('/api/upstreams');
    if (d.error) return;
    var tb = document.getElementById('upstreams-tbody');
    if (!d.upstreams || d.upstreams.length === 0) {
        tb.innerHTML = '<tr><td colspan="6" style="text-align:center;color:#64748b;padding:20px">No upstreams</td></tr>';
        return;
    }
    tb.innerHTML = d.upstreams.map(function(u) {
        return '<tr><td><b>'+esc(u.name)+'</b></td><td>'+esc(u.type)+'</td><td>'+esc(u.addr||'—')+'</td><td>'+esc(u.weight)+'</td><td>'+(u.enabled==='true'?'<span class="badge active">On</span>':'<span class="badge disabled">Off</span>')+'</td><td><button class="btn btn-sm btn-danger" onclick="deleteUpstream(\''+esc(u.name)+'\')">✕</button></td></tr>';
    }).join('');
}

window.showAddUpstream = function() { document.getElementById('add-upstream-form').classList.remove('hidden'); };
window.hideAddUpstream = function() { document.getElementById('add-upstream-form').classList.add('hidden'); };

window.addUpstream = async function() {
    var body = {
        name: document.getElementById('up-name').value.trim(),
        type: document.getElementById('up-type').value,
        addr: document.getElementById('up-addr').value.trim(),
        user: document.getElementById('up-user').value.trim(),
        pass: document.getElementById('up-pass').value.trim(),
        weight: document.getElementById('up-weight').value.trim() || '10'
    };
    if (!body.name) { toast('Enter label', 'error'); return; }
    var d = await api('/api/upstreams', { method: 'POST', body: body });
    if (d.error) { toast(d.error, 'error'); return; }
    toast('Added', 'success'); hideAddUpstream(); loadUpstreams();
};

window.deleteUpstream = async function(name) {
    if (!confirm('Delete "' + name + '"?')) return;
    var d = await api('/api/upstreams/' + encodeURIComponent(name), { method: 'DELETE' });
    if (d.error) { toast(d.error, 'error'); return; }
    toast('Removed', 'success'); loadUpstreams();
};

// ── Settings ──
async function loadSettings() {
    var d = await api('/api/settings');
    if (d.error || !d.settings) return;
    var s = d.settings;
    document.getElementById('set-port').value = s.PROXY_PORT || '';
    document.getElementById('set-domain').value = s.PROXY_DOMAIN || '';
    document.getElementById('set-concurrency').value = s.PROXY_CONCURRENCY || '';
    document.getElementById('set-mss').value = s.CLIENT_MSS || '';
    document.getElementById('set-metrics-port').value = s.PROXY_METRICS_PORT || '';
    document.getElementById('set-adtag').value = s.AD_TAG || '';
    document.getElementById('set-cert-len').value = s.FAKE_CERT_LEN || '';
    document.getElementById('set-mask-host').value = s.MASKING_HOST || '';
    document.getElementById('set-mask-port').value = s.MASKING_PORT || '';
    document.getElementById('set-sni-action').value = s.UNKNOWN_SNI_ACTION || 'mask';
}

window.saveSettings = async function(e) {
    e.preventDefault();
    var body = {
        PROXY_PORT: document.getElementById('set-port').value,
        PROXY_DOMAIN: document.getElementById('set-domain').value,
        PROXY_CONCURRENCY: document.getElementById('set-concurrency').value,
        CLIENT_MSS: document.getElementById('set-mss').value,
        PROXY_METRICS_PORT: document.getElementById('set-metrics-port').value,
        AD_TAG: document.getElementById('set-adtag').value,
        FAKE_CERT_LEN: document.getElementById('set-cert-len').value,
        MASKING_HOST: document.getElementById('set-mask-host').value,
        MASKING_PORT: document.getElementById('set-mask-port').value,
        UNKNOWN_SNI_ACTION: document.getElementById('set-sni-action').value
    };
    var d = await api('/api/settings', { method: 'POST', body: body });
    if (d.error) { toast('Error: ' + d.error, 'error'); return; }
    toast('Saved', 'success');
};

// ── Logs ──
window.loadLogs = async function() {
    var d = await api('/api/proxy/logs');
    var el = document.getElementById('log-output');
    if (d.error) el.textContent = 'Error: ' + d.error;
    else { el.textContent = d.logs || 'No logs'; el.scrollTop = el.scrollHeight; }
};

// ── Auto Refresh ──
var refreshInterval = null;
function startAutoRefresh() {
    if (refreshInterval) clearInterval(refreshInterval);
    refreshInterval = setInterval(function() {
        if (currentPage === 'dashboard') loadDashboard();
    }, 10000);
}

window.refreshAll = function() { loadPageData(currentPage); toast('Refreshed', 'info'); };

// ── Init ──
checkAuth();

})();
