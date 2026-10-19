Config = {}

-- ZONE SETTINGS
-- Change these coordinates to matches your PVP area.
Config.Zone = {
    x = -7.84,    -- X Coordinate
    y = 505.32,   -- Y Coordinate
    z = 157.21,   -- Z Coordinate
    radius = 200.0 -- Zone Radius
}

-- PERMISSIONS
-- List of groups allowed to use reset commands
Config.AdminGroups = { 'superadmin', 'admin' }

-- COMMANDS
Config.Command = 'resetzonekills' -- Command to reset leaderboard

-- MESSAGES (Translate here)
Config.Lang = {
    enteredZone = "You entered the PVP Zone! ⚔️",
    leftZone = "You left the PVP Zone.",
    resetSuccess = "Leaderboard has been reset."
}