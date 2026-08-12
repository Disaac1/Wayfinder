import express from 'express';
import http from 'http';
import { WebSocketServer } from 'ws';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';

import { execSync } from 'child_process';
import { handleConnection, killRoomServer, activeServers, broadcastRoomState } from './roomManager.js';
import { ensureArchipelagoCore, getAvailableGames, getGameOptions, clearCache } from './archipelagoRunner.js';
import db from './db.js';
import adminRoutes, { localhostOnly } from './adminRoutes.js';

// Load environment variables
dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const CUSTOM_WORLDS_DIR = path.join(__dirname, '..', 'archipelago_core', 'custom_worlds');
const ADMIN_UI_DIR = path.join(__dirname, '..', 'public', 'admin');

const PORT = process.env.PORT || 8080;

const app = express();
app.use(express.json());

// Enable CORS for frontend requests if needed
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  next();
});

const PUBLIC_TOOLS_DIR = path.join(__dirname, '..', 'public', 'tools');

// Serve tools download directory
app.use('/tools', express.static(PUBLIC_TOOLS_DIR));

// Admin Web UI (Localhost restricted)
app.use('/admin', localhostOnly, express.static(ADMIN_UI_DIR));
app.use('/api/admin', adminRoutes);

// Configure Multer for APWorld uploads
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      cb(null, CUSTOM_WORLDS_DIR);
    },
    filename: (req, file, cb) => {
      // Preserve original name (e.g. game.apworld)
      cb(null, file.originalname);
    }
  }),
  fileFilter: (req, file, cb) => {
    if (file.originalname.endsWith('.apworld')) {
      cb(null, true);
    } else {
      cb(new Error('Only .apworld files are allowed'));
    }
  }
});

const sessionUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 } // 50MB
});

// --- REST Endpoints ---

// 1. Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// 2. Get list of available games
app.get('/api/games', async (req, res) => {
  const force = req.query.force === 'true';
  try {
    const games = await getAvailableGames(force);
    res.json({ games });
  } catch (error: any) {
    res.status(500).json({ error: error.message || 'Failed to fetch games list' });
  }
});

// 3. Get options schema for a specific game
app.get('/api/options/:gameName', async (req, res) => {
  const gameName = req.params.gameName;
  const force = req.query.force === 'true';
  try {
    const schema = await getGameOptions(gameName, force);
    res.json(schema);
  } catch (error: any) {
    res.status(500).json({ error: error.message || `Failed to fetch options for ${gameName}` });
  }
});

// 3b. Get game launcher & tools configuration
app.get('/api/launcher/config', (req, res) => {
  const configPath = path.join(__dirname, '..', 'data', 'game_launcher_config.json');
  if (fs.existsSync(configPath)) {
    const data = fs.readFileSync(configPath, 'utf8');
    res.json(JSON.parse(data));
  } else {
    res.status(404).json({ error: 'Launcher configuration file not found.' });
  }
});

// 3c. Direct REST HTTP API for querying session details
app.get('/api/session/:id', (req, res) => {
  const roomCode = req.params.id.toUpperCase();
  const room = db.prepare("SELECT code, host_id, seed_status, seed_zip_name, seed_spoiler_name, tunnel_url FROM Rooms WHERE code = ?").get(roomCode) as any;
  if (!room) {
    return res.status(404).json({ error: `Room ${roomCode} not found.` });
  }

  const session = db.prepare("SELECT locked_by, locked_at FROM Sessions WHERE room_code = ?").get(roomCode) as any;
  const users = db.prepare("SELECT id, name, games, is_ready, is_connected FROM Users WHERE room_code = ?").all(roomCode) as any[];

  const players = users.map((u) => {
    let parsedGames = [];
    try { parsedGames = JSON.parse(u.games || '[]'); } catch (e) { parsedGames = []; }
    return {
      userId: u.id,
      name: u.name,
      games: parsedGames,
      isReady: u.is_ready === 1,
      isConnected: u.is_connected === 1,
      isHost: u.id === room.host_id
    };
  });

  res.json({
    roomCode: room.code,
    seedStatus: room.seed_status,
    seedZipName: room.seed_zip_name,
    seedSpoilerName: room.seed_spoiler_name,
    tunnelUrl: room.tunnel_url,
    lockedBy: session ? session.locked_by : null,
    lockedAt: session ? session.locked_at : null,
    players
  });
});

