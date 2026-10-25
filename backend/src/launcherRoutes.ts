import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { getAvailableGames, getGameOptions } from './archipelagoRunner.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

type JsonRecord = Record<string, any>;

const DATA_DIR = path.join(__dirname, '..', 'data');
const TOOLS_DIR = path.join(DATA_DIR, 'tools');
const GAMES_DIR = path.join(DATA_DIR, 'games');

function readJsonFile(filePath: string, description: string): JsonRecord | undefined {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as JsonRecord;
  } catch (error) {
    console.error(`Failed to read ${description}:`, error);
    return undefined;
  }
}

export interface LauncherConfig {
  tools: Record<string, JsonRecord>;
  games: Record<string, JsonRecord>;
}

export function getLauncherConfig(): LauncherConfig {
  const tools: Record<string, JsonRecord> = {};
  if (fs.existsSync(TOOLS_DIR)) {
    for (const entry of fs.readdirSync(TOOLS_DIR, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.json')) {
        const toolKey = path.basename(entry.name, '.json');
        const tool = readJsonFile(path.join(TOOLS_DIR, entry.name), `tool json ${entry.name}`);
        if (tool) {
          tools[toolKey] = tool;
        }
      }
    }
  }

  const games: Record<string, JsonRecord> = {};
  if (fs.existsSync(GAMES_DIR)) {
    for (const entry of fs.readdirSync(GAMES_DIR, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const launchPath = path.join(GAMES_DIR, entry.name, 'launch.json');
      if (fs.existsSync(launchPath)) {
        const gameData = readJsonFile(launchPath, `game launch json ${entry.name}`);
        if (gameData) {
          const gameName = String(gameData.game_name || entry.name);
          gameData.slug = entry.name;
          games[gameName] = gameData;
        }
      }
    }
  }

  return { tools, games };
}

let gameSlugMapCache: Record<string, string> | null = null;

export function normalizeGameSlugKey(key: string): string {
  return key.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function getGameSlugMap(): Record<string, string> {
  if (gameSlugMapCache) {
    return gameSlugMapCache;
  }
  const slugMap: Record<string, string> = {};
  if (fs.existsSync(GAMES_DIR)) {
    for (const entry of fs.readdirSync(GAMES_DIR, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const canonicalSlug = entry.name;
      slugMap[normalizeGameSlugKey(entry.name)] = canonicalSlug;

      // launch.json is the single source of truth for game identifiers.
      const launchPath = path.join(GAMES_DIR, entry.name, 'launch.json');
      if (fs.existsSync(launchPath)) {
        const launchData = readJsonFile(launchPath, `launch.json for slug mapping in ${entry.name}`);
        if (launchData) {
          if (launchData.game_name) {
            slugMap[normalizeGameSlugKey(launchData.game_name)] = canonicalSlug;
          }
          if (Array.isArray(launchData.aliases)) {
            for (const alias of launchData.aliases) {
              slugMap[normalizeGameSlugKey(String(alias))] = canonicalSlug;
            }
          }
        }
      }
    }
  }
  gameSlugMapCache = slugMap;
  return slugMap;
}

export function getCanonicalGameSlug(rawSlug: string): string {
  const normKey = normalizeGameSlugKey(rawSlug);
  const slugMap = getGameSlugMap();
  if (slugMap[normKey]) {
    return slugMap[normKey];
  }
  return rawSlug.toLowerCase().replace(/[^a-z0-9_-]/g, '_');
}

export const gamesRouter = Router();
export const optionsRouter = Router();
export const launcherRouter = Router();
export const toolsRouter = Router();

// Games routes
gamesRouter.get('/', async (req: Request, res: Response) => {
  const force = req.query.force === 'true';
  try {
    const games = await getAvailableGames(force);
    res.json({ games });
  } catch (error: any) {
    res.status(500).json({ error: error.message || 'Failed to fetch games list' });
  }
});

gamesRouter.get('/:gameId/launch', (req: Request, res: Response) => {
  const gameId = getCanonicalGameSlug(path.basename(req.params.gameId as string));
  const launchFile = path.join(GAMES_DIR, gameId, 'launch.json');
  if (fs.existsSync(launchFile)) {
    const launchConfig = readJsonFile(launchFile, `launch config for ${gameId}`);
    if (!launchConfig) {
      return res.status(500).json({ error: `Invalid launch configuration for ${gameId}` });
    }
    return res.json(launchConfig);
  }
  // Try matching by game name
  const config = getLauncherConfig();
  for (const [name, g] of Object.entries(config.games)) {
    if (getCanonicalGameSlug(name) === gameId) {
      return res.json(g);
    }
  }
  res.status(404).json({ error: `Game launch config for ${gameId} not found` });
});

gamesRouter.get('/:gameId/guided-setup', (req: Request, res: Response) => {
  const gameId = getCanonicalGameSlug(path.basename(req.params.gameId as string));
  const setupFile = path.join(GAMES_DIR, gameId, 'guided_setup.json');
  if (fs.existsSync(setupFile)) {
    const setupConfig = readJsonFile(setupFile, `guided setup configuration for ${gameId}`);
    if (!setupConfig) {
      return res.status(500).json({ error: `Invalid guided setup configuration for ${gameId}` });
    }
    return res.json(setupConfig);
  }
  res.status(404).json({ error: `Guided setup configuration for ${gameId} not found` });
});

function serveGameIcon(req: Request, res: Response): void {
  const rawId = req.params.gameId as string;
  const gameId = getCanonicalGameSlug(path.basename(rawId).replace(/\.(png|jpg|webp)$/i, ''));
  
  const candidates = [
    path.join(GAMES_DIR, gameId, 'icon.png'),
    path.join(GAMES_DIR, gameId, 'icon.jpg'),
    path.join(GAMES_DIR, gameId, 'icon.webp'),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      res.setHeader('Cache-Control', 'public, max-age=86400');
      res.sendFile(path.resolve(candidate));
      return;
    }
  }
  res.status(404).json({ error: `Icon for ${gameId} not found` });
}

// Keep both URL forms while sharing one implementation.
gamesRouter.get('/:gameId/icon', serveGameIcon);
gamesRouter.get('/:gameId/icon.png', serveGameIcon);

// Options routes
optionsRouter.get('/:gameName', async (req: Request, res: Response) => {
  const gameName = req.params.gameName as string;
  const force = req.query.force === 'true';
  try {
    const schema = await getGameOptions(gameName, force);
    res.json(schema);
  } catch (error: any) {
    res.status(500).json({ error: error.message || `Failed to fetch options for ${gameName}` });
  }
});

// Launcher config route
launcherRouter.get('/config', async (req: Request, res: Response) => {
  try {
    const config = getLauncherConfig();
    try {
      const allGames = await getAvailableGames(false);
      for (const gameName of allGames) {
        if (!config.games[gameName]) {
          const norm = gameName.toLowerCase().replace(/[^a-z0-9]/g, '');
          const exists = Object.keys(config.games).some(k => k.toLowerCase().replace(/[^a-z0-9]/g, '') === norm);
          if (!exists) {
            config.games[gameName] = {
              game_name: gameName,
              support_tier: 4,
              launch_mode: "ap_client",
              client_tool: "archipelago_client",
              client_component: "Archipelago Text Client",
              auto_connect: true,
              clipboard_action: "copy_server_address",
              install_instructions: `Community / Core Game: Click Launch to open the Archipelago Client and copy connection details to clipboard.`
            };
          }
        }
      }
    } catch (e) {
      // Archipelago core may still be initializing; proceed with static configs
    }
    res.json(config);
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to load launcher configuration: ' + err.message });
  }
});

// Tools routes
toolsRouter.get('/', (req: Request, res: Response) => {
  const config = getLauncherConfig();
  res.json({ tools: config.tools });
});

toolsRouter.get('/:toolId', (req: Request, res: Response) => {
  const toolId = path.basename(req.params.toolId as string);
  const toolFile = path.join(TOOLS_DIR, `${toolId}.json`);
  if (fs.existsSync(toolFile)) {
    const toolConfig = readJsonFile(toolFile, `tool json ${toolId}`);
    if (!toolConfig) {
      return res.status(500).json({ error: `Invalid tool configuration for ${toolId}` });
    }
    return res.json(toolConfig);
  }
  const config = getLauncherConfig();
  if (config.tools[toolId]) {
    return res.json(config.tools[toolId]);
  }
  res.status(404).json({ error: `Tool ${toolId} not found` });
});
