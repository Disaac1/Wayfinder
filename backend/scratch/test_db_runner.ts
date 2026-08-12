import test from 'node:test';
import assert from 'node:assert';
import Database from 'better-sqlite3';

test('sqlite in-memory test in project scratch', () => {
  const db = new Database(':memory:');
  db.exec('CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT)');
  const stmt = db.prepare('INSERT INTO test (val) VALUES (?)');
  const info = stmt.run('hello');
  assert.strictEqual(info.changes, 1);
  
  const row = db.prepare('SELECT val FROM test WHERE id = 1').get() as { val: string };
  assert.strictEqual(row.val, 'hello');
});
