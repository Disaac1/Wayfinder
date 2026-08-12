import express from 'express';
import http from 'http';
import adminRoutes, { localhostOnly } from '../src/adminRoutes.js';

const app = express();
app.use(express.json());
app.use('/api/admin', localhostOnly, adminRoutes);

const server = app.listen(0, '127.0.0.1', () => {
  const address = server.address() as any;
  const port = address.port;
  console.log(`Purge Test server running on port ${port}`);

  const postData = JSON.stringify({ includeCustomWorlds: false });

  const req = http.request({
    hostname: '127.0.0.1',
    port: port,
    path: '/api/admin/purge-all',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData),
      Host: `localhost:${port}`
    }
  }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      console.log(`Purge All status: ${res.statusCode}`);
      console.log(`Purge All response: ${data}`);

      if (res.statusCode !== 200) {
        console.error('❌ Purge All endpoint failed');
        process.exit(1);
      }

      console.log('✅ PURGE ALL TEST PASSED SUCCESSFULLY!');
      server.close();
    });
  });

  req.write(postData);
  req.end();
});
