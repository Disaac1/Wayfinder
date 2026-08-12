// Wayfinder Management Console Frontend Application Logic

let currentTab = 'overview';
let activeDbTable = 'Rooms';
let pollInterval = null;
let roomsData = [];

// DOM Element References
const elements = {
  navItems: document.querySelectorAll('.nav-item'),
  tabPanes: document.querySelectorAll('.tab-pane'),
  pageTitle: document.getElementById('page-title'),
  pageSubtitle: document.getElementById('page-subtitle'),
  btnRefresh: document.getElementById('btn-refresh'),
  btnClearCache: document.getElementById('btn-clear-cache'),
  qbtnClearCache: document.getElementById('qbtn-clear-cache'),
  qbtnRefreshAll: document.getElementById('qbtn-refresh-all'),
  searchRooms: document.getElementById('search-rooms'),
  
  // Overview Stats
  statActiveRooms: document.getElementById('stat-active-rooms'),
  statTotalRooms: document.getElementById('stat-total-rooms'),
  statConnectedUsers: document.getElementById('stat-connected-users'),
  statTotalUsers: document.getElementById('stat-total-users'),
  statActiveServers: document.getElementById('stat-active-servers'),
  statLockedSessions: document.getElementById('stat-locked-sessions'),
  vitalUptime: document.getElementById('vital-uptime'),
  vitalNode: document.getElementById('vital-node'),
  vitalMemory: document.getElementById('vital-memory'),
  vitalApworlds: document.getElementById('vital-apworlds'),

  // Badges
  badgeRooms: document.getElementById('badge-rooms'),
  badgeServers: document.getElementById('badge-servers'),
  badgeApworlds: document.getElementById('badge-apworlds'),

  // Tables
  roomsTableBody: document.getElementById('rooms-table-body'),
  serversTableBody: document.getElementById('servers-table-body'),
  apworldsTableBody: document.getElementById('apworlds-table-body'),
  dbTableHead: document.getElementById('db-table-head'),
  dbTableBody: document.getElementById('db-table-body'),
  dbTabBtns: document.querySelectorAll('.db-tab-btn'),

  // APWorld Upload
  dropzone: document.getElementById('apworld-dropzone'),
  fileInput: document.getElementById('apworld-file-input'),
  btnBrowseApworld: document.getElementById('btn-browse-apworld'),
  uploadProgress: document.getElementById('upload-progress'),
  progressFill: document.getElementById('progress-fill'),
  uploadStatusText: document.getElementById('upload-status-text'),

  // Modal
  playerModal: document.getElementById('player-modal'),
  modalRoomTitle: document.getElementById('modal-room-title'),
  modalPlayerList: document.getElementById('modal-player-list'),
  modalCloseBtn: document.getElementById('modal-close-btn'),

  // Purge Modal
  btnPurgeAll: document.getElementById('btn-purge-all'),
  qbtnPurgeAll: document.getElementById('qbtn-purge-all'),
  purgeModal: document.getElementById('purge-modal'),
  purgeModalCloseBtn: document.getElementById('purge-modal-close-btn'),
  btnCancelPurge: document.getElementById('btn-cancel-purge'),
  btnConfirmPurge: document.getElementById('btn-confirm-purge'),
  chkPurgeApworlds: document.getElementById('chk-purge-apworlds'),

  // Toast
  toastContainer: document.getElementById('toast-container')
};

// Titles map for tabs
const tabTitles = {
  overview: { title: 'System Overview', subtitle: 'Real-time telemetry and orchestrator vitals' },
  rooms: { title: 'Rooms & Sessions Manager', subtitle: 'Manage active multiworld lobbies and checkout locks' },
  servers: { title: 'Archipelago MultiServer Monitor', subtitle: 'Running AP server subprocesses and port bindings' },
  apworlds: { title: 'Custom APWorld Packages', subtitle: 'Upload and manage custom game world definitions' },
  database: { title: 'Database Explorer', subtitle: 'Inspect raw SQLite database records' }
};

