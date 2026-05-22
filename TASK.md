# 7-pmms Backend — Task Tracker

## Current Task
**DONE** — Playback/UI regression fixes complete

## Backlog

### Sync (Problem 1)
- [x] A-ANALYZE — Read `server/main.lua` + `server/media.lua`. Find: sync loop location, broadcast frequency, payload size, whether dirty flags exist, how joining players receive state. Write findings below.
- [x] A-FIX     — Implement sync fixes based on A-ANALYZE findings: throttle, delta, TriggerLatentClientEvent for large payloads, targeted join sync, periodic full resync

### Resolver (Problem 2)
- [x] B-ANALYZE — Read `server/resolver.lua` + how it's called from `server/main.lua` or `server/media.lua`. Find: deduplication (yes/no), per-provider concurrency limits (yes/no), timeouts (yes/no), failover mechanism, how result is returned. Write findings below.
- [x] B-FIX     — Implement resolver fixes based on B-ANALYZE findings: dedup, semaphores, per-provider timeouts, adaptive ban, hedged failover, absolute timeout, progress events, cancel handler

### Queue / Race Conditions (Problem 3)
- [x] C-ANALYZE — Read `server/queue.lua` + `server/main.lua` + `server/media.lua`. Find: how queue is stored, what functions mutate it, whether any locking exists, whether version/optimistic locking exists. Write findings below.
- [x] C-FIX     — Implement queue fixes based on C-ANALYZE findings: per-device mutex, version counter, stale-rejection with resync

### Join Sync (Problem 4)
- [x] D-ANALYZE — Read `client/main.lua` + `client/media.lua` + how server sends state on join. Find: is latency compensation applied (yes/no), is there a drift correction loop (yes/no), does `onClientResourceStart` re-request state (yes/no). Write findings below.
- [x] D-FIX     — Implement join sync fixes based on D-ANALYZE findings: _sentAt timestamp, client-side latency compensation, drift correction loop, resource restart recovery

### Discovery (Problem 5)
- [x] E-ANALYZE — Read `client/entities.lua` + `client/main.lua`. Find: discovery mechanism (poll/push/both), poll interval, whether interval adapts when device is selected, whether mass-join jitter exists. Write findings below.
- [x] E-FIX     — Implement discovery fixes based on E-ANALYZE findings: adaptive interval, join jitter, optionally server-push nearby list

### Database (Problem 6)
- [x] F-ANALYZE — Read `server/database.lua` + `pmms.sql`. Find: missing indexes, SELECT * queries, any existing caching. Write findings below.
- [x] F-FIX     — Add missing indexes to pmms.sql; fix SELECT * in database.lua; add persistent device cache if warranted

### Config
- [x] G         — Read `config/config.lua` in full. Add only the Config keys from PLAN_BACKEND.md that don't already exist.

### Playback / UI Regression
- [x] H-ANALYZE — Read `server/resolver.lua`, `server/search.lua`, `server/media.lua`, `client/dui.lua`, `client/nui.lua`, `http/dui_runtime/index.html`, `http/dui_runtime/script.js`, `http/dui_runtime/style.css`, `nui/src/App.tsx`, `nui/src/legacy/controller.js`, `nui/src/styles.css`, and built `ui/*` assets. Find: when embed fallback is selected, why blocked playback falls back to YouTube, how search thumbnails are surfaced, and how nearby devices render when crowded. Write findings below.
- [x] H-FIX     — Implement fixes based on H-ANALYZE findings: avoid embedded YouTube fallback for normal playback, prefer direct/proxied resolver streams or structured failure, restore thumbnails, and keep nearby devices to one row with a More modal.

---

## Findings

