import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import db from './db.js';
import { getValidatedRoomCode } from './utils.js';
import { killRoomServer } from './serverManager.js';
import { broadcastRoomState, closeRoom, executeHostCommand } from './roomManager.js';
import { fetchRoomSeedData } from './checksService.js';
import { localhostOnly } from './adminRoutes.js';
import { getHostingProvider } from './hostingProvider.js';

const router = Router();

function isRoomHost(roomCode: string, userId: unknown): boolean {
  if (typeof userId !== 'string' || !userId) return false;
  const room = db.prepare('SELECT host_id FROM Rooms WHERE code = ?').get(roomCode) as { host_id: string } | undefined;
  return Boolean(room && room.host_id === userId);
}

router.get('/:code/hosting', async (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
  const room = db.prepare('SELECT hosting_mode, hosting_seed_id, hosting_room_id, hosting_room_url, hosting_server_url, hosting_status, hosting_last_activity, hosting_timeout, hosting_last_error FROM Rooms WHERE code = ?').get(roomCode) as any;
  if (!room) return res.status(404).json({ error: `Room ${roomCode} not found` });
  if (!room.hosting_room_id) return res.json(room);

  try {
    const hosting = await getHostingProvider(room.hosting_mode).refresh({ roomCode, seedId: room.hosting_seed_id, roomId: room.hosting_room_id });
    db.prepare('UPDATE Rooms SET hosting_server_url = ?, hosting_status = ?, hosting_last_activity = ?, hosting_timeout = ?, hosting_last_error = NULL, hosting_updated_at = CURRENT_TIMESTAMP, tunnel_url = COALESCE(?, tunnel_url) WHERE code = ?').run(
      hosting.serverUrl,
      hosting.status,
      hosting.lastActivity,
      hosting.timeout,
      hosting.serverUrl,
      roomCode
    );
    return res.json({ ...room, hosting_server_url: hosting.serverUrl, hosting_status: hosting.status, hosting_last_activity: hosting.lastActivity, hosting_timeout: hosting.timeout, hosting_last_error: null });
  } catch (error: any) {
    console.error(`Failed to refresh Archipelago.gg status for room ${roomCode}:`, error);
    return res.status(502).json({ ...room, error: error.message || 'Failed to refresh remote hosting status' });
  }
});

router.post('/:code/hosting/mode', async (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
  const userId = req.body?.userId || req.query?.userId;
  if (!isRoomHost(roomCode, userId)) return res.status(403).json({ error: 'Only the room host can change hosting mode' });
  const mode = req.body?.hostingMode;
  if (mode !== 'lodestone_backend' && mode !== 'wayfinder_backend' && mode !== 'archipelago_gg') return res.status(400).json({ error: 'hostingMode must be lodestone_backend or archipelago_gg' });
  const room = db.prepare('SELECT seed_status FROM Rooms WHERE code = ?').get(roomCode) as { seed_status: string } | undefined;
  if (!room) return res.status(404).json({ error: `Room ${roomCode} not found` });
  if (room.seed_status !== 'idle') return res.status(409).json({ error: 'Hosting mode can only be changed before seed generation' });
  db.prepare('UPDATE Rooms SET hosting_mode = ?, hosting_last_error = NULL, updated_at = CURRENT_TIMESTAMP WHERE code = ?').run(mode, roomCode);
  broadcastRoomState(roomCode);
  res.json({ success: true, hostingMode: mode });
});

