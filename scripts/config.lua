--[[
  Built-in defaults for PalworldEasyCheats.
  Runtime values live in settings.json (grouped by feature).
  That file is created automatically if missing.
]]

local Config = {
    -- movement --------------------------------------------------------------
    DefaultSpeedMultiplier = 1.0,
    SpeedStep = 0.25,
    MinSpeedMultiplier = 0.25,
    MaxSpeedMultiplier = 10.0,
    MatchSwimSpeed = false,
    SpeedFlagName = "PalworldEasyCheats",
    SavedSpeedMultiplier = 2.0,

    -- jump ------------------------------------------------------------------
    HighJumpEnabled = false,
    JumpHeightMultiplier = 2.0,
    JumpFlagName = "PalworldEasyCheats",

    -- fuel (Alt+F) ----------------------------------------------------------
    -- true = unlimited glider / wing-pack / jetpack fuel
    InfiniteFuel = false,

    -- stamina (Alt+S) -------------------------------------------------------
    -- true = UPalCharacterParameterComponent.bIsInfinitySP (all SP costs)
    InfiniteStamina = false,

    -- combat / god mode (Alt+G) ---------------------------------------------
    GodModeEnabled = false,
    -- settings-only (like IncludePalsHunger): also muteki + full heal party pals
    IncludePalsGodMode = false,
    GodModeFlagName = "PalworldEasyCheats",

    -- hunger (Alt+H) --------------------------------------------------------
    DisableHunger = false,
    -- settings-only (like MatchSwimSpeed): also stop pal stomach drain
    IncludePalsHunger = false,
    HungerFlagName = "PalworldEasyCheats",

    -- map (settings.json only) ----------------------------------------------
    -- true -> PalGameSetting.worldmapUIMaskClearSize = RevealMapClearSize
    RevealMap = false,
    RevealMapClearSize = 50000,

    -- system ----------------------------------------------------------------
    -- Skip Pocketpair "mods detected" dialog via SetAlreadyShowModDetectionDialog
    SkipModDisclaimer = true,
    PersistModifications = true,
    -- Light keep-alive only; avoid low values (heavy work is event-driven)
    MaintainIntervalMs = 10000,
    ApplyOnLoadDelayMs = 2000,
}

return Config