### A-ANALYZE
- Sync loop is `syncMediaPlayers()` in `server/main.lua` lines ~90-145, called from the main Citizen thread every 250ms at lines ~238-246.
- The loop updates active player offsets every tick, advances/removes ended media, runs cleanup hooks, drains `syncQueue`, then sends `pmms:sync` when the global `dirty` flag is set or `os.time() - lastBroadcast > 10`.
- Broadcast cadence is therefore: dirty changes sync on the next 250ms loop tick; otherwise a full periodic sync happens after more than 10 seconds, effectively about every 11 seconds because the clock is whole seconds.
- The sync is not a single `-1` broadcast. `server/main.lua` lines ~132-140 loops `GetPlayers()` and sends `TriggerClientEvent("pmms:sync", target, payload)` to each player. When available, `BuildMediaPlayersSyncStateForPlayer(target)` builds a player-specific payload.
- Payload size is not measured in code. There is no `json.encode` size check and no `TriggerLatentClientEvent` use for `pmms:sync`. The payload built in `server/media.lua` lines ~449-526 includes full `mediaPlayers`, `startupStates`, and `deviceSessions`; session data includes settings/defaults, full queue, recent history, playback preview, current track, request state, linked speakers, equalizer profile, pending requests, and optional admin state.
- History is capped for sync by `Config.ui.maxHistorySyncItems` (default 30) in `cloneRecentHistoryForSync`, but queue and playback preview are still sent as full tables.
- Dirty tracking exists, but only as one global boolean in `server/main.lua` plus `syncQueue`. `SetMediaPlayer`, `RemoveMediaPlayerEntry`, `EnqueueSync`, and `MarkDirty` mark it dirty; `commitDeviceSession()` in `server/media.lua` line ~945 marks dirty after session changes. There are no per-device dirty flags or delta payloads for sync, although sessions do maintain `stateRevision`.
- `server/media.lua` does broadcast directly in some paths. `pushImmediateSync()` at lines ~529-538 sends full `pmms:sync` snapshots immediately to one target or every player, and it is called by startup state changes, startup-ready, metadata updates, ended-track loop handling, local playback failure, and device destruction paths.
- Other media changes only mark dirty and wait for the main loop, including pause/play seek/settings changes. Add/remove lifecycle also uses `EnqueueSync()` to broadcast `pmms:play`/`pmms:stop` to `-1` before the next full sync.
- Joining/player initialization receives targeted full state: `pmms:loadPermissions` sends `pmms:sync` to `src` in `server/media.lua` lines ~4186-4190, and `playerJoining` sends targeted `pmms:sync` at lines ~4193-4195.
- Main risk for A-FIX: full sync snapshots can be duplicated and unthrottled by immediate sync paths, and large per-player payloads are always sent via normal `TriggerClientEvent` rather than latent events or deltas.

