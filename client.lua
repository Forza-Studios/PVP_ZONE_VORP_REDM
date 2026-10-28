local showingUI = false
local inZone = false
local hasDied = false
local ZoneData = nil
local createdBlips = {}
local spawnedSmokeFx = {}
local activeSmokeZoneId = nil
local DisableInfiniteAmmo -- defined near the bottom, used by onResourceStop

-- Blip Color Modifiers (RedM MP Color hashes)
local ColorModifiers = {
    ['red']    = joaat("BLIP_MODIFIER_MP_COLOR_2"),
    ['gold']   = joaat("BLIP_MODIFIER_MP_COLOR_32"),
    ['yellow'] = joaat("BLIP_MODIFIER_MP_COLOR_8"),
    ['cyan']   = joaat("BLIP_MODIFIER_MP_COLOR_6"),
    ['green']  = joaat("BLIP_MODIFIER_MP_COLOR_7"),
    ['purple'] = joaat("BLIP_MODIFIER_MP_COLOR_4"),
    ['blue']   = joaat("BLIP_MODIFIER_MP_COLOR_5"),
    ['orange'] = joaat("BLIP_MODIFIER_MP_COLOR_9"),
    ['white']  = joaat("BLIP_MODIFIER_MP_COLOR_1")
}

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

-- Helper: Clear active smoke particle effects
local function ClearAllZoneSmoke()
    for _, handle in ipairs(spawnedSmokeFx) do
        if DoesParticleFxLoopedExist(handle) then
            StopParticleFxLooped(handle, false)
        end
    end
    spawnedSmokeFx = {}
    activeSmokeZoneId = nil
end

-- Helper: Set active particle fx asset (RedM RDR3 native)
-- RedM exposes SET_PARTICLE_FX_ASSET_NEXT_CALL as SetPtfxAssetNextCall.
-- UseParticleFxAssetNextCall / UseParticleFxAsset are GTA V (FiveM) names and are nil in RedM.
local function SetPtfx(asset)
    if SetPtfxAssetNextCall then
        SetPtfxAssetNextCall(asset)
    elseif UseParticleFxAsset then
        UseParticleFxAsset(asset)
    else
        Citizen.InvokeNative(0xA10DB07D234C06D0, asset)
    end
end

-- Helper: Spawn Zone Smoke Effect (Center beacon + 4 perimeter pillars)
local function SpawnZoneSmoke(zone)
    pcall(function()
        local ptfxDict = "core"
        RequestNamedPtfxAsset(ptfxDict)
        local tries = 0
        while not HasNamedPtfxAssetLoaded(ptfxDict) and tries < 50 do
            Citizen.Wait(10)
            tries = tries + 1
        end
        if not HasNamedPtfxAssetLoaded(ptfxDict) then return end

        local zX = zone.x
        local zY = zone.y
        local zZ = zone.z
        local radius = zone.radius or 200.0

        -- 1. Center Tall Rising Smoke Column
        SetPtfx(ptfxDict)
        local centerFx = StartParticleFxLoopedAtCoord("ent_amb_falling_smoke", zX, zY, zZ, 0.0, 0.0, 0.0, 2.2, false, false, false, false)
        if centerFx and centerFx > 0 then
            table.insert(spawnedSmokeFx, centerFx)
        end

        -- 2. Perimeter Smoke Pillars (4 Compass Points along radius)
        local perimeterAngles = { 0, 90, 180, 270 }
        for _, deg in ipairs(perimeterAngles) do
            local rad = math.rad(deg)
            local pX = zX + (radius * math.cos(rad))
            local pY = zY + (radius * math.sin(rad))
            local groundZ = zZ
            local found, gZ = GetGroundZFor_3dCoord(pX, pY, zZ + 60.0, false)
            if found then groundZ = gZ end

            SetPtfx(ptfxDict)
            local pFx = StartParticleFxLoopedAtCoord("ent_amb_falling_smoke", pX, pY, groundZ, 0.0, 0.0, 0.0, 1.5, false, false, false, false)
            if pFx and pFx > 0 then
                table.insert(spawnedSmokeFx, pFx)
            end
        end
    end)
end

