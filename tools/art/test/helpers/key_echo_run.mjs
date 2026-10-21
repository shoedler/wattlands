// Child-process driver for key_echo.test.mjs (W3 ART-W3-1, ART-W3-2). With KEY_ECHO_RUN=1 it runs
// generate.mjs's main() in this process in REAL mode against a fake fal: main() gets a plain env
// object with a dummy key (this process's environment never has FAL_KEY or WATTLANDS_ALLOW_ART), and
// globalThis.fetch is replaced by a fake that echoes the Authorization header back in fal's answers.
// The test starts it under no_network_preload.mjs with NO_NET_LOG set, so no socket, DNS lookup or
// real fetch can happen. Without KEY_ECHO_RUN (node --test loads every file under test/) it does
// nothing.
//   argv: <mode> <root> <key as JSON string>
//   modes: status_error (the status JSON's error echoes the header), result_echo (the result body
//          and image URL echo it), echo_401 (the status request fails with a 401 echoing it)
import { main } from '../../lib/generate.mjs';
import { encodePng } from '../../lib/png.mjs';

if (process.env.KEY_ECHO_RUN === '1') {
  const [mode, root, keyJson] = process.argv.slice(2);
  const key = JSON.parse(keyJson);
  const png = encodePng(16, 16, new Uint8Array(16 * 16 * 4).fill(255));
  const calls = [];
  globalThis.fetch = async (url, init) => {
    const u = new URL(url);
    calls.push(`${init.method} ${u.host}${u.pathname}`);
    // What actually goes on the wire: fetch trims header values.
    const auth = new Headers(init.headers).get('authorization') ?? '';
    const json = (b, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });
    if (u.hostname === 'api.fal.ai') return json({ items: [], next_cursor: null });
    if (init.method === 'POST') return json({ request_id: 'req1' });
    if (u.pathname.endsWith('/status')) {
      if (mode === 'echo_401') return new Response(`invalid credentials: ${auth}`, { status: 401 });
      if (mode === 'status_error') return json({ status: 'COMPLETED', error: `upstream rejected header Authorization: ${auth}`, error_type: 'auth_error' });
      return json({ status: 'COMPLETED' });
    }
    if (u.hostname === 'queue.fal.run') {
      return json({ images: [{ url: `https://v3.fal.media/files/x.png?echo=${encodeURIComponent(auth)}` }], debug: { echoed_headers: { authorization: auth } } });
    }
    if (u.hostname === 'v3.fal.media') return new Response(png, { status: 200 });
    return json({}, 404);
  };
  let stdout = '';
  let stderr = '';
  const code = await main(['--game=k', `--root=${root}`, '--poll-ms=1', '--timeout-s=5'], { FAL_KEY: key, WATTLANDS_ALLOW_ART: '1' }, {
    stdout: { write: (s) => (stdout += s) },
    stderr: { write: (s) => (stderr += s) },
  });
  process.stdout.write(`${JSON.stringify({ code, calls, stdout, stderr })}\n`);
}
