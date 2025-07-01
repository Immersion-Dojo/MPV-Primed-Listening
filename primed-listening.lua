-- primed_listening.lua  (2025-06-30)
--
--  n          : toggle Primed Listening on/off (no play/pause side-effects)
--  Cmd+n / Cmd+b (macOS) or Ctrl+n / Ctrl+b (Windows/Linux):
--               - Cmd/Ctrl+n  ↑ pause_per_char by 0.01 s
--               - Cmd/Ctrl+b  ↓ pause_per_char by 0.01 s  (min 0.01)
--  SPACE / p   : when playback is paused *by this script* …
--                  • 1st press → cancel auto-resume, keep paused
--                  • 2nd press → resume playback
--  Manual pause by the user (or enabling the script while already paused)
--      enters the same "stand-by / 待機" mode: subs stay visible and
--      the next pause-key press resumes playback.
--
--  All settings are stored in / loaded from:
--      ~/.config/mpv/script-opts/primed_listening.conf


--------------------------- DEFAULTS -----------------------------
-- These defaults are only used if not found in config file
local settings = {
    pause_per_char = 0.06,              -- seconds paused *per character*
    min_pause = 0.50,                   -- never pause for less than this
    min_chars = 2,                      -- ignore subs shorter than this
    min_ppc = 0.01,                     -- floor for pause_per_char
    subtitle_delay_adjustment = -0.15,  -- pause timing relative to original subtitle start time
    style_blacklist = "sign,fx,song,title,op*,ed*"  -- comma-separated list of style words to filter out (supports * wildcard)
}


------------------------ LOAD / SAVE OPTS ------------------------
local conf_name = "primed_listening.conf"

local function conf_path()
    return mp.command_native({ "expand-path", "~~/script-opts/" .. conf_name })
end

local function save_opts()
    local f = io.open(conf_path(), "w+")
    if not f then
        mp.msg.error("primed listening: cannot write options file")
        return
    end
    
    -- Write all settings to file
    f:write("# primed_listening.conf - Auto-generated settings file\n")
    f:write("# Edit values as needed. New settings will be added automatically.\n\n")
    
    -- Sort keys for consistent file output
    local keys = {}
    for k in pairs(settings) do
        table.insert(keys, k)
    end
    table.sort(keys)
    
    for _, key in ipairs(keys) do
        local value = settings[key]
        if type(value) == "number" then
            f:write(("%s=%.4f\n"):format(key, value))
        else
            f:write(("%s=%s\n"):format(key, tostring(value)))
        end
    end
    
    f:close()
end

local function load_opts()
    local loaded_settings = {}
    
    -- Try to read existing config file
    local f = io.open(conf_path(), "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(%S+)")
            if k and v then
                loaded_settings[k] = tonumber(v) or v
            end
        end
        f:close()
    end
    
    -- Apply loaded settings, keeping defaults for missing values
    for key, default_value in pairs(settings) do
        if loaded_settings[key] ~= nil then
            settings[key] = loaded_settings[key]
        end
    end
    
    -- Save the complete config (this will add any new settings with defaults)
    save_opts()
end


-- Load settings on script start
load_opts()


--------------------- GLOBAL VARIABLES --------------------------
local enabled                = false  -- script master switch
local timer                  = nil    -- auto-resume timer
local awaiting_second_press  = false  -- pause-lock flag
local last_dialogue_text 	 = ""  	  -- buffer to detect repeated lines (countermeasure for animated sub styling tricks)
local original_sub_delay 	 = nil	  -- storage for pre existing user sub timing adjustment


--------------------- UTILITY FUNCTIONS -------------------------
local pause_keys = { "SPACE", "p", "MBTN_LEFT" }


--Detect operating system and set appropriate modifier key 
local function get_modifier_key()
    local platform = mp.get_property("platform")
    if platform == "darwin" then
        return "CMD"
    else
        return "Ctrl"
    end
end

local modifier_key = get_modifier_key()


local function count_characters(text)
    if not text or text == "" then return 0 end

    -- Remove ASS override tags like {\i1}, {\an8}, {\fad(...)}, etc.
    text = text:gsub("{\\[^}]+}", "")
    text = text:gsub("{[^}]+}", "")

    -- Remove all whitespace (spaces, tabs, newlines)
    text = text:gsub("%s+", "")

    -- Count UTF-8 characters (handles multibyte scripts properly)
    local count = 0
    for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
    end

	-- mp.msg.info("[char count] " .. count)
    return count
end

function get_subtitle_line()

		-- get verbose raw subtitle line data to filter based on .ASS styling (for simple .srt lines this just returns plaintext)
    local ass_full = mp.get_property("sub-text/ass-full")
    if not ass_full then return nil end

    -- Parse the style blacklist into a table
    local blacklist = {}
    for word in settings.style_blacklist:gmatch("[^,]+") do
        blacklist[word:gsub("^%s*(.-)%s*$", "%1"):lower()] = true
    end

    for line in ass_full:gmatch("[^\r\n]+") do
        -- Format: Dialogue: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
		local dialogue_parts = {}
		local remaining = line
		
		-- ASS files separate fields with commas, but only up to the "Text" field, which is the 10th field. 
		-- After that, everything is part of the subtitle text—even if it contains commas, quotes, formatting, or newlines.
		
		for i = 1, 9 do
			local part
			part, remaining = remaining:match("([^,]*),(.*)")
			table.insert(dialogue_parts, part or "")
		end

		-- remaining now contains the full text field (with all commas, tags, etc.)
		local style = dialogue_parts[4] or ""
		local text = remaining or ""