router.post('/:code/hosting/wake', async (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
  const userId = req.body?.userId || req.query?.userId;
  if (!isRoomHost(roomCode, userId)) return res.status(403).json({ error: 'Only the room host can wake hosting' });
  const room = db.prepare('SELECT hosting_mode, hosting_seed_id, hosting_room_id FROM Rooms WHERE code = ?').get(roomCode) as { hosting_mode: string; hosting_seed_id: string | null; hosting_room_id: string | null } | undefined;
  if (!room || !room.hosting_room_id) return res.status(409).json({ error: 'Room is not configured for external hosting' });
  try {
    const hosting = await getHostingProvider(room.hosting_mode).wake({ roomCode, seedId: room.hosting_seed_id, roomId: room.hosting_room_id });
    db.prepare('UPDATE Rooms SET hosting_server_url = ?, hosting_status = ?, hosting_last_activity = ?, hosting_timeout = ?, hosting_last_error = NULL, hosting_updated_at = CURRENT_TIMESTAMP, tunnel_url = COALESCE(?, tunnel_url) WHERE code = ?').run(hosting.serverUrl, hosting.status, hosting.lastActivity, hosting.timeout, hosting.serverUrl, roomCode);
    res.json({ success: true, serverUrl: hosting.serverUrl, status: hosting.status });
  } catch (error: any) {
    db.prepare('UPDATE Rooms SET hosting_status = ?, hosting_last_error = ?, hosting_updated_at = CURRENT_TIMESTAMP WHERE code = ?').run('error', error.message || 'Failed to wake remote room', roomCode);
    res.status(502).json({ error: error.message || 'Failed to wake remote room' });
  }
});

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 1. Direct REST HTTP API for querying active rooms list
router.get('/', (req: Request, res: Response) => {
  try {
    const filterPlayer = (req.query.playerName as string || '').trim().toLowerCase();
    const filterUserId = (req.query.userId as string || '').trim();

    // Privacy protection: Do not expose all lobbies to anonymous or unauthenticated queries.
    // Clients must provide playerName or userId to see lobbies they belong to.
    if (!filterPlayer && !filterUserId) {
      return res.json({ rooms: [] });
    }

    const rows = db.prepare(`
      SELECT 
        r.code, 
        r.host_id,
        r.seed_status, 
        r.created_at, 
        u.name as host_name,
        (SELECT COUNT(*) FROM Users WHERE room_code = r.code) as player_count,
        (SELECT GROUP_CONCAT(name, '|||') FROM Users WHERE room_code = r.code) as player_names,
        (SELECT GROUP_CONCAT(id, '|||') FROM Users WHERE room_code = r.code) as player_ids
      FROM Rooms r
      LEFT JOIN Users u ON r.code = u.room_code AND r.host_id = u.id
      WHERE (r.status IS NULL OR r.status = 'active') AND r.deleted_at IS NULL
      ORDER BY r.created_at DESC
    `).all() as any[];

    let rooms = rows.map(r => {
      const pNames: string[] = r.player_names ? r.player_names.split('|||').map((s: string) => s.trim()).filter(Boolean) : [];
      const pIds: string[] = r.player_ids ? r.player_ids.split('|||').map((s: string) => s.trim()).filter(Boolean) : [];
      return {
        code: r.code,
        hostName: r.host_name || 'Unknown Host',
        hostId: r.host_id,
        playerCount: r.player_count || 0,
        playerNames: pNames,
        playerIds: pIds,
        seedStatus: r.seed_status || 'idle',
        createdAt: r.created_at
      };
    });

    rooms = rooms.filter(r => {
      const matchPlayer = filterPlayer && (
        r.hostName.toLowerCase() === filterPlayer || 
        r.playerNames.some((p: string) => p.toLowerCase() === filterPlayer)
      );
      const matchUser = filterUserId && (
        r.hostId === filterUserId ||
        r.playerIds.some((id: string) => id === filterUserId)
      );
      return matchPlayer || matchUser;
    });

    res.json({ rooms });
  } catch (error: any) {
    console.error('Failed to fetch rooms list:', error);
    res.status(500).json({ error: error.message || 'Failed to fetch rooms list' });
  }
});

