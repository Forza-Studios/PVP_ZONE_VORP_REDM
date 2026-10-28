Config = {}

-- PERMISSIONS
-- List of groups allowed to use reset commands
Config.AdminGroups = { 'superadmin', 'admin' }

-- Icon blip sprite for each zone (skull; tinted with the zone's color). Per-zone override: zone.sprite
Config.BlipSprite = "blip_ambient_bounty"

-- Minimum radius (meters) of the map circle so small zones stay visible on the minimap
Config.MinBlipRadius = 40.0

-- COMMANDS
Config.Command = 'resetzonekills' -- Command to reset leaderboard

-- MESSAGES (Translate here)
Config.Lang = {
    enteredZone = "You entered the PVP Zone! ⚔️",
    leftZone = "You left the PVP Zone.",
    resetSuccess = "Leaderboard has been reset."
}