// 3d. Direct REST HTTP API for querying player assigned games
app.get('/api/session/:id/games', (req, res) => {
  const roomCode = req.params.id.toUpperCase();
  const users = db.prepare("SELECT id, name, games FROM Users WHERE room_code = ?").all(roomCode) as any[];
  if (!users || users.length === 0) {
    return res.status(404).json({ error: `No active room or players found for ${roomCode}.` });
  }

  const result = users.map((u) => {
    let parsedGames = [];
    try { parsedGames = JSON.parse(u.games || '[]'); } catch (e) { parsedGames = []; }
    return {
      userId: u.id,
      name: u.name,
      games: parsedGames
    };
  });

  res.json({ roomCode, players: result });
});

// 3e. Direct REST HTTP API for MultiServer status
app.get('/api/session/:id/server', (req, res) => {
  const roomCode = req.params.id.toUpperCase();
  const room = db.prepare("SELECT seed_status, tunnel_url FROM Rooms WHERE code = ?").get(roomCode) as any;
  if (!room) {
    return res.status(404).json({ error: `Room ${roomCode} not found.` });
  }

  const server = activeServers.get(roomCode);
  res.json({
    roomCode,
    seedStatus: room.seed_status,
    serverActive: !!server,
    port: server ? server.port : 38000,
    tunnelUrl: room.tunnel_url
  });
});

// 3f. Direct REST HTTP API for querying active rooms list
app.get('/api/rooms', (req, res) => {
  try {
    const rows = db.prepare(`
      SELECT 
        r.code, 
        r.host_id,
        r.seed_status, 
        r.created_at, 
        u.name as host_name,
        (SELECT COUNT(*) FROM Users WHERE room_code = r.code) as player_count
      FROM Rooms r
      LEFT JOIN Users u ON r.code = u.room_code AND r.host_id = u.id
      ORDER BY r.created_at DESC
    `).all() as any[];

    const rooms = rows.map(r => ({
      code: r.code,
      hostName: r.host_name || 'Unknown Host',
      playerCount: r.player_count || 0,
      seedStatus: r.seed_status || 'idle',
      createdAt: r.created_at
    }));

    res.json({ rooms });
  } catch (error: any) {
    console.error('Failed to fetch rooms list:', error);
    res.status(500).json({ error: error.message || 'Failed to fetch rooms list' });
  }
});

// 3g. Delete room endpoint
const handleDeleteRoom = (req: express.Request, res: express.Response) => {
  const roomCode = req.params.code.toUpperCase();
  try {
    const room = db.prepare('SELECT code FROM Rooms WHERE code = ?').get(roomCode);
    if (!room) {
      return res.status(404).json({ error: `Room ${roomCode} not found` });
    }

    killRoomServer(roomCode);
    const tempSeedsDir = path.join(__dirname, '../temp_seeds', roomCode);
    if (fs.existsSync(tempSeedsDir)) {
      fs.rmSync(tempSeedsDir, { recursive: true, force: true });
    }

    db.prepare('DELETE FROM Rooms WHERE code = ?').run(roomCode);
    console.log(`Room ${roomCode} deleted via API.`);
    res.json({ success: true, roomCode });
  } catch (error: any) {
    console.error(`Failed to delete room ${roomCode}:`, error);
    res.status(500).json({ error: error.message || 'Failed to delete room' });
  }
};

app.delete('/api/rooms/:code', handleDeleteRoom);
app.post('/api/rooms/:code/delete', handleDeleteRoom);

// 4. Upload custom apworld file
app.post('/api/custom-worlds/upload', (req, res) => {
  upload.single('file')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }
    console.log(`Custom world uploaded successfully: ${req.file.filename}`);
    clearCache(); // invalidate options caching on file upload
    res.json({ success: true, filename: req.file.filename });
  });
});

// 5. Clear options and games cache manually
app.all('/api/cache/clear', (req, res) => {
  clearCache();
  res.json({ success: true, message: 'Caches cleared successfully' });
});

