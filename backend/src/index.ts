import express from 'express';
import http from 'http';
import net from 'net';
import { WebSocketServer } from 'ws';
import path from 'path';
import fs from 'fs';
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';

import { handleConnection } from './roomManager.js';
import { killAllServers, getRoomPort } from './serverManager.js';
import { ensureArchipelagoCore, getAvailableGames, clearCache } from './archipelagoRunner.js';
import { startCloudflareTunnel, stopCloudflareTunnel } from './tunnelManager.js';
import adminRoutes, { localhostOnly } from './adminRoutes.js';
import updateRoutes from './updateRoutes.js';
import sessionRoutes from './sessionRoutes.js';
import roomRoutes, { testCleanupHandler } from './roomRoutes.js';
import customWorldRoutes from './customWorldRoutes.js';
import seedRoutes from './seedRoutes.js';
import clientLogRoutes from './clientLogRoutes.js';
import { gamesRouter, optionsRouter, launcherRouter, toolsRouter, getLauncherConfig } from './launcherRoutes.js';
import { getValidatedRoomCode } from './utils.js';

// Re-export common utilities for backward-compatibility
export { getValidatedRoomCode, getLauncherConfig };

// Load environment variables
dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PUBLIC_TOOLS_DIR = path.join(__dirname, '..', 'public', 'tools');
const ADMIN_UI_DIR = path.join(__dirname, '..', 'public', 'admin');
const LANDING_PAGE_DIR = path.join(__dirname, '..', 'public', 'landing');
const DATA_DIR = path.join(__dirname, '..', 'data');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
const HOST = process.env.HOST;

const app = express();
app.use(express.json());

// Enable CORS for frontend requests if needed
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  next();
});

// Static asset directories
app.use('/tools', express.static(PUBLIC_TOOLS_DIR));
app.use('/admin', localhostOnly, express.static(ADMIN_UI_DIR));
app.use('/data', express.static(DATA_DIR));

// Keep clients using the retired catalog URL on the current catalog.
app.get('/rom.json', (_req, res) => {
  res.redirect(308, '/roms.json');
});

app.use(express.static(LANDING_PAGE_DIR));

// Landing page root
app.get('/', (req, res) => {
  const indexPath = path.join(LANDING_PAGE_DIR, 'index.html');
  res.sendFile(indexPath);
});

// Endpoint to serve roms.json catalog (temporary)
app.get('/roms.json', (req, res) => {
  if (fs.existsSync(path.join(DATA_DIR, 'roms.json'))) {
    res.setHeader('Content-Type', 'application/json');
    return res.sendFile(path.resolve(path.join(DATA_DIR, 'roms.json')));
  }  
  res.status(404).json({ error: 'roms.json not found on server' });
});

// Modular Feature Routers
app.use('/api/admin', adminRoutes);
app.use('/api/client', updateRoutes);
app.use('/api/admin/updates', updateRoutes);
app.use('/api/session', sessionRoutes);
app.use('/api/rooms', roomRoutes);
app.use('/api/games', gamesRouter);
app.use('/api/options', optionsRouter);
app.use('/api/launcher', launcherRouter);
app.use('/api/tools', toolsRouter);
app.use('/api/custom-worlds', customWorldRoutes);
app.use('/api/seeds', seedRoutes);
app.use('/api/client/logs', clientLogRoutes);
app.post('/api/test/cleanup', localhostOnly, testCleanupHandler);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', time: new Date().toISOString() });
});

// Clear options and games cache manually
app.all('/api/cache/clear', (req, res) => {
  clearCache();
  res.json({ success: true, message: 'Caches cleared successfully' });
});

// Create HTTP server wrapping Express app
const server = http.createServer(app);

// Attach WebSocket Server without binding directly to server so we can multiplex upgrades
const wss = new WebSocketServer({ noServer: true });

wss.on('connection', (ws) => {
  handleConnection(ws);
});

