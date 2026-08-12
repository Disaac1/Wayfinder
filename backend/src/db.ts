import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Resolve directory paths since we are using ES Modules/ts-node
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DB_PATH = process.env.DATABASE_URL || path.join(__dirname, '..', 'database.db');
const SCHEMA_PATH = path.join(__dirname, 'schema.sql');

console.log(`Connecting to SQLite database at: ${DB_PATH}`);

const db = new Database(DB_PATH);

// Enable foreign keys
db.pragma('foreign_keys = ON');

// Initialize database schema
try {
  const schemaSql = fs.readFileSync(SCHEMA_PATH, 'utf8');
  db.exec(schemaSql);
  
  // Dynamic migrations for Rooms seed generation columns
  const tableInfo = db.prepare("PRAGMA table_info(Rooms)").all() as Array<{ name: string }>;
  const columns = tableInfo.map(c => c.name);
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
  
  // Reset any stale generating status to idle on startup
  db.prepare("UPDATE Rooms SET seed_status = 'idle' WHERE seed_status = 'generating'").run();
  console.log("Stale room seed statuses reset to idle.");
  
  console.log('Database schema verified/initialized successfully.');
} catch (error) {
  console.error('Failed to initialize database schema:', error);
  process.exit(1);
}

export default db;
export { Database };
