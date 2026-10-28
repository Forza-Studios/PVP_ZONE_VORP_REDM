local VORPcore = {}

TriggerEvent("getCore", function(core)
    VORPcore = core
end)

-- SQL Table Names
local TableName = 'pvp_leader'

-- Zone coordinates loaded from database
local ZoneCords = {}

-- Helper: Check if player is admin
local function IsAdmin(src)
    local User = VORPcore.getUser(src)
    if not User then return false end
    local Group = User.getGroup
    for _, g in ipairs(Config.AdminGroups) do
        if Group == g then return true end
    end
    return false
end

-- Load zone cords from database
function LoadZoneCords()
    MySQL.query('SELECT * FROM pvp_cords', {}, function(result)
        ZoneCords = {}
        if result and #result > 0 then
            for _, row in ipairs(result) do
                table.insert(ZoneCords, {
                    id = row.id,
                    name = row.name,
                    x = row.x,
                    y = row.y,
                    z = row.z,
                    radius = row.radius or 200.0,
                    color = row.color or 'red',
                    smoke = (row.smoke == 1 or row.smoke == true or row.smoke == nil) and 1 or 0
                })
            end
            print('[zone_top_kills] Loaded ' .. #ZoneCords .. ' zone(s) from database')
        else
            print('[zone_top_kills] No zones found in pvp_cords table')
        end
        TriggerClientEvent('zone_top_kills:receiveZoneData', -1, ZoneCords)
    end)
end

-- Create required tables on resource start
CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS pvp_leader (
            identifier VARCHAR(64) PRIMARY KEY,
            name VARCHAR(128),
            kills INT DEFAULT 0,
            streak INT DEFAULT 0
        )
    ]], {})

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS pvp_cords (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(128),
            x FLOAT,
            y FLOAT,
            z FLOAT,
            radius FLOAT DEFAULT 200.0,
            color VARCHAR(32) DEFAULT 'red',
            smoke TINYINT(1) DEFAULT 1
        )
    ]], {}, function()
        -- Ensure new columns exist on legacy tables
        MySQL.query("SHOW COLUMNS FROM pvp_cords LIKE 'color'", {}, function(cols)
            if not cols or #cols == 0 then
                MySQL.query("ALTER TABLE pvp_cords ADD COLUMN color VARCHAR(32) DEFAULT 'red'", {})
            end
        end)
        MySQL.query("SHOW COLUMNS FROM pvp_cords LIKE 'smoke'", {}, function(cols)
            if not cols or #cols == 0 then
                MySQL.query("ALTER TABLE pvp_cords ADD COLUMN smoke TINYINT(1) DEFAULT 1", {})
            end
        end)
        LoadZoneCords()
    end)
end)

-- Send zone cords to requesting client (for in-zone detection)
RegisterNetEvent('zone_top_kills:requestZoneData', function()
    local src = source
    TriggerClientEvent('zone_top_kills:receiveZoneData', src, ZoneCords)
end)

-- Get all zone cords (for Cord Manager NUI)
RegisterNetEvent('zone_top_kills:getZoneCords', function()
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent("vorp:TipRight", src, "You do not have permission.", 3000)
        return
    end
    MySQL.query('SELECT * FROM pvp_cords', {}, function(result)
        TriggerClientEvent('zone_top_kills:receiveZoneCords', src, result or {})
    end)
end)

-- Add a new zone cord to database
RegisterNetEvent('zone_top_kills:addZoneCord', function(data)
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent("vorp:TipRight", src, "You do not have permission.", 3000)
        return
    end

    local color = data.color or 'red'
    local smoke = (data.smoke == true or data.smoke == 1 or data.smoke == '1') and 1 or 0

    MySQL.query('INSERT INTO pvp_cords (name, x, y, z, radius, color, smoke) VALUES (?, ?, ?, ?, ?, ?, ?)',
        {data.name, data.x, data.y, data.z, data.radius or 200.0, color, smoke},
        function()
            LoadZoneCords()
            TriggerClientEvent("vorp:TipRight", src, "Zone cord added to database.", 3000)
            -- Send updated list back
            MySQL.query('SELECT * FROM pvp_cords', {}, function(result)
                TriggerClientEvent('zone_top_kills:receiveZoneCords', src, result or {})
            end)
        end)
end)