// 2. Delete room endpoint (Supports host deletion or localhost, soft-deletes with 7-day recovery grace period)
const handleDeleteRoom = async (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format' });
  }
  const userId = (req.query.userId as string) || (req.body && req.body.userId);

  try {
    const room = db.prepare('SELECT code, host_id FROM Rooms WHERE code = ?').get(roomCode) as { code: string; host_id: string } | undefined;
    if (!room) {
      return res.status(404).json({ error: `Room ${roomCode} not found` });
    }

    // Verify host if userId is provided
    if (userId && room.host_id !== userId) {
      return res.status(403).json({ error: 'Only the room host can delete this room' });
    }

    // Close room server, notify players with room_deleted, and disconnect sockets
    await closeRoom(roomCode);

    // Soft delete with 7-day grace period
    db.prepare("UPDATE Rooms SET status = 'abandoned', deleted_at = CURRENT_TIMESTAMP WHERE code = ?").run(roomCode);
    console.log(`Room ${roomCode} soft-deleted with 7-day recovery grace period.`);

    res.json({ success: true, roomCode, message: 'Room archived with a 7-day recovery grace period.' });
  } catch (error: any) {
    console.error(`Failed to delete room ${roomCode}:`, error);
    res.status(500).json({ error: error.message || 'Failed to delete room' });
  }
};

router.delete('/:code', handleDeleteRoom);
router.post('/:code/delete', handleDeleteRoom);

// 3. Recover deleted room within 7-day grace period
router.post('/:code/recover', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) {
    return res.status(400).json({ error: 'Invalid room code format' });
  }
  try {
    const room = db.prepare("SELECT code FROM Rooms WHERE code = ? AND deleted_at IS NOT NULL").get(roomCode);
    if (!room) {
      return res.status(404).json({ error: `Archived room ${roomCode} not found or already active` });
    }
    db.prepare("UPDATE Rooms SET status = 'active', deleted_at = NULL WHERE code = ?").run(roomCode);
    console.log(`Room ${roomCode} recovered from archive.`);
    res.json({ success: true, roomCode });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 4. Cleanup route for integration tests (Restricted to localhost)
export const testCleanupHandler = (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.body.roomCode);
  if (!roomCode) {
    return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
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
};

router.post('/test/cleanup', localhostOnly, testCleanupHandler);

// 5. Host command execution route
router.post('/:code/command', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) {
    return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
  }
  const userId = req.body?.userId || req.query?.userId;
  const command = req.body?.command;
  if (!userId || typeof userId !== 'string') {
    return res.status(400).json({ error: 'userId is required' });
  }
  if (!command || typeof command !== 'string') {
    return res.status(400).json({ error: 'command is required' });
  }

  const result = executeHostCommand(roomCode, userId, command);
  if (!result.success) {
    return res.status(400).json({ error: result.error });
  }
  res.json({ success: true, message: result.message });
});

// 6. Seed locations and items data endpoint
router.get('/:code/seed-data', async (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) {
    return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
  }
  const bypassCache = req.query.refresh === 'true';
  const data = await fetchRoomSeedData(roomCode, bypassCache);
  if (!data) {
    return res.status(404).json({ error: `Seed data not found for room ${roomCode}` });
  }
  res.json(data);
});

// 7. Connection mode and custom server IP configuration
router.post('/:code/connection-settings', (req: Request, res: Response) => {
  const roomCode = getValidatedRoomCode(req.params.code);
  if (!roomCode) {
    return res.status(400).json({ error: 'Valid 6-character roomCode is required' });
  }
  const userId = req.body?.userId || req.query?.userId;
  const serverIp = typeof req.body?.serverIp === 'string' ? req.body.serverIp.trim() : null;

  try {
    const room = db.prepare('SELECT host_id FROM Rooms WHERE code = ?').get(roomCode) as { host_id: string } | undefined;
    if (!room) {
      return res.status(404).json({ error: `Room ${roomCode} not found` });
    }
    if (userId && room.host_id !== userId) {
      return res.status(403).json({ error: 'Only the room host can update connection settings' });
    }

    db.prepare("UPDATE Rooms SET server_ip = ? WHERE code = ?").run(serverIp && serverIp.length > 0 ? serverIp : null, roomCode);
    console.log(`[Room ${roomCode}] Updated connection settings: server_ip=${serverIp || '(default tunnel)'}`);
    res.json({ success: true, serverIp: serverIp || null });
  } catch (error: any) {
    console.error(`Failed to update connection settings for room ${roomCode}:`, error);
    res.status(500).json({ error: error.message });
  }
});

export default router;
