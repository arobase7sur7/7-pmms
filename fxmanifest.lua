fx_version "cerulean"
game "gta5"

name "7-pmms"
description "Synchronized media player for FiveM"
author "kibukj (base script) & arobase7sur7 (full rework)"
version "0.1.1"


shared_scripts {
    "config/config.lua",
    "shared/utils.lua",
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    "shared/static_emitters.lua",
    "server/database.lua",
    "server/search.lua",
    "server/resolver.lua",
    "server/friends.lua",
    "server/playlists.lua",
    "server/permissions.lua",
    "server/equalizer.lua",
    "server/admin.lua",
    "server/main.lua",
    "server/media.lua",
    "server/queue.lua",
    "server/commands.lua",
    "server/persistence.lua",
}

client_scripts {
    "shared/static_emitters.lua",
    "client/dui.lua",
    "client/entities.lua",
    "client/target.lua",
    "client/media.lua",
    "client/placement.lua",
    "client/nui.lua",
    "client/main.lua",
}

files {
    "ui/index.html",
    "ui/style.css",
    "ui/app.js",
    "ui/assets/props/*.svg",
    "ui/assets/props/*.png",
    "ui/assets/props/*.jpg",
    "ui/assets/props/*.webp",
    "http/dui_runtime/index.html",
    "http/dui_runtime/style.css",
    "http/dui_runtime/script.js",
    "http/dui_runtime/hls.min.js",
    "http/dui_runtime/loading.svg",
    "http/dui_runtime/mediaelement.min.js",
    "http/dui_runtime/mediaelementplayer.min.css",
    "http/dui_runtime/dailymotion.min.js",
    "http/dui_runtime/twitch.min.js",
    "http/dui_runtime/vimeo.min.js",
    "http/dui_runtime/wave.js",
    "web/youtube-player/player.html",
}

ui_page "ui/index.html"
