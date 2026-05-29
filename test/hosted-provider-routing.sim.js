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

console.log('\n[Hosted provider routing]');
const resolver = fs.readFileSync('server/resolver.lua', 'utf8');
const media = fs.readFileSync('server/media.lua', 'utf8');
const clientMedia = fs.readFileSync('client/media.lua', 'utf8');
const queue = fs.readFileSync('server/queue.lua', 'utf8');
const runtime = fs.readFileSync('http/dui_runtime/script.js', 'utf8');
const controller = fs.readFileSync('nui/src/legacy/controller.js', 'utf8');
const styles = fs.readFileSync('nui/src/styles.css', 'utf8');
const config = fs.readFileSync('config/config.lua', 'utf8');

assert('Resolver registers hosted as a provider', resolver.includes('hosted_player = resolveHosted'));
assert('Resolver registers browser YouTube provider', resolver.includes('chromium_youtube = resolveBrowserYoutube'));
assert('Resolver registers generic browser provider', resolver.includes('browser = resolveBrowserPage'));
assert('Hosted no longer short-circuits every URL', !resolver.includes('return resolverOptions.avoidProvider ~= "hosted_player"'));
assert('Hosted is not appended as hidden fallback', !resolver.includes('order[#order + 1] = "hosted_player"'));
assert('Resolver preserves configured order on score ties', resolver.includes('orderRank') && resolver.includes('math.abs(leftScore - rightScore) < 0.0001'));
assert('Auto YouTube tries hosted before browser fallbacks', config.includes('providerOrder = { "hosted_player", "chromium_youtube", "browser"'));
assert('Hosted result is tagged for DUI runtime', resolver.includes('resolved.hostedPlayer = true'));
assert('Config exposes hosted DUI URL', config.includes('urls                 = {') && config.includes('https = "https://arobase7sur7.github.io/7-pmms-dui/"'));
assert('Config keeps hosted player alias', config.includes('hostedPlayerUrl = "https://arobase7sur7.github.io/7-pmms-dui/"'));
assert('Client selects hosted DUI by resolver', clientMedia.includes('resolver.provider == "hosted_player"') && clientMedia.includes('getHostedDuiUrl() or getLocalDuiUrl()'));
assert('Client keeps direct media on local DUI', clientMedia.includes('return getLocalDuiUrl()'));
assert('DUI runtime no longer nests hosted player iframe', !runtime.includes('return initHostedPlayer'));
assert('Provider-backed startup does not trust duration only', runtime.includes('providerBackedStartup') && runtime.includes('!(media.pmms && media.pmms.providerBackedStartup) && readyState >= 1 && state.duration > 0'));
assert('Validated direct links bypass resolver', media.includes('finalIntent.directLink') && media.includes('validated_direct_link'));
assert('Hosted startup can retry non-YouTube browser pages', media.includes('retryHostedBrowserFailure') && media.includes('not isYoutubeLikeUrl(sourceUrl) and not retryHostedBrowserFailure'));
assert('Queue next does not avoid previous provider', !queue.includes('avoidProvider = mp.resolver') && !queue.includes('avoidProvider = mp and mp.resolver'));
assert('YouTube provider menu includes hosted', controller.includes("{ value: 'hosted_player', label: 'Hosted'"));
assert('YouTube provider selector defaults visible', config.includes('hideProviderSelector = false'));
assert('Search thumbnails constrain image size', styles.includes('.sr-thumb-img') && styles.includes('object-fit: cover'));
assert('Now-playing thumbnails constrain image size', styles.includes('.np-thumb-img') && styles.includes('object-fit: cover'));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
