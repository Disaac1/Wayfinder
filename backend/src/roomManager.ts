import { WebSocket } from 'ws';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { spawn, ChildProcess, execSync } from 'child_process';
import net from 'net';
import db from './db.js';
import { PlayerState, ClientMessage, ServerMessage } from './types.js';
import { generateSeed } from './archipelagoRunner.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.join(__dirname, '..');

// Character set for 6-digit room codes (excluding confusing characters: 0, 1, I, O, L)
const ROOM_CODE_CHARACTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// Map of userId -> active WebSocket connection
const activeConnections = new Map<string, WebSocket>();

// Map of WebSocket -> metadata (userId and roomCode)
const connectionMetadata = new Map<WebSocket, { userId: string; roomCode: string }>();

// Registry of active Archipelago Server processes by room code
interface ActiveServer {
  child: ChildProcess;
  port: number;
  saveFilePath: string;
}
export const activeServers = new Map<string, ActiveServer>();

/**
 * Find a free TCP port recursively starting from startPort
 */
function getFreePort(startPort: number = 38000): Promise<number> {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.on('error', () => {
      resolve(getFreePort(startPort + 1));
    });
    server.listen(startPort, () => {
      server.close(() => {
        resolve(startPort);
      });
    });
  });
}

/**
 * Kill Archipelago server process for a given room
 */
export function killRoomServer(roomCode: string) {
  const server = activeServers.get(roomCode);
  if (server) {
    console.log(`Killing Archipelago server process for room ${roomCode}...`);
    try {
      server.child.kill();
    } catch (e) {
      console.error(`Failed to kill server process for room ${roomCode}:`, e);
    }
    activeServers.delete(roomCode);
  }
}

/**
 * Launch local Archipelago MultiServer process for a room
 */
