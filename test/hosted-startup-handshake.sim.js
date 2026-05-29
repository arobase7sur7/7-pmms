import fs from 'node:fs';

let passed = 0;
let failed = 0;

function assert(name, condition, details) {
  if (condition) {
    passed += 1;
    console.log(`  PASS  ${name}`);
    return;
  }

  failed += 1;
  console.error(`  FAIL  ${name}`);
  if (details) console.error(`        ${details}`);
}

function hasExternalPlayerStartupEvidence(media) {
  if (!media || !media.externalYoutube) return false;
  if (media.pmms && media.pmms.externalYoutubeReady === true) return true;

  const externalState = media.externalYoutube.state || {};
  return externalState.paused === false
    && Number.isFinite(Number(externalState.currentTime))
    && Number(externalState.currentTime) > 0;
}

console.log('\n[Hosted startup handshake]');
assert(
  'Duration from hosted player is not startup evidence',
  !hasExternalPlayerStartupEvidence({ pmms: {}, externalYoutube: { state: { paused: true, duration: 190, currentTime: 0 } } })
);
assert(
  'Progress from hosted player is startup evidence',
  hasExternalPlayerStartupEvidence({ pmms: {}, externalYoutube: { state: { paused: false, duration: 0, currentTime: 1.2 } } })
);
assert(
  'Empty hosted player state is not startup evidence',
  !hasExternalPlayerStartupEvidence({ pmms: {}, externalYoutube: { state: { paused: true, duration: 0, currentTime: 0 } } })
);

console.log('\n[Runtime guards]');
const runtime = fs.readFileSync('http/dui_runtime/script.js', 'utf8');
assert(
  'Runtime accepts external startup evidence',
  runtime.includes('function hasExternalPlayerStartupEvidence(media)')
);
assert(
  'Runtime requires playback state for unpaused external readiness',
  runtime.includes('return externalState.paused === false')
);
assert(
  'Provider-backed startup does not use duration-only poll readiness',
  runtime.includes('!(media.pmms && media.pmms.providerBackedStartup) && readyState >= 1 && state.duration > 0')
);
assert(
  'Hosted iframe player is not used for startup',
  !runtime.includes('return initHostedPlayer')
);

console.log(`\nResults: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
