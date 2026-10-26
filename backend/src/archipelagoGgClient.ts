import fs from 'fs/promises';
import fsSync from 'fs';
import path from 'path';
import { randomUUID } from 'crypto';

const DEFAULT_BASE_URL = 'https://archipelago.gg';
const REQUEST_TIMEOUT_MS = 30_000;
const ROOM_READY_TIMEOUT_MS = 60_000;
const ROOM_READY_POLL_MS = 2_000;
const SESSION_FILE_NAME = '.archipelago-gg-session-id';
const SESSION_FILE_PATH = path.join(process.env.WAYFINDER_DATA_DIR || process.cwd(), SESSION_FILE_NAME);

export interface ArchipelagoGgRoomStatus {
  tracker: string | null;
  players: Array<[string, string]>;
  last_port: number;
  last_activity: string;
  timeout: number;
  downloads: Array<{ slot: number; download: string }>;
}

export interface ArchipelagoGgHostedRoom {
  seedId: string;
  roomId: string;
  roomUrl: string;
  serverUrl: string | null;
  status: ArchipelagoGgRoomStatus;
}

function getBaseUrl(): string {
  return (process.env.ARCHIPELAGO_GG_BASE_URL || DEFAULT_BASE_URL).replace(/\/+$/, '');
}

function getSessionId(): string {
  const sessionId = process.env.ARCHIPELAGO_GG_SESSION_ID?.trim();
  if (sessionId) {
    return sessionId;
  }

  try {
    const storedSessionId = fsSync.readFileSync(SESSION_FILE_PATH, 'utf8').trim();
    if (storedSessionId) return storedSessionId;
  } catch (error: any) {
    if (error.code !== 'ENOENT') {
      throw new Error(`Failed to read Archipelago.gg session identity: ${error.message}`);
    }
  }

  const generatedSessionId = randomUUID();
  try {
    fsSync.writeFileSync(SESSION_FILE_PATH, `${generatedSessionId}\n`, {
      encoding: 'utf8',
      mode: 0o600,
      flag: 'wx'
    });
  } catch (error: any) {
    if (error.code === 'EEXIST') {
      const existingSessionId = fsSync.readFileSync(SESSION_FILE_PATH, 'utf8').trim();
      if (existingSessionId) return existingSessionId;
    }
    throw new Error(`Failed to persist Archipelago.gg session identity: ${error.message}`);
  }

  console.log(`Created persistent Archipelago.gg session identity at ${SESSION_FILE_PATH}`);
  return generatedSessionId;
}

function getCookie(response: Response): string | null {
  const headers = response.headers as Headers & { getSetCookie?: () => string[] };
  const setCookies = headers.getSetCookie?.() || [];
  if (setCookies.length > 0) {
    return setCookies.map(cookie => cookie.split(';', 1)[0]).join('; ');
  }
  const cookie = response.headers.get('set-cookie');
  return cookie ? cookie.split(';', 1)[0] : null;
}

