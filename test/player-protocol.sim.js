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

function simulatePlayer() {
  const state = { url: null, playing: false, volume: 0.5, pendingSeek: null };
  const events = [];

  function emit(event) {
    events.push(event);
  }

  function handleCommand(command) {
    switch (command.type) {
      case 'PLAY':
        state.pendingSeek = Number.isFinite(Number(command.startAt)) ? Math.max(0, Number(command.startAt)) : null;
        state.url = command.url;
        state.volume = Number.isFinite(Number(command.volume)) ? Math.max(0, Math.min(1, Number(command.volume))) : 0.5;
        state.playing = true;
        break;
      case 'PAUSE':
        state.playing = false;
        break;
      case 'RESUME':
        state.playing = true;
        break;
      case 'STOP':
        state.url = null;
        state.playing = false;
        state.pendingSeek = null;
        break;
      case 'VOLUME':
        state.volume = Math.max(0, Math.min(1, Number(command.volume) || 0));
        break;
      case 'SEEK':
        emit({ type: 'SEEK_APPLIED', position: Math.max(0, Number(command.position) || 0) });
        break;
    }
  }

  function handleWithSourceCheck(message) {
    if (message.source !== 'pmms-nui') return false;
    handleCommand(message);
    return true;
  }

  return { state, events, handleCommand, handleWithSourceCheck };
}

console.log('\n=== Player PostMessage Protocol ===');

const { state, events, handleCommand, handleWithSourceCheck } = simulatePlayer();

handleCommand({ type: 'PLAY', url: 'https://youtube.com/watch?v=TEST', volume: 0.8, startAt: 30 });
assert('PLAY sets url', state.url === 'https://youtube.com/watch?v=TEST');
assert('PLAY sets playing', state.playing === true);
assert('PLAY sets volume', state.volume === 0.8);
assert('PLAY records startAt', state.pendingSeek === 30);

handleCommand({ type: 'PAUSE' });
assert('PAUSE stops playing', state.playing === false);

handleCommand({ type: 'RESUME' });
assert('RESUME starts playing', state.playing === true);

handleCommand({ type: 'VOLUME', volume: 0.3 });
assert('VOLUME sets volume', state.volume === 0.3);

handleCommand({ type: 'SEEK', position: 120 });
assert('SEEK emits event', events.some((event) => event.type === 'SEEK_APPLIED' && event.position === 120));

handleCommand({ type: 'STOP' });
assert('STOP clears url', state.url === null);
assert('STOP stops playing', state.playing === false);
assert('STOP clears pending seek', state.pendingSeek === null);

const wrongSourceHandled = handleWithSourceCheck({ source: 'other', type: 'PLAY', url: 'bad', volume: 1 });
assert('Wrong source ignored', wrongSourceHandled === false);
assert('Wrong source does not mutate url', state.url === null);

const rightSourceHandled = handleWithSourceCheck({ source: 'pmms-nui', type: 'PLAY', url: 'https://soundcloud.com/a/b' });
assert('pmms-nui source accepted', rightSourceHandled === true);
assert('Default volume applied', state.volume === 0.5);

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
