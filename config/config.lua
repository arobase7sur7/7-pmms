-- Root table for all 7-PMMS settings; keep this as an empty table.
Config                                 = {}


-- Command prefix for registered PMMS commands; use a short lowercase string.
Config.commandPrefix                   = "pmms"
-- Separator inserted between command prefix and command name; use a string such as "_".
Config.commandSeparator                = "_"

-- Maximum distance for discovering nearby media devices; use meters.
Config.maxDiscoveryDistance            = 30.0
-- Movement threshold before refreshing nearby discovery; use meters.
Config.discoveryUpdateDistance         = 10.0
-- Default audible range for new devices; use meters.
Config.defaultRange                    = 30.0
-- Maximum range normal players can set; use meters.
Config.maxRange                        = 200.0
-- Maximum range staff controls can set; use meters.
Config.adminMaxRange                   = 10000.0
-- Seconds before inactive device sessions are cleaned up; use 0 or more.
Config.deviceIdleResetSeconds          = 300
-- Default device volume percent; use 0 to 100.
Config.defaultVolume                   = 100
-- Whether new devices default to vehicle behavior; true or false.
Config.defaultVehicleMode              = false
-- Default screen size for video render targets; use a positive number.
Config.defaultVideoSize                = 30
-- Initial search provider key in the UI; use a key from Config.searchSources.
Config.defaultSearchSource             = "youtube"
-- Default fade or transition duration; use seconds.
Config.defaultTransitionSeconds        = 5.0
-- Maximum allowed transition duration; use seconds.
Config.maxTransitionSeconds            = 15.0

-- Enables in-game NUI notifications; true or false.
Config.showNotifications               = true
-- Default notification lifetime; use milliseconds.
Config.notificationDuration            = 5000

-- Allows players to control media from vehicles; true or false.
Config.allowPlayingFromVehicles        = true
-- Disables GTA static emitters near active devices; true or false.
Config.autoDisableStaticEmitters       = true
-- Disables idle camera while UI or playback is active; true or false.
Config.autoDisableIdleCam              = true
-- Disables vehicle radio while PMMS is active; true or false.
Config.autoDisableVehicleRadio         = true

-- Hosted player settings; use a table.
Config.player                          = {
    -- Backward-compatible alias for Config.dui.urls.https; use the hosted DUI runtime URL.
    hostedPlayerUrl = "https://kibook.github.io/pmms-dui/",
    -- Enables hosted DUI playback when selected by the resolver; true or false.
    useHostedPlayer = true,
}

-- Debug logging category switches; use a table of booleans.
Config.debug                           = {
    -- Sets enabled for this section. Use true or false.
    enabled = false,

    -- Enables every debug category when debug is enabled; true or false.
    all = false,

    -- Hosted player settings; use a table.
    player = false,
    -- Resolver debug or resolver configuration section depending on scope; use a table or boolean.
    resolver = false,
    -- Enables favorite-library debug logging; true or false.
    favorites = false,
    -- DUI runtime configuration or debug switch depending on scope; use a table or boolean.
    dui = false,
    -- NUI debug logging switch; true or false.
    nui = false,
    -- Search service settings; use a table.
    search = false,
    -- Database debug logging switch; true or false.
    database = false,
    -- Targeting debug logging switch; true or false.
    target = false,
    -- Permission system configuration or debug switch depending on scope; use a table or boolean.
    permissions = false,
}

-- NUI behavior limits; use a table.
Config.ui                              = {
    -- Maximum history rows synced to clients; use 0 or more.
    maxHistorySyncItems = 30,
}

-- Network synchronization timing settings; use a table.
Config.sync                            = {
    -- Minimum delay between normal state syncs; use milliseconds.
    throttleMs = 500,
    -- Interval for full state snapshots; use milliseconds.
    fullSyncIntervalMs = 30000,
    -- Interval for playback drift correction checks; use seconds.
    driftCheckIntervalS = 30,
    -- Maximum accepted playback drift before correction; use seconds.
    maxDriftSeconds = 2.0,
    -- Random join offset to avoid synchronized spikes; use milliseconds.
    joinJitterMs = 500,
}

-- Admin UI and control settings; use a table.
Config.admin                           = {
    -- Admin quick-action visibility settings; use a table.
    quickActions = {
        -- Shows the apply-profile quick action; true or false.
        applyProfiles = true,
        -- Shows the extended-range toggle quick action; true or false.
        extendedRangeToggle = true,
    },
    -- Admin log settings; use a table.
    logs = {
        -- Maximum admin log rows kept in memory; use 1 or more.
        maxEntries = 150,
    },
}

-- Playlist limits; use a table.
Config.playlists                       = {
    -- Maximum playlists per player; use 0 or more.
    maxCount = 50,
    -- Maximum favorite playlists per player; use 0 or more.
    maxFavorites = 10,
}

