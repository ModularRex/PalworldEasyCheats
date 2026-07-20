--[[
  PalworldEasyCheats - pure Lua hotkeys for Palworld (UE4SS)

  Hotkeys:
    + / numpad +     increase movement speed
    - / numpad -     decrease movement speed
    Alt + 0          reset movement speed to default
    Alt + J          toggle high jump
    Alt + F          toggle unlimited fuel
    Alt + S          toggle unlimited stamina
    Alt + G          toggle god mode (muteki) + full heal
    Alt + H          toggle disable hunger (player)

  settings.json only (no hotkey):
    matchSwimSpeed         - swim uses same mult as walk when true
    includePalsGodMode     - when god mode is on, also muteki + heal party pals
    includePalsHunger      - when no-hunger is on, also apply to pals
    revealMap              - set PalGameSetting.worldmapUIMaskClearSize large to clear fog
    skipModDisclaimer      - call PalGameInstance.SetAlreadyShowModDetectionDialog

  Settings:
    Scripts/settings.json  - created on first run, stores defaults + last state
]]

local UEHelpers = require("UEHelpers")
local Defaults = require("config")

local MOD = "PalworldEasyCheats"

-- ---------------------------------------------------------------------------
-- Settings path + JSON (minimal, no external deps)
-- ---------------------------------------------------------------------------

local function settingsPathCandidates()
    local paths = {}
    -- Prefer path next to this script
    local ok, info = pcall(debug.getinfo, 1, "S")
    if ok and info and info.source then
        local src = info.source
        if src:sub(1, 1) == "@" then
            src = src:sub(2)
        end
        local dir = src:match("^(.*)[/\\][^/\\]+$")
        if dir then
            table.insert(paths, dir .. "/settings.json")
            table.insert(paths, dir .. "\\settings.json")
        end
    end
    -- Common UE4SS / Palworld working directories
    table.insert(paths, "ue4ss/Mods/PalworldEasyCheats/Scripts/settings.json")
    table.insert(paths, "Mods/PalworldEasyCheats/Scripts/settings.json")
    table.insert(paths, "UE4SS/Mods/PalworldEasyCheats/Scripts/settings.json")
    table.insert(paths, "./ue4ss/Mods/PalworldEasyCheats/Scripts/settings.json")
    return paths
end

local function resolveSettingsPath()
    -- Prefer an existing file
    for _, p in ipairs(settingsPathCandidates()) do
        local f = io.open(p, "r")
        if f then
            f:close()
            return p
        end
    end
    -- Else first writable candidate
    for _, p in ipairs(settingsPathCandidates()) do
        local f = io.open(p, "w")
        if f then
            f:close()
            return p
        end
    end
    return "ue4ss/Mods/PalworldEasyCheats/Scripts/settings.json"
end

local SETTINGS_PATH = resolveSettingsPath()

