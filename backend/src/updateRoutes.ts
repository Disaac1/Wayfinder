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
const PCK_FILE = path.join(UPDATES_DIR, 'Wayfinder.pck');
const PRIV_KEY_FILE = path.join(BACKEND_ROOT, 'certs', 'updater_private_key.pem');

// Ensure directories exist
if (!fs.existsSync(UPDATES_DIR)) {
  fs.mkdirSync(UPDATES_DIR, { recursive: true });
}
if (!fs.existsSync(DOWNLOADS_DIR)) {
  fs.mkdirSync(DOWNLOADS_DIR, { recursive: true });
}

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
    pck_filename: 'Wayfinder.pck',
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
    if (fs.existsSync(VERSION_FILE)) {
      const data = JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8'));
      const hasPck = fs.existsSync(PCK_FILE);
      if (hasPck) {
        const stats = fs.statSync(PCK_FILE);
        data.pck_size = stats.size;
        // If file exists but sha256 or signature is missing, auto-sign on the fly if key is available
        if (!data.signature && fs.existsSync(PRIV_KEY_FILE)) {
          const fileBuf = fs.readFileSync(PCK_FILE);
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
        download_url: '/api/client/download-pck'
      });
    }
    res.json({
      version: '1.0.0',
      min_version: '1.0.0',
      has_pck: false,
      notes: 'No update packages available'
    });
  } catch (err: any) {
    res.status(500).json({ error: `Failed to read version metadata: ${err.message}` });
  }
});

/**
 * GET /api/client/download-client
 * Streams the latest Windows installer (.exe) or portable archive (.zip)
 */
router.get('/download-client', (req: Request, res: Response) => {
  const installerPath = path.join(DOWNLOADS_DIR, 'Wayfinder_Setup.exe');
  const zipPath = path.join(DOWNLOADS_DIR, 'Wayfinder_Windows.zip');

  if (fs.existsSync(installerPath)) {
    const stat = fs.statSync(installerPath);
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': stat.size,
      'Content-Disposition': 'attachment; filename="Wayfinder_Setup.exe"'
    });
    return fs.createReadStream(installerPath).pipe(res);
  }

  if (fs.existsSync(zipPath)) {
    const stat = fs.statSync(zipPath);
    res.writeHead(200, {
      'Content-Type': 'application/zip',
      'Content-Length': stat.size,
      'Content-Disposition': 'attachment; filename="Wayfinder_Windows.zip"'
    });
    return fs.createReadStream(zipPath).pipe(res);
  }

  if (fs.existsSync(PCK_FILE)) {
    return res.redirect('/api/client/download-pck');
  }

  res.status(404).json({ error: 'No client package or installer currently available' });
});

/**
 * GET /api/client/download-pck
 * Streams the latest exported Godot package (.pck) to the client
 */
router.get('/download-pck', (req: Request, res: Response) => {
  if (!fs.existsSync(PCK_FILE)) {
    return res.status(404).json({ error: 'No update .pck package available on server' });
  }

  const stat = fs.statSync(PCK_FILE);
  res.writeHead(200, {
    'Content-Type': 'application/octet-stream',
    'Content-Length': stat.size,
    'Content-Disposition': 'attachment; filename="Wayfinder.pck"'
  });

  const readStream = fs.createReadStream(PCK_FILE);
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
      pck_filename: 'Wayfinder.pck',
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
