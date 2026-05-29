import React, { useCallback, useEffect, useMemo } from "react";
import { motion } from "motion/react";
import { legacyActions } from "./legacy/controller";
import { sendNuiMessage } from "./nuiBridge";
import { AdminView } from "./AdminView";
import { EqualizerView } from "./EqualizerView";
import {
  Tabs,
  TabsList,
  TabsTrigger,
} from "./animate-ui/components/animate/tabs";
import { MotionProvider, usePmmsMotion } from "./motion/MotionProvider";
import { LegacyTooltipHost } from "./motion/LegacyTooltipHost";
import { useStableState } from "./useStableState";

function closeModal(id: string) {
  const modal = document.getElementById(id);
  if (modal) {
    modal.style.display = "none";
  }
}

function MusicLogoIcon() {
  return (
    <svg
      width="26"
      height="26"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 18V5l12-2v13" />
      <circle cx="6" cy="18" r="3" />
      <circle cx="18" cy="16" r="3" />
    </svg>
  );
}

function HomeIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  );
}

function LibraryIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
    </svg>
  );
}

function SocialIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  );
}

function AdminIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      <path d="M9 12l2 2 4-5" />
    </svg>
  );
}

function EqIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <line x1="4" y1="21" x2="4" y2="14" />
      <line x1="4" y1="10" x2="4" y2="3" />
      <line x1="12" y1="21" x2="12" y2="12" />
      <line x1="12" y1="8" x2="12" y2="3" />
      <line x1="20" y1="21" x2="20" y2="16" />
      <line x1="20" y1="12" x2="20" y2="3" />
      <line x1="1" y1="14" x2="7" y2="14" />
      <line x1="9" y1="8" x2="15" y2="8" />
      <line x1="17" y1="16" x2="23" y2="16" />
    </svg>
  );
}

function CloseMenuIcon() {
  return (
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <polyline points="16 17 21 12 16 7" />
      <line x1="21" y1="12" x2="9" y2="12" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg
      className="search-icon"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
  );
}

function BackIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <line x1="19" y1="12" x2="5" y2="12" />
      <polyline points="12 19 5 12 12 5" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

function PlayerMusicIcon() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 18V5l12-2v13" />
      <circle cx="6" cy="18" r="3" />
      <circle cx="18" cy="16" r="3" />
    </svg>
  );
}

function LoopIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polyline points="17 1 21 5 17 9" />
      <path d="M3 11V9a4 4 0 0 1 4-4h14" />
      <polyline points="7 23 3 19 7 15" />
      <path d="M21 13v2a4 4 0 0 1-4 4H3" />
    </svg>
  );
}

function InfoIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="12" cy="12" r="10" />
      <line x1="12" y1="16" x2="12" y2="12" />
      <line x1="12" y1="8" x2="12.01" y2="8" />
    </svg>
  );
}

function PreviousIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polygon points="19 20 9 12 19 4 19 20" />
      <line x1="5" y1="19" x2="5" y2="5" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="currentColor"
      stroke="currentColor"
      strokeWidth="0.5"
      strokeLinejoin="round"
    >
      <polygon points="5 3 19 12 5 21" />
    </svg>
  );
}

function NextIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polygon points="5 4 15 12 5 20 5 4" />
      <line x1="19" y1="5" x2="19" y2="19" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <rect x="3" y="3" width="18" height="18" rx="2" />
    </svg>
  );
}

function VideoIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polygon points="23 7 16 12 23 17 23 7" />
      <rect x="1" y="5" width="15" height="14" rx="2" />
    </svg>
  );
}

function VolumeIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
      <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
      <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
    </svg>
  );
}

