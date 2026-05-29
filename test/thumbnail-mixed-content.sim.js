import fs from 'node:fs';

let passed = 0;
let failed = 0;

function assert(label, ok, note = '') {
  if (ok) {
    console.log(`  PASS  ${label}`);
    passed += 1;
    return;
  }
  console.error(`  FAIL  ${label}  ${note}`);
  failed += 1;
}

function normalizeRemoteAssetUrl(url) {
  if (typeof url !== 'string') return '';
  const trimmed = url.trim();
  if (!trimmed) return '';
  if (trimmed.indexOf('//') === 0) return `https:${trimmed}`;
  if (trimmed.indexOf('http://') === 0) return `https://${trimmed.slice(7)}`;
  if (trimmed.indexOf('https://') === 0) return trimmed;
  return '';
}

function encodeBase64Url(value) {
  return Buffer.from(value, 'utf8').toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function wouldCreateMixedContent(pageProtocol, url) {
  try {
    return pageProtocol === 'https:' && new URL(url, 'https://cfx-nui-7-pmms/ui/index.html').protocol === 'http:';
  } catch {
    return true;
  }
}

function getThumbnailDisplayUrl(url, options = {}) {
  const normalized = normalizeRemoteAssetUrl(url);
  if (!normalized) return '';
  if (options.proxyThumbnails === false) return normalized;

  const encoded = encodeBase64Url(normalized);
  const base = options.endpoint && options.resource ? `http://${String(options.endpoint).replace(/\/+$/g, '')}/${options.resource}` : '';
  const proxyUrl = base ? `${base}/thumb/${encoded}` : '';
  return proxyUrl && !wouldCreateMixedContent(options.pageProtocol ?? 'https:', proxyUrl) ? proxyUrl : normalized;
}

console.log('\n[Thumbnail mixed content]');

const thumbnail = 'https://i.ytimg.com/vi/demo/hqdefault.jpg';
const proxied = getThumbnailDisplayUrl(thumbnail, {
  pageProtocol: 'http:',
  endpoint: '192.168.56.1:9120',
  resource: '7-pmms',
});
assert('HTTP NUI can use resource thumbnail proxy', proxied.startsWith('http://192.168.56.1:9120/7-pmms/thumb/'), proxied);

const secure = getThumbnailDisplayUrl(thumbnail, {
  pageProtocol: 'https:',
  endpoint: '192.168.56.1:9120',
  resource: '7-pmms',
});
assert('HTTPS NUI keeps direct HTTPS thumbnail', secure === thumbnail, secure);

const disabled = getThumbnailDisplayUrl(thumbnail, {
  pageProtocol: 'https:',
  endpoint: '192.168.56.1:9120',
  resource: '7-pmms',
  proxyThumbnails: false,
});
assert('Disabled proxy keeps direct thumbnail', disabled === thumbnail, disabled);

const upgraded = getThumbnailDisplayUrl('http://i.ytimg.com/vi/demo/hqdefault.jpg', {
  pageProtocol: 'https:',
  endpoint: '192.168.56.1:9120',
  resource: '7-pmms',
});
assert('HTTP remote thumbnail is normalized to HTTPS', upgraded === thumbnail, upgraded);

console.log('\n[Source guards]');
const controller = fs.readFileSync('nui/src/legacy/controller.js', 'utf8');
assert('Controller detects mixed-content proxy URLs', /function wouldCreateMixedContent/.test(controller));
assert('Thumbnail display skips mixed-content proxy', /!wouldCreateMixedContent\(proxyUrl\) \? proxyUrl : normalized/.test(controller));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
