import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const backendRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const archipelagoPath = path.join(backendRoot, 'archipelago_core');
const envPath = path.join(backendRoot, '.env');
const envExamplePath = path.join(backendRoot, '..', '.env.example');

function run(command: string, args: string[], cwd?: string): void {
  console.log(`> ${command} ${args.join(' ')}`);
  execFileSync(command, args, { cwd, stdio: 'inherit' });
}

function findPython(): { command: string; args: string[] } {
  if (process.platform === 'win32') {
    try {
      execFileSync('py', ['-3.12', '--version'], { stdio: 'ignore' });
      return { command: 'py', args: ['-3.12'] };
    } catch {
      return { command: 'python', args: [] };
    }
  }
  return { command: 'python3', args: [] };
}

if (!fs.existsSync(path.join(archipelagoPath, 'worlds', '__init__.py'))) {
  if (!fs.existsSync(archipelagoPath)) {
    run('git', ['clone', '--depth', '1', 'https://github.com/ArchipelagoMW/Archipelago.git', archipelagoPath], backendRoot);
  } else {
    throw new Error(`Archipelago core directory exists but is incomplete: ${archipelagoPath}`);
  }
}

const python = findPython();
run(python.command, [...python.args, '-m', 'pip', 'install', '-r', path.join(archipelagoPath, 'requirements.txt')], backendRoot);

for (const directory of ['temp_seeds', 'failed_generations', 'logs', path.join('public', 'downloads'), path.join('public', 'updates')]) {
  fs.mkdirSync(path.join(backendRoot, directory), { recursive: true });
}

if (!fs.existsSync(envPath) && fs.existsSync(envExamplePath)) {
  fs.copyFileSync(envExamplePath, envPath);
  console.log(`Created ${envPath} from .env.example. Review it before enabling production services.`);
}

console.log('Wayfinder backend setup completed.');
