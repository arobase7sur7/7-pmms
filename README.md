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
- `m4a`
- `aac`
- `mp4`
- `m4v`
- `webm`
- `ogg`
- `ogv`
- `oga`
- `wav`
- `m3u8`

Direct-link validation rules:

- HTTPS only when `Config.directLinks.requireHttps = true`
- absolute URL required
- no embedded credentials
- no malformed or suspicious URLs
- no webpage-style or extensionless URLs in the direct-link path
- no redirects or non-media probe responses
- no unsupported formats such as `mov`, `flv`, `mpeg`, `mid`, or `midi`

Provider page URLs without file-like media extensions stay on the resolver path instead of being treated as direct links.
Proxy-style URLs with a nested `url`, `u`, `src`, `source`, `media`, `stream`, or `target` query parameter are unwrapped only when the nested value is itself a safe supported direct media URL.
HLS (`.m3u8`) playback uses the bundled `hls.js` DUI runtime, so server owners do not need to install a browser plugin for direct HLS links.
For HLS, the playlist and segment hosts still need to be reachable by the FiveM browser and expose browser-friendly CORS headers. Alternate audio tracks exposed by the manifest are synced back to the NUI and can be selected from the now-playing panel.
For best DUI compatibility, HLS video should expose browser-decodable H.264/AAC variants at practical RP screen sizes. Very high resolution, HDR, DRM, or unusual codec playlists can load metadata but fail or show black in FiveM's embedded Chromium.
High-resolution HLS is attempted instead of rejected. When `Config.dui.hlsCanvasDownscale = true`, DUI can draw decoded oversized video through a capped canvas layer:

```lua
Config.dui.hlsCanvasDownscale = true
Config.dui.hlsCanvasMaxWidth = 1920
Config.dui.hlsCanvasMaxHeight = 1080
Config.dui.hlsCanvasMaxFps = 30
```

This only downscales video that FiveM CEF can already decode. It cannot transcode HEVC/HDR/DRM streams into H.264/AAC.

## Radio Source

The NUI includes a `Radio` source when `Config.searchSources.radio.enabled = true`.

- Search supports station name, country, language, and genre/tag lookups through the public Radio Browser API.
- Pasted radio stream URLs are accepted as live audio streams when they pass the same safety/probe checks as other direct links.
- Radio streams are treated as `LIVE`: no duration, no seek bar control, and no automatic end event.
- Favorite radio stations are saved locally in the player's browser storage.
- Radio stations added to playlists store metadata in `pmms_playlist_tracks.metadata` so they remain audio/live streams when replayed later.

Radio streams still need to be playable by FiveM CEF. If a station uses an unsupported codec or blocks browser playback, the resource will fail it like any other direct media source.

## Requirements

- FiveM server with `fx_version "cerulean"` and GTA V
- `oxmysql`
- outbound HTTP access for search, resolver fallback, and direct-link probing

Optional integrations:

- `qb-target`
- `ox_target`
- `qb-core` for optional QBCore permission mode
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
- `Config.resolver.retryAttempts = 4`
- `Config.resolver.audioLanguagePriority = { "original", "en", "en-US", "und" }`

The default resolver chain treats only ad-free direct streams as successful playback sources: local `yt-dlp`, configured extractor HTTP endpoints, optional Cobalt API endpoints, Invidious, Piped, then audio-only fallback. Embedded YouTube fallback is opt-in with `allowEmbedFallback = true`; when no ad-free source is found, playback fails cleanly instead of staying in a fallback loading state.
In the NUI, the YouTube source has a provider selector. `Auto` uses the ad-free resolver chain. Selecting `YouTube Embed` is an explicit per-play opt-in and can show ads, so it is not used by default.

### Beginner YouTube Provider Guide

If you see this warning:

```text
Resolver preflight: local yt-dlp probe could not spawn any candidate command from the FXServer environment. No Cobalt endpoint is configured, so YouTube playback will depend on public Invidious/Piped instances and may fail.
```

