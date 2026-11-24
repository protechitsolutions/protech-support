// Builds + signs a ProTech custom.txt (the file the client reads next to its exe to get its name, server, key and lockdown).
//
//   node sign-custom.mjs --variant variants/customer.json --server config/server.json 
//        --secret <path to the private signing key: NOT in this repository> 
//        --source <path to the assembled source tree> --out custom.txt
//
// Format (verified against read_custom_client() in src/common.rs): base64( ed25519_signature(64) || json ), standard alphabet.
// Uses Node's built-in Ed25519 only, so no third-party code ever touches the signing secret.
import { readFileSync, writeFileSync } from 'node:fs';
import { createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? [...a, [v.slice(2), all[i + 1]]] : a), []));
for (const k of ['variant', 'server', 'secret', 'source', 'out']) if (!args[k]) { console.error(`missing --${k}`); process.exit(2); }

const fail = (m) => { console.error('ERROR: ' + m); process.exit(1); };
// Notepad / PowerShell's Set-Content add a UTF-8 BOM, which JSON.parse rejects
const readText = (p) => readFileSync(p, 'utf8').replace(/^﻿/, '');

// ---- signing key: 64 bytes = seed(32) || public(32), exactly as rustdesk-utils genkeypair prints it
const secret = Buffer.from(readText(args.secret).trim(), 'base64');
if (secret.length !== 64) fail('signing secret must decode to 64 bytes');
const seed = secret.subarray(0, 32), pk = secret.subarray(32);
const priv = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]), format: 'der', type: 'pkcs8' });
const pub = createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), pk]), format: 'der', type: 'spki' });
// the seed must really produce that public key (guards against a corrupted/mixed-up secret file)
const derived = createPublicKey(priv).export({ format: 'der', type: 'spki' }).subarray(-32);
if (!derived.equals(pk)) fail('secret key is inconsistent (seed does not produce the stored public key)');

// ---- the public key compiled into THIS source tree must be the one we sign for, or the client will reject the file
const common = readFileSync(`${args.source}\\src\\common.rs`, 'utf8');
const m = common.match(/fn read_custom_client[\s\S]*?const KEY: &str = "([^"]+)";/);
if (!m) fail('could not find the custom.txt verification KEY in src/common.rs');
if (m[1] !== pk.toString('base64')) fail(`signing key ${pk.toString('base64')} != key compiled into the client ${m[1]} - the client would reject this file`);

// ---- variant + server identity
const server = JSON.parse(readText(args.server));
for (const k of ['host', 'relay', 'key']) if (!server[k]) fail(`server.json is missing "${k}"`);
// {{SITE}} and {{API}} are optional: while server.json leaves them empty, the settings that need them are dropped
// ("site": the client uses its compiled About-page fallback; "api": the client reports nothing to anyone).
const site = String(server.site || '').replace(/\/+$/, '');
// "api" = base URL of the ProTech presence service. With it set the customer client tells that service its ID, PC name,
// Windows username and OS every ~15 s, so staff can see who is running it. It must be https:// unless --allow-http is given
// (test builds on a LAN): over plain http a network attacker could read the PC name and answer with settings changes.
const api = String(server.api || '').replace(/\/+$/, '');
if (api && !/^https?:\/\/[A-Za-z0-9.\-]+(:\d{1,5})?$/.test(api)) fail(`server.json "api" must look like https://host (no path), got "${api}"`);
if (api.startsWith('http://') && args['allow-http'] !== 'yes') fail('server.json "api" is plain http://: refusing (pass --allow-http yes only for a throw-away test build)');
const optional = { '{{SITE}}': site, '{{API}}': api };
const subst = (s) => s.replaceAll('{{HOST}}', server.host).replaceAll('{{RELAY}}', server.relay).replaceAll('{{KEY}}', server.key)
  .replaceAll('{{SITE}}', site).replaceAll('{{API}}', api).replaceAll('{{REGISTER}}', api ? 'Y' : 'N');
const walk = (o) => { for (const [k, v] of Object.entries(o)) {
  if (typeof v === 'string') { if (Object.entries(optional).some(([p, val]) => v.includes(p) && !val)) { delete o[k]; continue; } o[k] = subst(v); }
  else if (v && typeof v === 'object') walk(v);
} };
const cfg = JSON.parse(readText(args.variant)); walk(cfg);
if (/\{\{[A-Z]+\}\}/.test(JSON.stringify(cfg))) fail('unreplaced {{placeholder}} left in variant');

// ---- typo guard: every option name must be one the client knows (an unknown name is silently ignored at runtime)
const known = new Set(['app-name', 'default-settings', 'override-settings', 'conn-type', 'disable-ab', 'disable-account', 'disable-installation', 'disable-settings', 'disable-tcp-listen', 'protech-website-url', 'protech-source-url']);
const strings = (s) => [...s.matchAll(/=\s*\n?\s*"([a-zA-Z0-9_-]+)";/g)].map((x) => x[1]);
for (const f of [`${args.source}\\libs\\base\\src\\config\\keys.rs`, `${args.source}\\libs\\hbb_common\\src\\config.rs`]) strings(readFileSync(f, 'utf8')).forEach((s) => known.add(s));
const bad = [];
for (const [k, v] of Object.entries(cfg)) {
  if (typeof v === 'object') { for (const k2 of Object.keys(v)) if (!known.has(k2)) bad.push(`${k}.${k2}`); }
  else if (!known.has(k)) bad.push(k);
  if (typeof v !== 'object' && typeof v !== 'string') bad.push(`${k} (value must be a string or object)`);
}
if (bad.length) fail('unknown option name(s): ' + bad.join(', '));

// ---- sign + self-verify
const msg = Buffer.from(JSON.stringify(cfg));
const sig = sign(null, msg, priv);
if (!verify(null, msg, pub, sig)) fail('self-verification failed');
writeFileSync(args.out, Buffer.concat([sig, msg]).toString('base64'));
console.log(`wrote ${args.out}: ${msg.length} bytes of config, signed for key ${pk.toString('base64')} (matches the compiled-in key)`);
console.log(`  app-name=${cfg['app-name']}  host=${server.host}  settings=${Object.keys(cfg['override-settings'] || {}).length}`);
console.log(`  reports to ProTech presence service: ${cfg['override-settings']?.['register-device'] === 'Y' ? cfg['override-settings']['api-server'] : 'NO (register-device N)'}`);