export async function startCentralServer(roomCode: string, zipName: string) {
  killRoomServer(roomCode);

  const outputsDir = path.join(BACKEND_ROOT, 'temp_seeds', roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    throw new Error(`Outputs directory not found for room ${roomCode}`);
  }

  // 1. Extract the seed zip file contents directly into the outputs directory using Python zipfile
  const zipPath = path.join(outputsDir, zipName);
  try {
    const safeZipPath = zipPath.replace(/\\/g, '/');
    const safeOutputsDir = outputsDir.replace(/\\/g, '/');
    const pythonCmd = `python -c "import zipfile; zipfile.ZipFile(r'${safeZipPath}').extractall(r'${safeOutputsDir}')"`;
    console.log(`Extracting seed archive for room ${roomCode}: ${zipPath}`);
    execSync(pythonCmd, {
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    });
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
  const port = await getFreePort(38000);

  const pythonExe = 'python';
  const multiServerScript = path.join(BACKEND_ROOT, 'archipelago_core', 'MultiServer.py');

  console.log(`Starting Central Archipelago Server for room ${roomCode} on port ${port}...`);
  const child = spawn(pythonExe, [
    multiServerScript,
    '--port', port.toString(),
    '--use_embedded_options',
    '--savefile', saveFilePath,
    multidataPath
  ], {
    env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
  });

  activeServers.set(roomCode, { child, port, saveFilePath });

  child.stdout.on('data', (data) => {
    console.log(`[AP Server ${roomCode}]: ${data.toString().trim()}`);
  });
  child.stderr.on('data', (data) => {
    console.error(`[AP Server ${roomCode} Error]: ${data.toString().trim()}`);
  });

  child.on('close', (code) => {
    console.log(`AP Server for room ${roomCode} exited with code ${code}`);
    activeServers.delete(roomCode);
  });

  // Update room table with tunnel_url = ws://localhost:PORT
  const tunnelUrl = `ws://localhost:${port}`;
  db.prepare("UPDATE Rooms SET tunnel_url = ? WHERE code = ?").run(tunnelUrl, roomCode);
  
  // Broadcast updated room state
  broadcastRoomState(roomCode);
}

/**
 * Ensure the server process is active if the room has a generated seed
 */
async function ensureServerRunning(roomCode: string) {
  if (activeServers.has(roomCode)) {
    return;
  }
  
  // Check if session is locked/checked out
  const session = db.prepare("SELECT locked_by FROM Sessions WHERE room_code = ?").get(roomCode) as { locked_by: string | null } | undefined;
  if (session && session.locked_by) {
    console.log(`Archipelago session for room ${roomCode} is currently checked out by ${session.locked_by}. Auto-start skipped.`);
    return;
  }

  const room = db.prepare("SELECT seed_status, seed_zip_name FROM Rooms WHERE code = ?").get(roomCode) as { seed_status: string; seed_zip_name: string | null } | undefined;
  if (room && room.seed_status === 'done' && room.seed_zip_name) {
    console.log(`Archipelago server is not running for room ${roomCode} but seed is done. Auto-starting...`);
    try {
      await startCentralServer(roomCode, room.seed_zip_name);
    } catch (e) {
      console.error(`Failed to automatically start server for room ${roomCode}:`, e);
    }
  }
}

/**
 * Generate a unique 6-character room code
 */
function generateRoomCode(): string {
  let code = '';
  const len = ROOM_CODE_CHARACTERS.length;
  // Try generating a unique code up to 10 times
  for (let attempt = 0; attempt < 10; attempt++) {
    code = '';
    for (let i = 0; i < 6; i++) {
      code += ROOM_CODE_CHARACTERS.charAt(Math.floor(Math.random() * len));
    }
    // Check if code is already in use
    const exists = db.prepare('SELECT 1 FROM Rooms WHERE code = ?').get(code);
    if (!exists) {
      return code;
    }
  }
  throw new Error('Failed to generate a unique room code');
}

/**
 * Helper to fetch and format the current room state (list of players)
 */
function getRoomState(roomCode: string): PlayerState[] {
  const room = db.prepare('SELECT host_id FROM Rooms WHERE code = ?').get(roomCode) as { host_id: string } | undefined;
  if (!room) return [];

  const users = db.prepare('SELECT id, name, games, is_ready, is_connected, yaml FROM Users WHERE room_code = ?').all(roomCode) as Array<{
    id: string;
    name: string;
    games: string;
    is_ready: number;
    is_connected: number;
    yaml: string | null;
  }>;

  return users.map((u) => {
    let parsedGames: string[] = [];
    try {
      parsedGames = JSON.parse(u.games || '[]');
    } catch (e) {
      parsedGames = [];
    }
    return {
      userId: u.id,
      name: u.name,
      games: parsedGames,
      isReady: u.is_ready === 1,
      isConnected: u.is_connected === 1,
      isHost: u.id === room.host_id,
      yaml: u.yaml,
    };
  });
}

/**
 * Broadcast general message to all connected players in a room
 */
function broadcastToRoom(roomCode: string, message: ServerMessage) {
  const payload = JSON.stringify(message);
  const players = getRoomState(roomCode);
  const roomUserIds = players.filter((p) => p.isConnected).map((p) => p.userId);
  for (const userId of roomUserIds) {
    const ws = activeConnections.get(userId);
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(payload);
    }
  }
}

export function broadcastRoomState(roomCode: string) {
  const room = db.prepare("SELECT seed_status, seed_zip_name, seed_spoiler_name, tunnel_url FROM Rooms WHERE code = ?").get(roomCode) as {
    seed_status: 'idle' | 'generating' | 'done';
    seed_zip_name: string | null;
    seed_spoiler_name: string | null;
    tunnel_url: string | null;
  } | undefined;

  const session = db.prepare("SELECT locked_by FROM Sessions WHERE room_code = ?").get(roomCode) as { locked_by: string | null } | undefined;
  const lockedBy = session ? session.locked_by : null;

  const players = getRoomState(roomCode);
  broadcastToRoom(roomCode, {
    type: 'room_state',
    roomCode,
    players,
    seedStatus: room ? room.seed_status : 'idle',
    seedZipName: room ? room.seed_zip_name : null,
    seedSpoilerName: room ? room.seed_spoiler_name : null,
    tunnelUrl: room ? room.tunnel_url : null,
    lockedBy: lockedBy,
  });
}

/**
 * Sends a JSON message to a specific socket
 */
function sendToSocket(ws: WebSocket, message: ServerMessage) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

/**
 * Handle host seed generation request
 */
