import { uploadSeedAndCreateRoom, getRoomStatus, wakeRoom, markRoomAndSeedForDeletion, ArchipelagoGgHostedRoom, ArchipelagoGgRoomStatus } from './archipelagoGgClient.js';
import { startCentralServer, killRoomServer } from './serverManager.js';
import db from './db.js';

export type HostingMode = 'lodestone_backend' | 'wayfinder_backend' | 'archipelago_gg';

export interface HostingResult {
  seedId: string | null;
  roomId: string | null;
  roomUrl: string | null;
  serverUrl: string | null;
  status: string | null;
  lastActivity: string | null;
  timeout: number | null;
}

export interface HostingRecord {
  roomCode?: string;
  seedId: string | null;
  roomId: string | null;
}

export interface HostingProvider {
  readonly mode: HostingMode;
  readonly managesLocalProcess: boolean;
  hostSeed(roomCode: string, seedArchivePath: string, zipName: string): Promise<HostingResult>;
  refresh(record: HostingRecord): Promise<HostingResult>;
  wake(record: HostingRecord): Promise<HostingResult>;
  stop(roomCode: string): void;
  markForDeletion(record: HostingRecord): Promise<void>;
}

function remoteResult(hostedRoom: ArchipelagoGgHostedRoom): HostingResult {
  return {
    seedId: hostedRoom.seedId,
    roomId: hostedRoom.roomId,
    roomUrl: hostedRoom.roomUrl,
    serverUrl: hostedRoom.serverUrl,
    status: hostedRoom.serverUrl ? 'active' : 'starting',
    lastActivity: hostedRoom.status.last_activity,
    timeout: hostedRoom.status.timeout
  };
}

function archipelagoStatusResult(status: ArchipelagoGgRoomStatus, roomId: string): HostingResult {
  const serverUrl = status.last_port > 0 ? `archipelago.gg:${status.last_port}` : null;
  return {
    seedId: null,
    roomId,
    roomUrl: null,
    serverUrl,
    status: serverUrl ? 'active' : 'starting',
    lastActivity: status.last_activity,
    timeout: status.timeout
  };
}

const lodestoneBackendProvider: HostingProvider = {
  mode: 'lodestone_backend',
  managesLocalProcess: true,
  async hostSeed(roomCode, seedArchivePath, zipName) {
    await startCentralServer(roomCode, zipName);
    const room = db
      .prepare('SELECT tunnel_url, server_port FROM Rooms WHERE code = ?')
      .get(roomCode) as { tunnel_url: string | null; server_port: number | null } | undefined;
    return {
      seedId: null,
      roomId: null,
      roomUrl: null,
      serverUrl: room?.tunnel_url || (room?.server_port ? `localhost:${room.server_port}` : null),
      status: 'active',
      lastActivity: null,
      timeout: null
    };
  },
  async refresh(record) {
    const room = record.roomCode
      ? db.prepare('SELECT tunnel_url, server_port FROM Rooms WHERE code = ?').get(record.roomCode) as { tunnel_url: string | null; server_port: number | null } | undefined
      : undefined;
    return {
      seedId: null,
      roomId: null,
      roomUrl: null,
      serverUrl: room?.tunnel_url || (room?.server_port ? `localhost:${room.server_port}` : null),
      status: 'active',
      lastActivity: null,
      timeout: null
    };
  },
  async wake(record) {
    return this.refresh(record);
    return {
      seedId: null,
      roomId: null,
      roomUrl: null,
      serverUrl: null,
      status: 'active',
      lastActivity: null,
      timeout: null
    };
  },
  stop(roomCode) {
    killRoomServer(roomCode);
  },
  async markForDeletion() {
  }
};

const archipelagoGgProvider: HostingProvider = {
  mode: 'archipelago_gg',
  managesLocalProcess: false,
  async hostSeed(_roomCode, seedArchivePath) {
    return remoteResult(await uploadSeedAndCreateRoom(seedArchivePath));
  },
  async refresh(record) {
    if (!record.roomId) throw new Error('Archipelago.gg room ID is missing.');
    return archipelagoStatusResult(await getRoomStatus(record.roomId), record.roomId);
  },
  async wake(record) {
    if (!record.roomId) throw new Error('Archipelago.gg room ID is missing.');
    return archipelagoStatusResult(await wakeRoom(record.roomId), record.roomId);
  },
  stop() {
    // Archipelago.gg rooms are managed by the provider and cannot be stopped locally.
  },
  async markForDeletion(record) {
    await markRoomAndSeedForDeletion(record.roomId, record.seedId);
  }
};

const providers: Record<string, HostingProvider> = {
  lodestone_backend: lodestoneBackendProvider,
  wayfinder_backend: lodestoneBackendProvider,
  archipelago_gg: archipelagoGgProvider
};

export function getHostingProvider(mode: string | null | undefined): HostingProvider {
  const normalized = (!mode || mode === 'wayfinder_backend' || mode === 'lodestone_backend') ? 'lodestone_backend' : mode;
  if (!providers[normalized]) {
    throw new Error(`Unsupported hosting mode: ${mode || 'empty'}`);
  }
  return providers[normalized];
}