-- Search service settings; use a table.
Config.search                          = {
    -- Minimum visible busy time for search loading states; use milliseconds.
    minimumBusyMs = 500,
    -- Maximum provider instances used for search or resolver fallback; use 1 or more.
    maxInstances = 8,
    -- Cooldown after a provider instance fails; use seconds.
    instanceFailureCooldownSeconds = 600,
    -- Routes remote thumbnails through the server proxy; true or false.
    proxyThumbnails = true,
    -- Thumbnail proxy timeout; use milliseconds.
    thumbnailProxyTimeoutMs = 1500,
}

-- Direct media-link validation settings; use a table.
Config.directLinks                     = {
    -- Requires HTTPS direct links when true; true or false.
    requireHttps = true,
    -- Timeout for direct link probes; use milliseconds.
    probeTimeoutMs = 2500,
    -- Direct media extensions allowed by the probe; use lowercase strings.
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

-- Playback queue behavior; use a table.
Config.queue                           = {
    -- Number of upcoming queue items sent to clients; use 0 or more.
    lookaheadCount = 1,
}

-- Friend and suggestion settings; use a table.
Config.social                          = {
    -- Days before recent-player suggestions expire; use 1 or more.
    recentPlayerExpiryDays = 30,
    -- Maximum player suggestions returned to the UI; use 0 or more.
    maxSuggestions = 10,
}

-- Target integration settings; use a table.
Config.targeting                       = {
    -- Targeting system; use "fallback", "qb-target", or "ox_target".
    system = "qb-target",
    -- Display label shown in UI; use a short English string.
    label = "Open Media",
    -- Font Awesome icon class shown by target systems; use a string.
    icon = "fas fa-music",
    -- Interaction distance for target systems; use meters.
    distance = 2.0,
}

-- Permission system configuration or debug switch depending on scope; use a table or boolean.
Config.permissions                     = {
    -- Mode value for the current section; use the documented string values.
    mode = "hybrid",

    -- ACE permissions accepted as admin fallbacks; use permission strings.
    adminAceFallbacks = { "command", "command.pmms", "god", "admin", "group.admin", "qbcore.god", "qbcore.admin", "command.tpm", "command.addpermission" },

    -- QBCore permission integration settings; use a table.
    qbcore = {
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Resource name used for framework lookup; use an installed resource name.
        resource = "qb-core",
        -- Allows ACE fallback when framework permission fails; true or false.
        aceFallback = true,
        -- Framework permission names treated as admin; use strings.
        adminPermissions = { "god", "admin" },
    },
}

-- Reusable device profile presets; use keyed tables.
Config.deviceProfiles                  = {
    -- Club device profile preset; edit or remove as needed.
    club = {
        -- Display label shown in UI; use a short English string.
        label = "Club",
        -- Audible range for this profile or device; use meters.
        range = 80.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 80,
        -- Maximum allowed volume percent for this profile; use 0 to 100.
        maxVolume = 100,
        -- Loop mode for this profile; use "off", "track", "queue", "shuffle_once", or "shuffle_loop".
        loopMode = "queue",
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "pending",
    },
    -- DJ booth device profile preset; edit or remove as needed.
    dj_booth = {
        -- Display label shown in UI; use a short English string.
        label = "DJ Booth",
        -- Audible range for this profile or device; use meters.
        range = 65.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 85,
        -- Maximum allowed volume percent for this profile; use 0 to 100.
        maxVolume = 100,
        -- Loop mode for this profile; use "off", "track", "queue", "shuffle_once", or "shuffle_loop".
        loopMode = "queue",
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "pending",
    },
    -- Cinema device profile preset; edit or remove as needed.
    cinema = {
        -- Display label shown in UI; use a short English string.
        label = "Cinema",
        -- Audible range for this profile or device; use meters.
        range = 120.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 70,
        -- Marks this profile as video-focused; true or false.
        videoOnly = true,
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "disabled",
    },
    -- Radio device profile preset; edit or remove as needed.
    radio = {
        -- Display label shown in UI; use a short English string.
        label = "Radio",
        -- Audible range for this profile or device; use meters.
        range = 45.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 60,
        -- Loop mode for this profile; use "off", "track", "queue", "shuffle_once", or "shuffle_loop".
        loopMode = "queue",
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "queue",
    },
    -- Vehicle device profile preset; edit or remove as needed.
    vehicle = {
        -- Display label shown in UI; use a short English string.
        label = "Vehicle",
        -- Audible range for this profile or device; use meters.
        range = 35.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 65,
        -- Marks this profile as vehicle-bound; true or false.
        isVehicle = true,
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "queue",
    },
    -- Event device profile preset; edit or remove as needed.
    event = {
        -- Display label shown in UI; use a short English string.
        label = "Event",
        -- Audible range for this profile or device; use meters.
        range = 150.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 80,
        -- Maximum allowed volume percent for this profile; use 0 to 100.
        maxVolume = 100,
        -- Loop mode for this profile; use "off", "track", "queue", "shuffle_once", or "shuffle_loop".
        loopMode = "queue",
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "pending",
    },
    -- Staff-only device profile preset; edit or remove as needed.
    staff = {
        -- Display label shown in UI; use a short English string.
        label = "Staff Device",
        -- Audible range for this profile or device; use meters.
        range = 60.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 75,
        -- Default administrative lock for this profile; use a table.
        adminLock = { mode = "admin" },
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "disabled",
    },
    -- Public device profile preset; edit or remove as needed.
    public = {
        -- Display label shown in UI; use a short English string.
        label = "Public Device",
        -- Audible range for this profile or device; use meters.
        range = 30.0,
        -- Default volume percent for this profile; use 0 to 100.
        volume = 60,
        -- Request handling mode; use "queue", "pending", or "disabled".
        requestMode = "queue",
    },
}

-- Listener request settings; use a table.
Config.requests                        = {
    -- Sets enabled for this section. Use true or false.
    enabled = true,
    -- Default request mode; use "queue", "pending", or "disabled".
    defaultMode = "queue",
    -- Maximum pending requests per player per device; use 0 or more.
    maxPendingPerPlayer = 3,
    -- Seconds before pending requests expire; use 1 or more.
    pendingExpireSeconds = 600,
    -- Allows current device host to approve requests; true or false.
    hostCanApprove = true,
    -- Framework jobs allowed to approve requests; use job names mapped to grades.
    approverJobs = {
    },
}

-- Linked speaker settings; use a table.
Config.speakers                        = {
    -- Sets enabled for this section. Use true or false.
    enabled = true,
    -- Maximum linked speakers normal players can create; use 0 or more.
    normalPlayerLimit = 3,
    -- Maximum linked speakers staff can create; use -1 for unlimited.
    staffLimit = -1,
    -- Keeps staff speaker devices persistent; true or false.
    persistentForStaffDevices = true,
    -- Reduces echo between linked speakers; true or false.
    avoidEcho = true,
    -- Default speaker prop model name; use a GTA model string.
    propModel = Config.defaultModel or "sf_prop_sf_speaker_l_01a",
}


-- Default same-room attenuation amount; use a positive number.
Config.defaultSameRoomAttenuation      = 4.0
-- Default different-room attenuation amount; use a positive number.
Config.defaultDiffRoomAttenuation      = 6.0
-- Default cross-room volume multiplier; use 0.0 to 1.0.
Config.defaultDiffRoomVolume           = 0.25
-- Enables room filtering by default; true or false.
Config.enableFilterByDefault           = false
-- Volume falloff curve exponent; use a positive number.
Config.rangeCurveExponent              = 1.6


-- DUI runtime configuration or debug switch depending on scope; use a table or boolean.
Config.dui                             = {
    -- DUI render width in pixels; use a positive integer.
    screenWidth          = 1280,
    -- DUI render height in pixels; use a positive integer.
    screenHeight         = 720,
    -- DUI startup timeout; use milliseconds.
    timeout              = 30000,
    -- Maximum active DUI render FPS; use 1 to 60.
    renderMaxFps         = 144,
    -- Idle DUI render FPS; use 0 or more.
    renderIdleFps        = 5,
    -- Extra render distance beyond audible range; use meters.
    renderDistanceBuffer = 5.0,
    -- Caches DUI runtime assets locally; true or false.
    cacheRuntimeAssets   = true,
    -- Downscales HLS canvas rendering when possible; true or false.
    hlsCanvasDownscale   = true,
    -- Maximum HLS canvas width; use pixels.
    hlsCanvasMaxWidth    = 1920,
    -- Maximum HLS canvas height; use pixels.
    hlsCanvasMaxHeight   = 1080,
    -- Maximum HLS canvas FPS; use 1 to 60.
    hlsCanvasMaxFps      = 30,

    -- DUI YouTube-specific settings; use a table.
    youtube              = {
        -- Optional HTTPS URL for a separate YouTube player page; use empty string or URL.
        externalPlayerUrl = "https://cdpn.io/pen/debug/oNPzxKo",
        -- Uses external player before local DUI YouTube; true or false.
        preferExternalPlayer = true,

        -- Allows public front-end fallback candidates; true or false.
        allowFrontendFallback = false,
        -- Timeout per public front-end fallback candidate; use milliseconds.
        frontendFallbackTimeoutMs = 6000,
        -- Public front-end fallback instances; use tables with type and url.
        frontendInstances = {
            { type = "invidious", url = "https://yewtu.be" },
            { type = "invidious", url = "https://inv.nadeko.net" },
            { type = "piped", url = "https://piped.video" },
        },
    },

    -- Additional runtime URLs; use strings.
    urls                 = {
        -- Public HTTPS URL for the hosted DUI runtime; deploy http/dui_runtime here.
        https = "",
    },

    -- DUI runtime probe settings; use a table.
    probe                = {
        -- Sets enabled for this section. Use true or false.
        enabled = false,
        -- DUI startup timeout; use milliseconds.
        timeout = 4500,
        -- Provider order for this section; use provider key strings.
        order = { "local" },
        -- Prioritizes the last successful probe target; true or false.
        rememberLastGood = false,
    }
}

-- Resolver debug or resolver configuration section depending on scope; use a table or boolean.
Config.resolver                        = {
    -- Sets enabled for this section. Use true or false.
    enabled = true,
    -- Timeout for this section; use milliseconds.
    timeoutMs = 6000,
    -- Resolver cache lifetime; use seconds.
    cacheTtlSeconds = 1800,
    -- Maximum provider instances used for search or resolver fallback; use 1 or more.
    maxInstances = 6,
    -- Maximum parallel instances per provider; use 1 or more.
    parallelInstancesPerProvider = 2,
    -- Cooldown after a provider instance fails; use seconds.
    instanceFailureCooldownSeconds = 600,
    -- Cooldown before retrying a failed source; use seconds.
    sourceFailureCooldownSeconds = 900,
    -- Preferred audio language codes; use strings such as "en" or "und".
    audioLanguagePriority = { "original", "en", "en-US", "und" },

    -- Fallback provider order; use provider keys from this config.
    providerOrder = { "hosted_player", "chromium_youtube", "browser", "invidious", "piped", "page_scrape", "cobalt" },

    -- Browser YouTube behavior settings; use a table.
    browserYoutube = {
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Makes browser YouTube the primary YouTube path; true or false.
        primary = false,
        -- Hides manual provider selection in the UI; true or false.
        hideProviderSelector = false,
    },

    -- Resolver extractor settings; use a table.
    extractor = {
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Fallback provider order; use provider keys from this config.
        providerOrder = { "hosted_player", "chromium_youtube", "browser", "invidious", "piped", "page_scrape", "cobalt" },
        -- Allows public resolver fallbacks; true or false.
        allowPublicFallbacks = false,
        -- Timeout for this section; use milliseconds.
        timeoutMs = 9000,
        -- Provider cooldown after failures; use seconds.
        cooldownSeconds = 300,
        -- Maximum attempts per provider before moving on; use 1 or more.
        maxAttemptsPerProvider = 2,
        -- Maximum simultaneous resolver jobs; use 1 or more.
        maxGlobalConcurrent = 8,
        -- Hard resolver deadline; use seconds.
        absoluteTimeoutSeconds = 45,
        -- Delay ratio before starting backup providers; use 0.0 to 1.0.
        hedgeRatio = 0.6,
        -- Short provider penalty duration; use seconds.
        softBanDurationSeconds = 60,
        -- Long provider penalty duration; use seconds.
        hardBanDurationSeconds = 300,
        -- Per-provider concurrency and timeout settings; use a table.
        providers = {
            -- Cobalt provider settings; use a table.
            cobalt = { maxConcurrent = 4, timeoutSeconds = 12 },
            -- Invidious provider settings or instances; use a table.
            invidious = { maxConcurrent = 6, timeoutSeconds = 10 },
            -- Piped provider settings or instances; use a table.
            piped = { maxConcurrent = 6, timeoutSeconds = 10 },
            -- YouTube page-scrape fallback settings; use a table.
            page_scrape = { maxConcurrent = 4, timeoutSeconds = 10 },
        },
    },

    -- Cobalt provider settings; use a table.
    cobalt = {
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Cobalt API endpoints; use HTTPS URLs.
        endpoints = {
        },
        -- Optional Cobalt API key; leave empty when not required.
        apiKey = "",
        -- Header name used for Cobalt API key; use a string.
        apiKeyHeader = "Authorization",
        -- Prefix added before Cobalt API key; use a string or empty string.
        apiKeyPrefix = "Api-Key",
        -- Timeout for this section; use milliseconds.
        timeoutMs = 12000,
        -- Requests proxied Cobalt URLs where supported; true or false.
        alwaysProxy = true,
        -- Requested video quality; use strings such as "720".
        videoQuality = "720",
        -- Requested YouTube video codec; use strings such as "h264".
        youtubeVideoCodec = "h264",
        -- Requested YouTube video container; use strings such as "mp4".
        youtubeVideoContainer = "mp4",
        -- Requested audio format; use strings such as "mp3".
        audioFormat = "mp3",
        -- Requested audio bitrate; use strings such as "128".
        audioBitrate = "128",
    },

    -- Public provider instance URLs; use tables of HTTPS URLs.
    instances = {
        -- Invidious provider settings or instances; use a table.
        invidious = {
            "https://inv.nadeko.net",
            "https://yewtu.be",
            "https://invidious.nerdvpn.de",
            "https://yt.chocolatemoo53.com",
            "https://inv.thepixora.com",
        },

        -- Piped provider settings or instances; use a table.
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


    -- Allows audio-only fallback when video fails; true or false.
    allowAudioFallback = false,

    -- Allows embed fallback after resolver failure; true or false.
    allowEmbedFallback = false,

    -- Attempts fallback providers after primary failure; true or false.
    fallbackOnFailure = true,
    -- Shows a user warning when fallback is used; true or false.
    warnOnFallback = false,

    -- Retries resolver playback on client error; true or false.
    retryOnPlaybackError = true,
    -- Maximum retry count after playback errors; use 0 or more.
    retryAttempts = 1,

    -- Provider scoring settings; use a table.
    adaptiveProviderRanking = {
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Completed plays before provider score is trusted; use 0 or more.
        minCompletedPlays = 8,
        -- Samples required before provider ranking changes; use 0 or more.
        minProviderSamples = 2,
        -- Provider stats file path inside the resource; use a JSON path string.
        dataFile = "data/provider_stats.json",
        -- Delay before saving provider stats; use milliseconds.
        saveDebounceMs = 5000,
    },
}


-- Default scaleform renderer name; use a string.
Config.defaultScaleformName            = "pmms_texture_renderer"


-- Optional URL allowlist; leave empty to allow configured direct links.
Config.allowedUrls                     = {
    "^https?://w?w?w?%.?youtube.com/.*$",
    "^https?://w?w?w?%.?youtu.be/.*$",
    "^https?://w?w?w?%.?twitch.tv/.*$",
}


-- Preset definitions for this section; use a table.
Config.presets                         = {}


-- Default static media player definitions; use a table.
Config.defaultMediaPlayers             = {}
-- Spawn distance for default media players; use meters.
Config.defaultMediaPlayerSpawnDistance = Config.maxRange + 10.0


-- Default prop model for new devices; use a GTA model string.
Config.defaultModel                    = "sf_prop_sf_speaker_l_01a"


-- Known renderable prop model settings; use a keyed table.
Config.models                          = {
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

    ["bkr_prop_clubhouse_jukebox_01a"]  = { label = "Jukebox", isPlaceable = true },
    ["bkr_prop_clubhouse_jukebox_01b"]  = { label = "Jukebox", isPlaceable = true },
    ["bkr_prop_clubhouse_jukebox_02a"]  = { label = "Jukebox", isPlaceable = true },
    ["ch_prop_arcade_jukebox_01a"]      = { label = "Jukebox", isPlaceable = true },
    ["prop_50s_jukebox"]                = { label = "Jukebox", isPlaceable = true },
    ["prop_jukebox_01"]                 = { label = "Jukebox", isPlaceable = true },

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

    ["prop_monitor_w_large"]            = { label = "Monitor", renderTarget = "tvscreen", isPlaceable = true },
    ["prop_monitor_02"]                 = { label = "Monitor", renderTarget = "tvscreen", isPlaceable = true },

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

    ["hei_prop_dlc_tablet"]             = { label = "Tablet", renderTarget = "tablet", isPlaceable = true },
    ["ba_prop_battle_hacker_screen"]    = { label = "Tablet", renderTarget = "prop_battle_touchscreen_rt", isPlaceable = true },

    ["prop_big_cin_screen"]             = { label = "Cinema", renderTarget = "cinscreen", isPlaceable = true },
    ["v_ilev_cin_screen"]               = { label = "Cinema", renderTarget = "cinscreen", isPlaceable = true },

    ["v_ilev_lest_bigscreen"]           = { label = "Projector", renderTarget = "tvscreen", isPlaceable = true },
    ["v_ilev_mm_screen"]                = { label = "Projector", renderTarget = "big_disp", isPlaceable = true },
    ["v_ilev_mm_screen2"]               = { label = "Projector", renderTarget = "tvscreen", isPlaceable = true },
    ["hei_prop_dlc_heist_board"]        = { label = "Projector", renderTarget = "heist_brd", isPlaceable = true },

    ["ba_prop_battle_club_computer_01"] = { label = "Computer", renderTarget = "club_computer", isPlaceable = true },
    ["sm_prop_smug_monitor_01"]         = { label = "Computer", renderTarget = "smug_monitor_01", isPlaceable = true },
    ["ex_prop_monitor_01_ex"]           = { label = "Computer", renderTarget = "prop_ex_computer_screen", isPlaceable = true },

    ["prop_huge_display_01"]            = { label = "Screen", renderTarget = "big_disp", width = 1920, height = 1080, isPlaceable = true },
    ["prop_huge_display_02"]            = { label = "Screen", renderTarget = "big_disp", width = 1920, height = 1080, isPlaceable = true },
    ["xs_prop_arena_bigscreen_01"]      = { label = "Jumbotron", renderTarget = "bigscreen_01", width = 1920, height = 1080, isPlaceable = true },

    ["gr_prop_gr_trailer_monitor_01"]   = { label = "Monitor", renderTarget = "gr_trailer_monitor_01", isPlaceable = true },
    ["gr_prop_gr_trailer_monitor_02"]   = { label = "Monitor", renderTarget = "gr_trailer_monitor_02", isPlaceable = true },
    ["gr_prop_gr_trailer_monitor_03"]   = { label = "Monitor", renderTarget = "gr_trailer_monitor_03", isPlaceable = true },
    ["gr_prop_gr_trailer_tv"]           = { label = "TV", renderTarget = "gr_trailertv_01", isPlaceable = true },
    ["gr_prop_gr_trailer_tv_02"]        = { label = "TV", renderTarget = "gr_trailertv_02", isPlaceable = true },

    ["hei_prop_hei_monitor_overlay"]    = { label = "Monitor", renderTarget = "hei_mon", isPlaceable = true },
    ["hei_prop_hei_muster_01"]          = { label = "Whiteboard", renderTarget = "planning", isPlaceable = true },
    ["xm_prop_orbital_cannon_table"]    = { label = "Orbital Cannon", renderTarget = "orbital_table", isPlaceable = true },
    ["sr_mp_spec_races_blimp_sign"]     = { label = "Blimp", renderTarget = "blimp_text", isPlaceable = true },
    ["xm_prop_x17_sec_panel_01"]        = { label = "Panel", renderTarget = "prop_x17_p_01", isPlaceable = true },

    ["xm_prop_x17_tv_flat_01"]          = { label = "TV", renderTarget = "tv_flat_01", isPlaceable = true },
    ["sm_prop_smug_tv_flat_01"]         = { label = "TV", renderTarget = "tv_flat_01", isPlaceable = true },
    ["xm_prop_x17_computer_02"]         = { label = "Monitor", renderTarget = "monitor_02", isPlaceable = true },
    ["xm_prop_x17dlc_monitor_wall_01a"] = { label = "Screen", renderTarget = "prop_x17dlc_monitor_wall_01a", isPlaceable = true },

    ["xm_prop_x17_screens_02a_01"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_01", isPlaceable = true },
    ["xm_prop_x17_screens_02a_02"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_02", isPlaceable = true },
    ["xm_prop_x17_screens_02a_03"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_03", isPlaceable = true },
    ["xm_prop_x17_screens_02a_04"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_04", isPlaceable = true },
    ["xm_prop_x17_screens_02a_05"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_05", isPlaceable = true },
    ["xm_prop_x17_screens_02a_06"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_06", isPlaceable = true },
    ["xm_prop_x17_screens_02a_07"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_07", isPlaceable = true },
    ["xm_prop_x17_screens_02a_08"]      = { label = "Screen", renderTarget = "prop_x17_8scrn_08", isPlaceable = true },

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

    ["xs_prop_arena_screen_tv_01"]      = { label = "TV", renderTarget = "screen_tv_01" },

    ["vw_prop_vw_arcade_01_screen"]     = { label = "Arcade Machine", renderTarget = "arcade_01a_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02_screen"]     = { label = "Arcade Machine", renderTarget = "arcade_02a_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02b_screen"]    = { label = "Arcade Machine", renderTarget = "arcade_02b_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02c_screen"]    = { label = "Arcade Machine", renderTarget = "arcade_02c_screen", isPlaceable = true },
    ["vw_prop_vw_arcade_02d_screen"]    = { label = "Arcade Machine", renderTarget = "arcade_02d_screen", isPlaceable = true },

    ["apa_mp_h_str_avunitl_01_b"]       = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunitl_04"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunitm_01"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunitm_03"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunits_01"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["apa_mp_h_str_avunits_04"]         = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },
    ["hei_heist_str_avunitl_03"]        = { label = "TV", renderTarget = "tvscreen", isPlaceable = true },

    ["prop_phone_cs_frank"]             = { label = "Phone", renderTarget = "npcphone" },
    ["prop_phone_proto"]                = { label = "Phone", renderTarget = "npcphone" },

    ["w_am_digiscanner"]                = { label = "Digiscanner", renderTarget = "digiscanner" },

    ["pbus2"]                           = { attenuation = { sameRoom = 1.5, diffRoom = 6 }, range = 100, isVehicle = false },
    ["blimp3"]                          = { attenuation = { sameRoom = 0.6, diffRoom = 6 }, range = 150, isVehicle = false },
}


-- Search source definitions shown in the UI; use a keyed table.
Config.searchSources                   = {
    ["youtube"] = {
        -- Display label shown in UI; use a short English string.
        label = "YouTube",
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Font Awesome icon class shown by target systems; use a string.
        icon = "video",
        -- Input placeholder shown in the UI; use a short English string.
        placeholder = "Search YouTube...",
        -- Maximum results returned for this search source; use 1 or more.
        maxResults = 10,
        -- Cooldown between searches for this source; use seconds.
        cooldown = 2,
    },
    ["youtube_embed"] = {
        -- Display label shown in UI; use a short English string.
        label = "YouTube Embed",
        -- Sets enabled for this section. Use true or false.
        enabled = false,
        -- Font Awesome icon class shown by target systems; use a string.
        icon = "video",
        -- Input placeholder shown in the UI; use a short English string.
        placeholder = "Search YouTube (embed)...",
        -- Maximum results returned for this search source; use 1 or more.
        maxResults = 10,
        -- Cooldown between searches for this source; use seconds.
        cooldown = 2,
        -- YouTube provider key for this search source; use a configured provider string.
        youtubeProvider = "embed",
    },
    ["soundcloud"] = {
        -- Display label shown in UI; use a short English string.
        label = "SoundCloud",
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Font Awesome icon class shown by target systems; use a string.
        icon = "music",
        -- Input placeholder shown in the UI; use a short English string.
        placeholder = "Search SoundCloud...",
        -- Maximum results returned for this search source; use 1 or more.
        maxResults = 10,
        -- Cooldown between searches for this source; use seconds.
        cooldown = 2,
    },
    ["twitch"] = {
        -- Display label shown in UI; use a short English string.
        label = "Twitch",
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Font Awesome icon class shown by target systems; use a string.
        icon = "twitch",
        -- Input placeholder shown in the UI; use a short English string.
        placeholder = "Enter Twitch Username...",
        -- Maximum results returned for this search source; use 1 or more.
        maxResults = 10,
        -- Cooldown between searches for this source; use seconds.
        cooldown = 2,
        -- Optional Twitch client ID; leave empty to use direct channel handling.
        clientId = "",
        -- Optional Twitch client secret; leave empty unless custom API usage is enabled.
        clientSecret = "",
    },
    ["direct"] = {
        -- Display label shown in UI; use a short English string.
        label = "Direct",
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Font Awesome icon class shown by target systems; use a string.
        icon = "link",
        -- Input placeholder shown in the UI; use a short English string.
        placeholder = "Paste a direct media URL...",
        -- Maximum results returned for this search source; use 1 or more.
        maxResults = 1,
        -- Cooldown between searches for this source; use seconds.
        cooldown = 0,
    },
    ["radio"] = {
        -- Display label shown in UI; use a short English string.
        label = "Radio",
        -- Sets enabled for this section. Use true or false.
        enabled = true,
        -- Font Awesome icon class shown by target systems; use a string.
        icon = "radio",
        -- Input placeholder shown in the UI; use a short English string.
        placeholder = "Search radio stations...",
        -- Maximum results returned for this search source; use 1 or more.
        maxResults = 20,
        -- Cooldown between searches for this source; use seconds.
        cooldown = 2,
    }
}

-- Equalizer settings and presets; use a table.
Config.equalizer                       = {
    -- Sets enabled for this section. Use true or false.
    enabled           = true,

    -- Maximum custom EQ presets per player; use 0 or more.
    maxCustomPresets  = 5,

    -- Enables EQ by default; true or false.
    defaultEnabled    = false,
    -- Default EQ preamp gain; use decibels.
    defaultPreampDb   = 0.0,
    -- Enables high-pass filter by default; true or false.
    defaultHighpass   = false,
    -- Enables compressor by default; true or false.
    defaultCompressor = false,

    -- EQ band values or frequencies; use numbers in table order.
    bands             = { 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 },

    -- Default EQ band gains; use decibel numbers matching Config.equalizer.bands.
    defaultBands      = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },

    -- Minimum gain per EQ band; use decibels.
    bandMinDb         = -15,
    -- Maximum gain per EQ band; use decibels.
    bandMaxDb         = 15,
    -- Minimum EQ preamp gain; use decibels.
    preampMinDb       = -8,
    -- Maximum EQ preamp gain; use decibels.
    preampMaxDb       = 8,

    -- Preset definitions for this section; use a table.
    presets           = {
        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "flat",
            -- Display label shown in UI; use a short English string.
            label = "Flat",
            -- Preset preamp gain; use decibels.
            preampDb = 0,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "acoustic",
            -- Display label shown in UI; use a short English string.
            label = "Acoustic",
            -- Preset preamp gain; use decibels.
            preampDb = -1,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -2, -1, 0, 1, 2, 2, 1, 2, 3, 3 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "bass_booster",
            -- Display label shown in UI; use a short English string.
            label = "Bass booster",
            -- Preset preamp gain; use decibels.
            preampDb = -4,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 10, 9, 7, 4, 1, 0, -1, -2, -3, -4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "bass_reducer",
            -- Display label shown in UI; use a short English string.
            label = "Bass reducer",
            -- Preset preamp gain; use decibels.
            preampDb = 0,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -10, -8, -6, -4, -2, -1, 0, 0, 0, 0 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "classical",
            -- Display label shown in UI; use a short English string.
            label = "Classical",
            -- Preset preamp gain; use decibels.
            preampDb = -1,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -1, -1, 0, 1, 2, 2, 2, 3, 3, 2 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "dance",
            -- Display label shown in UI; use a short English string.
            label = "Dance",
            -- Preset preamp gain; use decibels.
            preampDb = -3,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 7, 6, 4, 1, -1, -2, -1, 1, 3, 4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "deep",
            -- Display label shown in UI; use a short English string.
            label = "Deep",
            -- Preset preamp gain; use decibels.
            preampDb = -5,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 12, 10, 8, 4, 0, -2, -3, -3, -2, -2 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "electronic",
            -- Display label shown in UI; use a short English string.
            label = "Electronic",
            -- Preset preamp gain; use decibels.
            preampDb = -3,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 8, 7, 5, 2, 0, -1, 0, 2, 4, 4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "hiphop",
            -- Display label shown in UI; use a short English string.
            label = "HipHop",
            -- Preset preamp gain; use decibels.
            preampDb = -4,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 10, 10, 8, 5, 1, -1, -2, -1, 1, 2 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "jazz",
            -- Display label shown in UI; use a short English string.
            label = "Jazz",
            -- Preset preamp gain; use decibels.
            preampDb = -1,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 2, 2, 1, 1, 0, 0, 1, 2, 3, 3 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "latin",
            -- Display label shown in UI; use a short English string.
            label = "Latin",
            -- Preset preamp gain; use decibels.
            preampDb = -2,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 5, 4, 2, 1, 0, 1, 2, 3, 4, 4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "loudness",
            -- Display label shown in UI; use a short English string.
            label = "Loudness",
            -- Preset preamp gain; use decibels.
            preampDb = 3,
            -- Enables compressor for this preset; true or false.
            compressorEnabled = true,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 7, 6, 4, 1, -1, -2, -1, 1, 3, 4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "lounge",
            -- Display label shown in UI; use a short English string.
            label = "Lounge",
            -- Preset preamp gain; use decibels.
            preampDb = -1,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 3, 2, 1, 1, 0, 0, 1, 2, 2, 2 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "piano",
            -- Display label shown in UI; use a short English string.
            label = "Piano",
            -- Preset preamp gain; use decibels.
            preampDb = 0,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -1, 0, 0, 1, 2, 3, 3, 2, 1, 1 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "pop",
            -- Display label shown in UI; use a short English string.
            label = "Pop",
            -- Preset preamp gain; use decibels.
            preampDb = -2,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 0, 1, 3, 4, 2, 0, -1, 1, 3, 4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "rnb",
            -- Display label shown in UI; use a short English string.
            label = "RnB",
            -- Preset preamp gain; use decibels.
            preampDb = -3,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 8, 8, 6, 3, 0, -1, -2, -1, 1, 2 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "rock",
            -- Display label shown in UI; use a short English string.
            label = "Rock",
            -- Preset preamp gain; use decibels.
            preampDb = -2,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 5, 4, 2, 0, -1, 0, 2, 3, 4, 4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "small_speakers",
            -- Display label shown in UI; use a short English string.
            label = "Small Speakers",
            -- Preset preamp gain; use decibels.
            preampDb = -4,
            -- Enables high-pass filter for this preset; true or false.
            highpassEnabled = true,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -12, -10, -7, -4, -1, 2, 4, 5, 4, 2 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "spoken_word",
            -- Display label shown in UI; use a short English string.
            label = "Spoken word",
            -- Preset preamp gain; use decibels.
            preampDb = -2,
            -- Enables high-pass filter for this preset; true or false.
            highpassEnabled = true,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -12, -10, -8, -4, 0, 4, 6, 4, 2, 0 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "treble_booster",
            -- Display label shown in UI; use a short English string.
            label = "Treble booster",
            -- Preset preamp gain; use decibels.
            preampDb = -2,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -4, -4, -3, -2, 0, 2, 4, 6, 8, 10 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "treble_reducer",
            -- Display label shown in UI; use a short English string.
            label = "Treble reducer",
            -- Preset preamp gain; use decibels.
            preampDb = 0,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { 0, 0, 0, -1, -2, -2, -1, 0, -2, -4 }
        },

        {
            -- Stable identifier for this entry; use lowercase string keys.
            id = "vocal_booster",
            -- Display label shown in UI; use a short English string.
            label = "Vocal booster",
            -- Preset preamp gain; use decibels.
            preampDb = -2,
            -- EQ band values or frequencies; use numbers in table order.
            bands = { -4, -5, -4, -2, 1, 4, 6, 5, 3, 1 }
        },
    },
}


-- Known renderable prop model settings; use a keyed table.
Config.speakers.models                 = Config.speakers.models or {
    { model = "sf_prop_sf_speaker_l_01a",       label = "Large Speaker" },
    { model = "ba_prop_battle_club_speaker_dj", label = "Extra Large Speaker" },
    { model = "h4_prop_battle_dj_kit_speaker",  label = "Speaker in a box" },
    { model = "prop_speaker_02",                label = "Thin Speaker" },
    { model = "prop_speaker_05",                label = "Wooden Large Speaker" },
    { model = "sf_prop_sf_speaker_stand_01a",   label = "Speaker Stand" },
}

-- Audio visualization settings; use a table.
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