async function handleGenerateSeed(ws: WebSocket) {
  const meta = connectionMetadata.get(ws);
  if (!meta) {
    return sendToSocket(ws, { type: 'error', message: 'Not connected to a room' });
  }

  const { userId, roomCode } = meta;

  // 1. Verify user is the host and room is not already generating
  const room = db.prepare("SELECT host_id, seed_status FROM Rooms WHERE code = ?").get(roomCode) as { host_id: string, seed_status: string } | undefined;
  if (!room) {
    return sendToSocket(ws, { type: 'error', message: 'Room not found' });
  }
  if (room.host_id !== userId) {
    return sendToSocket(ws, { type: 'error', message: 'Only the host can generate the seed' });
  }
  if (room.seed_status === 'generating') {
    return sendToSocket(ws, { type: 'error', message: 'Seed generation is already in progress for this room' });
  }
  if (room.seed_status === 'done') {
    return sendToSocket(ws, { type: 'error', message: 'Seed has already been generated and locked for this room' });
  }

  // 2. Retrieve all players in room
  const players = getRoomState(roomCode);
  if (players.length === 0) {
    return sendToSocket(ws, { type: 'error', message: 'Lobby has no players' });
  }

  // 3. Verify all players are ready
  const unready = players.filter(p => !p.isReady);
  if (unready.length > 0) {
    return sendToSocket(ws, { type: 'error', message: 'Cannot generate: waiting for all players to be ready' });
  }

  try {
    // 4. Update room status to generating
    db.prepare("UPDATE Rooms SET seed_status = 'generating' WHERE code = ?").run(roomCode);
    console.log(`Room ${roomCode} seed status updated to generating.`);
    broadcastRoomState(roomCode);

    // 5. Gather player YAMLs
    const playersYamls = db.prepare("SELECT name, yaml FROM Users WHERE room_code = ?").all(roomCode) as Array<{ name: string, yaml: string }>;

    // 6. Invoke generator
    const { zipName, spoilerName } = await generateSeed(roomCode, playersYamls, (line) => {
      broadcastToRoom(roomCode, { type: 'generation_log', line });
    });

    // 7. Update status to done
    db.prepare("UPDATE Rooms SET seed_status = 'done', seed_zip_name = ?, seed_spoiler_name = ? WHERE code = ?").run(
      zipName,
      spoilerName,
      roomCode
    );

    // Start Central Archipelago Server for the room
    await startCentralServer(roomCode, zipName);

    console.log(`Room ${roomCode} seed generation completed successfully.`);
  } catch (error: any) {
    console.error(`Seed generation failed for room ${roomCode}:`, error);
    
    // Save generation log to error folder for review
    try {
      const failedGenDir = path.join(BACKEND_ROOT, 'failed_generations');
      if (!fs.existsSync(failedGenDir)) {
        fs.mkdirSync(failedGenDir, { recursive: true });
      }
      const tempLogPath = path.join(BACKEND_ROOT, 'temp_seeds', roomCode, 'outputs', 'generation.log');
      if (fs.existsSync(tempLogPath)) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const destLogPath = path.join(failedGenDir, `failed_${roomCode}_${timestamp}.log`);
        fs.copyFileSync(tempLogPath, destLogPath);
        console.log(`Failed generation log copied to: ${destLogPath}`);
      }
    } catch (logErr) {
      console.error('Failed to copy error logs:', logErr);
    }

    db.prepare("UPDATE Rooms SET seed_status = 'idle' WHERE code = ?").run(roomCode);
    broadcastRoomState(roomCode);
    sendToSocket(ws, { type: 'error', message: `Generation failed: ${error.message}` });
  }
}

/**
 * Handles incoming WebSocket connection messages
 */
