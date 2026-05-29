# Hosted DUI Runtime Deploy Guide

The hosted URL must serve the full DUI runtime from `http/dui_runtime/`. Do not deploy `player/dist/` for production playback.

## What To Publish

Publish these files as a static HTTPS site:

```text
http/dui_runtime/index.html
http/dui_runtime/style.css
http/dui_runtime/script.js
http/dui_runtime/hls.min.js
http/dui_runtime/loading.svg
http/dui_runtime/mediaelement.min.js
http/dui_runtime/mediaelementplayer.min.css
http/dui_runtime/dailymotion.min.js
http/dui_runtime/twitch.min.js
http/dui_runtime/vimeo.min.js
http/dui_runtime/wave.js
```

The published root should open `index.html`, for example:

```text
https://arobase7sur7.github.io/7-pmms-dui/
```

## Configure 7-PMMS

Set the hosted DUI URL in `config/config.lua`:

```lua
Config.dui = {
    urls = {
        https = "https://your-hosted-dui.example.com/",
    },
}
```

The older alias still works:

```lua
Config.player = {
    hostedPlayerUrl = "https://your-hosted-dui.example.com/",
    useHostedPlayer = true,
}
```

`Config.dui.urls.https` wins when both are set.

## Verify

1. Open the hosted URL in a browser and confirm `script.js`, `style.css`, and the vendor files load.
2. Restart `7-pmms`.
3. Play a YouTube URL with provider mode `Hosted`.
4. Confirm the DUI screen leaves the loader only after real playback starts.
5. Play a direct HLS, MP4, MP3, or radio URL and confirm it stays on the local direct path.

## Notes

The hosted page is controlled by the FiveM DUI callback bridge, so a black page in a normal browser is expected.

The static host must allow iframe usage and must not send `X-Frame-Options: DENY`, `X-Frame-Options: SAMEORIGIN`, or a `Content-Security-Policy` `frame-ancestors` rule that blocks FiveM.