// Initialize Application
document.addEventListener('DOMContentLoaded', () => {
  setupNavigation();
  setupEventListeners();
  setupDropzone();
  
  // Initial data fetch
  refreshAllData();

  // Start polling telemetry every 3 seconds
  pollInterval = setInterval(refreshAllData, 3000);
});

// Setup Tab Navigation
function setupNavigation() {
  elements.navItems.forEach(item => {
    item.addEventListener('click', () => {
      const targetTab = item.getAttribute('data-tab');
      if (!targetTab) return;

      elements.navItems.forEach(i => i.classList.remove('active'));
      elements.tabPanes.forEach(p => p.classList.remove('active'));

      item.classList.add('active');
      document.getElementById(`tab-${targetTab}`).classList.add('active');

      currentTab = targetTab;

      if (tabTitles[targetTab]) {
        elements.pageTitle.textContent = tabTitles[targetTab].title;
        elements.pageSubtitle.textContent = tabTitles[targetTab].subtitle;
      }

      refreshCurrentTab();
    });
  });

  // DB Table Tab Buttons
  elements.dbTabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      elements.dbTabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activeDbTable = btn.getAttribute('data-dbtable');
      fetchDBTable(activeDbTable);
    });
  });
}

// Setup Event Listeners
function setupEventListeners() {
  elements.btnRefresh.addEventListener('click', () => {
    refreshAllData();
    showToast('Telemetry refreshed successfully', 'info');
  });

  elements.btnClearCache.addEventListener('click', clearCache);
  if (elements.qbtnClearCache) elements.qbtnClearCache.addEventListener('click', clearCache);
  if (elements.qbtnRefreshAll) elements.qbtnRefreshAll.addEventListener('click', () => {
    refreshAllData();
    showToast('Vitals refreshed', 'info');
  });

  // Purge All Modal Openers
  const openPurgeModal = () => {
    if (elements.chkPurgeApworlds) elements.chkPurgeApworlds.checked = false;
    if (elements.purgeModal) elements.purgeModal.style.display = 'flex';
  };
  if (elements.btnPurgeAll) elements.btnPurgeAll.addEventListener('click', openPurgeModal);
  if (elements.qbtnPurgeAll) elements.qbtnPurgeAll.addEventListener('click', openPurgeModal);

  // Purge Modal Closers & Confirmation
  if (elements.purgeModalCloseBtn) {
    elements.purgeModalCloseBtn.addEventListener('click', () => {
      elements.purgeModal.style.display = 'none';
    });
  }
  if (elements.btnCancelPurge) {
    elements.btnCancelPurge.addEventListener('click', () => {
      elements.purgeModal.style.display = 'none';
    });
  }
  if (elements.btnConfirmPurge) {
    elements.btnConfirmPurge.addEventListener('click', purgeAllData);
  }

  elements.searchRooms.addEventListener('input', renderRoomsTable);

  // Modal close
  elements.modalCloseBtn.addEventListener('click', () => {
    elements.playerModal.style.display = 'none';
  });

  window.addEventListener('click', (e) => {
    if (e.target === elements.playerModal) {
      elements.playerModal.style.display = 'none';
    }
    if (e.target === elements.purgeModal) {
      elements.purgeModal.style.display = 'none';
    }
  });
}

// Refresh all telemetry data
async function refreshAllData() {
  await Promise.all([
    fetchOverview(),
    fetchRooms(),
    fetchServers(),
    fetchAPWorlds()
  ]);

  if (currentTab === 'database') {
    fetchDBTable(activeDbTable);
  }
}

function refreshCurrentTab() {
  switch (currentTab) {
    case 'overview': fetchOverview(); break;
    case 'rooms': fetchRooms(); break;
    case 'servers': fetchServers(); break;
    case 'apworlds': fetchAPWorlds(); break;
    case 'database': fetchDBTable(activeDbTable); break;
  }
}