-- Helper: Refresh Map Blips
local function RefreshZoneBlips()
    RemoveAllBlips()

    local zones = {}
    if ZoneData and #ZoneData > 0 then
        zones = ZoneData
    end

    for _, zone in ipairs(zones) do
        local zX = zone.x
        local zY = zone.y
        local zZ = zone.z
        local radius = zone.radius or 200.0
        local name = zone.name or "PvP Zone"
        local colorKey = zone.color or 'red'
        local colorMod = ColorModifiers[colorKey] or ColorModifiers['red']

        -- 1. Radius Blip (Colored Area Circle on Map & Minimap)
        local radiusBlip = Citizen.InvokeNative(0x45f13b7e0a15c880, -1282792512, zX, zY, zZ, math.max(radius + 0.0, Config.MinBlipRadius or 40.0))
        if radiusBlip and radiusBlip ~= 0 then
            Citizen.InvokeNative(0x662D364ABF16DE2F, radiusBlip, colorMod)
            Citizen.InvokeNative(0x45FF974EEE1C8734, radiusBlip, 140) -- SetBlipAlpha: makes the circle visible on minimap
            table.insert(createdBlips, radiusBlip)
        end
        print(("[coi-pvpzone] zone '%s' radius blip=%s smoke=%s r=%s"):format(name, tostring(radiusBlip), tostring(zone.smoke), tostring(radius)))

        -- 2. Icon Blip with Custom Name & Color (Visible on Minimap)
        local iconBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, zX, zY, zZ)
        if iconBlip and iconBlip ~= 0 then
            -- Sprite is overridable per zone (zone.sprite) or globally (Config.BlipSprite) to test minimap visibility
            local sprite = zone.sprite or (Config and Config.BlipSprite) or "blip_ambient_bounty"
            SetBlipSprite(iconBlip, joaat(sprite), true)
            print(("[coi-pvpzone] icon blip %s sprite=%s exists=%s"):format(iconBlip, sprite, tostring(DoesBlipExist(iconBlip))))
            SetBlipScale(iconBlip, 1.0)
            -- RedM (RDR3) does not expose SetBlipAsShortRange (GTA V native, nil here).
            -- Icon blips added via ADD_BLIP_FOR_COORD display on the minimap by default.
            Citizen.InvokeNative(0x662D364ABF16DE2F, iconBlip, colorMod)
            local varString = CreateVarString(10, 'LITERAL_STRING', name)
            Citizen.InvokeNative(0x9CB1A1623062F402, iconBlip, varString)
            table.insert(createdBlips, iconBlip)
        end
    end
end

-- Receive zone coordinates from server
RegisterNetEvent('zone_top_kills:receiveZoneData', function(cords)
    ZoneData = cords
    ClearAllZoneSmoke()
    RefreshZoneBlips()
end)

-- Helper: Check if player is in any configured zone
local function CheckPlayerInAnyZone(coords)
    local zones = {}
    if ZoneData and #ZoneData > 0 then
        zones = ZoneData
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

