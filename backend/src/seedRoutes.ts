import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import AdmZip from 'adm-zip';
import express from 'express';
import { injectServerIntoPatchFile } from './patchUtils.js';
import { getLauncherConfig } from './launcherRoutes.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const TEMP_SEEDS_DIR = path.join(__dirname, '..', 'temp_seeds');

const router = Router();

// Helper to check if an entry matches ignore extensions
function isIgnoredFile(name: string): boolean {
  const lower = name.toLowerCase();
  return (
    lower.endsWith('.zip') ||
    lower.endsWith('.txt') ||
    lower.endsWith('.json') ||
    lower.endsWith('.yaml') ||
    lower.endsWith('.archipelago') ||
    lower.endsWith('.multidata') ||
    lower === 'generation.log'
  );
}

// Serve player-specific seed patch file directly to minimize download bandwidth
router.get('/:roomCode/player-patch', async (req: Request, res: Response) => {
  const roomCode = req.params.roomCode as string;
  const playerName = (req.query.playerName as string || '').trim().toLowerCase();
  const gameName = (req.query.gameName as string || '').trim().toLowerCase();
  const patchExtension = (req.query.patchExtension as string || '').trim().toLowerCase();

  const outputsDir = path.join(TEMP_SEEDS_DIR, roomCode, 'outputs');
  if (!fs.existsSync(outputsDir)) {
    return res.status(404).json({ error: `Seed output directory for room ${roomCode} not found.` });
  }

  // 1. Resolve Game Preset metadata to extract valid extensions and tokens
  const config = getLauncherConfig();
  let targetGamePreset: any = null;
  const reqGameNorm = gameName.replace(/[^a-z0-9]/g, '');
  if (config && config.games) {
    for (const key of Object.keys(config.games)) {
      const g = config.games[key];
      const normKey = key.toLowerCase().replace(/[^a-z0-9]/g, '');
      const normName = (g.game_name || '').toLowerCase().replace(/[^a-z0-9]/g, '');
      if (normKey === reqGameNorm || normName === reqGameNorm) {
        targetGamePreset = g;
        break;
      }
      if (Array.isArray(g.aliases)) {
        if (g.aliases.some((a: string) => a.toLowerCase().replace(/[^a-z0-9]/g, '') === reqGameNorm)) {
          targetGamePreset = g;
          break;
        }
      }
    }
  }

  const validExtensions: string[] = [];
  if (patchExtension) {
    validExtensions.push(patchExtension.startsWith('.') ? patchExtension : '.' + patchExtension);
  }
  if (targetGamePreset) {
    if (targetGamePreset.patch_extension) {
      const ext = String(targetGamePreset.patch_extension).toLowerCase();
      if (!validExtensions.includes(ext)) validExtensions.push(ext);
    }
    if (Array.isArray(targetGamePreset.patch_extension_aliases)) {
      for (const a of targetGamePreset.patch_extension_aliases) {
        const ext = String(a).toLowerCase();
        if (ext && !validExtensions.includes(ext)) validExtensions.push(ext);
      }
    }
  }

  const searchTokens: string[] = [];
  for (const t of gameName.split(/[^a-z0-9]+/).filter(t => t.length > 1)) {
    if (!searchTokens.includes(t)) searchTokens.push(t);
  }
  if (targetGamePreset) {
    if (targetGamePreset.short_tag) {
      const tag = String(targetGamePreset.short_tag).toLowerCase();
      if (tag && !searchTokens.includes(tag)) searchTokens.push(tag);
    }
    if (Array.isArray(targetGamePreset.aliases)) {
      for (const a of targetGamePreset.aliases) {
        const aLower = String(a).toLowerCase();
        if (!searchTokens.includes(aLower)) searchTokens.push(aLower);
        for (const t of aLower.split(/[^a-z0-9]+/).filter(t => t.length > 2)) {
          if (!searchTokens.includes(t)) searchTokens.push(t);
        }
      }
    }
  }

  const matchesGameCriteria = (filename: string): boolean => {
    const fLower = filename.toLowerCase();
    if (validExtensions.length > 0 && validExtensions.some(ext => fLower.endsWith(ext))) {
      return true;
    }
    if (searchTokens.length > 0 && searchTokens.some(token => fLower.includes(token))) {
      return true;
    }
    return false;
  };

  const files = fs.readdirSync(outputsDir);
  let patchFile = '';

  // 1. First priority: match BOTH playerName AND game criteria in outputsDir
  for (const f of files) {
    if (isIgnoredFile(f)) continue;
    const fLower = f.toLowerCase();
    const matchesPlayer = !playerName || fLower.includes(playerName);
    if (matchesPlayer && matchesGameCriteria(f)) {
      patchFile = f;
      break;
    }
  }

  // 2. Second priority: match by game criteria alone in outputsDir
  if (!patchFile) {
    for (const f of files) {
      if (isIgnoredFile(f)) continue;
      if (matchesGameCriteria(f)) {
        patchFile = f;
        break;
      }
    }
  }

  // 3. If patch files are inside a .zip file in outputsDir and not yet extracted
  if (!patchFile) {
    const zipFile = files.find(f => f.endsWith('.zip'));
    if (zipFile) {
      const zipPath = path.join(outputsDir, zipFile);
      try {
        const zip = new AdmZip(zipPath);
        const zipEntries = zip.getEntries();
        let targetEntry: any = null;

        // Try matching both player and game in zip
        for (const entry of zipEntries) {
          if (isIgnoredFile(entry.entryName)) continue;
          const entryName = entry.entryName.toLowerCase();
          const matchesPlayer = !playerName || entryName.includes(playerName);
          if (matchesPlayer && matchesGameCriteria(entryName)) {
            targetEntry = entry;
            break;
          }
        }

        // Try matching game criteria alone in zip
        if (!targetEntry) {
          for (const entry of zipEntries) {
            if (isIgnoredFile(entry.entryName)) continue;
            if (matchesGameCriteria(entry.entryName.toLowerCase())) {
              targetEntry = entry;
              break;
            }
          }
        }

        if (targetEntry) {
          const extractedPath = path.join(outputsDir, path.basename(targetEntry.entryName));
          fs.writeFileSync(extractedPath, targetEntry.getData());
          console.log(`Extracted single player patch ${targetEntry.entryName} to ${extractedPath}`);
          injectServerIntoPatchFile(extractedPath, roomCode);
          return res.download(extractedPath, path.basename(targetEntry.entryName));
        }
      } catch (e: any) {
        console.error('Zip extraction error:', e);
      }
    }
  }

  if (patchFile) {
    const fullPath = path.join(outputsDir, patchFile);
    console.log(`Serving targeted player patch file: ${patchFile} for player '${playerName}', game '${gameName}' in room ${roomCode}`);
    injectServerIntoPatchFile(fullPath, roomCode);
    return res.download(fullPath, patchFile);
  }

  res.status(404).json({ error: `Player patch file not found for player '${playerName}', game '${gameName}' in room ${roomCode}.` });
});

// Serve generated seeds statically
router.use('/', express.static(TEMP_SEEDS_DIR));

export default router;