--		mp.msg.info("[raw line] " .. text)

        -- Filter signs based on style or formatting
		-- replace just the style test block
		local style_lower = style:lower()

		local function has_word(s, w)
			return s:match("%f[%a]"..w.."%f[%A]") ~= nil
		end

		local function matches_pattern(style, pattern)
			-- Check if pattern contains wildcard
			if pattern:find("*", 1, true) then
				-- Convert wildcard pattern to Lua pattern
				-- Escape special pattern characters except *
				local lua_pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-?])", "%%%1")
				-- Replace * with .*
				lua_pattern = lua_pattern:gsub("%*", ".*")
				-- Add anchors to match the whole string
				lua_pattern = "^" .. lua_pattern .. "$"
				return style:match(lua_pattern) ~= nil
			else
				-- No wildcard, use original word boundary matching
				return has_word(style, pattern)
			end
		end

		-- Check if style contains any blacklisted words
		local is_blacklisted = false
		for pattern in pairs(blacklist) do
			if matches_pattern(style_lower, pattern) then
				is_blacklisted = true
				break
			end
		end

		-- Only process if not blacklisted
		if not is_blacklisted then
			local clean_text = text:gsub("{\\[^}]+}", ""):gsub("{[^}]+}", ""):gsub("^%s*(.-)%s*$", "%1")
			return clean_text
		end
    end

    return nil
end

local function remove_pause_key_bindings()
    for _, key in ipairs(pause_keys) do
        mp.remove_key_binding("pl-first-" .. key)
        mp.remove_key_binding("pl-second-" .. key)
    end
end

local function release_script_control()
    if timer then timer:kill(); timer = nil end
    awaiting_second_press = false
    remove_pause_key_bindings()
end


-- Bindings for the *second* press (resume playback)
local function resume_playback()
    release_script_control()
    mp.set_property_bool("pause", false)
end

local function add_second_press_bindings()
    awaiting_second_press = true
    remove_pause_key_bindings()
    for _, key in ipairs(pause_keys) do
        mp.add_forced_key_binding(key, "pl-second-" .. key, resume_playback)
    end
end


-- First-press handler used when the script paused playback 
local function lock_pause()
    if timer then timer:kill(); timer = nil end
    mp.osd_message("Pause locked — press again to resume")
    add_second_press_bindings()
end


----------------------- CORE FUNCTION ---------------------------


local function pause_for_current_sub()
    local text  = get_subtitle_line()
    if not text or text == "" then return end
	
	-- check if line is identical to the last one
    if text == last_dialogue_text then return end
    last_dialogue_text = text

	-- check if line is below minimum characters
    local chars = count_characters(text)
    if chars < settings.min_chars then return end

	-- calculate duration
    local duration = math.max(settings.min_pause, chars * settings.pause_per_char)

    mp.set_property_bool("sub-visibility", true)
    mp.set_property_bool("pause", true)

    timer = mp.add_timeout(duration, resume_playback)
    remove_pause_key_bindings()
    for _, key in ipairs(pause_keys) do
        mp.add_forced_key_binding(key, "pl-first-" .. key, lock_pause)
    end
end


------------------------ OBSERVERS ------------------------------
local function on_sub_text_change(_, new_value)
    if not enabled or awaiting_second_press then return end
    if new_value and new_value ~= "" then pause_for_current_sub() end
end

local function on_pause_change(_, paused)
    if not enabled then return end
    mp.set_property_bool("sub-visibility", paused)

    if paused then
        if not timer and not awaiting_second_press then
            add_second_press_bindings()
        end
    else
        release_script_control()
    end
end


---------------------- TOGGLE HANDLER ---------------------------
local function set_enabled(state)
    if state == enabled then return end
    enabled = state

    release_script_control()

    if enabled then
        local currently_paused = mp.get_property_bool("pause")
        if currently_paused then
            add_second_press_bindings()
            mp.set_property_bool("sub-visibility", true)
        end
		
        -- Store the current sub-delay and apply adjustment
        original_sub_delay = mp.get_property_number("sub-delay") or 0
        mp.set_property_number("sub-delay", original_sub_delay + settings.subtitle_delay_adjustment)
		
        mp.observe_property("sub-text", "string", on_sub_text_change)
        mp.observe_property("pause",    "bool",   on_pause_change)
        mp.osd_message("Primed Listening ENABLED")
    else
	    -- Restore original sub delay if script changed it
        if original_sub_delay ~= nil then
            mp.set_property_number("sub-delay", original_sub_delay)
            original_sub_delay = nil
        end
        mp.unobserve_property(on_sub_text_change)
        mp.unobserve_property(on_pause_change)
        mp.set_property_bool("sub-visibility", true)
        mp.osd_message("Primed Listening DISABLED")
    end
end


--------------------- PPC DISPLAY / UPDATE ----------------------
local function show_ppc()
    mp.osd_message(("pause_per_char = %.2f s/char"):format(settings.pause_per_char), 1.2)
    save_opts()
end


----------------------- KEY BINDINGS ----------------------------
mp.add_key_binding("n", "toggle-primed-listening", function()
    set_enabled(not enabled)
end)

-- Use platform-appropriate modifier key
mp.add_key_binding(modifier_key .. "+n", "increase-ppc", function()
    settings.pause_per_char = settings.pause_per_char + 0.01
    show_ppc()
end)

mp.add_key_binding(modifier_key .. "+b", "decrease-ppc", function()
    settings.pause_per_char = math.max(settings.min_ppc, settings.pause_per_char - 0.01)
    show_ppc()
end)
