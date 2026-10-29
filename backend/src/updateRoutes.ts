import { Router, Request, Response } from 'express';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import multer from 'multer';
import { localhostOnly } from './adminRoutes.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const BACKEND_ROOT = path.join(__dirname, '..');
const UPDATES_DIR = path.join(BACKEND_ROOT, 'public', 'updates');
const DOWNLOADS_DIR = path.join(BACKEND_ROOT, 'public', 'downloads');
const VERSION_FILE = path.join(UPDATES_DIR, 'version.json');
const PCK_FILE = fs.existsSync(path.join(UPDATES_DIR, 'Lodestone.pck'))
  ? path.join(UPDATES_DIR, 'Lodestone.pck')
  : path.join(UPDATES_DIR, 'Wayfinder.pck');
const BRIDGE_VERSION_FILE = path.join(UPDATES_DIR, 'bridge-version.json');
const BRIDGE_PCK_FILE = fs.existsSync(path.join(UPDATES_DIR, 'Lodestone-bridge.pck'))
  ? path.join(UPDATES_DIR, 'Lodestone-bridge.pck')
  : path.join(UPDATES_DIR, 'Wayfinder-bridge.pck');
const PRIV_KEY_FILE = path.join(BACKEND_ROOT, 'certs', 'updater_private_key.pem');
const LEGACY_UPDATE_CUTOFF = '1.0.6';
const BRIDGE_VERSION = '1.0.9';
const MANUAL_UPDATE_URL = '/api/client/download-client';

// Ensure directories exist
if (!fs.existsSync(UPDATES_DIR)) {
  fs.mkdirSync(UPDATES_DIR, { recursive: true });
}
if (!fs.existsSync(DOWNLOADS_DIR)) {
  fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
}


interface GitHubAsset {
  name: string;
  browser_download_url: string;
  size: number;
}

interface GitHubRelease {
  tag_name: string;
  name: string;
  html_url: string;
  published_at: string;
  assets: GitHubAsset[];
}

let cachedRelease: { release: GitHubRelease; timestamp: number } | null = null;
const GITHUB_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

export async function fetchLatestGitHubRelease(forceRefresh = false, tag?: string): Promise<GitHubRelease | null> {
  const now = Date.now();
  if (!forceRefresh && !tag && cachedRelease && (now - cachedRelease.timestamp) < GITHUB_CACHE_TTL_MS) {
    return cachedRelease.release;
  }

  const endpoint = tag
    ? `https://api.github.com/repos/Disaac1/Wayfinder/releases/tags/${encodeURIComponent(tag)}`
    : 'https://api.github.com/repos/Disaac1/Wayfinder/releases/latest';

  const headers: Record<string, string> = {
    'User-Agent': 'Wayfinder-Lodestone-Backend',
    'Accept': 'application/vnd.github.v3+json'
  };

  const githubToken = process.env.GITHUB_TOKEN;
  if (githubToken) {
    headers['Authorization'] = `Bearer ${githubToken}`;
  }

  try {
    const res = await fetch(endpoint, { headers });

    if (!res.ok) {
      console.warn(`[GitHub Releases] API returned HTTP ${res.status} for ${endpoint}`);
      return cachedRelease ? cachedRelease.release : null;
    }

    const data = await res.json() as GitHubRelease;
    cachedRelease = { release: data, timestamp: now };
    console.log(`[GitHub Releases] Cached release: ${data.tag_name} (${data.name})`);
    return data;
  } catch (err: any) {
    console.warn('[GitHub Releases] Error fetching release:', err.message);
    return cachedRelease ? cachedRelease.release : null;
  }
}

// Background polling: keep the release metadata fresh every 10 minutes
const GITHUB_POLL_INTERVAL_MS = 10 * 60 * 1000;
const githubPoller = setInterval(() => {
  fetchLatestGitHubRelease(true).catch(err => {
    console.warn('[GitHub Releases] Background poll error:', err.message);
  });
}, GITHUB_POLL_INTERVAL_MS);

// Allow Node process to terminate cleanly without waiting on poller timer
if (githubPoller.unref) {
  githubPoller.unref();
}

// Initial async fetch on module load
fetchLatestGitHubRelease().catch(() => {});

