const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('site/public/download.js', 'utf8');
const fallback = 'https://github.com/darkarena1/timetug/releases/latest';
const valid = 'https://github.com/darkarena1/timetug/releases/download/v1.3.0/TimeTug-1.3.0.dmg';

async function resolve(assets, options = {}) {
  const download = { href: fallback };
  const context = {
    document: { querySelector: () => download },
    URL,
    fetch: async () => {
      if (options.reject) throw new Error('network');
      return { ok: !options.badStatus, status: 500, json: async () => {
        if (options.badJSON) throw new SyntaxError('bad JSON');
        return { assets };
      } };
    }
  };
  vm.runInNewContext(source, context);
  await new Promise(resolve => setImmediate(resolve));
  return download.href;
}

test('accepts a signed DMG from the expected repository', async () => {
  assert.equal(await resolve([{ name: 'TimeTug-1.3.0.dmg', browser_download_url: valid }]), valid);
});

test('skips unsigned assets and untrusted download URLs', async () => {
  const blocked = [
    'https://github.com.evil.test/darkarena1/timetug/releases/download/v1/file.dmg',
    'https://github.com/other/timetug/releases/download/v1/file.dmg',
    'javascript:alert(1)',
    'file:///tmp/file.dmg',
    'https://user:pass@github.com/darkarena1/timetug/releases/download/v1/file.dmg'
  ];
  for (const url of blocked) {
    assert.equal(await resolve([{ name: 'TimeTug-1.3.0.dmg', browser_download_url: url }]), fallback, url);
  }
  assert.equal(await resolve([{ name: 'TimeTug-1.3.0-unsigned.dmg', browser_download_url: valid }]), fallback);
});

test('keeps the release fallback when the request or JSON fails', async () => {
  for (const options of [{ reject: true }, { badStatus: true }, { badJSON: true }]) {
    assert.equal(await resolve([], options), fallback);
  }
});

test('the configured policy permits the current static page resources', () => {
  const hosting = JSON.parse(fs.readFileSync('site/firebase.json', 'utf8')).hosting;
  const policy = hosting.headers.find(entry => entry.source === '**').headers
    .find(header => header.key === 'Content-Security-Policy').value;
  for (const directive of [
    "script-src 'self'", "style-src 'self' https://fonts.googleapis.com",
    'font-src https://fonts.gstatic.com', 'connect-src https://api.github.com',
    "object-src 'none'", "frame-src 'none'"
  ]) assert.ok(policy.includes(directive), directive);
  assert.ok(!policy.includes('unsafe-eval'));
  for (const page of ['index', 'privacy', 'terms']) {
    const html = fs.readFileSync(`site/public/${page}.html`, 'utf8');
    assert.doesNotMatch(html, /\sstyle=/, `${page} has an inline style blocked by CSP`);
    assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)/, `${page} has an inline script blocked by CSP`);
  }
});