async function request(pathname: string, init: RequestInit = {}, cookie?: string): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const headers = new Headers(init.headers);
  if (cookie) headers.set('Cookie', cookie);

  try {
    return await fetch(`${getBaseUrl()}${pathname}`, {
      ...init,
      headers,
      redirect: 'manual',
      signal: controller.signal
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function establishSession(): Promise<string> {
  const response = await request(`/session/${encodeURIComponent(getSessionId())}`);
  if (response.status >= 400) {
    throw new Error(`Archipelago.gg session setup failed with HTTP ${response.status}.`);
  }
  const cookie = getCookie(response);
  if (!cookie) {
    throw new Error('Archipelago.gg session setup did not return a session cookie.');
  }
  return cookie;
}

function extractRedirectId(location: string | null, prefix: string): string {
  if (!location) throw new Error(`Archipelago.gg did not return a ${prefix} redirect.`);
  const match = new URL(location, getBaseUrl()).pathname.match(new RegExp(`/${prefix}/([^/]+)$`));
  if (!match?.[1]) throw new Error(`Archipelago.gg returned an invalid ${prefix} redirect.`);
  return match[1];
}

async function getRoomStatusWithCookie(roomId: string, cookie: string): Promise<ArchipelagoGgRoomStatus> {
  const response = await request(`/api/room_status/${encodeURIComponent(roomId)}`, {}, cookie);
  if (!response.ok) {
    throw new Error(`Archipelago.gg room status failed with HTTP ${response.status}.`);
  }
  const status = await response.json() as ArchipelagoGgRoomStatus;
  if (!Number.isInteger(status.last_port) || status.last_port < 0) {
    throw new Error('Archipelago.gg returned an invalid room port.');
  }
  return status;
}

function serverUrl(status: ArchipelagoGgRoomStatus): string | null {
  return status.last_port > 0 ? `archipelago.gg:${status.last_port}` : null;
}

export async function uploadSeedAndCreateRoom(seedArchivePath: string): Promise<ArchipelagoGgHostedRoom> {
  const cookie = await establishSession();
  const seedArchive = await fs.readFile(seedArchivePath);
  const filename = path.basename(seedArchivePath);
  const form = new FormData();
  form.append('file', new Blob([seedArchive], { type: 'application/zip' }), filename);

  const uploadResponse = await request('/uploads', { method: 'POST', body: form }, cookie);
  if (uploadResponse.status < 300 || uploadResponse.status >= 400) {
    throw new Error(`Archipelago.gg seed upload failed with HTTP ${uploadResponse.status}.`);
  }
  const seedId = extractRedirectId(uploadResponse.headers.get('location'), 'seed');

  const roomResponse = await request(`/new_room/${encodeURIComponent(seedId)}`, {}, cookie);
  if (roomResponse.status < 300 || roomResponse.status >= 400) {
    throw new Error(`Archipelago.gg room creation failed with HTTP ${roomResponse.status}.`);
  }
  const roomId = extractRedirectId(roomResponse.headers.get('location'), 'room');
  const status = await waitForRoomReady(roomId, cookie);

  return {
    seedId,
    roomId,
    roomUrl: `${getBaseUrl()}/room/${roomId}`,
    serverUrl: serverUrl(status),
    status
  };
}

async function waitForRoomReady(roomId: string, cookie: string): Promise<ArchipelagoGgRoomStatus> {
  const deadline = Date.now() + ROOM_READY_TIMEOUT_MS;
  let status = await getRoomStatusWithCookie(roomId, cookie);
  while (status.last_port === 0 && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, ROOM_READY_POLL_MS));
    status = await getRoomStatusWithCookie(roomId, cookie);
  }
  return status;
}

export async function wakeRoom(roomId: string): Promise<ArchipelagoGgRoomStatus> {
  const cookie = await establishSession();
  const response = await request(`/room/${encodeURIComponent(roomId)}`, {}, cookie);
  if (response.status < 300 || response.status >= 400) {
    throw new Error(`Archipelago.gg room wake failed with HTTP ${response.status}.`);
  }
  return getRoomStatusWithCookie(roomId, cookie);
}

export async function getRoomStatus(roomId: string): Promise<ArchipelagoGgRoomStatus> {
  const cookie = await establishSession();
  return getRoomStatusWithCookie(roomId, cookie);
}

async function markForDeletion(pathname: string, label: string): Promise<void> {
  const cookie = await establishSession();
  const response = await request(pathname, {}, cookie);
  if (response.status < 300 || response.status >= 400) {
    throw new Error(`Archipelago.gg ${label} deletion marking failed with HTTP ${response.status}.`);
  }
}

export async function markRoomAndSeedForDeletion(roomId: string | null, seedId: string | null): Promise<void> {
  const operations: Promise<void>[] = [];
  if (roomId) {
    operations.push(markForDeletion(`/disown_room/${encodeURIComponent(roomId)}`, 'room'));
  }
  if (seedId) {
    operations.push(markForDeletion(`/disown_seed/${encodeURIComponent(seedId)}`, 'seed'));
  }
  const results = await Promise.allSettled(operations);
  const failures = results
    .filter((result): result is PromiseRejectedResult => result.status === 'rejected')
    .map(result => result.reason instanceof Error ? result.reason.message : String(result.reason));
  if (failures.length > 0) {
    throw new Error(failures.join(' '));
  }
}