export function handleConnection(ws: WebSocket) {
  console.log('New WebSocket connection established.');

  ws.on('message', (rawData) => {
    try {
      const data: ClientMessage = JSON.parse(rawData.toString());
      console.log('Received message:', data);

      switch (data.type) {
        case 'create_room':
          handleCreateRoom(ws, data.playerName);
          break;

        case 'join_room':
          handleJoinRoom(ws, data.roomCode.toUpperCase(), data.playerName);
          break;

        case 'reconnect':
          handleReconnect(ws, data.userId, data.roomCode.toUpperCase());
          break;

        case 'update_state':
          handleUpdateState(ws, data.games, data.isReady, data.yaml);
          break;

        case 'generate_seed':
          handleGenerateSeed(ws);
          break;

        default:
          sendToSocket(ws, { type: 'error', message: 'Unknown message type' });
      }
    } catch (error: any) {
      console.error('Error handling WebSocket message:', error);
      sendToSocket(ws, { type: 'error', message: 'Invalid message format or server error' });
    }
  });

  ws.on('close', () => {
    handleDisconnect(ws);
  });

  ws.on('error', (err) => {
    console.error('WebSocket connection error:', err);
    handleDisconnect(ws);
  });
}

/**
 * Create a new room and join as host
 */
function handleCreateRoom(ws: WebSocket, playerName: string) {
  if (!playerName || playerName.trim() === '') {
    return sendToSocket(ws, { type: 'error', message: 'Player name is required' });
  }

  const roomCode = generateRoomCode();
  const userId = uuidv4();

  const transaction = db.transaction(() => {
    // 1. Create the room
    db.prepare('INSERT INTO Rooms (code, host_id) VALUES (?, ?)').run(roomCode, userId);

    // 2. Add user to database
    db.prepare('INSERT INTO Users (id, room_code, name, is_connected) VALUES (?, ?, ?, 1)').run(
      userId,
      roomCode,
      playerName.trim()
    );

    // 3. Initialize session state
    db.prepare('INSERT INTO Sessions (room_code) VALUES (?)').run(roomCode);
  });

  try {
    transaction();

    // Map connections
    activeConnections.set(userId, ws);
    connectionMetadata.set(ws, { userId, roomCode });

    console.log(`Room ${roomCode} created by host ${playerName} (${userId})`);

    // Acknowledge creation
    sendToSocket(ws, { type: 'room_created', roomCode, userId });

    // Send initial room state
    broadcastRoomState(roomCode);
  } catch (error: any) {
    console.error('Transaction failed while creating room:', error);
    sendToSocket(ws, { type: 'error', message: 'Failed to create room' });
  }
}

/**
 * Join an existing room
 */
function handleJoinRoom(ws: WebSocket, roomCode: string, playerName: string) {
  if (!playerName || playerName.trim() === '') {
    return sendToSocket(ws, { type: 'error', message: 'Player name is required' });
  }

  // 1. Verify room exists
  const room = db.prepare("SELECT code FROM Rooms WHERE code = ? AND status = 'active'").get(roomCode);
  if (!room) {
    return sendToSocket(ws, { type: 'error', message: `Room ${roomCode} not found or inactive` });
  }

  // Ensure Archipelago server is running if seed is done
  ensureServerRunning(roomCode).catch(e => console.error("ensureServerRunning failed:", e));

  // 2. Verify name unique in this room (among connected or disconnected players)
  const existingUser = db.prepare('SELECT id, is_connected FROM Users WHERE room_code = ? AND name = ? COLLATE NOCASE').get(roomCode, playerName.trim()) as { id: string; is_connected: number } | undefined;
  
  if (existingUser) {
    if (existingUser.is_connected === 1) {
      return sendToSocket(ws, { type: 'error', message: `Name "${playerName}" is already taken and actively connected in room ${roomCode}` });
    }
    
    // Take over disconnected player session
    const userId = existingUser.id;
    try {
      db.prepare('UPDATE Users SET is_connected = 1 WHERE id = ?').run(userId);
      activeConnections.set(userId, ws);
      connectionMetadata.set(ws, { userId, roomCode });
      
      console.log(`Player ${playerName} (${userId}) took over disconnected slot in room ${roomCode}`);
      
      const roomInfo = db.prepare("SELECT seed_status, seed_zip_name, seed_spoiler_name FROM Rooms WHERE code = ?").get(roomCode) as {
        seed_status: 'idle' | 'generating' | 'done';
        seed_zip_name: string | null;
        seed_spoiler_name: string | null;
      } | undefined;
      const players = getRoomState(roomCode);
      sendToSocket(ws, {
        type: 'room_joined',
        roomCode,
        userId,
        players,
        seedStatus: roomInfo ? roomInfo.seed_status : 'idle',
        seedZipName: roomInfo ? roomInfo.seed_zip_name : null,
        seedSpoilerName: roomInfo ? roomInfo.seed_spoiler_name : null
      });
      broadcastRoomState(roomCode);
      return;
    } catch (error: any) {
      console.error('Failed to take over slot:', error);
      return sendToSocket(ws, { type: 'error', message: 'Failed to join room' });
    }
  }

  const userId = uuidv4();

  try {
    // Insert new user
    db.prepare('INSERT INTO Users (id, room_code, name, is_connected) VALUES (?, ?, ?, 1)').run(
      userId,
      roomCode,
      playerName.trim()
    );

    // Map connections
    activeConnections.set(userId, ws);
    connectionMetadata.set(ws, { userId, roomCode });

    console.log(`Player ${playerName} (${userId}) joined room ${roomCode}`);

    // Acknowledge join
    const roomInfo = db.prepare("SELECT seed_status, seed_zip_name, seed_spoiler_name FROM Rooms WHERE code = ?").get(roomCode) as {
      seed_status: 'idle' | 'generating' | 'done';
      seed_zip_name: string | null;
      seed_spoiler_name: string | null;
    } | undefined;
    const players = getRoomState(roomCode);
    sendToSocket(ws, {
      type: 'room_joined',
      roomCode,
      userId,
      players,
      seedStatus: roomInfo ? roomInfo.seed_status : 'idle',
      seedZipName: roomInfo ? roomInfo.seed_zip_name : null,
      seedSpoilerName: roomInfo ? roomInfo.seed_spoiler_name : null
    });

    // Notify other players
    broadcastRoomState(roomCode);
  } catch (error: any) {
    console.error('Failed to join room:', error);
    sendToSocket(ws, { type: 'error', message: 'Failed to join room' });
  }
}

