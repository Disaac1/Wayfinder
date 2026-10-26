-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- Rooms Table
CREATE TABLE IF NOT EXISTS Rooms (
    code TEXT PRIMARY KEY,
    host_id TEXT,
    status TEXT CHECK(status IN ('active', 'completed', 'abandoned')) DEFAULT 'active',
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

-- Users Table
CREATE TABLE IF NOT EXISTS Users (
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

-- Sessions Table (to track Archipelago save states and checkout locks)
CREATE TABLE IF NOT EXISTS Sessions (
    room_code TEXT PRIMARY KEY REFERENCES Rooms(code) ON DELETE CASCADE,
    save_file_path TEXT,
    locked_by TEXT REFERENCES Users(id) ON DELETE SET NULL,
    locked_at DATETIME,
    force_unlocked INTEGER DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- OptionsCache Table (to cache parsed game options and games list)
CREATE TABLE IF NOT EXISTS OptionsCache (
    cache_key TEXT PRIMARY KEY,
    json_data TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_users_room_code ON Users(room_code);

-- Unique index to prevent duplicate names in the same room
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_room_name ON Users(room_code, name COLLATE NOCASE) WHERE room_code IS NOT NULL;
