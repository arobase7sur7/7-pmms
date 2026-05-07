# 7-pmms

`7-pmms` is a synchronized in-world media player for FiveM. It supports shared playback on props, saved world positions, scaleforms, and compatible vehicles, with server-authoritative playback state, per-device runtime sessions, playlists, favorites, queueing, history, social sharing, and configurable permissions.

This project started from PMMS by kibook and has been heavily reworked.

## Features

- Shared audio and video playback across clients.
- Device discovery for supported props, saved positions, scaleforms, and compatible vehicles.
- Queue, autoplay, loop modes, manual previous/next, and per-device temporary playback history.
- Runtime device sessions that keep settings, range, queue, history, and lock state alive after playback stops, then reset automatically after an idle timeout.
- Audible nearby visibility, so a device can stay in the nearby list while it is still actually hearable from its configured range.
- Playlist library with favorites, shared playlists, friend requests, and player suggestions backed by SQL.
- Secure direct-link validation for a conservative set of browser-playable media formats.
- Resolver caching, inflight dedupe, bounded provider concurrency, and controlled retry behavior.
- Admin persistence for model defaults and saved world-position defaults.

## Playback Model

The resource is built around server-authoritative shared state.

- The server owns active device playback, queue state, history state, runtime settings, reset timers, lock state, and playlist persistence.
- Clients render the current authoritative state and may use short-lived optimistic overlays for UI responsiveness.
- Manual `previous` and `next` switch immediately.
- Automatic progression can still use transition timing, but playback remains single-source per device. The DUI does not keep two live sources running for the same handle during a handoff.

## Runtime Device Sessions

Devices do not reset immediately when playback stops.

- `Config.deviceIdleResetSeconds` controls the idle reset window.
- The default reset window is `300` seconds.
- During the idle window, runtime settings remain active, including range, volume, attenuation, mute state, transition setting, queue, history, and session lock state.
- The UI exposes the pending reset countdown.
- Starting playback again before the timer expires cancels the pending reset and keeps the session alive.
- When the timer expires, the temporary session is cleared and the device returns to its configured defaults.

Runtime sessions are temporary. They are not durable persistence across resource restarts or full server restarts.

## Nearby Visibility

Nearby discovery still uses `Config.maxDiscoveryDistance`, but active audibility can extend visibility for a specific device.

- If a player can still hear a device because they are inside that device's effective range, that device remains visible in the nearby list.
- This is device-specific and does not increase the global discovery radius.
- When playback stops, becomes inaudible, or the runtime session resets, visibility returns to normal nearby rules.

## Queue, History, and Manual Controls

- Queue and history are separate.
- Confirmed playback is written into per-device runtime history.
- History survives until the device session resets.
- Manual `previous` reads from that runtime history.
- Manual `previous` and `next` bypass transition timing.
- Automatic end-of-track progression can still use the configured transition length.

## Direct Links

Direct links are accepted only when they are both safe and realistically playable by the DUI/browser stack.

Supported direct-link extensions:

- `mp3`
- `mp4`
- `m4v`
- `webm`
- `ogg`
- `ogv`
- `oga`
- `wav`

Direct-link validation rules:

- HTTPS only when `Config.directLinks.requireHttps = true`
- absolute URL required
- no embedded credentials
- no malformed or suspicious URLs
- no webpage-style or extensionless URLs in the direct-link path
- no redirects or non-media probe responses
- no unsupported formats such as `mov`, `flv`, `mpeg`, `mid`, or `midi`

Provider page URLs without file-like media extensions stay on the resolver path instead of being treated as direct links.

## Requirements

- FiveM server with `fx_version "cerulean"` and GTA V
- `oxmysql`
- outbound HTTP access for search, resolver fallback, and direct-link probing

Optional integrations:

- `qb-target`
- `ox_target`
- a local `yt-dlp` install for local extractor fallback

## NUI Development

The in-game interface is authored in `nui/` as a React + TypeScript app and built with Vite into the FiveM runtime files in `ui/`.

- `npm run dev` starts a local preview with mocked FiveM data.
- `npm run check` runs TypeScript validation.
- `npm run build` regenerates `ui/index.html`, `ui/app.js`, and `ui/style.css`.

FiveM still loads `ui/index.html`; the Node toolchain is only for building the browser assets.

## Installation

1. Place `7-pmms` in your server `resources` directory.
2. Import `pmms.sql` into your database.
3. Add `ensure oxmysql` before this resource in `server.cfg`.
4. Add `exec @7-pmms/config/permissions.cfg` to `server.cfg`.
5. Add `ensure 7-pmms` to `server.cfg`.

## Configuration

Main configuration lives in `config/config.lua`.

Important options:

