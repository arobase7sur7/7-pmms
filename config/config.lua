Config = {}

-- ═══════════════════════════════════════════════════════════════
--  GENERAL
-- ═══════════════════════════════════════════════════════════════

Config.commandPrefix    = "pmms"
Config.commandSeparator = "_"

Config.maxDiscoveryDistance = 30.0
Config.defaultRange         = 30.0
Config.maxRange             = 200.0
Config.adminMaxRange        = Config.maxRange
Config.deviceIdleResetSeconds = 300
Config.defaultVolume        = 100
Config.defaultVehicleMode   = false
Config.defaultVideoSize     = 30
Config.defaultSearchSource  = "youtube"
Config.defaultTransitionSeconds = 5.0
Config.maxTransitionSeconds     = 15.0

Config.showNotifications    = true
Config.notificationDuration = 5000

Config.allowPlayingFromVehicles  = true
Config.autoDisableStaticEmitters = true
Config.autoDisableIdleCam        = true
Config.autoDisableVehicleRadio   = true

Config.debug = {
    -- Master switch. Leave false in production unless you are diagnosing an issue.
    enabled = true,

    -- Set all = true to enable every debug category below.
    all = true,

    player = true,    -- start/stop/startup/retry/cancel playback decisions
    resolver = true,  -- provider order, provider failures, fallback decisions
    favorites = true, -- favorite optimistic/server ack/persistence decisions
    dui = true,       -- DUI browser startup and local playback errors
    nui = false,      -- browser/NUI console logs
    search = false,
    database = false,
    target = false,
}

Config.playlists = {
    maxCount = 20,
    maxFavorites = 5,
}

Config.search = {
    minimumBusyMs = 500,
}

Config.directLinks = {
    requireHttps = true,
    probeTimeoutMs = 2500,
    allowedExtensions = {
        "mp3",
        "mp4",
        "m4v",
        "webm",
        "ogg",
        "ogv",
        "oga",
        "wav",
    },
}

Config.queue = {
    lookaheadCount = 1,
}

Config.social = {
    recentPlayerExpiryDays = 30,
    maxSuggestions = 10,
}

Config.targeting = {
    -- "fallback" | "qb-target" | "ox_target"
    system = "qb-target",
    label = "Open Media",
    icon = "fas fa-music",
    distance = 2.0,
}

-- ═══════════════════════════════════════════════════════════════
--  AUDIO
-- ═══════════════════════════════════════════════════════════════

Config.defaultSameRoomAttenuation = 4.0
Config.defaultDiffRoomAttenuation = 6.0
Config.defaultDiffRoomVolume      = 0.25
Config.enableFilterByDefault      = false
Config.rangeCurveExponent         = 1.6

-- ═══════════════════════════════════════════════════════════════
--  DUI
-- ═══════════════════════════════════════════════════════════════

Config.dui = {
    screenWidth  = 1280,
    screenHeight = 720,
    timeout      = 30000,

    urls = {},

    probe = {
        enabled = false,
        timeout = 4500,
        order = { "local" },
        rememberLastGood = false,
    }
}

Config.resolver = {
    enabled = true,
    timeoutMs = 6000,
    cacheTtlSeconds = 1800,
    maxInstances = 6,
    parallelInstancesPerProvider = 2,
    -- How long a failing resolver instance is skipped before retrying it.
    instanceFailureCooldownSeconds = 600,

    extractor = {
        enabled = true,
        providerOrder = { "yt_dlp_local", "extractor_http", "cobalt", "invidious", "piped" },
        httpEndpoints = {
            -- Example:
            -- "https://your-resolver.example.com/api/resolve",
        },
        -- First available command is used in order.
        ytDlpCommand = {
            "yt-dlp",
            "python -m yt_dlp",
            "py -m yt_dlp",
        },
        timeoutMs = 9000,
        cooldownSeconds = 300,
        maxAttemptsPerProvider = 2,
    },

    -- Optional Cobalt media downloader API endpoints. This is the most reliable
    -- ad-free fallback when you cannot run yt-dlp inside the FiveM server process.
    -- Self-host Cobalt or use a trusted private instance, then add its API root here.
    cobalt = {
        enabled = true,
        endpoints = {
            -- Example:
            -- "https://your-cobalt-instance.example.com",
        },
        apiKey = "",
        apiKeyHeader = "Authorization",
        apiKeyPrefix = "Api-Key",
        timeoutMs = 12000,
        alwaysProxy = true,
        videoQuality = "720",
        youtubeVideoCodec = "h264",
        youtubeVideoContainer = "mp4",
        audioFormat = "mp3",
        audioBitrate = "128",
    },

    -- Optional static resolver instances used before public discovery.
    -- Add your own reliable endpoints here for best results.
    instances = {
        invidious = {
            "https://inv.nadeko.net",
            "https://yewtu.be",
            "https://invidious.nerdvpn.de",
        },
        piped = {
            "https://api.piped.private.coffee",
            "https://pipedapi.kavin.rocks",
            "https://api-piped.mha.fi",
            "https://pipedapi.adminforge.de",
            "https://piped-api.hostux.net",
            "https://pipedapi.qdi.fi",
        },
    },

    -- If video resolution fails, try an ad-free audio-only stream before failing.
    allowAudioFallback = true,

    -- Embedded YouTube can show ads or hang in DUI. Keep it opt-in.
    allowEmbedFallback = false,

    -- Legacy switch for resolver fallback behavior. Embedded fallback still requires allowEmbedFallback.
    fallbackOnFailure = true,
    warnOnFallback = false,

    -- Retry resolution after an early playback failure.
    retryOnPlaybackError = true,
    retryAttempts = 1,
}

