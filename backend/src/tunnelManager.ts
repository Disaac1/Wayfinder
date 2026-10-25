import { spawn, execSync, ChildProcess } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';
import https from 'https';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.join(__dirname, '..');
const BIN_DIR = path.join(BACKEND_ROOT, 'bin');

let tunnelProcess: ChildProcess | null = null;

/**
 * Returns the expected cloudflared executable name for the current platform
 */
function getCloudflaredBinaryName(): string {
  return os.platform() === 'win32' ? 'cloudflared.exe' : 'cloudflared';
}

/**
 * Returns official release download URL for cloudflared based on OS and architecture
 */
function getCloudflaredDownloadUrl(): string | null {
  const platform = os.platform();
  const arch = os.arch();

  if (platform === 'win32') {
    return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe';
  } else if (platform === 'linux') {
    if (arch === 'arm64') {
      return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64';
    } else if (arch === 'arm') {
      return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm';
    }
    return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64';
  } else if (platform === 'darwin') {
    if (arch === 'arm64') {
      return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64';
    }
    return 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64';
  }
  return null;
}

/**
 * Downloads a file from a URL, following redirects
 */
async function downloadFile(url: string, destPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        // Follow redirect
        return downloadFile(res.headers.location, destPath).then(resolve).catch(reject);
      }

      if (res.statusCode !== 200) {
        return reject(new Error(`Failed to download cloudflared: HTTP status ${res.statusCode}`));
      }

      const fileStream = fs.createWriteStream(destPath);
      res.pipe(fileStream);

      fileStream.on('finish', () => {
        fileStream.close();
        resolve();
      });

      fileStream.on('error', (err) => {
        fs.unlink(destPath, () => {});
        reject(err);
      });
    }).on('error', reject);
  });
}

/**
 * Locates or automatically downloads the cloudflared binary
 */
export async function ensureCloudflaredBinary(): Promise<string> {
  const binaryName = getCloudflaredBinaryName();

  // 1. Check if cloudflared is already in PATH
  try {
    execSync(`${binaryName} --version`, { stdio: 'ignore' });
    return binaryName;
  } catch {}

  // 2. Check in backend/bin/
  const localBinaryPath = path.join(BIN_DIR, binaryName);
  if (fs.existsSync(localBinaryPath)) {
    return localBinaryPath;
  }

  // 3. Auto-download from GitHub releases
  const downloadUrl = getCloudflaredDownloadUrl();
  if (!downloadUrl) {
    throw new Error(`Unsupported platform/architecture for automated cloudflared download: ${os.platform()} (${os.arch()})`);
  }

  if (!fs.existsSync(BIN_DIR)) {
    fs.mkdirSync(BIN_DIR, { recursive: true });
  }

  console.log(`[Cloudflare Tunnel] Downloading cloudflared binary for ${os.platform()} (${os.arch()})...`);
  const tempPath = `${localBinaryPath}.tmp`;
  await downloadFile(downloadUrl, tempPath);
  fs.renameSync(tempPath, localBinaryPath);

  if (os.platform() !== 'win32') {
    fs.chmodSync(localBinaryPath, 0o755);
  }

  console.log(`[Cloudflare Tunnel] cloudflared downloaded successfully to: ${localBinaryPath}`);
  return localBinaryPath;
}

/**
 * Spawns and manages the Cloudflare Tunnel daemon
 */
export async function startCloudflareTunnel(): Promise<ChildProcess | null> {
  const token = process.env.CLOUDFLARE_TUNNEL_TOKEN?.trim();

  if (!token) {
    console.log('[Cloudflare Tunnel] CLOUDFLARE_TUNNEL_TOKEN not provided in .env; running backend without automated tunnel.');
    return null;
  }

  try {
    const binary = await ensureCloudflaredBinary();
    console.log(`[Cloudflare Tunnel] Starting tunnel using token on ${os.hostname()}...`);

    tunnelProcess = spawn(binary, ['tunnel', 'run', '--token', token], {
      stdio: ['ignore', 'pipe', 'pipe']
    });

    tunnelProcess.stdout?.on('data', (data) => {
      const line = data.toString().trim();
      if (line) {
        console.log(`[Cloudflare] ${line}`);
      }
    });

    tunnelProcess.stderr?.on('data', (data) => {
      const line = data.toString().trim();
      // cloudflared logs diagnostic output to stderr in JSON or plain text
      if (line.includes('Registered tunnel connection') || line.includes('Connection') && line.includes('registered')) {
        console.log(`\x1b[32m[Cloudflare Tunnel Connected]\x1b[0m ${line}`);
      } else if (line.toLowerCase().includes('error')) {
        console.error(`[Cloudflare Tunnel Error] ${line}`);
      }
    });

    tunnelProcess.on('exit', (code, signal) => {
      console.warn(`[Cloudflare Tunnel] Process terminated (code: ${code}, signal: ${signal})`);
      tunnelProcess = null;
    });

    // Cleanup on process shutdown
    const cleanup = () => {
      if (tunnelProcess) {
        console.log('[Cloudflare Tunnel] Shutting down tunnel daemon...');
        try {
          tunnelProcess.kill();
        } catch {}
        tunnelProcess = null;
      }
    };

    process.on('SIGINT', cleanup);
    process.on('SIGTERM', cleanup);
    process.on('exit', cleanup);

    return tunnelProcess;
  } catch (err: any) {
    console.error('[Cloudflare Tunnel] Failed to start tunnel:', err.message);
    return null;
  }
}

/**
 * Stops the running tunnel process if active
 */
export function stopCloudflareTunnel(): void {
  if (tunnelProcess) {
    console.log('[Cloudflare Tunnel] Stopping tunnel...');
    try {
      tunnelProcess.kill();
    } catch {}
    tunnelProcess = null;
  }
}