// Serve player-specific seed patch file directly to minimize download bandwidth
app.get('/api/seeds/:roomCode/player-patch', async (req, res) => {
  const { roomCode } = req.params;
  const playerName = (req.query.playerName as string || '').trim().toLowerCase();
  const gameName = (req.query.gameName as string || '').trim().toLowerCase();

  const outputsDir = path.join(__dirname, '..', 'temp_seeds', roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    return res.status(404).json({ error: `Seed output directory for room ${roomCode} not found.` });
  }

  const files = fs.readdirSync(outputsDir);
  let patchFile = '';

  // 1. Try matching both playerName and patch file extension/name in outputsDir
  for (const f of files) {
    if (f.endsWith('.zip') || f.endsWith('.txt') || f.endsWith('.json') || f.endsWith('.yaml') || f === 'generation.log') {
      continue;
    }
    const fLower = f.toLowerCase();
    if (playerName && fLower.includes(playerName)) {
      patchFile = f;
      break;
    }
  }

  // 2. If no direct match by player name, check by game extension/name
  if (!patchFile) {
    for (const f of files) {
      if (f.endsWith('.zip') || f.endsWith('.txt') || f.endsWith('.json') || f.endsWith('.yaml') || f === 'generation.log') {
        continue;
      }
      const fLower = f.toLowerCase();
      if (gameName.includes('emerald') || gameName.includes('pokemon')) {
        if (fLower.endsWith('.apemerald') || fLower.endsWith('.apgba')) {
          patchFile = f;
          break;
        }
      } else if (gameName.includes('zelda') || gameName.includes('past')) {
        if (fLower.endsWith('.apz3') || fLower.endsWith('.sfc')) {
          patchFile = f;
          break;
        }
      } else if (fLower.startsWith('ap_') || fLower.includes('.ap')) {
        patchFile = f;
        break;
      }
    }
  }

  // 3. If patch files are inside a .zip file in outputsDir and not yet extracted
  if (!patchFile) {
    const zipFile = files.find(f => f.endsWith('.zip'));
    if (zipFile) {
      const zipPath = path.join(outputsDir, zipFile);
      try {
        const { default: AdmZip } = await import('adm-zip');
        const zip = new AdmZip(zipPath);
        const zipEntries = zip.getEntries();
        let targetEntry: any = null;

        for (const entry of zipEntries) {
          const entryName = entry.entryName.toLowerCase();
          if (entryName.endsWith('.zip') || entryName.endsWith('.txt') || entryName.endsWith('.json') || entryName.endsWith('.yaml')) {
            continue;
          }
          if (playerName && entryName.includes(playerName)) {
            targetEntry = entry;
            break;
          }
        }

        if (!targetEntry) {
          for (const entry of zipEntries) {
            const entryName = entry.entryName.toLowerCase();
            if (entryName.endsWith('.zip') || entryName.endsWith('.txt') || entryName.endsWith('.json') || entryName.endsWith('.yaml')) {
              continue;
            }
            if (entryName.startsWith('ap_') || entryName.includes('.ap')) {
              targetEntry = entry;
              break;
            }
          }
        }

        if (targetEntry) {
          const extractedPath = path.join(outputsDir, path.basename(targetEntry.entryName));
          fs.writeFileSync(extractedPath, targetEntry.getData());
          console.log(`Extracted single player patch ${targetEntry.entryName} to ${extractedPath}`);
          return res.download(extractedPath, path.basename(targetEntry.entryName));
        }
      } catch (e: any) {
        console.error('Zip extraction error:', e);
      }
    }
  }

  if (patchFile) {
    const fullPath = path.join(outputsDir, patchFile);
    console.log(`Serving targeted player patch file: ${patchFile} for player '${playerName}' in room ${roomCode}`);
    return res.download(fullPath, patchFile);
  }

  res.status(404).json({ error: `Player patch file not found for player '${playerName}' in room ${roomCode}.` });
});

// 6. Serve generated seeds statically
app.use('/api/seeds', express.static(path.join(__dirname, '../temp_seeds')));