/**
 * Reconnect to an existing session using userId
 */
function handleReconnect(ws: WebSocket, userId: string, roomCode: string) {
  // Check database for existing player in that room
  const user = db.prepare('SELECT id, name, room_code FROM Users WHERE id = ? AND room_code = ?').get(userId, roomCode) as {
    id: string;
    name: string;
    room_code: string;
  } | undefined;

  if (!user) {
    return sendToSocket(ws, { type: 'error', message: 'Session details not found' });
  }

  // Ensure Archipelago server is running if seed is done
  ensureServerRunning(roomCode).catch(e => console.error("ensureServerRunning failed:", e));

  try {
    // If there was an old connection, disconnect it
    const oldWs = activeConnections.get(userId);
    if (oldWs && oldWs !== ws) {
      console.log(`Closing stale socket connection for user ${userId}`);
      connectionMetadata.delete(oldWs);
      oldWs.close();
    }

    // Update connection status
    db.prepare('UPDATE Users SET is_connected = 1 WHERE id = ?').run(userId);

    // Map connection
    activeConnections.set(userId, ws);
    connectionMetadata.set(ws, { userId, roomCode });

    console.log(`Player ${user.name} (${userId}) reconnected to room ${roomCode}`);

    // Send room joined status to client
    const roomInfo = db.prepare("SELECT seed_status, seed_zip_name, seed_spoiler_name FROM Rooms WHERE code = ?").get(roomCode) as {
      seed_status: 'idle' | 'generating' | 'done';
      seed_zip_name: string | null;
      seed_spoiler_name: string | null;
    } | undefined;
    const players = getRoomState(roomCode);
    sendToSocket(ws, {
      type: 'room_joined',
      roomCode,
      userId,
      players,
      seedStatus: roomInfo ? roomInfo.seed_status : 'idle',
      seedZipName: roomInfo ? roomInfo.seed_zip_name : null,
      seedSpoilerName: roomInfo ? roomInfo.seed_spoiler_name : null
    });

    // Notify others
    broadcastRoomState(roomCode);
  } catch (error: any) {
    console.error('Failed to reconnect player:', error);
    sendToSocket(ws, { type: 'error', message: 'Failed to reconnect session' });
  }
}

/**
 * Update player ready status and game selection
 */
