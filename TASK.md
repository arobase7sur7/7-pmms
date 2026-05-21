# 7-pmms Backend — Task Tracker

## Current Task
**B-ANALYZE** — Read server/resolver.lua + how it's called from server/main.lua or server/media.lua; document resolver behavior

## Backlog

### Sync (Problem 1)
- [x] A-ANALYZE — Read `server/main.lua` + `server/media.lua`. Find: sync loop location, broadcast frequency, payload size, whether dirty flags exist, how joining players receive state. Write findings below.
- [x] A-FIX     — Implement sync fixes based on A-ANALYZE findings: throttle, delta, TriggerLatentClientEvent for large payloads, targeted join sync, periodic full resync

### Resolver (Problem 2)
- [ ] B-ANALYZE — Read `server/resolver.lua` + how it's called from `server/main.lua` or `server/media.lua`. Find: deduplication (yes/no), per-provider concurrency limits (yes/no), timeouts (yes/no), failover mechanism, how result is returned. Write findings below.
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
<!-- Fill in after reading the files -->

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
<!-- ✅ A-FIX — 2026-05-22 -->
<!-- ✅ A-ANALYZE — 2026-05-22 -->
<!-- ✅ TASK_ID — YYYY-MM-DD -->