// 7. Cleanup route for integration tests
app.post('/api/test/cleanup', (req, res) => {
  const { roomCode } = req.body;
  if (!roomCode) {
    return res.status(400).json({ error: 'roomCode is required' });
  }

  try {
    killRoomServer(roomCode);
    const tempSeedsDir = path.join(__dirname, '../temp_seeds', roomCode);
    if (fs.existsSync(tempSeedsDir)) {
      fs.rmSync(tempSeedsDir, { recursive: true, force: true });
    }
    
    // Delete room from database (will cascade delete Users/Sessions)
    db.prepare('DELETE FROM Rooms WHERE code = ?').run(roomCode);
    
    console.log(`Test cleanup completed for room ${roomCode}`);
    res.json({ success: true });
  } catch (error: any) {
    console.error(`Failed to clean up room ${roomCode}:`, error);
    res.status(500).json({ error: error.message });
  }
});

// 8. Session Checkout Save File
app.get('/api/session/:id/checkout', (req, res) => {
  const roomCode = req.params.id;
  const userId = req.query.userId as string;

  if (!userId) {
    return res.status(400).json({ error: 'userId query parameter is required' });
  }

  // Verify player exists in the room
  const user = db.prepare('SELECT id FROM Users WHERE id = ? AND room_code = ?').get(userId, roomCode);
  if (!user) {
    return res.status(403).json({ error: 'User is not connected to this room' });
  }

  // Check lock status
  const session = db.prepare('SELECT locked_by FROM Sessions WHERE room_code = ?').get(roomCode) as { locked_by: string | null } | undefined;
  if (session && session.locked_by && session.locked_by !== userId) {
    return res.status(409).json({ error: `Session is currently checked out by another player: ${session.locked_by}` });
  }

  // Acquire lock in the database
  db.prepare(`
    INSERT INTO Sessions (room_code, locked_by, locked_at, updated_at)
    VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT(room_code) DO UPDATE SET
      locked_by = ?,
      locked_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
  `).run(roomCode, userId, userId);

  console.log(`User ${userId} checked out room ${roomCode}`);

  const outputsDir = path.join(__dirname, '../temp_seeds', roomCode, 'outputs');
  const saveFilePath = path.join(outputsDir, `${roomCode}.apsave`);
  const zipPath = path.join(outputsDir, `${roomCode}_checkout_save.zip`);

  if (!fs.existsSync(saveFilePath)) {
    // Session is locked successfully, but there is no save file yet
    broadcastRoomState(roomCode);
    return res.json({ success: true, message: 'Session locked; no save file exists yet' });
  }

  // Stop the central room server process if it is running to release file locks
  killRoomServer(roomCode);

  try {
    // Zip the save file using Python with forward slashes for cross-platform safety
    const safeZipPath = zipPath.replace(/\\/g, '/');
    const safeSavePath = saveFilePath.replace(/\\/g, '/');
    const pythonCmd = `python -c "import zipfile; z = zipfile.ZipFile(r'${safeZipPath}', 'w'); z.write(r'${safeSavePath}', '${roomCode}.apsave')"`;
    execSync(pythonCmd, {
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    });

    res.download(zipPath, `${roomCode}_save.zip`, (err) => {
      // Cleanup the temporary zip file after download finishes/aborts
      try {
        if (fs.existsSync(zipPath)) {
          fs.unlinkSync(zipPath);
        }
      } catch (e) {}
    });

    broadcastRoomState(roomCode);
  } catch (err: any) {
    console.error(`Failed to package save file:`, err);
    res.status(500).json({ error: `Failed to compress save file: ${err.message}` });
  }
});

