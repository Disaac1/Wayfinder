import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Resolve directory paths since we are using ES Modules/ts-node
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DB_PATH = process.env.DATABASE_URL || path.join(__dirname, '..', 'database.db');
const SCHEMA_PATH = fs.existsSync(path.join(__dirname, 'schema.sql'))
  ? path.join(__dirname, 'schema.sql')
  : path.join(__dirname, '..', 'src', 'schema.sql');

console.log(`Connecting to SQLite database at: ${DB_PATH}`);

const db = new Database(DB_PATH);

// Enable foreign keys and Write-Ahead Logging (WAL) for high concurrency
db.pragma('foreign_keys = ON');
db.pragma('journal_mode = WAL');

// Initialize database schema
try {
  const schemaSql = fs.readFileSync(SCHEMA_PATH, 'utf8');
  db.exec(schemaSql);
  
  // Dynamic migrations for Rooms seed generation columns
  const tableInfo = db.prepare("PRAGMA table_info(Rooms)").all() as Array<{ name: string }>;
  let columns = tableInfo.map(c => c.name);
  if (!columns.includes('seed_status')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN seed_status TEXT DEFAULT 'idle'").run();
    console.log("Migration: Added seed_status to Rooms table");
  }
  if (!columns.includes('seed_zip_name')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN seed_zip_name TEXT DEFAULT NULL").run();
    console.log("Migration: Added seed_zip_name to Rooms table");
  }
  if (!columns.includes('seed_spoiler_name')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN seed_spoiler_name TEXT DEFAULT NULL").run();
    console.log("Migration: Added seed_spoiler_name to Rooms table");
  }
  if (!columns.includes('tunnel_url')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN tunnel_url TEXT DEFAULT NULL").run();
    console.log("Migration: Added tunnel_url to Rooms table");
  }
  if (!columns.includes('deleted_at')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN deleted_at DATETIME DEFAULT NULL").run();
    console.log("Migration: Added deleted_at to Rooms table");
  }
  if (!columns.includes('server_ip')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN server_ip TEXT DEFAULT NULL").run();
    console.log("Migration: Added server_ip to Rooms table");
  }
  if (!columns.includes('server_port')) {
    db.prepare("ALTER TABLE Rooms ADD COLUMN server_port INTEGER DEFAULT NULL").run();
    console.log("Migration: Added server_port to Rooms table");
  }
  const legacyHostingColumns: Array<[string, string]> = [
    ['remote_seed_id', 'hosting_seed_id'],
    ['remote_room_id', 'hosting_room_id'],
    ['remote_room_url', 'hosting_room_url'],
    ['remote_server_url', 'hosting_server_url'],
    ['remote_status', 'hosting_status'],
    ['remote_last_activity', 'hosting_last_activity'],
    ['remote_timeout', 'hosting_timeout'],
    ['remote_last_error', 'hosting_last_error'],
    ['remote_updated_at', 'hosting_updated_at']
  ];
  if (columns.includes('remote_seed_id')) {
    db.pragma('foreign_keys = OFF');
    db.exec(`
      CREATE TABLE Rooms_new (
        code TEXT PRIMARY KEY,
        host_id TEXT,
        status TEXT DEFAULT 'active',
        seed_status TEXT DEFAULT 'idle',
        seed_zip_name TEXT DEFAULT NULL,
        seed_spoiler_name TEXT DEFAULT NULL,
        tunnel_url TEXT DEFAULT NULL,
        server_ip TEXT DEFAULT NULL,
        server_port INTEGER DEFAULT NULL,
        hosting_mode TEXT DEFAULT 'wayfinder_backend',
        hosting_seed_id TEXT DEFAULT NULL,
        hosting_room_id TEXT DEFAULT NULL,
        hosting_room_url TEXT DEFAULT NULL,
        hosting_server_url TEXT DEFAULT NULL,
        hosting_status TEXT DEFAULT NULL,
        hosting_last_activity TEXT DEFAULT NULL,
        hosting_timeout INTEGER DEFAULT NULL,
        hosting_last_error TEXT DEFAULT NULL,
        hosting_updated_at DATETIME DEFAULT NULL,
        deleted_at DATETIME DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      INSERT INTO Rooms (
        code, host_id, status, seed_status, seed_zip_name, seed_spoiler_name,
        tunnel_url, server_ip, server_port, hosting_mode, hosting_seed_id,
        hosting_room_id, hosting_room_url, hosting_server_url, hosting_status,
        hosting_last_activity, hosting_timeout, hosting_last_error, hosting_updated_at,
        deleted_at, created_at, updated_at
      )
      SELECT
        code, host_id, status, seed_status, seed_zip_name, seed_spoiler_name,
        tunnel_url, server_ip, server_port,
        CASE WHEN hosting_mode = 'local' THEN 'wayfinder_backend'
             WHEN hosting_mode IS NULL THEN 'wayfinder_backend'
             ELSE hosting_mode END,
        remote_seed_id, remote_room_id, remote_room_url, remote_server_url,
        remote_status, remote_last_activity, remote_timeout, remote_last_error,
        remote_updated_at, deleted_at, created_at, updated_at
      FROM Rooms;
      DROP TABLE Rooms;
      ALTER TABLE Rooms_new RENAME TO Rooms;
    `);
    db.pragma('foreign_keys = ON');
    columns = (db.prepare("PRAGMA table_info(Rooms)").all() as Array<{ name: string }>).map(c => c.name);
    console.log('Migration: Rebuilt Rooms table with generic hosting fields');
  }
  for (const [legacyColumn, hostingColumn] of legacyHostingColumns) {
    if (columns.includes(legacyColumn) && !columns.includes(hostingColumn)) {
      db.prepare(`ALTER TABLE Rooms RENAME COLUMN ${legacyColumn} TO ${hostingColumn}`).run();
      console.log(`Migration: Renamed ${legacyColumn} to ${hostingColumn}`);
    }
  }
  if (columns.includes('hosting_mode')) {
    db.prepare("UPDATE Rooms SET hosting_mode = 'wayfinder_backend' WHERE hosting_mode = 'local' OR hosting_mode IS NULL").run();
  } else {
    db.prepare("ALTER TABLE Rooms ADD COLUMN hosting_mode TEXT DEFAULT 'wayfinder_backend'").run();
    console.log('Migration: Added hosting_mode to Rooms table');
  }
  const hostingColumns: Array<[string, string]> = [
    ['hosting_seed_id', 'TEXT DEFAULT NULL'],
    ['hosting_room_id', 'TEXT DEFAULT NULL'],
    ['hosting_room_url', 'TEXT DEFAULT NULL'],
    ['hosting_server_url', 'TEXT DEFAULT NULL'],
    ['hosting_status', 'TEXT DEFAULT NULL'],
    ['hosting_last_activity', 'TEXT DEFAULT NULL'],
    ['hosting_timeout', 'INTEGER DEFAULT NULL'],
    ['hosting_last_error', 'TEXT DEFAULT NULL'],
    ['hosting_updated_at', 'DATETIME DEFAULT NULL']
  ];
  columns = (db.prepare("PRAGMA table_info(Rooms)").all() as Array<{ name: string }>).map(c => c.name);
  for (const [column, definition] of hostingColumns) {
    if (!columns.includes(column)) {
      db.prepare(`ALTER TABLE Rooms ADD COLUMN ${column} ${definition}`).run();
      console.log(`Migration: Added ${column} to Rooms table`);
    }
  }
  
  // Purge expired rooms and inactive rooms (3+ months)
  purgeInactiveRooms();
  
  // Schedule daily housekeeping
  setInterval(purgeInactiveRooms, 24 * 60 * 60 * 1000);
  
  // Reset any stale generating status to idle on startup
  db.prepare("UPDATE Rooms SET seed_status = 'idle' WHERE seed_status = 'generating'").run();
  console.log("Stale room seed statuses reset to idle.");
  
  console.log('Database schema verified/initialized successfully.');
} catch (error) {
  console.error('Failed to initialize database schema:', error);
  process.exit(1);
}

