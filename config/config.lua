Config                                 = {}

-- ═══════════════════════════════════════════════════════════════
--  GENERAL
-- ═══════════════════════════════════════════════════════════════

Config.commandPrefix                   = "pmms"
Config.commandSeparator                = "_"

Config.maxDiscoveryDistance            = 30.0
Config.discoveryUpdateDistance         = 10.0
Config.defaultRange                    = 30.0
Config.maxRange                        = 200.0
Config.adminMaxRange                   = 10000.0
Config.deviceIdleResetSeconds          = 300
Config.defaultVolume                   = 100
Config.defaultVehicleMode              = false
Config.defaultVideoSize                = 30
Config.defaultSearchSource             = "youtube"
Config.defaultTransitionSeconds        = 5.0
Config.maxTransitionSeconds            = 15.0

Config.showNotifications               = true
Config.notificationDuration            = 5000

Config.allowPlayingFromVehicles        = true
Config.autoDisableStaticEmitters       = true
Config.autoDisableIdleCam              = true
Config.autoDisableVehicleRadio         = true

Config.player                          = {
    -- URL for the hosted React Player page. Deploy your own copy or keep the project default.
    hostedPlayerUrl = "https://pmms-player.pages.dev",
    -- Enables the hosted iframe for HTTP(S) playback before falling back to local DUI providers.
    useHostedPlayer = true,
}

Config.debug                           = {
    -- Master switch. Leave false unless you are diagnosing an issue
    enabled = false,

    -- Set all = true to enable every debug category below
    all = false,

    player = false,
    resolver = false,
    favorites = false,
    dui = false,
    nui = false,
    search = false,
    database = false,
    target = false,
    permissions = false,
}

Config.ui                              = {
    maxHistorySyncItems = 30,
}

Config.sync                            = {
    throttleMs = 500,
    fullSyncIntervalMs = 30000,
    driftCheckIntervalS = 30,
    maxDriftSeconds = 2.0,
    joinJitterMs = 500,
}

Config.admin                           = {
    quickActions = {
        applyProfiles = true,
        extendedRangeToggle = true,
    },
    logs = {
        maxEntries = 150,
    },
}

Config.playlists                       = {
    maxCount = 50,
    maxFavorites = 10,
}

Config.search                          = {
    minimumBusyMs = 500,
    maxInstances = 8,
    instanceFailureCooldownSeconds = 600,
    proxyThumbnails = true,
    thumbnailProxyTimeoutMs = 1500,
}

Config.directLinks                     = {
    requireHttps = true,
    probeTimeoutMs = 2500,
    allowedExtensions = {
        "mp3",
        "m4a",
        "aac",
        "mp4",
        "m4v",
        "webm",
        "ogg",
        "ogv",
        "oga",
        "wav",
        "m3u8",
    },
}

Config.queue                           = {
    lookaheadCount = 1,
}

Config.social                          = {
    recentPlayerExpiryDays = 30,
    maxSuggestions = 10,
}

Config.targeting                       = {
    -- "fallback" | "qb-target" | "ox_target"
    system = "qb-target",
    label = "Open Media",
    icon = "fas fa-music",
    distance = 2.0,
}

Config.permissions                     = {
    mode = "hybrid",

    adminAceFallbacks = { "command", "command.pmms", "god", "admin", "group.admin", "qbcore.god", "qbcore.admin", "command.tpm", "command.addpermission" },

    qbcore = {
        enabled = true,
        resource = "qb-core",
        aceFallback = true,
        adminPermissions = { "god", "admin" },
    },
}