// 1. Overview Telemetry
async function fetchOverview() {
  try {
    const res = await fetch('/api/admin/overview');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    const { stats, uptimeSeconds, memoryUsage, nodeVersion } = data;

    elements.statActiveRooms.textContent = stats.activeRooms;
    elements.statTotalRooms.textContent = `${stats.totalRooms} total created rooms`;
    elements.statConnectedUsers.textContent = stats.connectedUsers;
    elements.statTotalUsers.textContent = `${stats.totalUsers} total players registered`;
    elements.statActiveServers.textContent = stats.activeServersCount;
    elements.statLockedSessions.textContent = stats.lockedSessions;

    elements.badgeRooms.textContent = stats.activeRooms;
    elements.badgeServers.textContent = stats.activeServersCount;
    elements.badgeApworlds.textContent = stats.apWorldCount;

    // Vitals
    elements.vitalUptime.textContent = formatUptime(uptimeSeconds);
    elements.vitalNode.textContent = nodeVersion;
    const heapMb = (memoryUsage.heapUsed / (1024 * 1024)).toFixed(1);
    elements.vitalMemory.textContent = `${heapMb} MB`;
    elements.vitalApworlds.textContent = stats.apWorldCount;
  } catch (err) {
    console.error('Failed to fetch overview vitals:', err);
  }
}

// 2. Fetch Rooms
async function fetchRooms() {
  try {
    const res = await fetch('/api/admin/rooms');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    roomsData = data.rooms || [];
    renderRoomsTable();
  } catch (err) {
    console.error('Failed to fetch rooms data:', err);
    elements.roomsTableBody.innerHTML = `<tr><td colspan="7" class="loading-cell">Failed to load room data: ${err.message}</td></tr>`;
  }
}

function renderRoomsTable() {
  const query = elements.searchRooms.value.toLowerCase().trim();
  const filtered = roomsData.filter(r => 
    r.code.toLowerCase().includes(query) || 
    (r.players && r.players.some(p => p.name.toLowerCase().includes(query)))
  );

  if (filtered.length === 0) {
    elements.roomsTableBody.innerHTML = `<tr><td colspan="7" class="loading-cell">No rooms found.</td></tr>`;
    return;
  }

  elements.roomsTableBody.innerHTML = filtered.map(room => {
    const seedBadge = getStatusPill(room.seed_status);
    const lockText = room.locked_by 
      ? `<span class="status-pill locked" title="Locked at ${new Date(room.locked_at).toLocaleTimeString()}">🔒 ${escapeHtml(room.locked_by)}</span>` 
      : `<span class="status-pill idle">Unlocked</span>`;

    const serverPort = room.serverPort 
      ? `<span class="code-tag">:${room.serverPort}</span>` 
      : `<span class="text-muted">Stopped</span>`;

    const playerList = JSON.stringify(room.players).replace(/"/g, '&quot;');

    return `
      <tr>
        <td><strong class="code-tag">${escapeHtml(room.code)}</strong></td>
        <td><span class="status-pill ${room.status === 'active' ? 'active' : 'idle'}">${escapeHtml(room.status)}</span></td>
        <td>${seedBadge}</td>
        <td>${serverPort}</td>
        <td>
          <button class="btn btn-secondary btn-sm btn-view-players" data-code="${room.code}" data-players="${playerList}">
            👥 ${room.players ? room.players.length : 0} Players
          </button>
        </td>
        <td>${lockText}</td>
        <td>
          <div class="action-buttons" style="display: flex; gap: 0.35rem;">
            ${room.isServerRunning ? `<button class="btn btn-warning btn-sm btn-kill-server" data-code="${room.code}" title="Kill AP MultiServer">⏹️ Kill</button>` : ''}
            ${room.locked_by ? `<button class="btn btn-secondary btn-sm btn-unlock-session" data-code="${room.code}" title="Force Unlock Save">🔓 Unlock</button>` : ''}
            <button class="btn btn-danger btn-sm btn-delete-room" data-code="${room.code}" title="Delete Room & Files">🗑️ Delete</button>
          </div>
        </td>
      </tr>
    `;
  }).join('');

  // Attach event listeners for dynamic action buttons
  document.querySelectorAll('.btn-view-players').forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.getAttribute('data-code');
      const players = JSON.parse(btn.getAttribute('data-players'));
      openPlayerModal(code, players);
    });
  });

  document.querySelectorAll('.btn-kill-server').forEach(btn => {
    btn.addEventListener('click', () => killServer(btn.getAttribute('data-code')));
  });

  document.querySelectorAll('.btn-unlock-session').forEach(btn => {
    btn.addEventListener('click', () => unlockSession(btn.getAttribute('data-code')));
  });

  document.querySelectorAll('.btn-delete-room').forEach(btn => {
    btn.addEventListener('click', () => deleteRoom(btn.getAttribute('data-code')));
  });
}

