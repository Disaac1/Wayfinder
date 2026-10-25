import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { spawn, ChildProcess } from 'child_process';
import net from 'net';
import AdmZip from 'adm-zip';
import db, { touchRoomActivity } from './db.js';
import { getPythonCommand } from './archipelagoRunner.js';
import { roomChecksCache, recalculateRoomChecks, fetchRoomChecks } from './checksService.js';
import { injectServerAddressIntoOutputs } from './patchUtils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.join(__dirname, '..');

export interface ActiveServer {
  child: ChildProcess;
  port: number;
  saveFilePath: string;
  statusInterval?: NodeJS.Timeout;
}

export const activeServers = new Map<string, ActiveServer>();

let onRoomStateBroadcast: ((roomCode: string) => void) | null = null;
let onChecksBroadcast: ((roomCode: string) => void) | null = null;
let onServerLogBroadcast: ((roomCode: string, line: string) => void) | null = null;

export function registerBroadcastCallback(cb: (roomCode: string) => void): void {
  onRoomStateBroadcast = cb;
}

export function registerChecksBroadcastCallback(cb: (roomCode: string) => void): void {
  onChecksBroadcast = cb;
}

export function registerServerLogBroadcastCallback(cb: (roomCode: string, line: string) => void): void {
  onServerLogBroadcast = cb;
}

const AP_START_PORT = parseInt(process.env.AP_START_PORT || '38000', 10);
const AP_MAX_PORT = parseInt(process.env.AP_MAX_PORT || '38010', 10);

/**
 * Find a free TCP port recursively starting from startPort within configured pool
 */
export function getFreePort(startPort: number = AP_START_PORT): Promise<number> {
  const activePorts = new Set(Array.from(activeServers.values()).map(s => s.port));
  let candidate = startPort;
  while (activePorts.has(candidate) && candidate <= AP_MAX_PORT) {
    candidate++;
  }
  if (candidate > AP_MAX_PORT) {
    console.warn(`[Port Manager] All ports in pool ${AP_START_PORT}-${AP_MAX_PORT} are busy. Searching above max range...`);
  }
  return new Promise((resolve) => {
    const server = net.createServer();
    server.on('error', () => {
      resolve(getFreePort(candidate + 1));
    });
    server.listen(candidate, () => {
      server.close(() => {
        resolve(candidate);
      });
    });
  });
}

/**
 * Kill Archipelago server process for a given room
 */
export function killRoomServer(roomCode: string): void {
  const server = activeServers.get(roomCode);
  if (server) {
    console.log(`Killing Archipelago server process for room ${roomCode}...`);
    if (server.statusInterval) {
      clearInterval(server.statusInterval);
    }
    try {
      server.child.kill();
    } catch (e) {
      console.error(`Failed to kill server process for room ${roomCode}:`, e);
    }
    activeServers.delete(roomCode);
  }
}

/**
 * Kill all running Archipelago server processes (used during shutdown)
 */
export function killAllServers(): void {
  for (const [roomCode, activeServer] of activeServers.entries()) {
    console.log(`Killing AP Server for room ${roomCode}...`);
    try {
      if (activeServer.statusInterval) {
        clearInterval(activeServer.statusInterval);
      }
      activeServer.child.kill();
    } catch (e) {}
  }
  activeServers.clear();
}

/**
 * Send an Archipelago console command to a running MultiServer subprocess
 */
export function sendServerCommand(roomCode: string, command: string): boolean {
  const server = activeServers.get(roomCode);
  if (!server || !server.child || !server.child.stdin || server.child.stdin.destroyed) {
    return false;
  }
  try {
    const cmd = command.trim();
    console.log(`[AP Server ${roomCode} Command]: ${cmd}`);
    server.child.stdin.write(cmd + '\n');
    return true;
  } catch (err) {
    console.error(`Failed to send command to AP Server ${roomCode}:`, err);
    return false;
  }
}

/**
 * Launch local Archipelago MultiServer process for a room
 */
