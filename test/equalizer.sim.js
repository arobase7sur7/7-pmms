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

function makeNode(name) {
  return {
    name,
    connections: [],
    connect(target) {
      this.connections.push(target.name);
      return target;
    },
    disconnect() {
      this.connections = [];
    }
  };
}

function rebuildChain(profile) {
  const source = makeNode('source');
  const preamp = makeNode('preamp');
  const highpass = makeNode('highpass');
  const band0 = makeNode('band0');
  const band1 = makeNode('band1');
  const compressor = makeNode('compressor');
  const analyser = makeNode('analyser');
  const destination = makeNode('destination');
  const chain = [source, preamp];

  if (profile.highpassEnabled) chain.push(highpass);
  chain.push(band0, band1);
  if (profile.compressorEnabled) chain.push(compressor);
  chain.push(analyser, destination);

  chain.reduce((previous, current) => previous.connect(current));
  return chain.map((node) => node.name).join('>');
}

function makeSourceRegistry() {
  const sources = new WeakMap();
  let creates = 0;
  return {
    init(media) {
      const existing = sources.get(media);
      if (existing) return existing;
      const source = { media, id: ++creates };
      sources.set(media, source);
      return source;
    },
    get creates() {
      return creates;
    }
  };
}

console.log('\n[Graph chain]');
assert(
  'Flat profile chains source to analyser destination',
  rebuildChain({ highpassEnabled: false, compressorEnabled: false }) === 'source>preamp>band0>band1>analyser>destination'
);
assert(
  'Highpass and compressor are inserted in order',
  rebuildChain({ highpassEnabled: true, compressorEnabled: true }) === 'source>preamp>highpass>band0>band1>compressor>analyser>destination'
);
assert(
  'Disabled profile removes optional filters',
  rebuildChain({ highpassEnabled: false, compressorEnabled: false }).includes('highpass') === false
);

console.log('\n[Media source ownership]');
const registry = makeSourceRegistry();
const mediaElement = {};
const firstSource = registry.init(mediaElement);
const secondSource = registry.init(mediaElement);
assert('Same media element reuses source', firstSource === secondSource);
assert('Source is created only once per element', registry.creates === 1, `creates=${registry.creates}`);
registry.init({});
assert('Different media element gets its own source', registry.creates === 2, `creates=${registry.creates}`);

console.log('\n[Source guards]');
const runtime = fs.readFileSync('http/dui_runtime/script.js', 'utf8');
assert('EQ graph exposes initAudioGraph', /initAudioGraph: initAudioGraph/.test(runtime));
assert('EQ source registry uses WeakMap', /new WeakMap\(\)/.test(runtime));
assert('EQ connects through reduce', /chain\.reduce\(function\(previous, current\)/.test(runtime));
assert('EQ resumes suspended AudioContext', /function resumeAudioContext\(\)/.test(runtime) && /\.resume\(\)/.test(runtime));
assert('EQ binds pointer activation', /pointerdown', resumeAudioContext/.test(runtime));
assert('Disabled EQ rebuilds neutral chain', /rebuildChain\(false, false\);\s*return;/.test(runtime));
assert('EQ initializes before radio filter', runtime.indexOf('eqGraph.initAudioGraph') < runtime.indexOf('applyRadioFilter(media)'));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