export function signBuffer(buffer: Buffer): { sha256: string; signature: string } | null {
  if (!fs.existsSync(PRIV_KEY_FILE)) {
    console.warn(`[Update Signer] Private key not found at ${PRIV_KEY_FILE}. Updates will be unsigned.`);
    return null;
  }
  try {
    const privKey = fs.readFileSync(PRIV_KEY_FILE, 'utf8');
    const sha256 = crypto.createHash('sha256').update(buffer).digest('hex');
    const signer = crypto.createSign('SHA256');
    signer.update(buffer);
    const signature = signer.sign(privKey).toString('base64');
    return { sha256, signature };
  } catch (err: any) {
    console.error('[Update Signer] Error generating signature:', err.message);
    return null;
  }
}

// Ensure default version file exists
if (!fs.existsSync(VERSION_FILE)) {
  fs.writeFileSync(VERSION_FILE, JSON.stringify({
    version: '1.0.0',
    min_version: '1.0.0',
    release_date: new Date().toISOString(),
    notes: 'Initial release',
    pck_filename: 'Lodestone.pck',
    pck_size: 0,
    sha256: '',
    signature: ''
  }, null, 2), 'utf8');
}

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 100 * 1024 * 1024 } // 100MB
});

/**
 * GET /api/client/version
 * Public endpoint queried by Godot client on startup to check for available updates
 */
router.get('/version', (req: Request, res: Response) => {
  try {
    const clientVersion = typeof req.query.client_version === 'string'
      ? req.query.client_version
      : '';
    const legacyClient = !clientVersion || isVersionAtOrBelow(clientVersion, LEGACY_UPDATE_CUTOFF);
    if (legacyClient) {
      const currentManifest = fs.existsSync(VERSION_FILE)
        ? JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8'))
        : { version: '1.1.0' };
      return res.json({
        version: currentManifest.version,
        target_version: currentManifest.version,
        current_version: clientVersion || 'unknown',
        update_required: true,
        requires_full_install: true,
        update_mode: 'manual',
        force_restart: false,
        download_url: MANUAL_UPDATE_URL,
        message: 'This version is no longer supported. Download and install the latest version of Lodestone.'
      });
    }
    const manifestFile = VERSION_FILE;
    const packageFile = PCK_FILE;
    if (fs.existsSync(manifestFile)) {
      const data = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
      const hasPck = fs.existsSync(packageFile);
      if (hasPck) {
        const stats = fs.statSync(packageFile);
        data.pck_size = stats.size;
        // If file exists but sha256 or signature is missing, auto-sign on the fly if key is available
        if (!data.signature && fs.existsSync(PRIV_KEY_FILE)) {
          const fileBuf = fs.readFileSync(packageFile);
          const sigResult = signBuffer(fileBuf);
          if (sigResult) {
            data.sha256 = sigResult.sha256;
            data.signature = sigResult.signature;
            fs.writeFileSync(VERSION_FILE, JSON.stringify(data, null, 2), 'utf8');
          }
        }
      }
      return res.json({
        ...data,
        has_pck: hasPck,
        download_url: data.download_url || '/api/client/download-pck',
        update_mode: clientVersion === BRIDGE_VERSION ? 'finalize' : 'normal',
        force_restart: clientVersion === BRIDGE_VERSION,
        target_version: data.target_version || data.version
      });
    }
    res.json({
      version: '1.0.0',
      min_version: '1.0.0',
      has_pck: false,
      notes: 'No update packages available',
      update_mode: 'normal',
      force_restart: false
    });
  } catch (err: any) {
    res.status(500).json({ error: `Failed to read version metadata: ${err.message}` });
  }
});

function isVersionAtOrBelow(version: string, maximum: string): boolean {
  const parse = (value: string): number[] => value.split('.').map((part) => {
    const match = part.match(/^\d+/);
    return match ? Number(match[0]) : 0;
  });
  const left = parse(version);
  const right = parse(maximum);
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const leftPart = left[index] || 0;
    const rightPart = right[index] || 0;
    if (leftPart < rightPart) return true;
    if (leftPart > rightPart) return false;
  }
  return true;
}

/**
 * POST /api/client/sync-release
 * Authenticated webhook to trigger instant sync of latest GitHub release
 * Can be called by GitHub Actions upon publishing a release or by admins.
 * Protected by RELEASE_WEBHOOK_SECRET or localhost access.
 */
