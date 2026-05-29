# 7-pmms

> Modern media player for FiveM with synced audio/video playback, playlists, queues, radio support, persistent devices, and a full React UI.

Originally based on PMMS by kibook, but heavily rewritten and expanded over time.

# Features

### Playback

- Synced audio and video playback between players
- Supports props, world positions, scaleforms, and compatible vehicles
- Queue system with autoplay, loop modes, previous/next, and history
- Runtime sessions that keep device state alive temporarily after playback stops
- Nearby discovery based on actual audible range
- Built-in equalizer with presets and custom profiles

### Sources

- YouTube
- SoundCloud
- Twitch
- Radio streams
- Direct media links
- HLS (`.m3u8`) support

### Resolver System

Supports multiple playback backends:

- hosted player page
- Cobalt
- Invidious
- Piped
- optional YouTube Embed fallback (disabled by default because owners can block embeds)

Includes caching, retries, failover handling, adaptive provider ranking, and concurrency limits.

### Playlists and Social

- Favorites
- Shared playlists
- Friend requests
- Playlist persistence with SQL storage
- Player suggestions/search

### Permissions and Admin Tools

- Device locking and request mode
- Persistent admin settings
- Staff/admin overrides
- Device profiles
- Linked speakers

# Installation

### Requirements

Required:

- `oxmysql`

Optional:

- `qb-core`
- `qb-target`
- `ox_target`

### Setup

Import `pmms.sql` into your database, then add:

```cfg
ensure oxmysql
...
ensure 7-pmms
```

---

# Configuration

Main config:

```txt
config/config.lua
```

Some important settings:

```lua
Config.maxDiscoveryDistance
Config.defaultRange
Config.maxRange

Config.deviceIdleResetSeconds

Config.directLinks
Config.resolver
Config.permissions
Config.searchSources
```

# YouTube and Resolver Setup

The default config works with the hosted player and public fallback providers. For better reliability at scale, use the hosted player plus a private or community Cobalt endpoint when available.

No local downloader or paid API key is required.

Default provider order:

```lua
Config.resolver.providerOrder = {
    "invidious",
    "piped",
    "page_scrape",
    "cobalt",
}
```

# Direct Links

Supported formats:

```txt
mp3
m4a
aac
mp4
webm
ogg
wav
m3u8
```

Direct links are validated before playback:

- malformed URLs rejected
- optional HTTPS-only mode
- media probing
- redirect validation
- unsupported formats blocked

HLS playback is handled through the bundled `hls.js` runtime.

---

# Permissions

Default mode:

```lua
Config.permissions.mode = "hybrid"
```

Supports:

- QBCore admin groups
- ACE fallbacks

Example:

```lua
Config.permissions.qbcore.adminPermissions = {
    "god",
    "admin"
}
```

Admins can override devices, bypass locks, approve requests, manage hidden devices, linked speakers, and persistent settings.

# NUI Development

The UI is built with:

- React
- TypeScript
- Vite

Commands:

```sh
npm run dev
npm run check
npm run build
```

Production files are generated into:

```txt
ui/
```

# Commands

Default commands:

```txt
/pmms
/pmms_play
/pmms_pause
/pmms_stop
/pmms_status
/pmms_vol
/pmms_fix
/pmms_ctl
/pmms_add
/pmmsperf
```

# Exports

### Playback

```lua
exports["7-pmms"]:startByNetworkId(handle, options)
exports["7-pmms"]:startByCoords(x, y, z, options)
exports["7-pmms"]:startScaleform(scaleform, options)

exports["7-pmms"]:stop(handle)
exports["7-pmms"]:pause(handle)

exports["7-pmms"]:lock(handle)
exports["7-pmms"]:unlock(handle)
```

### Persistence

```lua
exports["7-pmms"]:addModel(model, data)
exports["7-pmms"]:addEntity(coords, data)

exports["7-pmms"]:removeModel(model)
exports["7-pmms"]:removeEntity(coords)
```

### Resolver

```lua
exports["7-pmms"]:SearchYouTube(query, callback)
exports["7-pmms"]:SearchMedia(query, source, callback)
```

# Limitations

- Runtime sessions are temporary
- Playback depends on browser-compatible codecs
- Public providers can fail/rate-limit
- Some YouTube/Twitch content may not be playable depending on the resolver used

# Credits

- Original PMMS project -> kibook
- Rework and expansion -> arobase7sur7