function handleUpdateState(ws: WebSocket, games: string[], isReady: boolean, yaml: string | null) {
  const meta = connectionMetadata.get(ws);
  if (!meta) {
    return sendToSocket(ws, { type: 'error', message: 'Not connected to a room' });
  }

  const { userId, roomCode } = meta;

  // Verify room configuration is not locked
  const room = db.prepare("SELECT seed_status FROM Rooms WHERE code = ?").get(roomCode) as { seed_status: string } | undefined;
  if (room && room.seed_status === 'done') {
    return sendToSocket(ws, { type: 'error', message: 'Room configuration is locked after seed generation' });
  }

  try {
    const gamesJson = JSON.stringify(games || []);
    db.prepare('UPDATE Users SET games = ?, is_ready = ?, yaml = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').run(
      gamesJson,
      isReady ? 1 : 0,
      yaml,
      userId
    );

    console.log(`Player ${userId} in room ${roomCode} updated games to ${gamesJson}, ready: ${isReady}, yaml length: ${yaml ? yaml.length : 0}`);

    // Broadcast updated state to all room players
    broadcastRoomState(roomCode);
  } catch (error: any) {
    console.error('Failed to update player state:', error);
    sendToSocket(ws, { type: 'error', message: 'Failed to update ready state' });
  }
}

/**
 * Check if any game clients are currently connected to the AP server port
 */
export async function hasActiveTcpClients(port: number): Promise<boolean> {
  try {
    if (process.platform === 'win32') {
      const output = execSync(`netstat -ano | findstr :${port}`).toString();
      const lines = output.split('\n');
      for (const line of lines) {
        if (line.includes('ESTABLISHED')) {
          return true;
        }
      }
      return false;
    } else {
      const output = execSync(`netstat -an | grep :${port}`).toString();
      return output.includes('ESTABLISHED');
    }
  } catch (e) {
    return false;
  }
}

// Audit active AP servers every 30 seconds to clean up when both lobby users and AP clients disconnect
setInterval(async () => {
  for (const [roomCode, server] of activeServers.entries()) {
    const connectedCount = db.prepare("SELECT COUNT(*) as count FROM Users WHERE room_code = ? AND is_connected = 1").get(roomCode) as { count: number } | undefined;
    const lobbyConnected = connectedCount ? connectedCount.count > 0 : false;
    
    if (!lobbyConnected) {
      const hasClients = await hasActiveTcpClients(server.port);
      if (!hasClients) {
        console.log(`Periodic Cleanup: No lobby users or game clients connected to room ${roomCode} (port ${server.port}). Stopping AP server.`);
        killRoomServer(roomCode);
      }
    }
  }
}, 30000);

/**
 * Handle client disconnection
 */
function handleDisconnect(ws: WebSocket) {
  const meta = connectionMetadata.get(ws);
  if (!meta) return;

  const { userId, roomCode } = meta;

  // Clean up references
  connectionMetadata.delete(ws);
  if (activeConnections.get(userId) === ws) {
    activeConnections.delete(userId);
  }

  try {
    // Set user to disconnected
    db.prepare('UPDATE Users SET is_connected = 0 WHERE id = ?').run(userId);

    console.log(`Player ${userId} disconnected from room ${roomCode}`);

    // Broadcast update
    broadcastRoomState(roomCode);

    // If no players are actively connected, check if game clients are connected before killing server process
    const connectedCount = db.prepare("SELECT COUNT(*) as count FROM Users WHERE room_code = ? AND is_connected = 1").get(roomCode) as { count: number } | undefined;
    if (connectedCount && connectedCount.count === 0) {
      const server = activeServers.get(roomCode);
      if (server) {
        hasActiveTcpClients(server.port).then((hasClients) => {
          if (hasClients) {
            console.log(`Lobby users disconnected from room ${roomCode}, but game clients are still connected on port ${server.port}. Keeping AP server active.`);
          } else {
            killRoomServer(roomCode);
          }
        }).catch(() => {
          killRoomServer(roomCode);
        });
      } else {
        killRoomServer(roomCode);
      }
    }
  } catch (error: any) {
    console.error('Error during player disconnection cleanup:', error);
  }
}