/**
 * Updates a room's updated_at timestamp to mark activity
 */
export function touchRoomActivity(roomCode: string): void {
  try {
    db.prepare("UPDATE Rooms SET updated_at = CURRENT_TIMESTAMP WHERE code = ?").run(roomCode);
  } catch (err) {
    console.warn(`Failed to touch room activity for ${roomCode}:`, err);
  }
}

/**
 * Deletes room artifacts from disk and removes the room record from the database.
 * Cascades automatically to Users and Sessions.
 */
export function deleteRoomArtifactsAndRow(code: string, reason: string): void {
  const tempSeedsDir = path.join(path.dirname(DB_PATH), 'temp_seeds', code);
  if (fs.existsSync(tempSeedsDir)) {
    try {
      fs.rmSync(tempSeedsDir, { recursive: true, force: true });
    } catch (e) {
      console.warn(`[Housekeeping] Could not remove temp_seeds directory for room ${code}:`, e);
    }
  }
  db.prepare('DELETE FROM Rooms WHERE code = ?').run(code);
  console.log(`[Housekeeping] Purged room ${code} (${reason})`);
}

/**
 * Housekeeping job:
 * 1. Purges soft-deleted rooms past their 7-day recovery grace period
 * 2. Purges inactive rooms with no activity for more than 3 months (90 days)
 */
export function purgeInactiveRooms(): void {
  try {
    // 1. Purge soft-deleted rooms past their 7-day recovery grace period
    const expiredDeletedRooms = db.prepare(
      "SELECT code FROM Rooms WHERE deleted_at IS NOT NULL AND deleted_at < datetime('now', '-7 days')"
    ).all() as Array<{ code: string }>;

    for (const { code } of expiredDeletedRooms) {
      deleteRoomArtifactsAndRow(code, 'soft-deleted > 7 days ago');
    }

    // 2. Purge rooms with no activity for more than 3 months (90 days)
    const inactiveRooms = db.prepare(
      "SELECT code FROM Rooms WHERE COALESCE(updated_at, created_at) < datetime('now', '-90 days')"
    ).all() as Array<{ code: string }>;

    for (const { code } of inactiveRooms) {
      deleteRoomArtifactsAndRow(code, 'inactive for > 3 months (90 days)');
    }
  } catch (err) {
    console.warn('[Housekeeping] Error purging expired/inactive rooms:', err);
  }
}

export default db;
export { Database };