### B-ANALYZE
- `server/resolver.lua` already has result caching and non-forced in-flight deduplication. `resolveCache`/`resolveInflight` are declared at lines ~10-11; `ResolvePlaybackOptions()` joins an existing in-flight resolve at lines ~2882-2896 unless `resolverOptions.forceRefresh == true`.
- The in-flight key includes URL, video/audio mode, fallback flags, forced provider, avoid provider, avoid instance, avoid resolved URL, and audio fallback state at lines ~592-617. This means normal duplicate starts dedupe, but forced retries and slightly different retry options create separate resolver work.
- Cache lookup happens in `resolveYoutubeStream()` lines ~2506-2560, keyed only by YouTube video id and video/audio mode. Cached entries are bypassed when the cached provider/instance is suppressed, embed fallback is disallowed, or retry options ask to avoid the cached provider, instance, or URL.
- Per-provider concurrency exists only for Invidious/Piped instance fanout. `resolveAcrossInstances()` lines ~2366-2433 runs up to `Config.resolver.parallelInstancesPerProvider` instances at once, default 2. The provider chain itself remains sequential in `tryProvider()` lines ~2744-2869.
- HTTP extractor and Cobalt endpoints are tried sequentially inside each provider at lines ~1368-1428 and ~1561-1633. Local `yt-dlp` is synchronous through `io.popen` at lines ~704-753, so it can block the server tick while the command runs.
- Timeouts are partially present. `PerformHttpRequest` calls pass native timeout options through `performGet()`/`performPost()` at lines ~424-470, instance discovery has a `SetTimeout` guard at lines ~2106-2108, and yt-dlp uses socket timeout plus a shell `timeout` wrapper on non-Windows at lines ~1245-1249. There is no resolver-wide absolute timeout wrapping the whole `ResolvePlaybackOptions()` operation.
- Adaptive behavior exists, but it is ranking and cooldown rather than a provider ban system. Provider stats are recorded by `RecordResolverProviderPlayback()` lines ~220-280 and later reorder providers through `getAdaptiveProviderOrder()` lines ~175-218; provider cooldown exists for local yt-dlp at lines ~391-393 and instance suppression exists for Invidious/Piped/HTTP extractor/Cobalt at lines ~1636-1700.
- Failover is sequential by provider order: default order is `yt_dlp_local`, `extractor_http`, `cobalt`, `invidious`, `piped` at lines ~960-993, with optional embed fallback. If video resolution fails and audio fallback is allowed, it recursively tries audio-only at lines ~2634-2705, then embed fallback if enabled at lines ~2709-2741.
- `server/media.lua` is the caller. `resolvePlaybackAndNotify()` lines ~1296-1347 calls `ResolvePlaybackOptions(options, resolverOptions, callback)` and returns `(ok, resolvedOptions, warning)` to the playback start flow; failures optionally trigger `pmms:error`.
- Playback starts call the resolver in `startMediaPlayerForClient()` lines ~2482-2562 after direct-link probing. Startup and local playback failures use forced refresh, avoid URL/provider/instance, and `maxInstances` retry options at lines ~3328-3340 and ~3497-3508.
- Client-reported resolver failures suppress the failed resolver instance with `SuppressResolverInstance()` from `server/media.lua` lines ~3257-3261 and ~3427-3431, implemented in `server/resolver.lua` lines ~1663-1680.
- A cancel handler already exists: `pmms:cancelStartup` calls `cancelStartupForSource()` at `server/media.lua` lines ~1551-1636 and ~3588-3589. It clears the startup context, releases the restricted device, and stops the client startup attempt, but it does not cancel resolver HTTP requests, queued callbacks, or in-flight dedup listeners.
- No resolver call path was found in `server/main.lua`; resolver work is driven from `server/media.lua`.

### C-ANALYZE
- Queue state is stored on `deviceSessions[handle].queue` in `server/media.lua`. Sessions are created with `queue = {}` and `stateRevision` at lines ~1049-1068, returned by `GetDeviceSession()`/`GetDeviceSessions()` at lines ~1071-1076, and committed by `commitDeviceSession()`/`CommitDeviceSessionState()` at lines ~1035-1084.
- Active media players mirror the same queue table. `syncActiveMediaPlayerWithSession()` copies `session.queue` and `session.stateRevision` onto `mp` at lines ~1024-1033, and `AddMediaPlayer()` sets `options.queue = session.queue` before `SetMediaPlayer()` at lines ~2370-2428.
- `server/queue.lua` is the main mutator. `AddToQueue()` appends entries at lines ~536-595, `RemoveFromQueue()` uses `table.remove(session.queue, parsedIndex)` at lines ~597-624, `PlayNextInQueue()` recycles/removes/advances entries at lines ~626-726, and `PlayPreviousFromHistory()` prepends the current track via `PrependDeviceQueueEntry()` at lines ~728-781.
- Queue IDs exist but are mostly internal. `ensureSessionQueueMetadata()` assigns `queueId` and `nextQueueEntryId` at `server/queue.lua` lines ~50-72, and shuffle preview tracks queue IDs, but `RemoveFromQueue()` still treats the client-provided id as an array index at lines ~604-609.
- Async queue mutations exist. `prepareNextEntry()` starts `ResolvePlaybackOptions()` for the first queued item and later mutates the live first queue entry only if its signature still matches at lines ~388-450. `AddToQueue()` also starts `ResolvePlaybackOptions()` and later mutates the captured `queueEntry.options` at lines ~562-587; if that entry has already moved or been removed, it can still resolve and bump session state.
- `PlayNextInQueue()` mutates the queue before playback is actually started. It removes/recycles entries, calls `RemoveMediaPlayer()`, then schedules `StartMediaPlayerForClient()` through `EnqueueSync()` at lines ~656-665 and ~701-720. `server/main.lua` drains that sync queue later in `syncMediaPlayers()` lines ~379-382.
- `server/main.lua` can also advance queue playback from the periodic sync loop when duration is reached: it calls `PlayNextInQueue(handle, { reason = "ended" })` at lines ~341-360. The client `pmms:ended` handler also calls `PlayNextInQueue()` at `server/media.lua` lines ~3201-3314, guarded only by an ended-event duplicate guard for client reports.
- `server/media.lua` adds queue entries from active playback requests at lines ~2913-2920, queues playlist tracks at lines ~3001-3027, handles manual next/previous/remove at lines ~4258-4288, and can seed session queues from incoming playback options at `AddMediaPlayer()` lines ~2370-2373.
- There is no per-device queue mutex or callback semaphore. `sessionLocks` in `server/media.lua` lines ~10 and ~329-537 are user access locks, not mutation serialization. `restrictedHandles` in `server/main.lua` lines ~284-291 blocks overlapping startup ownership, not queue changes.
- A version counter exists as `session.stateRevision`, but it is only incremented on commit and synced to clients. No server event requires an expected revision, no queue mutation rejects stale revisions, and no stale-rejection resync path exists.
- Race risk for C-FIX: FiveM is cooperative, so two Lua chunks do not run at the exact same instant, but async resolver callbacks and deferred `EnqueueSync()` playback can apply stale queue decisions after later queue edits unless queue mutations are serialized per handle and checked against a queue/session revision.

