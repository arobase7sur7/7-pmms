# 7-pmms Backend — Task Tracker

## Current Task
**B-FIX** — Implement resolver fixes based on B-ANALYZE findings

## Backlog

### Sync (Problem 1)
- [x] A-ANALYZE — Read `server/main.lua` + `server/media.lua`. Find: sync loop location, broadcast frequency, payload size, whether dirty flags exist, how joining players receive state. Write findings below.
- [x] A-FIX     — Implement sync fixes based on A-ANALYZE findings: throttle, delta, TriggerLatentClientEvent for large payloads, targeted join sync, periodic full resync

### Resolver (Problem 2)
- [x] B-ANALYZE — Read `server/resolver.lua` + how it's called from `server/main.lua` or `server/media.lua`. Find: deduplication (yes/no), per-provider concurrency limits (yes/no), timeouts (yes/no), failover mechanism, how result is returned. Write findings below.
- [ ] B-FIX     — Implement resolver fixes based on B-ANALYZE findings: dedup, semaphores, per-provider timeouts, adaptive ban, hedged failover, absolute timeout, progress events, cancel handler

### Queue / Race Conditions (Problem 3)
- [ ] C-ANALYZE — Read `server/queue.lua` + `server/main.lua` + `server/media.lua`. Find: how queue is stored, what functions mutate it, whether any locking exists, whether version/optimistic locking exists. Write findings below.
- [ ] C-FIX     — Implement queue fixes based on C-ANALYZE findings: per-device mutex, version counter, stale-rejection with resync

### Join Sync (Problem 4)
- [ ] D-ANALYZE — Read `client/main.lua` + `client/media.lua` + how server sends state on join. Find: is latency compensation applied (yes/no), is there a drift correction loop (yes/no), does `onClientResourceStart` re-request state (yes/no). Write findings below.
- [ ] D-FIX     — Implement join sync fixes based on D-ANALYZE findings: _sentAt timestamp, client-side latency compensation, drift correction loop, resource restart recovery

### Discovery (Problem 5)
- [ ] E-ANALYZE — Read `client/entities.lua` + `client/main.lua`. Find: discovery mechanism (poll/push/both), poll interval, whether interval adapts when device is selected, whether mass-join jitter exists. Write findings below.
- [ ] E-FIX     — Implement discovery fixes based on E-ANALYZE findings: adaptive interval, join jitter, optionally server-push nearby list

### Database (Problem 6)
- [ ] F-ANALYZE — Read `server/database.lua` + `pmms.sql`. Find: missing indexes, SELECT * queries, any existing caching. Write findings below.
- [ ] F-FIX     — Add missing indexes to pmms.sql; fix SELECT * in database.lua; add persistent device cache if warranted

### Config
- [ ] G         — Read `config/config.lua` in full. Add only the Config keys from PLAN_BACKEND.md that don't already exist.

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
<!-- Fill in after reading the files -->

### D-ANALYZE
<!-- Fill in after reading the files -->

### E-ANALYZE
<!-- Fill in after reading the files -->

### F-ANALYZE
<!-- Fill in after reading the files -->

---

## Completed
<!-- ✅ B-ANALYZE — 2026-05-22 -->
<!-- ✅ A-FIX — 2026-05-22 -->
<!-- ✅ A-ANALYZE — 2026-05-22 -->
<!-- ✅ TASK_ID — YYYY-MM-DD -->
