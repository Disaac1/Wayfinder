import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { addLog } from './logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const CLIENT_REPORTS_DIR = path.join(__dirname, '..', 'logs', 'client_reports');

if (!fs.existsSync(CLIENT_REPORTS_DIR)) {
  fs.mkdirSync(CLIENT_REPORTS_DIR, { recursive: true });
}

export const clientLogRouter = Router();

// Endpoint for clients to submit crash/install error reports
clientLogRouter.post('/', (req: Request, res: Response) => {
  try {
    const { source, error, platform, recent_logs, diagnostic_summary } = req.body || {};
    const timestamp = new Date().toISOString();
    const plat = platform || 'UnknownOS';
    const errSummary = error || 'Unspecified client error';

    addLog('error', `[Client Report - ${plat}] ${errSummary}`);

    // Persist full report payload to disk
    const filename = `client_err_${Date.now()}_${plat.replace(/[^a-zA-Z0-9_-]/g, '')}.log`;
    const filePath = path.join(CLIENT_REPORTS_DIR, filename);

    const fullReport = [
      `=========================================`,
      `Client Diagnostic Report`,
      `Timestamp: ${timestamp}`,
      `Platform:  ${plat}`,
      `Source:    ${source || 'client'}`,
      `Error:     ${errSummary}`,
      `=========================================`,
      ``,
      `--- Diagnostic Summary ---`,
      diagnostic_summary || '(No diagnostic summary provided)',
      ``,
      `--- Recent Logs ---`,
      recent_logs || '(No recent logs provided)',
      `=========================================`
    ].join('\n');

    fs.writeFileSync(filePath, fullReport, 'utf8');

    // Retain only last 50 reports to avoid disk bloat
    const files = fs.readdirSync(CLIENT_REPORTS_DIR).sort();
    if (files.length > 50) {
      for (const oldFile of files.slice(0, files.length - 50)) {
        try {
          fs.unlinkSync(path.join(CLIENT_REPORTS_DIR, oldFile));
        } catch (e) {}
      }
    }

    res.json({ success: true, message: 'Diagnostic report saved successfully', filename });
  } catch (err: any) {
    console.error('[ClientLogRouter] Failed to record client log report:', err);
    res.status(500).json({ error: 'Failed to record diagnostic report: ' + err.message });
  }
});

// Admin endpoint to view recent client reports
clientLogRouter.get('/recent', (req: Request, res: Response) => {
  try {
    if (!fs.existsSync(CLIENT_REPORTS_DIR)) {
      return res.json({ reports: [] });
    }
    const files = fs.readdirSync(CLIENT_REPORTS_DIR).sort().reverse();
    const list = files.slice(0, 20).map(f => {
      const p = path.join(CLIENT_REPORTS_DIR, f);
      const stat = fs.statSync(p);
      return {
        filename: f,
        size: stat.size,
        createdAt: stat.birthtime
      };
    });
    res.json({ reports: list });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Admin endpoint to read a specific client report
clientLogRouter.get('/report/:filename', (req: Request, res: Response) => {
  try {
    const rawName = path.basename(req.params.filename as string);
    const targetPath = path.join(CLIENT_REPORTS_DIR, rawName);
    if (!fs.existsSync(targetPath)) {
      return res.status(404).json({ error: 'Report not found' });
    }
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.send(fs.readFileSync(targetPath, 'utf8'));
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

export default clientLogRouter;
