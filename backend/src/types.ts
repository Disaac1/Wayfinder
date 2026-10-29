// WebSocket Message Protocols

export interface PlayerState {
  userId: string;
  name: string;
  games: string[];
  isReady: boolean;
  isConnected: boolean;
  isHost: boolean;
  yaml: string | null;
}

// Messages sent by Clients to the Server
export type ClientMessage =
  | { type: 'create_room'; playerName: string }
  | { type: 'join_room'; roomCode: string; playerName: string }
  | { type: 'reconnect'; userId: string; roomCode: string }
  | { type: 'update_state'; games: string[]; isReady: boolean; yaml: string | null }
  | { type: 'generate_seed' }
  | { type: 'kick_player'; targetUserId: string };

export interface GameCheckStats {
  game: string;
  checked: number;
  total: number;
}

export interface RoomChecks {
  totalChecked: number;
  totalLocations: number;
  games: Record<string, GameCheckStats>;
  players: Record<string, { checked: number; total: number; game: string }>;
}

// Messages sent by the Server to Clients
export type ServerMessage =
  | { type: 'room_created'; roomCode: string; userId: string }
  | { type: 'room_joined'; roomCode: string; userId: string; players: PlayerState[]; seedStatus: 'idle' | 'generating' | 'done'; seedZipName: string | null; seedSpoilerName: string | null; tunnelUrl?: string | null; hostingMode?: 'lodestone_backend' | 'wayfinder_backend' | 'archipelago_gg'; hostingStatus?: string | null; hostingRoomUrl?: string | null; hostingServerUrl?: string | null; lockedBy?: string | null; checks?: RoomChecks | null }
  | { type: 'room_state'; roomCode: string; players: PlayerState[]; seedStatus: 'idle' | 'generating' | 'done'; seedZipName: string | null; seedSpoilerName: string | null; tunnelUrl?: string | null; hostingMode?: 'lodestone_backend' | 'wayfinder_backend' | 'archipelago_gg'; hostingStatus?: string | null; hostingRoomUrl?: string | null; hostingServerUrl?: string | null; lockedBy?: string | null; checks?: RoomChecks | null }
  | { type: 'error'; message: string }
  | { type: 'generation_log'; line: string }
  | { type: 'kicked'; message: string }
  | { type: 'room_deleted'; message: string }
  | { type: 'checks_updated'; checks: RoomChecks }
  | { type: 'server_log'; line: string };