- `Config.maxDiscoveryDistance`
- `Config.defaultRange`
- `Config.maxRange`
- `Config.deviceIdleResetSeconds`
- `Config.defaultTransitionSeconds`
- `Config.maxTransitionSeconds`
- `Config.directLinks`
- `Config.resolver`
- `Config.searchSources`
- `Config.playlists`
- `Config.targeting`

Important resolver defaults:

- `Config.resolver.allowAudioFallback = true`
- `Config.resolver.allowEmbedFallback = false`
- `Config.resolver.warnOnFallback = false`
- `Config.resolver.retryOnPlaybackError = true`
- `Config.resolver.retryAttempts = 1`

The default resolver chain treats only ad-free direct streams as successful playback sources: local `yt-dlp`, configured extractor HTTP endpoints, optional Cobalt API endpoints, Invidious, Piped, then audio-only fallback. Embedded YouTube fallback is opt-in with `allowEmbedFallback = true`; when no ad-free source is found, playback fails cleanly instead of staying in a fallback loading state.

If your server runtime cannot spawn `yt-dlp`, configure `Config.resolver.cobalt.endpoints` with a self-hosted or trusted private Cobalt API root. Protected instances can use `Config.resolver.cobalt.apiKey`, which is sent as `Authorization: Api-Key <key>` by default. A YouTube Data API key alone cannot provide direct playable media streams; scripts that “just work” with YouTube usually rely on embedded playback, a downloader service, or a local extractor.

Debug logging is controlled by `Config.debug`. Set `Config.debug.enabled = true`, then enable the categories you need, such as `player`, `resolver`, `favorites`, `dui`, or `nui`; set `all = true` only when you want very noisy diagnostics.

The bundled search UI supports the configured sources in `Config.searchSources`. The default configuration includes YouTube, SoundCloud, and Twitch.

## Persistent vs Temporary State

There are two different kinds of device state:

- persistent defaults: model defaults and saved world-position defaults
- temporary runtime state: live playback, queue, history, session locks, and per-device overrides that last until idle reset

Persistent defaults are stored in:

- `models.json`
- `defaultMediaPlayers.json`

## Permissions

The default ACE rules live in `config/permissions.cfg`.

Common ACE permissions:

- `pmms.interact`
- `pmms.anyEntity`
- `pmms.customUrl`
- `pmms.anyUrl`
- `pmms.manage`

Review the bundled defaults before using them in production.

## Commands

With the default command settings:

- `/pmms`
- `/pmms_play`
- `/pmms_pause`
- `/pmms_stop`
- `/pmms_status`
- `/pmms_presets`
- `/pmms_vol`
- `/pmms_fix`
- `/pmms_ctl`
- `/pmms_add`
- `/pmms_refresh_perms`

These names depend on `Config.commandPrefix` and `Config.commandSeparator`.

## Exports

Media exports:

- `exports["7-pmms"]:startByNetworkId(handle, options)`
- `exports["7-pmms"]:startByCoords(x, y, z, options)`
- `exports["7-pmms"]:startScaleform(scaleform, options)`
- `exports["7-pmms"]:stop(handle)`
- `exports["7-pmms"]:pause(handle)`
- `exports["7-pmms"]:lock(handle)`
- `exports["7-pmms"]:unlock(handle)`
- `exports["7-pmms"]:mute(handle)`
- `exports["7-pmms"]:unmute(handle)`
- `exports["7-pmms"]:getMediaPlayerInfo(handle)`
- `exports["7-pmms"]:getAllMediaPlayers()`

Persistence exports:

- `exports["7-pmms"]:addModel(model, data)`
- `exports["7-pmms"]:addModelPermanently(model, data)`
- `exports["7-pmms"]:addEntity(coords, data)`
- `exports["7-pmms"]:addEntityPermanently(coords, data)`
- `exports["7-pmms"]:removeModel(model)`
- `exports["7-pmms"]:removeModelPermanently(model)`
- `exports["7-pmms"]:removeEntity(coords)`
- `exports["7-pmms"]:removeEntityPermanently(coords)`

Search and resolver exports:

- `exports["7-pmms"]:SearchYouTube(query, callback)`
- `exports["7-pmms"]:SearchMedia(query, source, callback)`
- `exports["7-pmms"]:resolvePlaybackOptions(options, resolverOptions, callback)`

## Limitations

- Runtime sessions are temporary and are cleared on idle reset.
- Direct-link support is limited to formats that are reliably playable by the DUI/browser pipeline.
- Search and resolution still depend on outbound HTTP access and third-party endpoints.
- YouTube and Twitch playback quality depends on your configured resolver sources and extractor availability.

## Credits

- Original PMMS concept and base work: kibook
- Rework and expansion: arobase7sur7