// 3. Fetch Active Servers
async function fetchServers() {
  try {
    const res = await fetch('/api/admin/servers');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const servers = data.servers || [];

    if (servers.length === 0) {
      elements.serversTableBody.innerHTML = `<tr><td colspan="6" class="loading-cell">No Archipelago MultiServer processes currently active.</td></tr>`;
      return;
    }

    elements.serversTableBody.innerHTML = servers.map(srv => `
      <tr>
        <td><strong class="code-tag">${escapeHtml(srv.roomCode)}</strong></td>
        <td><span class="code-tag">:${srv.port}</span></td>
        <td><span class="vital-value">${srv.pid || 'N/A'}</span></td>
        <td><small class="code-tag" style="font-size: 0.75rem;">${escapeHtml(srv.saveFilePath)}</small></td>
        <td><span class="status-pill active">Running</span></td>
        <td>
          <button class="btn btn-danger btn-sm btn-kill-server" data-code="${srv.roomCode}">
            ⏹️ Stop Process
          </button>
        </td>
      </tr>
    `).join('');

    document.querySelectorAll('#servers-table-body .btn-kill-server').forEach(btn => {
      btn.addEventListener('click', () => killServer(btn.getAttribute('data-code')));
    });
  } catch (err) {
    console.error('Failed to fetch AP servers:', err);
  }
}

// 4. Fetch Custom APWorlds
async function fetchAPWorlds() {
  try {
    const res = await fetch('/api/admin/custom-worlds');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const files = data.files || [];

    if (files.length === 0) {
      elements.apworldsTableBody.innerHTML = `<tr><td colspan="4" class="loading-cell">No custom .apworld packages installed.</td></tr>`;
      return;
    }

    elements.apworldsTableBody.innerHTML = files.map(file => `
      <tr>
        <td><strong>📦 ${escapeHtml(file.filename)}</strong></td>
        <td>${(file.sizeBytes / 1024).toFixed(1)} KB</td>
        <td>${new Date(file.modifiedAt).toLocaleString()}</td>
        <td>
          <button class="btn btn-danger btn-sm btn-delete-apworld" data-file="${escapeHtml(file.filename)}">
            🗑️ Delete
          </button>
        </td>
      </tr>
    `).join('');

    document.querySelectorAll('.btn-delete-apworld').forEach(btn => {
      btn.addEventListener('click', () => deleteAPWorld(btn.getAttribute('data-file')));
    });
  } catch (err) {
    console.error('Failed to fetch apworlds:', err);
  }
}

