import { getGameOptions } from '../src/archipelagoRunner.ts';
import fs from 'fs';
import { execSync } from 'child_process';
import path from 'path';

async function run() {
  const schema = await getGameOptions('A Link to the Past');
  let yaml = 'name: TestPlayer\ngame: A Link to the Past\nA Link to the Past:\n';
  for (const opt of schema.options) {
    const val = opt.default;
    if (typeof val === 'boolean') {
      yaml += `  ${opt.name}: ${val ? 'true' : 'false'}\n`;
    } else if (Array.isArray(val)) {
      if (val.length === 0) {
        yaml += `  ${opt.name}: []\n`;
      } else {
        yaml += `  ${opt.name}:\n`;
        for (const item of val) {
          yaml += `    - ${item}\n`;
        }
      }
    } else if (typeof val === 'object' && val !== null) {
      if (Object.keys(val).length === 0) {
        yaml += `  ${opt.name}: {}\n`;
      } else {
        yaml += `  ${opt.name}:\n`;
        for (const k of Object.keys(val)) {
          yaml += `    ${k}: ${val[k]}\n`;
        }
      }
    } else if (typeof val === 'number') {
      if (val === Math.floor(val)) {
        yaml += `  ${opt.name}: ${Math.floor(val)}\n`;
      } else {
        yaml += `  ${opt.name}: ${val}\n`;
      }
    } else {
      if (val === '') {
        yaml += `  ${opt.name}: ""\n`;
      } else {
        yaml += `  ${opt.name}: ${val}\n`;
      }
    }
  }
  fs.mkdirSync('scratch/test_alttp/inputs', { recursive: true });
  fs.writeFileSync('scratch/test_alttp/inputs/TestPlayer.yaml', yaml);
  try {
    const out = execSync('python archipelago_core/Generate.py --player_files_path scratch/test_alttp/inputs --outputpath scratch/test_alttp/outputs', {
      env: { ...process.env, SKIP_REQUIREMENTS_UPDATE: '1' }
    });
    console.log(out.toString());
  } catch (e: any) {
    console.log('STDOUT:', e.stdout?.toString());
    console.log('STDERR:', e.stderr?.toString());
  }
}

run();
