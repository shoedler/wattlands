#!/usr/bin/env node
// A stand-in mock Strava for the harness tests: counts POST /api/v3/uploads (a body starting with
// FAKEFIT is a valid FIT file) and lists them at GET /admin/uploads as a JSON array with the real
// mock's data_type, trainer, fit_valid, fit_error, error and activity_id, and prints
// "MOCK_STRAVA_PORT <port>" like server/mock_strava. --parent-pid=<pid> makes it exit when the
// harness is gone, like the real mock.
import http from 'node:http';

const arg = (k) => {
  const a = process.argv.find((x) => x.startsWith(`--${k}=`));
  return a ? a.slice(k.length + 3) : null;
};
const port = Number(arg('port') ?? 0);
const parent = Number(arg('parent-pid') ?? 0);
const uploads = [];
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => {
    body += c;
  });
  req.on('end', () => {
    if (req.method === 'POST' && req.url === '/api/v3/uploads') {
      const fitValid = body.startsWith('FAKEFIT');
      const up = { id: uploads.length + 1, activity_id: fitValid ? 1000 + uploads.length : null, size: body.length, data_type: 'fit', trainer: '1', fit_valid: fitValid, fit_error: fitValid ? null : 'not a FIT file', error: fitValid ? null : 'Improperly formatted data.' };
      uploads.push(up);
      res.writeHead(201, { 'content-type': 'application/json' });
      res.end(JSON.stringify(up));
      return;
    }
    if (req.method === 'GET' && req.url === '/admin/uploads') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(uploads));
      return;
    }
    res.writeHead(req.url === '/' ? 200 : 404, { 'content-type': 'text/plain' });
    res.end('fake mock strava');
  });
});
server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`MOCK_STRAVA_PORT ${server.address().port}\n`);
  process.stdout.write(`mock_strava listening on http://127.0.0.1:${server.address().port}\n`);
});
if (parent > 0) {
  setInterval(() => {
    try {
      process.kill(parent, 0);
    } catch {
      process.exit(0);
    }
  }, 500).unref();
}
