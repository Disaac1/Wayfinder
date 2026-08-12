import { Router, Request, Response, NextFunction } from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import multer from 'multer';
import db from './db.js';
import { activeServers, killRoomServer, broadcastRoomState } from './roomManager.js';
import { clearCache } from './archipelagoRunner.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.join(__dirname, '..');
const CUSTOM_WORLDS_DIR = path.join(BACKEND_ROOT, 'archipelago_core', 'custom_worlds');

/**
 * Middleware to restrict access strictly to localhost requests (127.0.0.1 or ::1)
 */
export function localhostOnly(req: Request, res: Response, next: NextFunction) {
  const remoteIp = req.socket.remoteAddress || req.ip || '';
  const hostHeader = req.headers.host || '';

  const isLocalIp =
    remoteIp === '127.0.0.1' ||
    remoteIp === '::1' ||
    remoteIp === '::ffff:127.0.0.1';

  const isLocalHostHeader =
    hostHeader.startsWith('localhost:') ||
    hostHeader === 'localhost' ||
    hostHeader.startsWith('127.0.0.1:') ||
    hostHeader === '127.0.0.1' ||
    hostHeader.startsWith('[::1]:') ||
    hostHeader === '[::1]';

  if (!isLocalIp || !isLocalHostHeader) {
    return res.status(403).json({
      error: 'Forbidden: Access to Web UI administration is strictly limited to localhost.'
    });
  }

  next();
}

