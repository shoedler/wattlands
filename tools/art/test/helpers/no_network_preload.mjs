// Preload for generate.mjs in the art-lock tests: `node --import <this> tools/art/generate.mjs ...`.
// With NO_NET_LOG set, every attempt to open a socket, resolve a name or fetch appends a line to
// that file and throws, so a test can prove the art lock refuses before any connection is made.
// Without NO_NET_LOG it does nothing (node --test also loads this file as a test module).
import dns from 'node:dns';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';

const log = process.env.NO_NET_LOG;

if (log) {
  const record = (what) => {
    fs.appendFileSync(log, `${what}\n`);
    throw new Error(`no_network_preload: ${what} blocked`);
  };
  net.connect = () => record('net.connect');
  net.createConnection = () => record('net.createConnection');
  net.Socket.prototype.connect = function connect() {
    return record('net.Socket.connect');
  };
  tls.connect = () => record('tls.connect');
  http.request = () => record('http.request');
  http.get = () => record('http.get');
  https.request = () => record('https.request');
  https.get = () => record('https.get');
  dns.lookup = () => record('dns.lookup');
  dns.promises.lookup = async () => record('dns.promises.lookup');
  globalThis.fetch = async () => record('fetch');
  if (globalThis.WebSocket) {
    globalThis.WebSocket = class {
      constructor() {
        record('WebSocket');
      }
    };
  }
}
