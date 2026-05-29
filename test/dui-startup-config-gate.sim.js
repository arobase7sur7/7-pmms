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

function createGate() {
  let loaded = false;
  let callbacks = [];
  const calls = [];

  function whenStartupConfigLoaded(callback) {
    if (loaded) {
      callback();
      return;
    }
    callbacks.push(callback);
  }

  function finishStartupConfigLoad() {
    if (loaded) return;
    loaded = true;
    const pending = callbacks.slice();
    callbacks = [];
    pending.forEach(callback => callback());
  }

  return { calls, whenStartupConfigLoaded, finishStartupConfigLoad };
}

console.log('\n[DUI startup config gate]');
const gate = createGate();
gate.whenStartupConfigLoaded(() => gate.calls.push('init'));
gate.whenStartupConfigLoaded(() => gate.calls.push('startup'));
assert('Callbacks wait before config load', gate.calls.length === 0, JSON.stringify(gate.calls));
gate.finishStartupConfigLoad();
assert('Queued callbacks flush after config load', gate.calls.join(',') === 'init,startup', JSON.stringify(gate.calls));
gate.whenStartupConfigLoaded(() => gate.calls.push('update'));
assert('Callbacks run immediately after config load', gate.calls.join(',') === 'init,startup,update', JSON.stringify(gate.calls));
gate.finishStartupConfigLoad();
assert('Config load completes only once', gate.calls.join(',') === 'init,startup,update', JSON.stringify(gate.calls));

console.log('\n[Runtime guards]');
const runtime = fs.readFileSync('http/dui_runtime/script.js', 'utf8');
assert('Runtime tracks startup config load', runtime.includes('var startupConfigLoaded = false;'));
assert('Runtime queues startup until config load', runtime.includes("case 'startup':\n            whenStartupConfigLoaded(function()"));
assert('Runtime queues initDone until config load', runtime.includes("case 'DuiBrowser:init':\n            whenStartupConfigLoaded(function()"));
assert('Runtime releases gate after config success', runtime.includes('finishStartupConfigLoad();\n        })\n        .catch'));
assert('Runtime releases gate after config failure', runtime.includes('finishStartupConfigLoad();\n        });\n});'));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
