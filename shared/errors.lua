PMMS_ERROR_MESSAGES = {
	invalid_playback_options = {
		title = "Playback",
		message = "Enter a playable media URL.",
		duration = 6500,
		type = "error",
	},
	invalid_url = {
		title = "Playback",
		message = "Enter a valid http or https media URL.",
		duration = 6500,
		type = "error",
	},
	resolver_timeout = {
		title = "Playback",
		message = "The media resolver timed out. Try again or choose another source.",
		duration = 7000,
		type = "error",
	},
	resolver_unplayable = {
		title = "Playback",
		message = "No fallback provider returned a playable stream.",
		duration = 7000,
		type = "error",
	},
	resolver_cancelled = {
		title = "Playback",
		message = "Media resolution was cancelled.",
		duration = 5000,
		type = "warning",
	},
	playback_start_timeout = {
		title = "Playback",
		message = "Playback startup timed out. Try another source.",
		duration = 7000,
		type = "error",
	},
	playback_start_failed = {
		title = "Playback",
		message = "Playback failed after retries. Try another source.",
		duration = 7000,
		type = "error",
	},
	local_playback_failed = {
		title = "Playback",
		message = "This client could not play the media source.",
		duration = 7000,
		type = "error",
	},
	player_busy = {
		title = "Playback",
		message = "This media player is busy. Wait for the current action to finish.",
		duration = 5000,
		type = "warning",
	},
	no_permission = {
		title = "Permission",
		message = "You do not have permission for this action.",
		duration = 6000,
		type = "error",
	},
	device_restricted = {
		title = "Device",
		message = "This device is restricted by staff.",
		duration = 6000,
		type = "error",
	},
	device_locked = {
		title = "Device",
		message = "This media player is locked.",
		duration = 6000,
		type = "error",
	},
	live_seek = {
		title = "Playback",
		message = "Live streams cannot be seeked.",
		duration = 5000,
		type = "warning",
	},
	playlist_empty = {
		title = "Library",
		message = "This playlist has no playable tracks.",
		duration = 5000,
		type = "warning",
	},
	action_failed = {
		title = "7-PMMS",
		message = "The action failed. Please try again.",
		duration = 6000,
		type = "error",
	},
}

local errorPatterns = {
	{ pattern = "resolver timed out", code = "resolver_timeout" },
	{ pattern = "timed out", code = "playback_start_timeout" },
	{ pattern = "resolver cancelled", code = "resolver_cancelled" },
	{ pattern = "cancelled", code = "resolver_cancelled" },
	{ pattern = "no fallback provider returned", code = "resolver_unplayable" },
	{ pattern = "no fallback provider is available", code = "resolver_unplayable" },
	{ pattern = "unable to resolve", code = "resolver_unplayable" },
	{ pattern = "invalid playback", code = "invalid_playback_options" },
	{ pattern = "invalid playback url", code = "invalid_url" },
	{ pattern = "must specify a url", code = "invalid_url" },
	{ pattern = "busy", code = "player_busy" },
	{ pattern = "permission", code = "no_permission" },
	{ pattern = "restricted", code = "device_restricted" },
	{ pattern = "locked", code = "device_locked" },
	{ pattern = "live streams", code = "live_seek" },
	{ pattern = "no playable tracks", code = "playlist_empty" },
}

local function copyErrorDefinition(definition)
	local copy = {}
	for key, value in pairs(definition or {}) do
		copy[key] = value
	end
	return copy
end

function GetPmmsErrorDefinition(code)
	return copyErrorDefinition(PMMS_ERROR_MESSAGES[tostring(code or "")] or PMMS_ERROR_MESSAGES.action_failed)
end

function ClassifyPmmsErrorCode(message, fallbackCode)
	local text = tostring(message or ""):lower()
	for _, entry in ipairs(errorPatterns) do
		if text:find(entry.pattern, 1, true) then
			return entry.code
		end
	end
	return fallbackCode or "action_failed"
end

function BuildPmmsErrorPayload(input, extra)
	local payload = {}
	if type(input) == "table" then
		for key, value in pairs(input) do
			payload[key] = value
		end
	else
		payload.message = tostring(input or "")
	end

	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end

	payload.code = payload.code or ClassifyPmmsErrorCode(payload.message or payload.detail, "action_failed")
	local definition = GetPmmsErrorDefinition(payload.code)
	payload.title = payload.title or definition.title
	payload.type = payload.type or definition.type or "error"
	payload.duration = tonumber(payload.duration or definition.duration) or 6000
	payload.message = payload.message or definition.message
	payload.fallbackMessage = definition.message
	return payload
end

function TriggerPmmsError(target, input, extra)
	if type(TriggerClientEvent) == "function" then
		TriggerClientEvent("pmms:error", target, BuildPmmsErrorPayload(input, extra))
	end
end
