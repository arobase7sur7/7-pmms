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

async function testDedup() {
  console.log('\n[Deduplication]');
  let calls = 0;
  const inflight = new Map();

  function resolve(url) {
    if (inflight.has(url)) return inflight.get(url);
    calls += 1;
    const promise = sleep(50).then(() => ({ url: 'cdn://audio' })).finally(() => inflight.delete(url));
    inflight.set(url, promise);
    return promise;
  }

  await Promise.all(Array.from({ length: 50 }, () => resolve('https://yt/v=X')));
  assert('50 requests -> 1 outbound call', calls === 1, `calls=${calls}`);
}

async function testCache() {
  console.log('\n[TTL Cache]');
  const cache = new Map();
  const ttl = 100;

  function get(url) {
    const entry = cache.get(url);
    return entry && Date.now() < entry.expiresAt ? entry.payload : null;
  }

  function set(url, payload) {
    cache.set(url, { payload, expiresAt: Date.now() + ttl });
  }

  set('url1', { url: 'cdn://1' });
  assert('Cache hit', get('url1') !== null);
  await sleep(150);
  assert('Cache expires', get('url1') === null);
}

async function testSemaphore() {
  console.log('\n[Concurrency Cap]');
  let max = 0;
  let current = 0;

  class Semaphore {
    constructor(limit) {
      this.limit = limit;
      this.active = 0;
      this.queue = [];
    }

    acquire() {
      if (this.active < this.limit) {
        this.active += 1;
        return Promise.resolve();
      }
      return new Promise((resolve) => this.queue.push(resolve)).then(() => {
        this.active += 1;
      });
    }

    release() {
      this.active = Math.max(0, this.active - 1);
      this.queue.shift()?.();
    }
  }

  const semaphore = new Semaphore(5);

  async function task() {
    await semaphore.acquire();
    current += 1;
    max = Math.max(max, current);
    await sleep(10);
    current -= 1;
    semaphore.release();
  }

  await Promise.all(Array.from({ length: 30 }, () => task()));
  assert('Max concurrent <= cap', max <= 5, `max=${max}`);
}

async function testRace() {
  console.log('\n[First valid provider wins]');
  const provider = (name) => async (ok, ms) => {
    await sleep(ms);
    if (!ok) throw new Error(name);
    return { url: `cdn://${name}`, provider: name };
  };
  const winner = await Promise.any([
    provider('slow_ok')(true, 200),
    provider('fast_fail')(false, 30),
    provider('fast_ok')(true, 80),
  ]);
  assert('Fastest successful provider wins', winner.provider === 'fast_ok', `got=${winner.provider}`);
}

async function testFakeSuccess() {
  console.log('\n[Fake-success rejection]');

  async function validate(url) {
    if (url.includes('fake')) throw new Error('probe 403');
    return { url };
  }

  let threw = false;
  try {
    await validate('https://cdn.fake/stream');
  } catch {
    threw = true;
  }
  assert('Fake URL rejected', threw);

  let ok = true;
  try {
    await validate('https://cdn.real/audio.mp3');
  } catch {
    ok = false;
  }
  assert('Real URL accepted', ok);
}

(async () => {
  console.log('=== Resolver Simulation ===');
  await testDedup();
  await testCache();
  await testSemaphore();
  await testRace();
  await testFakeSuccess();
  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
})();