Config.deviceProfiles                  = { -- these are only some examples but you can create as many as you want and edit them as you want
    club = {
        label = "Club",
        range = 80.0,
        volume = 80,
        maxVolume = 100,
        loopMode = "queue",
        requestMode = "pending",
    },
    dj_booth = {
        label = "DJ Booth",
        range = 65.0,
        volume = 85,
        maxVolume = 100,
        loopMode = "queue",
        requestMode = "pending",
    },
    cinema = {
        label = "Cinema",
        range = 120.0,
        volume = 70,
        videoOnly = true,
        requestMode = "disabled",
    },
    radio = {
        label = "Radio",
        range = 45.0,
        volume = 60,
        loopMode = "queue",
        requestMode = "queue",
    },
    vehicle = {
        label = "Vehicle",
        range = 35.0,
        volume = 65,
        isVehicle = true,
        requestMode = "queue",
    },
    event = {
        label = "Event",
        range = 150.0,
        volume = 80,
        maxVolume = 100,
        loopMode = "queue",
        requestMode = "pending",
    },
    staff = {
        label = "Staff Device",
        range = 60.0,
        volume = 75,
        adminLock = { mode = "admin" },
        requestMode = "disabled",
    },
    public = {
        label = "Public Device",
        range = 30.0,
        volume = 60,
        requestMode = "queue",
    },
}

Config.requests                        = {
    enabled = true,
    defaultMode = "queue", -- queue | pending | disabled
    maxPendingPerPlayer = 3,
    pendingExpireSeconds = 600,
    hostCanApprove = true,
    approverJobs = {
        -- Example:
        -- police = 2,
    },
}

Config.speakers                        = {
    enabled = true,
    normalPlayerLimit = 3,
    staffLimit = -1, -- -1 = unlimited
    persistentForStaffDevices = true,
    avoidEcho = true,
    propModel = Config.defaultModel or "sf_prop_sf_speaker_l_01a", -- This is only a fallback but you can manage them on the SPEAKERS MODEL LIST below
}

-- ═══════════════════════════════════════════════════════════════
--  AUDIO
-- ═══════════════════════════════════════════════════════════════

Config.defaultSameRoomAttenuation      = 4.0
Config.defaultDiffRoomAttenuation      = 6.0
Config.defaultDiffRoomVolume           = 0.25
Config.enableFilterByDefault           = false
Config.rangeCurveExponent              = 1.6

-- ═══════════════════════════════════════════════════════════════
--  DUI
-- ═══════════════════════════════════════════════════════════════

Config.dui                             = {
    screenWidth          = 1280,
    screenHeight         = 720,
    timeout              = 30000,
    renderMaxFps         = 60,
    renderIdleFps        = 5,
    renderDistanceBuffer = 5.0,
    cacheRuntimeAssets   = true,
    hlsCanvasDownscale   = true,
    hlsCanvasMaxWidth    = 1920,
    hlsCanvasMaxHeight   = 1080,
    hlsCanvasMaxFps      = 30,

    youtube              = {
        -- Optional: host web/youtube-player/player.html on a real HTTPS domain
        -- and paste the URL here. When set, it becomes the primary YouTube path.
        externalPlayerUrl = "",
        preferExternalPlayer = true,

        -- Optional public front-end fallback for non-policy iframe/API failures.
        -- This is disabled by default because public instances are best-effort,
        -- may rate-limit, and cannot override YouTube owner-disabled embeds.
        allowFrontendFallback = false,
        frontendFallbackTimeoutMs = 6000,
        frontendInstances = {
            { type = "invidious", url = "https://yewtu.be" },
            { type = "invidious", url = "https://inv.nadeko.net" },
            { type = "piped", url = "https://piped.video" },
        },
    },

    urls                 = {},

    probe                = {
        enabled = false,
        timeout = 4500,
        order = { "local" },
        rememberLastGood = false,
    }
}

