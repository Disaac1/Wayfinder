import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import multer from 'multer';
import express from 'express';
import AdmZip from 'adm-zip';
import db, { touchRoomActivity } from './db.js';
import { getValidatedRoomCode } from './utils.js';
import { activeServers, killRoomServer } from './serverManager.js';
import { roomChecksCache, fetchRoomChecks } from './checksService.js';
import { broadcastRoomState } from './roomManager.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const sessionUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 } // 50MB
});

const router = Router();

// 1. Session details query
router.get('/:id', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format.' });
  }
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

// 2. Query player assigned games
router.get('/:id/games', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format.' });
  }
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

// 3. MultiServer status
router.get('/:id/server', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format.' });
  }
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

// 4. Session Checks & Location Progress
router.get('/:id/checks', async (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format.' });
  }
  let checks = roomChecksCache.get(roomCode);
  if (!checks) {
    checks = (await fetchRoomChecks(roomCode)) || undefined;
  }
  if (!checks) {
    return res.json({
      totalChecked: 0,
      totalLocations: 0,
      games: {},
      players: {}
    });
  }
  res.json(checks);
});

// 5. Checkout save file
router.get('/:id/checkout', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format' });
  }
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
  touchRoomActivity(roomCode);

  const outputsDir = path.join(__dirname, '../temp_seeds', roomCode, 'outputs');
  const saveFilePath = path.join(outputsDir, `${roomCode}.apsave`);

  if (!fs.existsSync(saveFilePath)) {
    // Session is locked successfully, but there is no save file yet
    broadcastRoomState(roomCode);
    return res.json({ success: true, message: 'Session locked; no save file exists yet' });
  }

  // Stop the central room server process if it is running to release file locks
  killRoomServer(roomCode);

  try {
    const zip = new AdmZip();
    zip.addLocalFile(saveFilePath, '', `${roomCode}.apsave`);
    const zipBuffer = zip.toBuffer();

    broadcastRoomState(roomCode);

    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Disposition', `attachment; filename="${roomCode}_save.zip"`);
    res.send(zipBuffer);
  } catch (err: any) {
    console.error(`Failed to package save file:`, err);
    res.status(500).json({ error: `Failed to compress save file: ${err.message}` });
  }
});

// 6. Checkin save file (raw application/zip or multipart)
router.post('/:id/checkin', (req: Request, res: Response, next) => {
  if (req.headers['content-type'] === 'application/zip') {
    express.raw({ type: 'application/zip', limit: '50mb' })(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message });
      (req as any).file = {
        buffer: req.body,
        originalname: `${req.params.id}.zip`
      };
      next();
    });
  } else {
    sessionUpload.single('file')(req, res, next);
  }
}, (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format' });
  }
  const userId = req.query.userId as string;

  if (!userId) {
    return res.status(400).json({ error: 'userId query parameter is required' });
  }
  const uploadedFile = (req as any).file;
  if (!uploadedFile) {
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

  try {
    const zip = new AdmZip(uploadedFile.buffer);
    const zipEntries = zip.getEntries();
    const targetEntry = zipEntries.find(e => 
      !e.isDirectory && path.basename(e.entryName) === `${roomCode}.apsave`
    );

    if (!targetEntry) {
      return res.status(400).json({ error: `Archive does not contain ${roomCode}.apsave` });
    }

    const savePath = path.join(outputsDir, `${roomCode}.apsave`);
    if (fs.existsSync(savePath)) {
      const backupsDir = path.join(outputsDir, 'backups');
      if (!fs.existsSync(backupsDir)) {
        fs.mkdirSync(backupsDir, { recursive: true });
      }
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      fs.copyFileSync(savePath, path.join(backupsDir, `${roomCode}_${timestamp}.apsave`));
      
      // Retain up to 5 rolling snapshots
      const allBackups = fs.readdirSync(backupsDir).filter(f => f.endsWith('.apsave')).sort();
      while (allBackups.length > 5) {
        const oldest = allBackups.shift();
        if (oldest) fs.unlinkSync(path.join(backupsDir, oldest));
      }
    }
    fs.writeFileSync(savePath, targetEntry.getData());
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
  touchRoomActivity(roomCode);

  broadcastRoomState(roomCode);
  res.json({ success: true });
});

// 7. Force unlock
const handleUnlock = (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.id);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format' });
  }
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
  touchRoomActivity(roomCode);

  broadcastRoomState(roomCode);
  res.json({ success: true });
};

router.post('/:id/unlock', handleUnlock);
router.post('/:id/force-unlock', handleUnlock);

export default router;