function Sidebar() {
  const motionConfig = usePmmsMotion();
  const [activeView, setActiveView] = useStableState("view-home");

  useEffect(() => {
    const handler = (event: Event) => {
      const detail = (event as CustomEvent<{ viewId?: string }>).detail;
      if (detail?.viewId) setActiveView(detail.viewId);
    };
    window.addEventListener("pmms:viewChanged", handler);
    return () => window.removeEventListener("pmms:viewChanged", handler);
  }, []);

  const navItems = useMemo(() => [
    { viewId: "view-home", label: "Home", icon: <HomeIcon />, className: "" },
    {
      viewId: "view-library",
      label: "Library",
      icon: <LibraryIcon />,
      className: "",
    },
    {
      viewId: "view-social",
      label: "Social",
      icon: <SocialIcon />,
      className: "",
    },
    {
      viewId: "view-equalizer",
      label: "Equalizer",
      icon: <EqIcon />,
      className: "",
    },
    {
      viewId: "view-admin",
      label: "Admin",
      icon: <AdminIcon />,
      className: "staff-only",
    },
  ], []);
  const handleViewChange = useCallback((viewId: string) => legacyActions.switchView(viewId), []);
  const handleCloseMenu = useCallback(() => void sendNuiMessage("closeUi"), []);

  return (
    <aside id="sidebar">
      <motion.div
        className="sidebar-logo"
        initial={motionConfig.reducedMotion ? false : { opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={motionConfig.softSpring}
      >
        <MusicLogoIcon />
        <div>
          <div className="sidebar-logo-text">7-PMMS</div>
          <div className="sidebar-logo-version">Media Player</div>
        </div>
      </motion.div>

      <nav>
        <Tabs
          value={activeView}
          onValueChange={handleViewChange}
          className="pmms-nav-tabs"
          transition={motionConfig.spring}
        >
          <TabsList className="pmms-nav-list">
            {navItems.map((item, index) => (
              <TabsTrigger
                key={item.viewId}
                value={item.viewId}
                className={`nav-item ${item.className} ${activeView === item.viewId ? "active" : ""}`}
                data-target={item.viewId}
                initial={
                  motionConfig.reducedMotion ? false : { opacity: 0, x: -8 }
                }
                animate={{ opacity: 1, x: 0 }}
                transition={{
                  ...motionConfig.softSpring,
                  delay: motionConfig.reducedMotion ? 0 : index * 0.035,
                }}
              >
                {item.icon}
                <span>{item.label}</span>
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
        <div className="nav-divider" />

        <motion.div
          className="sidebar-favorites"
          initial={motionConfig.reducedMotion ? false : { opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{
            ...motionConfig.softSpring,
            delay: motionConfig.reducedMotion ? 0 : 0.08,
          }}
        >
          <div className="sidebar-favorites-title">Favorites</div>
          <div id="sidebar-favorites-list" className="sidebar-favorites-list">
            <div className="sidebar-favorites-empty">No favorites pinned</div>
          </div>
        </motion.div>
      </nav>

      <div className="sidebar-footer">
        <button
          className="sidebar-footer-btn"
          onClick={handleCloseMenu}
        >
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
        <button
          id="youtube-provider-btn"
          type="button"
          title="YouTube source provider"
        >
          Auto
        </button>
        <input
          type="text"
          id="search-input"
          placeholder="Search or paste a URL..."
          autoComplete="off"
        />
        <button id="search-btn">Search</button>
      </div>
      <div
        id="search-status"
        className="search-status"
        style={{ display: "none" }}
      />
      <div id="search-results" style={{ display: "none" }} />

      <div className="section-row">
        <span className="section-title">Nearby Devices</span>
        <span className="section-count" id="devices-count">
          None found
        </span>
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
          <button
            className="btn-accent"
            onClick={() => legacyActions.openCreatePlaylist()}
          >
            + New Playlist
          </button>
        </div>
      </div>

      <div className="section-row" style={{ marginBottom: 12 }}>
        <span className="section-title">Your Playlists</span>
      </div>
      <div id="playlists-grid" className="playlists-grid" />

      <div className="separator" style={{ margin: "24px 0" }} />

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
          onClick={() => legacyActions.switchView("view-library")}
          title="Back to Library"
          style={{ marginRight: 4 }}
        >
          <BackIcon />
        </button>
        <h2 id="current-playlist-title">Playlist</h2>
        <div className="view-header-actions">
          <button
            className="btn-outline"
            onClick={() => legacyActions.playPlaylist()}
          >
            Play All
          </button>
          <button
            className="btn-danger"
            onClick={() => legacyActions.deleteCurrentPlaylist()}
          >
            Delete
          </button>
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
        <input
          type="text"
          id="friend-id-input"
          placeholder="Enter player server ID..."
        />
        <button
          className="btn-accent"
          onClick={() => legacyActions.sendFriendRequest()}
        >
          Add Friend
        </button>
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

function MainContent({
  eqConfig,
  analyserData,
}: {
  eqConfig: any;
  analyserData: Float32Array | null;
}) {
  return (
    <main id="main-content">
      <HomeView />
      <LibraryView />
      <PlaylistView />
      <SocialView />
      <EqualizerView eqConfig={eqConfig} analyserData={analyserData} />
      <AdminView />
    </main>
  );
}

function NowPlayingBar() {
  const openLoopHelp = useCallback(() => {
    const modal = document.getElementById("loop-help-modal");
    if (modal) modal.style.display = "flex";
  }, []);

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
            onClick={openLoopHelp}
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
          <span className="time-label" id="np-time-current">
            0:00
          </span>
          <input
            type="range"
            id="np-progress"
            min="0"
            max="100"
            defaultValue="0"
            disabled
          />
          <span className="time-label right" id="np-time-total">
            0:00
          </span>
        </div>
      </div>

      <div className="player-right">
        <button
          id="np-video"
          className="btn-icon"
          disabled
          title="Toggle Video"
        >
          <VideoIcon />
        </button>
        <div className="volume-group">
          <button id="np-mute" className="btn-icon" disabled title="Mute">
            <VolumeIcon />
          </button>
          <input
            type="range"
            id="np-volume"
            min="0"
            max="100"
            defaultValue="100"
            disabled
          />
          <span id="np-volume-val">100%</span>
        </div>
      </div>
    </footer>
  );
}

function AdminModal() {
  return (
    <div
      id="admin-modal"
      className="modal-backdrop"
      style={{ display: "none" }}
    >
      <div className="modal modal-wide">
        <div className="modal-header">
          <h3>Device Settings</h3>
          <button
            className="btn-icon btn-sm"
            onClick={() => legacyActions.closeAdminModal()}
          >
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
    <div
      id="share-modal"
      className="modal-backdrop"
      style={{ display: "none" }}
    >
      <div className="modal">
        <div className="modal-header">
          <h3>Share Playlist</h3>
          <button
            className="btn-icon btn-sm"
            onClick={() => closeModal("share-modal")}
          >
            <XIcon />
          </button>
        </div>
        <div className="modal-body">
          <p
            style={{
              fontSize: 13,
              color: "var(--text-muted)",
              marginBottom: 14,
            }}
          >
            Select a friend to share with:
          </p>
          <div id="share-friends-list" className="list-container" />
        </div>
      </div>
    </div>
  );
}

function AddToPlaylistModal() {
  return (
    <div
      id="add-to-playlist-modal"
      className="modal-backdrop"
      style={{ display: "none" }}
    >
      <div className="modal">
        <div className="modal-header">
          <h3>Add to Playlist</h3>
          <button
            className="btn-icon btn-sm"
            onClick={() => closeModal("add-to-playlist-modal")}
          >
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
    <div
      id="prompt-modal"
      className="modal-backdrop"
      style={{ display: "none" }}
    >
      <div className="modal">
        <div className="modal-header">
          <h3 id="prompt-title">Input</h3>
        </div>
        <div className="modal-body">
          <input type="text" id="prompt-input" style={{ marginBottom: 16 }} />
          <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
            <button className="btn-outline" id="prompt-cancel">
              Cancel
            </button>
            <button className="btn-accent" id="prompt-confirm">
              Confirm
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ConfirmModal() {
  return (
    <div
      id="confirm-modal"
      className="modal-backdrop"
      style={{ display: "none" }}
    >
      <div className="modal">
        <div className="modal-header">
          <h3 id="confirm-title">Are you sure?</h3>
        </div>
        <div className="modal-body">
          <p
            id="confirm-message"
            style={{
              fontSize: 13.5,
              color: "var(--text-muted)",
              lineHeight: 1.6,
              marginBottom: 20,
            }}
          />
          <div style={{ display: "flex", gap: 10, justifyContent: "flex-end" }}>
            <button className="btn-outline" id="confirm-cancel">
              Cancel
            </button>
            <button className="btn-danger" id="confirm-ok">
              Confirm
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function LoopHelpModal() {
  return (
    <div
      id="loop-help-modal"
      className="modal-backdrop"
      style={{ display: "none" }}
    >
      <div className="modal">
        <div className="modal-header">
          <h3>Playback Modes</h3>
          <button
            className="btn-icon btn-sm"
            onClick={() => closeModal("loop-help-modal")}
          >
            <XIcon />
          </button>
        </div>
        <div className="modal-body">
          <div className="loop-mode-help-list">
            <div className="loop-mode-help-item">
              <strong>Loop Off</strong>
              <span>
                Play the current media once. If the manual queue has tracks, the
                next queued item still plays.
              </span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Loop Track</strong>
              <span>
                Repeat the current media only. Manual queue items wait until you
                change mode or press Next.
              </span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Loop Queue</strong>
              <span>
                Play the queue in order and recycle the current track to the
                back of the queue.
              </span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Shuffle 1x</strong>
              <span>
                Play queued tracks once in a shuffled order, then stop when the
                queue is empty.
              </span>
            </div>
            <div className="loop-mode-help-item">
              <strong>Shuffle Loop</strong>
              <span>
                Shuffle queued tracks and keep recycling playback so the queue
                keeps going.
              </span>
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

function AppShell() {
  const [eqConfig, setEqConfig] = useStableState<any>(null);
  const [analyserData, setAnalyserData] = useStableState<Float32Array | null>(null);

  useEffect(() => {
    const handler = (event: MessageEvent) => {
      const data = event.data;
      if (!data || !data.type) return;

      if (data.type === "showUi" || data.type === "startup") {
        if (data.equalizerConfig) setEqConfig(data.equalizerConfig);
        if (Object.prototype.hasOwnProperty.call(data, "selectedHandle")) {
          window.dispatchEvent(
            new CustomEvent("pmms:adminSelectHandle", {
              detail: { handle: data.selectedHandle ?? null },
            }),
          );
        }
        if (data.admin)
          window.dispatchEvent(
            new CustomEvent("pmms:adminUpdate", {
              detail: { ...data.admin, selectedHandle: data.selectedHandle },
            }),
          );
      }
      if (data.type === "updateUi") {
        if (data.admin) {
          window.dispatchEvent(
            new CustomEvent("pmms:adminUpdate", {
              detail: {
                ...data.admin,
                activeMediaPlayers: data.activeMediaPlayers,
                usableMediaPlayers: data.usableMediaPlayers,
                deviceSessions: data.deviceSessions,
              },
            }),
          );
        }
      }
      if (data.type === "eqProfile") {
        window.dispatchEvent(
          new CustomEvent("pmms:eqProfile", { detail: data }),
        );
      }
      if (data.type === "eqDeviceProfile") {
        window.dispatchEvent(
          new CustomEvent("pmms:eqDeviceProfile", { detail: data }),
        );
      }
      if (data.type === "eqAnalyserFrame" && data.bins) {
        setAnalyserData(new Float32Array(data.bins));
      }
    };
    window.addEventListener("message", handler);
    return () => window.removeEventListener("message", handler);
  }, []);

  return (
    <div id="app-container">
      <LegacyTooltipHost />
      <div className="app-body">
        <Sidebar />
        <MainContent eqConfig={eqConfig} analyserData={analyserData} />
      </div>
      <NowPlayingBar />
      <Modals />
    </div>
  );
}

export function App() {
  return (
    <MotionProvider>
      <AppShell />
    </MotionProvider>
  );
}
