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

const errorMessages = {
  invalid_playback_options: {
    title: 'Playback',
    message: 'Enter a playable media URL.',
    duration: 6500,
    type: 'error'
  },
  resolver_timeout: {
    title: 'Playback',
    message: 'The media resolver timed out. Try again or choose another source.',
    duration: 7000,
    type: 'error'
  },
  resolver_unplayable: {
    title: 'Playback',
    message: 'No fallback provider returned a playable stream.',
    duration: 7000,
    type: 'error'
  },
  player_busy: {
    title: 'Playback',
    message: 'This media player is busy. Wait for the current action to finish.',
    duration: 5000,
    type: 'warning'
  },
  action_failed: {
    title: '7-PMMS',
    message: 'The action failed. Please try again.',
    duration: 6000,
    type: 'error'
  }
};

const errorPatterns = [
  { pattern: 'resolver timed out', code: 'resolver_timeout' },
  { pattern: 'timed out', code: 'playback_start_timeout' },
  { pattern: 'no fallback provider returned', code: 'resolver_unplayable' },
  { pattern: 'unable to resolve', code: 'resolver_unplayable' },
  { pattern: 'invalid playback', code: 'invalid_playback_options' },
  { pattern: 'busy', code: 'player_busy' }
];

function stripErrorStack(text) {
  const lines = String(text || '').replace(/\r/g, '\n').split('\n');
  const kept = [];
  for (const rawLine of lines) {
    const line = String(rawLine || '').trim();
    if (!line) continue;
    if (/^at\s+/.test(line) || /^stack traceback/i.test(line) || /^traceback/i.test(line)) break;
    if (/^[A-Za-z]:\\/.test(line) && line.includes(':')) break;
    kept.push(line);
    if (kept.length >= 2) break;
  }
  return (kept.join(' ') || String(text || '')).replace(/\s+/g, ' ').trim();
}

function classifyErrorCode(message, fallbackCode = 'action_failed') {
  const text = String(message || '').toLowerCase();
  const match = errorPatterns.find((entry) => text.includes(entry.pattern));
  return match ? match.code : fallbackCode;
}

function normalizeErrorPayload(input) {
  const payload = input && typeof input === 'object' ? input : { message: input };
  const rawMessage = stripErrorStack(payload.message || payload.detail || '');
  const code = payload.code || classifyErrorCode(rawMessage);
  const definition = errorMessages[code] || errorMessages.action_failed;
  const isKnownCode = code !== 'action_failed' && errorMessages[code];
  return {
    code,
    title: payload.title || definition.title,
    message: stripErrorStack(payload.friendlyMessage || (isKnownCode ? definition.message : rawMessage || definition.message)),
    type: payload.type || definition.type || 'error',
    duration: Number(payload.duration || definition.duration || 6000)
  };
}

console.log('\n[Normalizer]');
const timeoutPayload = normalizeErrorPayload('Resolver timed out.\n    at internal function');
assert('Stack traces are stripped', timeoutPayload.message.indexOf(' at ') === -1);
assert('Resolver timeout gets stable code', timeoutPayload.code === 'resolver_timeout');
assert('Resolver timeout gets friendly copy', timeoutPayload.message === errorMessages.resolver_timeout.message);

const structuredPayload = normalizeErrorPayload({ code: 'resolver_unplayable', detail: 'No fallback provider returned a playable stream. provider traceback' });
assert('Structured resolver code is preserved', structuredPayload.code === 'resolver_unplayable');
assert('Structured resolver message is friendly', structuredPayload.message === errorMessages.resolver_unplayable.message);
assert('Structured resolver duration lasts 6+ seconds', structuredPayload.duration >= 6000);

const busyPayload = normalizeErrorPayload('This player is busy');
assert('Warning class is derived from busy errors', busyPayload.type === 'warning');
assert('Unknown friendly text is preserved', normalizeErrorPayload('Playlist name is required.').message === 'Playlist name is required.');

console.log('\n[Toast queue]');
const toastQueue = [];
function addToast(entry) {
  while (toastQueue.length >= 3) toastQueue.shift();
  toastQueue.push(entry);
}
addToast('one');
addToast('two');
addToast('three');
addToast('four');
assert('Toast queue keeps max 3', toastQueue.length === 3);
assert('Toast queue removes oldest', toastQueue[0] === 'two');

console.log('\n[Source guards]');
const manifest = fs.readFileSync('fxmanifest.lua', 'utf8');
const sharedErrors = fs.readFileSync('shared/errors.lua', 'utf8');
const clientNui = fs.readFileSync('client/nui.lua', 'utf8');
const mediaLua = fs.readFileSync('server/media.lua', 'utf8');
const legacy = fs.readFileSync('nui/src/legacy/controller.js', 'utf8');

assert('Shared errors are loaded', /"shared\/errors\.lua"/.test(manifest));
assert('Shared errors define payload builder', /function BuildPmmsErrorPayload\(input, extra\)/.test(sharedErrors));
assert('Shared errors define server emitter', /function TriggerPmmsError\(target, input, extra\)/.test(sharedErrors));
assert('Client forwards structured errors to NUI', /type = "pmmsError"/.test(clientNui));
assert('Resolver failure emits structured code', /TriggerPmmsError\(src, "resolver_unplayable"/.test(mediaLua));
assert('Startup failure emits structured code', /TriggerPmmsError\(src, "playback_start_failed"/.test(mediaLua));
assert('Local playback failure emits structured code', /TriggerPmmsError\(src, "local_playback_failed"/.test(mediaLua));
assert('Invalid playback emits structured code', /TriggerPmmsError\(src, "invalid_playback_options"/.test(mediaLua));
assert('Legacy UI handles structured error event', /case 'pmmsError':/.test(legacy));
assert('Legacy UI caps toast count', /ERROR_TOAST_MAX\s*=\s*3/.test(legacy));
assert('Legacy UI strips stack traces', /function stripErrorStack\(text\)/.test(legacy));
assert('Legacy UI stores error code on toast', /data-error-code/.test(legacy));
assert('Legacy UI close button is dismissible', /aria-label="Dismiss notification"/.test(legacy));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