-- ═══════════════════════════════════════════════════════════════
--  SCALEFORM
-- ═══════════════════════════════════════════════════════════════

Config.defaultScaleformName = "pmms_texture_renderer"

-- ═══════════════════════════════════════════════════════════════
--  ALLOWED URLS (players without pmms.anyUrl)
-- ═══════════════════════════════════════════════════════════════

Config.allowedUrls = {
    "^https?://w?w?w?%.?youtube.com/.*$",
    "^https?://w?w?w?%.?youtu.be/.*$",
    "^https?://w?w?w?%.?twitch.tv/.*$",
}

-- ═══════════════════════════════════════════════════════════════
--  PRESETS
--  ['key'] = { url = '...', title = '...', filter = bool, video = bool }
-- ═══════════════════════════════════════════════════════════════

Config.presets = {}

-- ═══════════════════════════════════════════════════════════════
--  DEFAULT MEDIA PLAYERS (auto-spawn / auto-play on resource start)
-- ═══════════════════════════════════════════════════════════════

Config.defaultMediaPlayers = {}
Config.defaultMediaPlayerSpawnDistance = Config.maxRange + 10.0

-- ═══════════════════════════════════════════════════════════════
--  DEFAULT MODEL
-- ═══════════════════════════════════════════════════════════════

Config.defaultModel = "prop_boombox_01"

-- ═══════════════════════════════════════════════════════════════
--  ENTITY MODELS
-- ═══════════════════════════════════════════════════════════════

