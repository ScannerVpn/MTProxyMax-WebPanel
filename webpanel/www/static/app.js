/* MTProxyMax Web Panel — Frontend Application */
(function() {
  'use strict';

  const API = '';  // Same origin
  let currentPage = 'dashboard';
  let refreshInterval = null;

  // ── API Helpers ──
  async function api(path, opts = {}) {
    try {
      const resp = await fetch(API + path, {
        method: opts.method || 'GET',
        headers: {
          'Content-Type': 'application/json',
          ...opts.headers,
        },
        body: opts.body ? JSON.stringify(opts.body) : undefined,
      });
      return await resp.json();
    } catch (e) {
      return { error: e.message };
    }
  }

  function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  function formatDuration(secs) {
    if (!secs || secs < 1) return '—';
    const d = Math.floor(secs / 86400);
    const h = Math.floor((secs % 86400) / 3600);
    const m = Math.floor((secs % 3600) / 60);
    if (d > 0) return d + 'd ' + h + 'h ' + m + 'm';
    if (h > 0) return h + 'h ' + m + 'm';
    if (m > 0) return m + 'm';
    return Math.floor(secs) + 's';
  }

  function toast(msg, type) {
    const el = document.createElement('div');
    el.className = 'toast ' + (type || 'info');
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 3500);
  }

  function showModal(title, content) {
    document.getElementById('modalTitle').textContent = title;
    document.getElementById('modalBody').innerHTML = content;
    document.getElementById('modalOverlay').classList.remove('hidden');
  }

  window.closeModal = function() {
    document.getElementById('modalOverlay').classList.add('hidden');
  };

  window.closeLinkModal = function() {
    document.getElementById('linkModalOverlay').classList.add('hidden');
  };

  window.closeLimitsModal = function() {
    document.getElementById('limitsModalOverlay').classList.add('hidden');
  };

  // ── Navigation ──
  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', function(e) {
      e.preventDefault();
      const page = this.dataset.page;
      navigateTo(page);
    });
  });

  function navigateTo(page) {
    currentPage = page;
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    document.querySelector(`.nav-item[data-page="${page}"]`).classList.add('active');
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.getElementById('page-' + page).classList.add('active');
    document.getElementById('pageTitle').textContent = {
      dashboard: 'Dashboard',
      secrets: 'Secret Management',
      traffic: 'Traffic Monitor',
      proxy: 'Proxy Control',
      upstreams: 'Upstream Routing',
      settings: 'Settings',
      logs: 'Container Logs',
    }[page] || page;

    // Close mobile sidebar
    document.getElementById('sidebar').classList.remove('open');

    // Load page data
    loadPageData(page);
  }

  // Mobile menu toggle
  document.getElementById('menuToggle').addEventListener('click', () => {
    document.getElementById('sidebar').classList.toggle('open');
  });

  // ── Page Data Loaders ──
  async function loadPageData(page) {
    switch (page) {
      case 'dashboard': await loadDashboard(); break;
      case 'secrets': await loadSecrets(); break;
      case 'traffic': await loadTraffic(); break;
      case 'proxy': await loadProxyStatus(); break;
      case 'upstreams': await loadUpstreams(); break;
      case 'settings': await loadSettings(); break;
      case 'logs': await loadLogs(); break;
    }
  }

  // ── Dashboard ──
  async function loadDashboard() {
    const data = await api('/api/dashboard');
    if (data.error) return;

    // Status
    const isRunning = data.status === 'running';
    const statusEl = document.getElementById('dash-status');
    statusEl.textContent = isRunning ? 'Running' : 'Stopped';
    statusEl.className = 'stat-value ' + (isRunning ? 'accent-green' : 'accent-red');

    document.getElementById('dash-uptime').textContent = 'Uptime: ' + formatDuration(data.uptime);

    const badge = document.getElementById('statusBadge');
    badge.textContent = isRunning ? 'ONLINE' : 'OFFLINE';
    badge.className = 'status-badge ' + (isRunning ? 'running' : 'stopped');

    // Sidebar server info
    document.getElementById('sidebar-server-info').textContent =
      'Port: ' + data.port + ' | ' + (isRunning ? '● Running' : '○ Stopped');

    // Traffic
    document.getElementById('dash-traffic-in').textContent = formatBytes(data.traffic.bytes_in);
    document.getElementById('dash-traffic-out').textContent = formatBytes(data.traffic.bytes_out);
    document.getElementById('dash-connections').textContent = data.traffic.connections;

    // Secrets
    document.getElementById('dash-secrets').textContent = data.secrets.active + ' / ' + data.secrets.total;

    // System
    if (data.system) {
      const cpu = data.system.cpu_percent || 0;
      document.getElementById('dash-cpu').textContent = cpu.toFixed(1) + '%';
      const cpuBar = document.getElementById('dash-cpu-bar');
      cpuBar.style.width = cpu + '%';
      cpuBar.className = 'progress-fill' + (cpu > 90 ? ' danger' : cpu > 70 ? ' warn' : '');

      const ram = data.system.ram_percent || 0;
      document.getElementById('dash-ram').textContent = ram.toFixed(1) + '% (' +
        data.system.ram_used_mb + '/' + data.system.ram_total_mb + ' MB)';
      const ramBar = document.getElementById('dash-ram-bar');
      ramBar.style.width = ram + '%';
      ramBar.className = 'progress-fill' + (ram > 90 ? ' danger' : ram > 70 ? ' warn' : '');

      const disk = data.system.disk_percent || 0;
      document.getElementById('dash-disk').textContent = disk.toFixed(1) + '%';
      const diskBar = document.getElementById('dash-disk-bar');
      diskBar.style.width = disk + '%';
      diskBar.className = 'progress-fill' + (disk > 90 ? ' danger' : disk > 70 ? ' warn' : '');
    }

    // Info
    document.getElementById('dash-port').textContent = data.port;
    document.getElementById('dash-domain').textContent = data.domain;
    document.getElementById('dash-engine').textContent = data.engine_version;
    document.getElementById('dash-concurrency').textContent = data.concurrency;
  }

  // ── Secrets ──
  async function loadSecrets() {
    const data = await api('/api/secrets');
    if (data.error) return;

    const tbody = document.getElementById('secrets-tbody');
    if (!data.secrets || data.secrets.length === 0) {
      tbody.innerHTML = '<tr><td colspan="10" style="text-align:center;color:var(--text-dim);padding:20px">No secrets configured</td></tr>';
      return;
    }

    tbody.innerHTML = data.secrets.map((s, i) => {
      const isEnabled = s.enabled === 'true';
      const quota = parseInt(s.quota) || 0;
      const traffic = (parseInt(s.traffic_in) || 0) + (parseInt(s.traffic_out) || 0);
      let statusBadge = isEnabled ? '<span class="badge active">Active</span>' :
        (quota > 0 && traffic >= quota) ? '<span class="badge quota-hit">Quota Hit</span>' :
        '<span class="badge disabled">Disabled</span>';

      let expDisplay = 'Never';
      if (s.expires && s.expires !== '0') {
        expDisplay = s.expires.split('T')[0];
      }

      return `<tr>
        <td>${i + 1}</td>
        <td><strong>${escHtml(s.label)}</strong></td>
        <td>${statusBadge}</td>
        <td>${s.max_conns === '0' ? '∞' : s.max_conns}</td>
        <td>${s.max_ips === '0' ? '∞' : s.max_ips}</td>
        <td>${quota === 0 ? '∞' : formatBytes(quota)}</td>
        <td>${expDisplay}</td>
        <td>${formatBytes(s.traffic_in)}</td>
        <td>${formatBytes(s.traffic_out)}</td>
        <td>
          <div class="action-buttons">
            <button class="btn btn-sm btn-info" onclick="showSecretLink('${escAttr(s.label)}')" title="Show Link">🔗</button>
            <button class="btn btn-sm btn-warning" onclick="showEditLimits('${escAttr(s.label)}','${s.max_conns}','${s.max_ips}','${s.quota}','${s.expires}')" title="Edit Limits">⚙</button>
            <button class="btn btn-sm ${isEnabled ? 'btn-danger' : 'btn-success'}" onclick="toggleSecret('${escAttr(s.label)}')" title="${isEnabled ? 'Disable' : 'Enable'}">${isEnabled ? '⏸' : '▶'}</button>
            <button class="btn btn-sm btn-warning" onclick="rotateSecret('${escAttr(s.label)}')" title="Rotate">🔄</button>
            <button class="btn btn-sm btn-danger" onclick="deleteSecret('${escAttr(s.label)}')" title="Delete">✕</button>
          </div>
        </td>
      </tr>`;
    }).join('');
  }

  window.showAddSecret = function() {
    document.getElementById('add-secret-form').classList.remove('hidden');
    document.getElementById('new-secret-label').focus();
  };

  window.hideAddSecret = function() {
    document.getElementById('add-secret-form').classList.add('hidden');
    document.getElementById('new-secret-label').value = '';
  };

  window.addSecret = async function() {
    const label = document.getElementById('new-secret-label').value.trim();
    if (!label) return toast('Enter a label', 'error');

    const data = await api('/api/secrets', { method: 'POST', body: { label } });
    if (data.error) return toast(data.error, 'error');

    hideAddSecret();
    toast('Secret "' + label + '" created', 'success');
    loadSecrets();

    if (data.link) {
      showLinkModal('New Secret Link', data.link);
    }
  };

  window.deleteSecret = async function(label) {
    if (!confirm('Delete secret "' + label + '"? Users with this key will be disconnected.')) return;
    const data = await api('/api/secrets/' + encodeURIComponent(label), { method: 'DELETE' });
    if (data.error) return toast(data.error, 'error');
    toast('Secret "' + label + '" removed', 'success');
    loadSecrets();
  };

  window.toggleSecret = async function(label) {
    const data = await api('/api/secrets/' + encodeURIComponent(label) + '/toggle', { method: 'POST' });
    if (data.error) return toast(data.error, 'error');
    toast('Secret "' + label + '" toggled', 'success');
    loadSecrets();
  };

  window.rotateSecret = async function(label) {
    if (!confirm('Rotate secret "' + label + '"? The old key will stop working immediately.')) return;
    const data = await api('/api/secrets/' + encodeURIComponent(label) + '/rotate', { method: 'POST' });
    if (data.error) return toast(data.error, 'error');
    toast('Secret "' + label + '" rotated', 'success');
    loadSecrets();
    if (data.link) {
      showLinkModal('New Rotated Link', data.link);
    }
  };

  window.showSecretLink = async function(label) {
    const data = await api('/api/secrets/' + encodeURIComponent(label) + '/link');
    if (data.error) return toast(data.error, 'error');
    showLinkModal('Proxy Link — ' + label, data.link);
  };

  function showLinkModal(title, link) {
    document.getElementById('linkModalTitle').textContent = title;
    const body = document.getElementById('linkModalBody');
    body.innerHTML = '';
    if (link) {
      const lines = link.split('\n').filter(l => l.trim());
      lines.forEach(line => {
        const trimmed = line.trim();
        if (trimmed) {
          const div = document.createElement('div');
          div.className = 'link-box';
          div.textContent = trimmed;
          div.onclick = function() {
            navigator.clipboard.writeText(trimmed).then(() => toast('Copied!', 'success'));
          };
          const label = document.createElement('div');
          label.className = 'link-label';
          if (trimmed.includes('tg://proxy')) label.textContent = 'Telegram Deep Link';
          else if (trimmed.includes('https://t.me/proxy')) label.textContent = 'HTTPS Web Link';
          else label.textContent = 'Link';
          body.appendChild(label);
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
    document.getElementById('limits-quota').value = quota === '0' ? '' : formatBytes(parseInt(quota) || 0);
    document.getElementById('limits-expires').value = (expires === '0' || !expires) ? '' : expires.split('T')[0];
    document.getElementById('limitsModalOverlay').classList.remove('hidden');
  };

  window.saveLimits = async function() {
    const label = document.getElementById('limits-label').value;
    const body = {
      max_conns: document.getElementById('limits-conns').value || '0',
      max_ips: document.getElementById('limits-ips').value || '0',
      quota: document.getElementById('limits-quota').value || '0',
      expires: document.getElementById('limits-expires').value || '0',
    };
    const data = await api('/api/secrets/' + encodeURIComponent(label) + '/limits', { method: 'POST', body });
    if (data.error) return toast(data.error, 'error');
    toast('Limits updated for "' + label + '"', 'success');
    closeLimitsModal();
    loadSecrets();
  };

  // ── Traffic ──
  async function loadTraffic() {
    const data = await api('/api/traffic');
    if (data.error) return;

    document.getElementById('traffic-total-in').textContent = formatBytes(data.global.bytes_in);
    document.getElementById('traffic-total-out').textContent = formatBytes(data.global.bytes_out);
    document.getElementById('traffic-active-conns').textContent = data.global.connections;

    const tbody = document.getElementById('traffic-tbody');
    if (!data.traffic || data.traffic.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-dim);padding:20px">No traffic data</td></tr>';
      return;
    }

    const maxTotal = Math.max(...data.traffic.map(t => t.total), 1);

    tbody.innerHTML = data.traffic.map(t => {
      const total = t.bytes_in + t.bytes_out;
      const pct = Math.min((total / maxTotal) * 100, 100);
      return `<tr>
        <td><strong>${escHtml(t.label)}</strong></td>
        <td>${t.enabled === 'true' ? '<span class="badge active">Active</span>' : '<span class="badge disabled">Off</span>'}</td>
        <td>${formatBytes(t.bytes_in)}</td>
        <td>${formatBytes(t.bytes_out)}</td>
        <td>${formatBytes(total)}</td>
        <td><div class="traffic-bar"><div class="traffic-bar-fill" style="width:${pct}%"></div></div></td>
      </tr>`;
    }).join('');
  }

  // ── Proxy Control ──
  async function loadProxyStatus() {
    const data = await api('/api/dashboard');
    if (data.error) return;
    const isRunning = data.status === 'running';
    const el = document.getElementById('proxy-status-display');
    el.textContent = isRunning ? '● Running' : '○ Stopped';
    el.className = 'stat-value ' + (isRunning ? 'accent-green' : 'accent-red');

    const badge = document.getElementById('statusBadge');
    badge.textContent = isRunning ? 'ONLINE' : 'OFFLINE';
    badge.className = 'status-badge ' + (isRunning ? 'running' : 'stopped');
  }

  window.proxyAction = async function(action) {
    toast('Sending ' + action + ' command...', 'info');
    const data = await api('/api/proxy/' + action, { method: 'POST' });
    if (data.error) return toast('Error: ' + data.error, 'error');
    toast('Proxy ' + action + ' completed', 'success');
    setTimeout(() => {
      loadDashboard();
      loadProxyStatus();
    }, 1500);
  };

  window.runAction = async function(action) {
    toast('Running ' + action + '...', 'info');
    const data = await api('/api/action', { method: 'POST', body: { action } });
    if (data.error) return toast('Error: ' + data.error, 'error');
    showModal('Result: ' + action, '<pre>' + escHtml(data.message || 'Done') + '</pre>');
  };

  // ── Upstreams ──
  async function loadUpstreams() {
    const data = await api('/api/upstreams');
    if (data.error) return;

    const tbody = document.getElementById('upstreams-tbody');
    if (!data.upstreams || data.upstreams.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-dim);padding:20px">No upstreams configured</td></tr>';
      return;
    }

    tbody.innerHTML = data.upstreams.map(u => `<tr>
      <td><strong>${escHtml(u.name)}</strong></td>
      <td>${escHtml(u.type)}</td>
      <td>${escHtml(u.addr || '—')}</td>
      <td>${escHtml(u.weight)}</td>
      <td>${u.enabled === 'true' ? '<span class="badge active">On</span>' : '<span class="badge disabled">Off</span>'}</td>
      <td>
        <button class="btn btn-sm btn-danger" onclick="deleteUpstream('${escAttr(u.name)}')">✕</button>
      </td>
    </tr>`).join('');
  }

  window.showAddUpstream = function() {
    document.getElementById('add-upstream-form').classList.remove('hidden');
  };

  window.hideAddUpstream = function() {
    document.getElementById('add-upstream-form').classList.add('hidden');
  };

  window.addUpstream = async function() {
    const body = {
      name: document.getElementById('up-name').value.trim(),
      type: document.getElementById('up-type').value,
      addr: document.getElementById('up-addr').value.trim(),
      user: document.getElementById('up-user').value.trim(),
      pass: document.getElementById('up-pass').value.trim(),
      weight: document.getElementById('up-weight').value.trim() || '10',
    };
    if (!body.name) return toast('Enter a label', 'error');

    const data = await api('/api/upstreams', { method: 'POST', body });
    if (data.error) return toast(data.error, 'error');
    toast('Upstream "' + body.name + '" added', 'success');
    hideAddUpstream();
    loadUpstreams();
  };

  window.deleteUpstream = async function(name) {
    if (!confirm('Delete upstream "' + name + '"?')) return;
    const data = await api('/api/upstreams/' + encodeURIComponent(name), { method: 'DELETE' });
    if (data.error) return toast(data.error, 'error');
    toast('Upstream "' + name + '" removed', 'success');
    loadUpstreams();
  };

  // ── Settings ──
  async function loadSettings() {
    const data = await api('/api/settings');
    if (data.error || !data.settings) return;

    const s = data.settings;
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
    const body = {
      PROXY_PORT: document.getElementById('set-port').value,
      PROXY_DOMAIN: document.getElementById('set-domain').value,
      PROXY_CONCURRENCY: document.getElementById('set-concurrency').value,
      CLIENT_MSS: document.getElementById('set-mss').value,
      PROXY_METRICS_PORT: document.getElementById('set-metrics-port').value,
      AD_TAG: document.getElementById('set-adtag').value,
      FAKE_CERT_LEN: document.getElementById('set-cert-len').value,
      MASKING_HOST: document.getElementById('set-mask-host').value,
      MASKING_PORT: document.getElementById('set-mask-port').value,
      UNKNOWN_SNI_ACTION: document.getElementById('set-sni-action').value,
    };
    const data = await api('/api/settings', { method: 'POST', body });
    if (data.error) return toast('Error: ' + data.error, 'error');
    toast('Settings saved', 'success');
  };

  // ── Logs ──
  window.loadLogs = async function() {
    const data = await api('/api/proxy/logs');
    const el = document.getElementById('log-output');
    if (data.error) {
      el.textContent = 'Error loading logs: ' + data.error;
    } else {
      el.textContent = data.logs || 'No logs available';
      el.scrollTop = el.scrollHeight;
    }
  };

  // ── Utilities ──
  function escHtml(s) {
    const d = document.createElement('div');
    d.textContent = s || '';
    return d.innerHTML;
  }

  function escAttr(s) {
    return (s || '').replace(/'/g, "\\'").replace(/"/g, '&quot;');
  }

  // ── Auto-Refresh ──
  function startAutoRefresh() {
    if (refreshInterval) clearInterval(refreshInterval);
    refreshInterval = setInterval(() => {
      if (currentPage === 'dashboard' || currentPage === 'proxy') {
        loadPageData(currentPage);
      }
    }, 10000);  // Every 10 seconds
  }

  window.refreshAll = function() {
    loadPageData(currentPage);
    toast('Refreshed', 'info');
  };

  // ── Init ──
  async function init() {
    await loadDashboard();
    startAutoRefresh();
  }

  // Handle Enter key on add secret input
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Enter') {
      if (document.activeElement && document.activeElement.id === 'new-secret-label') {
        addSecret();
      }
    }
  });

  init();
})();