### D-ANALYZE
- Server sync payloads are built by `BuildMediaPlayersSyncStateForPlayer()` in `server/media.lua` lines ~534-612. They include `mediaPlayers`, `startupStates`, and `deviceSessions`, but no `_sentAt`, server timer, or sync timestamp field.
- Full and delta sync sends flow through `sendSyncToTarget()` in `server/main.lua` lines ~208-228, using `TriggerClientEvent` or `TriggerLatentClientEvent` based on encoded size. The send path does not stamp the payload immediately before dispatch.
- Joining/initializing clients receive state from two targeted paths: `pmms:loadPermissions` sends permissions and a full sync to the requesting source in `server/media.lua` lines ~4296-4304, and `playerJoining` sends a full sync to the joining source at lines ~4307-4314.
- `client/main.lua` applies full sync in `applyFullSyncPayload()` lines ~680-694 and delta sync in `applyDeltaSyncPayload()` lines ~696-717, then `reconcileSyncState()` records a snapshot for each active media player.
- Latency compensation is not applied from server send time. `updateSnapshot()` stores `info.offset` plus local `GetGameTimer()` receive time at `client/main.lua` lines ~470-476, and `getInterpolatedOffset()` advances from that local receive time at lines ~487-509. Without a server `_sentAt`, network/latent delivery delay is treated as if playback started when the client received the sync.
- There is lightweight offset interpolation, but no drift correction loop was found. The main client loop sends the computed `currentOffset` to the DUI browser at `client/main.lua` lines ~977-999, but neither `client/main.lua` nor `client/media.lua` compares browser current time against expected playback time or issues correction messages when drift exceeds a threshold.
- Playback creation in `client/media.lua` lines ~105-187 uses the synced options directly; startup attempts are marked ready from the main loop at `client/main.lua` lines ~966-968. No join-specific offset adjustment happens in `InitMediaPlayer()` or `StartMediaPlayerStartupAttempt()`.
- Resource restart recovery is partial. There is no `onClientResourceStart` handler in the client files; only `onResourceStop` cleanup exists at `client/main.lua` line ~1296. A startup `Citizen.CreateThread()` sends `pmms:loadSettings` and `pmms:loadPermissions` once at lines ~879-881, and `pmms:syncDelta` re-requests full state if a delta arrives before any full sync at lines ~804-810.
- Server playback offset is computed from `os.time()` seconds in `server/main.lua` lines ~341-347 and media start stores `startTime = os.time() - options.offset` in `server/media.lua` lines ~2382-2383, so existing sync precision is one second unless D-FIX adds a millisecond timer field.

