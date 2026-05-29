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

function makeBridge() {
  const sent = [];
  const handlers = {};
  let fallbackUrl = null;

  const bridge = {
    send: (type, data = {}) => sent.push({ source: 'pmms-nui', type, ...data }),
    on: (type, handler) => {
      handlers[type] = handlers[type] ?? [];
      handlers[type].push(handler);
    },
    simulate: (message) => {
      if (message.source !== 'pmms-player') return;
      (handlers[message.type] ?? []).forEach((handler) => handler(message));
    },
    play: (url, volume, startAt) => bridge.send('PLAY', { url, volume, startAt }),
    pause: () => bridge.send('PAUSE'),
    resume: () => bridge.send('RESUME'),
    stop: () => bridge.send('STOP'),
    seek: (position) => bridge.send('SEEK', { position }),
    volume: (volume) => bridge.send('VOLUME', { volume }),
    triggerFallback: (url) => {
      fallbackUrl = url;
    },
    getFallbackUrl: () => fallbackUrl,
  };

  return { bridge, sent, handlers };
}

console.log('\n=== Player Bridge Protocol ===');

const { bridge, sent } = makeBridge();
let currentUrl = 'https://youtube.com/watch?v=X';

bridge.on('ERROR', ({ code }) => {
  if (code === 'EMBED_BLOCKED' || code === 'PLAYBACK_ERROR') {
    bridge.triggerFallback(currentUrl);
  }
});

bridge.play(currentUrl, 0.7, 15);
assert(
  'PLAY sent with correct fields',
  sent.at(-1)?.type === 'PLAY' && sent.at(-1)?.url === currentUrl && sent.at(-1)?.volume === 0.7 && sent.at(-1)?.startAt === 15,
);

bridge.pause();
assert('PAUSE sent', sent.at(-1)?.type === 'PAUSE');

bridge.resume();
assert('RESUME sent', sent.at(-1)?.type === 'RESUME');

bridge.seek(42);
assert('SEEK sent', sent.at(-1)?.type === 'SEEK' && sent.at(-1)?.position === 42);

bridge.volume(0.4);
assert('VOLUME sent', sent.at(-1)?.type === 'VOLUME' && sent.at(-1)?.volume === 0.4);

let errorReceived = null;
bridge.on('ERROR', (data) => {
  errorReceived = data;
});
bridge.simulate({ source: 'pmms-player', type: 'ERROR', code: 'EMBED_BLOCKED' });
assert('ERROR event routed correctly', errorReceived?.code === 'EMBED_BLOCKED');
assert('Fallback triggered on embed block', bridge.getFallbackUrl() === currentUrl);

currentUrl = 'https://soundcloud.com/a/b';
bridge.simulate({ source: 'pmms-player', type: 'ERROR', code: 'AUTOPLAY_BLOCKED' });
assert('Non-fallback error does not trigger resolver', bridge.getFallbackUrl() !== currentUrl);

let spuriousFired = false;
bridge.on('PLAYING', () => {
  spuriousFired = true;
});
bridge.simulate({ source: 'wrong-source', type: 'PLAYING' });
assert('Messages from wrong source ignored', !spuriousFired);

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