// 9. Session Checkin Save File (handles both application/zip body and multipart uploads)
app.post('/api/session/:id/checkin', (req, res, next) => {
  if (req.headers['content-type'] === 'application/zip') {
    express.raw({ type: 'application/zip', limit: '50mb' })(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message });
      req.file = {
        buffer: req.body,
        originalname: `${req.params.id}.zip`
      } as any;
      next();
    });
  } else {
    sessionUpload.single('file')(req, res, next);
  }
}, (req, res) => {
  const roomCode = req.params.id;
  const userId = req.query.userId as string;

  if (!userId) {
    return res.status(400).json({ error: 'userId query parameter is required' });
  }
  if (!req.file) {
    return res.status(400).json({ error: 'No save file archive uploaded' });
  }

  const room = db.prepare('SELECT code FROM Rooms WHERE code = ?').get(roomCode);
  if (!room) {
    return res.status(404).json({ error: 'Room not found' });
  }

  // Verify that the user currently holds the session lock
  const session = db.prepare('SELECT locked_by FROM Sessions WHERE room_code = ?').get(roomCode) as { locked_by: string | null } | undefined;
  if (session && session.locked_by && session.locked_by !== userId) {
    return res.status(409).json({ error: `Session is locked by another player: ${session.locked_by}` });
  }

  const outputsDir = path.join(__dirname, '../temp_seeds', roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    fs.mkdirSync(outputsDir, { recursive: true });
  }

  const zipPath = path.join(outputsDir, `${roomCode}_uploaded_save.zip`);
  fs.writeFileSync(zipPath, req.file.buffer);

  try {
    // Extract using Python zipfile with forward slashes
    const safeZipPath = zipPath.replace(/\\/g, '/');
    const safeOutputsDir = outputsDir.replace(/\\/g, '/');
    const pythonCmd = `python -c "import zipfile; zipfile.ZipFile(r'${safeZipPath}').extractall(r'${safeOutputsDir}')"`;
    execSync(pythonCmd, {
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    });
    fs.unlinkSync(zipPath);
  } catch (err: any) {
    console.error('Failed to unpack save zip:', err);
    return res.status(500).json({ error: `Failed to extract save archive: ${err.message}` });
  }

  // Release lock
  db.prepare(`
    INSERT INTO Sessions (room_code, save_file_path, locked_by, locked_at, updated_at)
    VALUES (?, ?, NULL, NULL, CURRENT_TIMESTAMP)
    ON CONFLICT(room_code) DO UPDATE SET
      locked_by = NULL,
      locked_at = NULL,
      updated_at = CURRENT_TIMESTAMP
  `).run(roomCode, path.join(outputsDir, `${roomCode}.apsave`));

  console.log(`User ${userId} checked in save file for room ${roomCode}`);
  
  broadcastRoomState(roomCode);
  res.json({ success: true });
});

// 10. Session Force Unlock
app.post('/api/session/:id/unlock', (req, res) => {
  const roomCode = req.params.id;
  const userId = req.query.userId as string;

  const room = db.prepare('SELECT code FROM Rooms WHERE code = ?').get(roomCode);
  if (!room) {
    return res.status(404).json({ error: 'Room not found' });
  }

  db.prepare(`
    INSERT INTO Sessions (room_code, locked_by, locked_at, updated_at)
    VALUES (?, NULL, NULL, CURRENT_TIMESTAMP)
    ON CONFLICT(room_code) DO UPDATE SET
      locked_by = NULL,
      locked_at = NULL,
      updated_at = CURRENT_TIMESTAMP
  `).run(roomCode);

  console.log(`User ${userId || 'unknown'} force unlocked session for room ${roomCode}`);

  broadcastRoomState(roomCode);
  res.json({ success: true });
});

// Create HTTP server wrapping Express app
const server = http.createServer(app);

// Attach WebSocket Server
const wss = new WebSocketServer({ server });
wss.on('connection', (ws) => {
  handleConnection(ws);
});

// Initialize Archipelago core and start listening
async function startServer() {
  try {
    await ensureArchipelagoCore();
    
    server.listen(PORT, () => {
      console.log(`===============================================`);
      console.log(`  Wayfinder Lobby Backend running on port ${PORT}`);
      console.log(`  WebSocket URL: ws://localhost:${PORT}`);
      console.log(`  HTTP API URL:  http://localhost:${PORT}`);
      console.log(`===============================================`);
    });
  } catch (err) {
    console.error('Failed to initialize Archipelago core repository, aborting startup:', err);
    process.exit(1);
  }
}

startServer();

// Graceful shutdown
const shutdown = () => {
  console.log('Shutting down server...');
  
  // Kill all active Archipelago server processes
  for (const [roomCode, activeServer] of activeServers.entries()) {
    console.log(`Killing AP Server for room ${roomCode} during graceful shutdown...`);
    try {
      activeServer.child.kill();
    } catch (e) {}
  }
  activeServers.clear();

  server.close(() => {
    console.log('Server stopped.');
    process.exit(0);
  });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
