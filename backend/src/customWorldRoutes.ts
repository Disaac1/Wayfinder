import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import AdmZip from 'adm-zip';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const CUSTOM_WORLDS_DIR = path.join(__dirname, '..', 'archipelago_core', 'custom_worlds');

const router = Router();

// 1. List custom worlds
router.get('/', (req: Request, res: Response) => {
  try {
    if (!fs.existsSync(CUSTOM_WORLDS_DIR)) {
      return res.json({ worlds: [] });
    }
    const files = fs.readdirSync(CUSTOM_WORLDS_DIR).filter(f => f.endsWith('.apworld'));
    const worlds = files.map(filename => {
      const filePath = path.join(CUSTOM_WORLDS_DIR, filename);
      const stat = fs.statSync(filePath);
      let game = '';
      try {
        const zip = new AdmZip(filePath);
        const entry = zip.getEntries().find(e => e.entryName.endsWith('archipelago.json') || e.entryName.endsWith('manifest.json'));
        if (entry) {
          const parsed = JSON.parse(entry.getData().toString('utf8'));
          game = parsed.game || parsed.world || parsed.name || '';
        }
      } catch {}
      return {
        game,
        filename,
        size: stat.size,
        modified: stat.mtime.toISOString(),
      };
    });
    res.json({ worlds });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to list custom worlds: ' + err.message });
  }
});

// 2. Download custom world .apworld
router.get('/:worldName', (req: Request, res: Response) => {
  const safeFilename = path.basename(req.params.worldName as string);
  if (!safeFilename.endsWith('.apworld')) {
    return res.status(400).json({ error: 'Filename must end with .apworld' });
  }
  const filePath = path.join(CUSTOM_WORLDS_DIR, safeFilename);
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: `Custom world ${safeFilename} not found` });
  }
  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Disposition', `attachment; filename="${safeFilename}"`);
  res.sendFile(filePath);
});

export default router;