router.post('/sync-release', async (req: Request, res: Response) => {
  const webhookSecret = process.env.RELEASE_WEBHOOK_SECRET;
  const authHeader = req.headers['authorization'];
  const tokenFromAuth = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
  const clientSecret = req.headers['x-release-secret'] || tokenFromAuth;

  const clientIp = req.ip || req.socket.remoteAddress || '';
  const isLocal = clientIp === '127.0.0.1' || clientIp === '::1' || clientIp === '::ffff:127.0.0.1' || req.hostname === 'localhost';
  const isSecretValid = Boolean(webhookSecret && clientSecret && clientSecret === webhookSecret);

  if (!isSecretValid && !isLocal) {
    return res.status(401).json({ error: 'Unauthorized: invalid or missing release webhook secret' });
  }

  const requestedTag = typeof req.body?.tag === 'string' ? req.body.tag.trim() : undefined;
  console.log(`[GitHub Releases] Release sync triggered via webhook${requestedTag ? ` for tag: ${requestedTag}` : ''}`);

  try {
    const release = await fetchLatestGitHubRelease(true, requestedTag);
    if (!release) {
      return res.status(502).json({
        success: false,
        message: 'Webhook received but failed to retrieve release from GitHub API'
      });
    }

    res.json({
      success: true,
      message: 'Release synced successfully',
      tag: release.tag_name,
      version: release.tag_name.replace(/^v/, ''),
      name: release.name,
      published_at: release.published_at,
      asset_count: release.assets?.length || 0
    });
  } catch (err: any) {
    console.error('[GitHub Releases] Error processing sync-release webhook:', err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/client/download-info
 * Returns metadata and direct download URLs for the latest GitHub release
 */
router.get('/download-info', async (req: Request, res: Response) => {
  const release = await fetchLatestGitHubRelease();
  if (release) {
    const setupAsset = release.assets.find(a => /setup.*\.exe$/i.test(a.name)) ||
                       release.assets.find(a => /\.exe$/i.test(a.name));
    const zipAsset = release.assets.find(a => /windows.*\.zip$/i.test(a.name));
    const linuxAsset = release.assets.find(a => /linux.*\.(tar\.gz|zip)$/i.test(a.name));

    return res.json({
      tag: release.tag_name,
      version: release.tag_name.replace(/^v/, ''),
      name: release.name,
      html_url: release.html_url,
      published_at: release.published_at,
      installer_url: setupAsset?.browser_download_url || 'https://github.com/Disaac1/Wayfinder/releases/latest/download/Lodestone_Setup.exe',
      portable_url: zipAsset?.browser_download_url || 'https://github.com/Disaac1/Wayfinder/releases/latest/download/Lodestone_Windows.zip',
      linux_url: linuxAsset?.browser_download_url || null,
      assets: release.assets.map(a => ({ name: a.name, size: a.size, url: a.browser_download_url }))
    });
  }

  res.json({
    tag: 'latest',
    version: 'latest',
    html_url: 'https://github.com/Disaac1/Wayfinder/releases/latest',
    installer_url: 'https://github.com/Disaac1/Wayfinder/releases/latest/download/Lodestone_Setup.exe',
    portable_url: 'https://github.com/Disaac1/Wayfinder/releases/latest/download/Lodestone_Windows.zip',
    linux_url: null,
    assets: []
  });
});

/**
 * GET /api/client/download-client
 * Redirects directly to the latest executable installer on GitHub Releases
 * Supports query parameters: ?type=zip or ?platform=linux
 */
router.get('/download-client', async (req: Request, res: Response) => {
  const platform = String(req.query.platform || '').toLowerCase();
  const format = String(req.query.format || req.query.type || '').toLowerCase();

  // 1. Resolve matching binary from latest GitHub Release
  try {
    const release = await fetchLatestGitHubRelease();
    if (release && Array.isArray(release.assets) && release.assets.length > 0) {
      let matchedAsset: GitHubAsset | undefined;

      if (platform === 'linux') {
        matchedAsset = release.assets.find(a => /linux.*\.tar\.gz$/i.test(a.name)) ||
                       release.assets.find(a => /linux.*\.zip$/i.test(a.name));
      } else if (format === 'zip' || format === 'portable') {
        matchedAsset = release.assets.find(a => /windows.*\.zip$/i.test(a.name));
      } else {
        // Default: Windows installer .exe
        matchedAsset = release.assets.find(a => /setup.*\.exe$/i.test(a.name)) ||
                       release.assets.find(a => /\.exe$/i.test(a.name)) ||
                       release.assets.find(a => /windows.*\.zip$/i.test(a.name));
      }

      if (matchedAsset && matchedAsset.browser_download_url) {
        return res.redirect(302, matchedAsset.browser_download_url);
      }
    }
  } catch (err: any) {
    console.warn('[Download Client] GitHub redirect resolution failed:', err.message);
  }

  // 2. Fall back to local downloads if present on server disk
  const installerCandidates = ['Lodestone_Setup.exe', 'Wayfinder_Setup.exe'];
  const zipCandidates = ['Lodestone_Windows.zip', 'Wayfinder_Windows.zip'];

  for (const name of installerCandidates) {
    const p = path.join(DOWNLOADS_DIR, name);
    if (fs.existsSync(p)) {
      const stat = fs.statSync(p);
      res.writeHead(200, {
        'Content-Type': 'application/octet-stream',
        'Content-Length': stat.size,
        'Content-Disposition': `attachment; filename="${name}"`
      });
      return fs.createReadStream(p).pipe(res);
    }
  }

  for (const name of zipCandidates) {
    const p = path.join(DOWNLOADS_DIR, name);
    if (fs.existsSync(p)) {
      const stat = fs.statSync(p);
      res.writeHead(200, {
        'Content-Type': 'application/zip',
        'Content-Length': stat.size,
        'Content-Disposition': `attachment; filename="${name}"`
      });
      return fs.createReadStream(p).pipe(res);
    }
  }

  if (fs.existsSync(PCK_FILE)) {
    return res.redirect('/api/client/download-pck');
  }

  // 3. Fallback redirect to GitHub Releases latest page
  return res.redirect(302, 'https://github.com/Disaac1/Wayfinder/releases/latest');
});

/**
 * GET /api/client/download-pck
 * Streams the latest exported Godot package (.pck) to the client
 */
router.get('/download-pck', (req: Request, res: Response) => {
  const bridge = req.query.channel === 'bridge';
  const packageFile = bridge ? BRIDGE_PCK_FILE : PCK_FILE;
  if (!fs.existsSync(packageFile)) {
    return res.status(404).json({ error: 'No update .pck package available on server' });
  }

  const stat = fs.statSync(packageFile);
  const pckName = path.basename(packageFile);
  res.writeHead(200, {
    'Content-Type': 'application/octet-stream',
    'Content-Length': stat.size,
    'Content-Disposition': `attachment; filename="${pckName}"`
  });

  const readStream = fs.createReadStream(packageFile);
  readStream.pipe(res);
});

/**
 * POST /api/admin/updates/upload-pck
 * Upload a new .pck file, digitally sign it, and update the published version (localhost only)
 */
router.post('/upload-pck', localhostOnly, upload.single('pck'), (req: Request, res: Response) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No .pck file uploaded' });
  }

  const newVersion = req.body.version || '1.0.1';
  const notes = req.body.notes || 'Automated update';

  try {
    fs.writeFileSync(PCK_FILE, req.file.buffer);

    const sigResult = signBuffer(req.file.buffer);

    const versionData = {
      version: newVersion,
      min_version: req.body.min_version || '1.0.0',
      release_date: new Date().toISOString(),
      notes: notes,
      pck_filename: 'Lodestone.pck',
      pck_size: req.file.buffer.length,
      sha256: sigResult ? sigResult.sha256 : '',
      signature: sigResult ? sigResult.signature : ''
    };
    fs.writeFileSync(VERSION_FILE, JSON.stringify(versionData, null, 2), 'utf8');

    console.log(`[Update Manager] Published digitally signed client update: v${newVersion} (${req.file.buffer.length} bytes)`);
    res.json({ success: true, version: versionData });
  } catch (err: any) {
    console.error('[Update Manager] Failed to save .pck update:', err);
    res.status(500).json({ error: err.message });
  }
});

export default router;
