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

function isPlaybackEndCredible(metadata, state) {
  const durationSource = metadata && metadata.duration !== undefined && metadata.duration !== null
    ? metadata.duration
    : state && state.duration;
  const duration = Number(durationSource);
  if (Number.isNaN(duration)) return true;
  if (!Number.isFinite(duration) || duration <= 0) return false;

  const currentTime = Number(metadata && metadata.currentTime !== undefined ? metadata.currentTime : state && state.currentTime);
  if (!Number.isFinite(currentTime)) return false;

  return (duration - currentTime) < 3;
}

function makeCooldown() {
  const events = new Map();
  return function canTriggerEvent(src, eventName, handle, now, cooldownMs = 500) {
    const key = `${src || 'server'}:${eventName || 'event'}:${handle || 'global'}`;
    const previous = events.get(key);
    if (previous !== undefined && now - previous < cooldownMs) return false;
    events.set(key, now);
    return true;
  };
}

console.log('\n[False ended guard]');
assert('Near-duration end is accepted', isPlaybackEndCredible({ currentTime: 118 }, { duration: 120 }) === true);
assert('Early ended event is rejected', isPlaybackEndCredible({ currentTime: 32 }, { duration: 120 }) === false);
assert('Unknown duration is accepted', isPlaybackEndCredible({ currentTime: 12 }, {}) === true);
assert('Infinite duration is rejected', isPlaybackEndCredible({ currentTime: 12 }, { duration: Infinity }) === false);
assert('Missing current time is rejected for known duration', isPlaybackEndCredible({}, { duration: 120 }) === false);

console.log('\n[Server event cooldown]');
const canTriggerEvent = makeCooldown();
assert('First event passes', canTriggerEvent(1, 'pmms:setVolume', 22, 1000) === true);
assert('Duplicate inside cooldown is blocked', canTriggerEvent(1, 'pmms:setVolume', 22, 1200) === false);
assert('Same event after cooldown passes', canTriggerEvent(1, 'pmms:setVolume', 22, 1510) === true);
assert('Different handle is independent', canTriggerEvent(1, 'pmms:setVolume', 23, 1210) === true);
assert('Different source is independent', canTriggerEvent(2, 'pmms:setVolume', 22, 1220) === true);

console.log('\n[Source guards]');
const mainLua = fs.readFileSync('server/main.lua', 'utf8');
const mediaLua = fs.readFileSync('server/media.lua', 'utf8');
const duiRuntime = fs.readFileSync('http/dui_runtime/script.js', 'utf8');

assert('Sync throttle is 1000ms', /SYNC_THROTTLE_MS\s*=\s*1000/.test(mainLua));
assert('Server has canTriggerEvent wrapper', /local function canTriggerEvent\(src, eventName, handle, cooldownMs\)/.test(mediaLua));
assert('Playback metadata is cooldown protected', /canTriggerEvent\(src, "pmms:updatePlaybackMetadata", handle\)/.test(mediaLua));
assert('Ended events are cooldown protected', /canTriggerEvent\(src, "pmms:ended", handle\)/.test(mediaLua));
assert('Server ended guard uses 3 second window', /duration - 3/.test(mediaLua));
assert('DUI has false-ended helper', /function isPlaybackEndCredible\(metadata, state\)/.test(duiRuntime));
assert('DUI checks ended before setting endedSent', duiRuntime.indexOf('if (!isPlaybackEndCredible(metadata, state))') < duiRuntime.indexOf('media.pmms.endedSent = true;'));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
