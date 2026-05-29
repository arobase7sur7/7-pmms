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

function normalizePlaylistNameKey(name) {
  return String(name || '').trim().toLowerCase();
}

function makePlaylistUi() {
  const pending = {};
  let requestSeq = 0;
  let playlists = [];
  let refreshes = 0;
  let notification = null;

  function clearPendingPlaylistCreateByName(name) {
    delete pending[normalizePlaylistNameKey(name)];
  }

  function addPendingPlaylistCreate(name) {
    const key = normalizePlaylistNameKey(name);
    if (!key || pending[key]) return null;
    requestSeq += 1;
    pending[key] = {
      id: `pending-playlist-${requestSeq}`,
      requestId: requestSeq,
      name: String(name || '').trim(),
      pendingCreate: true
    };
    return pending[key];
  }

  function applyServerPlaylists(nextPlaylists) {
    playlists = nextPlaylists.slice();
    playlists.forEach((playlist) => clearPendingPlaylistCreateByName(playlist.name));
  }

  function requestPlaylists() {
    refreshes += 1;
  }

  function handlePlaylistCreateResult(payload) {
    payload = payload && typeof payload === 'object' ? payload : {};
    if (payload.name) clearPendingPlaylistCreateByName(payload.name);

    if (payload.success === true) {
      if (Array.isArray(payload.playlists)) applyServerPlaylists(payload.playlists);
      else requestPlaylists();
      if (payload.message) notification = payload.message;
      return;
    }

    notification = payload.message || 'Playlist could not be created.';
    requestPlaylists();
  }

  return {
    addPendingPlaylistCreate,
    handlePlaylistCreateResult,
    pending,
    get playlists() {
      return playlists;
    },
    get refreshes() {
      return refreshes;
    },
    get notification() {
      return notification;
    }
  };
}

function makeServerCreate(existingCount, maxCount) {
  let revision = 0;
  return function createPlaylist(name, requestId) {
    if (typeof name !== 'string') {
      return { success: false, requestId, message: 'Playlist name is required.' };
    }
    const trimmed = name.trim();
    if (!trimmed) {
      return { success: false, requestId, name: trimmed, message: 'Playlist name is required.' };
    }
    if (trimmed.length > 50) {
      return { success: false, requestId, name: trimmed, message: 'Playlist name too long (max 50 characters).' };
    }
    if (existingCount >= maxCount) {
      return { success: false, requestId, name: trimmed, message: `You have reached the maximum of ${maxCount} playlists.` };
    }
    existingCount += 1;
    revision += 1;
    return {
      success: true,
      requestId,
      playlistId: 101,
      name: trimmed,
      message: `Playlist '${trimmed}' created!`,
      libraryRevision: revision,
      playlists: [{ id: 101, name: trimmed, is_favorite: 0 }],
      summary: { playlistCount: existingCount, favoriteCount: 0, maxPlaylists: maxCount, maxFavorites: 5 }
    };
  };
}

console.log('\n[Create flow]');
const ui = makePlaylistUi();
const serverCreate = makeServerCreate(0, 20);
const pending = ui.addPendingPlaylistCreate('Road Trip');
assert('Pending create gets request id', pending && pending.requestId === 1);
const result = serverCreate('Road Trip', pending.requestId);
ui.handlePlaylistCreateResult(result);
assert('Successful ack clears pending row', Object.keys(ui.pending).length === 0);
assert('Successful ack applies canonical snapshot', ui.playlists.length === 1 && ui.playlists[0].name === 'Road Trip');
assert('Successful ack preserves request id', result.requestId === pending.requestId);

console.log('\n[Failure flow]');
const fullUi = makePlaylistUi();
const fullPending = fullUi.addPendingPlaylistCreate('Overflow');
const fullResult = makeServerCreate(20, 20)('Overflow', fullPending.requestId);
fullUi.handlePlaylistCreateResult(fullResult);
assert('Failure ack clears pending row', Object.keys(fullUi.pending).length === 0);
assert('Failure ack requests canonical refresh', fullUi.refreshes === 1, `refreshes=${fullUi.refreshes}`);
assert('Failure ack exposes message', /maximum/.test(fullUi.notification));

console.log('\n[Source guards]');
const legacy = fs.readFileSync('nui/src/legacy/controller.js', 'utf8');
const client = fs.readFileSync('client/nui.lua', 'utf8');
const server = fs.readFileSync('server/playlists.lua', 'utf8');

assert('Legacy create sends requestId', /sendMessage\('createPlaylist', \{ name: trimmed, requestId: pending\.requestId \}\)/.test(legacy));
assert('Legacy handles playlistCreateResult', /case 'playlistCreateResult':/.test(legacy));
assert('Client forwards create requestId', /pmms:createPlaylist", data\.name, data\.requestId/.test(client));
assert('Client forwards playlist create result to NUI', /type = "playlistCreateResult"/.test(client));
assert('Server create accepts requestId', /function\(name, requestId\)/.test(server));
assert('Server emits structured create result', /pmms:playlistCreateResult/.test(server));
assert('Server result includes canonical snapshot', /payload\.playlists = snapshot\.playlists/.test(server));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