-- Update an existing zone cord
RegisterNetEvent('zone_top_kills:updateZoneCord', function(data)
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent("vorp:TipRight", src, "You do not have permission.", 3000)
        return
    end

    local smoke = (data.smoke == true or data.smoke == 1 or data.smoke == '1') and 1 or 0

    MySQL.query('UPDATE pvp_cords SET name = ?, x = ?, y = ?, z = ?, radius = ?, color = ?, smoke = ? WHERE id = ?',
        {data.name, data.x, data.y, data.z, data.radius or 200.0, data.color or 'red', smoke, data.id},
        function()
            LoadZoneCords()
            TriggerClientEvent("vorp:TipRight", src, "Zone updated.", 3000)
            MySQL.query('SELECT * FROM pvp_cords', {}, function(result)
                TriggerClientEvent('zone_top_kills:receiveZoneCords', src, result or {})
            end)
        end)
end)

-- Remove a zone cord from database
RegisterNetEvent('zone_top_kills:removeZoneCord', function(data)
    local src = source
    if not IsAdmin(src) then
        TriggerClientEvent("vorp:TipRight", src, "You do not have permission.", 3000)
        return
    end
    MySQL.query('DELETE FROM pvp_cords WHERE id = ?', {data.id}, function()
        LoadZoneCords()
        TriggerClientEvent("vorp:TipRight", src, "Zone cord removed from database.", 3000)
        -- Send updated list back
        MySQL.query('SELECT * FROM pvp_cords', {}, function(result)
            TriggerClientEvent('zone_top_kills:receiveZoneCords', src, result or {})
        end)
    end)
end)

-- Helper: Get Top Killers
function GetTopKillers(cb)
    local query = string.format('SELECT name, kills FROM %s ORDER BY kills DESC LIMIT 3', TableName)
    MySQL.query(query, {}, function(result)
        if result then
            cb(result)
        else
            cb({})
        end
    end)
end

-- Request Initial Data
RegisterNetEvent('zone_top_kills:requestData', function()
    local src = source
    local User = VORPcore.getUser(src)
    if User then
        local Character = User.getUsedCharacter
        if Character then
            local charId = Character.identifier
            local myKills = 0
            local myName = Character.firstname .. ' ' .. Character.lastname
            
            MySQL.scalar(string.format('SELECT kills FROM %s WHERE identifier = ?', TableName), {charId}, function(killsResult)
                myKills = killsResult or 0
                TriggerClientEvent('zone_top_kills:updateSelf', src, { name = myName, kills = myKills })
            end)
        end
    end
    -- Use the callback for GetTopKillers
    GetTopKillers(function(top3)
        TriggerClientEvent('zone_top_kills:updateLeaderboard', src, top3)
    end)
end)