// Multiplex HTTP Upgrade requests:
// 1. /ap/:roomCode or /ap/:port -> proxy directly to local Archipelago MultiServer
// 2. All other paths -> Wayfinder Lobby WebSocket Server
server.on('upgrade', (req, clientSocket, head) => {
  const reqUrl = req.url || '';
  if (reqUrl.startsWith('/ap/')) {
    const cleanPath = reqUrl.slice('/ap/'.length);
    const roomIdentifier = cleanPath.split(/[?#/]/)[0];
    const targetPort = getRoomPort(roomIdentifier);

    if (!targetPort) {
      clientSocket.write('HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nArchipelago Room not found or not active\r\n');
      clientSocket.destroy();
      return;
    }

    const targetSocket = net.connect(targetPort, '127.0.0.1', () => {
      const socket = clientSocket as net.Socket;
      if (typeof socket.setKeepAlive === 'function') socket.setKeepAlive(true, 10000);
      if (typeof socket.setNoDelay === 'function') socket.setNoDelay(true);
      targetSocket.setKeepAlive(true, 10000);
      targetSocket.setNoDelay(true);

      const queryIdx = reqUrl.indexOf('?');
      const newPath = queryIdx !== -1 ? reqUrl.slice(queryIdx) : '/';

      let rawHeaders = `${req.method} ${newPath} HTTP/${req.httpVersion}\r\n`;
      if (req.rawHeaders) {
        for (let i = 0; i < req.rawHeaders.length; i += 2) {
          const key = req.rawHeaders[i];
          let val = req.rawHeaders[i + 1];
          if (key.toLowerCase() === 'host') {
            val = `127.0.0.1:${targetPort}`;
          }
          rawHeaders += `${key}: ${val}\r\n`;
        }
      }
      rawHeaders += '\r\n';

      targetSocket.write(rawHeaders);
      if (head && head.length > 0) {
        targetSocket.write(head);
      }

      clientSocket.pipe(targetSocket);
      targetSocket.pipe(clientSocket);

      // Start 15-second active WebSocket Ping heartbeat to prevent Cloudflare Tunnel idle timeouts (100s limit)
      // RFC 6455 unmasked Ping frame: 0x89 (FIN + Opcode 0x9), 0x00 (Payload length 0)
      const PING_FRAME = Buffer.from([0x89, 0x00]);
      let proxyCleanedUp = false;
      const heartbeatInterval = setInterval(() => {
        if (!clientSocket.destroyed && clientSocket.writable) {
          try {
            clientSocket.write(PING_FRAME);
          } catch (e) {
            clearInterval(heartbeatInterval);
          }
        } else {
          clearInterval(heartbeatInterval);
        }
      }, 15000);

      const cleanup = () => {
        if (proxyCleanedUp) {
          return;
        }
        proxyCleanedUp = true;
        clearInterval(heartbeatInterval);
        console.log(`[ARCHIPELAGO_GAME_PROXY] Closing proxied game connection for ${roomIdentifier} (local port ${targetPort})`);
        if (!targetSocket.destroyed) {
          targetSocket.destroy();
        }
        if (!clientSocket.destroyed) {
          clientSocket.destroy();
        }
      };

      targetSocket.on('error', (err) => {
        console.warn(`[ARCHIPELAGO_GAME_PROXY] Error connecting to local AP server on port ${targetPort}:`, err.message);
        cleanup();
      });

      clientSocket.on('error', (err: any) => {
        console.warn(`[ARCHIPELAGO_GAME_PROXY] Client socket error on port ${targetPort}:`, err.message);
        cleanup();
      });

      console.log(`[ARCHIPELAGO_GAME_PROXY] Game connection established for ${roomIdentifier} (local port ${targetPort})`);
      clientSocket.on('close', cleanup);
      targetSocket.on('close', cleanup);
    });
  } else {
    // Normal Wayfinder Lobby WebSocket upgrade
    console.log(`[LODESTONE_LOBBY] WebSocket upgrade requested for ${reqUrl}`);
    wss.handleUpgrade(req, clientSocket, head, (ws) => {
      wss.emit('connection', ws, req);
    });
  }
});

// Initialize Archipelago core and start listening
async function startServer() {
  try {
    await ensureArchipelagoCore();
    
    // Pre-warm the games list cache in background so first client request is instantaneous
    getAvailableGames(false).then((games) => {
      console.log(`[Cache Warmup] Pre-warmed ${games.length} available Archipelago games into SQLite cache.`);
    }).catch(err => {
      console.warn('[Cache Warmup] Background games pre-warming warning:', err.message);
    });

    const listenCallback = () => {
      const publicDomain = process.env.PUBLIC_DOMAIN || 'wayfinder.disaac1.com';
      console.log(`===============================================`);
      console.log(`  Lodestone Lobby Backend running on port ${PORT}`);
      console.log(`  Local WebSocket:  ws://localhost:${PORT}`);
      console.log(`  Local HTTP API:   http://localhost:${PORT}`);
      if (process.env.CLOUDFLARE_TUNNEL_TOKEN) {
        console.log(`  Cloudflare Host:  https://${publicDomain}`);
        console.log(`  Cloudflare WSS:   wss://${publicDomain}`);
      }
      console.log(`===============================================`);

      // Start automated Cloudflare Tunnel if token provided
      startCloudflareTunnel().catch(err => {
        console.error('[Cloudflare Tunnel] Error during tunnel startup:', err);
      });
    };

    const bindHost = HOST || '0.0.0.0';
    server.listen(PORT, bindHost, listenCallback);
  } catch (err) {
    console.error('Failed to initialize Archipelago core repository, aborting startup:', err);
    process.exit(1);
  }
}

startServer();

// Graceful shutdown
const shutdown = () => {
  console.log('Shutting down server...');
  stopCloudflareTunnel();
  killAllServers();
  server.close(() => {
    console.log('Server stopped.');
    process.exit(0);
  });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

process.on('uncaughtException', (err) => {
  console.error('[Backend Uncaught Exception]:', err);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('[Backend Unhandled Rejection]:', reason);
});