Config.resolver                        = {
    enabled = true,
    timeoutMs = 6000,
    cacheTtlSeconds = 1800,
    maxInstances = 6,
    parallelInstancesPerProvider = 2,
    -- How long a failing resolver instance is skipped before retrying it
    instanceFailureCooldownSeconds = 600,
    -- How long one failed media source is quarantined from automatic retries/loop recycling
    sourceFailureCooldownSeconds = 900,
    -- Used when providers expose alternate audio metadata. First match wins
    audioLanguagePriority = { "original", "en", "en-US", "und" },

    -- Default public-release YouTube mode: client Chromium/DUI plays YouTube directly.
    -- Server-side extractors are developer-only fallbacks and are not required for users.
    browserYoutube = {
        enabled = true,
        primary = true,
        hideProviderSelector = true,
    },

    extractor = {
        enabled = false,
        providerOrder = { "yt_dlp_local", "extractor_http", "cobalt", "invidious", "piped" },
        -- Advanced/developer-only fallback. Leave disabled for normal public installs.
        -- Public Invidious/Piped playback is best-effort and often slow/blocked.
        allowPublicFallbacks = false,
        httpEndpoints = {
            -- Example:
            -- "https://your-resolver.example.com/api/resolve",
        },
        -- Optional dev/private-fork extractor commands. Not required for public users.
        ytDlpCommand = {
            "yt-dlp",
            "python -m yt_dlp",
            "py -m yt_dlp",
        },
        -- Optional dev/private-fork binary/path override. Example: "C:/tools/yt-dlp.exe"
        ytDlpPath = nil,
        -- Optional cookie file or extra args for yt-dlp when YouTube challenges the server IP.
        ytDlpCookiesPath = nil,
        ytDlpExtraArgs = {},
        timeoutMs = 9000,
        cooldownSeconds = 300,
        maxAttemptsPerProvider = 2,
        maxGlobalConcurrent = 8,
        absoluteTimeoutSeconds = 45,
        hedgeRatio = 0.6,
        softBanDurationSeconds = 60,
        hardBanDurationSeconds = 300,
        providers = {
            yt_dlp_local = { maxConcurrent = 1, timeoutSeconds = 20 },
            extractor_http = { maxConcurrent = 5, timeoutSeconds = 15 },
            cobalt = { maxConcurrent = 4, timeoutSeconds = 12 },
            invidious = { maxConcurrent = 6, timeoutSeconds = 10 },
            piped = { maxConcurrent = 6, timeoutSeconds = 10 },
        },
    },

    -- Optional dev/private-fork Cobalt endpoints. Not used by the default
    -- browser YouTube provider and not required for public installs.
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

    -- Optional static resolver instances used before public discovery
    -- Add your own reliable endpoints here for best results
    instances = {
        invidious = {
            "https://inv.nadeko.net",
            "https://yewtu.be",
            "https://invidious.nerdvpn.de",
            "https://yt.chocolatemoo53.com",
            "https://inv.thepixora.com",
        },

        piped = {
            "https://api.piped.private.coffee",
            "https://pipedapi.kavin.rocks",
            "https://api-piped.mha.fi",
            "https://pipedapi.adminforge.de",
            "https://piped-api.hostux.net",
            "https://pipedapi.qdi.fi",
            "https://pipedapi.leptons.xyz",
            "https://pipedapi.nosebs.ru",
            "https://pipedapi.privacy.com.de",
            "https://pipedapi.drgns.space",
            "https://pipedapi.owo.si",
            "https://pipedapi.ducks.party",
            "https://piped-api.codespace.cz",
            "https://pipedapi.reallyaweso.me",
            "https://api.piped.private.coffee",
            "https://pipedapi.darkness.services",
            "https://pipedapi.orangenet.cc",
            "https://pipedapi-libre.kavin.rocks",
        },
    },


    -- Browser YouTube is the default. Audio/server fallbacks are dev-only opt-ins.
    allowAudioFallback = false,

    -- Embedded YouTube can show ads or hang in DUI. Keep it opt-in so false if you see too many ads
    allowEmbedFallback = false,

    -- Legacy switch for resolver fallback behavior. Embedded fallback still requires allowEmbedFallback
    fallbackOnFailure = true,
    warnOnFallback = false,

    -- Retry resolution after an early playback failure
    retryOnPlaybackError = true,
    retryAttempts = 1,

    adaptiveProviderRanking = {
        enabled = true,
        minCompletedPlays = 8,
        minProviderSamples = 2,
        dataFile = "data/provider_stats.json",
        saveDebounceMs = 5000,
    },
}

-- ═══════════════════════════════════════════════════════════════
--  SCALEFORM
-- ═══════════════════════════════════════════════════════════════

Config.defaultScaleformName            = "pmms_texture_renderer"

-- ═══════════════════════════════════════════════════════════════
--  ALLOWED URLS (players without pmms.anyUrl)
-- ═══════════════════════════════════════════════════════════════

