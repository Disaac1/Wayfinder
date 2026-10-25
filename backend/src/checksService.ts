import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFile } from 'child_process';
import { RoomChecks, GameCheckStats } from './types.js';
import { getPythonCommand } from './archipelagoRunner.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.join(__dirname, '..');

export const roomChecksCache = new Map<string, RoomChecks>();

export function recalculateRoomChecks(roomCode: string): void {
  const checks = roomChecksCache.get(roomCode);
  if (!checks) return;
  let totalChecked = 0;
  let totalLocations = 0;
  const gameStats: Record<string, GameCheckStats> = {};

  for (const [, pData] of Object.entries(checks.players)) {
    totalChecked += pData.checked;
    totalLocations += pData.total;
    const g = pData.game;
    if (!gameStats[g]) {
      gameStats[g] = { game: g, checked: 0, total: 0 };
    }
    gameStats[g].checked += pData.checked;
    gameStats[g].total += pData.total;
  }
  checks.totalChecked = totalChecked;
  checks.totalLocations = totalLocations;
  checks.games = gameStats;
}

export async function fetchRoomChecks(roomCode: string): Promise<RoomChecks | null> {
  const outputsDir = path.join(BACKEND_ROOT, 'temp_seeds', roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    return null;
  }
  const { exe: pythonExe, prefixArgs } = getPythonCommand();
  const scriptPath = path.join(BACKEND_ROOT, 'src', 'parse_checks.py');
  const archipelagoPath = path.join(BACKEND_ROOT, 'archipelago_core');

  return new Promise((resolve) => {
    execFile(pythonExe, [...prefixArgs, scriptPath, archipelagoPath, outputsDir], {
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    }, (error, stdout) => {
      if (error) {
        console.warn(`[Checks] Failed to parse checks for room ${roomCode}:`, error.message);
        return resolve(roomChecksCache.get(roomCode) || null);
      }
      try {
        const result = JSON.parse(stdout);
        if (result && !result.error) {
          roomChecksCache.set(roomCode, result);
          return resolve(result);
        }
      } catch (e) {}
      resolve(roomChecksCache.get(roomCode) || null);
    });
  });
}

export interface RoomSeedData {
  players: string[];
  locations: Record<string, string[]>;
  items: Record<string, string[]>;
  allItems: string[];
}

export const roomSeedDataCache = new Map<string, RoomSeedData>();

export function clearRoomSeedData(roomCode: string): void {
  roomSeedDataCache.delete(roomCode);
}

export async function fetchRoomSeedData(roomCode: string, bypassCache = false): Promise<RoomSeedData | null> {
  if (!bypassCache && roomSeedDataCache.has(roomCode)) {
    return roomSeedDataCache.get(roomCode)!;
  }
  const outputsDir = path.join(BACKEND_ROOT, 'temp_seeds', roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    return null;
  }
  const { exe: pythonExe, prefixArgs } = getPythonCommand();
  const scriptPath = path.join(BACKEND_ROOT, 'src', 'parse_seed_data.py');
  const archipelagoPath = path.join(BACKEND_ROOT, 'archipelago_core');

  return new Promise((resolve) => {
    execFile(pythonExe, [...prefixArgs, scriptPath, archipelagoPath, outputsDir], {
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    }, (error, stdout) => {
      if (error) {
        console.warn(`[SeedData] Failed to parse seed data for room ${roomCode}:`, error.message);
        return resolve(null);
      }
      try {
        const result = JSON.parse(stdout);
        if (result && !result.error) {
          roomSeedDataCache.set(roomCode, result);
          return resolve(result);
        }
      } catch (e) {}
      resolve(null);
    });
  });
}