local function jsonEscape(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end


-- Runtime Settings stays flat; save/load nest and flatten via this map.
local SETTINGS_LAYOUT = {
    {
        group = "movement",
        keys = {
            "speedMultiplier",
            "speedStep",
            "minSpeedMultiplier",
            "maxSpeedMultiplier",
            "defaultSpeedMultiplier",
            "matchSwimSpeed",
            "speedFlagName",
        },
    },
    {
        group = "jump",
        keys = {
            "highJumpEnabled",
            "jumpHeightMultiplier",
            "jumpFlagName",
        },
    },
    {
        group = "fuel",
        keys = {
            "infiniteFuel",
        },
    },
    {
        group = "stamina",
        keys = {
            "infiniteStamina",
        },
    },
    {
        group = "combat",
        keys = {
            "godModeEnabled",
            "includePalsGodMode",
            "godModeFlagName",
        },
    },
    {
        group = "hunger",
        keys = {
            "disableHunger",
            "includePalsHunger",
            "hungerFlagName",
        },
    },
    {
        group = "map",
        keys = {
            "revealMap",
            "revealMapClearSize",
        },
    },
    {
        group = "system",
        keys = {
            "skipModDisclaimer",
            "persistModifications",
            "maintainIntervalMs",
            "applyOnLoadDelayMs",
        },
    },
}

local SETTINGS_GROUP_NAMES = {}
for _, section in ipairs(SETTINGS_LAYOUT) do
    SETTINGS_GROUP_NAMES[section.group] = true
end

local function toJson(value, indent, keyOrder)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local padIn = string.rep("  ", indent + 1)
    local t = type(value)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "0"
        end
        -- Multipliers look like 1.0; large ints (ms) stay whole numbers
        if value == math.floor(value) then
            if math.abs(value) >= 100 then
                return string.format("%d", value)
            end
            return string.format("%.1f", value)
        end
        return tostring(value)
    elseif t == "string" then
        return '"' .. jsonEscape(value) .. '"'
    elseif t == "table" then
        local isArray = true
        local n = 0
        for k, _ in pairs(value) do
            n = n + 1
            if type(k) ~= "number" then
                isArray = false
                break
            end
        end
        if isArray and n == #value then
            local parts = {}
            for i = 1, #value do
                parts[#parts + 1] = padIn .. toJson(value[i], indent + 1)
            end
            if #parts == 0 then
                return "[]"
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        end

        local keys = {}
        local used = {}
        if type(keyOrder) == "table" then
            for _, k in ipairs(keyOrder) do
                if type(k) == "string" and value[k] ~= nil then
                    keys[#keys + 1] = k
                    used[k] = true
                end
            end
        end
        local rest = {}
        for k, _ in pairs(value) do
            if type(k) == "string" and not used[k] then
                rest[#rest + 1] = k
            end
        end
        table.sort(rest)
        for _, k in ipairs(rest) do
            keys[#keys + 1] = k
        end

        local parts = {}
        for _, k in ipairs(keys) do
            local childOrder = nil
            if type(value[k]) == "table" then
                -- Prefer layout order for known groups
                for _, section in ipairs(SETTINGS_LAYOUT) do
                    if section.group == k then
                        childOrder = section.keys
                        break
                    end
                end
            end
            parts[#parts + 1] = padIn
                .. '"'
                .. jsonEscape(k)
                .. '": '
                .. toJson(value[k], indent + 1, childOrder)
        end
        if #parts == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    end
    return "null"
end

-- Minimal recursive JSON parser (objects / arrays / numbers / bools / strings).
local function parseJson(str)
    if not str or str == "" then
        return {}
    end
    local i = 1
    local n = #str

    local function peek()
        return str:sub(i, i)
    end

    local function skip()
        while i <= n do
            local c = str:sub(i, i)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                i = i + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        i = i + 1 -- skip opening "
        local parts = {}
        while i <= n do
            local c = str:sub(i, i)
            if c == '"' then
                i = i + 1
                break
            elseif c == "\\" then
                local nextc = str:sub(i + 1, i + 1)
                if nextc == "n" then
                    parts[#parts + 1] = "\n"
                elseif nextc == "t" then
                    parts[#parts + 1] = "\t"
                elseif nextc == "r" then
                    parts[#parts + 1] = "\r"
                elseif nextc == '"' then
                    parts[#parts + 1] = '"'
                elseif nextc == "\\" then
                    parts[#parts + 1] = "\\"
                else
                    parts[#parts + 1] = nextc
                end
                i = i + 2
            else
                parts[#parts + 1] = c
                i = i + 1
            end
        end
        return table.concat(parts)
    end

    local function parseNumber()
        local start = i
        if peek() == "-" then
            i = i + 1
        end
        while i <= n and str:sub(i, i):match("%d") do
            i = i + 1
        end
        if peek() == "." then
            i = i + 1
            while i <= n and str:sub(i, i):match("%d") do
                i = i + 1
            end
        end
        if peek() == "e" or peek() == "E" then
            i = i + 1
            if peek() == "+" or peek() == "-" then
                i = i + 1
            end
            while i <= n and str:sub(i, i):match("%d") do
                i = i + 1
            end
        end
        return tonumber(str:sub(start, i - 1))
    end

    local function parseObject()
        local obj = {}
        i = i + 1 -- {
        skip()
        if peek() == "}" then
            i = i + 1
            return obj
        end
        while i <= n do
            skip()
            if peek() ~= '"' then
                break
            end
            local key = parseString()
            skip()
            if peek() == ":" then
                i = i + 1
            end
            skip()
            obj[key] = parseValue()
            skip()
            if peek() == "," then
                i = i + 1
            elseif peek() == "}" then
                i = i + 1
                break
            else
                break
            end
        end
        return obj
    end

    local function parseArray()
        local arr = {}
        i = i + 1 -- [
        skip()
        if peek() == "]" then
            i = i + 1
            return arr
        end
        while i <= n do
            skip()
            arr[#arr + 1] = parseValue()
            skip()
            if peek() == "," then
                i = i + 1
            elseif peek() == "]" then
                i = i + 1
                break
            else
                break
            end
        end
        return arr
    end

    parseValue = function()
        skip()
        local c = peek()
        if c == "{" then
            return parseObject()
        elseif c == "[" then
            return parseArray()
        elseif c == '"' then
            return parseString()
        elseif c == "t" and str:sub(i, i + 3) == "true" then
            i = i + 4
            return true
        elseif c == "f" and str:sub(i, i + 4) == "false" then
            i = i + 5
            return false
        elseif c == "n" and str:sub(i, i + 3) == "null" then
            i = i + 4
            return nil
        else
            return parseNumber()
        end
    end

    skip()
    local ok, result = pcall(parseValue)
    if ok and type(result) == "table" then
        return result
    end
    return {}
end

-- Accept nested groups (preferred) or legacy flat keys.
local function flattenSettingsOverlay(parsed)
    local flat = {}
    if type(parsed) ~= "table" then
        return flat
    end
    for k, v in pairs(parsed) do
        if SETTINGS_GROUP_NAMES[k] and type(v) == "table" then
            for kk, vv in pairs(v) do
                if vv ~= nil then
                    flat[kk] = vv
                end
            end
        elseif type(v) ~= "table" then
            flat[k] = v
        end
    end
    return flat
end

local function nestSettingsForSave(flat)
    local nested = {}
    for _, section in ipairs(SETTINGS_LAYOUT) do
        local group = {}
        for _, key in ipairs(section.keys) do
            if flat[key] ~= nil then
                group[key] = flat[key]
            end
        end
        nested[section.group] = group
    end
    return nested
end

local function defaultSettingsTable()
    return {
        speedStep = Defaults.SpeedStep or 0.25,
        minSpeedMultiplier = Defaults.MinSpeedMultiplier or 0.25,
        maxSpeedMultiplier = Defaults.MaxSpeedMultiplier or 10.0,
        defaultSpeedMultiplier = Defaults.DefaultSpeedMultiplier or 1.0,
        jumpHeightMultiplier = Defaults.JumpHeightMultiplier or 2.0,
        speedFlagName = Defaults.SpeedFlagName or "PalworldEasyCheats",
        jumpFlagName = Defaults.JumpFlagName or "PalworldEasyCheats",
        persistModifications = Defaults.PersistModifications ~= false,
        maintainIntervalMs = Defaults.MaintainIntervalMs or 10000,
        applyOnLoadDelayMs = Defaults.ApplyOnLoadDelayMs or 2000,
        -- Skip Pocketpair mod detection dialog (UE4SS: SetAlreadyShowModDetectionDialog)
        skipModDisclaimer = Defaults.SkipModDisclaimer ~= false,
        -- When true, swim uses the same speed multiplier as walk.
        matchSwimSpeed = Defaults.MatchSwimSpeed == true,
        -- persisted state
        speedMultiplier = Defaults.SavedSpeedMultiplier or Defaults.DefaultSpeedMultiplier or 1.0,
        highJumpEnabled = Defaults.HighJumpEnabled == true,
        -- Hotkey toggles (also saved / applied on load)
        infiniteFuel = Defaults.InfiniteFuel == true,
        infiniteStamina = Defaults.InfiniteStamina == true,
        godModeEnabled = Defaults.GodModeEnabled == true,
        -- includePalsGodMode is settings-only (menu); muteki + heal party pals when god is on
        includePalsGodMode = Defaults.IncludePalsGodMode == true,
        godModeFlagName = Defaults.GodModeFlagName or "PalworldEasyCheats",
        -- Hunger (Alt+H); includePalsHunger is settings-only like matchSwimSpeed
        disableHunger = Defaults.DisableHunger == true,
        includePalsHunger = Defaults.IncludePalsHunger == true,
        hungerFlagName = Defaults.HungerFlagName or "PalworldEasyCheats",
        -- Edit in settings.json only (not a hotkey)
        revealMap = Defaults.RevealMap == true,
        -- PalGameSetting.worldmapUIMaskClearSize when revealMap is true
        revealMapClearSize = Defaults.RevealMapClearSize or 50000,
    }
end

local Settings = defaultSettingsTable()

local function mergeSettings(base, overlay)
    if not overlay then
        return base
    end
    for k, v in pairs(overlay) do
        if v ~= nil then
            base[k] = v
        end
    end
    return base
end

local function saveSettings()
    local ok, err = pcall(function()
        local f = assert(io.open(SETTINGS_PATH, "w"))
        local groupOrder = {}
        for _, section in ipairs(SETTINGS_LAYOUT) do
            groupOrder[#groupOrder + 1] = section.group
        end
        f:write(toJson(nestSettingsForSave(Settings), 0, groupOrder))
        f:write("\n")
        f:close()
    end)
    if not ok then
        print(string.format("[%s] Failed to save settings (%s): %s\n", MOD, SETTINGS_PATH, tostring(err)))
        return false
    end
    return true
end

local function loadSettings()
    local f = io.open(SETTINGS_PATH, "r")
    if not f then
        Settings = defaultSettingsTable()
        saveSettings()
        print(string.format("[%s] Created settings file: %s\n", MOD, SETTINGS_PATH))
        return Settings
    end
    local content = f:read("*a") or ""
    f:close()
    local parsed = flattenSettingsOverlay(parseJson(content))
    Settings = mergeSettings(defaultSettingsTable(), parsed)
    -- Normalize types
    Settings.speedMultiplier = tonumber(Settings.speedMultiplier) or 1.0
    Settings.speedStep = tonumber(Settings.speedStep) or 0.25
    Settings.minSpeedMultiplier = tonumber(Settings.minSpeedMultiplier) or 0.25
    Settings.maxSpeedMultiplier = tonumber(Settings.maxSpeedMultiplier) or 10.0
    Settings.defaultSpeedMultiplier = tonumber(Settings.defaultSpeedMultiplier) or 1.0
    Settings.jumpHeightMultiplier = tonumber(Settings.jumpHeightMultiplier) or 2.0
    Settings.maintainIntervalMs = tonumber(Settings.maintainIntervalMs) or 10000
    Settings.applyOnLoadDelayMs = tonumber(Settings.applyOnLoadDelayMs) or 2000
    Settings.highJumpEnabled = Settings.highJumpEnabled == true
    -- Infinite fuel (settings.json only). Migrate older keys.
    if Settings.infiniteFuel == nil then
        if Settings.infiniteFuelEnabled ~= nil then
            Settings.infiniteFuel = Settings.infiniteFuelEnabled == true
        elseif Settings.fuelDurationMultiplier ~= nil then
            -- Any non-vanilla efficiency request -> unlimited
            local m = tonumber(Settings.fuelDurationMultiplier) or 1.0
            Settings.infiniteFuel = math.abs(m - 1.0) > 0.001
        else
            Settings.infiniteFuel = Defaults.InfiniteFuel == true
        end
    end
    Settings.infiniteFuel = Settings.infiniteFuel == true
    if Settings.infiniteStamina == nil then
        Settings.infiniteStamina = Defaults.InfiniteStamina == true
    end
    Settings.infiniteStamina = Settings.infiniteStamina == true
    Settings.godModeEnabled = Settings.godModeEnabled == true
    Settings.includePalsGodMode = Settings.includePalsGodMode == true
    if Settings.godModeFlagName == nil or Settings.godModeFlagName == "" then
        Settings.godModeFlagName = Defaults.GodModeFlagName or "PalworldEasyCheats"
    end
    Settings.disableHunger = Settings.disableHunger == true
    Settings.includePalsHunger = Settings.includePalsHunger == true
    if Settings.hungerFlagName == nil or Settings.hungerFlagName == "" then
        Settings.hungerFlagName = Defaults.HungerFlagName or "PalworldEasyCheats"
    end
    Settings.revealMap = Settings.revealMap == true
    Settings.revealMapClearSize = tonumber(Settings.revealMapClearSize) or 50000
    -- Default true (skip disclaimer) unless explicitly false
    if Settings.skipModDisclaimer == nil then
        Settings.skipModDisclaimer = true
    else
        Settings.skipModDisclaimer = Settings.skipModDisclaimer == true
    end
    -- Drop legacy fuel keys
    Settings.infiniteFuelEnabled = nil
    Settings.fuelDurationMultiplier = nil
    Settings.fuelDurationStep = nil
    Settings.defaultFuelDurationMultiplier = nil
    Settings.minFuelDurationMultiplier = nil
    Settings.maxFuelDurationMultiplier = nil
    if Settings.matchSwimSpeed == nil then
        Settings.matchSwimSpeed = Defaults.MatchSwimSpeed == true
    else
        Settings.matchSwimSpeed = Settings.matchSwimSpeed == true
    end
    -- Prefer new key; accept legacy persistCheats from older settings files
    if Settings.persistModifications == nil and Settings.persistCheats ~= nil then
        Settings.persistModifications = Settings.persistCheats
    end
    Settings.persistCheats = nil
    Settings.persistModifications = Settings.persistModifications ~= false
    print(string.format("[%s] Loaded settings: %s\n", MOD, SETTINGS_PATH))
    return Settings
end

loadSettings()

-- ---------------------------------------------------------------------------
-- Runtime state (mirrors persisted toggles)
-- ---------------------------------------------------------------------------

local state = {
    speedMultiplier = Settings.speedMultiplier,
    highJump = Settings.highJumpEnabled,
    infiniteFuel = Settings.infiniteFuel == true,
    infiniteStamina = Settings.infiniteStamina == true,
    godMode = Settings.godModeEnabled == true,
    disableHunger = Settings.disableHunger == true,
    matchSwimSpeed = Settings.matchSwimSpeed == true,
    revealMap = Settings.revealMap == true,
    -- Vanilla worldmapUIMaskClearSize (captured before first reveal apply)
    mapMaskClearBaseline = nil,
    fuelApplied = false,
    staminaApplied = false,
    godModeApplied = false,
    hungerApplied = false,
    -- Vanilla UPalGameSetting SP costs captured when infinite stamina first enables
    savedStaminaCosts = nil,
    -- Vanilla stomach decrease rates (player / monster)
    savedStomachRates = nil,
    maintainStarted = false,
    appliedOnLoad = false,
    modDisclaimerSuppressed = false,
    modDisclaimerAttempts = 0,
}

local cache = {
    util = nil,
    player = nil,
    move = nil,
    paramComp = nil,
    gliderComp = nil,
    jetComp = nil,
    settingsObj = nil,
    gameInstance = nil,
    jumpFlag = nil,
    speedFlag = nil,
    godFlag = nil,
    hungerFlag = nil,
    otomoHolder = nil,
}

local function log(msg)
    print(string.format("[%s] %s\n", MOD, msg))
end

local function isValid(obj)
    return obj ~= nil and type(obj) == "userdata" and obj:IsValid()
end

local function getSpeedFlag()
    if not cache.speedFlag then
        cache.speedFlag = FName(Settings.speedFlagName or "PalworldEasyCheats")
    end
    return cache.speedFlag
end

local function getJumpFlag()
    if not cache.jumpFlag then
        cache.jumpFlag = FName(Settings.jumpFlagName or "PalworldEasyCheats")
    end
    return cache.jumpFlag
end

local function getGodFlag()
    if not cache.godFlag then
        cache.godFlag = FName(Settings.godModeFlagName or "PalworldEasyCheats")
    end
    return cache.godFlag
end

local function getHungerFlag()
    if not cache.hungerFlag then
        cache.hungerFlag = FName(Settings.hungerFlagName or "PalworldEasyCheats")
    end
    return cache.hungerFlag
end

local function getPalUtility()
    if isValid(cache.util) then
        return cache.util
    end
    local util = StaticFindObject("/Script/Pal.Default__PalUtility")
    if isValid(util) then
        cache.util = util
        return util
    end
    return nil
end

local function getPalGameInstance(forceRefresh)
    if not forceRefresh and isValid(cache.gameInstance) then
        return cache.gameInstance
    end

    local gi = nil

    if type(UEHelpers.GetGameInstance) == "function" then
        local ok, result = pcall(UEHelpers.GetGameInstance)
        if ok and isValid(result) then
            gi = result
        end
    end

    if not isValid(gi) then
        local found = FindFirstOf("PalGameInstance")
        if isValid(found) then
            gi = found
        end
    end

    if not isValid(gi) then
        local found = FindFirstOf("GameInstance")
        if isValid(found) then
            gi = found
        end
    end

    cache.gameInstance = gi
    return gi
end

-- Mark Pocketpair mod-detection dialog as already shown.
-- UPalGameInstance::SetAlreadyShowModDetectionDialog
local function suppressModDisclaimer(opts)
    opts = opts or {}
    local silent = opts.silent == true

    if Settings.skipModDisclaimer == false then
        return false
    end

    local gi = getPalGameInstance(true)
    if not isValid(gi) then
        return false
    end

    local ok, err = pcall(function()
        gi:SetAlreadyShowModDetectionDialog()
    end)
    if not ok then
        if not silent then
            log("SetAlreadyShowModDetectionDialog failed: " .. tostring(err))
        end
        return false
    end

    state.modDisclaimerSuppressed = true
    if not silent then
        log("Mod disclaimer suppressed (SetAlreadyShowModDetectionDialog).")
    end
    return true
end

local function scheduleModDisclaimerSuppress()
    if Settings.skipModDisclaimer == false then
        return
    end

    local function trySuppress()
        if state.modDisclaimerSuppressed then
            return
        end
        if Settings.skipModDisclaimer == false then
            return
        end

        state.modDisclaimerAttempts = (state.modDisclaimerAttempts or 0) + 1
        local silent = state.modDisclaimerAttempts > 1
        if suppressModDisclaimer({ silent = silent }) then
            return
        end

        -- Retry while title / game instance come online
        if state.modDisclaimerAttempts < 40 then
            ExecuteWithDelay(250, function()
                ExecuteInGameThread(trySuppress)
            end)
        elseif not silent then
            log("Mod disclaimer: PalGameInstance not ready after retries.")
        end
    end

    ExecuteInGameThread(trySuppress)

    -- When a new game instance appears, mark dialog shown immediately
    pcall(function()
        if type(NotifyOnNewObject) == "function" then
            NotifyOnNewObject("/Script/Pal.PalGameInstance", function(obj)
                if Settings.skipModDisclaimer == false then
                    return
                end
                if isValid(obj) then
                    cache.gameInstance = obj
                    pcall(function()
                        obj:SetAlreadyShowModDetectionDialog()
                    end)
                    state.modDisclaimerSuppressed = true
                end
            end)
        end
    end)
end

local function getPlayerController()
    local pc = UEHelpers.GetPlayerController()
    if isValid(pc) then
        return pc
    end
    return nil
end

local function getPlayerCharacter(forceRefresh)
    if not forceRefresh and isValid(cache.player) then
        return cache.player
    end

    local util = getPalUtility()
    local pc = getPlayerController()
    local player = nil

    if util and pc then
        local ok, p = pcall(function()
            return util:GetPlayerCharacter(pc)
        end)
        if ok and isValid(p) then
            player = p
        end
    end

    if not isValid(player) and pc and isValid(pc.Pawn) then
        player = pc.Pawn
    end

    if not isValid(player) then
        local found = FindFirstOf("PalPlayerCharacter")
        if isValid(found) then
            player = found
        end
    end

    cache.player = player
    cache.move = nil
    return player
end

local function getMovementComponent(player, forceRefresh)
    if not forceRefresh and isValid(cache.move) then
        return cache.move
    end
    if not isValid(player) then
        return nil
    end

    local move = nil
    local ok, m = pcall(function()
        return player:GetPalCharacterMovementComponent()
    end)
    if ok and isValid(m) then
        move = m
    elseif isValid(player.CharacterMovement) then
        move = player.CharacterMovement
    end

    cache.move = move
    return move
end

local function getGameSetting(forceRefresh)
    if not forceRefresh and isValid(cache.settingsObj) then
        return cache.settingsObj
    end

    local settings = nil
    local util = getPalUtility()
    local pc = getPlayerController()
    if util and pc then
        local ok, s = pcall(function()
            return util:GetGameSetting(pc)
        end)
        if ok and isValid(s) then
            settings = s
        end
    end
    if not isValid(settings) then
        local found = FindFirstOf("PalGameSetting")
        if isValid(found) then
            settings = found
        end
    end

    cache.settingsObj = settings
    return settings
end

local function findOwnedComponent(className, player, cacheKey, forceRefresh)
    if not forceRefresh and cacheKey and isValid(cache[cacheKey]) then
        local cached = cache[cacheKey]
        -- Drop cache if owner no longer matches (wrong component / respawn)
        if isValid(player) then
            local owner = nil
            pcall(function()
                owner = cached:GetOwner()
            end)
            if isValid(owner) and owner ~= player then
                cache[cacheKey] = nil
            else
                return cached
            end
        else
            return cached
        end
    end

    local function ownerMatches(comp)
        if not isValid(player) then
            return true
        end
        local owner = nil
        pcall(function()
            owner = comp:GetOwner()
        end)
        return not isValid(owner) or owner == player
    end

    local found = FindFirstOf(className)
    if isValid(found) and ownerMatches(found) then
        if cacheKey then
            cache[cacheKey] = found
        end
        return found
    end

    local all = FindAllOf(className)
    if all then
        for _, comp in pairs(all) do
            if isValid(comp) and ownerMatches(comp) then
                if cacheKey then
                    cache[cacheKey] = comp
                end
                return comp
            end
        end
    end

    return nil
end

-- UPalCharacterParameterComponent on the player (holds SP / bIsInfinitySP)
local function getCharacterParameterComponent(player, forceRefresh)
    if not forceRefresh and isValid(cache.paramComp) then
        local owner = nil
        pcall(function()
            owner = cache.paramComp:GetOwner()
        end)
        if not isValid(player) or not isValid(owner) or owner == player then
            return cache.paramComp
        end
        cache.paramComp = nil
    end

    if not isValid(player) then
        return nil
    end

    local param = nil
    local ok, p = pcall(function()
        return player:GetCharacterParameterComponent()
    end)
    if ok and isValid(p) then
        param = p
    elseif isValid(player.CharacterParameterComponent) then
        param = player.CharacterParameterComponent
    else
        param = findOwnedComponent("PalCharacterParameterComponent", player, "paramComp", true)
    end

    cache.paramComp = param
    return param
end

local function clamp(value, minV, maxV)
    if value < minV then
        return minV
    end
    if value > maxV then
        return maxV
    end
    return value
end

local function persistState()
    Settings.speedMultiplier = state.speedMultiplier
    Settings.highJumpEnabled = state.highJump == true
    Settings.infiniteFuel = state.infiniteFuel == true
    Settings.infiniteStamina = state.infiniteStamina == true
    Settings.godModeEnabled = state.godMode == true
    Settings.disableHunger = state.disableHunger == true
    -- includePalsGodMode / includePalsHunger / matchSwim / revealMap stay settings-only (no hotkey)
    saveSettings()
end

-- ---------------------------------------------------------------------------
-- Reveal map (PalGameSetting.worldmapUIMaskClearSize)
-- true  -> large clear size (default 50000) so fog/mask is cleared
-- false -> restore captured vanilla value (SDK default ~20)
-- ---------------------------------------------------------------------------

local function readWorldMapMaskClearSize(settings)
    if not isValid(settings) then
        return nil, nil
    end
    -- UPalGameSetting property name in SDK is worldmapUIMaskClearSize
    local ok, val = pcall(function()
        return settings.worldmapUIMaskClearSize
    end)
    if ok and val ~= nil then
        return val, "worldmapUIMaskClearSize"
    end
    ok, val = pcall(function()
        return settings.WorldMapUIMaskClearSize
    end)
    if ok and val ~= nil then
        return val, "WorldMapUIMaskClearSize"
    end
    return nil, nil
end

local function writeWorldMapMaskClearSize(settings, field, value)
    if not isValid(settings) or not field then
        return false
    end
    local ok = pcall(function()
        settings[field] = value
    end)
    return ok
end

local function applyRevealMap(enabled, opts)
    opts = opts or {}
    local silent = opts.silent == true

    state.revealMap = enabled == true

    local settings = getGameSetting(true)
    if not isValid(settings) then
        if not silent then
            log("Reveal map: PalGameSetting not ready yet.")
        end
        return false
    end

    local current, field = readWorldMapMaskClearSize(settings)
    if not field then
        if not silent then
            log("Reveal map: worldmapUIMaskClearSize field not found.")
        end
        return false
    end

    -- Capture vanilla once (prefer first value we see before modifying)
    if state.mapMaskClearBaseline == nil and current ~= nil then
        local revealSize = tonumber(Settings.revealMapClearSize) or 50000
        -- If we already see a huge value, keep SDK default as baseline fallback
        if current >= (revealSize * 0.5) then
            state.mapMaskClearBaseline = 20.0
        else
            state.mapMaskClearBaseline = current
        end
    end

    local target
    if enabled then
        target = tonumber(Settings.revealMapClearSize) or 50000
    else
        target = state.mapMaskClearBaseline or 20.0
    end

    if not writeWorldMapMaskClearSize(settings, field, target) then
        if not silent then
            log("Reveal map: failed to write worldmapUIMaskClearSize.")
        end
        return false
    end

    if not silent then
        log(string.format(
            "Reveal map: %s (worldmapUIMaskClearSize=%.0f)",
            enabled and "ON" or "OFF",
            target
        ))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Movement speed (+ swim)
-- ---------------------------------------------------------------------------

local function applySpeed(multiplier, opts)
    opts = opts or {}
    local silent = opts.silent == true
    local skipSave = opts.skipSave == true

    local player = getPlayerCharacter(true)
    if not isValid(player) then
        if not silent then
            log("No player character yet - enter a world first.")
        end
        return false
    end

    local move = getMovementComponent(player, true)
    if not isValid(move) then
        if not silent then
            log("Could not find PalCharacterMovementComponent.")
        end
        return false
    end

    local flag = getSpeedFlag()
    local ok, err = pcall(function()
        move:SetWalkSpeedMultiplier(flag, multiplier)
    end)
    if not ok then
        if not silent then
            log("SetWalkSpeedMultiplier failed: " .. tostring(err))
        end
        return false
    end

    -- Swim: either match walk multiplier, or leave swim at vanilla (x1).
    local swimMult = 1.0
    if state.matchSwimSpeed == true then
        swimMult = multiplier
    end
    pcall(function()
        move:SetSwimSpeedMultiplier(flag, swimMult)
    end)
    pcall(function()
        move:SetSwimAccelerationMultiplier(flag, swimMult)
    end)

    state.speedMultiplier = multiplier
    if not skipSave then
        persistState()
    end
    if not silent then
        if state.matchSwimSpeed == true then
            log(string.format("Movement / swim speed x%.2f", multiplier))
        else
            log(string.format("Movement speed x%.2f (swim unmatched / vanilla)", multiplier))
        end
    end
    return true
end

local function changeSpeed(delta)
    local next = clamp(
        state.speedMultiplier + delta,
        Settings.minSpeedMultiplier or 0.25,
        Settings.maxSpeedMultiplier or 10.0
    )
    next = math.floor(next * 100 + 0.5) / 100
    applySpeed(next)
end

local function resetSpeed()
    applySpeed(Settings.defaultSpeedMultiplier or 1.0)
end

-- ---------------------------------------------------------------------------
-- High jump
-- ---------------------------------------------------------------------------

local function applyHighJump(enabled, opts)
    opts = opts or {}
    local silent = opts.silent == true
    local skipSave = opts.skipSave == true

    local player = getPlayerCharacter(true)
    if not isValid(player) then
        if not silent then
            log("No player character yet - enter a world first.")
        end
        return false
    end

    local move = getMovementComponent(player, true)
    if not isValid(move) then
        if not silent then
            log("Could not find movement component.")
        end
        return false
    end

    local height = enabled and (Settings.jumpHeightMultiplier or 2.0) or 1.0
    local ok, err = pcall(function()
        move:SetJumpZVelocityMultiplier(getJumpFlag(), height)
    end)
    if not ok then
        if not silent then
            log("SetJumpZVelocityMultiplier failed: " .. tostring(err))
        end
        return false
    end

    state.highJump = enabled
    if not skipSave then
        persistState()
    end
    if not silent then
        log(string.format(
            "Jump height x%.2f: %s",
            Settings.jumpHeightMultiplier or 2.0,
            enabled and "ON" or "OFF"
        ))
    end
    return true
end

local function toggleHighJump()
    applyHighJump(not state.highJump)
end

-- ---------------------------------------------------------------------------
-- Infinite fuel (wing pack / jetpack / glider)
-- settings.json: infiniteFuel = true|false
--
-- Two drain paths in the SDK:
--   1) Regular gliders  -> GliderSP (player stamina) on UPalGameSetting + APalGliderObject
--   2) Wing pack/jetpack -> APalGliderObject fuel rates + bCanFlyWithoutFuel,
--                          UPalJetpackGliderComponent stamina costs + ConsumeFuel
-- Re-applied on maintain, on glider spawn, and on start-glide hooks.
-- ---------------------------------------------------------------------------

local fuelHooksRegistered = false

-- Always attempt the write (do not skip when read-back is nil - UE4SS can
-- return nil for some reflected props that are still writable).
local function writeProp(obj, propName, value)
    if not isValid(obj) then
        return false
    end
    local ok = pcall(function()
        obj[propName] = value
    end)
    return ok
end

local function getClassDefaultObject(objOrClass)
    local c = objOrClass
    if not isValid(c) then
        return nil
    end
    -- If given an instance, resolve its UClass first
    pcall(function()
        if c.GetClass then
            local maybe = c:GetClass()
            if isValid(maybe) then
                c = maybe
            end
        end
    end)
    local cdo = nil
    pcall(function()
        if c.GetDefaultObject then
            cdo = c:GetDefaultObject()
        elseif c.GetCDO then
            cdo = c:GetCDO()
        elseif c.DefaultObject ~= nil then
            cdo = c.DefaultObject
        end
    end)
    if isValid(cdo) then
        return cdo
    end
    return nil
end

-- APalGliderObject: stamina + jetpack/wing-pack fuel fields
local function applyInfiniteFuelToGliderObject(glider)
    if not isValid(glider) then
        return
    end
    -- Regular glider stamina drain (this was missing before - main bug)
    writeProp(glider, "GliderSP", 0.0)
    -- Official free-flight flag (wing pack / jetpack item fuel)
    writeProp(glider, "bCanFlyWithoutFuel", true)
    -- Zero burn so tanks / cells are not drained if the flag is ignored
    writeProp(glider, "JetpackFuelConsumptionPerSecond", 0.0)
    writeProp(glider, "JetpackBoostFuelConsumptionPerSecond", 0.0)
    writeProp(glider, "JetpackFuelAscentPenaltyMultiplier", 0.0)
    -- Keep tank topped up if the game still runs a fuel meter
    writeProp(glider, "JetpackFuelRegenPerSecond", 999999.0)
    local maxF = nil
    pcall(function()
        maxF = glider.JetpackMaxFuel
    end)
    if type(maxF) == "number" and maxF > 0 then
        writeProp(glider, "JetpackMaxFuel", math.max(maxF, 999999.0))
    else
        writeProp(glider, "JetpackMaxFuel", 999999.0)
    end
end

-- UPalJetpackGliderComponent: secondary stamina costs while jetpacking
local function applyInfiniteFuelToJetComponent(jet)
    if not isValid(jet) then
        return
    end
    writeProp(jet, "BaseStaminaCostPerSecond", 0.0)
    writeProp(jet, "BoostStaminaCostPerSecond", 0.0)
    writeProp(jet, "AscentPenaltyMultiplier", 0.0)
end

local function applyInfiniteFuelToCdoAndInstance(obj, applyFn)
    if not isValid(obj) then
        return
    end
    applyFn(obj)
    local cdo = getClassDefaultObject(obj)
    if isValid(cdo) and cdo ~= obj then
        applyFn(cdo)
    end
end

-- Expensive: world UObject scan. Only for full apply / rare events - never maintain.
local function patchAllGliderObjects()
    local all = nil
    pcall(function()
        all = FindAllOf("PalGliderObject")
    end)
    if not all then
        return
    end
    for _, glider in pairs(all) do
        if isValid(glider) then
            applyInfiniteFuelToCdoAndInstance(glider, applyInfiniteFuelToGliderObject)
        end
    end
end

local function ensureGameSettingGliderSPZero(forceRefresh)
    local settings = getGameSetting(forceRefresh == true)
    if not isValid(settings) then
        return
    end
    local cur = nil
    pcall(function()
        cur = settings.GliderSP
    end)
    if cur ~= 0 and cur ~= 0.0 then
        writeProp(settings, "GliderSP", 0.0)
    end
end

-- light=true: maintain path - cached comps only, no FindAllOf / no CDO churn
-- light=false: full apply - may scan gliders once + patch CDOs
local function touchInfiniteFuelTargets(player, opts)
    opts = opts or {}
    local light = opts.light == true
    local forceRefresh = (not light) and (opts.forceRefresh ~= false)

    ensureGameSettingGliderSPZero(forceRefresh)

    if not light then
        patchAllGliderObjects()
    end

    if not isValid(player) then
        return
    end

    local gliderComp = findOwnedComponent("PalGliderComponent", player, "gliderComp", forceRefresh)
    if isValid(gliderComp) then
        local ok, glider = pcall(function()
            return gliderComp:GetCurrentGliderObject()
        end)
        if ok and isValid(glider) then
            if light then
                applyInfiniteFuelToGliderObject(glider)
            else
                applyInfiniteFuelToCdoAndInstance(glider, applyInfiniteFuelToGliderObject)
            end
        end
        if isValid(gliderComp.CurrentGlider) then
            if light then
                applyInfiniteFuelToGliderObject(gliderComp.CurrentGlider)
            else
                applyInfiniteFuelToCdoAndInstance(gliderComp.CurrentGlider, applyInfiniteFuelToGliderObject)
            end
        end
        if not light then
            pcall(function()
                local cls = gliderComp.CurrentGliderClass
                if isValid(cls) then
                    local cdo = getClassDefaultObject(cls)
                    if isValid(cdo) then
                        applyInfiniteFuelToGliderObject(cdo)
                    end
                end
            end)
        end
    end

    local jet = findOwnedComponent("PalJetpackGliderComponent", player, "jetComp", forceRefresh)
    if isValid(jet) then
        if light then
            applyInfiniteFuelToJetComponent(jet)
        else
            applyInfiniteFuelToCdoAndInstance(jet, applyInfiniteFuelToJetComponent)
        end
    end
end

-- Debounced light re-touch (hooks). Avoid stacking full scans mid-flight.
local fuelRetouchPending = false
local function scheduleFuelRetouch(delayMs, heavy)
    if state.infiniteFuel ~= true then
        return
    end
    if fuelRetouchPending and not heavy then
        return
    end
    fuelRetouchPending = true
    delayMs = delayMs or 50
    ExecuteWithDelay(delayMs, function()
        ExecuteInGameThread(function()
            fuelRetouchPending = false
            if state.infiniteFuel ~= true then
                return
            end
            local player = getPlayerCharacter(false)
            if not isValid(player) then
                player = getPlayerCharacter(true)
            end
            if heavy then
                touchInfiniteFuelTargets(player, { light = false, forceRefresh = true })
            else
                touchInfiniteFuelTargets(player, { light = true })
            end
            state.fuelApplied = true
        end)
    end)
end

local function ensureFuelHooks()
    if fuelHooksRegistered then
        return
    end
    fuelHooksRegistered = true

    -- New glider actor (equip / start glide) - cheap instance patch only
    pcall(function()
        if type(NotifyOnNewObject) == "function" then
            NotifyOnNewObject("/Script/Pal.PalGliderObject", function(obj)
                if state.infiniteFuel ~= true then
                    return
                end
                if isValid(obj) then
                    applyInfiniteFuelToGliderObject(obj)
                end
            end)
        end
    end)

    -- Re-apply lightly when gliding / jetpacking starts (rates may be re-copied then)
    local startHooks = {
        "/Script/Pal.PalGliderComponent:StartGliding",
        "/Script/Pal.PalJetpackGliderComponent:StartJetpackGliding",
        "/Script/Pal.PalJetpackGliderComponent:StartBoost",
    }
    for _, path in ipairs(startHooks) do
        pcall(function()
            RegisterHook(path, function()
                if state.infiniteFuel == true then
                    scheduleFuelRetouch(50, false)
                end
            end)
        end)
    end

    -- Do NOT hook ConsumeFuel/ConsumeBoostItem: those fire continuously while flying
    -- and would hitch every frame if they re-scan objects.
end

local function applyInfiniteFuel(enabled, opts)
    opts = opts or {}
    local silent = opts.silent == true
    local skipSave = opts.skipSave == true
    enabled = enabled == true
    state.infiniteFuel = enabled

    ensureFuelHooks()

    if not enabled then
        state.fuelApplied = false
        if not skipSave then
            persistState()
        end
        if not silent then
            log("Infinite fuel: OFF (restart world if rates were already zeroed)")
        end
        return true
    end

    local player = getPlayerCharacter(true)
    -- Full apply once (includes world glider scan)
    touchInfiniteFuelTargets(player, { light = false, forceRefresh = true })

    if not isValid(player) then
        if not skipSave then
            persistState()
        end
        return false
    end

    state.fuelApplied = true
    if not skipSave then
        persistState()
    end

    if not silent then
        log("Infinite fuel: ON (glider SP + wing pack / jetpack fuel)")
    end
    return true
end

local function toggleInfiniteFuel()
    applyInfiniteFuel(not state.infiniteFuel)
end

-- ---------------------------------------------------------------------------
-- Infinite stamina (all SP costs: sprint, glider, climb, swim, jump, roll, ...)
-- settings.json: infiniteStamina = true|false
--
-- SDK paths:
--   UPalCharacterParameterComponent.bIsInfinitySP  - main "infinite SP" flag
--   UPalGameSetting.StepSP                         - roll / dodge cost (int)
--   UPalGameSetting.JumpSP / SprintSP / GliderSP...  - other action costs
--   UPalStatus_StaminaControl::DecreaseStepStamina - applies roll SP drain
-- Some roll checks use StepSP directly and ignore bIsInfinitySP, so we zero
-- those costs as well.
-- ---------------------------------------------------------------------------

-- Game-setting SP cost fields (defaults from PalGameSetting.cpp)
local STAMINA_COST_FIELDS = {
    -- ints
    { name = "StepSP", kind = "int" },          -- roll / step / dodge
    { name = "JumpSP", kind = "int" },
    { name = "MeleeAttackSP", kind = "int" },
    { name = "ConsumStamina_PalThrow", kind = "int" },
    -- floats
    { name = "SprintSP", kind = "float" },
    { name = "GliderSP", kind = "float" },
    { name = "ClimbingStamina_Move", kind = "float" },
    { name = "ClimbingStamina_Jump", kind = "float" },
    { name = "Swimming_SP_Idle", kind = "float" },
    { name = "Swimming_SP_Swim", kind = "float" },
    { name = "Swimming_SP_DashSwim", kind = "float" },
    { name = "FlyHover_SP", kind = "float" },
    { name = "FlyHorizon_SP", kind = "float" },
    { name = "FlyHorizon_Dash_SP", kind = "float" },
    { name = "FlyVertical_SP", kind = "float" },
}

local staminaHooksRegistered = false

local function readSettingNumber(settings, name)
    local v = nil
    pcall(function()
        v = settings[name]
    end)
    if type(v) == "number" then
        return v
    end
    return nil
end

local function applyStaminaCostsToGameSetting(enabled, forceRefresh)
    local settings = getGameSetting(forceRefresh == true)
    if not isValid(settings) then
        return false
    end

    if enabled then
        if type(state.savedStaminaCosts) ~= "table" then
            state.savedStaminaCosts = {}
        end
        for _, field in ipairs(STAMINA_COST_FIELDS) do
            local name = field.name
            local cur = readSettingNumber(settings, name)
            if cur ~= nil then
                if state.savedStaminaCosts[name] == nil then
                    state.savedStaminaCosts[name] = cur
                end
                if cur ~= 0 then
                    writeProp(settings, name, 0)
                end
            else
                -- Still force-write known fields (UE4SS sometimes returns nil on read)
                writeProp(settings, name, 0)
            end
        end
    else
        local saved = state.savedStaminaCosts
        if type(saved) == "table" then
            for name, val in pairs(saved) do
                if type(val) == "number" then
                    writeProp(settings, name, val)
                end
            end
        end
        state.savedStaminaCosts = nil
    end
    return true
end

-- light maintain: only set the flag / costs if they drifted; no ResetSP spam
local function touchInfiniteStamina(player, enabled, opts)
    opts = opts or {}
    local light = opts.light == true
    local forceRefresh = (not light) and (opts.forceRefresh ~= false)

    -- Roll uses StepSP from game settings even when bIsInfinitySP is set
    applyStaminaCostsToGameSetting(enabled, forceRefresh)

    if not isValid(player) then
        return false
    end

    local param = getCharacterParameterComponent(player, forceRefresh)
    if not isValid(param) then
        return false
    end

    if enabled then
        local already = false
        pcall(function()
            already = param.bIsInfinitySP == true
        end)
        if not already then
            pcall(function()
                param.bIsInfinitySP = true
            end)
        end
        -- Always clear overheat so roll isn't blocked after a prior drain
        pcall(function()
            param.IsSPOverheat = false
        end)
        if not light then
            pcall(function()
                if param.ResetSP then
                    param:ResetSP()
                end
            end)
        end
    else
        pcall(function()
            param.bIsInfinitySP = false
        end)
    end
    return true
end

local function ensureStaminaHooks()
    if staminaHooksRegistered then
        return
    end
    staminaHooksRegistered = true

    -- After roll SP drain, re-assert infinity + free StepSP (private UFUNCTION may not hook)
    pcall(function()
        RegisterHook("/Script/Pal.PalStatus_StaminaControl:DecreaseStepStamina", function()
            if state.infiniteStamina ~= true then
                return
            end
            local player = getPlayerCharacter(false)
            if isValid(player) then
                touchInfiniteStamina(player, true, { light = true })
                local param = getCharacterParameterComponent(player, false)
                if isValid(param) then
                    pcall(function()
                        if param.ResetSP then
                            param:ResetSP()
                        end
                    end)
                end
            else
                applyStaminaCostsToGameSetting(true, false)
            end
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalStatus_StaminaControl:DecreaseJumpStamina", function()
            if state.infiniteStamina ~= true then
                return
            end
            local player = getPlayerCharacter(false)
            if isValid(player) then
                local param = getCharacterParameterComponent(player, false)
                if isValid(param) then
                    pcall(function()
                        param.bIsInfinitySP = true
                        param.IsSPOverheat = false
                        if param.ResetSP then
                            param:ResetSP()
                        end
                    end)
                end
            end
        end)
    end)

    -- Player controller roll entry points
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:DoStep", function()
            if state.infiniteStamina == true then
                local player = getPlayerCharacter(false)
                if isValid(player) then
                    touchInfiniteStamina(player, true, { light = true })
                end
            end
        end)
    end)
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:DoAirDash", function()
            if state.infiniteStamina == true then
                local player = getPlayerCharacter(false)
                if isValid(player) then
                    touchInfiniteStamina(player, true, { light = true })
                end
            end
        end)
    end)
end

local function applyInfiniteStamina(enabled, opts)
    opts = opts or {}
    local silent = opts.silent == true
    local skipSave = opts.skipSave == true
    enabled = enabled == true
    state.infiniteStamina = enabled

    ensureStaminaHooks()

    -- Zero StepSP etc. even if player not ready yet
    applyStaminaCostsToGameSetting(enabled, true)

    local player = getPlayerCharacter(true)
    if not isValid(player) then
        if not skipSave then
            persistState()
        end
        if enabled then
            -- Costs zeroed; param flag waits for world load
            return false
        end
        if not silent then
            log("Infinite stamina: OFF")
        end
        return true
    end

    cache.paramComp = nil

    if not touchInfiniteStamina(player, enabled, { light = false, forceRefresh = true }) then
        if not silent then
            log("Infinite stamina: costs zeroed; parameter component missing")
        end
        -- Still partially applied via game settings
        state.staminaApplied = enabled
        if not skipSave then
            persistState()
        end
        return enabled
    end

    state.staminaApplied = enabled
    if not skipSave then
        persistState()
    end

    if not silent then
        log("Infinite stamina: " .. (enabled and "ON (bIsInfinitySP + StepSP/JumpSP/...=0)" or "OFF"))
    end
    return true
end

local function toggleInfiniteStamina()
    applyInfiniteStamina(not state.infiniteStamina)
end

-- ---------------------------------------------------------------------------
-- God mode (muteki / invuln) + full heal
-- Alt+G toggle. Optional settings: includePalsGodMode (party pals muteki + heal)
-- SDK: UPalCharacterParameterComponent::SetMuteki + SetHP(GetMaxHP)
-- ---------------------------------------------------------------------------

-- EPalStatusPhysicalHealthType: Healthful=0, MinorInjury=1, Severe=2, Dying=3, ...
local PHYSICAL_HEALTH_HEALTHFUL = 0
-- EPalBaseCampWorkerSickType::None
local WORKER_SICK_NONE = 0
-- EPalStatusID (subset we clear as injury / death related)
local STATUS_ID_DYING = 15 -- EPalStatusID::Dying
local STATUS_ID_PART_BREAK = 37 -- EPalStatusID::PartBreak

local function clearInjuryIndividual(ind)
    if not isValid(ind) then
        return false
    end
    local ok = false
    -- UPalIndividualCharacterParameter::SetPhysicalHealth(Healthful)
    pcall(function()
        if ind.SetPhysicalHealth then
            ind:SetPhysicalHealth(PHYSICAL_HEALTH_HEALTHFUL)
            ok = true
        end
    end)
    -- Mirror into SaveParameter when exposed (WorkerSick / PhysicalHealth)
    pcall(function()
        local save = ind.SaveParameter
        if save ~= nil then
            pcall(function()
                save.PhysicalHealth = PHYSICAL_HEALTH_HEALTHFUL
            end)
            pcall(function()
                save.WorkerSick = WORKER_SICK_NONE
            end)
            ok = true
        end
    end)
    return ok
end

local function clearInjuryOnCharacter(character)
    if not isValid(character) then
        return
    end
    -- UPalStatusComponent::RemoveStatus for dying / part break
    local statusComp = nil
    pcall(function()
        statusComp = character.StatusComponent
    end)
    if not isValid(statusComp) then
        pcall(function()
            if character.GetComponentByClass then
                -- class path may vary; Find on owner is safer below
            end
        end)
    end
    if not isValid(statusComp) then
        local found = FindFirstOf("PalStatusComponent")
        if isValid(found) then
            local owner = nil
            pcall(function()
                owner = found:GetOwner()
            end)
            if isValid(owner) and owner == character then
                statusComp = found
            end
        end
    end
    if isValid(statusComp) then
        pcall(function()
            if statusComp.RemoveStatus then
                statusComp:RemoveStatus(STATUS_ID_DYING)
                statusComp:RemoveStatus(STATUS_ID_PART_BREAK)
            end
        end)
    end
end

local function fullHealIndividual(ind)
    if not isValid(ind) then
        return false
    end
    clearInjuryIndividual(ind)
    -- Preferred: UPalIndividualCharacterParameter::FullRecoveryHP
    local ok = pcall(function()
        if ind.FullRecoveryHP then
            ind:FullRecoveryHP()
        end
    end)
    if ok then
        return true
    end
    return false
end

local function fullHealParam(param)
    if not isValid(param) then
        return false
    end

    pcall(function()
        if param.ReviveFromDying then
            param:ReviveFromDying()
        end
    end)

    -- Individual save-parameter path (works for otomo HP storage + injury)
    local ind = nil
    pcall(function()
        if param.GetIndividualParameter then
            ind = param:GetIndividualParameter()
        end
    end)
    if not isValid(ind) then
        pcall(function()
            ind = param.IndividualParameter
        end)
    end
    if isValid(ind) then
        fullHealIndividual(ind)
    end

    -- Clear injury-related runtime statuses on the owner character
    local owner = nil
    pcall(function()
        owner = param:GetOwner()
    end)
    if isValid(owner) then
        clearInjuryOnCharacter(owner)
    end

    local ok = pcall(function()
        local maxHp = param:GetMaxHP()
        if maxHp ~= nil then
            param:SetHP(maxHp)
        end
    end)
    return ok
end

local function fullHealPlayer(player)
    local param = getCharacterParameterComponent(player, false)
    if not isValid(param) then
        param = getCharacterParameterComponent(player, true)
    end
    return fullHealParam(param)
end

local function getParamComponentFromCharacter(character, forceRefresh)
    if not isValid(character) then
        return nil
    end
    local param = nil
    pcall(function()
        if character.GetCharacterParameterComponent then
            param = character:GetCharacterParameterComponent()
        end
    end)
    if not isValid(param) then
        pcall(function()
            param = character.CharacterParameterComponent
        end)
    end
    if not isValid(param) and forceRefresh then
        param = findOwnedComponent("PalCharacterParameterComponent", character, nil, true)
    end
    if isValid(param) then
        return param
    end
    return nil
end

local function touchGodModeOnParam(param, enabled, opts)
    opts = opts or {}
    local light = opts.light == true
    if not isValid(param) then
        return false
    end

    local flag = getGodFlag()
    pcall(function()
        if param.SetMuteki then
            param:SetMuteki(flag, enabled == true)
        end
    end)
    pcall(function()
        param.bIsDebugMuteki = enabled == true
    end)
    pcall(function()
        param.IsImmortality = enabled == true
    end)
    pcall(function()
        param.bIsEnableMuteki = enabled == true
    end)

    if enabled and not light then
        fullHealParam(param)
    elseif enabled and light then
        -- Light maintain: clear injury, keep HP topped if it drifted
        local healed = false
        pcall(function()
            local ind = nil
            if param.GetIndividualParameter then
                ind = param:GetIndividualParameter()
            end
            if not isValid(ind) then
                ind = param.IndividualParameter
            end
            if isValid(ind) then
                clearInjuryIndividual(ind)
                if ind.IsHPFullRecovered then
                    if not ind:IsHPFullRecovered() and ind.FullRecoveryHP then
                        ind:FullRecoveryHP()
                        healed = true
                    end
                end
            end
        end)
        if not healed then
            pcall(function()
                local maxHp = param:GetMaxHP()
                local hp = param:GetHP()
                if maxHp ~= nil and hp ~= nil then
                    local rate = nil
                    pcall(function()
                        rate = param:GetHPRate()
                    end)
                    if type(rate) == "number" then
                        if rate < 0.999 then
                            param:SetHP(maxHp)
                        end
                    else
                        param:SetHP(maxHp)
                    end
                end
            end)
        end
    end

    return true
end

local function touchGodMode(player, enabled, opts)
    opts = opts or {}
    local light = opts.light == true
    local forceRefresh = (not light) and (opts.forceRefresh ~= false)

    if not isValid(player) then
        return false
    end

    local param = getCharacterParameterComponent(player, forceRefresh)
    if not isValid(param) then
        return false
    end

    return touchGodModeOnParam(param, enabled, opts)
end

-- Otomo holder is NOT owned by the player pawn (controller/player-state side).
-- Prefer UPalUtility::GetOtomoHolderComponent; fall back to holder that controls our player.
local function getOtomoHolder(player, forceRefresh)
    if not forceRefresh and isValid(cache.otomoHolder) then
        return cache.otomoHolder
    end

    local holder = nil
    local util = getPalUtility()
    local contexts = {}
    if isValid(player) then
        contexts[#contexts + 1] = player
    end
    local pc = getPlayerController()
    if isValid(pc) then
        contexts[#contexts + 1] = pc
    end

    if util then
        for _, ctx in ipairs(contexts) do
            local ok, h = pcall(function()
                return util:GetOtomoHolderComponent(ctx)
            end)
            if ok and isValid(h) then
                holder = h
                break
            end
        end
    end

    if not isValid(holder) then
        local function controlledMatches(h)
            local char = nil
            pcall(function()
                if h.TryGetOwnerControlledCharacter then
                    char = h:TryGetOwnerControlledCharacter()
                end
            end)
            if isValid(char) and isValid(player) and char == player then
                return true
            end
            local pawn = nil
            pcall(function()
                if h.TryGetOwnerControlledPawn then
                    pawn = h:TryGetOwnerControlledPawn()
                end
            end)
            if isValid(pawn) and isValid(player) and pawn == player then
                return true
            end
            return false
        end

        local found = FindFirstOf("PalOtomoHolderComponentBase")
        if isValid(found) and controlledMatches(found) then
            holder = found
        end
        if not isValid(holder) then
            local all = FindAllOf("PalOtomoHolderComponentBase")
            if all then
                for _, h in pairs(all) do
                    if isValid(h) and controlledMatches(h) then
                        holder = h
                        break
                    end
                end
            end
        end
    end

    if isValid(holder) then
        cache.otomoHolder = holder
    end
    return holder
end

local function touchGodModeOnIndividualHandle(handle, enabled, opts)
    if not isValid(handle) then
        return false
    end

    local applied = false

    -- Heal via individual parameter even when pal is in the ball (no actor)
    local ind = nil
    pcall(function()
        if handle.TryGetIndividualParameter then
            ind = handle:TryGetIndividualParameter()
        end
    end)
    if isValid(ind) and enabled then
        clearInjuryIndividual(ind)
        if fullHealIndividual(ind) then
            applied = true
        end
    end

    -- Muteki requires a spawned APalCharacter + UPalCharacterParameterComponent
    local actor = nil
    pcall(function()
        if handle.TryGetIndividualActor then
            actor = handle:TryGetIndividualActor()
        end
    end)
    if isValid(actor) then
        local param = getParamComponentFromCharacter(actor, not opts.light)
        if touchGodModeOnParam(param, enabled, opts) then
            applied = true
        end
    end

    return applied
end

-- Party otomo: muteki + full heal when includePalsGodMode is on
-- SDK:
--   UPalUtility::GetOtomoHolderComponent
--   UPalOtomoHolderComponentBase::GetOtomoIndividualHandle / TryGetOtomoActorBySlotIndex / TryGetSpawnedOtomo
--   UPalIndividualCharacterHandle::TryGetIndividualActor / TryGetIndividualParameter
--   UPalIndividualCharacterParameter::FullRecoveryHP
--   UPalCharacterParameterComponent::SetMuteki / IsOtomo / Trainer
local function touchPartyPalsGodMode(player, enabled, opts)
    opts = opts or {}
    if not isValid(player) then
        return 0
    end

    local touched = 0
    local seen = {}

    local function markAndCount(key)
        if key == nil or seen[key] then
            return false
        end
        seen[key] = true
        touched = touched + 1
        return true
    end

    local holder = getOtomoHolder(player, opts.forceRefresh == true or not opts.light)
    if isValid(holder) then
        -- Currently spawned otomo (active in world)
        pcall(function()
            if holder.TryGetSpawnedOtomo then
                local spawned = holder:TryGetSpawnedOtomo()
                if isValid(spawned) then
                    local param = getParamComponentFromCharacter(spawned, not opts.light)
                    if touchGodModeOnParam(param, enabled, opts) then
                        markAndCount(tostring(spawned))
                    end
                end
            end
        end)

        local maxSlots = 5
        pcall(function()
            if holder.GetMaxOtomoNum then
                local m = holder:GetMaxOtomoNum()
                if type(m) == "number" and m > 0 then
                    maxSlots = m
                end
            end
        end)
        pcall(function()
            if holder.GetOtomoCount then
                local c = holder:GetOtomoCount()
                if type(c) == "number" and c > maxSlots then
                    maxSlots = c
                end
            end
        end)

        for slot = 0, maxSlots - 1 do
            local handle = nil
            pcall(function()
                if holder.GetOtomoIndividualHandle then
                    handle = holder:GetOtomoIndividualHandle(slot)
                end
            end)
            if isValid(handle) then
                if touchGodModeOnIndividualHandle(handle, enabled, opts) then
                    markAndCount(tostring(handle))
                end
            end

            -- Also direct actor lookup per slot (spawned only)
            local actor = nil
            pcall(function()
                if holder.TryGetOtomoActorBySlotIndex then
                    actor = holder:TryGetOtomoActorBySlotIndex(slot)
                end
            end)
            if isValid(actor) then
                local param = getParamComponentFromCharacter(actor, not opts.light)
                if touchGodModeOnParam(param, enabled, opts) then
                    markAndCount(tostring(actor))
                end
            end
        end
    end

    -- Fallback: any otomo whose Trainer is the local player (spawned pals)
    -- UPalCharacterParameterComponent::IsOtomo / Trainer
    if not opts.light or touched == 0 then
        local allParams = FindAllOf("PalCharacterParameterComponent")
        if allParams then
            for _, param in pairs(allParams) do
                if isValid(param) then
                    local isOtomo = false
                    pcall(function()
                        if param.IsOtomo then
                            isOtomo = param:IsOtomo() == true
                        end
                    end)
                    if not isOtomo then
                        pcall(function()
                            isOtomo = param.bIsOtomoStandbyAI == true
                        end)
                    end
                    if isOtomo then
                        local trainer = nil
                        pcall(function()
                            trainer = param.Trainer
                        end)
                        if isValid(trainer) and trainer == player then
                            if touchGodModeOnParam(param, enabled, opts) then
                                markAndCount(tostring(param))
                            end
                        end
                    end
                end
            end
        end
    end

    return touched
end

local function applyGodMode(enabled, opts)
    opts = opts or {}
    local silent = opts.silent == true
    local skipSave = opts.skipSave == true
    enabled = enabled == true
    state.godMode = enabled

    local player = getPlayerCharacter(true)
    if not isValid(player) then
        if not silent then
            log("God mode: no player yet - enter a world first.")
        end
        if not skipSave then
            persistState()
        end
        return false
    end

    cache.paramComp = nil
    cache.otomoHolder = nil
    if not touchGodMode(player, enabled, { light = false, forceRefresh = true }) then
        if not silent then
            log("God mode: could not find PalCharacterParameterComponent")
        end
        return false
    end

    local palCount = 0
    if Settings.includePalsGodMode == true then
        palCount = touchPartyPalsGodMode(player, enabled, { light = false, forceRefresh = true }) or 0
    elseif not enabled then
        -- Turning god off: clear pals if they may still hold our muteki flag
        palCount = touchPartyPalsGodMode(player, false, { light = false, forceRefresh = true }) or 0
    end

    state.godModeApplied = enabled
    if not skipSave then
        persistState()
    end

    if not silent then
        if enabled then
            if Settings.includePalsGodMode == true then
                log(string.format("God mode: ON (muteki + full heal, player+pals, palsTouched=%d)", palCount))
            else
                log("God mode: ON (muteki + full heal, player only)")
            end
        else
            log("God mode: OFF")
        end
    end
    return true
end

local function toggleGodMode()
    applyGodMode(not state.godMode)
end

-- When an otomo spawns / initializes, re-apply god mode if includePalsGodMode is on
local function scheduleOtomoGodModeHooks()
    pcall(function()
        if type(NotifyOnNewObject) ~= "function" then
            return
        end
        NotifyOnNewObject("/Script/Pal.PalCharacter", function(obj)
            if state.godMode ~= true or Settings.includePalsGodMode ~= true then
                return
            end
            if not isValid(obj) then
                return
            end
            ExecuteWithDelay(250, function()
                ExecuteInGameThread(function()
                    if state.godMode ~= true or Settings.includePalsGodMode ~= true then
                        return
                    end
                    local player = getPlayerCharacter(false)
                    if not isValid(player) then
                        player = getPlayerCharacter(true)
                    end
                    if not isValid(player) then
                        return
                    end
                    local param = getParamComponentFromCharacter(obj, true)
                    if not isValid(param) then
                        return
                    end
                    local isOtomo = false
                    pcall(function()
                        if param.IsOtomo then
                            isOtomo = param:IsOtomo() == true
                        end
                    end)
                    local trainer = nil
                    pcall(function()
                        trainer = param.Trainer
                    end)
                    if isOtomo and isValid(trainer) and trainer == player then
                        touchGodModeOnParam(param, true, { light = false })
                    end
                end)
            end)
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Disable hunger (player stomach drain)
-- Alt+H toggle. Optional settings: includePalsHunger (like matchSwimSpeed)
--
-- SDK:
--   UPalGameSetting.StomachDecreace_perSecond_Player / _Monster
--   UPalIndividualCharacterParameter::SetDecreaseFullStomachRates / SetFullStomach
-- ---------------------------------------------------------------------------

local function getIndividualParameterFromCharacter(character)
    if not isValid(character) then
        return nil
    end
    local paramComp = nil
    pcall(function()
        if character.GetCharacterParameterComponent then
            paramComp = character:GetCharacterParameterComponent()
        end
    end)
    if not isValid(paramComp) then
        pcall(function()
            paramComp = character.CharacterParameterComponent
        end)
    end
    if not isValid(paramComp) then
        return nil
    end
    local ind = nil
    pcall(function()
        if paramComp.GetIndividualParameter then
            ind = paramComp:GetIndividualParameter()
        end
    end)
    if not isValid(ind) then
        pcall(function()
            ind = paramComp.IndividualParameter
        end)
    end
    if isValid(ind) then
        return ind
    end
    return nil
end

local function applyNoHungerToIndividual(ind, enabled)
    if not isValid(ind) then
        return false
    end
    local flag = getHungerFlag()
    if enabled then
        pcall(function()
            if ind.SetDecreaseFullStomachRates then
                ind:SetDecreaseFullStomachRates(flag, 0.0)
            end
        end)
        pcall(function()
            local maxS = nil
            if ind.GetMaxFullStomach then
                maxS = ind:GetMaxFullStomach()
            end
            if type(maxS) == "number" and maxS > 0 and ind.SetFullStomach then
                ind:SetFullStomach(maxS)
            end
        end)
    else
        pcall(function()
            if ind.RemoveDecreaseFullStomachRates then
                ind:RemoveDecreaseFullStomachRates(flag)
            end
        end)
    end
    return true
end

local function applyStomachRatesToGameSetting(enabled, includePals, forceRefresh)
    local settings = getGameSetting(forceRefresh == true)
    if not isValid(settings) then
        return false
    end

    if enabled then
        if type(state.savedStomachRates) ~= "table" then
            state.savedStomachRates = {}
        end
        -- Always zero player drain
        local playerFields = {
            "StomachDecreace_perSecond_Player",
            "StomachDecreaceRate_GroundRide_Sprint",
            "StomachDecreaceRate_WaterRide",
            "StomachDecreaceRate_WaterRide_Sprint",
            "StomachDecreaceRate_FlyRide",
            "StomachDecreaceRate_FlyRide_Sprint",
        }
        for _, name in ipairs(playerFields) do
            local cur = nil
            pcall(function()
                cur = settings[name]
            end)
            if type(cur) == "number" and state.savedStomachRates[name] == nil then
                state.savedStomachRates[name] = cur
            end
            writeProp(settings, name, 0.0)
        end
        -- Pal / worker drain only when includePalsHunger is on
        if includePals then
            local palFields = {
                "StomachDecreace_perSecond_Monster",
                "StomachDecreace_AutoHealing",
                "StomachDecreace_WorkingRate",
            }
            for _, name in ipairs(palFields) do
                local cur = nil
                pcall(function()
                    cur = settings[name]
                end)
                if type(cur) == "number" and state.savedStomachRates[name] == nil then
                    state.savedStomachRates[name] = cur
                end
                writeProp(settings, name, 0.0)
            end
        else
            -- If pals were previously zeroed and include is now off, restore pal fields
            local palFields = {
                "StomachDecreace_perSecond_Monster",
                "StomachDecreace_AutoHealing",
                "StomachDecreace_WorkingRate",
            }
            for _, name in ipairs(palFields) do
                local saved = state.savedStomachRates and state.savedStomachRates[name]
                if type(saved) == "number" then
                    writeProp(settings, name, saved)
                end
            end
        end
    else
        local saved = state.savedStomachRates
        if type(saved) == "table" then
            for name, val in pairs(saved) do
                if type(val) == "number" then
                    writeProp(settings, name, val)
                end
            end
        end
        state.savedStomachRates = nil
    end
    return true
end

local function touchPartyPalsNoHunger(player, enabled)
    if not isValid(player) then
        return
    end
    -- Same holder resolution as god mode (not owned by player pawn)
    local holder = getOtomoHolder(player, true)
    if not isValid(holder) then
        return
    end

    local maxSlots = 5
    pcall(function()
        if holder.GetMaxOtomoNum then
            local m = holder:GetMaxOtomoNum()
            if type(m) == "number" and m > 0 then
                maxSlots = m
            end
        end
    end)
    pcall(function()
        if holder.GetOtomoCount then
            local c = holder:GetOtomoCount()
            if type(c) == "number" and c > maxSlots then
                maxSlots = c
            end
        end
    end)

    for slot = 0, maxSlots - 1 do
        local handle = nil
        pcall(function()
            if holder.GetOtomoIndividualHandle then
                handle = holder:GetOtomoIndividualHandle(slot)
            end
        end)
        if isValid(handle) then
            local ind = nil
            pcall(function()
                if handle.TryGetIndividualParameter then
                    ind = handle:TryGetIndividualParameter()
                end
            end)
            applyNoHungerToIndividual(ind, enabled)
        end

        local actor = nil
        pcall(function()
            if holder.TryGetOtomoActorBySlotIndex then
                actor = holder:TryGetOtomoActorBySlotIndex(slot)
            end
        end)
        if isValid(actor) then
            local ind = getIndividualParameterFromCharacter(actor)
            applyNoHungerToIndividual(ind, enabled)
        end
    end
end

local function touchDisableHunger(player, enabled, opts)
    opts = opts or {}
    local light = opts.light == true
    local forceRefresh = (not light) and (opts.forceRefresh ~= false)
    local includePals = Settings.includePalsHunger == true

    applyStomachRatesToGameSetting(enabled, includePals, forceRefresh)

    if isValid(player) then
        local ind = getIndividualParameterFromCharacter(player)
        applyNoHungerToIndividual(ind, enabled)
        if includePals then
            touchPartyPalsNoHunger(player, enabled)
        end
    end
    return true
end

local function applyDisableHunger(enabled, opts)
    opts = opts or {}
    local silent = opts.silent == true
    local skipSave = opts.skipSave == true
    enabled = enabled == true
    state.disableHunger = enabled

    local player = getPlayerCharacter(true)
    touchDisableHunger(player, enabled, { light = false, forceRefresh = true })

    state.hungerApplied = enabled
    if not skipSave then
        persistState()
    end

    if not silent then
        if enabled then
            local pals = (Settings.includePalsHunger == true) and "player+pals" or "player only"
            log("Disable hunger: ON (" .. pals .. ")")
        else
            log("Disable hunger: OFF")
        end
    end
    return true
end

local function toggleDisableHunger()
    applyDisableHunger(not state.disableHunger)
end

-- ---------------------------------------------------------------------------
-- Apply saved state once player is in a world
-- ---------------------------------------------------------------------------

-- Re-apply walk/swim speed without full save/log noise (load + maintain keep-alive).
local function reapplySpeedKeepAlive()
    local mult = tonumber(state.speedMultiplier) or tonumber(Settings.speedMultiplier) or 1.0
    state.speedMultiplier = mult
    if math.abs(mult - 1.0) < 0.001 then
        return true
    end
    local player = getPlayerCharacter(false)
    if not isValid(player) then
        player = getPlayerCharacter(true)
    end
    if not isValid(player) then
        return false
    end
    local move = getMovementComponent(player, false)
    if not isValid(move) then
        move = getMovementComponent(player, true)
    end
    if not isValid(move) then
        return false
    end
    local flag = getSpeedFlag()
    local ok = pcall(function()
        move:SetWalkSpeedMultiplier(flag, mult)
    end)
    if not ok then
        return false
    end
    local swimMult = 1.0
    if state.matchSwimSpeed == true then
        swimMult = mult
    end
    pcall(function()
        move:SetSwimSpeedMultiplier(flag, swimMult)
    end)
    pcall(function()
        move:SetSwimAccelerationMultiplier(flag, swimMult)
    end)
    return true
end

-- Game often rebuilds movement after first apply; push speed a few more times.
local function scheduleSpeedReapplyBursts()
    local delays = { 400, 1200, 3000, 6000 }
    for _, d in ipairs(delays) do
        ExecuteWithDelay(d, function()
            ExecuteInGameThread(function()
                reapplySpeedKeepAlive()
            end)
        end)
    end
end

local function applySavedOnLoad()
    local player = getPlayerCharacter(true)
    if not isValid(player) then
        return false
    end

    state.matchSwimSpeed = Settings.matchSwimSpeed == true
    -- Always sync runtime speed from settings (file / prior session)
    local speed = tonumber(Settings.speedMultiplier) or 1.0
    state.speedMultiplier = speed

    local speedOk = applySpeed(speed, { silent = true, skipSave = true })
    if not speedOk then
        -- Movement component may not exist yet; retry whole apply
        return false
    end

    if Settings.highJumpEnabled then
        applyHighJump(true, { silent = true, skipSave = true })
    else
        applyHighJump(false, { silent = true, skipSave = true })
    end

    applyInfiniteFuel(Settings.infiniteFuel == true, { silent = true, skipSave = true })
    applyInfiniteStamina(Settings.infiniteStamina == true, { silent = true, skipSave = true })
    applyGodMode(Settings.godModeEnabled == true, { silent = true, skipSave = true })
    applyDisableHunger(Settings.disableHunger == true, { silent = true, skipSave = true })

    applyRevealMap(Settings.revealMap == true, { silent = true })
    suppressModDisclaimer({ silent = true })

    state.appliedOnLoad = true
    scheduleSpeedReapplyBursts()
    log(string.format(
        "Applied saved state: speed x%.2f, swimMatch=%s, jump=%s, infiniteFuel=%s, infiniteStamina=%s, godMode=%s (pals=%s), noHunger=%s (pals=%s), revealMap=%s, skipDisclaimer=%s",
        speed,
        state.matchSwimSpeed and "ON" or "OFF",
        Settings.highJumpEnabled and "ON" or "OFF",
        (Settings.infiniteFuel == true) and "ON" or "OFF",
        (Settings.infiniteStamina == true) and "ON" or "OFF",
        (Settings.godModeEnabled == true) and "ON" or "OFF",
        (Settings.includePalsGodMode == true) and "ON" or "OFF",
        (Settings.disableHunger == true) and "ON" or "OFF",
        (Settings.includePalsHunger == true) and "ON" or "OFF",
        Settings.revealMap and "ON" or "OFF",
        (Settings.skipModDisclaimer ~= false) and "ON" or "OFF"
    ))
    return true
end

local function scheduleApplyOnLoad()
    local delay = Settings.applyOnLoadDelayMs or 2000
    local applyAttempts = 0
    local maxAttempts = 12

    local function tryApply()
        ExecuteInGameThread(function()
            if state.appliedOnLoad then
                return
            end
            applyAttempts = applyAttempts + 1
            if applySavedOnLoad() then
                applyAttempts = 0
                return
            end
            if applyAttempts < maxAttempts then
                ExecuteWithDelay(delay, tryApply)
            else
                log("Apply on load: gave up after retries (player/movement not ready).")
                applyAttempts = 0
            end
        end)
    end

    -- Primary: when client restarts / enters world
    pcall(function()
        RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
            state.appliedOnLoad = false
            applyAttempts = 0
            cache.player = nil
            cache.move = nil
            cache.paramComp = nil
            cache.gliderComp = nil
            cache.jetComp = nil
            cache.otomoHolder = nil
            ExecuteWithDelay(delay, tryApply)
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Engine.PlayerController:ServerAcknowledgePossession", function()
            state.appliedOnLoad = false
            applyAttempts = 0
            cache.player = nil
            cache.move = nil
            cache.paramComp = nil
            cache.gliderComp = nil
            cache.jetComp = nil
            cache.otomoHolder = nil
            ExecuteWithDelay(delay, tryApply)
        end)
    end)

    -- Fallback if already in world when mod reloads
    ExecuteWithDelay(delay, tryApply)
end

-- ---------------------------------------------------------------------------
-- Maintain (slow, only when sticky modifications are ON)
-- IMPORTANT: keep this path CHEAP. Never FindAllOf / full world scans here.
-- Full fuel scans happen on load + glider spawn / start-glide hooks only.
-- ---------------------------------------------------------------------------

local function maintainRevealMapLight()
    local settings = getGameSetting(false)
    if not isValid(settings) then
        settings = getGameSetting(true)
    end
    if not isValid(settings) then
        return
    end
    local current, field = readWorldMapMaskClearSize(settings)
    if not field then
        return
    end
    local target = tonumber(Settings.revealMapClearSize) or 50000
    if current == nil or current < (target * 0.5) then
        writeWorldMapMaskClearSize(settings, field, target)
    end
end

local function maintainModifications()
    local fuelActive = state.infiniteFuel == true
    local staminaActive = state.infiniteStamina == true
    local godActive = state.godMode == true
    local hungerActive = state.disableHunger == true
    local revealActive = state.revealMap == true
    local speedMult = tonumber(state.speedMultiplier) or tonumber(Settings.speedMultiplier) or 1.0
    local speedActive = math.abs(speedMult - 1.0) > 0.001
    if not state.highJump and not fuelActive and not staminaActive and not godActive and not hungerActive and not revealActive and not speedActive then
        return
    end

    local player = getPlayerCharacter(false)
    if not isValid(player) then
        player = getPlayerCharacter(true)
    end

    -- Light fuel keep-alive only (cached comps + current glider; no world scan)
    if fuelActive then
        touchInfiniteFuelTargets(player, { light = true })
        state.fuelApplied = true
    end

    if not isValid(player) then
        if revealActive then
            maintainRevealMapLight()
        end
        return
    end

    -- Speed is saved, but the game often clears WalkSpeedMultiplierMap after load/respawn
    if speedActive then
        reapplySpeedKeepAlive()
    end

    if staminaActive then
        if touchInfiniteStamina(player, true, { light = true }) then
            state.staminaApplied = true
        end
    end

    if godActive then
        if touchGodMode(player, true, { light = true }) then
            state.godModeApplied = true
        end
        if Settings.includePalsGodMode == true then
            touchPartyPalsGodMode(player, true, { light = true })
        end
    end

    if hungerActive then
        touchDisableHunger(player, true, { light = true })
        state.hungerApplied = true
    end

    if state.highJump then
        local move = getMovementComponent(player, false)
        if not isValid(move) then
            move = getMovementComponent(player, true)
        end
        if isValid(move) then
            pcall(function()
                move:SetJumpZVelocityMultiplier(getJumpFlag(), Settings.jumpHeightMultiplier or 2.0)
            end)
        end
    end

    if revealActive then
        maintainRevealMapLight()
    end
end

local function ensureMaintainLoop()
    if state.maintainStarted or Settings.persistModifications == false then
        return
    end
    state.maintainStarted = true

    -- Default was 3s and did heavy FindAllOf work -> visible hitch. Light path + longer interval.
    local interval = Settings.maintainIntervalMs or 10000
    if interval < 2000 then
        interval = 2000
    end

    if type(LoopInGameThreadWithDelay) == "function" then
        LoopInGameThreadWithDelay(interval, function()
            maintainModifications()
        end)
        return
    end

    LoopAsync(interval, function()
        ExecuteInGameThread(maintainModifications)
        return false
    end)
end

-- ---------------------------------------------------------------------------
-- Keybinds
-- ---------------------------------------------------------------------------

local function withGameThread(fn)
    return function()
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then
                log("Error: " .. tostring(err))
            end
        end)
    end
end

RegisterKeyBind(Key.OEM_PLUS, withGameThread(function()
    changeSpeed(Settings.speedStep or 0.25)
end))
RegisterKeyBind(Key.OEM_MINUS, withGameThread(function()
    changeSpeed(-(Settings.speedStep or 0.25))
end))
RegisterKeyBind(Key.ADD, withGameThread(function()
    changeSpeed(Settings.speedStep or 0.25)
end))
RegisterKeyBind(Key.SUBTRACT, withGameThread(function()
    changeSpeed(-(Settings.speedStep or 0.25))
end))

RegisterKeyBind(Key.ZERO, { ModifierKey.ALT }, withGameThread(resetSpeed))
RegisterKeyBind(Key.NUM_ZERO, { ModifierKey.ALT }, withGameThread(resetSpeed))

RegisterKeyBind(Key.J, { ModifierKey.ALT }, withGameThread(toggleHighJump))
RegisterKeyBind(Key.F, { ModifierKey.ALT }, withGameThread(toggleInfiniteFuel))
RegisterKeyBind(Key.S, { ModifierKey.ALT }, withGameThread(toggleInfiniteStamina))
RegisterKeyBind(Key.G, { ModifierKey.ALT }, withGameThread(toggleGodMode))
RegisterKeyBind(Key.H, { ModifierKey.ALT }, withGameThread(toggleDisableHunger))

ensureMaintainLoop()
scheduleApplyOnLoad()
scheduleModDisclaimerSuppress()
scheduleOtomoGodModeHooks()
-- Register fuel/stamina hooks early so equip/roll mid-session is covered even before first apply
if Settings.infiniteFuel == true then
    ensureFuelHooks()
end
if Settings.infiniteStamina == true then
    ensureStaminaHooks()
end

log("Loaded. Settings: " .. SETTINGS_PATH)
log(string.format(
    "  Saved: speed x%.2f | swimMatch=%s | jump=%s | infiniteFuel=%s | infiniteStamina=%s | godMode=%s (pals=%s) | noHunger=%s (pals=%s) | revealMap=%s | skipDisclaimer=%s",
    Settings.speedMultiplier or 1.0,
    (Settings.matchSwimSpeed == true) and "ON" or "OFF",
    Settings.highJumpEnabled and "ON" or "OFF",
    (Settings.infiniteFuel == true) and "ON" or "OFF",
    (Settings.infiniteStamina == true) and "ON" or "OFF",
    (Settings.godModeEnabled == true) and "ON" or "OFF",
    (Settings.includePalsGodMode == true) and "ON" or "OFF",
    (Settings.disableHunger == true) and "ON" or "OFF",
    (Settings.includePalsHunger == true) and "ON" or "OFF",
    Settings.revealMap and "ON" or "OFF",
    (Settings.skipModDisclaimer ~= false) and "ON" or "OFF"
))
log("  + / -          : movement speed up / down")
log("  Alt+0          : reset movement speed")
log(string.format("  Alt+J          : toggle x%.2f jump height", Settings.jumpHeightMultiplier or 2.0))
log("  Alt+F          : toggle unlimited fuel")
log("  Alt+S          : toggle unlimited stamina")
log("  Alt+G          : toggle god mode (muteki + full heal)")
log("  Alt+H          : toggle disable hunger")
log("  settings.json  : matchSwimSpeed, includePalsGodMode, includePalsHunger, revealMap (no hotkey)")
