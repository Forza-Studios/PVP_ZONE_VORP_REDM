local showingUI = false
local inZone = false
local hasDied = false
local ZoneData = nil
local createdBlips = {}

-- Request initial zone coordinates from server
TriggerServerEvent('zone_top_kills:requestZoneData')

-- Helper: Remove all blips
local function RemoveAllBlips()
    for _, blip in ipairs(createdBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    createdBlips = {}
end

-- Helper: Refresh Map Blips
local function RefreshZoneBlips()
    RemoveAllBlips()

    local zones = {}
    if ZoneData and #ZoneData > 0 then
        zones = ZoneData
    elseif Config.Zone then
        zones = { Config.Zone }
    end

    for _, zone in ipairs(zones) do
        local zX = zone.x
        local zY = zone.y
        local zZ = zone.z
        local radius = zone.radius or 200.0
        local name = zone.name or "PvP Zone"

        -- 1. Radius Blip (Red Area on Map)
        -- Native 0x45f13b7e0a15c880 is AddBlipForRadius in RedM
        local radiusBlip = Citizen.InvokeNative(0x45f13b7e0a15c880, -1282792512, zX, zY, zZ, radius)
        if radiusBlip then
            Citizen.InvokeNative(0x662D364ABF16DE2F, radiusBlip, joaat("BLIP_MODIFIER_MP_COLOR_2")) -- Red Color
            table.insert(createdBlips, radiusBlip)
        end

        -- 2. Icon Blip with Name
        -- Native 0x554D9D53F696D002 is AddBlipForCoords in RedM
        local iconBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, zX, zY, zZ)
        if iconBlip then
            SetBlipSprite(iconBlip, joaat("blip_ambient_bounty"), true) -- Skull/bounty icon
            Citizen.InvokeNative(0x662D364ABF16DE2F, iconBlip, joaat("BLIP_MODIFIER_MP_COLOR_2"))
            Citizen.InvokeNative(0x9CB1A1623062F402, iconBlip, name)
            table.insert(createdBlips, iconBlip)
        end
    end
end

-- Receive zone coordinates from server
RegisterNetEvent('zone_top_kills:receiveZoneData', function(cords)
    ZoneData = cords
    RefreshZoneBlips()
end)

-- Helper: Check if player is in any configured zone
local function CheckPlayerInAnyZone(coords)
    local zones = {}
    if ZoneData and #ZoneData > 0 then
        zones = ZoneData
    elseif Config.Zone then
        zones = { Config.Zone }
    end

    if #zones == 0 then
        return false, 99999.0, nil
    end

    local minDistance = 99999.0
    local closestZone = nil

    for _, z in ipairs(zones) do
        local dist = #(coords - vector3(z.x, z.y, z.z))
        local rad = z.radius or 200.0
        if dist < rad then
            return true, dist, z
        end
        if dist < minDistance then
            minDistance = dist
            closestZone = z
        end
    end

    return false, minDistance, closestZone
end

-- Zone Detection Thread
Citizen.CreateThread(function()
    Citizen.Wait(1500) -- Wait for NUI initialization

    -- Initial Blips
    RefreshZoneBlips()

    while true do
        local sleep = 2000
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)

        local isInside, dist, activeZone = CheckPlayerInAnyZone(coords)

        if isInside then
            sleep = 500
            if not inZone then
                inZone = true
                showingUI = true
                SendNUIMessage({ action = "show" })
                TriggerServerEvent('zone_top_kills:requestData')
                SendNUIMessage({ action = "notify", message = Config.Lang.enteredZone })
            end
        else
            -- CRITICAL FIX: If player exits zone, dies and respawns far away, or teleports, ALWAYS hide UI
            if inZone then
                inZone = false
                showingUI = false
                SendNUIMessage({ action = "hide" })
                SendNUIMessage({ action = "notify", message = Config.Lang.leftZone })
            end

            if dist and dist < 250.0 then
                sleep = 1000 -- Near zone boundary
            else
                sleep = 2000 -- Far from any zone
            end
        end

        Citizen.Wait(sleep)
    end
end)

-- Map/Pause Menu UI Toggle Thread
Citizen.CreateThread(function()
    local isMapOpen = false
    while true do
        Citizen.Wait(250)
        if inZone and showingUI then
            local pauseActive = IsPauseMenuActive()
            local radarHidden = IsRadarHidden()

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
        Citizen.Wait(300)
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
                        else
                            TriggerServerEvent('zone_top_kills:onDeath')
                        end
                    else
                        TriggerServerEvent('zone_top_kills:onDeath')
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

-- Listen for Streak Notification
RegisterNetEvent('zone_top_kills:notify', function(message)
    SendNUIMessage({
        action = "notify",
        message = message
    })
end)

-- Listen for Zone Cords from server (for Cord Manager NUI)
RegisterNetEvent('zone_top_kills:receiveZoneCords', function(cords)
    SendNUIMessage({
        action = 'updateCords',
        cords = cords
    })
end)

-- Open Cord Manager NUI
RegisterNetEvent('zone_top_kills:openCordManager', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openCordManager' })
end)

-- NUI Callback: Get current player coordinates for easy form autofill
RegisterNuiCallback('cordManagerGetCurrentCoords', function(data, cb)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    cb({
        x = math.floor(coords.x * 100) / 100,
        y = math.floor(coords.y * 100) / 100,
        z = math.floor(coords.z * 100) / 100
    })
end)

-- NUI Callback: Close Cord Manager
RegisterNuiCallback('cordManagerClose', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeCordManager' })
    cb('ok')
end)

-- NUI Callback: Add a new zone cord
RegisterNuiCallback('cordManagerAdd', function(data, cb)
    TriggerServerEvent('zone_top_kills:addZoneCord', {
        name = data.name,
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0,
        z = tonumber(data.z) or 0.0,
        radius = tonumber(data.radius) or 200.0
    })
    cb('ok')
end)

-- NUI Callback: Remove a zone cord
RegisterNuiCallback('cordManagerRemove', function(data, cb)
    TriggerServerEvent('zone_top_kills:removeZoneCord', { id = data.id })
    cb('ok')
end)

-- NUI Callback: Request fresh cords from server
RegisterNuiCallback('cordManagerGetCords', function(data, cb)
    TriggerServerEvent('zone_top_kills:getZoneCords')
    cb('ok')
end)

-- Release focus if resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        SetNuiFocus(false, false)
        RemoveAllBlips()
    end
end)