const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      if (!fs.existsSync(CUSTOM_WORLDS_DIR)) {
        fs.mkdirSync(CUSTOM_WORLDS_DIR, { recursive: true });
      }
      cb(null, CUSTOM_WORLDS_DIR);
    },
    filename: (req, file, cb) => {
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

const router = Router();

// Apply localhost check to all admin routes
router.use(localhostOnly);

/**
 * GET /api/admin/overview
 * System vitals and aggregate metrics
 */
router.get('/overview', (req: Request, res: Response) => {
  try {
    const totalRooms = (db.prepare('SELECT COUNT(*) as count FROM Rooms').get() as any)?.count || 0;
    const activeRooms = (db.prepare("SELECT COUNT(*) as count FROM Rooms WHERE status = 'active'").get() as any)?.count || 0;
    const totalUsers = (db.prepare('SELECT COUNT(*) as count FROM Users').get() as any)?.count || 0;
    const connectedUsers = (db.prepare('SELECT COUNT(*) as count FROM Users WHERE is_connected = 1').get() as any)?.count || 0;
    const lockedSessions = (db.prepare('SELECT COUNT(*) as count FROM Sessions WHERE locked_by IS NOT NULL').get() as any)?.count || 0;

    let apWorldCount = 0;
    if (fs.existsSync(CUSTOM_WORLDS_DIR)) {
      apWorldCount = fs.readdirSync(CUSTOM_WORLDS_DIR).filter(f => f.endsWith('.apworld')).length;
    }

    res.json({
      status: 'online',
      uptimeSeconds: process.uptime(),
      memoryUsage: process.memoryUsage(),
      nodeVersion: process.version,
      stats: {
        totalRooms,
        activeRooms,
        totalUsers,
        connectedUsers,
        lockedSessions,
        activeServersCount: activeServers.size,
        apWorldCount
      }
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/admin/rooms
 * Detailed list of all rooms
 */
router.get('/rooms', (req: Request, res: Response) => {
  try {
    const rooms = db.prepare(`
      SELECT 
        r.code, 
        r.host_id, 
        r.status, 
        r.seed_status, 
        r.seed_zip_name, 
        r.seed_spoiler_name, 
        r.tunnel_url, 
        r.created_at,
        s.locked_by,
        s.locked_at
      FROM Rooms r
      LEFT JOIN Sessions s ON r.code = s.room_code
      ORDER BY r.created_at DESC
    `).all() as any[];

    const enrichedRooms = rooms.map(room => {
      const users = db.prepare(`
        SELECT id, name, games, is_ready, is_connected, updated_at 
        FROM Users 
        WHERE room_code = ?
      `).all(room.code) as any[];

      const isServerRunning = activeServers.has(room.code);
      const serverDetails = activeServers.get(room.code);

      return {
        ...room,
        isServerRunning,
        serverPort: serverDetails ? serverDetails.port : null,
        serverPid: serverDetails?.child ? serverDetails.child.pid : null,
        players: users.map(u => ({
          ...u,
          games: (() => {
            try { return JSON.parse(u.games || '[]'); } catch (e) { return []; }
          })(),
          isReady: u.is_ready === 1,
          isConnected: u.is_connected === 1,
          isHost: u.id === room.host_id
        }))
      };
    });

    res.json({ rooms: enrichedRooms });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/admin/rooms/:code/kill
 * Terminate Archipelago MultiServer process for room
 */
router.post('/rooms/:code/kill', (req: Request, res: Response) => {
  const code = req.params.code as string;
  try {
    if (!activeServers.has(code)) {
      return res.status(404).json({ error: `No active AP Server running for room ${code}` });
    }
    killRoomServer(code);
    broadcastRoomState(code);
    res.json({ success: true, message: `Terminated Archipelago server for room ${code}` });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/admin/rooms/:code/unlock
 * Force unlock save session lock
 */
router.post('/rooms/:code/unlock', (req: Request, res: Response) => {
  const code = req.params.code as string;
  try {
    db.prepare(`
      INSERT INTO Sessions (room_code, locked_by, locked_at, updated_at)
      VALUES (?, NULL, NULL, CURRENT_TIMESTAMP)
      ON CONFLICT(room_code) DO UPDATE SET
        locked_by = NULL,
        locked_at = NULL,
        updated_at = CURRENT_TIMESTAMP
    `).run(code);

    broadcastRoomState(code);
    res.json({ success: true, message: `Force unlocked session for room ${code}` });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /api/admin/rooms/:code
 * Delete room and remove temp files
 */
router.delete('/rooms/:code', (req: Request, res: Response) => {
  const code = req.params.code as string;
  try {
    killRoomServer(code);

    const tempSeedsDir = path.join(BACKEND_ROOT, 'temp_seeds', code);
    if (fs.existsSync(tempSeedsDir)) {
      fs.rmSync(tempSeedsDir, { recursive: true, force: true });
    }

    db.prepare('DELETE FROM Rooms WHERE code = ?').run(code);

    res.json({ success: true, message: `Deleted room ${code} and cleaned up assets.` });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/admin/custom-worlds
 * List custom .apworld files
 */
router.get('/custom-worlds', (req: Request, res: Response) => {
  try {
    if (!fs.existsSync(CUSTOM_WORLDS_DIR)) {
      return res.json({ files: [] });
    }
    const files = fs.readdirSync(CUSTOM_WORLDS_DIR)
      .filter(f => f.endsWith('.apworld'))
      .map(filename => {
        const filePath = path.join(CUSTOM_WORLDS_DIR, filename);
        const stat = fs.statSync(filePath);
        return {
          filename,
          sizeBytes: stat.size,
          modifiedAt: stat.mtime
        };
      });

    res.json({ files });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/admin/custom-worlds/upload
 * Upload new .apworld file
 */
router.post('/custom-worlds/upload', upload.single('file'), (req: Request, res: Response) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }
  clearCache();
  res.json({ success: true, filename: req.file.filename, size: req.file.size });
});

/**
 * DELETE /api/admin/custom-worlds/:filename
 * Delete a custom .apworld file
 */
router.delete('/custom-worlds/:filename', (req: Request, res: Response) => {
  const filename = req.params.filename as string;
  try {
    const filePath = path.join(CUSTOM_WORLDS_DIR, filename);
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'File not found' });
    }
    fs.unlinkSync(filePath);
    clearCache();
    res.json({ success: true, message: `Deleted ${filename}` });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/admin/servers
 * Active Archipelago server processes list
 */
router.get('/servers', (req: Request, res: Response) => {
  try {
    const serversList = Array.from(activeServers.entries()).map(([roomCode, server]) => ({
      roomCode,
      port: server.port,
      pid: server.child ? server.child.pid : null,
      saveFilePath: server.saveFilePath,
      connected: server.child && !server.child.killed
    }));
    res.json({ servers: serversList });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/admin/db
 * Database table viewer
 */
router.get('/db', (req: Request, res: Response) => {
  const table = (req.query.table as string) || 'Rooms';
  const allowedTables = ['Rooms', 'Users', 'Sessions'];

  if (!allowedTables.includes(table)) {
    return res.status(400).json({ error: `Invalid table name. Allowed: ${allowedTables.join(', ')}` });
  }

  try {
    const rows = db.prepare(`SELECT * FROM ${table} ORDER BY 1 DESC LIMIT 100`).all();
    res.json({ table, rows });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/admin/purge-all
 * Delete all backend data (rooms, users, sessions, temp seeds, failed logs, active AP servers)
 */
router.post('/purge-all', (req: Request, res: Response) => {
  try {
    const includeCustomWorlds = req.body?.includeCustomWorlds === true || req.query.includeCustomWorlds === 'true';

    // 1. Kill all active Archipelago server processes
    const activeRoomCodes = Array.from(activeServers.keys());
    for (const code of activeRoomCodes) {
      killRoomServer(code);
    }

    // 2. Clear database tables
    const purgeDb = db.transaction(() => {
      db.prepare('DELETE FROM Sessions').run();
      db.prepare('DELETE FROM Users').run();
      db.prepare('DELETE FROM Rooms').run();
      db.prepare('DELETE FROM OptionsCache').run();
    });
    purgeDb();

    // 3. Clean up temp_seeds directory
    const tempSeedsDir = path.join(BACKEND_ROOT, 'temp_seeds');
    if (fs.existsSync(tempSeedsDir)) {
      const items = fs.readdirSync(tempSeedsDir);
      for (const item of items) {
        fs.rmSync(path.join(tempSeedsDir, item), { recursive: true, force: true });
      }
    }

    // 4. Clean up failed_generations directory
    const failedGenDir = path.join(BACKEND_ROOT, 'failed_generations');
    if (fs.existsSync(failedGenDir)) {
      const items = fs.readdirSync(failedGenDir);
      for (const item of items) {
        fs.rmSync(path.join(failedGenDir, item), { recursive: true, force: true });
      }
    }

    // 5. Optionally remove custom .apworld packages
    let apWorldsPurged = 0;
    if (includeCustomWorlds && fs.existsSync(CUSTOM_WORLDS_DIR)) {
      const apFiles = fs.readdirSync(CUSTOM_WORLDS_DIR).filter(f => f.endsWith('.apworld'));
      apWorldsPurged = apFiles.length;
      for (const file of apFiles) {
        fs.unlinkSync(path.join(CUSTOM_WORLDS_DIR, file));
      }
    }

    // 6. Invalidate caches
    clearCache();

    res.json({
      success: true,
      message: `All server data successfully deleted.${apWorldsPurged > 0 ? ` (${apWorldsPurged} .apworld files removed)` : ''}`
    });
  } catch (err: any) {
    console.error('Failed to purge data:', err);
    res.status(500).json({ error: err.message || 'Failed to purge data' });
  }
});

export default router;
