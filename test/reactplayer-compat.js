const patterns = {
  YouTube: [/youtube\.com\/watch/, /youtu\.be\//, /youtube\.com\/shorts\//],
  SoundCloud: [/soundcloud\.com\//],
  Twitch: [/twitch\.tv\//],
  Vimeo: [/vimeo\.com\//],
  Mixcloud: [/mixcloud\.com\//],
  DailyMotion: [/dailymotion\.com\//],
  DirectFile: [/\.(mp3|mp4|webm|ogg|m3u8|mpd)(\?|$)/i],
};

const urls = [
  'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  'https://www.youtube.com/watch?v=w8QPV9_KVbk&list=RDw8QPV9_KVbk&start_radio=1',
  'https://soundcloud.com/artist/track',
  'https://www.twitch.tv/somestreamer',
  'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
  'https://vimeo.com/123456789',
];

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

console.log('\n=== React Player URL Compatibility ===\n');

for (const url of urls) {
  const match = Object.entries(patterns).find(([, providerPatterns]) => providerPatterns.some((pattern) => pattern.test(url)));
  const provider = match?.[0] ?? null;
  assert(url, provider !== null, 'no provider matched');
  if (provider) console.log(`         handled by: ${provider}`);
}

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
