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

  const roomForeignKeyReferences = db.prepare(`
    SELECT name, sql
    FROM sqlite_master
    WHERE type = 'table' AND name IN ('Users', 'Sessions')
  `).all() as Array<{ name: string; sql: string }>;
  if (roomForeignKeyReferences.some(table => table.sql.includes('Rooms_legacy'))) {
    db.pragma('foreign_keys = OFF');
    const repairRoomForeignKeys = db.transaction(() => {
      db.exec(`
        CREATE TABLE Sessions_repaired (
          room_code TEXT PRIMARY KEY REFERENCES Rooms(code) ON DELETE CASCADE,
          save_file_path TEXT,
          locked_by TEXT REFERENCES Users(id) ON DELETE SET NULL,
          locked_at DATETIME,
          force_unlocked INTEGER DEFAULT 0,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO Sessions_repaired
        SELECT room_code, save_file_path, locked_by, locked_at, force_unlocked, updated_at
        FROM Sessions;
        DROP TABLE Sessions;
        ALTER TABLE Sessions_repaired RENAME TO Sessions;

        DROP INDEX IF EXISTS idx_users_room_code;
        DROP INDEX IF EXISTS idx_users_room_name;
        CREATE TABLE Users_repaired (
          id TEXT PRIMARY KEY,
          room_code TEXT REFERENCES Rooms(code) ON DELETE CASCADE,
          name TEXT NOT NULL,
          games TEXT DEFAULT '[]',
          is_ready INTEGER DEFAULT 0,
          is_connected INTEGER DEFAULT 1,
          yaml TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO Users_repaired
        SELECT id, room_code, name, games, is_ready, is_connected, yaml, created_at, updated_at
        FROM Users;
        DROP TABLE Users;
        ALTER TABLE Users_repaired RENAME TO Users;
        CREATE INDEX idx_users_room_code ON Users(room_code);
        CREATE UNIQUE INDEX idx_users_room_name
          ON Users(room_code, name COLLATE NOCASE)
          WHERE room_code IS NOT NULL;
      `);
    });
    repairRoomForeignKeys();
    db.pragma('foreign_keys = ON');
    console.log('Migration: Repaired stale foreign keys referencing Rooms_legacy');
  }
  
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
    for (const [legacyColumn, hostingColumn] of legacyHostingColumns) {
      if (columns.includes(legacyColumn) && !columns.includes(hostingColumn)) {
        db.prepare(`ALTER TABLE Rooms RENAME COLUMN ${legacyColumn} TO ${hostingColumn}`).run();
        console.log(`Migration: Renamed ${legacyColumn} to ${hostingColumn}`);
      }
    }
    columns = (db.prepare("PRAGMA table_info(Rooms)").all() as Array<{ name: string }>).map(c => c.name);
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