### E-ANALYZE
- Discovery is primarily client-side polling. `client/entities.lua` scans `GetGamePool("CObject")` and optionally `GetGamePool("CVehicle")` in `GetMediaPlayerEntities()` lines ~14-90, caches entries in `entityCache`, and exposes sorted results through `GetEntityDistanceSorted()` lines ~102-120.
- Entity scan cache duration is fixed at `CACHE_DURATION = 2000` ms in `client/entities.lua` line ~6. The scan radius is `max(Config.maxDiscoveryDistance, Config.maxRange) + 10`, expanded by admin discovery range when staff controls set it, at lines ~22-32. Vehicle scan range is a fixed 50.0 when vehicle playback is enabled.
- `client/main.lua` has the playback/discovery loop at lines ~921-1255. The loop sleeps 1000ms normally, 240ms while the UI is open, and drops to 170ms when an active media player is within playback enter range at lines ~925 and ~951-953.
- UI device-list discovery is rebuilt only while the UI is open and only if at least 650ms elapsed since the last build, at `client/main.lua` lines ~1047-1055 and ~1192. It uses `GetEntityDistanceSorted()` for nearby entities, then supplements with audible active players, configured persistent devices, and admin devices.
- Selected-device awareness is limited to `ShowUi(selectedHandle, openView)` passing `selectedHandle` to NUI in `client/nui.lua` lines ~779-807. No selected handle is fed back into `client/entities.lua`, no cache TTL changes for a selected/open device, and no selected-device-specific scan path was found.
- Server push is limited to state/config events, not nearby discovery. `pmms:sync`/`pmms:syncDelta` update active state and linked speaker props, and `pmms:refreshPersistentEntities`/`pmms:loadSettings` refresh persistent props in `client/entities.lua` lines ~451-459. There is no server-pushed nearby list.
- Cache invalidation exists when settings load or admin discovery range changes: `client/main.lua` invalidates entities on `pmms:loadSettings` lines ~861-880, and `client/nui.lua` invalidates on `setAdminDiscoveryRange` lines ~224-230.
- No mass-join jitter was found. Startup sync requests immediately in `client/main.lua`, entity-cache expiry starts from first scan with a fixed 2000ms TTL, persistent entity refresh runs every 30000ms in `client/entities.lua` lines ~461-466, and no `math.random`/jitter is used in the discovery path.

### F-ANALYZE
- `server/database.lua` is mostly schema bootstrap plus known-player helpers. It loads and executes every statement from `pmms.sql` in `initDatabase()` lines ~101-126, then calls `ensureSchemas()` lines ~63-99 to add missing columns/tables/indexes for older installs.
- No `SELECT *` queries were found in `server/database.lua`; reads are `INFORMATION_SCHEMA` count checks and `SELECT display_name FROM pmms_known_players WHERE license = ?` at line ~194.
- Existing caching in `server/database.lua`: none. `GetKnownPlayerDisplayName()` checks live players first, then queries `pmms_known_players` every miss; persistent-device caching is not implemented in this file.
- `pmms_playlists` has primary key `id`, unique `(owner_license, id)`, and `idx_pmms_playlists_owner_favorite (owner_license, is_favorite, created_at)` in `pmms.sql` lines ~1-10. `ensureSchemas()` also backfills the same playlist indexes.
- `pmms_playlist_tracks` has primary key `id` and a foreign key on `playlist_id`, but no explicit covering index for `WHERE playlist_id = ? ORDER BY added_at ASC`. A useful missing index is `(playlist_id, added_at, id)`.
- `pmms_friends` has primary key `id` and unique `(user_license, friend_license)`, but no index for recipient/status lookups. Friend-request reads commonly need `friend_license` plus `status`, so a missing index is `(friend_license, status, created_at)`.
- `pmms_shared_playlists` has primary key `(playlist_id, shared_with_license)`, which helps playlist-owner lookups, but no reverse index for playlists shared with this player; a missing index is `(shared_with_license, playlist_id)`.
- `pmms_known_players`, `pmms_persistent_devices`, and `pmms_persistence_meta` all have primary keys for their direct lookup paths. `pmms_persistent_devices` also has a coordinate index `(x, y, z)`.
- `server/database.lua` ensures newer persistent tables exist, but persistent-device read/write behavior is outside this file; `server/persistence.lua` contains `SELECT x, y, z, data FROM pmms_persistent_devices ORDER BY updated_at ASC`, so F-FIX should read that file before deciding on a persistent-device cache.