export async function startCentralServer(roomCode: string, zipName: string): Promise<void> {
  killRoomServer(roomCode);

  const outputsDir = path.join(BACKEND_ROOT, 'temp_seeds', roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    throw new Error(`Outputs directory not found for room ${roomCode}`);
  }

  // 1. Extract the seed zip file contents directly into the outputs directory using AdmZip
  const zipPath = path.join(outputsDir, zipName);
  try {
    console.log(`Extracting seed archive for room ${roomCode}: ${zipPath}`);
    const zip = new AdmZip(zipPath);
    for (const entry of zip.getEntries()) {
      if (entry.isDirectory) continue;
      const safeEntryName = path.basename(entry.entryName);
      fs.writeFileSync(path.join(outputsDir, safeEntryName), entry.getData());
    }
  } catch (extractErr: any) {
    console.error(`Failed to extract seed ZIP archive for room ${roomCode}:`, extractErr);
    throw new Error(`Failed to extract seed ZIP archive: ${extractErr.message}`);
  }

  // 2. Scan outputsDir for .archipelago or .multidata files
  const files = fs.readdirSync(outputsDir);
  let multidataFile = '';
  for (const file of files) {
    if (file.endsWith('.archipelago') || file.endsWith('.multidata')) {
      multidataFile = file;
      break;
    }
  }

  if (!multidataFile) {
    throw new Error('No .archipelago or .multidata file found in generation outputs.');
  }

  const multidataPath = path.join(outputsDir, multidataFile);
  const saveFilePath = path.join(outputsDir, `${roomCode}.apsave`);
  const port = await getFreePort(AP_START_PORT);
  const publicHost = process.env.PUBLIC_HOST || 'localhost';

  let roomServerIp: string | null = null;
  try {
    const room = db.prepare("SELECT server_ip FROM Rooms WHERE code = ?").get(roomCode) as { server_ip?: string | null } | undefined;
    roomServerIp = room?.server_ip || null;
  } catch {}

  const serverHost = (roomServerIp && roomServerIp.trim()) ? roomServerIp.trim() : publicHost;
  let serverAddress = `${serverHost}:${port}`;

  // Determine tunnel_url: if public domain or cloudflare tunnel is active, route through WSS proxy on port 443
  // If HOSTING_MODE=direct or custom roomServerIp is specified, route directly to host IP & port (dedicated server mode)
  let tunnelUrl = `ws://${publicHost}:${port}`;
  const publicDomain = process.env.PUBLIC_DOMAIN || 
    (process.env.PUBLIC_URL ? new URL(process.env.PUBLIC_URL.includes('://') ? process.env.PUBLIC_URL : `https://${process.env.PUBLIC_URL}`).host : null) || 
    (process.env.CLOUDFLARE_TUNNEL_TOKEN ? 'wayfinder.disaac1.com' : null);

  const hostingMode = (process.env.HOSTING_MODE || 'tunnel').trim().toLowerCase();
  const isDirectMode = hostingMode === 'direct' || Boolean(roomServerIp && roomServerIp.trim());

  if (!isDirectMode && publicDomain && !publicDomain.includes('localhost') && !publicDomain.includes('127.0.0.1')) {
    const portSuffix = publicDomain.includes(':') ? '' : ':443';
    tunnelUrl = `wss://${publicDomain}${portSuffix}/ap/${roomCode}`;
    serverAddress = tunnelUrl;
  } else {
    tunnelUrl = `ws://${serverHost}:${port}`;
    serverAddress = `${serverHost}:${port}`;
  }

  try {
    db.prepare("UPDATE Rooms SET server_port = ?, tunnel_url = ? WHERE code = ?").run(port, tunnelUrl, roomCode);
  } catch {}

  // Inject serverAddress into all patch files in outputsDir
  injectServerAddressIntoOutputs(outputsDir, serverAddress);

  const { exe: pythonExe, prefixArgs } = getPythonCommand();
  const multiServerScript = path.join(BACKEND_ROOT, 'archipelago_core', 'MultiServer.py');

  console.log(`Starting Central Archipelago Server for room ${roomCode} on port ${port} using ${pythonExe} ${prefixArgs.join(' ')}...`);
  const child = spawn(pythonExe, [
    ...prefixArgs,
    '-u',
    multiServerScript,
    '--port', port.toString(),
    '--use_embedded_options',
    '--savefile', saveFilePath,
    multidataPath
  ], {
    cwd: path.join(BACKEND_ROOT, 'archipelago_core'),
    env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1', PYTHONUNBUFFERED: '1' }
  });

  if (child.stdin) {
    child.stdin.on('error', (err) => {
      console.warn(`[AP Server ${roomCode}] stdin error:`, err.message);
    });
  }

  const statusInterval = setInterval(() => {
    const server = activeServers.get(roomCode);
    if (server && server.child && server.child.stdin && !server.child.stdin.destroyed) {
      try {
        server.child.stdin.write('/status\n');
      } catch (err: any) {
        console.warn(`[AP Server ${roomCode}] Stdin write error:`, err.message);
      }
    }
  }, 20000);

  activeServers.set(roomCode, { child, port, saveFilePath, statusInterval });

  // Initialize checks metadata immediately
  fetchRoomChecks(roomCode).then((checks) => {
    if (checks) {
      if (onChecksBroadcast) {
        onChecksBroadcast(roomCode);
      }
      if (onRoomStateBroadcast) {
        onRoomStateBroadcast(roomCode);
      }
    }
  });

  child.stdout.on('data', (data) => {
    const text = data.toString();
    const cleanText = text.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');

    // Filter routine /status spam from console output and server log broadcasts
    const rawLines: string[] = cleanText.split(/\r?\n/).map((l: string) => l.trim()).filter(Boolean);
    const nonStatusLines = rawLines.filter((l: string) => 
      !l.startsWith('Player Status on team') &&
      !/has\s+\d+\s+connection[s]?.*?\s+\(\d+\/\d+\)/.test(l) &&
      !l.startsWith('/status')
    );

    if (nonStatusLines.length > 0) {
      const filteredMsg = nonStatusLines.join('\n');
      console.log(`[AP Server ${roomCode}]: ${filteredMsg}`);
      if (onServerLogBroadcast) {
        onServerLogBroadcast(roomCode, filteredMsg);
      }
    }

    // If an item was found or sent, immediately request status update without waiting for timer
    if (/found their|sent .* to|collected|received/i.test(cleanText)) {
      const server = activeServers.get(roomCode);
      if (server && server.child && server.child.stdin && !server.child.stdin.destroyed) {
        try {
          server.child.stdin.write('/status\n');
        } catch {}
      }
    }

    // Parse status output: PlayerName has N connections. (checked/total)
    const statusRegex = /^\s*(.+?)\s+has\s+\d+\s+connection[s]?.*?\s+\((\d+)\/(\d+)\)/gm;
    let match;
    let changed = false;
    while ((match = statusRegex.exec(cleanText)) !== null) {
      const [, pName, checkedStr, totalStr] = match;
      const checked = parseInt(checkedStr, 10);
      const total = parseInt(totalStr, 10);
      const cleanName = pName.trim();
      const checks = roomChecksCache.get(roomCode);
      if (checks) {
        let pKey = cleanName;
        if (!checks.players[pKey]) {
          // Fallback matching if slot name has suffix/prefix (e.g. "Isaac (Emerald)" vs "Isaac")
          const found = Object.keys(checks.players).find(k =>
            k.toLowerCase() === cleanName.toLowerCase() ||
            k.toLowerCase().startsWith(cleanName.toLowerCase() + ' ') ||
            cleanName.toLowerCase().startsWith(k.toLowerCase() + ' ')
          );
          if (found) {
            pKey = found;
          }
        }

        if (!checks.players[pKey]) {
          checks.players[pKey] = { checked, total, game: 'Unknown' };
          changed = true;
        } else if (checks.players[pKey].checked !== checked || checks.players[pKey].total !== total) {
          checks.players[pKey].checked = checked;
          checks.players[pKey].total = total;
          changed = true;
        }
      }
    }
    if (changed) {
      recalculateRoomChecks(roomCode);
      touchRoomActivity(roomCode);
      if (onChecksBroadcast) {
        onChecksBroadcast(roomCode);
      }
      if (onRoomStateBroadcast) {
        onRoomStateBroadcast(roomCode);
      }
    }
  });

  child.stderr.on('data', (data) => {
    const errText = data.toString().trim();
    console.error(`[AP Server ${roomCode} Error]: ${errText}`);
    if (onServerLogBroadcast && errText) {
      onServerLogBroadcast(roomCode, `[ERROR] ${errText}`);
    }
  });

  child.on('close', (code) => {
    console.log(`AP Server for room ${roomCode} exited with code ${code}`);
    clearInterval(statusInterval);
    activeServers.delete(roomCode);
  });

  // Broadcast updated room state
  if (onRoomStateBroadcast) {
    onRoomStateBroadcast(roomCode);
  }
}

/**
 * Resolves the local port for a given room code or port identifier
 */
export function getRoomPort(roomIdentifier: string): number | null {
  const cleanId = roomIdentifier.trim().toUpperCase();
  const server = activeServers.get(cleanId);
  if (server && server.port) {
    return server.port;
  }
  const numericPort = parseInt(cleanId, 10);
  if (!isNaN(numericPort) && numericPort >= 1024 && numericPort <= 65535) {
    return numericPort;
  }
  try {
    const row = db.prepare("SELECT server_port FROM Rooms WHERE code = ?").get(cleanId) as { server_port?: number } | undefined;
    if (row && row.server_port) {
      return row.server_port;
    }
  } catch {}
  return null;
}
