import { legacyActions } from './legacy/controller';
import { sendNuiMessage } from './nuiBridge';

function closeModal(id: string) {
  const modal = document.getElementById(id);
  if (modal) {
    modal.style.display = 'none';
  }
}

function MusicLogoIcon() {
  return (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 18V5l12-2v13" />
      <circle cx="6" cy="18" r="3" />
      <circle cx="18" cy="16" r="3" />
    </svg>
  );
}

function HomeIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  );
}

function LibraryIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
    </svg>
  );
}

function SocialIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  );
}

function CloseMenuIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <polyline points="16 17 21 12 16 7" />
      <line x1="21" y1="12" x2="9" y2="12" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg className="search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
  );
}

function BackIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <line x1="19" y1="12" x2="5" y2="12" />
      <polyline points="12 19 5 12 12 5" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

function PlayerMusicIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
      <path d="M9 18V5l12-2v13" />
      <circle cx="6" cy="18" r="3" />
      <circle cx="18" cy="16" r="3" />
    </svg>
  );
}

function LoopIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <polyline points="17 1 21 5 17 9" />
      <path d="M3 11V9a4 4 0 0 1 4-4h14" />
      <polyline points="7 23 3 19 7 15" />
      <path d="M21 13v2a4 4 0 0 1-4 4H3" />
    </svg>
  );
}

function InfoIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="16" x2="12" y2="12" />
      <line x1="12" y1="8" x2="12.01" y2="8" />
    </svg>
  );
}

function PreviousIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <polygon points="19 20 9 12 19 4 19 20" />
      <line x1="5" y1="19" x2="5" y2="5" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="5 3 19 12 5 21" />
    </svg>
  );
}

function NextIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <polygon points="5 4 15 12 5 20 5 4" />
      <line x1="19" y1="5" x2="19" y2="19" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="3" y="3" width="18" height="18" rx="2" />
    </svg>
  );
}

function VideoIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <polygon points="23 7 16 12 23 17 23 7" />
      <rect x="1" y="5" width="15" height="14" rx="2" />
    </svg>
  );
}

function VolumeIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
      <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
      <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
    </svg>
  );
}

function Sidebar() {
  return (
    <aside id="sidebar">
      <div className="sidebar-logo">
        <MusicLogoIcon />
        <div>
          <div className="sidebar-logo-text">7-PMMS</div>
          <div className="sidebar-logo-version">Media Player</div>
        </div>
      </div>

      <nav>
        <button className="nav-item active" data-target="view-home" onClick={() => legacyActions.switchView('view-home')}>
          <HomeIcon />
          Home
        </button>
        <button className="nav-item" data-target="view-library" onClick={() => legacyActions.switchView('view-library')}>
          <LibraryIcon />
          Library
        </button>
        <button className="nav-item" data-target="view-social" onClick={() => legacyActions.switchView('view-social')}>
          <SocialIcon />
          Social
        </button>
        <div className="nav-divider" />

        <div className="sidebar-favorites">
          <div className="sidebar-favorites-title">Favorites</div>
          <div id="sidebar-favorites-list" className="sidebar-favorites-list">
            <div className="sidebar-favorites-empty">No favorites pinned</div>
          </div>
        </div>
      </nav>

      <div className="sidebar-footer">
        <button className="sidebar-footer-btn" onClick={() => void sendNuiMessage('closeUi')}>
          <CloseMenuIcon />
          Close Menu
        </button>
      </div>
    </aside>
  );
}

function HomeView() {
  return (
    <div id="view-home" className="view active">
      <div id="search-bar">
        <SearchIcon />
        <select id="search-source" />
        <input type="text" id="search-input" placeholder="Search YouTube, paste a URL..." autoComplete="off" />
        <button id="search-btn">Search</button>
      </div>
      <div id="search-status" className="search-status" style={{ display: 'none' }} />
      <div id="search-results" style={{ display: 'none' }} />

      <div className="section-row">
        <span className="section-title">Nearby Devices</span>
        <span className="section-count" id="devices-count">None found</span>
      </div>
      <div id="devices-grid" />

      <div id="now-playing-panel" />
    </div>
  );
}

