import fs from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { getAvailableGames, getGameOptions } from '../src/archipelagoRunner.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BACKEND_ROOT = path.join(__dirname, '..');
const ARCHIPELAGO_PATH = path.join(BACKEND_ROOT, 'archipelago_core');
const TEST_DIR = path.join(BACKEND_ROOT, 'scratch', 'test_run');
const INPUTS_DIR = path.join(TEST_DIR, 'inputs');
const OUTPUTS_DIR = path.join(TEST_DIR, 'outputs');

function formatYamlValue(val: any, indent: number): string {
  const spaces = " ".repeat(indent);
  if (val === null || val === undefined) {
    return "null";
  }
  if (typeof val === 'boolean') {
    return val ? 'true' : 'false';
  }
  if (typeof val === 'number') {
    return val.toString();
  }
  if (typeof val === 'string') {
    if (val === '') {
      return '""';
    }
    return val;
  }
  if (Array.isArray(val)) {
    if (val.length === 0) {
      return "[]";
    }
    let res = "";
    for (const item of val) {
      res += `\n${spaces}- ${formatYamlValue(item, indent + 2)}`;
    }
    return res;
  }
  if (typeof val === 'object') {
    const keys = Object.keys(val);
    if (keys.length === 0) {
      return "{}";
    }
    let res = "";
    for (const k of keys) {
      res += `\n${spaces}${k}: ${formatYamlValue(val[k], indent + 2)}`;
    }
    return res;
  }
  return val.toString();
}

function compileYaml(gameName: string, name: string, optionsSchema: any): string {
  let yaml = `description: Test compiled options for ${gameName}\n`;
  yaml += `name: ${name}\n`;
  yaml += `game: ${gameName}\n`;
  yaml += `${gameName}:\n`;
  
  const options = optionsSchema.options || [];
  if (options.length === 0) {
    yaml += "  {}\n";
    return yaml;
  }
  
  for (const opt of options) {
    const optName = opt.name;
    const val = opt.default;
    yaml += `  ${optName}: ${formatYamlValue(val, 4)}\n`;
  }
  return yaml;
}

function runGenerate(gameName: string): Promise<{ success: boolean; error?: string }> {
  return new Promise((resolve) => {
    const pythonExe = 'python';
    const generateScript = path.join(ARCHIPELAGO_PATH, 'Generate.py');
    const args = [
      generateScript,
      '--player_files_path',
      INPUTS_DIR,
      '--outputpath',
      OUTPUTS_DIR
    ];
    
    const child = spawn(pythonExe, args, {
      cwd: ARCHIPELAGO_PATH,
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    });
    
    child.stdin.end();
    
    let stdout = '';
    let stderr = '';
    
    child.stdout.on('data', (d) => stdout += d.toString());
    child.stderr.on('data', (d) => stderr += d.toString());
    
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ success: true });
      } else {
        const fullLog = stdout + '\n' + stderr;
        let cleanErr = '';
        const lines = fullLog.split('\n');
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i].trim();
          if (line.includes('EOFError') || line.includes('Press enter to close')) continue;
          if (line.includes('Exception:') || line.includes('ValueError:') || line.includes('Error:')) {
            cleanErr = line;
            break;
          }
        }
        if (!cleanErr) {
          for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            if (line && !line.includes('Press enter to close')) {
              cleanErr = line;
              break;
            }
          }
        }
        resolve({ success: false, error: cleanErr || `Exit code ${code}` });
      }
    });
  });
}

async function startTests() {
  console.log('Fetching available games list...');
  const games = await getAvailableGames();
  console.log(`Found ${games.length} games to test.\n`);
  
  const results: Array<{ game: string; success: boolean; error?: string }> = [];
  
  for (let i = 0; i < games.length; i++) {
    const game = games[i];
    console.log(`[${i + 1}/${games.length}] Testing: ${game}...`);
    
    // 1. Clean directories with retry to handle Windows EBUSY locks
    let cleaned = false;
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        if (fs.existsSync(TEST_DIR)) {
          fs.rmSync(TEST_DIR, { recursive: true, force: true });
        }
        cleaned = true;
        break;
      } catch (e) {
        // Sleep 100ms
        const start = Date.now();
        while (Date.now() - start < 100) {}
      }
    }
    if (!cleaned) {
      console.warn(`Warning: Could not clean TEST_DIR due to busy locks.`);
    }
    fs.mkdirSync(INPUTS_DIR, { recursive: true });
    fs.mkdirSync(OUTPUTS_DIR, { recursive: true });
    
    // 2. Fetch schema
    const schema = await getGameOptions(game);
    
    // 3. Compile YAML
    const yaml = compileYaml(game, 'TestPlayer', schema);
    fs.writeFileSync(path.join(INPUTS_DIR, 'TestPlayer.yaml'), yaml, 'utf8');
    
    // 4. Run roll
    const res = await runGenerate(game);
    if (res.success) {
      console.log(`  => PASS`);
      results.push({ game, success: true });
    } else {
      console.error(`  => FAIL: ${res.error}`);
      results.push({ game, success: false, error: res.error });
    }
  }
  
  console.log('\n======================================');
  console.log('             TEST RESULTS             ');
  console.log('======================================');
  const fails = results.filter(r => !r.success);
  console.log(`Passed: ${results.length - fails.length}/${results.length}`);
  console.log(`Failed: ${fails.length}/${results.length}`);
  
  if (fails.length > 0) {
    console.log('\nFailed Games Summary:');
    for (const f of fails) {
      console.log(`- ${f.game}: ${f.error}`);
    }
  }
  console.log('======================================');
}

startTests();
