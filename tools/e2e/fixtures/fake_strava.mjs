#!/usr/bin/env node
// A stand-in mock Strava for the harness tests: counts POST /api/v3/uploads and lists them at
// GET /__admin/uploads. Prints its URL like the real mock.
import http from 'node:http';

const arg = process.argv.find((a) => a.startsWith('--port='));
const port = arg ? Number(arg.slice('--port='.length)) : 0;
const uploads = [];
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => {
    body += c;
  });
  req.on('end', () => {
    if (req.method === 'POST' && req.url === '/api/v3/uploads') {
      const up = { id: uploads.length + 1, activity_id: 1000 + uploads.length, size: body.length };
      uploads.push(up);
      res.writeHead(201, { 'content-type': 'application/json' });
      res.end(JSON.stringify(up));
      return;
    }
    if (req.method === 'GET' && req.url === '/__admin/uploads') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ uploads }));
      return;
    }
    res.writeHead(req.url === '/' ? 200 : 404, { 'content-type': 'text/plain' });
    res.end('fake mock strava');
  });
});
server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`mock strava listening on http://127.0.0.1:${server.address().port}\n`);
});