Config.models = {
    -- Audio devices
    ["prop_radio_01"]         = { label = "Radio", width = 128, height = 128 },
    ["prop_boombox_01"]       = { label = "Boombox", width = 128, height = 128 },
    ["prop_portable_hifi_01"] = { label = "Boombox", width = 128, height = 128 },
    ["prop_ghettoblast_01"]   = { label = "Boombox", width = 128, height = 128 },
    ["prop_ghettoblast_02"]   = { label = "Boombox", width = 128, height = 128 },
    ["prop_tapeplayer_01"]    = { label = "Tape Player", width = 128, height = 128 },
    ["prop_mp3_dock"]         = { label = "MP3 Dock", width = 128, height = 128 },
    ["v_res_mm_audio"]        = { label = "MP3 Dock", width = 128, height = 128 },
    ["v_res_j_radio"]         = { label = "Radio", width = 128, height = 128 },
    ["v_res_fa_radioalrm"]    = { label = "Alarm Clock", width = 128, height = 128 },
    ["sm_prop_smug_radio_01"] = { label = "Radio", width = 128, height = 128 },

    -- Jukeboxes
    ["bkr_prop_clubhouse_jukebox_01a"] = { label = "Jukebox" },
    ["bkr_prop_clubhouse_jukebox_01b"] = { label = "Jukebox" },
    ["bkr_prop_clubhouse_jukebox_02a"] = { label = "Jukebox" },
    ["ch_prop_arcade_jukebox_01a"]     = { label = "Jukebox" },
    ["prop_50s_jukebox"]               = { label = "Jukebox" },
    ["prop_jukebox_01"]                = { label = "Jukebox" },

    -- TVs
    ["ex_prop_ex_tv_flat_01"]  = { label = "TV", renderTarget = "ex_tvscreen" },
    ["prop_tv_flat_01"]        = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_flat_02"]        = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_flat_02b"]       = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_flat_03"]        = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_flat_03b"]       = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_flat_michael"]   = { label = "TV", renderTarget = "tvscreen" },
    ["prop_trev_tv_01"]        = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_02"]             = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_03"]             = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_03_overlay"]     = { label = "TV", renderTarget = "tvscreen" },
    ["des_tvsmash_start"]      = { label = "TV", renderTarget = "tvscreen" },
    ["prop_flatscreen_overlay"] = { label = "TV", renderTarget = "tvscreen" },
    ["prop_tv_flat_01_screen"] = { label = "TV", renderTarget = "tvscreen" },
    ["vw_prop_vw_cinema_tv_01"] = { label = "TV", renderTarget = "tvscreen" },
    ["ch_prop_ch_tv_rt_01a"]   = { label = "TV", renderTarget = "ch_tv_rt_01a" },

    -- Monitors
    ["prop_monitor_w_large"]   = { label = "Monitor", renderTarget = "tvscreen" },
    ["prop_monitor_02"  ]        = { label = "Monitor", renderTarget = "tvscreen" },

    -- Laptops
    ["prop_laptop_lester2"]    = { label = "Laptop", renderTarget = "tvscreen" },
    ["hei_prop_hst_laptop"]    = { label = "Laptop", renderTarget = "tvscreen" },
    ["hei_bank_heist_laptop"]  = { label = "Laptop", renderTarget = "tvscreen" },
    ["gr_prop_gr_laptop_01a"]  = { label = "Laptop", renderTarget = "gr_bunker_laptop_01a" },
    ["gr_prop_gr_laptop_01b"]  = { label = "Laptop", renderTarget = "gr_bunker_laptop_sq_01a" },
    ["imp_prop_impexp_lappy_01a"] = { label = "Laptop", renderTarget = "prop_impexp_lappy_01a" },
    ["bkr_prop_clubhouse_laptop_01a"] = { label = "Laptop", renderTarget = "prop_clubhouse_laptop_01a" },
    ["bkr_prop_clubhouse_laptop_01b"] = { label = "Laptop", renderTarget = "prop_clubhouse_laptop_square_01a" },
    ["ba_prop_club_laptop_dj"]    = { label = "Laptop", renderTarget = "laptop_dj" },
    ["ba_prop_club_laptop_dj_02"] = { label = "Laptop", renderTarget = "laptop_dj_02" },

    -- Tablets
    ["hei_prop_dlc_tablet"]    = { label = "Tablet", renderTarget = "tablet" },
    ["ba_prop_battle_hacker_screen"] = { label = "Tablet", renderTarget = "prop_battle_touchscreen_rt" },

    -- Cinema screens
    ["prop_big_cin_screen"]    = { label = "Cinema", renderTarget = "cinscreen" },
    ["v_ilev_cin_screen"]      = { label = "Cinema", renderTarget = "cinscreen" },

    -- Projectors
    ["v_ilev_lest_bigscreen"]  = { label = "Projector", renderTarget = "tvscreen" },
    ["v_ilev_mm_screen"]       = { label = "Projector", renderTarget = "big_disp" },
    ["v_ilev_mm_screen2"]      = { label = "Projector", renderTarget = "tvscreen" },
    ["hei_prop_dlc_heist_board"] = { label = "Projector", renderTarget = "heist_brd" },

    -- Computers
    ["ba_prop_battle_club_computer_01"] = { label = "Computer", renderTarget = "club_computer" },
    ["sm_prop_smug_monitor_01"] = { label = "Computer", renderTarget = "smug_monitor_01" },
    ["ex_prop_monitor_01_ex"]  = { label = "Computer", renderTarget = "prop_ex_computer_screen" },

    -- Large displays
    ["prop_huge_display_01"]   = { label = "Screen", renderTarget = "big_disp", width = 1920, height = 1080 },
    ["prop_huge_display_02"]   = { label = "Screen", renderTarget = "big_disp", width = 1920, height = 1080 },
    ["xs_prop_arena_bigscreen_01"] = { label = "Jumbotron", renderTarget = "bigscreen_01", width = 1920, height = 1080 },

    -- Bunker / Trailer monitors
    ["gr_prop_gr_trailer_monitor_01"] = { label = "Monitor", renderTarget = "gr_trailer_monitor_01" },
    ["gr_prop_gr_trailer_monitor_02"] = { label = "Monitor", renderTarget = "gr_trailer_monitor_02" },
    ["gr_prop_gr_trailer_monitor_03"] = { label = "Monitor", renderTarget = "gr_trailer_monitor_03" },
    ["gr_prop_gr_trailer_tv"]    = { label = "TV", renderTarget = "gr_trailertv_01" },
    ["gr_prop_gr_trailer_tv_02"] = { label = "TV", renderTarget = "gr_trailertv_02" },

    -- Heist / Special
    ["hei_prop_hei_monitor_overlay"] = { label = "Monitor", renderTarget = "hei_mon" },
    ["hei_prop_hei_muster_01"] = { label = "Whiteboard", renderTarget = "planning" },
    ["xm_prop_orbital_cannon_table"] = { label = "Orbital Cannon", renderTarget = "orbital_table" },
    ["sr_mp_spec_races_blimp_sign"] = { label = "Blimp", renderTarget = "blimp_text" },
    ["xm_prop_x17_sec_panel_01"] = { label = "Panel", renderTarget = "prop_x17_p_01" },

    -- Smuggler / Doomsday screens
    ["xm_prop_x17_tv_flat_01"]   = { label = "TV", renderTarget = "tv_flat_01" },
    ["sm_prop_smug_tv_flat_01"]  = { label = "TV", renderTarget = "tv_flat_01" },
    ["xm_prop_x17_computer_02"]  = { label = "Monitor", renderTarget = "monitor_02" },
    ["xm_prop_x17dlc_monitor_wall_01a"] = { label = "Screen", renderTarget = "prop_x17dlc_monitor_wall_01a" },

    -- Doomsday multi-screens
    ["xm_prop_x17_screens_02a_01"] = { label = "Screen", renderTarget = "prop_x17_8scrn_01" },
    ["xm_prop_x17_screens_02a_02"] = { label = "Screen", renderTarget = "prop_x17_8scrn_02" },
    ["xm_prop_x17_screens_02a_03"] = { label = "Screen", renderTarget = "prop_x17_8scrn_03" },
    ["xm_prop_x17_screens_02a_04"] = { label = "Screen", renderTarget = "prop_x17_8scrn_04" },
    ["xm_prop_x17_screens_02a_05"] = { label = "Screen", renderTarget = "prop_x17_8scrn_05" },
    ["xm_prop_x17_screens_02a_06"] = { label = "Screen", renderTarget = "prop_x17_8scrn_06" },
    ["xm_prop_x17_screens_02a_07"] = { label = "Screen", renderTarget = "prop_x17_8scrn_07" },
    ["xm_prop_x17_screens_02a_08"] = { label = "Screen", renderTarget = "prop_x17_8scrn_08" },

    -- Doomsday TVs
    ["xm_prop_x17_tv_ceiling_scn_01"] = { label = "TV", renderTarget = "prop_x17_tv_ceil_scn_01" },
    ["xm_prop_x17_tv_ceiling_scn_02"] = { label = "TV", renderTarget = "prop_x17_tv_ceil_scn_02" },
    ["xm_prop_x17_tv_scrn_01"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_01" },
    ["xm_prop_x17_tv_scrn_02"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_02" },
    ["xm_prop_x17_tv_scrn_03"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_03" },
    ["xm_prop_x17_tv_scrn_04"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_04" },
    ["xm_prop_x17_tv_scrn_05"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_05" },
    ["xm_prop_x17_tv_scrn_06"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_06" },
    ["xm_prop_x17_tv_scrn_07"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_07" },
    ["xm_prop_x17_tv_scrn_08"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_08" },
    ["xm_prop_x17_tv_scrn_09"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_09" },
    ["xm_prop_x17_tv_scrn_10"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_10" },
    ["xm_prop_x17_tv_scrn_11"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_11" },
    ["xm_prop_x17_tv_scrn_12"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_12" },
    ["xm_prop_x17_tv_scrn_13"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_13" },
    ["xm_prop_x17_tv_scrn_14"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_14" },
    ["xm_prop_x17_tv_scrn_15"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_15" },
    ["xm_prop_x17_tv_scrn_16"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_16" },
    ["xm_prop_x17_tv_scrn_17"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_17" },
    ["xm_prop_x17_tv_scrn_18"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_18" },
    ["xm_prop_x17_tv_scrn_19"]  = { label = "TV", renderTarget = "prop_x17_tv_scrn_18" },
    ["xm_screen_1"]             = { label = "Screen", renderTarget = "prop_x17_tv_ceiling_01" },

    -- Arena War
    ["xs_prop_arena_screen_tv_01"] = { label = "TV", renderTarget = "screen_tv_01" },

    -- Arcade machines
    ["vw_prop_vw_arcade_01_screen"]  = { label = "Arcade Machine", renderTarget = "arcade_01a_screen" },
    ["vw_prop_vw_arcade_02_screen"]  = { label = "Arcade Machine", renderTarget = "arcade_02a_screen" },
    ["vw_prop_vw_arcade_02b_screen"] = { label = "Arcade Machine", renderTarget = "arcade_02b_screen" },
    ["vw_prop_vw_arcade_02c_screen"] = { label = "Arcade Machine", renderTarget = "arcade_02c_screen" },
    ["vw_prop_vw_arcade_02d_screen"] = { label = "Arcade Machine", renderTarget = "arcade_02d_screen" },

    -- Apartments / High-end TVs
    ["apa_mp_h_str_avunitl_01_b"] = { label = "TV", renderTarget = "tvscreen" },
    ["apa_mp_h_str_avunitl_04"]   = { label = "TV", renderTarget = "tvscreen" },
    ["apa_mp_h_str_avunitm_01"]   = { label = "TV", renderTarget = "tvscreen" },
    ["apa_mp_h_str_avunitm_03"]   = { label = "TV", renderTarget = "tvscreen" },
    ["apa_mp_h_str_avunits_01"]   = { label = "TV", renderTarget = "tvscreen" },
    ["apa_mp_h_str_avunits_04"]   = { label = "TV", renderTarget = "tvscreen" },
    ["hei_heist_str_avunitl_03"]  = { label = "TV", renderTarget = "tvscreen" },

    -- Phones
    ["prop_phone_cs_frank"] = { label = "Phone", renderTarget = "npcphone" },
    ["prop_phone_proto"]    = { label = "Phone", renderTarget = "npcphone" },

    -- Misc
    ["w_am_digiscanner"] = { label = "Digiscanner", renderTarget = "digiscanner" },

    -- Vehicles
    ["pbus2"]   = { attenuation = { sameRoom = 1.5, diffRoom = 6 }, range = 100, isVehicle = false },
    ["blimp3"]  = { attenuation = { sameRoom = 0.6, diffRoom = 6 }, range = 150, isVehicle = false },
}

-- ═══════════════════════════════════════════════════════════════
--  AUDIO VISUALIZATIONS
-- ═══════════════════════════════════════════════════════════════

Config.searchSources = {
    ["youtube"] = {
        label = "YouTube",
        enabled = true,
        icon = "video",
        placeholder = "Search YouTube...",
        maxResults = 10,
        cooldown = 2,
    },
    ["soundcloud"] = {
        label = "SoundCloud",
        enabled = true,
        icon = "music",
        placeholder = "Search SoundCloud...",
        maxResults = 10,
        cooldown = 2,
    },
    ["twitch"] = {
        label = "Twitch",
        enabled = true,
        icon = "twitch",
        placeholder = "Enter Twitch Username...",
        maxResults = 10,
        cooldown = 2,
        clientId = "", -- Add Twitch API Client ID here if available, otherwise it directly bypasses
        clientSecret = "",
    }
}

Config.audioVisualizations = {
    ["bars"]         = { name = "Bars" },
    ["bars blocks"]  = { name = "Blocky Bars" },
    ["cubes"]        = { name = "Cubes" },
    ["dualbars"]     = { name = "Dual Bars" },
    ["dualbars blocks"] = { name = "Blocky Dual Bars" },
    ["fireworks"]    = { name = "Fireworks" },
    ["flower"]       = { name = "Flower" },
    ["flower blocks"] = { name = "Blocky Flower" },
    ["orbs"]         = { name = "Orbs" },
    ["ring"]         = { name = "Ring" },
    ["rings"]        = { name = "Rings" },
    ["round wave"]   = { name = "Round Wave" },
    ["shine"]        = { name = "Shine" },
    ["shine rings"]  = { name = "Shine Rings" },
    ["shockwave"]    = { name = "Shockwave" },
    ["star"]         = { name = "Star" },
    ["static"]       = { name = "Static" },
    ["stitches"]     = { name = "Stitches" },
    ["web"]          = { name = "Web" },
    ["wave"]         = { name = "Wave" },
}
