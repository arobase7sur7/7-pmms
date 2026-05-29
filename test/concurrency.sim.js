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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function testRequestJoining() {
  console.log('\n[Request joining]');
  let outbound = 0;
  const inflight = new Map();

  function resolve(key) {
    if (inflight.has(key)) return inflight.get(key);
    outbound += 1;
    const request = sleep(20).then(() => ({ key })).finally(() => inflight.delete(key));
    inflight.set(key, request);
    return request;
  }

  await Promise.all(Array.from({ length: 500 }, () => resolve('same-video')));
  assert('500 matching resolves share one outbound request', outbound === 1, `outbound=${outbound}`);
}

async function testGlobalConcurrencyCap() {
  console.log('\n[Global cap]');
  let active = 0;
  let maxActive = 0;
  const queue = [];
  const cap = 8;

  async function acquire() {
    if (active < cap) {
      active += 1;
      maxActive = Math.max(maxActive, active);
      return;
    }
    await new Promise((resolve) => queue.push(resolve));
    active += 1;
    maxActive = Math.max(maxActive, active);
  }

  function release() {
    active -= 1;
    const next = queue.shift();
    if (next) next();
  }

  await Promise.all(Array.from({ length: 100 }, async () => {
    await acquire();
    await sleep(5);
    release();
  }));

  assert('Max active work stays at cap', maxActive <= cap, `maxActive=${maxActive}`);
}

function testNuiThrottle() {
  console.log('\n[NUI throttle]');
  const throttleMs = 150;
  const last = new Map();
  let sent = 0;

  function canSend(name, handle, now) {
    const key = `${name}:${handle || 'global'}`;
    const previous = last.get(key) || 0;
    if (now - previous < throttleMs) return false;
    last.set(key, now);
    return true;
  }

  for (let i = 0; i < 30; i += 1) {
    if (canSend('setVolume', 42, i * 10 + 200)) sent += 1;
  }

  assert('Slider flood is reduced', sent <= 3, `sent=${sent}`);
  assert('Separate handles do not block each other', canSend('setVolume', 43, 220) === true);
}

function testSourceGuards() {
  console.log('\n[Source guards]');
  const config = fs.readFileSync('config/config.lua', 'utf8');
  const dui = fs.readFileSync('client/dui.lua', 'utf8');
  const main = fs.readFileSync('client/main.lua', 'utf8');
  const nui = fs.readFileSync('client/nui.lua', 'utf8');
  const bridge = fs.readFileSync('nui/src/nuiBridge.ts', 'utf8');
  const legacy = fs.readFileSync('nui/src/legacy/controller.js', 'utf8');

  assert('Default DUI render FPS is 30', /renderMaxFps\s*=\s*30/.test(config));
  assert('DUI runtime caps active render FPS at 30', /getConfiguredDuiFps\("renderMaxFps",\s*30,\s*5,\s*30\)/.test(dui));
  assert('Normal DUI render path avoids immediate zero wait', /wait\s*=\s*drawEveryFrame and 0 or interval/.test(dui));
  assert('Main loop selected UI wait is relaxed', /selectedHandle ~= nil and 250 or 500/.test(main));
  assert('Client NUI callbacks are throttled', /canRunNuiCallback\("setVolume", data\)/.test(nui));
  assert('React NUI bridge throttles noisy events', /THROTTLED_NUI_MESSAGES/.test(bridge));
  assert('Legacy NUI bridge throttles noisy events', /THROTTLED_NUI_MESSAGES/.test(legacy));
}

(async () => {
  console.log('=== Concurrency Simulation ===');
  await testRequestJoining();
  await testGlobalConcurrencyCap();
  testNuiThrottle();
  testSourceGuards();
  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
})();
