import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOGS_DIR = path.join(__dirname, '..', 'logs');
const LOG_FILE_PATH = path.join(LOGS_DIR, 'wayfinder-backend.log');
const MAX_LOG_FILE_SIZE = 5 * 1024 * 1024; // 5 MB

if (!fs.existsSync(LOGS_DIR)) {
  fs.mkdirSync(LOGS_DIR, { recursive: true });
}

function rotateFileIfNeeded(): void {
  try {
    if (fs.existsSync(LOG_FILE_PATH)) {
      const stats = fs.statSync(LOG_FILE_PATH);
      if (stats.size >= MAX_LOG_FILE_SIZE) {
        const backupPath = LOG_FILE_PATH + '.1';
        if (fs.existsSync(backupPath)) {
          fs.unlinkSync(backupPath);
        }
        fs.renameSync(LOG_FILE_PATH, backupPath);
      }
    }
  } catch (err) {
    // Suppress rotation failure to never break process
  }
}

function appendToPersistentLog(timestamp: string, source: string, message: string, roomCode?: string): void {
  try {
    rotateFileIfNeeded();
    const roomTag = roomCode ? ` [${roomCode}]` : '';
    const line = `[${timestamp}] [${source.toUpperCase()}]${roomTag} ${message}\n`;
    fs.appendFileSync(LOG_FILE_PATH, line, 'utf8');
  } catch (err) {
    // Ignore persistent log write errors
  }
}

export interface LogEntry {
  id: number;
  timestamp: string;
  source: 'system' | 'server' | 'generation' | 'error';
  roomCode?: string;
  message: string;
}

const MAX_LOGS = 1000;
let nextLogId = 1;
const logBuffer: LogEntry[] = [];

/**
 * Add a new log entry to the in-memory ring buffer and persistent log file
 */
export function addLog(
  source: 'system' | 'server' | 'generation' | 'error',
  message: string,
  roomCode?: string
): LogEntry {
  const timestamp = new Date().toISOString();
  const entry: LogEntry = {
    id: nextLogId++,
    timestamp,
    source,
    roomCode,
    message: String(message)
  };

  logBuffer.push(entry);
  if (logBuffer.length > MAX_LOGS) {
    logBuffer.shift();
  }

  appendToPersistentLog(timestamp, source, message, roomCode);

  return entry;
}

/**
 * Retrieve logs, optionally since a given ID or filtered by roomCode/source
 */
export function getLogs(options?: {
  sinceId?: number;
  limit?: number;
  roomCode?: string;
  source?: string;
}): { logs: LogEntry[]; lastId: number } {
  let filtered = logBuffer;

  if (options?.sinceId !== undefined && !isNaN(options.sinceId)) {
    filtered = filtered.filter(l => l.id > options.sinceId!);
  }

  if (options?.roomCode) {
    const code = options.roomCode.toUpperCase();
    filtered = filtered.filter(l => l.roomCode === code);
  }

  if (options?.source && options.source !== 'all') {
    filtered = filtered.filter(l => l.source === options.source);
  }

  if (options?.limit && options.limit > 0 && filtered.length > options.limit) {
    filtered = filtered.slice(filtered.length - options.limit);
  }

  const lastId = logBuffer.length > 0 ? logBuffer[logBuffer.length - 1].id : 0;
  return { logs: filtered, lastId };
}

/**
 * Clear the log buffer
 */
export function clearLogs(): void {
  logBuffer.length = 0;
}

// Hook into console to automatically mirror server logs into buffer
const originalConsoleLog = console.log;
const originalConsoleWarn = console.warn;
const originalConsoleError = console.error;

console.log = function (...args: any[]) {
  originalConsoleLog.apply(console, args);
  try {
    const msg = args.map(a => (typeof a === 'object' ? JSON.stringify(a) : String(a))).join(' ');
    // Detect room tag like [AP Server ABCDEF]:
    const match = msg.match(/\[AP Server ([A-Z0-9]{6})\]/);
    const roomCode = match ? match[1] : undefined;
    const source = roomCode ? 'server' : 'system';
    addLog(source, msg, roomCode);
  } catch (e) {
    // Avoid recursion
  }
};

console.warn = function (...args: any[]) {
  originalConsoleWarn.apply(console, args);
  try {
    const msg = args.map(a => (typeof a === 'object' ? JSON.stringify(a) : String(a))).join(' ');
    const match = msg.match(/\[AP Server ([A-Z0-9]{6})/);
    const roomCode = match ? match[1] : undefined;
    addLog('error', msg, roomCode);
  } catch (e) {
    // Avoid recursion
  }
};

console.error = function (...args: any[]) {
  originalConsoleError.apply(console, args);
  try {
    const msg = args.map(a => (typeof a === 'object' ? JSON.stringify(a) : String(a))).join(' ');
    const match = msg.match(/\[AP Server ([A-Z0-9]{6})/);
    const roomCode = match ? match[1] : undefined;
    addLog('error', msg, roomCode);
  } catch (e) {
    // Avoid recursion
  }
};