### H-ANALYZE
- `server/resolver.lua` still has full embed fallback support. `isEmbedFallbackAllowed()` returns true when `Config.resolver.allowEmbedFallback` and `fallbackOnFailure` are true; `getProviderOrder()` appends `embed`; provider exhaustion and failed audio fallback create `provider = "embed"` / `instance = "youtube_embed"` payloads.
- `config/config.lua` currently enables `Config.resolver.allowEmbedFallback = true`, `fallbackOnFailure = true`, and also exposes an enabled `youtube_embed` search source, so normal YouTube playback can end up in YouTube IFrame API playback after all direct providers fail.
- `server/media.lua` maps `youtube`, `youtube_embed`, and `embed` provider values to `embed`; explicit non-auto provider choices disable embed fallback, but default Auto requests inherit the global config. Startup/local playback retries pass `allowEmbedFallback = resolverConfig.allowEmbedFallback == true` unless the specific failure was classified as `youtube_embed_blocked`.
- `http/dui_runtime/script.js` only creates the YouTube IFrame player when resolver metadata or explicit provider marks playback as embed. The repeated `web-share`, permissions-policy, and postMessage warnings are side effects of loading YouTube's iframe/widget scripts; the actual fatal path is `onError` 101/150 mapped to "Embedded YouTube playback is blocked by the video owner."
- Direct resolver streams are played through `<video>`/MediaElement/HLS.js. The `NotSupportedError` / media error code 4 path reports back through `pmms:startupError` or `pmms:localPlaybackError`, so H-FIX should keep retrying direct providers and then fail cleanly instead of selecting embed.
- `server/search.lua` normalizes thumbnails by accepting only absolute/protocol-relative URLs. Piped and some Invidious search responses can return relative thumbnail paths, so those are dropped; Piped results also do not extract/store `videoId`, removing the easiest fallback to `i.ytimg.com`.
- `nui/src/legacy/controller.js` renders search thumbnails as an unquoted CSS `background-image:url(...)` string. If the server sends a usable URL with query characters, this can still be fragile in NUI.
- Nearby devices are rendered by `renderDevicesGrid()` / `updateDevicesGridInPlace()` in `nui/src/legacy/controller.js`. It currently renders every usable device as a full `.device-card`; CSS uses a wrapping grid, so many nearby devices create multiple rows of cards and animated gradient overlays.
- The React shell in `nui/src/App.tsx` only supplies containers and static modals; the legacy controller owns search result rendering and device-card behavior. Built `ui/app.js` and `ui/style.css` are served by `fxmanifest.lua`, so source changes must be rebuilt into `ui/*`.

---

## Completed
<!-- ✅ H-FIX — 2026-05-22 -->
<!-- ✅ H-ANALYZE — 2026-05-22 -->
<!-- ✅ G — 2026-05-22 -->
<!-- ✅ F-FIX — 2026-05-22 -->
<!-- ✅ F-ANALYZE — 2026-05-22 -->
<!-- ✅ E-FIX — 2026-05-22 -->
<!-- ✅ E-ANALYZE — 2026-05-22 -->
<!-- ✅ D-FIX — 2026-05-22 -->
<!-- ✅ D-ANALYZE — 2026-05-22 -->
<!-- ✅ C-FIX — 2026-05-22 -->
<!-- ✅ C-ANALYZE — 2026-05-22 -->
<!-- ✅ B-FIX — 2026-05-22 -->
<!-- ✅ B-ANALYZE — 2026-05-22 -->
<!-- ✅ A-FIX — 2026-05-22 -->
<!-- ✅ A-ANALYZE — 2026-05-22 -->
<!-- ✅ TASK_ID — YYYY-MM-DD -->
