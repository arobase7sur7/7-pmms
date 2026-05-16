import { getResourceName } from './nuiBridge';

type NuiPayload = Record<string, unknown>;
type MockPlaylist = {
  id: number;
  name: string;
  track_count: number;
  is_favorite: boolean;
};

type MockQueueEntry = {
  source: number;
  name: string;
  options: {
    title: string;
    url: string;
    originalUrl?: string;
    resolvedUrl?: string;
    author?: string;
    duration?: number;
    directLink?: Record<string, unknown>;
    resolver?: Record<string, unknown>;
  };
};

let installed = false;
let libraryRevision = 1;
let mockLoopMode = 'queue';
let mockPlaylists: MockPlaylist[] = [
  { id: 1, name: 'Downtown Set', track_count: 8, is_favorite: true },
  { id: 2, name: 'Garage Screens', track_count: 4, is_favorite: false }
];
let mockQueue: MockQueueEntry[] = [
  {
    source: 7,
    name: 'Arobase',
    options: {
      title: 'Prepared Direct Queue',
      url: 'https://example.com/prepared.mp3',
      resolvedUrl: 'https://example.com/prepared.mp3',
      author: 'Fast Queue',
      duration: 180,
      directLink: { validated: true }
    }
  },
  {
    source: 43,
    name: 'Cinema Host',
    options: {
      title: 'Fallback Queue Candidate',
      url: 'https://youtube.com/watch?v=fallback-demo',
      originalUrl: 'https://youtube.com/watch?v=fallback-demo',
      author: 'Provider Queue',
      duration: 240,
      resolver: { status: 'fallback', provider: 'embed', instance: 'youtube_embed' }
    }
  }
];

function post(payload: NuiPayload, delay = 0) {
  window.setTimeout(() => {
    window.dispatchEvent(new MessageEvent('message', { data: payload }));
  }, delay);
}

