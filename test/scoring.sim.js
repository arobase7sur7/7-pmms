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

function makeStats() {
  return Array.from({ length: 24 }, () => ({ successes: 0, failures: 0, fakeSuccesses: 0, totalMs: 0 }));
}

function score(stats, hour) {
  const weights = [[hour, 3], [(hour + 23) % 24, 2], [(hour + 1) % 24, 2], [(hour + 22) % 24, 1], [(hour + 2) % 24, 1]];
  let samples = 0;
  let successWeight = 0;
  let latencyWeight = 0;

  for (const [targetHour, weight] of weights) {
    const slot = stats[targetHour];
    const failures = slot.failures + slot.fakeSuccesses;
    const total = slot.successes + failures;
    if (!total) continue;
    samples += weight;
    successWeight += (slot.successes / total) * weight;
    latencyWeight += (slot.successes > 0 ? slot.totalMs / slot.successes : 15000) * weight;
  }

  if (!samples) return 0.5;
  return (successWeight / samples) * 0.7 + Math.max(0, 1 - (latencyWeight / samples) / 12000) * 0.3;
}

console.log('\n[Scoring basics]');
const good = makeStats();
good[12].successes = 100;
good[12].totalMs = 300000;
const bad = makeStats();
bad[12].failures = 100;
assert('Reliable provider scores higher', score(good, 12) > score(bad, 12), `good=${score(good, 12).toFixed(3)} bad=${score(bad, 12).toFixed(3)}`);
assert('Unknown provider -> 0.5', score(makeStats(), 12) === 0.5);

console.log('\n[Time awareness]');
const timeAware = makeStats();
timeAware[14].successes = 50;
timeAware[14].totalMs = 100000;
timeAware[3].failures = 50;
assert('Higher score at peak hour than bad hour', score(timeAware, 14) > score(timeAware, 3), `peak=${score(timeAware, 14).toFixed(3)} bad=${score(timeAware, 3).toFixed(3)}`);

console.log('\n[Fake-success penalty]');
const fake = makeStats();
fake[8].successes = 10;
fake[8].fakeSuccesses = 20;
fake[8].totalMs = 20000;
const clean = makeStats();
clean[8].successes = 10;
clean[8].totalMs = 20000;
assert('Fake successes lower score', score(clean, 8) > score(fake, 8), `clean=${score(clean, 8).toFixed(3)} fake=${score(fake, 8).toFixed(3)}`);

console.log('\n[Circuit breaker]');
const circuit = {};

function isOpen(provider) {
  return circuit[provider]?.until ? Date.now() < circuit[provider].until : false;
}

function record(provider, ok) {
  if (!circuit[provider]) circuit[provider] = { streak: 0, until: null };
  if (ok) {
    circuit[provider].streak = 0;
    circuit[provider].until = null;
    return;
  }
  circuit[provider].streak += 1;
  if (circuit[provider].streak >= 3) circuit[provider].until = Date.now() + 300000;
}

record('p', false);
record('p', false);
assert('Not open at 2 failures', !isOpen('p'));
record('p', false);
assert('Opens at 3 failures', isOpen('p'));
record('p', true);
assert('Resets after success', !isOpen('p'));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