// 5. Database Explorer
async function fetchDBTable(tableName) {
  try {
    elements.dbTableHead.innerHTML = '';
    elements.dbTableBody.innerHTML = `<tr><td class="loading-cell">Loading ${tableName}...</td></tr>`;

    const res = await fetch(`/api/admin/db?table=${tableName}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const rows = data.rows || [];

    if (rows.length === 0) {
      elements.dbTableBody.innerHTML = `<tr><td class="loading-cell">Table ${tableName} is empty.</td></tr>`;
      return;
    }

    // Build Table Headers from keys of first row
    const keys = Object.keys(rows[0]);
    elements.dbTableHead.innerHTML = `<tr>${keys.map(k => `<th>${escapeHtml(k)}</th>`).join('')}</tr>`;

    elements.dbTableBody.innerHTML = rows.map(row => `
      <tr>
        ${keys.map(k => {
          let val = row[k];
          if (val === null || val === undefined) val = '<em style="color: var(--text-muted);">null</em>';
          else if (typeof val === 'object') val = escapeHtml(JSON.stringify(val));
          else val = escapeHtml(String(val));
          return `<td>${val}</td>`;
        }).join('')}
      </tr>
    `).join('');
  } catch (err) {
    console.error(`Failed to fetch database table ${tableName}:`, err);
    elements.dbTableBody.innerHTML = `<tr><td class="loading-cell">Failed to load table: ${err.message}</td></tr>`;
  }
}

async function clearCache() {
  try {
    const res = await fetch('/api/cache/clear', { method: 'POST' });
    if (res.ok) {
      showToast('Archipelago cache successfully cleared!', 'success');
      refreshAllData();
    } else {
      showToast('Failed to clear cache', 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

async function purgeAllData() {
  const includeCustomWorlds = elements.chkPurgeApworlds ? elements.chkPurgeApworlds.checked : false;
  if (elements.purgeModal) elements.purgeModal.style.display = 'none';

  try {
    const res = await fetch('/api/admin/purge-all', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ includeCustomWorlds })
    });

    if (res.ok) {
      const data = await res.json();
      showToast(data.message || 'All server data deleted successfully!', 'success');
      refreshAllData();
    } else {
      const err = await res.json();
      showToast(`Purge failed: ${err.error}`, 'error');
    }
  } catch (err) {
    showToast(`Purge error: ${err.message}`, 'error');
  }
}

async function killServer(roomCode) {
  if (!confirm(`Are you sure you want to stop the Archipelago server process for room ${roomCode}?`)) return;
  try {
    const res = await fetch(`/api/admin/rooms/${roomCode}/kill`, { method: 'POST' });
    if (res.ok) {
      showToast(`Terminated AP Server for room ${roomCode}`, 'success');
      refreshAllData();
    } else {
      const err = await res.json();
      showToast(`Error: ${err.error}`, 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

async function unlockSession(roomCode) {
  if (!confirm(`Force unlock save session lock for room ${roomCode}?`)) return;
  try {
    const res = await fetch(`/api/admin/rooms/${roomCode}/unlock`, { method: 'POST' });
    if (res.ok) {
      showToast(`Unlocked session for room ${roomCode}`, 'success');
      refreshAllData();
    } else {
      const err = await res.json();
      showToast(`Error: ${err.error}`, 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

async function deleteRoom(roomCode) {
  if (!confirm(`WARNING: Are you sure you want to delete room ${roomCode}? This will remove all connected players and temporary seed files.`)) return;
  try {
    const res = await fetch(`/api/admin/rooms/${roomCode}`, { method: 'DELETE' });
    if (res.ok) {
      showToast(`Deleted room ${roomCode}`, 'success');
      refreshAllData();
    } else {
      const err = await res.json();
      showToast(`Error: ${err.error}`, 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

async function deleteAPWorld(filename) {
  if (!confirm(`Delete custom world file ${filename}?`)) return;
  try {
    const res = await fetch(`/api/admin/custom-worlds/${encodeURIComponent(filename)}`, { method: 'DELETE' });
    if (res.ok) {
      showToast(`Deleted ${filename}`, 'success');
      fetchAPWorlds();
      fetchOverview();
    } else {
      const err = await res.json();
      showToast(`Error: ${err.error}`, 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

// Upload APWorld Handling
function setupDropzone() {
  const { dropzone, fileInput, btnBrowseApworld } = elements;

  btnBrowseApworld.addEventListener('click', () => fileInput.click());

  dropzone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropzone.classList.add('dragover');
  });

  dropzone.addEventListener('dragleave', () => {
    dropzone.classList.remove('dragover');
  });

  dropzone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropzone.classList.remove('dragover');
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      uploadAPWorldFile(e.dataTransfer.files[0]);
    }
  });

  fileInput.addEventListener('change', () => {
    if (fileInput.files && fileInput.files.length > 0) {
      uploadAPWorldFile(fileInput.files[0]);
    }
  });
}

async function uploadAPWorldFile(file) {
  if (!file.name.endsWith('.apworld')) {
    return showToast('Invalid file: Only .apworld files are accepted', 'error');
  }

  const formData = new FormData();
  formData.append('file', file);

  elements.uploadProgress.style.display = 'block';
  elements.progressFill.style.width = '30%';
  elements.uploadStatusText.textContent = `Uploading ${file.name}...`;

  try {
    elements.progressFill.style.width = '70%';
    const res = await fetch('/api/admin/custom-worlds/upload', {
      method: 'POST',
      body: formData
    });

    elements.progressFill.style.width = '100%';

    if (res.ok) {
      showToast(`Successfully uploaded ${file.name}`, 'success');
      setTimeout(() => {
        elements.uploadProgress.style.display = 'none';
        elements.progressFill.style.width = '0%';
      }, 1000);
      fetchAPWorlds();
      fetchOverview();
    } else {
      const err = await res.json();
      showToast(`Upload failed: ${err.error}`, 'error');
      elements.uploadProgress.style.display = 'none';
    }
  } catch (err) {
    showToast(`Upload error: ${err.message}`, 'error');
    elements.uploadProgress.style.display = 'none';
  }
}

// Modal Helper
function openPlayerModal(roomCode, players) {
  elements.modalRoomTitle.textContent = `Players in Room ${roomCode}`;
  
  if (!players || players.length === 0) {
    elements.modalPlayerList.innerHTML = `<p class="text-muted">No connected or registered players in this room.</p>`;
  } else {
    elements.modalPlayerList.innerHTML = `
      <ul style="list-style: none; display: flex; flex-direction: column; gap: 0.75rem;">
        ${players.map(p => `
          <li style="display: flex; align-items: center; justify-content: space-between; padding: 0.75rem; background: var(--bg-dark); border-radius: var(--radius-md); border: 1px solid var(--border-color);">
            <div>
              <strong>${escapeHtml(p.name)}</strong>
              ${p.isHost ? '<span class="status-pill active" style="font-size: 0.7rem; margin-left: 0.35rem;">HOST</span>' : ''}
              <br>
              <small class="text-muted">Games: ${p.games.length > 0 ? p.games.join(', ') : 'None selected'}</small>
            </div>
            <div style="display: flex; gap: 0.5rem; align-items: center;">
              <span class="status-pill ${p.isConnected ? 'active' : 'idle'}">${p.isConnected ? 'Connected' : 'Offline'}</span>
              <span class="status-pill ${p.isReady ? 'done' : 'idle'}">${p.isReady ? 'Ready' : 'Not Ready'}</span>
            </div>
          </li>
        `).join('')}
      </ul>
    `;
  }

  elements.playerModal.style.display = 'flex';
}

// Helpers
function getStatusPill(status) {
  switch (status) {
    case 'done': return `<span class="status-pill done">Done</span>`;
    case 'generating': return `<span class="status-pill generating">Generating</span>`;
    default: return `<span class="status-pill idle">Idle</span>`;
  }
}

function formatUptime(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `
    <span>${type === 'success' ? '✅' : type === 'error' ? '❌' : 'ℹ️'}</span>
    <span>${escapeHtml(message)}</span>
  `;

  elements.toastContainer.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transition = 'opacity 0.3s ease';
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}