function response(body: unknown = { ok: true }) {
  return Promise.resolve(
    new Response(JSON.stringify(body), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  );
}

function librarySummary() {
  return {
    playlistCount: mockPlaylists.length,
    favoriteCount: mockPlaylists.filter((playlist) => playlist.is_favorite === true).length,
    maxPlaylists: 25,
    maxFavorites: 10
  };
}

function emitPlaylists(requestId?: unknown, delay = 80) {
  post({
    type: 'setPlaylists',
    requestId,
    playlists: mockPlaylists.map((playlist) => ({ ...playlist, is_favorite: playlist.is_favorite ? 1 : 0 })),
    summary: librarySummary(),
    libraryRevision
  }, delay);
}

function emitPlayerState(delay = 60) {
  post({
    type: 'updateUi',
    permissions: { interact: true, manage: true, anyUrl: true, customUrl: true },
    usableMediaPlayers: [
      { handle: 43, label: 'Cinema Screen', type: 'screen', distance: 4.8, capabilities: { video: true, audio: true } },
      { handle: 81, label: 'Flat TV', type: 'tv', distance: 8.2, capabilities: { video: true, audio: true } },
      { handle: 99, label: 'Nearby Vehicle', type: 'vehicle', distance: 11.4, isVehicle: true, capabilities: { audio: true } }
    ],
    activeMediaPlayers: {
      43: {
        canInteract: true,
        info: {
          title: 'React/Vite NUI Preview',
          url: 'https://example.com/demo.mp4',
          originalUrl: 'https://example.com/demo.mp4',
          paused: false,
          muted: false,
          loopMode: mockLoopMode,
          volume: 75,
          duration: 210,
          offset: 42,
          videoEnabled: true,
          video: true,
          canControl: true,
          queue: mockQueue
        }
      }
    },
    deviceSessions: {
      43: {
        queue: mockQueue,
        queueLength: mockQueue.length,
        historyCount: 1,
        settings: { loopMode: mockLoopMode, requestMode: 'pending' }
      }
    }
  }, delay);
}

function getPayloadField<T>(payload: unknown, field: string): T | undefined {
  if (!payload || typeof payload !== 'object') return undefined;
  return (payload as Record<string, T | undefined>)[field];
}

function handleMockCallback(name: string, payload: unknown) {
  switch (name) {
    case 'getPlaylists':
      emitPlaylists(getPayloadField(payload, 'requestId'));
      break;

    case 'getSharedPlaylists':
      post({
        type: 'setSharedPlaylists',
        playlists: [{ id: 11, name: 'Shared Cinema', owner_name: 'Matheo', track_count: 5 }]
      }, 90);
      break;

    case 'getPlaylistTracks': {
      const playlistId = typeof payload === 'object' && payload ? (payload as { playlistId?: unknown }).playlistId : 1;
      post({
        type: 'setPlaylistTracks',
        playlistId,
        tracks: [
          { id: 1, title: 'Direct MP3 Test', url: 'https://example.com/audio.mp3' },
          { id: 2, title: 'Big Screen Trailer', url: 'https://example.com/video.mp4' }
        ]
      }, 80);
      break;
    }

    case 'getFriends':
      post({
        type: 'setFriends',
        friends: [
          { id: 1, name: 'Arobase', source: 7, license: 'license:demo1' },
          { id: 2, name: 'Cinema Host', source: 43, license: 'license:demo2' }
        ]
      }, 70);
      break;

    case 'getFriendRequests':
      post({
        type: 'setFriendRequests',
        requests: [{ id: 3, name: 'New DJ', source: 12, license: 'license:demo3' }]
      }, 90);
      break;

    case 'searchMedia':
      post({
        type: 'searchResults',
        requestId: getPayloadField(payload, 'requestId'),
        results: [
          { title: 'Mock YouTube Result', url: 'https://youtube.com/watch?v=demo', author: '7-PMMS Dev', duration: 215, source: 'YouTube' },
          { title: 'Mock Direct Media', url: 'https://example.com/media.mp4', author: 'Local Preview', duration: 96, source: 'Direct' }
        ]
      }, 450);
      break;

    case 'play': {
      const options = getPayloadField<Record<string, unknown>>(payload, 'options') || {};
      mockQueue = mockQueue.concat({
        source: 7,
        name: 'Local Preview',
        options: {
          title: typeof options.title === 'string' ? options.title : 'Queued Mock Track',
          url: typeof options.url === 'string' ? options.url : 'https://example.com/queued.mp4',
          originalUrl: typeof options.url === 'string' ? options.url : 'https://example.com/queued.mp4',
          author: typeof options.author === 'string' ? options.author : 'Mock Search',
          duration: typeof options.duration === 'number' ? options.duration : 120
        }
      });
      emitPlayerState();
      break;
    }

    case 'removeFromQueue': {
      const index = Number(getPayloadField(payload, 'index'));
      if (Number.isFinite(index) && index > 0) {
        mockQueue = mockQueue.filter((_, entryIndex) => entryIndex !== index - 1);
      }
      emitPlayerState();
      break;
    }

    case 'next':
      if (mockQueue.length > 0) {
        mockQueue = mockQueue.slice(1);
      }
      emitPlayerState();
      break;

    case 'setLoopMode':
      mockLoopMode = String(getPayloadField(payload, 'loopMode') || mockLoopMode);
      emitPlayerState();
      break;

    case 'closeUi':
      post({ type: 'hideUi' }, 40);
      break;

    case 'setPlaylistFavorite': {
      const playlistId = Number(getPayloadField(payload, 'playlistId'));
      const favorite = getPayloadField<boolean>(payload, 'favorite') === true;
      const requestId = getPayloadField(payload, 'requestId');
      mockPlaylists = mockPlaylists.map((playlist) => (
        playlist.id === playlistId ? { ...playlist, is_favorite: favorite } : playlist
      ));
      libraryRevision += 1;
      mockPlaylists.sort((a, b) => Number(b.is_favorite) - Number(a.is_favorite));
      emitPlaylists(requestId, 70);
      post({
        type: 'playlistFavoriteUpdated',
        payload: {
          playlistId,
          requestId,
          is_favorite: favorite ? 1 : 0,
          isFavorite: favorite,
          success: true,
          playlists: mockPlaylists.map((playlist) => ({ ...playlist, is_favorite: playlist.is_favorite ? 1 : 0 })),
          summary: librarySummary(),
          libraryRevision
        }
      }, 120);
      break;
    }
  }
}

export function installDevMock() {
  if (installed || !import.meta.env.DEV) return;
  installed = true;

  if (typeof window.GetParentResourceName !== 'function') {
    window.GetParentResourceName = () => '7-pmms';
  }

  const originalFetch = window.fetch.bind(window);
  window.fetch = (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof Request ? input.url : String(input);
    const prefix = `https://${getResourceName()}/`;

    if (!url.startsWith(prefix)) {
      return originalFetch(input as RequestInfo | URL, init);
    }

    const name = url.slice(prefix.length);
    let payload: unknown = {};
    try {
      payload = init && typeof init.body === 'string' ? JSON.parse(init.body) : {};
    } catch {
      payload = {};
    }

    handleMockCallback(name, payload);
    return response({ ok: true });
  };

  post({
    type: 'showUi',
    searchSources: {
      youtube: { label: 'YouTube', enabled: true, placeholder: 'Search YouTube...' },
      soundcloud: { label: 'SoundCloud', enabled: true, placeholder: 'Search SoundCloud...' },
      twitch: { label: 'Twitch', enabled: true, placeholder: 'Enter Twitch Username...' },
      direct: { label: 'Direct', enabled: true, placeholder: 'Paste a direct media URL...' }
    },
    defaultSearchSource: 'youtube',
    selectedHandle: 43,
    defaultTransitionSeconds: 5,
    maxTransitionSeconds: 15,
    maxRange: 200,
    adminMaxRange: 200,
    searchMinimumBusyMs: 500,
    deviceDefaults: {
      volume: 100,
      attenuation: { sameRoom: 4, diffRoom: 6 },
      diffRoomVolume: 0.25,
      range: 30,
      transitionSeconds: 5,
      isVehicle: false
    }
  }, 50);

  emitPlayerState(120);
}
