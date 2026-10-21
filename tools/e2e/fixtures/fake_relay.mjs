#!/usr/bin/env node
// A stand-in relay for the harness tests: answers GET /health on $PORT.
import http from 'node:http';

const port = Number(process.env.PORT);
const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }
  res.writeHead(404);
  res.end();
});
server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`fake relay listening on ${port}\n`);
  if (process.env.FAKE_RELAY_FAULT === 'rate') process.stdout.write('peer 3: rate_limited\n');
});
