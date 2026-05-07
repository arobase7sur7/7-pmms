fx_version "cerulean"
game "gta5"

name        "7-pmms"
description "Synchronized media player for FiveM"
author      "kibukj (base script) & arobase7sur7 (full rework)"
version     "3.0.0"


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
    "client/nui.lua",
    "client/main.lua",
}

files {
    "ui/index.html",
    "ui/style.css",
    "ui/app.js",
}

ui_page "ui/index.html"