function LibraryView() {
  return (
    <div id="view-library" className="view">
      <div className="view-header">
        <h2>Your Library</h2>
        <div className="view-header-actions">
          <button className="btn-accent" onClick={() => legacyActions.openCreatePlaylist()}>+ New Playlist</button>
        </div>
      </div>

      <div className="section-row" style={{ marginBottom: 12 }}>
        <span className="section-title">Your Playlists</span>
      </div>
      <div id="playlists-grid" className="playlists-grid" />

      <div className="separator" style={{ margin: '24px 0' }} />

      <div className="section-row" style={{ marginBottom: 12 }}>
        <span className="section-title">Shared With You</span>
      </div>
      <div id="shared-playlists-grid" className="playlists-grid" />
    </div>
  );
}

function PlaylistView() {
  return (
    <div id="view-playlist" className="view">
      <div className="view-header">
        <button
          className="btn-icon btn-sm"
          onClick={() => legacyActions.switchView('view-library')}
          title="Back to Library"
          style={{ marginRight: 4 }}
        >
          <BackIcon />
        </button>
        <h2 id="current-playlist-title">Playlist</h2>
        <div className="view-header-actions">
          <button className="btn-outline" onClick={() => legacyActions.playPlaylist()}>Play All</button>
          <button className="btn-danger" onClick={() => legacyActions.deleteCurrentPlaylist()}>Delete</button>
        </div>
      </div>
      <div id="tracks-list" />
    </div>
  );
}

function SocialView() {
  return (
    <div id="view-social" className="view">
      <div className="view-header">
        <h2>Social</h2>
      </div>

      <div className="add-friend-bar">
        <input type="text" id="friend-id-input" placeholder="Enter player server ID..." />
        <button className="btn-accent" onClick={() => legacyActions.sendFriendRequest()}>Add Friend</button>
      </div>

      <div className="split-layout">
        <div>
          <div className="section-row" style={{ marginBottom: 12 }}>
            <span className="section-title">Friends</span>
          </div>
          <div id="friends-list" />
        </div>
        <div>
          <div className="section-row" style={{ marginBottom: 12 }}>
            <span className="section-title">Pending Requests</span>
          </div>
          <div id="requests-list" />
        </div>
      </div>
    </div>
  );
}

function MainContent() {
  return (
    <main id="main-content">
      <HomeView />
      <LibraryView />
      <PlaylistView />
      <SocialView />
    </main>
  );
}

function NowPlayingBar() {
  return (
    <footer id="now-playing-bar">
      <div className="player-left">
        <div className="player-left-icon">
          <PlayerMusicIcon />
        </div>
        <div className="player-meta">
          <div id="np-title">No Device Selected</div>
          <div id="np-subtitle">Select a nearby device to begin</div>
        </div>
      </div>

      <div className="player-center">
        <div className="player-controls">
          <button id="np-loop" className="btn-icon" disabled title="Loop">
            <LoopIcon />
          </button>
          <button
            id="np-loop-info"
            className="btn-icon"
            title="Loop mode help"
            aria-label="Loop mode help"
            onClick={() => {
              const modal = document.getElementById('loop-help-modal');
              if (modal) modal.style.display = 'flex';
            }}
          >
            <InfoIcon />
          </button>
          <button id="np-prev" className="btn-icon" disabled title="Previous">
            <PreviousIcon />
          </button>
          <button id="np-play" disabled title="Play / Pause">
            <PlayIcon />
          </button>
          <button id="np-next" className="btn-icon" disabled title="Next">
            <NextIcon />
          </button>
          <button id="np-stop" className="btn-icon" disabled title="Stop">
            <StopIcon />
          </button>
        </div>
        <div className="progress-row">
          <span className="time-label" id="np-time-current">0:00</span>
          <input type="range" id="np-progress" min="0" max="100" defaultValue="0" disabled />
          <span className="time-label right" id="np-time-total">0:00</span>
        </div>
      </div>

      <div className="player-right">
        <button id="np-video" className="btn-icon" disabled title="Toggle Video">
          <VideoIcon />
        </button>
        <div className="volume-group">
          <button id="np-mute" className="btn-icon" disabled title="Mute">
            <VolumeIcon />
          </button>
          <input type="range" id="np-volume" min="0" max="100" defaultValue="100" disabled />
          <span id="np-volume-val">100%</span>
        </div>
      </div>
    </footer>
  );
}