-- Zone Detection Thread & Smoke Manager
Citizen.CreateThread(function()
    Citizen.Wait(1500) -- Wait for NUI initialization

    -- Initial Blips
    RefreshZoneBlips()

    while true do
        local sleep = 2000
        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)

        local isInside, dist, activeZone = CheckPlayerInAnyZone(coords)

        -- Handle Smoke Effect for nearby zones
        if activeZone and (activeZone.smoke == 1 or activeZone.smoke == true) then
            local zoneIdentifier = activeZone.id or (activeZone.name .. "_" .. activeZone.x)
            local smokeDist = (activeZone.radius or 200.0) + 300.0

            if dist < smokeDist then
                if activeSmokeZoneId ~= zoneIdentifier then
                    ClearAllZoneSmoke()
                    print(("[coi-pvpzone] spawning smoke for %s (dist %.0f)"):format(tostring(zoneIdentifier), dist))
                    SpawnZoneSmoke(activeZone)
                    activeSmokeZoneId = zoneIdentifier
                end
            else
                if activeSmokeZoneId == zoneIdentifier then
                    ClearAllZoneSmoke()
                end
            end
        else
            if activeSmokeZoneId ~= nil then
                ClearAllZoneSmoke()
            end
        end

        if isInside then
            sleep = 500
            if not inZone then
                inZone = true
                showingUI = true

                -- Dramatic Smoke Burst on Zone Entrance
                Citizen.CreateThread(function()
                    pcall(function()
                        RequestNamedPtfxAsset("core")
                        local tries = 0
                        while not HasNamedPtfxAssetLoaded("core") and tries < 40 do
                            Citizen.Wait(10)
                            tries = tries + 1
                        end
                        if HasNamedPtfxAssetLoaded("core") then
                            SetPtfx("core")
                            StartParticleFxNonLoopedAtCoord("ent_amb_falling_smoke", coords.x, coords.y, coords.z - 0.4, 0.0, 0.0, 0.0, 2.5, false, false, false)
                        end
                    end)
                end)

                SendNUIMessage({ action = "show" })
                TriggerServerEvent('zone_top_kills:requestData')
                SendNUIMessage({ action = "notify", message = Config.Lang.enteredZone })
            end
        else
            -- If player leaves zone, dies/respawns far away, or teleports, hide UI
            if inZone then
                inZone = false
                showingUI = false
                SendNUIMessage({ action = "hide" })
                SendNUIMessage({ action = "notify", message = Config.Lang.leftZone })
            end

            if dist and dist < 250.0 then
                sleep = 1000 -- Near boundary
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

                    -- Instant auto revive at the same spot (VORP revive keeps the death position)
                    if Config.AutoReviveInZone then
                        Citizen.Wait(Config.AutoReviveDelay or 1000)
                        if IsEntityDead(PlayerPedId()) then
                            TriggerEvent('vorp_core:Client:OnPlayerRevive', true)
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
-- cb() MUST be called before SetNuiFocus(false, false); otherwise the NUI context
-- is torn down before the browser receives the response, causing a "Failed to fetch" error.
RegisterNuiCallback('cordManagerClose', function(data, cb)
    cb('ok')
    SendNUIMessage({ action = 'closeCordManager' })
    SetNuiFocus(false, false)
end)

-- NUI Callback: Add a new zone cord
RegisterNuiCallback('cordManagerAdd', function(data, cb)
    TriggerServerEvent('zone_top_kills:addZoneCord', {
        name = data.name,
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0,
        z = tonumber(data.z) or 0.0,
        radius = tonumber(data.radius) or 200.0,
        color = data.color or 'red',
        smoke = data.smoke
    })
    cb('ok')
end)

-- NUI Callback: Update an existing zone cord
RegisterNuiCallback('cordManagerUpdate', function(data, cb)
    TriggerServerEvent('zone_top_kills:updateZoneCord', {
        id = data.id,
        name = data.name,
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0,
        z = tonumber(data.z) or 0.0,
        radius = tonumber(data.radius) or 200.0,
        color = data.color or 'red',
        smoke = data.smoke
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

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        SetNuiFocus(false, false)
        DisableInfiniteAmmo()
        RemoveAllBlips()
        ClearAllZoneSmoke()
    end
end)

-- Unlimited ammo while inside a PvP zone (removed again on leaving)
local infiniteWeapons = {} -- every weapon hash we enabled infinite ammo on

DisableInfiniteAmmo = function()
    local ped = PlayerPedId()
    pcall(function()
        if SetPedInfiniteAmmoClip then SetPedInfiniteAmmoClip(ped, false) end
        if SetPedInfiniteAmmo then
            for weapon in pairs(infiniteWeapons) do
                SetPedInfiniteAmmo(ped, false, weapon)
            end
        end
    end)
    infiniteWeapons = {}
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(250)
        local ped = PlayerPedId()
        if Config.InfiniteAmmoInZone and inZone and not IsEntityDead(ped) then
            pcall(function()
                if SetPedInfiniteAmmoClip then SetPedInfiniteAmmoClip(ped, true) end
                if SetPedInfiniteAmmo then
                    local ok, weapon = GetCurrentPedWeapon(ped, true, 0, false)
                    if ok and weapon and weapon ~= 0 and not infiniteWeapons[weapon] then
                        SetPedInfiniteAmmo(ped, true, weapon)
                        infiniteWeapons[weapon] = true
                    end
                end
            end)
        elseif next(infiniteWeapons) ~= nil then
            DisableInfiniteAmmo()
        end
    end
end)