-- KILL EVENT
RegisterNetEvent('zone_top_kills:onKill', function(killerServerId)
    local victim = source
    local killer = killerServerId
    
    if killer and killer > 0 and killer ~= victim then
        local User = VORPcore.getUser(killer)
        if User then
            local Character = User.getUsedCharacter
            if Character then
                local charIdentifier = Character.identifier
                local charName = Character.firstname .. ' ' .. Character.lastname
                
                -- 1. Reset Victim Streak
                local VictimUser = VORPcore.getUser(victim)
                local victimName = "Unknown"
                if VictimUser then
                    local VictimChar = VictimUser.getUsedCharacter
                    if VictimChar then
                        victimName = VictimChar.firstname .. ' ' .. VictimChar.lastname
                        local vicId = VictimChar.identifier
                        
                        -- Check victim streak before reset (for notification)
                        MySQL.scalar(string.format('SELECT streak FROM %s WHERE identifier = ?', TableName), {vicId}, function(s)
                            if s and s >= 3 then
                                TriggerClientEvent('zone_top_kills:notify', victim, "Streak Lost!")
                            end
                            -- Reset victim streak
                            MySQL.update(string.format('UPDATE %s SET streak = 0 WHERE identifier = ?', TableName), {vicId})
                        end)
                    end
                end

                -- 2. Update Killer (Kills + Streak)
                -- We assume 'streak' column exists. If not, user needs to run SQL.
                local query = string.format('INSERT INTO %s (identifier, name, kills, streak) VALUES (?, ?, 1, 1) ON DUPLICATE KEY UPDATE kills = kills + 1, name = ?, streak = streak + 1', TableName)
                
                MySQL.update(query, {charIdentifier, charName, charName}, function()
                    -- 3. Broadcast Updates
                    GetTopKillers(function(top3)
                        -- Broadcast update
                        TriggerClientEvent('zone_top_kills:updateLeaderboard', -1, top3)
                    end)
                    
                    -- Fetch new kills for Killer's Personal Stats
                    MySQL.scalar(string.format('SELECT kills FROM %s WHERE identifier = ?', TableName), {charIdentifier}, function(newKills)
                        TriggerClientEvent('zone_top_kills:updateSelf', killer, { name = charName, kills = newKills or 0 })
                    end)
                    
                    -- Fetch new streak for Feed
                    MySQL.scalar(string.format('SELECT streak FROM %s WHERE identifier = ?', TableName), {charIdentifier}, function(newStreak)
                        local s = newStreak or 1
                        TriggerClientEvent('zone_top_kills:announceKill', -1, charName, victimName, s)
                    end)
                end)
            end
        end
    end
end)

-- DEATH EVENT (Reset Streak if died by other means in zone)
RegisterNetEvent('zone_top_kills:onDeath', function()
    local src = source
    local User = VORPcore.getUser(src)
    if not User then return end
    
    local Character = User.getUsedCharacter
    if Character then
        local charIdentifier = Character.identifier
        
        -- Reset streak
        MySQL.scalar(string.format('SELECT streak FROM %s WHERE identifier = ?', TableName), {charIdentifier}, function(s)
            if s and s >= 3 then
                TriggerClientEvent('zone_top_kills:notify', src, "Streak Lost!")
            end
            MySQL.update(string.format('UPDATE %s SET streak = 0 WHERE identifier = ?', TableName), {charIdentifier})
        end)
    end
end)

-- RESET COMMAND
RegisterCommand(Config.Command, function(source, args, rawCommand)
    local src = source
    
    local function executeReset()
        MySQL.update(string.format('TRUNCATE TABLE %s', TableName), {}, function()
            TriggerClientEvent('zone_top_kills:updateLeaderboard', -1, {})
            if src > 0 then
                TriggerClientEvent("vorp:TipRight", src, Config.Lang.resetSuccess, 3000)
            else
                print(Config.Lang.resetSuccess)
            end
        end)
    end

    if src == 0 then
        executeReset()
        return
    end

    if not IsAdmin(src) then
        TriggerClientEvent("vorp:TipRight", src, "You do not have permission.", 3000)
        return
    end
    
    executeReset()
end)

-- PVP COMMAND (Admin only) - Open Cord Manager NUI
RegisterCommand('pvp', function(source, args, rawCommand)
    local src = source

    if src == 0 then
        print('[zone_top_kills] /pvp must be run in-game.')
        return
    end

    if not IsAdmin(src) then
        TriggerClientEvent("vorp:TipRight", src, "You do not have permission.", 3000)
        return
    end

    -- Fetch cords from DB and tell client to open NUI
    MySQL.query('SELECT * FROM pvp_cords', {}, function(result)
        local cords = result or {}
        TriggerClientEvent('zone_top_kills:receiveZoneCords', src, cords)
        TriggerClientEvent('zone_top_kills:openCordManager', src)
    end)
end)