The resource still started correctly. It only means YouTube reliability depends on public fallback providers until you configure one stronger resolver.

Recommended setup ladder:

1. Default/noob setup: start the resource with the default config. Public Invidious and Piped instances are free and already listed, but they are community services and can randomly rate-limit, go offline, return CORS-hostile URLs, or fail for some videos.
2. Better setup: install `yt-dlp` on the same machine/user that starts FXServer. This is free and usually the easiest reliable ad-free option for a self-hosted server.
3. Best setup: run your own trusted extractor HTTP service or Cobalt instance and point `7-pmms` at it. This is still free software, but you host it yourself.

Provider order is configured here:

```lua
Config.resolver.extractor.providerOrder = {
    "yt_dlp_local",
    "extractor_http",
    "cobalt",
    "invidious",
    "piped",
}
```

Auto mode can also learn from successful playback starts across all players:

```lua
Config.resolver.adaptiveProviderRanking = {
    enabled = true,
    minCompletedPlays = 8,
    minProviderSamples = 2,
    dataFile = "data/provider_stats.json",
    saveDebounceMs = 5000,
}
```

This only affects automatic provider selection. If a player forces `yt-dlp`, Cobalt, Piped, Invidious, or Embed from the NUI, that forced choice is respected and is not used for ranking. Use `/pmmsproviders` or `/pmms_providers` to see the current provider top.

#### Local yt-dlp

Install `yt-dlp` where the FXServer process can run it, then test one of these commands in the same terminal/user that starts FXServer:

```sh
yt-dlp --version
python -m yt_dlp --version
py -m yt_dlp --version
```

If none of those works, `spawn_failed` is expected. It means FXServer could not start that command from its environment. On Windows, an explicit path is often the clearest fix:

```lua
Config.resolver.extractor.ytDlpPath = "C:/tools/yt-dlp.exe"
```

You can also change the command list:

```lua
Config.resolver.extractor.ytDlpCommand = {
    "C:/tools/yt-dlp.exe",
    "python -m yt_dlp",
    "py -m yt_dlp",
}
```

On Linux, add the command that works on your host:

```lua
Config.resolver.extractor.ytDlpCommand = {
    "yt-dlp",
    "python3 -m yt_dlp",
    "python -m yt_dlp",
}
```

#### Extractor HTTP

Use this only if you run or trust an HTTP resolver service. `7-pmms` sends a `POST` request with JSON like `{ url, mode, avoidResolvedUrl, source }`. The service should return JSON containing one of `playableUrl`, `url`, or `streamUrl`, plus optional `title`, `author`, `duration`, and `thumbnail`.

```lua
Config.resolver.extractor.httpEndpoints = {
    "https://your-resolver.example.com/api/resolve",
}
```

Do not add random public endpoints here unless you trust them. They receive the URLs your players request.

#### Cobalt

Cobalt is an optional media downloader API. For production, use a self-hosted or trusted private Cobalt API root.

```lua
Config.resolver.cobalt.endpoints = {
    "https://your-cobalt-instance.example.com",
}
Config.resolver.cobalt.apiKey = "your-secret-key"
Config.resolver.cobalt.apiKeyHeader = "Authorization"
Config.resolver.cobalt.apiKeyPrefix = "Api-Key"
```

With the default header settings, `7-pmms` sends:

```text
Authorization: Api-Key your-secret-key
```

Keep Cobalt output browser-friendly for FiveM DUI:

```lua
Config.resolver.cobalt.alwaysProxy = true
Config.resolver.cobalt.videoQuality = "720"
Config.resolver.cobalt.youtubeVideoCodec = "h264"
Config.resolver.cobalt.youtubeVideoContainer = "mp4"
```

#### Invidious and Piped

These are free public fallback providers. They are useful for a plug-and-play public resource, but they are not guaranteed. Keep multiple instances so one failing host does not break every play request:

```lua
Config.resolver.instances.invidious = {
    "https://inv.nadeko.net",
    "https://yewtu.be",
    "https://invidious.nerdvpn.de",
}

Config.resolver.instances.piped = {
    "https://api.piped.private.coffee",
    "https://pipedapi.kavin.rocks",
    "https://api-piped.mha.fi",
}
```

The resolver temporarily skips failing instances so it does not retry the same broken host immediately:

```lua
Config.resolver.instanceFailureCooldownSeconds = 600
```

#### YouTube Embed

YouTube Embed is available only when you explicitly opt in. It may show ads and is not recommended as the default RP mode.
The embed path uses the YouTube IFrame API instead of loading a `/watch` page as a normal media URL. This makes explicit embed playback cleaner, but it still depends on YouTube allowing the video to be embedded and it does not expose alternate audio tracks to `7-pmms`.

```lua
Config.resolver.allowEmbedFallback = false
```

If you intentionally allow it:

```lua
Config.resolver.allowEmbedFallback = true
```

Server owners and players still have to select/allow the embed provider intentionally. `Auto` stays on the ad-free resolver chain first.

If the preflight warning says every candidate `spawn_failed`, the resource is starting normally but FXServer could not create a child process for those commands from its runtime environment. On hosted or restricted FXServer setups, use `Config.resolver.extractor.httpEndpoints` or `Config.resolver.cobalt.endpoints` instead of local extraction.

A YouTube Data API key alone cannot provide direct playable media streams. Scripts that "just work" with YouTube usually rely on embedded playback, a downloader service, or a local extractor.

Debug logging is controlled by `Config.debug`. Set `Config.debug.enabled = true`, then enable the categories you need, such as `player`, `resolver`, `favorites`, `dui`, or `nui`; set `all = true` only when you want very noisy diagnostics.

The bundled search UI supports the configured sources in `Config.searchSources`. The default configuration includes YouTube, SoundCloud, Twitch, and Direct for pasted media links.

### Admin Devices, Requests, And Speakers

Normal players can use public devices without ACE/QBCore permissions. Permissions now gate staff/admin tools only.

Admin/staff additions:

- Staff quick actions appear inside Device Settings only for staff/admins.
- The Admin Panel tab appears only for `pmms.manage`.
- Admins bypass session/admin locks and can manage known devices even when normal discovery would hide them.
- Device profiles are configured in `Config.deviceProfiles` and can be applied without permanently locking the device.
- Persistent admin locks, request mode, names, range, volume, and linked speakers can be saved on persistent devices.
- Pending requests are controlled by `Config.requests`.
- Linked speakers are controlled by `Config.speakers`; they extend the original device audio without creating a second playback source.
- The optional mini HUD can be toggled by players and stores its preference with `pmms_hud_enabled`.

### Production Smoothness

`Config.ui.maxHistorySyncItems` limits how many recent history rows are sent to each NUI refresh. The full per-device history count stays server-side, but only the newest rows are rendered to keep repeated open/close and long sessions smooth.

`Config.dui.renderMaxFps`, `Config.dui.renderIdleFps`, `Config.dui.renderDistanceBuffer`, and `Config.dui.cacheRuntimeAssets` control DUI draw cost. The defaults render visible screens at a capped rate and keep hidden/out-of-range browsers from doing per-frame texture work.

Resolver provider stats are live operational data. The resource creates/updates `data/provider_stats.json` locally; public releases should ship `data/provider_stats.example.json` and let each server build its own stats.

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

Optional QBCore permissions are available, but ACE stays the default for backwards compatibility. To use QBCore, set `Config.permissions.mode = "qbcore"` or `"hybrid"` and enable `Config.permissions.qbcore.enabled`. QBCore permission names are configured in `Config.permissions.qbcore.permissionMap`; job and gang grade rules can be added under `Config.permissions.qbcore.jobs` and `Config.permissions.qbcore.gangs`.

Example:

```lua
Config.permissions.mode = "hybrid"
Config.permissions.qbcore.enabled = true
Config.permissions.qbcore.jobs = {
    manage = { police = 4 },
}
```

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
- `/pmmsperf`

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
