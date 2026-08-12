import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { getGameOptions } from '../src/archipelagoRunner.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function test() {
  const options = await getGameOptions('Hollow Knight');
  console.log(JSON.stringify(options.options.find(o => o.name === 'start_inventory'), null, 2));
}

test();
