# Browser YouTube Provider

7-PMMS uses a browser-based YouTube provider by default. The FiveM server does not download, transcode, cache, or re-stream YouTube media. Each client plays YouTube directly inside Chromium/DUI, while the server only synchronizes media state.

## User Setup

No extra setup is required for public releases:

- no local downloader
- no ffmpeg
- no Python
- no Cobalt or extractor server
- no media cache
- no executable path configuration

Install the resource like a normal FiveM script.

## Runtime Architecture

The server synchronizes:

- play, pause, stop
- seek position
- volume and device state
- playback tokens and revisions
- queue/session state

The client browser handles:

- YouTube URL playback
- youtu.be links
- autoplay attempts
- pause/resume/seek commands
- DUI rendering on world screens
- cleanup when the media object/resource stops

## Provider Notes

The default provider is `chromium_youtube`, backed by the YouTube IFrame Player API in the DUI runtime.

Server-side extractors remain disabled by default and are intended only for development or private forks. They are not part of the default public user experience.

The browser provider now waits for a real playable state before reporting startup success. It also performs one bounded client-side host retry between `youtube-nocookie.com` and `youtube.com` for retryable iframe/API failures. Owner-blocked embeds are treated as final failures and are not retried in a loop.

## Why YouTube Fails In DUI

Common failure causes:

- `101` / `150`: the owner has disabled embedded playback. The official player is required to honor this.
- `153`: YouTube rejected the embed because the request did not include an accepted identity/referrer. A real HTTPS origin can help here.
- `5`: the Chromium HTML5 player failed to decode or initialize the media.
- CEF autoplay: FiveM DUI behaves like a browser surface, so playback must start muted and be unmuted after the server volume loop takes over.
- Timing: reporting success on iframe `onReady` is too early; the runtime waits for `PLAYING` or an explicitly paused ready state.
- Host quirks: `youtube-nocookie.com` and `youtube.com` can behave differently, so the runtime tries both once.

## Optional HTTPS Player Page

For servers that want the most stable origin/referrer behavior, host:

```text
web/youtube-player/player.html
```

on a real HTTPS domain such as GitHub Pages, Cloudflare Pages, Vercel, or a normal static web host. Then set:

```lua
Config.dui.youtube.externalPlayerUrl = "https://your-domain.example/player.html"
```

When `externalPlayerUrl` is set, the hosted player becomes the primary YouTube path by default. Set `Config.dui.youtube.preferExternalPlayer = false` only if you want the local DUI runtime to try first and use the hosted page as a fallback.

The normal DUI wrapper still owns `CreateDui`, `SendDuiMessage`, `DestroyDui`, queue sync, volume, pause, seek, and cleanup. The hosted page only runs the YouTube player inside a stable HTTPS origin and communicates with the DUI wrapper through `postMessage`.

Optional public front-end fallback can be enabled for non-policy failures:

```lua
Config.dui.youtube.allowFrontendFallback = true
Config.dui.youtube.frontendInstances = {
    { type = "invidious", url = "https://yewtu.be" },
    { type = "invidious", url = "https://inv.nadeko.net" },
    { type = "piped", url = "https://piped.video" },
}
```

This is intentionally off by default. Public front-ends are best-effort, may rate-limit, and do not provide the same reliable playback control API as the official player. They are not used for `101` / `150` owner-disabled embed errors.

The hosted player rotates generated candidates per instance:

- Invidious: `/embed/{videoId}?autoplay=1&local=true&quality=dash&thin_mode=true&start={start}`
- Invidious: `/watch?v={videoId}&autoplay=1&local=true&quality=dash&thin_mode=true&start={start}`
- Piped: `/watch?v={videoId}&playerAutoPlay=true&autoplay=true&quality=720&start={start}`

Advanced users can provide a custom template:

```lua
Config.dui.youtube.frontendInstances = {
    {
        type = "custom",
        url = "https://video.example.com",
        template = "https://video.example.com/watch?v={videoId}&autoplay=1&start={start}",
    },
}
```

Templates support `{origin}`, `{videoId}`, and `{start}`.

## DUI Lua Integration

The production integration is split across existing files instead of adding a second client script:

- [client/dui.lua](client/dui.lua) owns `CreateDui`, `SendDuiMessage`, and `DestroyDui`.
- [client/media.lua](client/media.lua) ensures only one active browser exists per media handle.
- [http/dui_runtime/script.js](http/dui_runtime/script.js) receives startup/update messages, creates the YouTube/Twitch/player element, and reports ready/error/metadata back through NUI callbacks.
- [web/youtube-player/player.html](web/youtube-player/player.html) is the complete hosted-player implementation.

Core lifecycle:

```lua
-- client/media.lua
local browser = DuiBrowser:new(handle, model, renderTarget, options.scaleform, getLocalDuiUrl(), options, width, height, Config.dui.timeout)
browser:sendMessage({
    type = "startup",
    handle = handle,
    attemptId = startupAttemptId,
    playbackToken = playbackToken,
    startupTimeoutMs = startupTimeoutMs,
    options = options,
})

-- client/dui.lua
self.duiObject = CreateDui(fullUrl, math.floor(self.w), math.floor(self.h))
self.duiHandle = GetDuiHandle(self.duiObject)
SendDuiMessage(self.duiObject, json.encode(data))
DestroyDui(self.duiObject)
```

## File Structure

```text
http/dui_runtime/index.html       # DUI runtime shell
http/dui_runtime/script.js        # provider control, sync, YouTube/Twitch handling
http/dui_runtime/style.css        # full-screen DUI rendering
web/youtube-player/player.html    # optional hosted HTTPS YouTube player
client/dui.lua                    # CreateDui / SendDuiMessage / DestroyDui lifecycle
client/media.lua                  # one active DUI browser per media object
server/resolver.lua               # chromium_youtube provider selection
```

## Hosting Steps

1. Upload `web/youtube-player/player.html` to a static HTTPS host.
2. Open the hosted URL in a normal browser and confirm it loads.
3. Set `Config.dui.youtube.externalPlayerUrl`.
4. Restart the resource.
5. Test a normal YouTube URL, pause/resume, seek, reconnect, and resource restart.

## Practical Compatibility Notes

These are the non-invasive tricks used by the current implementation:

- Start muted, then let the normal PMMS volume loop unmute once playback is alive and in range.
- Use `playsinline=1`, `enablejsapi=1`, `origin`, and `widget_referrer`.
- Try both `youtube-nocookie.com` and `youtube.com`.
- Treat `onReady` as API readiness only; report server startup success on actual playback/paused-ready state.
- Use one player per media handle and destroy stale players before replacement.
- Rotate optional public front-end candidates with bounded timeouts instead of waiting on one slow instance.
- Include typed front-end templates so admins can plug in reliable Invidious/Piped/self-hosted front-ends.

Optional maximum-compatibility server-side approach:

- Run a private resolver/proxy such as Cobalt, Piped, or Invidious on infrastructure you control.
- Keep it optional and documented; do not require it for normal public-resource users.
- Do not make the FiveM server download, transcode, or cache full media files.

## YouTube Limitations

The official browser player must respect YouTube embed policy. If YouTube returns error `101` or `150`, the video owner has disabled embedded playback. A fully client-side, zero-setup provider cannot bypass that restriction without leaving the official browser-player architecture, so 7-PMMS fails cleanly and keeps the server lightweight instead of falling back to server downloads.
