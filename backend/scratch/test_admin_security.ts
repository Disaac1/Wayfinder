import express from 'express';
import http from 'http';
import { localhostOnly } from '../src/adminRoutes.js';

const app = express();
app.use('/admin', localhostOnly, (req, res) => {
  res.json({ success: true, message: 'Access granted' });
});

const server = app.listen(0, '127.0.0.1', () => {
  const address = server.address() as any;
  const port = address.port;
  console.log(`Test server running on port ${port}`);

  // Test 1: Standard localhost request
  const req1 = http.request({
    hostname: '127.0.0.1',
    port: port,
    path: '/admin',
    method: 'GET',
    headers: {
      Host: `localhost:${port}`
    }
  }, (res1) => {
    console.log(`Valid localhost request status: ${res1.statusCode}`);
    if (res1.statusCode !== 200) {
      console.error('❌ Failed valid localhost check');
      process.exit(1);
    }

    // Test 2: Invalid host header
    const req2 = http.request({
      hostname: '127.0.0.1',
      port: port,
      path: '/admin',
      method: 'GET',
      headers: {
        Host: 'external-domain.com'
      }
    }, (res2) => {
      console.log(`External Host header request status: ${res2.statusCode}`);
      if (res2.statusCode !== 403) {
        console.error('❌ Failed external host header restriction check');
        process.exit(1);
      }

      console.log('✅ ALL LOCALHOST SECURITY CHECKS PASSED SUCCESSFULLY!');
      server.close();
    });

    req2.end();
  });

  req1.end();
});