function AdminModal() {
  return (
    <div id="admin-modal" className="modal-backdrop" style={{ display: 'none' }}>
      <div className="modal modal-wide">
        <div className="modal-header">
          <h3>Device Settings</h3>
          <button className="btn-icon btn-sm" onClick={() => legacyActions.closeAdminModal()}>
            <XIcon />
          </button>
        </div>
        <div className="modal-body" id="admin-body" />
      </div>
    </div>
  );
}

function ShareModal() {
  return (
    <div id="share-modal" className="modal-backdrop" style={{ display: 'none' }}>
      <div className="modal">
        <div className="modal-header">
          <h3>Share Playlist</h3>
          <button className="btn-icon btn-sm" onClick={() => closeModal('share-modal')}>
            <XIcon />
          </button>
        </div>
        <div className="modal-body">
          <p style={{ fontSize: 13, color: 'var(--text-muted)', marginBottom: 14 }}>Select a friend to share with:</p>
          <div id="share-friends-list" className="list-container" />
        </div>
      </div>
    </div>
  );
}

function AddToPlaylistModal() {
  return (
    <div id="add-to-playlist-modal" className="modal-backdrop" style={{ display: 'none' }}>
      <div className="modal">
        <div className="modal-header">
          <h3>Add to Playlist</h3>
          <button className="btn-icon btn-sm" onClick={() => closeModal('add-to-playlist-modal')}>
            <XIcon />
          </button>
        </div>
        <div className="modal-body">
          <div id="atp-list" className="list-container" />
        </div>
      </div>
    </div>
  );
}

function PromptModal() {
  return (
    <div id="prompt-modal" className="modal-backdrop" style={{ display: 'none' }}>
      <div className="modal">
        <div className="modal-header">
          <h3 id="prompt-title">Input</h3>
        </div>
        <div className="modal-body">
          <input type="text" id="prompt-input" style={{ marginBottom: 16 }} />
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button className="btn-outline" id="prompt-cancel">Cancel</button>
            <button className="btn-accent" id="prompt-confirm">Confirm</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ConfirmModal() {
  return (
    <div id="confirm-modal" className="modal-backdrop" style={{ display: 'none' }}>
      <div className="modal">
        <div className="modal-header">
          <h3 id="confirm-title">Are you sure?</h3>
        </div>
        <div className="modal-body">
          <p id="confirm-message" style={{ fontSize: 13.5, color: 'var(--text-muted)', lineHeight: 1.6, marginBottom: 20 }} />
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button className="btn-outline" id="confirm-cancel">Cancel</button>
            <button className="btn-danger" id="confirm-ok">Confirm</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function LoopHelpModal() {
  return (
    <div id="loop-help-modal" className="modal-backdrop" style={{ display: 'none' }}>
      <div className="modal">
        <div className="modal-header">
          <h3>Playback Modes</h3>
          <button className="btn-icon btn-sm" onClick={() => closeModal('loop-help-modal')}>
            <XIcon />
          </button>
        </div>
        <div className="modal-body">
          <div className="loop-mode-help-list">
            <div className="loop-mode-help-item">
              <strong>Loop Off</strong>
              <span>Play the current media once. If the manual queue has tracks, the next queued item still plays.</span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Loop Track</strong>
              <span>Repeat the current media only. Manual queue items wait until you change mode or press Next.</span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Loop Queue</strong>
              <span>Play the queue in order and recycle the current track to the back of the queue.</span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Shuffle 1x</strong>
              <span>Play queued tracks once in a shuffled order, then stop when the queue is empty.</span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Shuffle Loop</strong>
              <span>Shuffle queued tracks and keep recycling playback so the queue keeps going.</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Modals() {
  return (
    <>
      <AdminModal />
      <ShareModal />
      <AddToPlaylistModal />
      <LoopHelpModal />
      <PromptModal />
      <ConfirmModal />
      <div id="notification-container" />
    </>
  );
}

export function App() {
  return (
    <div id="app-container">
      <div className="app-body">
        <Sidebar />
        <MainContent />
      </div>
      <NowPlayingBar />
      <Modals />
    </div>
  );
}