Config.allowedUrls                     = { -- actually, because of direct url in config, you dont need this
    "^https?://w?w?w?%.?youtube.com/.*$",
    "^https?://w?w?w?%.?youtu.be/.*$",
    "^https?://w?w?w?%.?twitch.tv/.*$",
}

-- ═══════════════════════════════════════════════════════════════
--  PRESETS
--  ['key'] = { url = '...', title = '...', filter = bool, video = bool }
-- ═══════════════════════════════════════════════════════════════

Config.presets                         = {}

-- ═══════════════════════════════════════════════════════════════
--  DEFAULT MEDIA PLAYERS (auto-spawn / auto-play on resource start)
-- ═══════════════════════════════════════════════════════════════

Config.defaultMediaPlayers             = {}
Config.defaultMediaPlayerSpawnDistance = Config.maxRange + 10.0

-- ═══════════════════════════════════════════════════════════════
--  DEFAULT MODEL
-- ═══════════════════════════════════════════════════════════════

Config.defaultModel                    = "sf_prop_sf_speaker_l_01a"

-- ═══════════════════════════════════════════════════════════════
--  ENTITY MODELS
-- ═══════════════════════════════════════════════════════════════

Config.models                          = {
    -- Audio devices
    ["prop_radio_01"]                   = { label = "Radio", width = 128, height = 128, isPlaceable = true },
    ["prop_boombox_01"]                 = { label = "Boombox", width = 128, height = 128, isPlaceable = true },
    ["prop_portable_hifi_01"]           = { label = "Boombox", width = 128, height = 128, isPlaceable = true },
    ["prop_ghettoblast_01"]             = { label = "Boombox", width = 128, height = 128, isPlaceable = true },
    ["prop_ghettoblast_02"]             = { label = "Boombox", width = 128, height = 128, isPlaceable = true },
    ["prop_tapeplayer_01"]              = { label = "Tape Player", width = 128, height = 128, isPlaceable = true },
    ["prop_mp3_dock"]                   = { label = "MP3 Dock", width = 128, height = 128, isPlaceable = true },
    ["v_res_mm_audio"]                  = { label = "MP3 Dock", width = 128, height = 128, isPlaceable = true },
    ["v_res_j_radio"]                   = { label = "Radio", width = 128, height = 128, isPlaceable = true },
    ["v_res_fa_radioalrm"]              = { label = "Alarm Clock", width = 128, height = 128, isPlaceable = true },
    ["sm_prop_smug_radio_01"]           = { label = "Radio", width = 128, height = 128, isPlaceable = true },

    -- Jukeboxes
    ["bkr_prop_clubhouse_jukebox_01a"]  = { label = "Jukebox", isPlaceable = true },
    ["bkr_prop_clubhouse_jukebox_01b"]  = { label = "Jukebox", isPlaceable = true },
    ["bkr_prop_clubhouse_jukebox_02a"]  = { label = "Jukebox", isPlaceable = true },
    ["ch_prop_arcade_jukebox_01a"]      = { label = "Jukebox", isPlaceable = true },
    ["prop_50s_jukebox"]                = { label = "Jukebox", isPlaceable = true },
    ["prop_jukebox_01"]                 = { label = "Jukebox", isPlaceable = true },

    -- TVs
    ["ex_prop_ex_tv_flat_01"]           = { label = "TV", renderTarget = "ex_tvscreen", isPlaceable = true },
    ["prop_tv_flat_01"]                 = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_flat_02"]                 = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_flat_02b"]                = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_flat_03"]                 = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_flat_03b"]                = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_flat_michael"]            = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_trev_tv_01"]                 = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_02"]                      = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_tv_flat_01_screen"]          = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["vw_prop_vw_cinema_tv_01"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["ch_prop_ch_tv_rt_01a"]            = { label = "TV", renderTarget = "ch_tv_rt_01a", isPlaceable = true },

    -- Monitors
    ["prop_monitor_w_large"]            = { label = "Monitor", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_monitor_02"]                 = { label = "Monitor", renderTarget = "tvscreen", isPlaceable = true },

    -- Laptops
    ["prop_laptop_lester2"]             = { label = "Laptop", renderTarget = "tvscreen", isPlaceable = true },
    ["hei_prop_hst_laptop"]             = { label = "Laptop", renderTarget = "tvscreen", isPlaceable = true },
    ["hei_bank_heist_laptop"]           = { label = "Laptop", renderTarget = "tvscreen", isPlaceable = true },
    ["gr_prop_gr_laptop_01a"]           = { label = "Laptop", renderTarget = "gr_bunker_laptop_01a", isPlaceable = true },
    ["gr_prop_gr_laptop_01b"]           = { label = "Laptop", renderTarget = "gr_bunker_laptop_sq_01a", isPlaceable = true },
    ["imp_prop_impexp_lappy_01a"]       = { label = "Laptop", renderTarget = "prop_impexp_lappy_01a", isPlaceable = true },
    ["bkr_prop_clubhouse_laptop_01a"]   = { label = "Laptop", renderTarget = "prop_clubhouse_laptop_01a", isPlaceable = true },
    ["bkr_prop_clubhouse_laptop_01b"]   = { label = "Laptop", renderTarget = "prop_clubhouse_laptop_square_01a", isPlaceable = true },
    ["ba_prop_club_laptop_dj"]          = { label = "Laptop", renderTarget = "laptop_dj", isPlaceable = true },
    ["ba_prop_club_laptop_dj_02"]       = { label = "Laptop", renderTarget = "laptop_dj_02", isPlaceable = true },

    -- Tablets
    ["hei_prop_dlc_tablet"]             = { label = "Tablet", renderTarget = "tablet", isPlaceable = true },
    ["ba_prop_battle_hacker_screen"]    = { label = "Tablet", renderTarget = "prop_battle_touchscreen_rt", isPlaceable = true },

    -- Cinema screens
    ["prop_big_cin_screen"]             = { label = "Cinema", renderTarget = "cinscreen", isPlaceable = true },
    ["v_ilev_cin_screen"]               = { label = "Cinema", renderTarget = "cinscreen", isPlaceable = true },

    -- Projectors
    ["v_ilev_lest_bigscreen"]           = { label = "Projector", renderTarget = "tvscreen", isPlaceable = true },
    ["v_ilev_mm_screen"]                = { label = "Projector", renderTarget = "big_disp", isPlaceable = true },
    ["v_ilev_mm_screen2"]               = { label = "Projector", renderTarget = "tvscreen", isPlaceable = true },
    ["hei_prop_dlc_heist_board"]        = { label = "Projector", renderTarget = "heist_brd", isPlaceable = true },

    -- Computers
    ["ba_prop_battle_club_computer_01"] = { label = "Computer", renderTarget = "club_computer", isPlaceable = true },
    ["sm_prop_smug_monitor_01"]         = { label = "Computer", renderTarget = "smug_monitor_01", isPlaceable = true },
    ["ex_prop_monitor_01_ex"]           = { label = "Computer", renderTarget = "prop_ex_computer_screen", isPlaceable = true },

    -- Large displays
    ["prop_huge_display_01"]            = { label = "Screen", renderTarget = "big_disp", width = 1920, height = 1080, isPlaceable = true },
    ["prop_huge_display_02"]            = { label = "Screen", renderTarget = "big_disp", width = 1920, height = 1080, isPlaceable = true },
    ["xs_prop_arena_bigscreen_01"]      = { label = "Jumbotron", renderTarget = "bigscreen_01", width = 1920, height = 1080, isPlaceable = true },

    -- Bunker / Trailer monitors
    ["gr_prop_gr_trailer_monitor_01"]   = { label = "Monitor", renderTarget = "gr_trailer_monitor_01", isPlaceable = true },
    ["gr_prop_gr_trailer_monitor_02"]   = { label = "Monitor", renderTarget = "gr_trailer_monitor_02", isPlaceable = true },
    ["gr_prop_gr_trailer_monitor_03"]   = { label = "Monitor", renderTarget = "gr_trailer_monitor_03", isPlaceable = true },
    ["gr_prop_gr_trailer_tv"]           = { label = "TV", renderTarget = "gr_trailertv_01", isPlaceable = true },
    ["gr_prop_gr_trailer_tv_02"]        = { label = "TV", renderTarget = "gr_trailertv_02", isPlaceable = true },

    -- Heist / Special
    ["hei_prop_hei_monitor_overlay"]    = { label = "Monitor", renderTarget = "hei_mon", isPlaceable = true },
    ["hei_prop_hei_muster_01"]          = { label = "Whiteboard", renderTarget = "planning", isPlaceable = true },
    ["xm_prop_orbital_cannon_table"]    = { label = "Orbital Cannon", renderTarget = "orbital_table", isPlaceable = true },
    ["sr_mp_spec_races_blimp_sign"]     = { label = "Blimp", renderTarget = "blimp_text", isPlaceable = true },
    ["xm_prop_x17_sec_panel_01"]        = { label = "Panel", renderTarget = "prop_x17_p_01", isPlaceable = true },

    -- Smuggler / Doomsday screens
    ["xm_prop_x17_tv_flat_01"]          = { label = "TV", renderTarget = "tv_flat_01", isPlaceable = true },
    ["sm_prop_smug_tv_flat_01"]         = { label = "TV", renderTarget = "tv_flat_01", isPlaceable = true },
    ["xm_prop_x17_computer_02"]         = { label = "Monitor", renderTarget = "monitor_02", isPlaceable = true },
    ["xm_prop_x17dlc_monitor_wall_01a"] = { label = "Screen", renderTarget = "prop_x17dlc_monitor_wall_01a", isPlaceable = true },

    -- Doomsday multi-screens
    ["xm_prop_x17_screens_02a_01"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_01", isPlaceable = true },
    ["xm_prop_x17_screens_02a_02"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_02", isPlaceable = true },
    ["xm_prop_x17_screens_02a_03"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_03", isPlaceable = true },
    ["xm_prop_x17_screens_02a_04"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_04", isPlaceable = true },
    ["xm_prop_x17_screens_02a_05"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_05", isPlaceable = true },
    ["xm_prop_x17_screens_02a_06"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_06", isPlaceable = true },
    ["xm_prop_x17_screens_02a_07"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_07", isPlaceable = true },
    ["xm_prop_x17_screens_02a_08"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_08", isPlaceable = true },

    -- Doomsday TVs
    ["xm_prop_x17_tv_ceiling_scn_01"]   = { label = "TV", renderTarget = "prop_x17_tv_ceil_scn_01", isPlaceable = true },
    ["xm_prop_x17_tv_ceiling_scn_02"]   = { label = "TV", renderTarget = "prop_x17_tv_ceil_scn_02", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_01"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_01", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_02"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_02", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_03"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_03", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_04"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_04", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_05"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_05", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_06"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_06", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_07"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_07", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_08"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_08", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_09"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_09", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_10"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_10", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_11"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_11", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_12"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_12", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_13"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_13", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_14"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_14", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_15"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_15", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_16"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_16", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_17"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_17", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_18"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_18", isPlaceable = true },
    ["xm_prop_x17_tv_scrn_19"]          = { label = "TV", renderTarget = "prop_x17_tv_scrn_18", isPlaceable = true },
    ["xm_screen_1"]                     = { label = "Screen", renderTarget = "prop_x17_tv_ceiling_01", isPlaceable = true },

    -- Arena War
    ["xs_prop_arena_screen_tv_01"]      = { label = "TV", renderTarget = "screen_tv_01" },

    -- Arcade machines
    ["vw_prop_vw_arcade_01_screen"]     = { label = "Arcade Machine", renderTarget = "arcade_01a_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02_screen"]     = { label = "Arcade Machine", renderTarget = "arcade_02a_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02b_screen"]    = { label = "Arcade Machine", renderTarget = "arcade_02b_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02c_screen"]    = { label = "Arcade Machine", renderTarget = "arcade_02c_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02d_screen"]    = { label = "Arcade Machine", renderTarget = "arcade_02d_screen", isPlaceable = true },

    -- Apartments / High-end TVs
    ["apa_mp_h_str_avunitl_01_b"]       = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunitl_04"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunitm_01"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunitm_03"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunits_01"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunits_04"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["hei_heist_str_avunitl_03"]        = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },

    -- Phones
    ["prop_phone_cs_frank"]             = { label = "Phone", renderTarget = "npcphone" },
    ["prop_phone_proto"]                = { label = "Phone", renderTarget = "npcphone" },

    -- Misc
    ["w_am_digiscanner"]                = { label = "Digiscanner", renderTarget = "digiscanner" },

    -- Vehicles
    ["pbus2"]                           = { attenuation = { sameRoom = 1.5, diffRoom = 6 }, range = 100, isVehicle = false },
    ["blimp3"]                          = { attenuation = { sameRoom = 0.6, diffRoom = 6 }, range = 150, isVehicle = false },
}

-- ═══════════════════════════════════════════════════════════════
--  AUDIO VISUALIZATIONS
-- ═══════════════════════════════════════════════════════════════

Config.searchSources                   = {
    ["youtube"] = {
        label = "YouTube",
        enabled = true,
        icon = "video",
        placeholder = "Search YouTube...",
        maxResults = 10,
        cooldown = 2,
    },
    ["youtube_embed"] = {
        label = "YouTube Embed",
        enabled = false,
        icon = "video",
        placeholder = "Search YouTube (embed)...",
        maxResults = 10,
        cooldown = 2,
        youtubeProvider = "embed",
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
    },
    ["direct"] = {
        label = "Direct",
        enabled = true,
        icon = "link",
        placeholder = "Paste a direct media URL...",
        maxResults = 1,
        cooldown = 0,
    },
    ["radio"] = {
        label = "Radio",
        enabled = true,
        icon = "radio",
        placeholder = "Search radio stations...",
        maxResults = 20,
        cooldown = 2,
    }
}

-- ═══════════════════════════════════════════════════════════════
--  EQUALIZER
-- ═══════════════════════════════════════════════════════════════
Config.equalizer                       = {
    enabled           = true,

    maxCustomPresets  = 5,

    defaultEnabled    = false,
    defaultPreampDb   = 0.0,
    defaultHighpass   = false,
    defaultCompressor = false,

    bands             = { 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 },

    defaultBands      = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },

    bandMinDb         = -15,
    bandMaxDb         = 15,
    preampMinDb       = -8,
    preampMaxDb       = 8,

    presets           = {
        {
            id = "flat",
            label = "Flat",
            preampDb = 0,
            bands = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
        },

        {
            id = "acoustic",
            label = "Acoustic",
            preampDb = -1,
            bands = { -2, -1, 0, 1, 2, 2, 1, 2, 3, 3 }
        },

        {
            id = "bass_booster",
            label = "Bass booster",
            preampDb = -4,
            bands = { 10, 9, 7, 4, 1, 0, -1, -2, -3, -4 }
        },

        {
            id = "bass_reducer",
            label = "Bass reducer",
            preampDb = 0,
            bands = { -10, -8, -6, -4, -2, -1, 0, 0, 0, 0 }
        },

        {
            id = "classical",
            label = "Classical",
            preampDb = -1,
            bands = { -1, -1, 0, 1, 2, 2, 2, 3, 3, 2 }
        },

        {
            id = "dance",
            label = "Dance",
            preampDb = -3,
            bands = { 7, 6, 4, 1, -1, -2, -1, 1, 3, 4 }
        },

        {
            id = "deep",
            label = "Deep",
            preampDb = -5,
            bands = { 12, 10, 8, 4, 0, -2, -3, -3, -2, -2 }
        },

        {
            id = "electronic",
            label = "Electronic",
            preampDb = -3,
            bands = { 8, 7, 5, 2, 0, -1, 0, 2, 4, 4 }
        },

        {
            id = "hiphop",
            label = "HipHop",
            preampDb = -4,
            bands = { 10, 10, 8, 5, 1, -1, -2, -1, 1, 2 }
        },

        {
            id = "jazz",
            label = "Jazz",
            preampDb = -1,
            bands = { 2, 2, 1, 1, 0, 0, 1, 2, 3, 3 }
        },

        {
            id = "latin",
            label = "Latin",
            preampDb = -2,
            bands = { 5, 4, 2, 1, 0, 1, 2, 3, 4, 4 }
        },

        {
            id = "loudness",
            label = "Loudness",
            preampDb = 3,
            compressorEnabled = true,
            bands = { 7, 6, 4, 1, -1, -2, -1, 1, 3, 4 }
        },

        {
            id = "lounge",
            label = "Lounge",
            preampDb = -1,
            bands = { 3, 2, 1, 1, 0, 0, 1, 2, 2, 2 }
        },

        {
            id = "piano",
            label = "Piano",
            preampDb = 0,
            bands = { -1, 0, 0, 1, 2, 3, 3, 2, 1, 1 }
        },

        {
            id = "pop",
            label = "Pop",
            preampDb = -2,
            bands = { 0, 1, 3, 4, 2, 0, -1, 1, 3, 4 }
        },

        {
            id = "rnb",
            label = "RnB",
            preampDb = -3,
            bands = { 8, 8, 6, 3, 0, -1, -2, -1, 1, 2 }
        },

        {
            id = "rock",
            label = "Rock",
            preampDb = -2,
            bands = { 5, 4, 2, 0, -1, 0, 2, 3, 4, 4 }
        },

        {
            id = "small_speakers",
            label = "Small Speakers",
            preampDb = -4,
            highpassEnabled = true,
            bands = { -12, -10, -7, -4, -1, 2, 4, 5, 4, 2 }
        },

        {
            id = "spoken_word",
            label = "Spoken word",
            preampDb = -2,
            highpassEnabled = true,
            bands = { -12, -10, -8, -4, 0, 4, 6, 4, 2, 0 }
        },

        {
            id = "treble_booster",
            label = "Treble booster",
            preampDb = -2,
            bands = { -4, -4, -3, -2, 0, 2, 4, 6, 8, 10 }
        },

        {
            id = "treble_reducer",
            label = "Treble reducer",
            preampDb = 0,
            bands = { 0, 0, 0, -1, -2, -2, -1, 0, -2, -4 }
        },

        {
            id = "vocal_booster",
            label = "Vocal booster",
            preampDb = -2,
            bands = { -4, -5, -4, -2, 1, 4, 6, 5, 3, 1 }
        },
    },
}

-- ═══════════════════════════════════════════════════════════════
--  SPEAKERS MODEL LIST
-- ═══════════════════════════════════════════════════════════════

Config.speakers.models                 = Config.speakers.models or {
    { model = "sf_prop_sf_speaker_l_01a",       label = "Large Speaker" },
    { model = "ba_prop_battle_club_speaker_dj", label = "Extra Large Speaker" },
    { model = "h4_prop_battle_dj_kit_speaker",  label = "Speaker in a box" },
    { model = "prop_speaker_02",                label = "Thin Speaker" },
    { model = "prop_speaker_05",                label = "Wooden Large Speaker" },
    { model = "sf_prop_sf_speaker_stand_01a",   label = "Speaker Stand" },
}

Config.audioVisualizations             = {
    ["bars"]            = { name = "Bars" },
    ["bars blocks"]     = { name = "Blocky Bars" },
    ["cubes"]           = { name = "Cubes" },
    ["dualbars"]        = { name = "Dual Bars" },
    ["dualbars blocks"] = { name = "Blocky Dual Bars" },
    ["fireworks"]       = { name = "Fireworks" },
    ["flower"]          = { name = "Flower" },
    ["flower blocks"]   = { name = "Blocky Flower" },
    ["orbs"]            = { name = "Orbs" },
    ["ring"]            = { name = "Ring" },
    ["rings"]           = { name = "Rings" },
    ["round wave"]      = { name = "Round Wave" },
    ["shine"]           = { name = "Shine" },
    ["shine rings"]     = { name = "Shine Rings" },
    ["shockwave"]       = { name = "Shockwave" },
    ["star"]            = { name = "Star" },
    ["static"]          = { name = "Static" },
    ["stitches"]        = { name = "Stitches" },
    ["web"]             = { name = "Web" },
    ["wave"]            = { name = "Wave" },
}
