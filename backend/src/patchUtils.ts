import path from 'path';
import fs from 'fs';
import AdmZip from 'adm-zip';
import db from './db.js';

/**
 * Injects the server host:port into archipelago.json inside an .ap* patch file
 */
export function injectServerIntoPatchFile(patchFilePath: string, roomCode: string, explicitServerAddr?: string): void {
  try {
    let serverAddress = explicitServerAddr;

    if (!serverAddress) {
      let sPort: number | undefined;
      let sHost: string = process.env.PUBLIC_HOST || 'localhost';

      try {
        const roomInfo = db.prepare("SELECT server_ip, server_port, tunnel_url FROM Rooms WHERE code = ?").get(roomCode) as { server_ip?: string; server_port?: number; tunnel_url?: string } | undefined;
        if (roomInfo) {
          if (roomInfo.tunnel_url && (roomInfo.tunnel_url.startsWith('wss://') || roomInfo.tunnel_url.startsWith('ws://'))) {
            serverAddress = roomInfo.tunnel_url;
          } else {
            if (roomInfo.server_ip && roomInfo.server_ip.trim()) {
              sHost = roomInfo.server_ip.trim();
            }
            if (roomInfo.server_port) {
              sPort = roomInfo.server_port;
            }
          }
        }
      } catch {}

      if (!serverAddress && sPort) {
        serverAddress = `${sHost}:${sPort}`;
      }
    }

    if (serverAddress) {
      const pZip = new AdmZip(patchFilePath);
      const archEntry = pZip.getEntry('archipelago.json');
      if (archEntry) {
        const archJson = JSON.parse(archEntry.getData().toString('utf8'));
        if (archJson.server !== serverAddress) {
          archJson.server = serverAddress;
          pZip.updateFile('archipelago.json', Buffer.from(JSON.stringify(archJson, null, 2)));
          pZip.writeZip();
          console.log(`[PatchUtils] Injected server address ${serverAddress} into patch: ${patchFilePath}`);
        }
      }
    }
  } catch (err: any) {
    console.warn(`[PatchUtils] Could not inject server into patch ${patchFilePath}:`, err.message);
  }
}

/**
 * Injects server address into all .ap patch archives in the outputs directory
 */
export function injectServerAddressIntoOutputs(outputsDir: string, serverAddress: string): void {
  if (!fs.existsSync(outputsDir)) return;
  const files = fs.readdirSync(outputsDir);
  for (const file of files) {
    if (file.toLowerCase().includes('.ap') && !file.endsWith('.zip') && !file.endsWith('.txt') && !file.endsWith('.json') && !file.endsWith('.bin') && !file.endsWith('.cue') && !file.endsWith('.gba')) {
      const patchPath = path.join(outputsDir, file);
      try {
        const pZip = new AdmZip(patchPath);
        const archEntry = pZip.getEntry('archipelago.json');
        if (archEntry) {
          const archJson = JSON.parse(archEntry.getData().toString('utf8'));
          archJson.server = serverAddress;
          pZip.updateFile('archipelago.json', Buffer.from(JSON.stringify(archJson, null, 2)));
          pZip.writeZip();
          console.log(`[PatchUtils] Injected server address ${serverAddress} into ${file}`);
        }
      } catch (err: any) {
        console.warn(`[PatchUtils] Could not update patch file ${file}:`, err.message);
      }
    }
  }
}
