local showingUI = false
local inZone = false
local hasDied = false
local ZoneData = nil

-- Request zone coordinates from server
TriggerServerEvent('zone_top_kills:requestZoneData')

-- Receive zone coordinates from server
RegisterNetEvent('zone_top_kills:receiveZoneData', function(cords)
    ZoneData = cords
end)

-- Helper: Get active zone from database only (no fallback)
local function GetActiveZone()
    if ZoneData and #ZoneData > 0 then
        local z = ZoneData[1]
        return { x = z.x, y = z.y, z = z.z, radius = z.radius or 200.0 }
    end
    return nil
end

-- Zone Detection Thread (Optimized)
Citizen.CreateThread(function()
    -- CRITICAL FIX: Wait for NUI to fully load before checking zone
    Citizen.Wait(2000) 

    while true do
        -- Dynamic Sleep: Default to 2 seconds (FAR)
        local sleep = 2000 
        
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        
        local zone = GetActiveZone()
        if zone then
            local dist = #(coords - vector3(zone.x, zone.y, zone.z))

            -- If close (within radius + 50m), check more frequently
            if dist < (zone.radius + 50.0) then
                sleep = 1000 -- Near
                
                if dist < zone.radius then
                    sleep = 500 -- Inside (Fast check)
                    
                    if not inZone then
                        inZone = true
                        showingUI = true
                        SendNUIMessage({ action = "show" })
                        TriggerServerEvent('zone_top_kills:requestData')
                        SendNUIMessage({ action = "notify", message = Config.Lang.enteredZone })
                    end
                else
                    if inZone then
                        inZone = false
                        showingUI = false
                        SendNUIMessage({ action = "hide" })
                        SendNUIMessage({ action = "notify", message = Config.Lang.leftZone })
                    end
                end
            end
        end
        
        Citizen.Wait(sleep)
    end
end)

-- Map/Pause Menu UI Toggle Thread
Citizen.CreateThread(function()
    local isMapOpen = false
    while true do
        Citizen.Wait(200)
        if inZone then
            local pauseActive = IsPauseMenuActive()
            local radarHidden = IsRadarHidden()
            
            -- If pause menu is active OR radar is forced hidden (which happens when map is open)
            if (pauseActive or radarHidden) and not isMapOpen then
                isMapOpen = true
                SendNUIMessage({ action = "hide" })
            elseif not (pauseActive or radarHidden) and isMapOpen then
                isMapOpen = false
                SendNUIMessage({ action = "show" })
            end
        else
            if isMapOpen then
                isMapOpen = false
            end
        end
    end
end)


-- Death Detection Thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        
        local playerPed = PlayerPedId()
        
        if IsEntityDead(playerPed) then
            if not hasDied then
                hasDied = true
                
                -- Check if death happened in zone
                if inZone then
                    local killer = GetPedSourceOfDeath(playerPed)
                    local killerServerId = -1
                    
                    if killer ~= 0 and IsEntityAPed(killer) and IsPedAPlayer(killer) then
                        local player = NetworkGetPlayerIndexFromPed(killer)
                        killerServerId = GetPlayerServerId(player)
                        
                        if killerServerId > 0 and killerServerId ~= GetPlayerServerId(PlayerId()) then
                            TriggerServerEvent('zone_top_kills:onKill', killerServerId)
                        end
                    end
                end
            end
        else
            if hasDied then
                hasDied = false
            end
        end
    end
end)

-- Listen for Leaderboard Updates
RegisterNetEvent('zone_top_kills:updateLeaderboard', function(topList)
    if showingUI then
        SendNUIMessage({
            action = "update",
            top = topList
        })
    end
end)

-- Listen for Personal Stats
RegisterNetEvent('zone_top_kills:updateSelf', function(data)
    if showingUI then
        SendNUIMessage({
            action = "updateSelf",
            name = data.name,
            kills = data.kills
        })
    end
end)

-- Listen for Kill Feed
RegisterNetEvent('zone_top_kills:announceKill', function(killerName, victimName, streak)
    if inZone then
        SendNUIMessage({
            action = "killFeed",
            killer = killerName,
            victim = victimName,
            streak = streak or 0
        })
    end
end)

-- Create Map Blip and Radius
Citizen.CreateThread(function()
    -- Wait for zone data from server (fallback to config after 5 seconds)
    local waited = 0
    while not ZoneData and waited < 5000 do
        Citizen.Wait(100)
        waited = waited + 100
    end

    local zone = GetActiveZone()
    if zone then
        -- 1. Create the Radius Blip (Red Area on Map)
        -- 0x45f13b7e0a15c880 is AddBlipForRadius in RedM
        local radiusBlip = Citizen.InvokeNative(0x45f13b7e0a15c880, -1282792512, zone.x, zone.y, zone.z, zone.radius)
        Citizen.InvokeNative(0x662D364ABF16DE2F, radiusBlip, joaat("BLIP_MODIFIER_MP_COLOR_2")) -- Force Red Color
        
        -- 2. Create the Icon Blip (So it has a name on the map)
        -- 0x554D9D53F696D002 is AddBlipForCoords in RedM
        local iconBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, zone.x, zone.y, zone.z)
        SetBlipSprite(iconBlip, joaat("blip_ambient_bounty"), true) -- A skull/bounty icon
        Citizen.InvokeNative(0x662D364ABF16DE2F, iconBlip, joaat("BLIP_MODIFIER_MP_COLOR_2")) -- Force Red Color
        Citizen.InvokeNative(0x9CB1A1623062F402, iconBlip, "PvP Zone") -- Set Name
    end
end)
