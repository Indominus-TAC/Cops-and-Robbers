-- client.lua
-- Cops & Robbers FiveM Game Mode - Client Script
-- Version: 1.2.0 | Date: June 17, 2025
-- Ped readiness flag and guards implemented.

-- =====================================
--     REGISTER NET EVENTS (MUST BE FIRST)
-- =====================================

-- Register all client events that will be triggered from server
RegisterNetEvent('cnr:sendInventoryForUI')
RegisterNetEvent('cnr:updatePlayerData')
RegisterNetEvent('cnr:spawnPlayerAt')
RegisterNetEvent('cnr:receiveMyInventory')
RegisterNetEvent('cnr:syncInventory')
RegisterNetEvent('cnr:inventoryUpdated')
RegisterNetEvent('cnr:receiveConfigItems')
RegisterNetEvent('cnr:showWantedLevel')
RegisterNetEvent('cnr:hideWantedLevel')
RegisterNetEvent('cnr:updateWantedLevel')
RegisterNetEvent('cops_and_robbers:sendPlayerInventory')
RegisterNetEvent('cops_and_robbers:buyResult')
RegisterNetEvent('cnr:showAdminPanel')
RegisterNetEvent('cnr:showRobberMenu')
RegisterNetEvent('cnr:showPoliceMenu')
RegisterNetEvent('cnr:xpGained')
RegisterNetEvent('cnr:levelUp')
RegisterNetEvent('cops_and_robbers:updateWantedDisplay')
RegisterNetEvent('cnr:heistAlert')
RegisterNetEvent('cnr:startHeistTimer')
RegisterNetEvent('cnr:heistCompleted')
RegisterNetEvent('cops_and_robbers:sendItemList')
RegisterNetEvent('cnr:openContrabandStoreUI')
RegisterNetEvent('cnr:sendNUIMessage') -- Register new event for NUI messages
RegisterNetEvent('cnr:sendToJail')
RegisterNetEvent('cnr:releaseFromJail')
RegisterNetEvent('cnr:wantedLevelSync') -- Register wanted level sync event
RegisterNetEvent('cnr:applyCharacterData')
RegisterNetEvent('cnr:loadedPlayerCharacters')
RegisterNetEvent('cnr:characterSaveResult')
RegisterNetEvent('cnr:characterDeleteResult')
RegisterNetEvent('cnr:updateBankingDetails')
RegisterNetEvent('cnr:lookupRobberInfoResult')
RegisterNetEvent('cnr:receiveCharacterForRole')
RegisterNetEvent('cnr:setPlayerRole')
RegisterNetEvent('cnr:showWantedNotification')
RegisterNetEvent('cnr:hideWantedNotification')
RegisterNetEvent('cnr:performUITest')
RegisterNetEvent('cnr:getUITestResults')
RegisterNetEvent('cnr:notification')
RegisterNetEvent('cnr:openHeistPlanning')
RegisterNetEvent('cnr:updateAvailableHeists')
RegisterNetEvent('cnr:updateCrewInfo')
RegisterNetEvent('cnr:startHeistExecution')
RegisterNetEvent('cnr:updateHeistStage')
RegisterNetEvent('cnr:policeAlert')
RegisterNetEvent('cnr:receivePoliceCadData')
RegisterNetEvent('cnr:receiveAdminLiveMapData')
RegisterNetEvent('cnr:receiveRoleTextMessage')

-- =====================================
--           VARIABLES
-- =====================================

-- Ensure Config is available (fallback initialization)
Config = Config or {}
Config.SpeedLimitMph = Config.SpeedLimitMph or 60.0
Config.Keybinds = Config.Keybinds or {}
Config.NPCVendors = Config.NPCVendors or {}
Config.RobberVehicleSpawns = Config.RobberVehicleSpawns or {}
Config.ContrabandDealers = Config.ContrabandDealers or {}
Config.WantedSettings = Config.WantedSettings or { levels = {} }
Config.SpawnPoints = Config.SpawnPoints or {
    cop = vector3(452.6, -980.0, 30.7),
    robber = vector3(2126.7, 4794.1, 41.1),
    citizen = vector3(-260.0, -970.0, 31.2)
}

-- Player-related variables
local g_isPlayerPedReady = false
local role = nil
local playerCash = 0
local currentSpikeStrips = {}
local spikeStripModelHash = GetHashKey("p_ld_stinger_s")
local pendingAdminLiveMapCallbacks = {}
local activePoliceDispatchBlips = {}
local playerStats = {
    heists = 0,
    arrests = 0,
    rewards = 0
}
local currentObjective = nil
local playerWeapons = {}
local playerAmmo = {}

-- Player Data (Synced from Server)
local playerData = {
    xp = 0,
    level = 1,
    role = "citizen",
    perks = {},
    armorModifier = 1.0,
    money = 0
}
local isJailed = false

-- Wanted System Client State (Server-side managed)
local currentWantedStarsClient = 0
local currentWantedPointsClient = 0
local wantedUiLabel = ""

local xpForNextLevelDisplay = 0

-- Contraband Drop Client State
local activeDropBlips = {}
local clientActiveContrabandDrops = {}
local droppedWorldItems = {}
local DROPPED_ITEM_MODEL = GetHashKey("prop_paper_bag_small")

-- Blip tracking
-- Performance monitoring for optimized loops
if PerformanceOptimizer then
    PerformanceOptimizer.CreateOptimizedLoop(function()
        local metrics = PerformanceOptimizer.GetMetrics()
        if metrics and metrics.memoryUsage and metrics.memoryUsage > Constants.PERFORMANCE.MEMORY_WARNING_THRESHOLD_MB * 1024 then
            Log("[CNR_CLIENT] High memory usage detected: " .. math.floor(metrics.memoryUsage/1024) .. "MB", "warn", "CNR_CLIENT")
        end
    end, Constants.TIME_MS.MINUTE / 2, Constants.TIME_MS.MINUTE, 4)
end


local copStoreBlips = {}
local robberStoreBlips = {}
local publicStoreBlips = {}

-- Track protected peds to prevent NPC suppression from affecting them
local g_protectedPolicePeds = {}

-- Track spawned NPCs to prevent duplicates
local g_spawnedNPCs = {}

-- Track spawned vehicles to prevent duplicates
local g_spawnedVehicles = {}
local g_robberVehiclesSpawned = false
local g_policeVehiclesSpawned = false

-- =====================================
--     INVENTORY SYSTEM (CONSOLIDATED)
-- =====================================

-- Inventory system variables
local clientConfigItems = nil
local isInventoryOpen = false
local localPlayerInventory = {}
local localPlayerEquippedItems = {}
local pendingPoliceLookupCallbacks = {}
local pendingPoliceCadCallbacks = {}
local roleSelectionShownForCurrentDeath = false
local deathReportedForCurrentLife = false
local adminNoClipEnabled = false
local adminInvisibleEnabled = false
local adminSpectateTargetServerId = nil
local adminPanelVisible = false
local activeRoleActionMenu = nil
local adminPanelRequestStartedAt = 0
local ADMIN_PANEL_REQUEST_GUARD_MS = 1500

local function BeginAdminPanelRequest()
    adminPanelRequestStartedAt = GetGameTimer()
end

local function ClearAdminPanelRequest()
    adminPanelRequestStartedAt = 0
end

local function IsAdminPanelRequestPending()
    if adminPanelRequestStartedAt <= 0 then
        return false
    end

    return (GetGameTimer() - adminPanelRequestStartedAt) < ADMIN_PANEL_REQUEST_GUARD_MS
end

-- Function to get the items, accessible by other parts of this script
function GetClientConfigItems()
    return clientConfigItems
end

-- Update full inventory function from inventory_client.lua
function UpdateFullInventory(minimalInventoryData)
    Log("UpdateFullInventory received data. Attempting reconstruction...", "info", "CNR_INV_CLIENT")
    local reconstructedInventory = {}
    local configItems = GetClientConfigItems()

    if not configItems then
        localPlayerInventory = minimalInventoryData or {}
        TriggerServerEvent('cnr:requestConfigItems')
        Log("Requested Config.Items from server due to missing data.", "info", "CNR_INV_CLIENT")
        
        TriggerEvent('chat:addMessage', {
            color = {255, 165, 0},
            multiline = true,
            args = {"System", "Loading inventory data..."}
        })
        
        Citizen.CreateThread(function()
            local attempts = 0
            local maxAttempts = 3
            
            while not GetClientConfigItems() and attempts < maxAttempts do
                Citizen.Wait(3000)
                attempts = attempts + 1
                
                if not GetClientConfigItems() then
                    TriggerServerEvent('cnr:requestConfigItems')
                    Log("Retry requesting Config.Items from server (attempt " .. attempts .. "/" .. maxAttempts .. ")", "warn", "CNR_INV_CLIENT")
                end
            end

            if GetClientConfigItems() and localPlayerInventory and next(localPlayerInventory) then
                Log("Config.Items received after retry, attempting inventory reconstruction again", "info", "CNR_INV_CLIENT")
                UpdateFullInventory(localPlayerInventory)
            end
        end)
        return
    end

    Log("Config.Items available, proceeding with inventory reconstruction. Config items count: " .. tablelength(configItems), "info", "CNR_INV_CLIENT")

    if minimalInventoryData and type(minimalInventoryData) == 'table' then
        for itemId, minItemData in pairs(minimalInventoryData) do
            if minItemData and minItemData.count and minItemData.count > 0 then
                local itemDetails = nil
                for _, cfgItem in ipairs(configItems) do
                    if cfgItem.itemId == itemId then
                        itemDetails = cfgItem
                        break
                    end
                end

                if itemDetails then
                    reconstructedInventory[itemId] = {
                        itemId = itemId,
                        name = itemDetails.name,
                        category = itemDetails.category,
                        count = minItemData.count,
                        basePrice = itemDetails.basePrice
                    }
                else
                    Log(string.format("UpdateFullInventory: ItemId '%s' not found in local clientConfigItems. Storing with minimal details.", itemId), "warn", "CNR_INV_CLIENT")
                    reconstructedInventory[itemId] = {
                        itemId = itemId,
                        name = itemId,
                        category = "Unknown",
                        count = minItemData.count
                    }
                end
            end
        end
    end

    localPlayerInventory = reconstructedInventory
    Log("Full inventory reconstructed. Item count: " .. tablelength(localPlayerInventory), "info", "CNR_INV_CLIENT")

    SendNUIMessage({
        action = 'refreshSellListIfNeeded'
    })

    EquipInventoryWeapons()
    Log("UpdateFullInventory: Called EquipInventoryWeapons() after inventory reconstruction.", "info", "CNR_INV_CLIENT")
end

-- Equipment function for inventory weapons
local failedWeaponEquipWarnings = {}

local function GiveRoleWeapon(playerPed, weaponName, ammoCount, equipNow)
    local weaponHash = GetHashKey(weaponName)
    if weaponHash == 0 or weaponHash == -1 then
        return false
    end

    GiveWeaponToPed(playerPed, weaponHash, ammoCount or 0, false, equipNow == true)
    SetPedAmmo(playerPed, weaponHash, ammoCount or 0)
    return HasPedGotWeapon(playerPed, weaponHash, false)
end

local function ApplyRoleStarterWeapons(currentRole)
    if isJailed then
        return
    end

    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then
        return
    end

    if currentRole == "cop" then
        GiveRoleWeapon(playerPed, "WEAPON_STUNGUN", 5, true)
        GiveRoleWeapon(playerPed, "WEAPON_NIGHTSTICK", 1, false)
        GiveRoleWeapon(playerPed, "WEAPON_FLASHLIGHT", 1, false)
        GiveRoleWeapon(playerPed, "WEAPON_PISTOL", Config.DefaultWeaponAmmo and Config.DefaultWeaponAmmo.weapon_pistol or 60, false)
    elseif currentRole == "robber" then
        GiveRoleWeapon(playerPed, "WEAPON_BAT", 1, true)
    end
end

function EquipInventoryWeapons()
    local playerPed = PlayerPedId()

    if not playerPed or playerPed == 0 or playerPed == -1 then
        Log("EquipInventoryWeapons: Invalid playerPed. Cannot equip weapons/armor.", "error", "CNR_INV_CLIENT")
        return
    end

    localPlayerEquippedItems = {}
    Log("EquipInventoryWeapons: Starting equipment process. Inv count: " .. tablelength(localPlayerInventory), "info", "CNR_INV_CLIENT")

    if not localPlayerInventory or tablelength(localPlayerInventory) == 0 then
        Log("EquipInventoryWeapons: Player inventory is empty or nil.", "info", "CNR_INV_CLIENT")
        return
    end

    RemoveAllPedWeapons(playerPed, true)
    Citizen.Wait(500)

    local processedItemCount = 0
    local weaponsEquipped = 0
    local armorApplied = false

    for itemId, itemData in pairs(localPlayerInventory) do
        processedItemCount = processedItemCount + 1

        if type(itemData) == "table" and itemData.category and itemData.count and itemData.name then
            if itemData.category == "Armor" and itemData.count > 0 and not armorApplied then
                local armorAmount = 100
                if itemId == "heavy_armor" then
                    armorAmount = 200
                end

                SetPedArmour(playerPed, armorAmount)
                armorApplied = true
                Log(string.format("  ✓ APPLIED ARMOR: %s (Amount: %d)", itemData.name or itemId, armorAmount), "info", "CNR_INV_CLIENT")

            elseif (itemData.category == "Weapons" or itemData.category == "Melee Weapons" or
                   (itemData.category == "Utility" and string.find(itemId, "weapon_"))) and itemData.count > 0 then
                
                local weaponHash = 0
                local attemptedHashes = {}
                
                weaponHash = GetHashKey(itemId)
                table.insert(attemptedHashes, itemId .. " -> " .. weaponHash)
                
                if weaponHash == 0 or weaponHash == -1 then
                    local upperItemId = string.upper(itemId)
                    weaponHash = GetHashKey(upperItemId)
                    table.insert(attemptedHashes, upperItemId .. " -> " .. weaponHash)
                end
                
                if (weaponHash == 0 or weaponHash == -1) and not string.find(itemId, "weapon_") then
                    local prefixedId = "weapon_" .. itemId
                    weaponHash = GetHashKey(prefixedId)
                    table.insert(attemptedHashes, prefixedId .. " -> " .. weaponHash)
                end

                if weaponHash ~= 0 and weaponHash ~= -1 then
                    local ammoCount = itemData.ammo
                    if ammoCount == nil then
                        if Config and Config.DefaultWeaponAmmo and Config.DefaultWeaponAmmo[itemId] then
                           ammoCount = Config.DefaultWeaponAmmo[itemId]
                        else
                           ammoCount = 250
                        end
                    end

                    if not HasWeaponAssetLoaded(weaponHash) then
                        RequestWeaponAsset(weaponHash, 31, 0)
                        local loadTimeout = 0
                        while not HasWeaponAssetLoaded(weaponHash) and loadTimeout < 50 do
                            Citizen.Wait(100)
                            loadTimeout = loadTimeout + 1
                        end
                    end

                    GiveWeaponToPed(playerPed, weaponHash, ammoCount, false, false)
                    Citizen.Wait(150)

                    if not HasPedGotWeapon(playerPed, weaponHash, false) and GiveDelayedWeaponToPed then
                        GiveDelayedWeaponToPed(playerPed, weaponHash, ammoCount, false)
                        Citizen.Wait(150)
                    end

                    SetPedAmmo(playerPed, weaponHash, ammoCount)
                    
                    local hasWeapon = HasPedGotWeapon(playerPed, weaponHash, false)
                    if hasWeapon then
                        weaponsEquipped = weaponsEquipped + 1
                        localPlayerEquippedItems[itemId] = true
                        Log(string.format("  ✓ EQUIPPED: %s (ID: %s, Hash: %s) Ammo: %d", itemData.name or itemId, itemId, weaponHash, ammoCount), "info", "CNR_INV_CLIENT")
                    else
                        localPlayerEquippedItems[itemId] = false
                        if not failedWeaponEquipWarnings[itemId] then
                            failedWeaponEquipWarnings[itemId] = true
                            Log(string.format("  ⚠ SKIPPED_UNSUPPORTED_WEAPON: %s (ID: %s, Hash: %s)", itemData.name or itemId, itemId, weaponHash), "warn", "CNR_INV_CLIENT")
                        end
                    end
                end
            end
        end
    end

    ApplyRoleStarterWeapons(role or playerData.role)
    Log(string.format("EquipInventoryWeapons: Finished. Processed %d items. Successfully equipped %d weapons. Armor applied: %s", processedItemCount, weaponsEquipped, armorApplied and "Yes" or "No"), "info", "CNR_INV_CLIENT")
end


-- Function to get local inventory
function GetLocalInventory()
    return localPlayerInventory
end

-- Function to toggle inventory UI
function ToggleInventoryUI()
    if isInventoryOpen then
        TriggerEvent('cnr:closeInventory')
    else
        TriggerEvent('cnr:openInventory')
    end
end

-- =====================================
--     CHARACTER EDITOR (CONSOLIDATED)
-- =====================================

-- Character editor variables
local isInCharacterEditor = false
local currentCharacterData = {}
local originalPlayerData = {}
local editorCamera = nil
local currentRole = nil
local currentCharacterSlot = 1
local playerCharacters = {}
local previewingUniform = false
local currentUniformPreset = nil
local currentEditorCameraMode = "full"
local isRoleSelectionVisible = false

-- Character editor UI state
local editorUI = {
    currentCategory = "appearance",
    currentSubCategory = "face",
    isVisible = false
}

local function DeepCopyCharacterData(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = DeepCopyCharacterData(entry)
    end

    return copy
end

local function DestroyCharacterEditorCamera()
    if editorCamera and DoesCamExist(editorCamera) then
        RenderScriptCams(false, true, 250, true, true)
        DestroyCam(editorCamera, false)
    end

    editorCamera = nil
end

local function UpdateCharacterEditorCamera(mode)
    if not isInCharacterEditor and not mode then
        return
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return
    end

    local cameraMode = mode or currentEditorCameraMode or "full"
    if cameraMode ~= "face" and cameraMode ~= "body" and cameraMode ~= "full" then
        cameraMode = "full"
    end

    currentEditorCameraMode = cameraMode

    local focusCoords
    local distance
    local heightOffset
    local targetHeightOffset

    if cameraMode == "face" then
        focusCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.03, 0.0)
        distance = 0.82
        heightOffset = 0.01
        targetHeightOffset = 0.0
    elseif cameraMode == "body" then
        focusCoords = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.98)
        distance = 1.85
        heightOffset = 0.08
        targetHeightOffset = 0.03
    else
        focusCoords = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.9)
        distance = 2.45
        heightOffset = 0.12
        targetHeightOffset = 0.02
    end

    local heading = GetEntityHeading(ped)
    local headingRadians = math.rad(heading)
    local forwardVector = vector3(-math.sin(headingRadians), math.cos(headingRadians), 0.0)
    local targetCoords = focusCoords + vector3(0.0, 0.0, targetHeightOffset)
    local camX = focusCoords.x - forwardVector.x * distance
    local camY = focusCoords.y - forwardVector.y * distance
    local camZ = focusCoords.z + heightOffset

    if not editorCamera or not DoesCamExist(editorCamera) then
        editorCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    end

    SetCamCoord(editorCamera, camX, camY, camZ)
    PointCamAtCoord(editorCamera, targetCoords.x, targetCoords.y, targetCoords.z)
    SetCamActive(editorCamera, true)
    SetCamFov(editorCamera, cameraMode == "face" and 30.0 or (cameraMode == "body" and 42.0 or 52.0))
    RenderScriptCams(true, true, 250, true, true)
end

local function GetEntryCoords(entry)
    if not entry then
        return nil
    end

    if type(entry) == "vector3" or type(entry) == "vector4" then
        return vector3(entry.x, entry.y, entry.z)
    end

    local location = entry.location or entry.pos or entry.coords
    if location then
        if type(location) == "vector3" or type(location) == "vector4" then
            return vector3(location.x, location.y, location.z)
        end

        if type(location) == "table" and location.x and location.y and location.z then
            return vector3(location.x, location.y, location.z)
        end
    end

    if entry.x and entry.y and entry.z then
        return vector3(entry.x, entry.y, entry.z)
    end

    return nil
end

local function GetEntryHeading(entry, fallbackHeading)
    if not entry then
        return fallbackHeading or 0.0
    end

    if type(entry) == "vector4" then
        return entry.w
    end

    local location = entry.location or entry.pos or entry.coords
    if type(location) == "vector4" then
        return location.w
    end

    if type(location) == "table" and location.w then
        return location.w
    end

    return entry.heading or fallbackHeading or 0.0
end

local function GetVendorIdentityKey(vendor)
    if not vendor or not vendor.location then
        return nil
    end

    return tostring(vendor.id or (vendor.name or "vendor") .. "_" .. vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z)
end

local function IsMedicalStoreVendor(vendor)
    return vendor and (vendor.storeType == "medical" or vendor.name == "Medical Store")
end

local function GetMedicalStoreBlipName(vendor)
    if not vendor then
        return "Medical Store"
    end

    return vendor.blipName or vendor.name or "Medical Store"
end

local function GetVehicleTypeLabelFromClass(vehicleClass)
    if vehicleClass == 15 then
        return "Helicopter"
    elseif vehicleClass == 16 then
        return "Plane"
    elseif vehicleClass == 14 then
        return "Boat"
    elseif vehicleClass == 8 then
        return "Motorcycle"
    end

    return "Vehicle"
end

local function ResolveWeaponDisplayLabel(weaponHash)
    if not weaponHash or weaponHash == 0 then
        return "Unarmed"
    end

    local label = nil
    if type(GetWeaponDisplayNameFromHash) == "function" and type(GetLabelText) == "function" then
        local weaponTextKey = GetWeaponDisplayNameFromHash(weaponHash)
        if weaponTextKey and weaponTextKey ~= "" then
            local translated = GetLabelText(weaponTextKey)
            if translated and translated ~= "NULL" then
                label = translated
            end
        end
    end

    return label or tostring(weaponHash)
end

local function ResolveVehicleDisplayLabel(vehicle)
    if not vehicle or vehicle == 0 then
        return nil, nil
    end

    local vehicleClass = GetVehicleClass(vehicle)
    local vehicleType = GetVehicleTypeLabelFromClass(vehicleClass)
    local modelName = tostring(GetEntityModel(vehicle))

    if type(GetDisplayNameFromVehicleModel) == "function" and type(GetLabelText) == "function" then
        local displayName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
        if displayName and displayName ~= "" then
            local translated = GetLabelText(displayName)
            modelName = (translated and translated ~= "NULL") and translated or displayName
        end
    end

    return vehicleType, modelName
end

local function BuildStreetLabelFromCoords(coords)
    if not coords or coords.x == nil or coords.y == nil or coords.z == nil then
        return "Unknown"
    end

    if type(GetStreetNameAtCoord) ~= "function" or type(GetStreetNameFromHashKey) ~= "function" then
        return string.format("%d, %d", math.floor(coords.x), math.floor(coords.y))
    end

    local primaryHash, crossingHash = GetStreetNameAtCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local primaryName = (primaryHash and primaryHash ~= 0) and GetStreetNameFromHashKey(primaryHash) or ""
    local crossingName = (crossingHash and crossingHash ~= 0) and GetStreetNameFromHashKey(crossingHash) or ""

    if primaryName ~= "" and crossingName ~= "" then
        return string.format("%s / %s", primaryName, crossingName)
    end

    if primaryName ~= "" then
        return primaryName
    end

    if crossingName ~= "" then
        return crossingName
    end

    return string.format("%d, %d", math.floor(coords.x), math.floor(coords.y))
end

local function EnhancePoliceCadPayload(cadData)
    if type(cadData) ~= "table" then
        return cadData
    end

    local enhancedPayload = {
        officers = {},
        calls = {},
        suspects = {},
        players = {},
        generatedAt = cadData.generatedAt or os.time()
    }

    for _, officer in ipairs(cadData.officers or {}) do
        local enhancedOfficer = {}
        for key, value in pairs(officer) do
            enhancedOfficer[key] = value
        end

        local playerIndex = GetPlayerFromServerId(officer.serverId or -1)
        if playerIndex and playerIndex ~= -1 then
            local officerPed = GetPlayerPed(playerIndex)
            if officerPed and officerPed ~= 0 and DoesEntityExist(officerPed) then
                local entityToTrack = officerPed
                local vehicleType = nil
                local vehicleModel = nil
                if IsPedInAnyVehicle(officerPed, false) then
                    entityToTrack = GetVehiclePedIsIn(officerPed, false)
                    vehicleType, vehicleModel = ResolveVehicleDisplayLabel(entityToTrack)
                end

                local coords = GetEntityCoords(officerPed)
                enhancedOfficer.coords = {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z
                }
                enhancedOfficer.speedMph = math.floor((GetEntitySpeed(entityToTrack) * 2.236936) + 0.5)
                enhancedOfficer.vehicleType = vehicleType or enhancedOfficer.vehicleType
                enhancedOfficer.vehicleModel = vehicleModel or enhancedOfficer.vehicleModel
                enhancedOfficer.equipped = ResolveWeaponDisplayLabel(GetSelectedPedWeapon(officerPed))
            end
        end

        enhancedOfficer.locationLabel = BuildStreetLabelFromCoords(enhancedOfficer.coords)

        enhancedPayload.officers[#enhancedPayload.officers + 1] = enhancedOfficer
    end

    for _, call in ipairs(cadData.calls or {}) do
        local enhancedCall = {}
        for key, value in pairs(call) do
            enhancedCall[key] = value
        end
        enhancedCall.locationLabel = BuildStreetLabelFromCoords(enhancedCall.coords)
        enhancedPayload.calls[#enhancedPayload.calls + 1] = enhancedCall
    end

    for _, suspect in ipairs(cadData.suspects or {}) do
        local enhancedSuspect = {}
        for key, value in pairs(suspect) do
            enhancedSuspect[key] = value
        end
        enhancedSuspect.locationLabel = BuildStreetLabelFromCoords(enhancedSuspect.coords)
        enhancedPayload.suspects[#enhancedPayload.suspects + 1] = enhancedSuspect
    end

    for _, playerEntry in ipairs(cadData.players or {}) do
        local enhancedPlayer = {}
        for key, value in pairs(playerEntry) do
            enhancedPlayer[key] = value
        end
        enhancedPayload.players[#enhancedPayload.players + 1] = enhancedPlayer
    end

    return enhancedPayload
end

local function RemovePoliceDispatchBlip(callId)
    local normalizedCallId = tonumber(callId)
    local blip = normalizedCallId and activePoliceDispatchBlips[normalizedCallId] or nil
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    if normalizedCallId then
        activePoliceDispatchBlips[normalizedCallId] = nil
    end
end

local function SyncPoliceDispatchBlips(cadCalls)
    if role ~= "cop" then
        for callId, _ in pairs(activePoliceDispatchBlips) do
            RemovePoliceDispatchBlip(callId)
        end
        return
    end

    local activeCallIds = {}
    for _, call in ipairs(cadCalls or {}) do
        local callId = tonumber(call and call.id)
        local coords = call and call.coords or nil
        if callId and coords and coords.x and coords.y and coords.z and (call.requestBackup == true or call.urgent == true) then
            activeCallIds[callId] = true

            local blip = activePoliceDispatchBlips[callId]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
                SetBlipSprite(blip, 161)
                SetBlipScale(blip, call.urgent and 1.35 or 1.15)
                SetBlipColour(blip, call.urgent and 1 or 5)
                SetBlipAlpha(blip, 255)
                SetBlipAsShortRange(blip, false)
                SetBlipHighDetail(blip, true)
                SetBlipBright(blip, true)
                SetBlipFlashes(blip, true)
                SetBlipFlashInterval(blip, call.urgent and 350 or 600)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(string.format("%s #%d", call.urgent and "🚨 Urgent Backup" or "🚨 Backup Request", callId))
                EndTextCommandSetBlipName(blip)
                activePoliceDispatchBlips[callId] = blip
            end

            SetBlipCoords(blip, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
        end
    end

    for callId, _ in pairs(activePoliceDispatchBlips) do
        if not activeCallIds[callId] then
            RemovePoliceDispatchBlip(callId)
        end
    end
end

local function GetRoleSpawnHeading(playerRole)
    if playerRole == "cop" then
        return 270.0
    elseif playerRole == "robber" then
        return 180.0
    end

    return 0.0
end

local function TeleportPlayerToEntry(playerPed, entry, heading)
    local targetCoords = GetEntryCoords(entry)
    if not targetCoords then
        return false
    end

    local targetHeading = GetEntryHeading(entry, heading or 0.0)

    FreezeEntityPosition(playerPed, true)
    RequestCollisionAtCoord(targetCoords.x, targetCoords.y, targetCoords.z)

    SetEntityCoordsNoOffset(playerPed, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false)
    SetEntityHeading(playerPed, targetHeading)

    local attempts = 0
    while attempts < 30 and not HasCollisionLoadedAroundEntity(playerPed) do
        Citizen.Wait(50)
        RequestCollisionAtCoord(targetCoords.x, targetCoords.y, targetCoords.z)
        attempts = attempts + 1
    end

    SetEntityCoordsNoOffset(playerPed, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false)
    SetEntityHeading(playerPed, targetHeading)
    FreezeEntityPosition(playerPed, false)

    return true
end

local function QueueInventoryReequip(delayMs)
    Citizen.SetTimeout(delayMs or 1000, function()
        local currentResourceName = GetCurrentResourceName()
        if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
            exports[currentResourceName]:EquipInventoryWeapons()
        end
    end)
end

-- Get default character data
function GetDefaultCharacterData()
    local defaultData = {}
    
    if not Config.CharacterEditor or not Config.CharacterEditor.defaultCharacter then
        return {
            model = "mp_m_freemode_01",
            face = 0,
            skin = 0,
            hair = 0,
            hairColor = 0,
            hairHighlight = 0,
            beard = -1,
            beardColor = 0,
            beardOpacity = 1.0,
            eyebrows = -1,
            eyebrowsColor = 0,
            eyebrowsOpacity = 1.0,
            eyeColor = 0,
            faceFeatures = {
                noseWidth = 0.0,
                noseHeight = 0.0,
                noseLength = 0.0,
                noseBridge = 0.0,
                noseTip = 0.0,
                noseShift = 0.0,
                browHeight = 0.0,
                browWidth = 0.0,
                cheekboneHeight = 0.0,
                cheekboneWidth = 0.0,
                cheeksWidth = 0.0,
                eyesOpening = 0.0,
                lipsThickness = 0.0,
                jawWidth = 0.0,
                jawHeight = 0.0,
                chinLength = 0.0,
                chinPosition = 0.0,
                chinWidth = 0.0,
                chinShape = 0.0,
                neckWidth = 0.0
            },
            components = {},
            props = {},
            tattoos = {}
        }
    end
    
    for k, v in next, Config.CharacterEditor.defaultCharacter do
        if type(v) == "table" then
            defaultData[k] = {}
            for k2, v2 in next, v do
                defaultData[k][k2] = v2
            end
        else
            defaultData[k] = v
        end
    end
    return defaultData
end

-- Apply character data to ped
function ApplyCharacterData(characterData, ped)
    if not characterData or not ped or not DoesEntityExist(ped) then
        return false
    end

    for propId = 0, 7 do
        ClearPedProp(ped, propId)
    end

    local clothingComponents = characterData.components or {}
    for componentId = 0, 11 do
        if componentId ~= 0 and componentId ~= 2 and not clothingComponents[tostring(componentId)] and not clothingComponents[componentId] then
            SetPedComponentVariation(ped, componentId, 0, 0, 0)
        end
    end

    SetPedHeadBlendData(ped, characterData.face or 0, characterData.face or 0, 0, 
                       characterData.skin or 0, characterData.skin or 0, 0, 
                       0.5, 0.5, 0.0, false)

    SetPedComponentVariation(ped, 2, characterData.hair or 0, 0, 0)
    SetPedHairColor(ped, characterData.hairColor or 0, characterData.hairHighlight or 0)

    if characterData.faceFeatures then
        local features = {
            {0, characterData.faceFeatures.noseWidth or 0.0},
            {1, characterData.faceFeatures.noseHeight or 0.0},
            {2, characterData.faceFeatures.noseLength or 0.0},
            {3, characterData.faceFeatures.noseBridge or 0.0},
            {4, characterData.faceFeatures.noseTip or 0.0},
            {5, characterData.faceFeatures.noseShift or 0.0},
            {6, characterData.faceFeatures.browHeight or 0.0},
            {7, characterData.faceFeatures.browWidth or 0.0},
            {8, characterData.faceFeatures.cheekboneHeight or 0.0},
            {9, characterData.faceFeatures.cheekboneWidth or 0.0},
            {10, characterData.faceFeatures.cheeksWidth or 0.0},
            {11, characterData.faceFeatures.eyesOpening or 0.0},
            {12, characterData.faceFeatures.lipsThickness or 0.0},
            {13, characterData.faceFeatures.jawWidth or 0.0},
            {14, characterData.faceFeatures.jawHeight or 0.0},
            {15, characterData.faceFeatures.chinLength or 0.0},
            {16, characterData.faceFeatures.chinPosition or 0.0},
            {17, characterData.faceFeatures.chinWidth or 0.0},
            {18, characterData.faceFeatures.chinShape or 0.0},
            {19, characterData.faceFeatures.neckWidth or 0.0}
        }
        
        for _, feature in ipairs(features) do
            SetPedFaceFeature(ped, feature[1], feature[2])
        end
    end

    local overlays = {
        {1, characterData.beard or -1, characterData.beardOpacity or 1.0, characterData.beardColor or 0, characterData.beardColor or 0},
        {2, characterData.eyebrows or -1, characterData.eyebrowsOpacity or 1.0, characterData.eyebrowsColor or 0, characterData.eyebrowsColor or 0},
        {5, characterData.blush or -1, characterData.blushOpacity or 0.0, characterData.blushColor or 0, characterData.blushColor or 0},
        {8, characterData.lipstick or -1, characterData.lipstickOpacity or 0.0, characterData.lipstickColor or 0, characterData.lipstickColor or 0},
        {4, characterData.makeup or -1, characterData.makeupOpacity or 0.0, characterData.makeupColor or 0, characterData.makeupColor or 0},
        {3, characterData.ageing or -1, characterData.ageingOpacity or 0.0, 0, 0},
        {6, characterData.complexion or -1, characterData.complexionOpacity or 0.0, 0, 0},
        {7, characterData.sundamage or -1, characterData.sundamageOpacity or 0.0, 0, 0},
        {9, characterData.freckles or -1, characterData.frecklesOpacity or 0.0, 0, 0},
        {0, characterData.bodyBlemishes or -1, characterData.bodyBlemishesOpacity or 0.0, 0, 0},
        {10, characterData.chesthair or -1, characterData.chesthairOpacity or 0.0, characterData.chesthairColor or 0, characterData.chesthairColor or 0},
        {11, characterData.addBodyBlemishes or -1, characterData.addBodyBlemishesOpacity or 0.0, 0, 0},
        {12, characterData.moles or -1, characterData.molesOpacity or 0.0, 0, 0}
    }

    for _, overlay in ipairs(overlays) do
        if overlay[2] ~= -1 then
            SetPedHeadOverlay(ped, overlay[1], overlay[2], overlay[3])
            if overlay[4] ~= 0 or overlay[5] ~= 0 then
                SetPedHeadOverlayColor(ped, overlay[1], 1, overlay[4], overlay[5])
            end
        else
            SetPedHeadOverlay(ped, overlay[1], 255, 0.0)
        end
    end

    SetPedEyeColor(ped, characterData.eyeColor or 0)

    if characterData.components then
        for componentId, component in pairs(characterData.components) do
            SetPedComponentVariation(ped, tonumber(componentId), component.drawable, component.texture, 0)
        end
    end

    if characterData.props then
        for propId, prop in pairs(characterData.props) do
            if prop.drawable == -1 then
                ClearPedProp(ped, tonumber(propId))
            else
                SetPedPropIndex(ped, tonumber(propId), prop.drawable, prop.texture, true)
            end
        end
    end

    if characterData.tattoos then
        ClearPedDecorations(ped)
        for _, tattoo in ipairs(characterData.tattoos) do
            AddPedDecorationFromHashes(ped, GetHashKey(tattoo.collection), GetHashKey(tattoo.name))
        end
    end

    return true
end

-- Get current character data
function GetCurrentCharacterData(ped)
    if not ped or not DoesEntityExist(ped) then
        return nil
    end
    return DeepCopyCharacterData(currentCharacterData)
end

local function SetMenuFocus(hasFocus, hasCursor)
    SetNuiFocus(hasFocus, hasCursor)
    SetNuiFocusKeepInput(false)
end

-- Open character editor
function OpenCharacterEditor(role, characterSlot)
    if isInCharacterEditor then
        return
    end

    currentRole = role or "cop"
    currentCharacterSlot = characterSlot or 1
    
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return
    end
    
    local characterKey = currentRole .. "_" .. currentCharacterSlot
    if playerCharacters[characterKey] then
        currentCharacterData = DeepCopyCharacterData(playerCharacters[characterKey])
    else
        currentCharacterData = GetDefaultCharacterData()
        local currentModel = GetEntityModel(ped)
        if currentModel == GetHashKey("mp_f_freemode_01") then
            currentCharacterData.model = "mp_f_freemode_01"
        else
            currentCharacterData.model = "mp_m_freemode_01"
        end
    end

    originalPlayerData = DeepCopyCharacterData(currentCharacterData)
    
    local modelToUse = currentCharacterData.model or "mp_m_freemode_01"
    local modelHash = GetHashKey(modelToUse)
    
    RequestModel(modelHash)
    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 100 do
        Citizen.Wait(50)
        attempts = attempts + 1
    end
    
    if HasModelLoaded(modelHash) then
        SetPlayerModel(PlayerId(), modelHash)
        Citizen.Wait(100)
        ped = PlayerPedId()
    end

    local previewLocation = vector3(-1042.0, -2745.0, 21.36)
    SetEntityCoords(ped, previewLocation.x, previewLocation.y, previewLocation.z, false, false, false, true)
    SetEntityHeading(ped, 180.0)
    
    Wait(200)
    
    DisplayHud(false)
    DisplayRadar(false)
    
    Wait(100)
    
    ApplyCharacterData(currentCharacterData, ped)
    
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    
    isInCharacterEditor = true
    isRoleSelectionVisible = false
    currentEditorCameraMode = "full"
    DestroyCharacterEditorCamera()
    UpdateCharacterEditorCamera(currentEditorCameraMode)
    editorUI.isVisible = true
    
    SendNUIMessage({
        action = 'openCharacterEditor',
        role = currentRole,
        characterSlot = currentCharacterSlot,
        characterData = currentCharacterData,
        uniformPresets = (Config.CharacterEditor and Config.CharacterEditor.uniformPresets and Config.CharacterEditor.uniformPresets[currentRole]) or {},
        customizationRanges = (Config.CharacterEditor and Config.CharacterEditor.customization) or {},
        playerCharacters = playerCharacters
    })
    
    Citizen.SetTimeout(100, function()
        if isInCharacterEditor then
            SetMenuFocus(true, true)
        end
    end)
end

-- Close character editor
function CloseCharacterEditor(save)
    if not isInCharacterEditor then
        return
    end

    local ped = PlayerPedId()
    
    SetNuiFocus(false, false)
    
    if save then
        local characterKey = string.format("%s_%d", currentRole, currentCharacterSlot)
        
        if currentCharacterData and type(currentCharacterData) == "table" then
            local characterToSave = DeepCopyCharacterData(currentCharacterData)
            playerCharacters[characterKey] = characterToSave
            TriggerServerEvent('cnr:saveCharacterData', characterKey, characterToSave)
        end
    else
        if originalPlayerData then
            currentCharacterData = DeepCopyCharacterData(originalPlayerData)
            ApplyCharacterData(currentCharacterData, ped)
        end
    end
    
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    DestroyCharacterEditorCamera()
    
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    
    if currentRole and Config.SpawnPoints and Config.SpawnPoints[currentRole] then
        local spawnPoint = Config.SpawnPoints[currentRole]
        local spawnCoords = GetEntryCoords(spawnPoint)
        if spawnCoords then
            SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, true)
            SetEntityHeading(ped, GetEntryHeading(spawnPoint, GetRoleSpawnHeading(currentRole)))
        end
    end
    
    isInCharacterEditor = false
    editorUI.isVisible = false
    previewingUniform = false
    currentUniformPreset = nil
    currentRole = nil
    currentCharacterSlot = 1
    
    SendNUIMessage({
        action = 'closeCharacterEditor'
    })
    
    DisplayHud(true)
    DisplayRadar(true)
end

local function ApplyUniformPresetForCurrentRole(presetIndex)
    local rolePresets = Config.CharacterEditor and Config.CharacterEditor.uniformPresets and Config.CharacterEditor.uniformPresets[currentRole]
    local preset = rolePresets and rolePresets[presetIndex]
    if not preset then
        return false
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end

    currentUniformPreset = presetIndex
    currentCharacterData.components = currentCharacterData.components or {}
    currentCharacterData.props = currentCharacterData.props or {}

    if preset.components then
        for componentId, componentData in pairs(preset.components) do
            currentCharacterData.components[componentId] = {
                drawable = componentData.drawable or 0,
                texture = componentData.texture or 0
            }
        end
    end

    if preset.props then
        for propId, propData in pairs(preset.props) do
            currentCharacterData.props[propId] = {
                drawable = propData.drawable or -1,
                texture = propData.texture or 0
            }
        end
    end

    ApplyCharacterData(currentCharacterData, ped)
    return true
end

-- =====================================
--     PROGRESSION SYSTEM (CONSOLIDATED)
-- =====================================

-- Progression variables
local playerAbilities = {}
local currentChallenges = {}
local activeSeasonalEvent = nil
local prestigeInfo = nil
local progressionUIVisible = false
local lastXPGain = 0
local xpGainTimer = 0
local currentXP = 0
local currentLevel = 1
local currentNextLvlXP = 100

-- Enhanced logging function
local function LogProgressionClient(message, level)
    level = level or "info"
    if Config and Config.DebugLogging then
        Log(message, level, "CNR_PROGRESSION_CLIENT")
    end
end

-- Show enhanced notification
local function ShowProgressionNotification(message, type, duration)
    type = type or "info"
    duration = duration or 5000
    
    SendNUIMessage({
        action = "showProgressionNotification",
        message = message,
        type = type,
        duration = duration
    })
    
    SetNotificationTextEntry("STRING")
    AddTextComponentString(message)
    DrawNotification(false, false)
end

-- Calculate XP for next level (client-side version)
function CalculateXpForNextLevelClient(currentLevel, role)
    if not Config or not Config.LevelingSystemEnabled or currentLevel >= (Config.MaxLevel or 50) then 
        return 0 
    end
    
    return (Config.XPTable and Config.XPTable[currentLevel]) or 1000
end

-- Update XP display with enhanced animations
function UpdateXPDisplayElements(xp, level, nextLvlXp, xpGained)
    xpGained = xpGained or 0
    
    currentXP = xp or 0
    currentLevel = level or 1
    currentNextLvlXP = nextLvlXp or 100
    lastXPGain = xpGained
    
    local totalXPForCurrentLevel = 0
    if Config and Config.XPTable then
        for i = 1, currentLevel - 1 do
            totalXPForCurrentLevel = totalXPForCurrentLevel + (Config.XPTable[i] or 1000)
        end
    end
    
    local xpInCurrentLevel = currentXP - totalXPForCurrentLevel
    local progressPercent = (xpInCurrentLevel / currentNextLvlXP) * 100
    
    SendNUIMessage({
        action = "updateProgressionDisplay",
        data = {
            currentXP = currentXP,
            currentLevel = currentLevel,
            xpForNextLevel = currentNextLvlXP,
            xpGained = xpGained,
            progressPercent = progressPercent,
            xpInCurrentLevel = xpInCurrentLevel,
            prestigeInfo = prestigeInfo,
            seasonalEvent = activeSeasonalEvent
        }
    })
    
    if xpGained > 0 then
        ShowXPGainAnimation(xpGained)
        xpGainTimer = GetGameTimer() + 3000
    end
end

-- Show XP gain animation
function ShowXPGainAnimation(amount)
    SendNUIMessage({
        action = "showXPGainAnimation",
        amount = amount,
        timestamp = GetGameTimer()
    })
    
    PlaySoundFrontend(-1, "RANK_UP", "HUD_AWARDS", true)
end

-- Play level up effects
function PlayLevelUpEffects(newLevel)
    SetTransitionTimecycleModifier("MP_Celeb_Win", 2.0)
    
    PlaySoundFrontend(-1, "RANK_UP", "HUD_AWARDS", true)
    Wait(500)
    PlaySoundFrontend(-1, "MEDAL_UP", "HUD_AWARDS", true)
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    RequestNamedPtfxAsset("scr_indep_fireworks")
    while not HasNamedPtfxAssetLoaded("scr_indep_fireworks") do
        Wait(1)
    end
    
    UseParticleFxAssetNextCall("scr_indep_fireworks")
    StartParticleFxNonLoopedAtCoord("scr_indep_fireworks_burst_spawn", 
        playerCoords.x, playerCoords.y, playerCoords.z + 2.0, 
        0.0, 0.0, 0.0, 1.0, false, false, false)
    
    SendNUIMessage({
        action = "showLevelUpAnimation",
        newLevel = newLevel,
        timestamp = GetGameTimer()
    })
    
    CreateThread(function()
        Wait(3000)
        ClearTimecycleModifier()
    end)
end

-- Safe Zone Client State
local isCurrentlyInSafeZone = false
local currentSafeZoneName = ""

-- Wanted System Expansion Client State
local currentPlayerNPCResponseEntities = {}
local corruptOfficialNPCs = {}
local currentHelpTextTarget = nil

-- Contraband collection state
local isCollectingFromDrop = nil
local collectionTimerEnd = 0
local activeDroppedItemHelpText = nil

-- Store UI state
local isCopStoreUiOpen = false
local isRobberStoreUiOpen = false
local activeStoreHelpText = nil
local lastStoreInteractionTime = 0
local STORE_INTERACTION_COOLDOWN_MS = 500

-- Jail System Client State
isJailed = false
local jailTimeRemaining = 0
local jailTimerDisplayActive = false
local jailReleaseLocation = nil
local JailMainPoint = Config.PrisonLocation or vector3(1651.0, 2570.0, 45.5)
local JailRadius = Constants.DISTANCES.SAFE_ZONE_DEFAULT_RADIUS or 50.0
local originalPlayerModelHash = nil

-- =====================================
--           HELPER FUNCTIONS
-- =====================================


-- Helper function to draw text on screen
function DrawText2D(x, y, text, scale, color)
    SetTextFont(4)
    SetTextProportional(false)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Helper function to show notifications
local function ShowNotification(text)
    if not text or text == "" then
        Log("ShowNotification: Received nil or empty text.", "warn", "CNR_CLIENT")
        return
    end
    SetNotificationTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawNotification(false, true)
end

-- Helper function to display help text
local function DisplayHelpText(text)
    if not text or text == "" then
        Log("DisplayHelpText: Received nil or empty text.", "warn", "CNR_CLIENT")
        return
    end
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function ShowPersistentStoreHelpText(text)
    if activeStoreHelpText == text then
        return
    end

    DisplayHelpText(text)
    activeStoreHelpText = text
end

local function ClearStoreHelpText()
    if activeStoreHelpText then
        ClearAllHelpMessages()
        activeStoreHelpText = nil
    end
end

local function ClearDroppedWorldItemHelpText()
    activeDroppedItemHelpText = nil
end

local function GetDroppedWorldItemCoords(drop)
    if not drop then
        return nil
    end

    if drop.object and DoesEntityExist(drop.object) then
        return GetEntityCoords(drop.object)
    end

    if drop.coords then
        return vector3(drop.coords.x, drop.coords.y, drop.coords.z)
    end

    return nil
end

local function RemoveDroppedWorldItem(dropId)
    local existing = droppedWorldItems[dropId]
    if not existing then
        return
    end

    if existing.object and DoesEntityExist(existing.object) then
        SetEntityAsMissionEntity(existing.object, true, true)
        DeleteEntity(existing.object)
    end

    droppedWorldItems[dropId] = nil
end

local function CreateDroppedWorldItem(dropData)
    if not dropData or not dropData.id or not dropData.coords then
        return
    end

    RemoveDroppedWorldItem(dropData.id)

    RequestModel(DROPPED_ITEM_MODEL)
    local attempts = 0
    while not HasModelLoaded(DROPPED_ITEM_MODEL) and attempts < 50 do
        Citizen.Wait(20)
        attempts = attempts + 1
    end

    local coords = vector3(dropData.coords.x, dropData.coords.y, dropData.coords.z)
    local dropObject = CreateObject(DROPPED_ITEM_MODEL, coords.x, coords.y, coords.z, false, false, false)

    if dropObject and dropObject ~= 0 then
        PlaceObjectOnGroundProperly(dropObject)
        FreezeEntityPosition(dropObject, true)
        SetEntityCollision(dropObject, true, true)
    end

    droppedWorldItems[dropData.id] = {
        id = dropData.id,
        itemId = dropData.itemId,
        quantity = dropData.quantity or 1,
        name = dropData.name or tostring(dropData.itemId or "Item"),
        coords = coords,
        object = dropObject
    }
end

local function IsAnyStoreUiOpen()
    return isCopStoreUiOpen or isRobberStoreUiOpen
end

-- CalculateXpForNextLevelClient function already defined in consolidated progression section

-- tablelength function already defined in consolidated inventory section

-- Helper function to spawn player at role-specific location
local function spawnPlayer(playerRole)
    if not playerRole then
        Log("Error: spawnPlayer called with nil role.", "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Could not determine spawn point. Role not set.")
        return
    end
    local spawnPoint = Config.SpawnPoints[playerRole]
    local spawnCoords = GetEntryCoords(spawnPoint)
    local spawnHeading = GetEntryHeading(spawnPoint, GetRoleSpawnHeading(playerRole))
    if spawnCoords then
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            TeleportPlayerToEntry(playerPed, spawnPoint, spawnHeading)
            ShowNotification("Spawned as " .. playerRole)
        else
            Log("spawnPlayer: playerPed invalid, cannot set coords.", "warn", "CNR_CLIENT")
        end
    else
        Log("Error: Invalid or missing spawn point for role: " .. tostring(playerRole), "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Spawn point not found for your role.")
    end
end

-- Apply role-specific visual appearance and basic loadout
local function ApplyRoleVisualsAndLoadout(newRole, oldRole)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then
        Log("ApplyRoleVisualsAndLoadout: Invalid playerPed.", "error", "CNR_CLIENT")
        return
    end
    
    RemoveAllPedWeapons(playerPed, true)
    playerWeapons = {}
    playerAmmo = {}
    
    -- Get character data from server
    local characterData = nil
    
    -- Request character data from server (will be handled asynchronously)
    TriggerServerEvent('cnr:getCharacterForRole', newRole, 1)
    
    local modelToLoad = nil
    local modelHash = nil
    
    if characterData and characterData.model then
        -- Use saved character model
        modelToLoad = characterData.model
    else
        -- Use default role models
        if newRole == "cop" then
            modelToLoad = "mp_m_freemode_01"  -- Changed to freemode for customization
        elseif newRole == "robber" then
            modelToLoad = "mp_m_freemode_01"  -- Changed to freemode for customization
        else
            modelToLoad = "mp_m_freemode_01"
        end
    end
    
    modelHash = GetHashKey(modelToLoad)
    if modelHash and modelHash ~= 0 and modelHash ~= -1 then
        RequestModel(modelHash)
        local attempts = 0
        while not HasModelLoaded(modelHash) and attempts < 100 do
            Citizen.Wait(50)
            attempts = attempts + 1
        end
        
        if HasModelLoaded(modelHash) then
            SetPlayerModel(PlayerId(), modelHash)
            Citizen.Wait(100) -- Increased wait time for model to fully load
            
            -- Get the new ped after model change
            playerPed = PlayerPedId()
            
            if characterData then
                -- Apply saved character data
                local currentResourceName = GetCurrentResourceName()
                if exports[currentResourceName] and exports[currentResourceName].ApplyCharacterData then
                    local success = exports[currentResourceName]:ApplyCharacterData(characterData, playerPed)
                    if success then
                        Log("Applied saved character data", "info", "CNR_CHARACTER_EDITOR")
                    else
                        Log("Failed to apply saved character data, using defaults", "warn", "CNR_CHARACTER_EDITOR")
                        SetPedDefaultComponentVariation(playerPed)
                    end
                else
                    Log("Character editor not available, using defaults", "warn", "CNR_CHARACTER_EDITOR")
                    SetPedDefaultComponentVariation(playerPed)
                end
            else
                -- Apply default appearance
                SetPedDefaultComponentVariation(playerPed)
                
                -- Apply basic role-specific uniform if no saved character
                if newRole == "cop" then
                    -- Basic cop uniform
                    SetPedComponentVariation(playerPed, 11, 55, 0, 0)  -- Tops - Police shirt
                    SetPedComponentVariation(playerPed, 4, 35, 0, 0)   -- Legs - Police pants
                    SetPedComponentVariation(playerPed, 6, 25, 0, 0)   -- Shoes - Police boots
                    SetPedPropIndex(playerPed, 0, 46, 0, true)         -- Hat - Police cap
                elseif newRole == "robber" then
                    -- Basic robber outfit
                    SetPedComponentVariation(playerPed, 11, 4, 0, 0)   -- Tops - Casual shirt
                    SetPedComponentVariation(playerPed, 4, 1, 0, 0)    -- Legs - Jeans
                    SetPedComponentVariation(playerPed, 6, 1, 0, 0)    -- Shoes - Sneakers
                    SetPedPropIndex(playerPed, 0, 18, 0, true)         -- Hat - Beanie
                end
            end
            
            SetModelAsNoLongerNeeded(modelHash)
        else
            Log(string.format("ApplyRoleVisualsAndLoadout: Failed to load model %s after 100 attempts.", modelToLoad), "error", "CNR_CLIENT")
        end
    else
        Log(string.format("ApplyRoleVisualsAndLoadout: Invalid model hash for %s.", modelToLoad), "error", "CNR_CLIENT")
    end
    
    Citizen.Wait(500)
    playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then
        Log("ApplyRoleVisualsAndLoadout: Invalid playerPed after model change attempt.", "error", "CNR_CLIENT")
        return
    end
    
    if newRole == "cop" then
        ApplyRoleStarterWeapons("cop")
        playerWeapons["weapon_stungun"] = true
        playerAmmo["weapon_stungun"] = 5
    elseif newRole == "robber" then
        ApplyRoleStarterWeapons("robber")
        playerWeapons["weapon_bat"] = true
        playerAmmo["weapon_bat"] = 1

        -- Note: Robber vehicles are spawned on resource start, not per-player
    end
    ShowNotification(string.format("~g~Role changed to %s. Model and basic loadout applied.", newRole))

   -- Equip weapons from inventory after role visuals and loadout are applied
   Citizen.Wait(50) -- Optional small delay to ensure ped model is fully set and previous weapons are processed.
   local currentResourceName = GetCurrentResourceName()
   if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
       exports[currentResourceName]:EquipInventoryWeapons()
   else
        Log(string.format("ApplyRoleVisualsAndLoadout: Could not find export EquipInventoryWeapons in resource %s.", currentResourceName), "error", "CNR_CLIENT")
   end
end

-- Ensure SetWantedLevelForPlayerRole is defined before all uses
local function SetWantedLevelForPlayerRole(stars, points)
    local playerId = PlayerId()
    
    -- Always set the game's wanted level to 0 to prevent the native wanted UI from showing
    SetPlayerWantedLevel(playerId, 0, false)
    SetPlayerWantedLevelNow(playerId, false)
    
    -- Instead, we use our custom UI based on the stars parameter
    currentWantedStarsClient = stars
    currentWantedPointsClient = points

    local uiLabel = ""
    for _, levelData in ipairs(Config.WantedSettings.levels or {}) do
        if levelData.stars == stars then
            uiLabel = levelData.uiLabel or levelData.description or ""
            break
        end
    end

    if uiLabel == "" and stars > 0 then
        uiLabel = "Wanted: " .. string.rep("★", stars) .. string.rep("☆", math.max(0, 5 - stars))
    end
    
    -- Show the wanted notification as the active wanted display while stars are present
    if stars > 0 then
        SendNUIMessage({
            action = 'showWantedNotification',
            stars = stars,
            points = points,
            level = uiLabel
        })
    else
        SendNUIMessage({
            action = 'hideWantedNotification'
        })
    end
end

-- Patch: Exclude protected peds from police suppression
local function IsPedProtected(ped)
    return g_protectedPolicePeds[ped] == true
end

-- =====================================
--       WANTED LEVEL NOTIFICATIONS
-- =====================================

-- Handle wanted level notifications from server
AddEventHandler('cnr:showWantedLevel', function(stars, points, level)
    SendNUIMessage({
        action = 'showWantedNotification',
        stars = stars,
        points = points,
        level = level
    })
end)

AddEventHandler('cnr:hideWantedLevel', function()
    SendNUIMessage({
        action = 'hideWantedNotification'
    })
end)

AddEventHandler('cnr:updateWantedLevel', function(stars, points, level)
    -- Ensure all parameters have default values to prevent nil concatenation errors
    stars = stars or 0
    points = points or 0
    level = level or ("" .. stars .. " star" .. (stars ~= 1 and "s" or ""))
    
    SendNUIMessage({
        action = 'showWantedNotification', 
        stars = stars,
        points = points,
        level = level
    })
end)

-- =====================================
--   NPC POLICE SUPPRESSION
-- =====================================

-- Helper: Safe call for SetDispatchServiceActive (for environments where it may not be defined)
local function SafeSetDispatchServiceActive(service, toggle)
    local hash = GetHashKey("SetDispatchServiceActive")
    if Citizen and Citizen.InvokeNative and hash then
        -- 0xDC0F817884CDD856 is the native hash for SetDispatchServiceActive
        local nativeHash = 0xDC0F817884CDD856
        local ok, err = pcall(function()
            Citizen.InvokeNative(nativeHash, service, toggle)
        end)
        if not ok then
            Log("SetDispatchServiceActive (InvokeNative) failed for service " .. tostring(service) .. ": " .. tostring(err), "warn", "CNR_CLIENT")
        end
    else
        -- fallback: do nothing
    end
end

-- Utility: Check if a ped is an NPC cop (by model or relationship group)
local function IsPedNpcCop(ped)
    if not DoesEntityExist(ped) then return false end
    local model = GetEntityModel(ped)
    local relGroup = GetPedRelationshipGroupHash(ped)
    local copModels = {
        [GetHashKey("s_m_y_cop_01")] = true,
        [GetHashKey("s_f_y_cop_01")] = true,
        [GetHashKey("s_m_y_swat_01")] = true,
        [GetHashKey("s_m_y_hwaycop_01")] = true,
        [GetHashKey("s_m_y_sheriff_01")] = true,
        [GetHashKey("s_f_y_sheriff_01")] = true,
    }
    return (copModels[model] or relGroup == GetHashKey("COP")) and not IsPedAPlayer(ped)
end

-- Aggressive police NPC suppression: Removes police NPCs and their vehicles near players with a wanted level.
Citizen.CreateThread(function()
    local policeSuppressInterval = 500 -- ms
    while true do
        Citizen.Wait(policeSuppressInterval)
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            local handle, ped = FindFirstPed()
            local success, nextPed = true, ped
            repeat
                if DoesEntityExist(ped) and ped ~= playerPed and IsPedNpcCop(ped) and not IsPedProtected(ped) then
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    local wasDriver = false
                    
                    -- Check if this ped is the driver before deleting the ped
                    if vehicle ~= 0 and DoesEntityExist(vehicle) then
                        wasDriver = GetPedInVehicleSeat(vehicle, -1) == ped
                    end
                    
                    SetEntityAsMissionEntity(ped, false, true)
                    ClearPedTasksImmediately(ped)
                    DeletePed(ped)
                    
                    -- Only delete the vehicle if the ped was the driver and no other player is in it
                    if wasDriver and vehicle ~= 0 and DoesEntityExist(vehicle) then
                        local hasPlayerInVehicle = false
                        for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
                            local seat_ped = GetPedInVehicleSeat(vehicle, i)
                            if seat_ped ~= 0 and seat_ped ~= ped and IsPedAPlayer(seat_ped) then
                                hasPlayerInVehicle = true
                                break
                            end
                        end
                        
                        -- Only delete if no players are using the vehicle
                        if not hasPlayerInVehicle then
                            SetEntityAsMissionEntity(vehicle, false, true)
                            DeleteEntity(vehicle)
                        end
                    end
                end
                success, nextPed = FindNextPed(handle)
                ped = nextPed
            until not success
            EndFindPed(handle)
        end
    end
end)

-- Prevent NPC police from responding to wanted levels (but keep wanted level for robbers)
Citizen.CreateThread(function()
    local interval = 1000
    while true do
        Citizen.Wait(interval)
        local playerId = PlayerId()
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            SetPoliceIgnorePlayer(playerPed, true)
            for i = 1, 15 do
                SafeSetDispatchServiceActive(i, false)
            end
            if role == "cop" then
                if GetPlayerWantedLevel(playerId) > 0 then
                    SetPlayerWantedLevel(playerId, 0, false)
                    SetPlayerWantedLevelNow(playerId, false)
                end
            end
        end
    end
end)

-- Enhanced GTA native wanted level suppression for all players (we use custom system)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        local playerId = PlayerId()
        local currentWantedLevel = GetPlayerWantedLevel(playerId)

        if currentWantedLevel > 0 then
            if role == "cop" then
            elseif role == "robber" then
            end
            SetPlayerWantedLevel(playerId, 0, false)
            SetPlayerWantedLevelNow(playerId, false)
        end

        -- Ensure police blips are hidden and police ignore all players (we handle this via custom system)
        SetPoliceIgnorePlayer(PlayerPedId(), true)
    end
end)

-- Unlimited Stamina Thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            RestorePlayerStamina(PlayerId(), 100.0)
        end
    end
end)

-- Inventory Key Binding
RegisterCommand('+cnr_openinventory', function()
    ToggleInventoryUI()
end, false)

RegisterCommand('-cnr_openinventory', function()
end, false)

RegisterKeyMapping('+cnr_openinventory', 'Open Inventory', 'keyboard', Config.Keybinds.openInventoryKey or 'I')

-- Register the inventory commands that are missing
RegisterCommand('getweapons', function()
    local currentResourceName = GetCurrentResourceName()
    if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
        exports[currentResourceName]:EquipInventoryWeapons()
    else
        Log("EquipInventoryWeapons export not found", "error", "CNR_CLIENT")
    end
end, false)

RegisterCommand('equipweapns', function()
    local currentResourceName = GetCurrentResourceName()
    if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
        exports[currentResourceName]:EquipInventoryWeapons()
    else
        Log("EquipInventoryWeapons export not found", "error", "CNR_CLIENT")
    end
end, false)

-- =====================================
--       WANTED LEVEL DETECTION SYSTEM
-- =====================================

-- Client-side wanted level detection removed - now handled entirely server-side
-- This ensures only robbers can get wanted levels and prevents conflicts

-- Weapon firing detection for server-side processing
CreateThread(function()
    while true do
        Wait(0)
        
        local playerPed = PlayerPedId()
        if playerPed and DoesEntityExist(playerPed) then
            if IsPedShooting(playerPed) then
                local weaponHash = GetSelectedPedWeapon(playerPed)
                local coords = GetEntityCoords(playerPed)
                
                -- Send to server for processing (server will check if player is robber)
                TriggerServerEvent('cnr:weaponFired', weaponHash, coords)
                
                -- Small delay to prevent spam
                Wait(1000)
            end
        end
    end
end)

-- Player damage detection for server-side processing
local lastHealthCheck = {}

CreateThread(function()
    while true do
        Wait(500) -- Check every 500ms
        
        local players = GetActivePlayers()
        for _, player in ipairs(players) do
            local playerId = GetPlayerServerId(player)
            local playerPed = GetPlayerPed(player)
            
            if playerPed and DoesEntityExist(playerPed) and playerId ~= GetPlayerServerId(PlayerId()) then
                local currentHealth = GetEntityHealth(playerPed)
                local maxHealth = GetEntityMaxHealth(playerPed)
                
                if not lastHealthCheck[playerId] then
                    lastHealthCheck[playerId] = currentHealth
                else
                    local lastHealth = lastHealthCheck[playerId]
                    
                    if currentHealth < lastHealth then
                        -- Player took damage
                        local damage = lastHealth - currentHealth
                        local isFatal = currentHealth <= 0
                        local weaponHash = GetPedCauseOfDeath(playerPed)
                        
                        -- Send to server for processing
                        TriggerServerEvent('cnr:playerDamaged', playerId, damage, weaponHash, isFatal)
                    end
                    
                    lastHealthCheck[playerId] = currentHealth
                end
            end
        end
    end
end)

-- =====================================
--          MISSING KEYBINDS
-- =====================================

RegisterCommand('+cnr_toggleadminpanel', function()
    if adminPanelVisible or IsAdminPanelRequestPending() then
        return
    end

    BeginAdminPanelRequest()
    TriggerServerEvent('cnr:checkAdminStatus')
end, false)

RegisterCommand('-cnr_toggleadminpanel', function() end, false)
RegisterKeyMapping('+cnr_toggleadminpanel', 'Open Admin Panel', 'keyboard', Config.Keybinds.toggleAdminPanelKey or 'F12')

RegisterCommand('+cnr_openrolemenu', function()
    if adminPanelVisible or IsAdminPanelRequestPending() or activeRoleActionMenu then
        return
    end

    TriggerServerEvent('cnr:openRoleActionMenu')
end, false)

RegisterCommand('-cnr_openrolemenu', function() end, false)
RegisterKeyMapping('+cnr_openrolemenu', 'Open Police/Robber Menu', 'keyboard', Config.Keybinds.openRoleMenuKey or 'F11')

-- F5 - Role Selection Menu
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)
        
        if IsControlJustPressed(0, 166) then -- F5 key
            TriggerEvent('cnr:showRoleSelection')
        end
    end
end)

-- Event handlers for admin status check
AddEventHandler('cnr:showAdminPanel', function(players, liveMapData)
    ClearAdminPanelRequest()
    adminPanelVisible = true
    activeRoleActionMenu = nil

    SendNUIMessage({
        action = 'hideRoleActionMenus'
    })

    -- Show admin panel UI
    SendNUIMessage({
        action = 'showAdminPanel',
        players = players or {},
        liveMapData = liveMapData or { players = {}, generatedAt = os.time() }
    })
    SetNuiFocus(true, true)
end)

AddEventHandler('cnr:showRobberMenu', function()
    if adminPanelVisible or IsAdminPanelRequestPending() then
        return
    end

    ClearAdminPanelRequest()
    activeRoleActionMenu = "robber"

    SendNUIMessage({
        action = 'hideRoleActionMenus'
    })

    -- Show robber-specific menu
    SendNUIMessage({
        action = 'showRobberMenu'
    })
    SetNuiFocus(true, true)
end)

AddEventHandler('cnr:showPoliceMenu', function()
    if adminPanelVisible or IsAdminPanelRequestPending() then
        return
    end

    ClearAdminPanelRequest()
    activeRoleActionMenu = "police"

    SendNUIMessage({
        action = 'hideRoleActionMenus'
    })

    SendNUIMessage({
        action = 'showPoliceMenu'
    })
    SetNuiFocus(true, true)
end)

AddEventHandler('cnr:adminTeleportToCoords', function(coords)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not coords then
        return
    end

    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    if coords.heading then
        SetEntityHeading(ped, coords.heading)
    end
end)

local function GetAdminControlledEntity()
    local ped = PlayerPedId()
    if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            return vehicle, ped
        end
    end

    return ped, ped
end

local function SetAdminInvisibleState(enabled)
    local entity, ped = GetAdminControlledEntity()
    adminInvisibleEnabled = enabled == true

    if not ped or ped == 0 then
        return adminInvisibleEnabled
    end

    SetEntityVisible(ped, not adminInvisibleEnabled, false)
    if adminInvisibleEnabled then
        SetEntityAlpha(ped, 125, false)
    else
        ResetEntityAlpha(ped)
    end

    if entity and entity ~= ped then
        SetEntityVisible(entity, not adminInvisibleEnabled, false)
        if adminInvisibleEnabled then
            SetEntityAlpha(entity, 180, false)
        else
            ResetEntityAlpha(entity)
        end
    end

    SetLocalPlayerVisibleLocally(true)
    return adminInvisibleEnabled
end

local function SetAdminNoClipState(enabled)
    local entity, ped = GetAdminControlledEntity()
    adminNoClipEnabled = enabled == true

    if not entity or entity == 0 then
        return adminNoClipEnabled
    end

    FreezeEntityPosition(entity, adminNoClipEnabled)
    SetEntityCollision(entity, not adminNoClipEnabled, not adminNoClipEnabled)
    SetEntityInvincible(ped, adminNoClipEnabled)

    if entity ~= ped then
        SetEntityInvincible(entity, adminNoClipEnabled)
    end

    if adminNoClipEnabled then
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    end

    return adminNoClipEnabled
end

local function StopAdminSpectate()
    if not adminSpectateTargetServerId then
        return false
    end

    NetworkSetInSpectatorMode(false, PlayerPedId())
    adminSpectateTargetServerId = nil
    ShowNotification("~g~Stopped spectating.")
    return true
end

local function StartAdminSpectate(targetServerId)
    local targetId = tonumber(targetServerId)
    if not targetId or targetId <= 0 then
        return false, "Invalid player ID."
    end

    local targetPlayer = GetPlayerFromServerId(targetId)
    if targetPlayer == -1 then
        return false, "Target is not currently available to spectate."
    end

    local targetPed = GetPlayerPed(targetPlayer)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
        return false, "Unable to spectate that player right now."
    end

    if adminSpectateTargetServerId and adminSpectateTargetServerId ~= targetId then
        StopAdminSpectate()
    end

    adminSpectateTargetServerId = targetId
    NetworkSetInSpectatorMode(true, targetPed)
    ShowNotification("~b~Spectating player " .. tostring(targetId))
    return true
end

Citizen.CreateThread(function()
    local function normalizeVector(vec)
        local magnitude = math.sqrt((vec.x * vec.x) + (vec.y * vec.y) + (vec.z * vec.z))
        if magnitude <= 0.001 then
            return vector3(0.0, 0.0, 0.0)
        end

        return vector3(vec.x / magnitude, vec.y / magnitude, vec.z / magnitude)
    end

    while true do
        if adminNoClipEnabled then
            Citizen.Wait(0)

            local entity = GetAdminControlledEntity()
            local currentCoords = GetEntityCoords(entity)
            local camRotation = GetGameplayCamRot(2)
            local headingRadians = math.rad(camRotation.z)
            local pitchRadians = math.rad(camRotation.x)
            local forward = vector3(-math.sin(headingRadians) * math.cos(pitchRadians), math.cos(headingRadians) * math.cos(pitchRadians), math.sin(pitchRadians))
            local right = vector3(math.cos(headingRadians), math.sin(headingRadians), 0.0)
            local moveVector = vector3(0.0, 0.0, 0.0)
            local speed = IsControlPressed(0, 21) and 4.5 or 1.8

            if IsControlPressed(0, 32) then
                moveVector = moveVector + forward
            end
            if IsControlPressed(0, 33) then
                moveVector = moveVector - forward
            end
            if IsControlPressed(0, 34) then
                moveVector = moveVector - right
            end
            if IsControlPressed(0, 35) then
                moveVector = moveVector + right
            end
            if IsControlPressed(0, 22) then
                moveVector = moveVector + vector3(0.0, 0.0, 1.0)
            end
            if IsControlPressed(0, 36) then
                moveVector = moveVector - vector3(0.0, 0.0, 1.0)
            end

            moveVector = normalizeVector(moveVector)
            SetEntityVelocity(entity, 0.0, 0.0, 0.0)
            SetEntityCoordsNoOffset(entity, currentCoords.x + (moveVector.x * speed), currentCoords.y + (moveVector.y * speed), currentCoords.z + (moveVector.z * speed), true, true, true)
        else
            Citizen.Wait(250)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        if adminSpectateTargetServerId then
            local targetPlayer = GetPlayerFromServerId(adminSpectateTargetServerId)
            if targetPlayer == -1 then
                StopAdminSpectate()
            else
                local targetPed = GetPlayerPed(targetPlayer)
                if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
                    StopAdminSpectate()
                end
            end

            Citizen.Wait(1000)
        else
            Citizen.Wait(1500)
        end
    end
end)

-- =====================================
--           STORE BLIP MANAGEMENT
-- =====================================

function UpdateCopStoreBlips()
    if not Config.NPCVendors then
        Log("UpdateCopStoreBlips: Config.NPCVendors not found.", "warn", "CNR_CLIENT")
        return
    end
    if type(Config.NPCVendors) ~= "table" or (getmetatable(Config.NPCVendors) and getmetatable(Config.NPCVendors).__name == "Map") then
        Log("UpdateCopStoreBlips: Config.NPCVendors is not an array. Cannot iterate.", "error", "CNR_CLIENT")
        return
    end
    for i, vendor in ipairs(Config.NPCVendors) do
        if vendor and vendor.location and vendor.name then
            local blipKey = tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z)
            if vendor.name == "Cop Store" then
                if role == "cop" then
                    if not copStoreBlips[blipKey] or not DoesBlipExist(copStoreBlips[blipKey]) then
                        local blip = AddBlipForCoord(vendor.location.x, vendor.location.y, vendor.location.z)
                        SetBlipSprite(blip, 60)
                        SetBlipColour(blip, 3)
                        SetBlipScale(blip, 0.8)
                        SetBlipAsShortRange(blip, true)
                        BeginTextCommandSetBlipName("STRING")
                        AddTextComponentSubstringPlayerName(vendor.name)
                        EndTextCommandSetBlipName(blip)
                        copStoreBlips[blipKey] = blip
                    end
                else
                    if copStoreBlips[blipKey] and DoesBlipExist(copStoreBlips[blipKey]) then
                        RemoveBlip(copStoreBlips[blipKey])
                        copStoreBlips[blipKey] = nil
                    end
                end
            else
                if copStoreBlips[blipKey] and DoesBlipExist(copStoreBlips[blipKey]) then
                    Log(string.format("Removing stray blip from copStoreBlips, associated with a non-Cop Store: '%s' at %s", vendor.name, blipKey), "warn", "CNR_CLIENT")
                    RemoveBlip(copStoreBlips[blipKey])
                    copStoreBlips[blipKey] = nil
                end
            end
        else
            Log(string.format("UpdateCopStoreBlips: Invalid vendor entry at index %d.", i), "warn", "CNR_CLIENT")
        end
    end
    for blipKey, blipId in pairs(copStoreBlips) do
        local stillExistsAndIsCopStore = false
        if Config.NPCVendors and type(Config.NPCVendors) == "table" then
            for _, vendor in ipairs(Config.NPCVendors) do
                if vendor and vendor.location and vendor.name then
                    if tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z) == blipKey and vendor.name == "Cop Store" then
                        stillExistsAndIsCopStore = true
                        break
                    end
                end
            end
        end
        if not stillExistsAndIsCopStore then
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            copStoreBlips[blipKey] = nil
        end
    end
end

-- Update Robber Store Blips (visible only to robbers)
function UpdateRobberStoreBlips()
    if not Config.NPCVendors then
        Log("UpdateRobberStoreBlips: Config.NPCVendors not found.", "warn", "CNR_CLIENT")
        return
    end
    if type(Config.NPCVendors) ~= "table" or (getmetatable(Config.NPCVendors) and getmetatable(Config.NPCVendors).__name == "Map") then
        Log("UpdateRobberStoreBlips: Config.NPCVendors is not an array. Cannot iterate.", "error", "CNR_CLIENT")
        return
    end
      for i, vendor in ipairs(Config.NPCVendors) do
        -- Skip invalid vendor entries
        if not vendor or not vendor.location or not vendor.name then
            if not vendor then
                Log(string.format("UpdateRobberStoreBlips: Nil vendor entry at index %d.", i), "warn", "CNR_CLIENT")
            elseif not vendor.location then
                Log(string.format("UpdateRobberStoreBlips: Missing location for vendor at index %d.", i), "warn", "CNR_CLIENT")
            elseif not vendor.name then
                Log(string.format("UpdateRobberStoreBlips: Missing name for vendor at index %d.", i), "warn", "CNR_CLIENT")
            end
            -- Skip processing this invalid entry
        elseif vendor and vendor.location and vendor.name then
            -- Process valid vendor entries
            if vendor.name == "Black Market Dealer" or vendor.name == "Gang Supplier" then
                local blipKey = tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z)
                
                -- Only show robber store blips to robbers
                if role == "robber" then
                    if not robberStoreBlips[blipKey] or not DoesBlipExist(robberStoreBlips[blipKey]) then
                        local blip = AddBlipForCoord(vendor.location.x, vendor.location.y, vendor.location.z)
                        if vendor.name == "Black Market Dealer" then
                            SetBlipSprite(blip, 266) -- Gun store icon
                            SetBlipColour(blip, 1) -- Red
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString("Black Market")
                            EndTextCommandSetBlipName(blip)
                        else -- Gang Supplier
                            SetBlipSprite(blip, 267) -- Ammu-nation icon
                            SetBlipColour(blip, 5) -- Yellow
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString("Gang Supplier")
                            EndTextCommandSetBlipName(blip)
                        end
                        SetBlipScale(blip, 0.8)
                        SetBlipAsShortRange(blip, true)
                        robberStoreBlips[blipKey] = blip
                    end
                else
                    -- Remove robber store blips for non-robbers
                    if robberStoreBlips[blipKey] and DoesBlipExist(robberStoreBlips[blipKey]) then
                        RemoveBlip(robberStoreBlips[blipKey])
                        robberStoreBlips[blipKey] = nil
                    end
                end
            end
        end
    end
    -- Clean up orphaned blips
    for blipKey, blipId in pairs(robberStoreBlips) do
        local stillExistsAndIsRobberStore = false
        if Config.NPCVendors and type(Config.NPCVendors) == "table" then
            for _, vendor in ipairs(Config.NPCVendors) do
                if vendor and vendor.location and vendor.name then
                    if tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z) == blipKey and (vendor.name == "Black Market Dealer" or vendor.name == "Gang Supplier") then
                        stillExistsAndIsRobberStore = true
                        break
                    end
                end
            end
        end
        if not stillExistsAndIsRobberStore then
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            robberStoreBlips[blipKey] = nil
        end
    end
end

function UpdatePublicStoreBlips()
    if type(Config.NPCVendors) ~= "table" then
        return
    end

    for _, vendor in ipairs(Config.NPCVendors) do
        if IsMedicalStoreVendor(vendor) and vendor.location then
            local blipKey = GetVendorIdentityKey(vendor)
            if blipKey and (not publicStoreBlips[blipKey] or not DoesBlipExist(publicStoreBlips[blipKey])) then
                local blip = AddBlipForCoord(vendor.location.x, vendor.location.y, vendor.location.z)
                SetBlipSprite(blip, vendor.blipSprite or 61)
                SetBlipColour(blip, vendor.blipColor or 2)
                SetBlipScale(blip, 0.85)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(GetMedicalStoreBlipName(vendor))
                EndTextCommandSetBlipName(blip)
                publicStoreBlips[blipKey] = blip
            end
        end
    end

    for blipKey, blipId in pairs(publicStoreBlips) do
        local stillExists = false
        for _, vendor in ipairs(Config.NPCVendors or {}) do
            if IsMedicalStoreVendor(vendor) and GetVendorIdentityKey(vendor) == blipKey then
                stillExists = true
                break
            end
        end

        if not stillExists then
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            publicStoreBlips[blipKey] = nil
        end
    end
end

-- =====================================
--           NPC MANAGEMENT
-- =====================================

-- Helper to spawn the Cop Store ped and protect it from suppression
function SpawnCopStorePed()
    -- Check if already spawned
    if g_spawnedNPCs["CopStore"] then
        return
    end

    local vendor = nil
    if Config and Config.NPCVendors then
        for _, v in ipairs(Config.NPCVendors) do
            if v.name == "Cop Store" then
                vendor = v
                break
            end
        end
    end
    if not vendor then
        Log("Cop Store vendor not found in Config.NPCVendors", "error", "CNR_CLIENT")
        return
    end

    local model = GetHashKey("s_m_m_ciasec_01") -- Use a unique cop-like model not used by NPC police
    RequestModel(model)
    while not HasModelLoaded(model) do Citizen.Wait(10) end

    -- Handle both vector3 and vector4 formats for location
    local x, y, z, heading
    if vendor.location.w then
        -- vector4 format
        x, y, z, heading = vendor.location.x, vendor.location.y, vendor.location.z, vendor.location.w
    else
        -- vector3 format with separate heading
        x, y, z = vendor.location.x, vendor.location.y, vendor.location.z
        heading = vendor.heading or 0.0
    end

    local ped = CreatePed(4, model, x, y, z - 1.0, heading, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false) -- Corrected: use boolean false
    SetPedCombatAttributes(ped, 17, true) -- Corrected: use boolean true
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    g_protectedPolicePeds[ped] = true
    g_spawnedNPCs["CopStore"] = ped
end

-- Helper to spawn Robber Store peds and protect them from suppression
function SpawnRobberStorePeds()
    if not Config or not Config.NPCVendors then
        Log("SpawnRobberStorePeds: Config.NPCVendors not found", "error", "CNR_CLIENT")
        return
    end
    
    for _, vendor in ipairs(Config.NPCVendors) do
        if vendor.name == "Black Market Dealer" or vendor.name == "Gang Supplier" then
            -- Check if already spawned
            if not g_spawnedNPCs[vendor.name] then
                local modelHash = GetHashKey(vendor.model or "s_m_y_dealer_01")
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do
                    Citizen.Wait(10)
                end

                -- Handle both vector3 and vector4 formats for location
                local x, y, z, heading
                if vendor.location.w then
                    -- vector4 format
                    x, y, z, heading = vendor.location.x, vendor.location.y, vendor.location.z, vendor.location.w
                else
                    -- vector3 format with separate heading
                    x, y, z = vendor.location.x, vendor.location.y, vendor.location.z
                    heading = vendor.heading or 0.0
                end

                local ped = CreatePed(4, modelHash, x, y, z - 1.0, heading, false, true)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCombatAttributes(ped, 17, true)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetEntityInvincible(ped, true)
                FreezeEntityPosition(ped, true)

                -- Add to protected peds to prevent deletion by NPC suppression
                g_protectedPolicePeds[ped] = true
                g_spawnedNPCs[vendor.name] = ped

            end
        end
    end
end

function SpawnPublicStorePeds()
    if type(Config.NPCVendors) ~= "table" then
        return
    end

    for _, vendor in ipairs(Config.NPCVendors) do
        if IsMedicalStoreVendor(vendor) and vendor.location then
            local spawnKey = GetVendorIdentityKey(vendor)
            if spawnKey and not g_spawnedNPCs[spawnKey] then
                local modelHash = GetHashKey(vendor.model or "s_m_m_doctor_01")
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do
                    Citizen.Wait(10)
                end

                local x, y, z, heading
                if vendor.location.w then
                    x, y, z, heading = vendor.location.x, vendor.location.y, vendor.location.z, vendor.location.w
                else
                    x, y, z = vendor.location.x, vendor.location.y, vendor.location.z
                    heading = vendor.heading or 0.0
                end

                local ped = CreatePed(4, modelHash, x, y, z - 1.0, heading, false, true)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCombatAttributes(ped, 17, true)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetEntityInvincible(ped, true)
                FreezeEntityPosition(ped, true)

                g_protectedPolicePeds[ped] = true
                g_spawnedNPCs[spawnKey] = ped
            end
        end
    end
end

-- Vehicle spawning system for robbers
function SpawnRobberVehicles()
    -- Prevent multiple spawning
    if g_robberVehiclesSpawned then
        return
    end

    if not Config or not Config.RobberVehicleSpawns then
        Log("SpawnRobberVehicles: Config.RobberVehicleSpawns not found", "error", "CNR_CLIENT")
        return
    end

    g_robberVehiclesSpawned = true

    for _, vehicleSpawn in ipairs(Config.RobberVehicleSpawns) do
        if vehicleSpawn.location and vehicleSpawn.model then
            local modelHash = GetHashKey(vehicleSpawn.model)
            RequestModel(modelHash)

            -- Wait for model to load
            local attempts = 0
            while not HasModelLoaded(modelHash) and attempts < 100 do
                Citizen.Wait(50)
                attempts = attempts + 1
            end
              if HasModelLoaded(modelHash) then
                -- Handle both vector3 and vector4 formats
                local x, y, z, heading
                if vehicleSpawn.location.w then
                    -- vector4 format
                    x, y, z, heading = vehicleSpawn.location.x, vehicleSpawn.location.y, vehicleSpawn.location.z, vehicleSpawn.location.w
                else
                    -- vector3 format with separate heading
                    x, y, z = vehicleSpawn.location.x, vehicleSpawn.location.y, vehicleSpawn.location.z
                    heading = vehicleSpawn.heading or 0.0
                end

                local vehicle = CreateVehicle(
                    modelHash,
                    x, y, z,
                    heading,
                    true, -- isNetwork
                    false -- netMissionEntity
                )

                if vehicle and DoesEntityExist(vehicle) then
                    -- Make vehicle available and persistent
                    SetEntityAsMissionEntity(vehicle, true, true)
                    SetVehicleOnGroundProperly(vehicle)
                    SetVehicleEngineOn(vehicle, false, true, false)
                    SetVehicleDoorsLocked(vehicle, 1) -- Unlocked
                else
                    Log(string.format("Failed to create vehicle %s", vehicleSpawn.model), "error", "CNR_CLIENT")
                end
            else
                Log(string.format("Failed to load model %s after 100 attempts", vehicleSpawn.model), "error", "CNR_CLIENT")
            end

            SetModelAsNoLongerNeeded(modelHash)
        end
    end
end

local function CreatePersistentRoleVehicle(vehicleSpawn, defaultModel, platePrefix)
    if not vehicleSpawn or not vehicleSpawn.location then
        return nil
    end

    local modelName = vehicleSpawn.model or defaultModel
    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash)

    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 100 do
        Citizen.Wait(50)
        attempts = attempts + 1
    end

    if not HasModelLoaded(modelHash) then
        Log(string.format("Failed to load vehicle model %s after 100 attempts", modelName), "error", "CNR_CLIENT")
        return nil
    end

    local spawnCoords = GetEntryCoords(vehicleSpawn)
    if not spawnCoords then
        SetModelAsNoLongerNeeded(modelHash)
        return nil
    end

    local vehicle = CreateVehicle(
        modelHash,
        spawnCoords.x, spawnCoords.y, spawnCoords.z,
        GetEntryHeading(vehicleSpawn),
        true,
        true
    )

    if vehicle and DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleEngineOn(vehicle, false, true, false)
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleNeedsToBeHotwired(vehicle, false)
        SetVehicleHasBeenOwnedByPlayer(vehicle, true)
        SetVehicleNumberPlateText(vehicle, (platePrefix or "CNR") .. tostring(#g_spawnedVehicles + 1))

        local networkId = NetworkGetNetworkIdFromEntity(vehicle)
        if networkId and networkId ~= 0 then
            SetNetworkIdCanMigrate(networkId, false)
            SetNetworkIdExistsOnAllMachines(networkId, true)
        end

        table.insert(g_spawnedVehicles, vehicle)
        return vehicle
    end

    Log(string.format("Failed to create vehicle %s", modelName), "error", "CNR_CLIENT")
    SetModelAsNoLongerNeeded(modelHash)
    return nil
end

function SpawnPoliceVehicles()
    if g_policeVehiclesSpawned then
        return
    end

    if not Config or not Config.PoliceVehicleSpawns then
        Log("SpawnPoliceVehicles: Config.PoliceVehicleSpawns not found", "error", "CNR_CLIENT")
        return
    end

    g_policeVehiclesSpawned = true

    local models = Config.PoliceVehicles or { "police", "police2" }
    for index, vehicleSpawn in ipairs(Config.PoliceVehicleSpawns) do
        vehicleSpawn.model = vehicleSpawn.model or models[((index - 1) % #models) + 1]
        CreatePersistentRoleVehicle(vehicleSpawn, "police", "PD")
    end
end

-- Call this on resource start and when player spawns
Citizen.CreateThread(function()
    Citizen.Wait(2000)
    SpawnCopStorePed()
    SpawnRobberStorePeds()
    SpawnPublicStorePeds()
    SpawnRobberVehicles() -- Added vehicle spawning for robbers
    SpawnPoliceVehicles()
    UpdatePublicStoreBlips()
    -- Initial blip setup based on current role
    if role == "cop" then
        UpdateCopStoreBlips()
    elseif role == "robber" then
        UpdateRobberStoreBlips()
    end
end)

-- =====================================
--           NETWORK EVENTS
-- =====================================

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('cnr:playerSpawned') -- Corrected event name
    roleSelectionShownForCurrentDeath = false

    -- Only show role selection if player doesn't have a role yet
    if not role or role == "" then
        isRoleSelectionVisible = true
        SendNUIMessage({ action = 'showRoleSelection', resourceName = GetCurrentResourceName() })
        SetMenuFocus(true, true)
        Citizen.SetTimeout(100, function()
            if isRoleSelectionVisible and not isInCharacterEditor then
                SetMenuFocus(true, true)
            end
        end)
    else
        -- Player already has a role, respawn them at their role's spawn point
        local spawnPoint = Config.SpawnPoints[role]
        local spawnCoords = GetEntryCoords(spawnPoint)
        if spawnCoords then
            local playerPed = PlayerPedId()
            TeleportPlayerToEntry(playerPed, spawnPoint, GetRoleSpawnHeading(role))
            ShowNotification("Respawned as " .. role)
            -- Reapply role visuals and loadout
            ApplyRoleVisualsAndLoadout(role, nil)
            QueueInventoryReequip(1250)
        end
    end
end)

RegisterNetEvent('cnr:updatePlayerData')
AddEventHandler('cnr:updatePlayerData', function(newPlayerData)
    if not newPlayerData then
        Log("Error: 'cnr:updatePlayerData' received nil data.", "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Failed to load player data.")
        return
    end
    local oldRole = playerData.role
    playerData = newPlayerData
    playerCash = newPlayerData.money or 0
    role = playerData.role
    local playerPedOnUpdate = PlayerPedId()
    -- Inventory is now handled by cnr:syncInventory event

    -- Update blips based on role
    if role == "cop" then
        UpdateCopStoreBlips()
        -- Clear robber store blips for cops
        for blipKey, blipId in pairs(robberStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            robberStoreBlips[blipKey] = nil
        end
    elseif role == "robber" then
        UpdateRobberStoreBlips()
        -- Clear cop store blips for robbers
        for blipKey, blipId in pairs(copStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            copStoreBlips[blipKey] = nil
        end
    else
        -- Clear all store blips for citizens
        for blipKey, blipId in pairs(copStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            copStoreBlips[blipKey] = nil
        end
        for blipKey, blipId in pairs(robberStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            robberStoreBlips[blipKey] = nil
        end
    end

    if role and oldRole ~= role then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            ApplyRoleVisualsAndLoadout(role, oldRole)
            Citizen.Wait(100)
            spawnPlayer(role)
            QueueInventoryReequip(1250)
        else
            Log("cnr:updatePlayerData: playerPed invalid during role change spawn.", "warn", "CNR_CLIENT")
        end
    elseif not oldRole and role and role ~= "citizen" then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            ApplyRoleVisualsAndLoadout(role, oldRole)
            Citizen.Wait(100)
            spawnPlayer(role)
            QueueInventoryReequip(1250)
        else
            Log("cnr:updatePlayerData: playerPed invalid during initial role spawn.", "warn", "CNR_CLIENT")
        end
    elseif not oldRole and role and role == "citizen" then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            spawnPlayer(role)
            QueueInventoryReequip(1250)
        else
            Log("cnr:updatePlayerData: playerPed invalid during initial citizen spawn.", "warn", "CNR_CLIENT")
        end
    end
    UpdateActivityBlips()
    SendNUIMessage({ action = 'updateMoney', cash = playerCash })
    UpdateCopStoreBlips() -- removed argument
    UpdatePublicStoreBlips()
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = playerData.xp,
        currentLevel = playerData.level,
        xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role)
    })
    ShowNotification(string.format("Data Synced: Lvl %d, XP %d, Role %s", playerData.level, playerData.xp, playerData.role))
    if newPlayerData.weapons and type(newPlayerData.weapons) == "table" then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            playerWeapons = {}
            playerAmmo = {}
            for weaponName, ammoCount in pairs(newPlayerData.weapons) do
                local weaponHash = GetHashKey(weaponName)
                if weaponHash ~= 0 and weaponHash ~= -1 then
                    GiveWeaponToPed(playerPedOnUpdate, weaponHash, ammoCount or 0, false, false)
                    playerWeapons[weaponName] = true
                    playerAmmo[weaponName] = ammoCount or 0
                else
                    print("Warning: Invalid weaponName received in newPlayerData: " .. tostring(weaponName))
                end
            end
        else
            Log("cnr:updatePlayerData: playerPed invalid, cannot give weapons.", "warn", "CNR_CLIENT")
        end
    end
    ApplyRoleStarterWeapons(role)
    if not g_isPlayerPedReady and role and role ~= "citizen" then
        Citizen.CreateThread(function()
            Citizen.Wait(1500)
            g_isPlayerPedReady = true
            end)
    elseif role == "citizen" and g_isPlayerPedReady then
        g_isPlayerPedReady = false
        print("[CNR_CLIENT] Player Ped is NO LONGER READY (g_isPlayerPedReady = false) due to role change to citizen.")
    end
end)

RegisterNetEvent('cnr:roleSelected')
AddEventHandler('cnr:roleSelected', function(success, message)
    if success then
        isRoleSelectionVisible = false
        SendNUIMessage({ action = 'hideRoleSelection' })
        SetMenuFocus(false, false)
    else
        isRoleSelectionVisible = true
        SendNUIMessage({
            action = 'roleSelectionFailed',
            error = message or 'Role selection failed.'
        })
        SetMenuFocus(true, true)
    end

    if message and message ~= "" then
        ShowNotification(success and ("~g~" .. message) or ("~r~" .. message))
    end
end)

AddEventHandler('cnr:lookupRobberInfoResult', function(requestId, result)
    local callback = pendingPoliceLookupCallbacks[requestId]
    if callback then
        pendingPoliceLookupCallbacks[requestId] = nil
        callback(result or {
            success = false,
            error = "Lookup failed."
        })
    end
end)

AddEventHandler('cnr:receivePoliceCadData', function(requestId, cadData, citationReasons)
    local enhancedCadData = EnhancePoliceCadPayload(cadData or {})
    SyncPoliceDispatchBlips(enhancedCadData.calls or {})
    local callback = requestId and pendingPoliceCadCallbacks[requestId] or nil

    if callback then
        pendingPoliceCadCallbacks[requestId] = nil
        callback({
            success = true,
            cadData = enhancedCadData,
            citationReasons = citationReasons or {}
        })
        return
    end

    SendNUIMessage({
        action = 'updatePoliceCadData',
        cadData = enhancedCadData,
        citationReasons = citationReasons or {}
    })
end)

AddEventHandler('cnr:receiveAdminLiveMapData', function(requestId, liveMapData)
    local callback = requestId and pendingAdminLiveMapCallbacks[requestId] or nil
    local payload = liveMapData or {
        players = {},
        generatedAt = os.time()
    }

    if callback then
        pendingAdminLiveMapCallbacks[requestId] = nil
        callback({
            success = true,
            liveMapData = payload
        })
        return
    end

    SendNUIMessage({
        action = 'updateAdminLiveMapData',
        liveMapData = payload
    })
end)

AddEventHandler('cnr:receiveRoleTextMessage', function(messageData)
    local senderName = messageData and messageData.fromName or "Unknown"
    local senderRole = messageData and messageData.fromRole or "player"
    local message = messageData and messageData.message or ""
    if message == "" then
        return
    end

    TriggerEvent('chat:addMessage', {
        args = { string.format("^5Text [%s]", senderRole), string.format("%s: %s", senderName, message) }
    })
    ShowNotification(string.format("~b~Text from %s~s~: %s", senderName, message))
end)

Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local isDead = playerPed ~= 0 and IsEntityDead(playerPed)

        if isDead and not roleSelectionShownForCurrentDeath then
            roleSelectionShownForCurrentDeath = true
            if not deathReportedForCurrentLife then
                deathReportedForCurrentLife = true

                local killerServerId = 0
                local killerEntity = GetPedSourceOfDeath(playerPed)
                if killerEntity and killerEntity ~= 0 and DoesEntityExist(killerEntity) then
                    if IsEntityAVehicle(killerEntity) then
                        killerEntity = GetPedInVehicleSeat(killerEntity, -1)
                    end

                    if killerEntity and killerEntity ~= 0 and DoesEntityExist(killerEntity) and IsPedAPlayer(killerEntity) then
                        local killerPlayer = NetworkGetPlayerIndexFromPed(killerEntity)
                        if killerPlayer and killerPlayer ~= -1 then
                            killerServerId = GetPlayerServerId(killerPlayer) or 0
                        end
                    end
                end

                TriggerServerEvent('cnr:playerDeathState', killerServerId)
            end

            TriggerEvent('cnr:closeInventory')
            CloseBankingInterface()
            TriggerServerEvent('cnr:requestRoleSelection')
        elseif not isDead and roleSelectionShownForCurrentDeath then
            roleSelectionShownForCurrentDeath = false
            deathReportedForCurrentLife = false
        end

        Citizen.Wait(isDead and 750 or 250)
    end
end)

Citizen.CreateThread(function()
    while true do
        if isRoleSelectionVisible or isInCharacterEditor then
            Citizen.Wait(0)

            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 68, true)
            DisableControlAction(0, 69, true)
            DisableControlAction(0, 70, true)
            DisableControlAction(0, 91, true)
            DisableControlAction(0, 92, true)
            DisableControlAction(0, 106, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 264, true)
        else
            Citizen.Wait(250)
        end
    end
end)

AddEventHandler('cnr:setPlayerRole', function(newRole)
    role = newRole or nil

    if playerData then
        playerData.role = role
    end

    activeRoleActionMenu = nil
    SendNUIMessage({
        action = 'hideRoleActionMenus'
    })
    SetMenuFocus(false, false)

    if role ~= "cop" then
        SyncPoliceDispatchBlips({})
    end

    UpdateActivityBlips()
end)

AddEventHandler('cnr:showWantedNotification', function(stars, points, level)
    stars = tonumber(stars) or 0
    points = tonumber(points) or 0
    currentWantedStarsClient = stars
    currentWantedPointsClient = points

    SendNUIMessage({
        action = 'showWantedNotification',
        stars = stars,
        points = points,
        level = level
    })
end)

AddEventHandler('cnr:hideWantedNotification', function()
    currentWantedStarsClient = 0
    currentWantedPointsClient = 0
    SendNUIMessage({
        action = 'hideWantedNotification'
    })
end)

RegisterNetEvent('cops_and_robbers:updateWantedDisplay')
AddEventHandler('cops_and_robbers:updateWantedDisplay', function(stars, points)
    currentWantedStarsClient = stars
    currentWantedPointsClient = points
    local newUiLabel = ""
    if stars > 0 then
        for _, levelData in ipairs(Config.WantedSettings.levels) do
            if levelData.stars == stars then
                newUiLabel = levelData.uiLabel
                break
            end
        end
        if newUiLabel == "" then newUiLabel = "Wanted: " .. string.rep("*", stars) end
    end
    wantedUiLabel = newUiLabel
    SetWantedLevelForPlayerRole(stars, points)
end)

-- Handle wanted level synchronization from server
AddEventHandler('cnr:wantedLevelSync', function(wantedData)
    if not wantedData then return end
    
    -- Update client-side wanted level data
    currentWantedStarsClient = wantedData.stars or 0
    currentWantedPointsClient = wantedData.wantedLevel or 0
    
    -- Update UI label
    local newUiLabel = ""
    if currentWantedStarsClient > 0 then
        for _, levelData in ipairs(Config.WantedSettings.levels or {}) do
            if levelData.stars == currentWantedStarsClient then
                newUiLabel = levelData.uiLabel
                break
            end
        end
        if newUiLabel == "" then 
            newUiLabel = "Wanted: " .. string.rep("*", currentWantedStarsClient) 
        end
    end
    wantedUiLabel = newUiLabel
    
    -- Update the wanted level display
    SetWantedLevelForPlayerRole(currentWantedStarsClient, currentWantedPointsClient)
    
end)

-- =====================================
--           HEIST ALERT SYSTEM
-- =====================================

-- Handler for receiving heist alerts (for cops)
AddEventHandler('cnr:heistAlert', function(heistType, coords)
    if role ~= 'cop' then return end

    -- Default location if no coords provided
    if not coords then
        coords = {x = 0, y = 0}
    end
    
    local heistName = ""
    if heistType == "bank" then
        heistName = "Bank Heist"
    elseif heistType == "jewelry" then
        heistName = "Jewelry Store Robbery"
    elseif heistType == "store" then
        heistName = "Store Robbery"
    else
        heistName = "Unknown Heist"
    end
    
    -- Show notification to cop
    local message = string.format("~r~ALERT:~w~ %s in progress! Check your map for location.", heistName)
    ShowNotification(message)
    
    -- Create a temporary blip at the heist location
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161) -- Red circle
    SetBlipColour(blip, 1)   -- Red color
    SetBlipScale(blip, 1.5)  -- Larger size
    SetBlipAsShortRange(blip, false)
    
    -- Add blip name/label
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(heistName)
    EndTextCommandSetBlipName(blip)
    
    -- Flash blip for attention
    SetBlipFlashes(blip, true)
    
    -- Remove blip after 2 minutes
    Citizen.SetTimeout(120000, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)

-- Handler for heist timer display
AddEventHandler('cnr:startHeistTimer', function(duration, heistName)
    -- Show heist timer UI for robber
    SendNUIMessage({
        action = 'startHeistTimer',
        duration = duration,
        bankName = heistName
    })
end)

-- Handler for heist completion
AddEventHandler('cnr:heistCompleted', function(heistResult, xpEarned)
    local resultData = heistResult
    if type(heistResult) ~= "table" then
        resultData = {
            success = true,
            reward = heistResult or 0,
            xp = xpEarned or 0
        }
    end

    SendNUIMessage({
        action = "heistCompleted",
        success = resultData.success,
        reward = resultData.reward or 0,
        xp = resultData.xp or 0,
        heistName = resultData.heistName,
        reason = resultData.reason,
        duration = resultData.duration
    })

    local message
    if resultData.success then
        message = string.format("~g~Heist completed!~w~ You earned ~g~$%s~w~ and ~b~%d XP~w~.", resultData.reward or 0, resultData.xp or 0)
        PlaySoundFrontend(-1, "MISSION_PASS_NOTIFY", "HUD_AWARDS", true)
        if playerStats then
            playerStats.heists = (playerStats.heists or 0) + 1
        end
    else
        message = string.format("~r~Heist failed!~w~ %s", resultData.reason or "Unknown reason")
        PlaySoundFrontend(-1, "Mission_Failed", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
    end

    ShowNotification(message)
end)

-- =====================================
--           NUI CALLBACKS
-- =====================================

-- NUI Callback for Role Selection
RegisterNUICallback('selectRole', function(data, cb)
    if not data or not data.role then
        cb({ success = false, error = "Invalid role data received" })
        return
    end
    
    local selectedRole = data.role
    if selectedRole ~= "cop" and selectedRole ~= "robber" and selectedRole ~= "civilian" then
        cb({ success = false, error = "Invalid role selected" })
        return
    end
    
    -- Send role selection to server
    TriggerServerEvent('cnr:selectRole', selectedRole)
    
    -- Close the UI immediately so the player is not left stuck in the menu while
    -- the server finishes role sync. Failure events will reopen it if needed.
    isRoleSelectionVisible = false
    SendNUIMessage({ action = 'hideRoleSelection' })
    SetMenuFocus(false, false)
    
    -- Return success to NUI
    cb({ success = true })
end)

-- Register NUI callback for setting NUI focus
-- Register NUI callbacks for robber menu actions
RegisterNUICallback('startHeist', function(data, cb)
    TriggerEvent('cnr:startHeist')
    cb({success = true})
end)

RegisterNUICallback('viewBounties', function(data, cb)
    TriggerEvent('cnr:viewBounties')
    cb({success = true})
end)

-- NUI Callback for UI test results
RegisterNUICallback('uiTestResults', function(data, cb)
    TriggerServerEvent('cnr:uiTestResults', data)
    cb('ok')
end)

RegisterNUICallback('buyContraband', function(data, cb)
    
    -- Check if player is near a contraband dealer
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearDealer = false
    
    for _, dealer in pairs(Config.ContrabandDealers or {}) do
        local dealerPos = GetEntryCoords(dealer)
        local distance = dealerPos and #(playerPos - dealerPos) or math.huge
        
        if distance < 5.0 then
            nearDealer = true
            break
        end
    end
    
    if nearDealer then
        -- Open the store with contraband items
        TriggerServerEvent('cnr:accessContrabandDealer')
    else
        ShowNotification("~r~You must be near a contraband dealer to buy contraband.")
    end
    
    cb({success = true})
end)

-- Register NUI callback for buying items
RegisterNUICallback('buyItem', function(data, cb)
    Log("buyItem NUI callback received for itemId: " .. tostring(data.itemId) .. " quantity: " .. tostring(data.quantity), "info", "CNR_CLIENT")
    
    if not data.itemId or not data.quantity then
        Log("buyItem NUI callback missing required data", "error", "CNR_CLIENT")
        cb({success = false, message = "Missing required data"})
        return
    end
    
    -- Trigger server event to buy the item
    TriggerServerEvent('cops_and_robbers:buyItem', data.itemId, data.quantity)
    
    -- Acknowledge receipt only; the server sends the final transaction result.
    cb({success = true, pending = true})
end)

-- Register NUI callback for selling items
RegisterNUICallback('sellItem', function(data, cb)
    Log("sellItem NUI callback received for itemId: " .. tostring(data.itemId) .. " quantity: " .. tostring(data.quantity), "info", "CNR_CLIENT")
    
    if not data.itemId or not data.quantity then
        Log("sellItem NUI callback missing required data", "error", "CNR_CLIENT")
        cb({success = false, message = "Missing required data"})
        return
    end
    
    -- Trigger server event to sell the item
    TriggerServerEvent('cops_and_robbers:sellItem', data.itemId, data.quantity)
    
    -- Acknowledge receipt only; the server sends the final transaction result.
    cb({success = true, pending = true})
end)

-- Register NUI callback for getting player inventory
-- =====================================
--           EVENT HANDLERS
-- =====================================

-- Event handler for showing role selection UI
RegisterNetEvent('cnr:showRoleSelection')
AddEventHandler('cnr:showRoleSelection', function()
    activeRoleActionMenu = nil
    isRoleSelectionVisible = true
    SendNUIMessage({
        action = 'hideRoleActionMenus'
    })
    SendNUIMessage({ 
        action = 'showRoleSelection', 
        resourceName = GetCurrentResourceName() 
    })
    SetMenuFocus(true, true)
    Citizen.SetTimeout(100, function()
        if isRoleSelectionVisible and not isInCharacterEditor then
            SetMenuFocus(true, true)
        end
    end)
end)

-- =====================================
--           ROBBER MENU ACTIONS
-- =====================================

RegisterNetEvent('cnr:startHeist')
AddEventHandler('cnr:startHeist', function()
    -- Check if player is near a heist location
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearHeist = false
    local heistType = nil
    
    -- Example: Check if player is near a bank
    for _, location in pairs(Config.HeistLocations or {}) do
        local heistCoords = location.location or vector3(location.x, location.y, location.z)
        local distance = #(playerPos - heistCoords)
        if distance < 20.0 then
            nearHeist = true
            heistType = location.type
            break
        end
    end
    
    if nearHeist then
        TriggerServerEvent('cnr:startHeistPlanning', heistType)
    else
        ShowNotification("~r~You must be near a valid heist location to start a heist.")
    end
end)

RegisterNetEvent('cnr:viewBounties')
AddEventHandler('cnr:viewBounties', function()
    TriggerServerEvent('cnr:requestBountyList')
end)

-- Add new event handler for receiving bounty list
RegisterNetEvent('cnr:receiveBountyList')
AddEventHandler('cnr:receiveBountyList', function(bountyList)
    
    -- Send the bounty list to the UI
    SendNUIMessage({
        action = 'showBountyList',
        bounties = bountyList
    })
    
    -- Set focus to the UI
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cnr:findHideout')
AddEventHandler('cnr:findHideout', function()
    
    -- Example: Show the nearest hideout on the map
    local nearestHideout = nil
    local shortestDistance = 1000000
    local playerPos = GetEntityCoords(PlayerPedId())
    
    for _, hideout in pairs(Config.RobberHideouts or {}) do
        local hideoutPos = GetEntryCoords(hideout)
        local distance = hideoutPos and #(playerPos - hideoutPos) or math.huge
        
        if distance < shortestDistance then
            shortestDistance = distance
            nearestHideout = hideout
        end
    end
    
    if nearestHideout then
        -- Create a temporary blip for the hideout
        local hideoutCoords = GetEntryCoords(nearestHideout)
        local blip = AddBlipForCoord(hideoutCoords.x, hideoutCoords.y, hideoutCoords.z)
        SetBlipSprite(blip, nearestHideout.blipSprite or 40) -- House icon
        SetBlipColour(blip, nearestHideout.blipColor or 1) -- Red
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Robber Hideout")
        EndTextCommandSetBlipName(blip)
        
        -- Show notification
        ShowNotification("~g~Hideout location marked on your map.")
        
        -- Remove blip after 60 seconds
        Citizen.SetTimeout(60000, function()
            RemoveBlip(blip)
            ShowNotification("~y~Hideout location removed from map.")
        end)
    else
        ShowNotification("~r~No hideout locations found.")
    end
end)

RegisterNetEvent('cnr:buyContraband')
AddEventHandler('cnr:buyContraband', function()
    
    -- Check if player is near a contraband dealer
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearDealer = false
    
    for _, dealer in pairs(Config.ContrabandDealers or {}) do
        local dealerPos = GetEntryCoords(dealer)
        local distance = dealerPos and #(playerPos - dealerPos) or math.huge
        
        if distance < 5.0 then
            nearDealer = true
            break
        end
    end
    
    if nearDealer then
        -- Open the store with contraband items
        TriggerServerEvent('cnr:accessContrabandDealer')
    else
        ShowNotification("~r~You must be near a contraband dealer to buy contraband.")
    end
end)

-- Function to check for nearby stores and display help text
function CheckNearbyStores()
    if IsAnyStoreUiOpen() then
        ClearStoreHelpText()
        return
    end

    local playerPed = PlayerPedId()
    if not playerPed or not DoesEntityExist(playerPed) then return end
    
    local playerPos = GetEntityCoords(playerPed)
    local isNearStore = false
    
    if Config and Config.NPCVendors then
        for _, vendor in ipairs(Config.NPCVendors) do
            if vendor and vendor.location then
                -- Handle both vector3 and vector4 formats
                local storePos
                if vendor.location.w then
                    storePos = vector3(vendor.location.x, vendor.location.y, vendor.location.z)
                else
                    storePos = vendor.location
                end
                
                local distance = #(playerPos - storePos)
                -- Check if player is within proximity radius (3.0 units)
                if distance <= 3.0 then
                    isNearStore = true
                    
                    -- Proper store type classification and role-based access validation
                    local hasAccess = false
                    local vendorStoreType = "civilian" -- default
                    
                    if vendor.name == "Cop Store" then
                        vendorStoreType = "cop"
                        hasAccess = (role == "cop")
                    elseif vendor.name == "Gang Supplier" or vendor.name == "Black Market Dealer" then
                        vendorStoreType = "robber"
                        hasAccess = (role == "robber")
                    else
                        -- General stores accessible to all roles
                        vendorStoreType = "civilian"
                        hasAccess = true
                    end

                    -- Display appropriate help text
                    local helpText
                    if hasAccess then
                        helpText = "Press ~INPUT_CONTEXT~ to open " .. vendor.name
                    else
                        helpText = "~r~Access Restricted: " .. vendor.name .. " (Role: " .. (vendorStoreType == "cop" and "Police Only" or "Robbers Only") .. ")"
                    end

                    ShowPersistentStoreHelpText(helpText)
                    
                    -- Check for E key press (INPUT_CONTEXT = 38)
                    local now = GetGameTimer()
                    if IsControlPressed(0, 38) and (now - lastStoreInteractionTime) > STORE_INTERACTION_COOLDOWN_MS then
                        lastStoreInteractionTime = now
                        if hasAccess then
                            OpenStoreMenu(vendorStoreType, vendor.items, vendor.name)
                        else
                            ShowNotification("~r~You don't have access to this store. This is restricted to " .. (vendorStoreType == "cop" and "police officers" or "robbers") .. " only.")
                        end
                    end
                    break
                end
            end
        end
    end

    if not isNearStore then
        ClearStoreHelpText()
    end
end

-- Function to open the store menu
function OpenStoreMenu(storeType, storeItems, storeName)
    if not storeType or not storeItems or not storeName then
        Log("OpenStoreMenu called with invalid parameters", "error", "CNR_CLIENT")
        return
    end

    if IsAnyStoreUiOpen() then
        return
    end

    ClearStoreHelpText()
    
    -- Set the appropriate UI flag
    if storeType == "cop" then
        isCopStoreUiOpen = true
    elseif storeType == "robber" then
        isRobberStoreUiOpen = true
    end
      -- Ensure fullItemConfig is available to NUI before opening store
    TriggerEvent('cnr:ensureConfigItems')
    
    -- Send message to NUI to open store with current player data
    SendNUIMessage({
        action = "openStore",
        storeType = storeType,
        items = storeItems,
        storeName = storeName,
        playerInfo = {
            level = playerData.level or 1,
            role = playerData.role or role or "citizen",
            cash = playerData.money or playerCash or 0,
            playerCash = playerData.money or playerCash or 0,
            playerLevel = playerData.level or 1
        },
        playerCash = playerData.money or playerCash or 0,  -- Use server data first, then client fallback
        playerLevel = playerData.level or 1,
        cash = playerData.money or playerCash or 0,  -- Add for backward compatibility
        level = playerData.level or 1  -- Add for backward compatibility
    })
    
    -- Enable NUI focus
    SetNuiFocus(true, true)
    
    -- Trigger server event to get detailed item information
    TriggerServerEvent('cops_and_robbers:getItemList', storeType, storeItems, storeName)
end

-- Register NUI callback for closing the store
RegisterNUICallback('closeStore', function(data, cb)
    Log("closeStore NUI callback received", "info", "CNR_CLIENT")
    
    -- Reset UI flags
    isCopStoreUiOpen = false
    isRobberStoreUiOpen = false
    
    -- Disable NUI focus
    SetNuiFocus(false, false)
    ClearStoreHelpText()
    
    cb({success = true})
end)

-- Handle detailed item list from server for store UI
RegisterNetEvent('cops_and_robbers:sendItemList')
AddEventHandler('cops_and_robbers:sendItemList', function(storeName, itemList, playerInfo)
    Log("Received detailed item list for store: " .. tostring(storeName) .. " with " .. (#itemList or 0) .. " items", "info", "CNR_CLIENT")
    
    if not itemList or #itemList == 0 then
        Log("Received empty item list for store: " .. tostring(storeName), "warning", "CNR_CLIENT")
        return
    end
    
    -- Update local player data if server provides it
    if playerInfo then
        if playerInfo.cash and playerInfo.cash ~= playerCash then
            playerCash = playerInfo.cash
            Log("Updated playerCash from server: " .. tostring(playerCash), "info", "CNR_CLIENT")
        end
        if playerInfo.level and playerData.level ~= playerInfo.level then
            playerData.level = playerInfo.level
            Log("Updated playerData.level from server: " .. tostring(playerData.level), "info", "CNR_CLIENT")
        end
    end
    
    -- Send the complete item data to NUI
    SendNUIMessage({
        action = "updateStoreData",
        storeName = storeName,
        items = itemList,
        playerInfo = playerInfo or {
            level = playerData.level or 1,
            role = playerData.role or "citizen",
            cash = playerCash or 0
        }
    })
    
    Log("Sent store data to NUI for " .. tostring(storeName), "info", "CNR_CLIENT")
end)

-- Handle contraband store UI opening
RegisterNetEvent('cnr:openContrabandStoreUI')
AddEventHandler('cnr:openContrabandStoreUI', function(contrabandItems)
    Log("Opening contraband store UI with " .. #contrabandItems .. " items", "info", "CNR_CLIENT")
    
    -- Open store menu as a special contraband store
    OpenStoreMenu("contraband", contrabandItems, "Contraband Dealer")
    
    -- Trigger server event to get detailed item information
    TriggerServerEvent('cops_and_robbers:getItemList', "contraband", contrabandItems, "Contraband Dealer")
end)

-- Register event to send NUI messages from server
RegisterNetEvent('cnr:sendNUIMessage')
AddEventHandler('cnr:sendNUIMessage', function(message)
    -- Validate message before sending to NUI
    if not message or type(message) ~= 'table' then
        print('[CNR_CLIENT_ERROR] Invalid NUI message received from server:', message)
        return
    end
    
    if not message.action or type(message.action) ~= 'string' then
        print('[CNR_CLIENT_ERROR] NUI message missing action field:', json.encode(message))
        return
    end
    
    SendNUIMessage(message)
end)

-- Thread to check for nearby stores
if PerformanceOptimizer then
    PerformanceOptimizer.CreateOptimizedLoop(function()
        if g_isPlayerPedReady then
            CheckNearbyStores()
        end
    end, 200, 500, 2)
else
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(200)
            
            if g_isPlayerPedReady then
                CheckNearbyStores()
            end
        end
    end)
end

-- OLD CLIENT-SIDE CRIME DETECTION DISABLED
-- This has been replaced by server-side crime detection systems
-- The new system handles:
-- - Weapon discharge detection (cnr:weaponFired event)
-- - Player damage detection (cnr:playerDamaged event)  
-- - Speeding detection (server-side vehicle monitoring)
-- - Restricted area detection (server-side position monitoring)
-- - Hit-and-run detection (server-side vehicle damage monitoring)

--[[
-- Thread to detect when player commits a crime (like killing NPCs or other players)
-- DISABLED - Replaced by server-side detection to prevent conflicts
Citizen.CreateThread(function()
    local lastMurderCheckTime = 0
    local nearbyPedsTracked = {}
    
    while true do
        Citizen.Wait(1000) -- Check once per second
        
        -- Only check if player is ready and is a robber
        if g_isPlayerPedReady and role == "robber" then
            local playerPed = PlayerPedId()
            local currentTime = GetGameTimer()
            
            -- Check if player killed an NPC (check nearby peds for recent deaths)
            if (currentTime - lastMurderCheckTime) > 2000 then -- Check every 2 seconds to avoid spam
                local playerCoords = GetEntityCoords(playerPed)
                local nearbyPeds = GetGamePool('CPed')
                
                for i = 1, #nearbyPeds do
                    local ped = nearbyPeds[i]
                    if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        local distance = #(playerCoords - pedCoords)
                        
                        -- Check if ped is close and recently died
                        if distance < 15.0 and IsEntityDead(ped) then
                            -- Check if this ped wasn't tracked as dead before
                            if not nearbyPedsTracked[ped] then
                                local killer = GetPedSourceOfDeath(ped)
                                -- If player was the killer
                                if killer == playerPed then
                                    TriggerServerEvent('cops_and_robbers:reportCrime', 'murder')
                                    nearbyPedsTracked[ped] = true
                                end
                            end
                        elseif distance > 50.0 then
                            -- Remove tracking for peds that are far away to prevent memory issues
                            nearbyPedsTracked[ped] = nil
                        end
                    end
                end
                lastMurderCheckTime = currentTime
            end
            
            -- Check for kill (player vs player)
            if IsEntityDead(playerPed) then
                -- Player died, check who killed them
                local killer = GetPedSourceOfDeath(playerPed)
                if killer ~= playerPed and DoesEntityExist(killer) and IsEntityAPed(killer) then
                    local killerType = GetEntityType(killer)
                    if killerType == 1 then -- Ped type
                        if IsPedAPlayer(killer) then
                            -- Player killed by another player
                            local killerServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(killer))
                            if killerServerId ~= GetPlayerServerId(PlayerId()) then
                                -- Report murder crime
                                TriggerServerEvent('cops_and_robbers:reportCrime', 'murder')
                            end
                        end
                    end
                end
            end
            
            -- Check for hit and run
            if IsPedInAnyVehicle(playerPed, false) then
                local vehicle = GetVehiclePedIsIn(playerPed, false)
                  -- Check if we hit a pedestrian
                if HasEntityCollidedWithAnything(vehicle) then
                    -- Since GetEntityHit isn't available, check if any nearby peds are injured
                    local playerCoords = GetEntityCoords(playerPed)
                    local nearbyPeds = GetGamePool('CPed')
                    
                    for i=1, #nearbyPeds do
                        local ped = nearbyPeds[i]
                        if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            local distance = #(playerCoords - pedCoords)
                            
                            -- If ped is close and injured, consider it a hit and run
                            if distance < 10.0 and (IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedInjured(ped)) then
                                TriggerServerEvent('cops_and_robbers:reportCrime', 'hit_and_run')
                                break
                            end
                        end
                    end
                end
            end
            
            -- Check for property damage
            if HasPlayerDamagedAtLeastOneNonAnimalPed(PlayerId()) then
                TriggerServerEvent('cops_and_robbers:reportCrime', 'assault')
                -- Reset the flag
                ClearPlayerHasDamagedAtLeastOneNonAnimalPed(PlayerId())
            end
            
            -- Check for vehicle theft
            if IsPedInAnyVehicle(playerPed, false) then
                local vehicle = GetVehiclePedIsIn(playerPed, false)                if GetPedInVehicleSeat(vehicle, -1) == playerPed then -- If player is driver
                    -- Check if vehicle is potentially stolen by checking common police/emergency vehicles
                    local model = GetEntityModel(vehicle)
                    local isEmergencyVehicle = IsVehicleModel(vehicle, GetHashKey("police")) or 
                                               IsVehicleModel(vehicle, GetHashKey("police2")) or 
                                               IsVehicleModel(vehicle, GetHashKey("police3")) or
                                               IsVehicleModel(vehicle, GetHashKey("ambulance")) or
                                               IsVehicleModel(vehicle, GetHashKey("firetruk"))
                    
                    -- Consider it stolen if it's an emergency vehicle or marked as stolen
                    if isEmergencyVehicle or IsVehicleStolen(vehicle) or (DecorExistOn(vehicle, 'isStolen') and DecorGetBool(vehicle, 'isStolen')) then
                        -- Report vehicle theft
                        TriggerServerEvent('cops_and_robbers:reportCrime', 'grand_theft_auto')
                        -- Mark the vehicle as stolen to prevent repeated reports
                        if not DecorExistOn(vehicle, 'isStolen') then
                            DecorSetBool(vehicle, 'isStolen', true)
                        end
                    end
                end
            end
        end
    end
end)

-- OLD WEAPON DISCHARGE DETECTION DISABLED
-- This has been replaced by the new server-side weapon discharge detection
-- The new system uses cnr:weaponFired event for better accuracy and server authority

-- Add detection for weapon discharge
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(50)
        
        if g_isPlayerPedReady and role == "robber" then
            local playerPed = PlayerPedId()
            
            -- Check for weapon discharge
            if IsPedShooting(playerPed) then
                local weapon = GetSelectedPedWeapon(playerPed)
                
                -- Only report for actual weapons, not non-lethal ones
                if weapon ~= GetHashKey('WEAPON_STUNGUN') and weapon ~= GetHashKey('WEAPON_FLASHLIGHT') then
                    -- Report weapon discharge                    TriggerServerEvent('cops_and_robbers:reportCrime', 'weapons_discharge')
                    -- Wait a bit to avoid spamming events
                    Citizen.Wait(5000)
                end
            end
        end
    end
end)
--]]

-- ====================================================================
-- Speedometer Functions
-- ====================================================================

-- Speedometer settings
local showSpeedometer = true
local speedometerUpdateInterval = 200 -- ms
local lastVehicleSpeed = 0

-- Cache for vehicle types we don't want to show speedometer for
local excludedVehicleTypes = {
    [8] = true,  -- Boats
    [14] = true, -- Boats
    [15] = true, -- Helicopters
    [16] = true, -- Planes
}

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(speedometerUpdateInterval)
        
        if showSpeedometer then
            local player = PlayerPedId()
            
            if IsPedInAnyVehicle(player, false) then
                local vehicle = GetVehiclePedIsIn(player, false)
               
                local vehicleClass = GetVehicleClass(vehicle)
                
                -- Only show speedometer for allowed vehicle types
                if not excludedVehicleTypes[vehicleClass] then
                    local speed = GetEntitySpeed(vehicle) * 2.236936 -- Convert to MPH
                    
                    -- Only update the UI if the speed has changed significantly
                    if math.abs(speed - lastVehicleSpeed) > 0.5 then
                        lastVehicleSpeed = speed
                        
                        -- Round to integer
                        local roundedSpeed = math.floor(speed + 0.5)
                        
                        -- Update UI
                        SendNUIMessage({
                            action = "updateSpeedometer",
                            speed = roundedSpeed
                        })
                        
                        -- Show speedometer if not already visible
                        SendNUIMessage({
                            action = "toggleSpeedometer",
                            show = true
                        })
                    end
                else
                    -- Hide speedometer for excluded vehicle types
                    SendNUIMessage({
                        action = "toggleSpeedometer",
                        show = false
                    })
                end
            else
                -- Hide speedometer when not in vehicle
                SendNUIMessage({
                    action = "toggleSpeedometer",
                    show = false
                })
            end
        end
    end
end)

-- Command to toggle speedometer
RegisterCommand('togglespeedometer', function()
    showSpeedometer = not showSpeedometer
    TriggerEvent('cnr:notification', 'Speedometer ' .. (showSpeedometer and 'enabled' or 'disabled'))
end, false)

-- ====================================================================
-- Robber Hideouts
-- ====================================================================

local hideoutBlips = {}
local isHideoutVisible = false
local pendingPlayerRoleCallbacks = {}

-- Function to get player's current role from server
function GetCurrentPlayerRole(callback)
    if type(callback) == "function" then
        table.insert(pendingPlayerRoleCallbacks, callback)
    end

    TriggerServerEvent('cnr:getPlayerRole')
end

AddEventHandler('cnr:returnPlayerRole', function(role)
    local callbacks = pendingPlayerRoleCallbacks
    pendingPlayerRoleCallbacks = {}

    for _, callback in ipairs(callbacks) do
        callback(role)
    end
end)

-- Create a blip for the nearest robber hideout
function FindNearestHideout()
    -- Check if player is a robber
    GetCurrentPlayerRole(function(role)
        if role ~= "robber" then
            TriggerEvent('cnr:notification', "Only robbers can access hideouts.", "error")
            return
        end
        
        -- Clean up any existing hideout blips
        RemoveHideoutBlips()
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearestHideout = nil
        local nearestDistance = 9999.0
        
        -- Find the nearest hideout
        for _, hideout in ipairs(Config.RobberHideouts) do
            local hideoutCoords = GetEntryCoords(hideout)
            if hideoutCoords then
                local distance = #(playerCoords - hideoutCoords)
                
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestHideout = hideout
                end
            end
        end
        
        if nearestHideout then
            local hideoutCoords = GetEntryCoords(nearestHideout)
            
            -- Create blip for the hideout
            local blip = AddBlipForCoord(hideoutCoords.x, hideoutCoords.y, hideoutCoords.z)
            SetBlipSprite(blip, 492) -- House icon
            SetBlipColour(blip, nearestHideout.blipColor or 1) -- Red
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(nearestHideout.name)
            EndTextCommandSetBlipName(blip)
            
            -- Set route to the hideout
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, 1) -- Red route
            
            -- Add to hideout blips table
            table.insert(hideoutBlips, blip)
            
            -- Notify player
            TriggerEvent('cnr:notification', "Route set to " .. nearestHideout.name .. ".")
            
            -- Set timer to remove the blip after 2 minutes
            Citizen.SetTimeout(120000, function()
                RemoveHideoutBlips()
                TriggerEvent('cnr:notification', "Hideout marker removed from map.")
            end)
            
            isHideoutVisible = true
        else
            TriggerEvent('cnr:notification', "No hideouts found nearby.", "error")
        end
    end)
end

-- Remove all hideout blips
function RemoveHideoutBlips()
    for _, blip in ipairs(hideoutBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    hideoutBlips = {}
    isHideoutVisible = false
end

local function GetRobberSafehouseState(playerCoords)
    local fallbackRadius = tonumber(Config.WantedSettings and Config.WantedSettings.safehouseRadius) or 65.0
    local nearestHideout = nil
    local nearestCoords = nil
    local nearestRadius = fallbackRadius
    local nearestDistance = math.huge
    local activeHideout = nil

    for _, hideout in ipairs(Config.RobberHideouts or {}) do
        local hideoutCoords = GetEntryCoords(hideout)
        if hideoutCoords then
            local hideoutRadius = tonumber(hideout.radius) or fallbackRadius
            local distance = #(playerCoords - hideoutCoords)

            if distance < nearestDistance then
                nearestHideout = hideout
                nearestCoords = hideoutCoords
                nearestRadius = hideoutRadius
                nearestDistance = distance
            end

            if distance <= hideoutRadius then
                activeHideout = {
                    name = hideout.name or "Robber Safehouse",
                    coords = hideoutCoords,
                    radius = hideoutRadius,
                    distance = distance
                }
            end
        end
    end

    return activeHideout, nearestHideout, nearestCoords, nearestRadius, nearestDistance
end

Citizen.CreateThread(function()
    while true do
        local sleepMs = 1500

        if g_isPlayerPedReady and role == "robber" then
            local playerPed = PlayerPedId()
            if playerPed and playerPed ~= 0 and DoesEntityExist(playerPed) then
                local playerCoords = GetEntityCoords(playerPed)
                local activeHideout, nearestHideout, nearestCoords, nearestRadius, nearestDistance = GetRobberSafehouseState(playerCoords)

                if nearestHideout and nearestCoords and nearestDistance <= math.max((nearestRadius or 65.0) + 120.0, 180.0) then
                    sleepMs = 0
                    DrawMarker(1, nearestCoords.x, nearestCoords.y, nearestCoords.z - 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (nearestRadius or 65.0) * 2.0, (nearestRadius or 65.0) * 2.0, 1.6, 220, 60, 60, 72, false, false, 2, false, nil, nil, false)
                    DrawMarker(1, nearestCoords.x, nearestCoords.y, nearestCoords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.2, 3.2, 1.1, 255, 255, 255, 120, false, false, 2, false, nil, nil, false)
                end

                if activeHideout and (not isCurrentlyInSafeZone or currentSafeZoneName ~= activeHideout.name) then
                    isCurrentlyInSafeZone = true
                    currentSafeZoneName = activeHideout.name
                    ShowNotification(string.format("~g~Safehouse bonus active at %s. Wanted level decays faster here.", currentSafeZoneName))
                elseif not activeHideout and isCurrentlyInSafeZone then
                    ShowNotification(string.format("~y~You left %s. Wanted decay is back to normal.", currentSafeZoneName ~= "" and currentSafeZoneName or "the safehouse"))
                    isCurrentlyInSafeZone = false
                    currentSafeZoneName = ""
                end
            end
        elseif isCurrentlyInSafeZone then
            isCurrentlyInSafeZone = false
            currentSafeZoneName = ""
        end

        Citizen.Wait(sleepMs)
    end
end)

-- ====================================================================
-- Client-Side Jail System Logic
-- ====================================================================

-- Track if the jail update thread is running
local jailThreadRunning = false

local function StopJailUpdateThread()
    -- Thread checks the isJailed flag, so simply hide the timer display
    jailTimerDisplayActive = false
    jailThreadRunning = false
    Log("Jail update thread signaled to stop.", "info", "CNR_CLIENT")
end

local function StartJailUpdateThread(duration)
    jailTimeRemaining = duration
    jailTimerDisplayActive = true

    -- Avoid spawning multiple threads
    if jailThreadRunning then
        Log("Jail update thread already running. Timer updated to " .. jailTimeRemaining, "info", "CNR_CLIENT")
        return
    end

    jailThreadRunning = true
    Citizen.CreateThread(function()
        Log("Jail update thread started. Duration: " .. jailTimeRemaining, "info", "CNR_CLIENT")
        local playerPed = PlayerPedId()

        while isJailed and jailTimeRemaining > 0 do
            Citizen.Wait(1000) -- Update every second

            if not isJailed then -- Double check in case of async state change
                break
            end

            jailTimeRemaining = jailTimeRemaining - 1

            -- Send update to NUI to display remaining time
            SendNUIMessage({
                action = "updateJailTimer",
                time = jailTimeRemaining
            })

            -- Enforce Jail Restrictions (Optimized to avoid redundant calls)
            local controlsToDisable = {
                24, 25, 140, 141, 142, 257, 263, 264,
                23, 51, 22,
                246, 12, 13, 14, 15, 44, 45
            }
            
            for _, control in ipairs(controlsToDisable) do
                DisableControlAction(0, control, true)
            end
            
            if GetSelectedPedWeapon(playerPed) ~= GetHashKey("WEAPON_UNARMED") then
                SetCurrentPedWeapon(playerPed, GetHashKey("WEAPON_UNARMED"), true)
            end

            if Config.Keybinds and Config.Keybinds.openInventory then
                DisableControlAction(0, Config.Keybinds.openInventory, true)
            else
                DisableControlAction(0, 244, true)
            end

            -- Confinement to jail area
            local currentPos = GetEntityCoords(playerPed)
            local distanceToJailCenter = #(currentPos - JailMainPoint)

            if distanceToJailCenter > JailRadius then
                Log("Jailed player attempted to escape. Teleporting back.", "warn", "CNR_CLIENT")
                ShowNotification("~r~You cannot leave the prison area.")
                SetEntityCoords(playerPed, JailMainPoint.x, JailMainPoint.y, JailMainPoint.z, false, false, false, true)
            end

            if jailTimeRemaining <= 0 then
                isJailed = false -- Ensure flag is set before potentially triggering release
                -- Server will trigger cnr:releaseFromJail, client should not do it directly
                Log("Jail time expired on client. Waiting for server release.", "info", "CNR_CLIENT")
                SendNUIMessage({ action = "hideJailTimer" })
                jailTimerDisplayActive = false
                break
            end
        end
        Log("Jail update thread finished or player released.", "info", "CNR_CLIENT")
        jailTimerDisplayActive = false
        SendNUIMessage({ action = "hideJailTimer" })
        jailThreadRunning = false
    end)
end

local function ApplyPlayerModel(modelHash)
    if not modelHash or modelHash == 0 then
        Log("ApplyPlayerModel: Invalid modelHash received: " .. tostring(modelHash), "error", "CNR_CLIENT")
        return
    end

    local playerPed = PlayerPedId()
    RequestModel(modelHash)
    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 100 do
        Citizen.Wait(50)
        attempts = attempts + 1
    end

    if HasModelLoaded(modelHash) then
        Log("ApplyPlayerModel: Model " .. modelHash .. " loaded. Setting player model.", "info", "CNR_CLIENT")
        SetPlayerModel(PlayerId(), modelHash)
        Citizen.Wait(100) -- Allow model to apply
        SetPedDefaultComponentVariation(playerPed) -- Reset components to default for the new model
        SetModelAsNoLongerNeeded(modelHash)
    else
        Log("ApplyPlayerModel: Failed to load model " .. modelHash .. " after 100 attempts.", "error", "CNR_CLIENT")
        ShowNotification("~r~Error applying appearance change.")
    end
end

AddEventHandler('cnr:sendToJail', function(durationSeconds, prisonLocation)
    Log(string.format("Received cnr:sendToJail. Duration: %d, Location: %s", durationSeconds, json.encode(prisonLocation)), "info", "CNR_CLIENT")
    local playerPed = PlayerPedId()

    isJailed = true
    jailTimeRemaining = durationSeconds

    -- Store original player model
    originalPlayerModelHash = GetEntityModel(playerPed)
    Log("Stored original player model: " .. originalPlayerModelHash, "info", "CNR_CLIENT")

    -- Apply jail uniform
    local jailUniformModelKey = Config.JailUniformModel or "a_m_m_prisoner_01" -- Fallback if config is missing
    local jailUniformModelHash = GetHashKey(jailUniformModelKey)
    if jailUniformModelHash ~= 0 then
        ApplyPlayerModel(jailUniformModelHash)
    else
        Log("Invalid JailUniformModel in Config: " .. jailUniformModelKey, "error", "CNR_CLIENT")
    end

    -- Teleport player to prison
    if prisonLocation and prisonLocation.x and prisonLocation.y and prisonLocation.z then
        JailMainPoint = vector3(prisonLocation.x, prisonLocation.y, prisonLocation.z) -- Update the jail center point
        RequestCollisionAtCoord(JailMainPoint.x, JailMainPoint.y, JailMainPoint.z) -- Request collision for the jail area
        SetEntityCoords(playerPed, JailMainPoint.x, JailMainPoint.y, JailMainPoint.z, false, false, false, true)
        SetEntityHeading(playerPed, prisonLocation.w or 0.0) -- Use heading if provided
        ClearPedTasksImmediately(playerPed)
    else
        Log("cnr:sendToJail - Invalid prisonLocation received. Using default: " .. json.encode(JailMainPoint), "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Could not teleport to jail - invalid location.")
        isJailed = false -- Don't proceed if teleport fails
        originalPlayerModelHash = nil -- Clear stored model if jailing fails
        return
    end

    -- Remove all weapons from player
    RemoveAllPedWeapons(playerPed, true)
    ShowNotification("~r~All weapons have been confiscated.")

    -- Send NUI message to show jail timer
    SendNUIMessage({
        action = "showJailTimer",
        initialTime = jailTimeRemaining
    })

    StartJailUpdateThread(durationSeconds)
end)

AddEventHandler('cnr:releaseFromJail', function()
    Log("Received cnr:releaseFromJail.", "info", "CNR_CLIENT")
    local playerPed = PlayerPedId()

    isJailed = false
    jailTimeRemaining = 0
    StopJailUpdateThread() -- Signal the jail loop to stop and hide UI

    -- Send NUI message to hide jail timer
    SendNUIMessage({ action = "hideJailTimer" })

    -- Restore player model
    if originalPlayerModelHash and originalPlayerModelHash ~= 0 then
        Log("Restoring original player model: " .. originalPlayerModelHash, "info", "CNR_CLIENT")
        ApplyPlayerModel(originalPlayerModelHash)
    else
        Log("No original player model stored or it was invalid. Attempting to restore to role default or citizen model.", "warn", "CNR_CLIENT")
        if playerData and playerData.role and playerData.role ~= "" and playerData.role ~= "citizen" then
            Log("Attempting to apply model for role: " .. playerData.role, "info", "CNR_CLIENT")
            ApplyRoleVisualsAndLoadout(playerData.role, nil) -- Applies role default model & basic loadout
        else
            Log("Player role unknown or citizen, applying default citizen model.", "info", "CNR_CLIENT")
            ApplyRoleVisualsAndLoadout("citizen", nil) -- Fallback to citizen visuals
        end
    end
    originalPlayerModelHash = nil -- Clear stored model hash after attempting restoration

    -- Determine release location
    local determinedReleaseLocation = nil
    local hardcodedDefaultSpawn = vector3(186.0, -946.0, 30.0) -- Legion Square, a very safe fallback

    if playerData and playerData.role and Config.SpawnPoints and Config.SpawnPoints[playerData.role] then
        determinedReleaseLocation = Config.SpawnPoints[playerData.role]
        Log(string.format("Using spawn point for role '%s'.", playerData.role), "info", "CNR_CLIENT")
    elseif Config.SpawnPoints and Config.SpawnPoints["citizen"] then
        determinedReleaseLocation = Config.SpawnPoints["citizen"]
        Log("Role spawn not found or role invalid, using citizen spawn point.", "warn", "CNR_CLIENT")
        ShowNotification("~y~Your role spawn was not found, using default citizen spawn.")
    else
        determinedReleaseLocation = hardcodedDefaultSpawn
        Log("Citizen spawn point also not found in Config. Using hardcoded default spawn.", "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Default spawn locations not configured. Using a fallback location.")
    end    if determinedReleaseLocation and determinedReleaseLocation.x and determinedReleaseLocation.y and determinedReleaseLocation.z then
        SetEntityCoords(playerPed, determinedReleaseLocation.x, determinedReleaseLocation.y, determinedReleaseLocation.z, false, false, false, true)
        SetEntityHeading(playerPed, 0.0) -- Set default heading since spawn points don't include rotation
        Log(string.format("Player released from jail. Teleported to: %s", json.encode(determinedReleaseLocation)), "info", "CNR_CLIENT")
    else
        -- This case should be rare given the fallbacks, but as a last resort:
        Log("cnr:releaseFromJail - CRITICAL: No valid release spawn point determined even with fallbacks. Player may be stuck or at Zero Coords.", "error", "CNR_CLIENT")
        ShowNotification("~r~CRITICAL ERROR: Could not determine release location. Please contact an admin.")
        -- As an absolute last measure, teleport to a known safe spot if playerPed is valid
        if playerPed and playerPed ~= 0 then
             SetEntityCoords(playerPed, hardcodedDefaultSpawn.x, hardcodedDefaultSpawn.y, hardcodedDefaultSpawn.z, false, false, false, true)
        end
    end

    ClearPedTasksImmediately(playerPed)
    -- Player's weapons are not automatically restored here.
    -- They would get default role weapons upon next role sync or if they visit an armory.
    -- Or, could potentially save/restore their exact weapons pre-jailing if desired (more complex).
    ShowNotification("~g~You have been released from jail.")
end)


-- ====================================================================
-- Contraband Dealers
-- ====================================================================

local contrabandDealerBlips = {}
local contrabandDealerPeds = {}
local activityBlips = {
    banks = {},
    hideouts = {},
    policeStations = {}
}

local function ClearBlipCollection(blips)
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    for index = #blips, 1, -1 do
        blips[index] = nil
    end
end

function UpdateActivityBlips()
    ClearBlipCollection(activityBlips.banks)
    ClearBlipCollection(activityBlips.hideouts)
    ClearBlipCollection(activityBlips.policeStations)

    local bankLocations = (Config.BankTellers and #Config.BankTellers > 0) and Config.BankTellers or (Config.HeistLocations or {})

    for _, location in ipairs(bankLocations) do
        local heistCoords = GetEntryCoords(location)
        if heistCoords then
            local blip = AddBlipForCoord(heistCoords.x, heistCoords.y, heistCoords.z)
            SetBlipSprite(blip, location.blipSprite or 108)
            SetBlipColour(blip, location.blipColor or 2)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(location.name or "Bank Teller")
            EndTextCommandSetBlipName(blip)
            table.insert(activityBlips.banks, blip)
        end
    end

    local policeStationCoords = Config.SpawnPoints and Config.SpawnPoints.cop
    if policeStationCoords then
        local stationCoords = GetEntryCoords(policeStationCoords) or policeStationCoords
        if stationCoords and stationCoords.x and stationCoords.y and stationCoords.z then
            local blip = AddBlipForCoord(stationCoords.x, stationCoords.y, stationCoords.z)
            SetBlipSprite(blip, 60)
            SetBlipColour(blip, 38)
            SetBlipScale(blip, 0.85)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Police Station")
            EndTextCommandSetBlipName(blip)
            table.insert(activityBlips.policeStations, blip)
        end
    end

    if role ~= "robber" then
        return
    end

    for _, hideout in ipairs(Config.RobberHideouts or {}) do
        local hideoutCoords = GetEntryCoords(hideout)
        if hideoutCoords then
            local blip = AddBlipForCoord(hideoutCoords.x, hideoutCoords.y, hideoutCoords.z)
            SetBlipSprite(blip, hideout.blipSprite or 40)
            SetBlipColour(blip, hideout.blipColor or 1)
            SetBlipScale(blip, 0.75)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(hideout.name or "Robber Hideout")
            EndTextCommandSetBlipName(blip)
            table.insert(activityBlips.hideouts, blip)
        end
    end
end

local function ClearContrabandDealerEntities()
    ClearBlipCollection(contrabandDealerBlips)

    for _, ped in ipairs(contrabandDealerPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    for index = #contrabandDealerPeds, 1, -1 do
        contrabandDealerPeds[index] = nil
    end
end

local function SpawnContrabandDealerEntities()
    if #contrabandDealerPeds > 0 or role ~= "robber" then
        return
    end

    for _, dealer in ipairs(Config.ContrabandDealers) do
        local dealerCoords = GetEntryCoords(dealer)
        if dealerCoords then
            -- Create blip
            local blip = AddBlipForCoord(dealerCoords.x, dealerCoords.y, dealerCoords.z)
            SetBlipSprite(blip, dealer.blipSprite or 378) -- Mask icon
            SetBlipColour(blip, dealer.blipColor or 1) -- Red
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(dealer.name or "Contraband Dealer")
            EndTextCommandSetBlipName(blip)
            
            -- Add to dealer blips table
            table.insert(contrabandDealerBlips, blip)
            
            -- Create dealer ped
            local pedHash = GetHashKey(dealer.model or "s_m_y_dealer_01")
            
            -- Request the model
            RequestModel(pedHash)
            while not HasModelLoaded(pedHash) do
                Citizen.Wait(10)
            end
            
            -- Create ped
            local ped = CreatePed(4, pedHash, dealerCoords.x, dealerCoords.y, dealerCoords.z, GetEntryHeading(dealer), false, true)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            
            -- Add to dealer peds table
            table.insert(contrabandDealerPeds, ped)
        end
    end
end

-- Create/remove contraband dealer blips and peds based on player role
Citizen.CreateThread(function()
    -- Wait for client to fully initialize
    Citizen.Wait(5000)

    while true do
        if role == "robber" then
            SpawnContrabandDealerEntities()
        else
            ClearContrabandDealerEntities()
        end

        Citizen.Wait(2000)
    end
end)

-- Interaction with contraband dealers
Citizen.CreateThread(function()
    while true do
        if role ~= "robber" then
            Citizen.Wait(1000)
        else
            Citizen.Wait(100)
        end
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        if role == "robber" then
            for _, dealer in ipairs(Config.ContrabandDealers) do
                local dealerCoords = GetEntryCoords(dealer)
                if dealerCoords then
                    local distance = #(playerCoords - dealerCoords)
                    if distance < 3.0 then
                        DrawSphere(dealerCoords.x, dealerCoords.y, dealerCoords.z - 0.5, 0.5, 255, 0, 0, 0.2)
                        
                        BeginTextCommandDisplayHelp("STRING")
                        AddTextComponentSubstringPlayerName("Press ~INPUT_CONTEXT~ to access the contraband dealer")
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        
                        if IsControlJustReleased(0, 38) then -- E key
                            TriggerServerEvent('cnr:accessContrabandDealer')
                        end
                    end
                end
            end
        end
    end
end)

-- Function to spawn player at a specific location
function SpawnPlayerAtLocation(spawnLocation, spawnHeading, role)
    if not spawnLocation then
        print("[CNR_CLIENT_ERROR] SpawnPlayerAtLocation: Invalid spawn location")
        return
    end
    
    local playerPed = PlayerPedId()
    local spawnCoords = GetEntryCoords(spawnLocation)
    local finalHeading = GetEntryHeading(spawnLocation, spawnHeading or GetRoleSpawnHeading(role))

    if not spawnCoords then
        print("[CNR_CLIENT_ERROR] SpawnPlayerAtLocation: Unsupported spawn location format")
        return
    end

    -- Apply the role model/loadout before moving the ped. Changing the model after
    -- teleporting can snap the player back to the previous location.
    if role then
        ApplyRoleVisualsAndLoadout(role)
        playerPed = PlayerPedId()
    end

    TeleportPlayerToEntry(playerPed, spawnLocation, finalHeading)
    QueueInventoryReequip(1000)
    
end

-- Event handler for spawning player at location
AddEventHandler('cnr:spawnPlayerAt', function(spawnLocation, spawnHeading, role)
    SpawnPlayerAtLocation(spawnLocation, spawnHeading, role)
end)

-- =========================
--      Banking System Client
-- =========================

-- Banking client variables
local bankingData = {
    balance = 0,
    transactionHistory = {},
    activeLoan = nil,
    activeInvestments = {},
    investmentOptions = {},
    currentATM = nil,
    currentBankTeller = nil,
    isUsingATM = false,
    isAtBank = false
}

local atmProps = {}
local bankTellerPeds = {}
local atmHackInProgress = false

-- Register banking events
RegisterNetEvent('cnr:updateBankBalance')
RegisterNetEvent('cnr:updateTransactionHistory')
RegisterNetEvent('cnr:startATMHack')
RegisterNetEvent('cnr:showNotification')

-- Update bank balance
AddEventHandler('cnr:updateBankBalance', function(balance)
    bankingData.balance = balance
    SendNUIMessage({
        action = "updateBankBalance",
        resourceName = GetCurrentResourceName(),
        balance = balance
    })
end)

-- Update transaction history
AddEventHandler('cnr:updateTransactionHistory', function(history)
    bankingData.transactionHistory = history
    SendNUIMessage({
        action = "updateTransactionHistory",
        resourceName = GetCurrentResourceName(),
        history = history
    })
end)

AddEventHandler('cnr:updateBankingDetails', function(payload)
    local details = payload and payload.details or payload or {}
    bankingData.balance = tonumber(details.balance) or bankingData.balance or 0
    bankingData.transactionHistory = details.transactions or bankingData.transactionHistory or {}
    bankingData.activeLoan = details.loan or nil
    bankingData.activeInvestments = details.investments or {}
    bankingData.investmentOptions = details.investmentOptions or bankingData.investmentOptions or {}

    SendNUIMessage({
        action = "updateBankingDetails",
        resourceName = GetCurrentResourceName(),
        details = {
            balance = bankingData.balance,
            transactions = bankingData.transactionHistory,
            loan = bankingData.activeLoan,
            investments = bankingData.activeInvestments,
            investmentOptions = bankingData.investmentOptions
        }
    })
end)

-- Show notification
AddEventHandler('cnr:showNotification', function(message, type)
    SendNUIMessage({
        action = "showNotification",
        resourceName = GetCurrentResourceName(),
        message = message,
        notificationType = type or "info"
    })
end)

AddEventHandler('cnr:notification', function(message, type)
    TriggerEvent('cnr:showNotification', message, type)
end)

AddEventHandler('cnr:openHeistPlanning', function(heistConfig, crewId, crewRoles, equipmentShop)
    SendNUIMessage({
        action = "openHeistPlanning",
        resourceName = GetCurrentResourceName(),
        heistConfig = heistConfig,
        crewId = crewId,
        crewRoles = crewRoles or {},
        equipmentShop = equipmentShop or {}
    })
    SetNuiFocus(true, true)
end)

AddEventHandler('cnr:updateAvailableHeists', function(heists)
    SendNUIMessage({
        action = "updateAvailableHeists",
        resourceName = GetCurrentResourceName(),
        heists = heists or {}
    })
end)

AddEventHandler('cnr:updateCrewInfo', function(crew)
    SendNUIMessage({
        action = "updateCrewInfo",
        resourceName = GetCurrentResourceName(),
        crew = crew
    })
end)

AddEventHandler('cnr:startHeistExecution', function(heistConfig, crew)
    SendNUIMessage({
        action = "startHeistExecution",
        resourceName = GetCurrentResourceName(),
        heistConfig = heistConfig,
        crew = crew
    })
    SetNuiFocus(true, true)
end)

AddEventHandler('cnr:updateHeistStage', function(stageData)
    SendNUIMessage({
        action = "updateHeistStage",
        resourceName = GetCurrentResourceName(),
        stageData = stageData
    })
end)

AddEventHandler('cnr:policeAlert', function(alertData)
    local alertType = alertData and alertData.type or "Police Alert"
    local details = alertData and (alertData.heistName or alertData.suspect) or nil
    local message = details and string.format("%s: %s", alertType, details) or alertType

    TriggerEvent('cnr:showNotification', message, "warning")
end)

-- ATM hacking for robbers
AddEventHandler('cnr:startATMHack', function(atmId, duration)
    if atmHackInProgress then return end
    
    atmHackInProgress = true
    local playerPed = PlayerPedId()
    
    -- Play hacking animation
    RequestAnimDict("anim@amb@business@cfid@cfid_machine_use@")
    while not HasAnimDictLoaded("anim@amb@business@cfid@cfid_machine_use@") do
        Citizen.Wait(100)
    end
    
    TaskPlayAnim(playerPed, "anim@amb@business@cfid@cfid_machine_use@", "machine_use_enter", 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- Show progress bar
    SendNUIMessage({
        type = "showProgressBar",
        duration = duration,
        label = "Hacking ATM..."
    })
    
    -- Reset after duration
    SetTimeout(duration, function()
        atmHackInProgress = false
        ClearPedTasks(playerPed)
        SendNUIMessage({
            type = "hideProgressBar"
        })
    end)
end)

-- Initialize ATM props on resource start
function InitializeBankingProps()
    for _, atm in pairs(atmProps) do
        if atm.prop and DoesEntityExist(atm.prop) then
            DeleteEntity(atm.prop)
        end
    end

    for _, teller in pairs(bankTellerPeds) do
        if teller.ped and DoesEntityExist(teller.ped) then
            DeleteEntity(teller.ped)
        end
    end

    atmProps = {}
    bankTellerPeds = {}

    -- Track ATM interaction points without spawning duplicate props over the map
    for i, atm in pairs(Config.ATMLocations) do
        atmProps[i] = {
            coords = atm.pos,
            id = i
        }
    end
    
    -- Create bank teller NPCs
    for i, teller in pairs(Config.BankTellers) do
        local tellerCoords = GetEntryCoords(teller)
        if tellerCoords then
            RequestModel(GetHashKey(teller.model))
            while not HasModelLoaded(GetHashKey(teller.model)) do
                Citizen.Wait(100)
            end

            local foundGround, groundZ = GetGroundZFor_3dCoord(tellerCoords.x, tellerCoords.y, tellerCoords.z + 1.0, false)
            local pedZ = foundGround and groundZ or (tellerCoords.z - 1.0)
            local ped = CreatePed(4, GetHashKey(teller.model), tellerCoords.x, tellerCoords.y, pedZ, GetEntryHeading(teller), false, true)
            SetEntityCanBeDamaged(ped, false)
            SetPedCanRagdollFromPlayerImpact(ped, false)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetEntityInvincible(ped, true)
            SetEntityAsMissionEntity(ped, true, true)
            SetEntityHeading(ped, GetEntryHeading(teller))
            FreezeEntityPosition(ped, true)
            
            bankTellerPeds[i] = {
                ped = ped,
                coords = tellerCoords,
                name = teller.name,
                services = teller.services,
                id = i
            }
        end
    end
end

-- Main banking interaction thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local closestATM = nil
        local closestBankTeller = nil
        local closestATMDist = math.huge
        local closestTellerDist = math.huge
        
        -- Check ATM proximity
        for i, atm in pairs(atmProps) do
            if atm.coords then
                local dist = #(playerCoords - atm.coords)
                if dist < 2.0 and dist < closestATMDist then
                    closestATM = atm
                    closestATMDist = dist
                end
            end
        end
        
        -- Check bank teller proximity
        for i, teller in pairs(bankTellerPeds) do
            if teller.ped and DoesEntityExist(teller.ped) then
                local dist = #(playerCoords - teller.coords)
                if dist < 3.0 and dist < closestTellerDist then
                    closestBankTeller = teller
                    closestTellerDist = dist
                end
            end
        end
        
        -- Handle ATM interactions
        if closestATM and closestATMDist < 2.0 then
            if not bankingData.isUsingATM then
                ShowHelpText("Press ~INPUT_CONTEXT~ to use ATM\nPress ~INPUT_DETONATE~ to hack ATM (Robbers only)")
                
                if IsControlJustPressed(0, 38) then -- E key
                    OpenATMInterface(closestATM)
                elseif IsControlJustPressed(0, 47) then -- G key (hack)
                    TriggerServerEvent('cnr:hackATM', closestATM.id)
                end
            end
        end
        
        -- Handle bank teller interactions
        if closestBankTeller and closestTellerDist < 3.0 then
            if not bankingData.isAtBank then
                ShowHelpText("Press ~INPUT_CONTEXT~ to speak with " .. closestBankTeller.name)
                
                if IsControlJustPressed(0, 38) then -- E key
                    OpenBankInterface(closestBankTeller)
                end
            end
        end
        
        -- If no interactions available, hide help text
        if not closestATM and not closestBankTeller then
            bankingData.isUsingATM = false
            bankingData.isAtBank = false
        end
    end
end)

-- Open ATM interface
function OpenATMInterface(atm)
    bankingData.isUsingATM = true
    bankingData.currentATM = atm
    
    TriggerServerEvent('cnr:getBankingDetails')
    
    -- Open ATM UI
    SendNUIMessage({
        action = "openATM",
        resourceName = GetCurrentResourceName(),
        atmData = {
            id = atm.id,
            balance = bankingData.balance
        }
    })
    
    SetNuiFocus(true, true)
end

-- Open bank interface
function OpenBankInterface(teller)
    bankingData.isAtBank = true
    bankingData.currentBankTeller = teller
    
    TriggerServerEvent('cnr:getBankingDetails')
    
    -- Open bank UI
    SendNUIMessage({
        action = "openBank",
        resourceName = GetCurrentResourceName(),
        bankData = {
            tellerName = teller.name,
            services = teller.services,
            balance = bankingData.balance,
            transactions = bankingData.transactionHistory,
            loan = bankingData.activeLoan,
            investments = bankingData.activeInvestments,
            investmentOptions = bankingData.investmentOptions
        }
    })
    
    SetNuiFocus(true, true)
end

-- Close banking interfaces
function CloseBankingInterface()
    bankingData.isUsingATM = false
    bankingData.isAtBank = false
    bankingData.currentATM = nil
    bankingData.currentBankTeller = nil
    
    SendNUIMessage({
        action = "closeBanking"
    })
    
    SetNuiFocus(false, false)
end

-- NUI Callbacks for banking
RegisterNUICallback('closeBanking', function(data, cb)
    CloseBankingInterface()
    cb('ok')
end)

RegisterNUICallback('openCharacterEditor', function(data, cb)
    if not data or not data.role then
        cb({ success = false, error = 'Invalid character editor request.' })
        return
    end

    isRoleSelectionVisible = false
    OpenCharacterEditor(data.role, tonumber(data.characterSlot) or 1)
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_save', function(data, cb)
    CloseCharacterEditor(true)
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_cancel', function(data, cb)
    CloseCharacterEditor(false)
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_updateFeature', function(data, cb)
    if not currentCharacterData then
        cb({ success = false, error = 'Character editor is not active.' })
        return
    end

    currentCharacterData.faceFeatures = currentCharacterData.faceFeatures or {}
    currentCharacterData.components = currentCharacterData.components or {}
    currentCharacterData.props = currentCharacterData.props or {}

    local category = data and data.category
    local feature = data and data.feature
    local value = data and data.value

    if not feature then
        cb({ success = false, error = 'Missing feature name.' })
        return
    end

    if category == 'faceFeatures' then
        currentCharacterData.faceFeatures[feature] = tonumber(value) or 0.0
    else
        currentCharacterData[feature] = tonumber(value)
        if currentCharacterData[feature] == nil then
            currentCharacterData[feature] = value
        end
    end

    ApplyCharacterData(currentCharacterData, PlayerPedId())
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_updateComponent', function(data, cb)
    if not currentCharacterData then
        cb({ success = false, error = 'Character editor is not active.' })
        return
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        cb({ success = false, error = 'Player ped is unavailable.' })
        return
    end

    local entryType = data and data.entryType == 'prop' and 'prop' or 'component'
    local targetId = tonumber(data and (data.targetId or data.component))
    local valueType = data and (data.valueType or data.type)
    local rawValue = tonumber(data and data.value)

    if targetId == nil or rawValue == nil or (valueType ~= 'drawable' and valueType ~= 'texture') then
        cb({ success = false, error = 'Invalid clothing update.' })
        return
    end

    currentCharacterData.components = currentCharacterData.components or {}
    currentCharacterData.props = currentCharacterData.props or {}

    local targetTable = entryType == 'prop' and currentCharacterData.props or currentCharacterData.components
    local targetKey = tostring(targetId)
    local targetEntry = targetTable[targetKey] or targetTable[targetId] or {
        drawable = entryType == 'prop' and -1 or 0,
        texture = 0
    }

    local clampedValue = rawValue

    if entryType == 'component' then
        if valueType == 'drawable' then
            local maxDrawable = math.max(GetNumberOfPedDrawableVariations(ped, targetId) - 1, 0)
            clampedValue = math.min(math.max(math.floor(rawValue), 0), maxDrawable)
            targetEntry.drawable = clampedValue

            local maxTexture = math.max(GetNumberOfPedTextureVariations(ped, targetId, clampedValue) - 1, 0)
            targetEntry.texture = math.min(math.max(tonumber(targetEntry.texture) or 0, 0), maxTexture)
        else
            local drawable = tonumber(targetEntry.drawable) or 0
            local maxTexture = math.max(GetNumberOfPedTextureVariations(ped, targetId, drawable) - 1, 0)
            clampedValue = math.min(math.max(math.floor(rawValue), 0), maxTexture)
            targetEntry.texture = clampedValue
        end
    else
        if valueType == 'drawable' then
            local maxDrawable = math.max(GetNumberOfPedPropDrawableVariations(ped, targetId) - 1, -1)
            clampedValue = math.min(math.max(math.floor(rawValue), -1), maxDrawable)
            targetEntry.drawable = clampedValue

            if clampedValue == -1 then
                targetEntry.texture = 0
            else
                local maxTexture = math.max(GetNumberOfPedPropTextureVariations(ped, targetId, clampedValue) - 1, 0)
                targetEntry.texture = math.min(math.max(tonumber(targetEntry.texture) or 0, 0), maxTexture)
            end
        else
            local drawable = tonumber(targetEntry.drawable)
            if drawable == nil or drawable < 0 then
                clampedValue = 0
                targetEntry.texture = 0
            else
                local maxTexture = math.max(GetNumberOfPedPropTextureVariations(ped, targetId, drawable) - 1, 0)
                clampedValue = math.min(math.max(math.floor(rawValue), 0), maxTexture)
                targetEntry.texture = clampedValue
            end
        end
    end

    targetTable[targetKey] = targetEntry
    ApplyCharacterData(currentCharacterData, ped)

    cb({
        success = true,
        entryType = entryType,
        targetId = targetId,
        drawable = targetEntry.drawable,
        texture = targetEntry.texture
    })
end)

RegisterNUICallback('characterEditor_changeCamera', function(data, cb)
    UpdateCharacterEditorCamera(data and data.mode or "full")
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_rotateCharacter', function(data, cb)
    local ped = PlayerPedId()
    local currentHeading = GetEntityHeading(ped)
    local delta = (data and data.direction == 'right') and 15.0 or -15.0
    SetEntityHeading(ped, currentHeading + delta)
    UpdateCharacterEditorCamera()
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_switchGender', function(data, cb)
    local gender = data and data.gender or 'male'
    local modelName = gender == 'female' and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Citizen.Wait(50)
    end

    SetPlayerModel(PlayerId(), modelHash)
    Citizen.Wait(100)
    currentCharacterData.model = modelName
    ApplyCharacterData(currentCharacterData, PlayerPedId())
    UpdateCharacterEditorCamera()
    cb({ success = true, characterData = DeepCopyCharacterData(currentCharacterData) })
end)

RegisterNUICallback('characterEditor_previewUniform', function(data, cb)
    local presetIndex = tonumber(data and data.presetIndex)
    local success = presetIndex and ApplyUniformPresetForCurrentRole(presetIndex + 1) or false
    cb({
        success = success,
        characterData = success and DeepCopyCharacterData(currentCharacterData) or nil
    })
end)

RegisterNUICallback('characterEditor_applyUniform', function(data, cb)
    local presetIndex = tonumber(data and data.presetIndex)
    local success = presetIndex and ApplyUniformPresetForCurrentRole(presetIndex + 1) or false
    cb({
        success = success,
        characterData = success and DeepCopyCharacterData(currentCharacterData) or nil
    })
end)

RegisterNUICallback('characterEditor_cancelUniformPreview', function(data, cb)
    ApplyCharacterData(currentCharacterData, PlayerPedId())
    cb({ success = true, characterData = DeepCopyCharacterData(currentCharacterData) })
end)

RegisterNUICallback('characterEditor_reset', function(data, cb)
    local defaultCharacter = GetDefaultCharacterData()
    defaultCharacter.model = currentCharacterData and currentCharacterData.model or defaultCharacter.model

    currentCharacterData = DeepCopyCharacterData(defaultCharacter)

    local desiredModel = currentCharacterData.model or "mp_m_freemode_01"
    local modelHash = GetHashKey(desiredModel)
    RequestModel(modelHash)

    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 100 do
        Citizen.Wait(50)
        attempts = attempts + 1
    end

    if HasModelLoaded(modelHash) and GetEntityModel(PlayerPedId()) ~= modelHash then
        SetPlayerModel(PlayerId(), modelHash)
        Citizen.Wait(100)
    end

    ApplyCharacterData(currentCharacterData, PlayerPedId())
    UpdateCharacterEditorCamera()

    cb({ success = true, characterData = DeepCopyCharacterData(currentCharacterData) })
end)

RegisterNUICallback('characterEditor_loadCharacter', function(data, cb)
    local characterKey = data and data.characterKey
    if characterKey and playerCharacters[characterKey] then
        currentCharacterData = DeepCopyCharacterData(playerCharacters[characterKey])

        local desiredModel = currentCharacterData.model or "mp_m_freemode_01"
        local modelHash = GetHashKey(desiredModel)
        RequestModel(modelHash)

        local attempts = 0
        while not HasModelLoaded(modelHash) and attempts < 100 do
            Citizen.Wait(50)
            attempts = attempts + 1
        end

        if HasModelLoaded(modelHash) and GetEntityModel(PlayerPedId()) ~= modelHash then
            SetPlayerModel(PlayerId(), modelHash)
            Citizen.Wait(100)
        end

        ApplyCharacterData(currentCharacterData, PlayerPedId())
        UpdateCharacterEditorCamera()
        cb({ success = true, characterData = DeepCopyCharacterData(currentCharacterData) })
        return
    end

    cb({ success = false, error = 'Character not found.' })
end)

RegisterNUICallback('characterEditor_deleteCharacter', function(data, cb)
    local characterKey = data and data.characterKey
    if characterKey then
        playerCharacters[characterKey] = nil
        TriggerServerEvent('cnr:deleteCharacterData', characterKey)
        cb({ success = true })
        return
    end

    cb({ success = false, error = 'Character not found.' })
end)

RegisterNUICallback('characterEditor_opened', function(data, cb)
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_closed', function(data, cb)
    cb({ success = true })
end)

RegisterNUICallback('characterEditor_error', function(data, cb)
    Log('[CNR_CHARACTER_EDITOR] ' .. tostring(data and data.error or 'Unknown NUI error'), 'error', 'CNR_CHARACTER_EDITOR')
    cb({ success = true })
end)

RegisterNUICallback('bankDeposit', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:bankDeposit', amount)
    end
    cb('ok')
end)

RegisterNUICallback('bankWithdraw', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:bankWithdraw', amount)
    end
    cb('ok')
end)

RegisterNUICallback('bankTransfer', function(data, cb)
    local targetId = tonumber(data.targetId)
    local amount = tonumber(data.amount)
    if targetId and amount and amount > 0 then
        TriggerServerEvent('cnr:bankTransfer', targetId, amount)
    end
    cb('ok')
end)

RegisterNUICallback('requestLoan', function(data, cb)
    local amount = tonumber(data.amount)
    local duration = tonumber(data.duration)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:requestLoan', amount, duration)
    end
    cb('ok')
end)

RegisterNUICallback('repayLoan', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:repayLoan', amount)
    end
    cb('ok')
end)

RegisterNUICallback('makeInvestment', function(data, cb)
    local investmentId = data.investmentId
    local amount = tonumber(data.amount)
    if investmentId and amount and amount > 0 then
        TriggerServerEvent('cnr:makeInvestment', investmentId, amount)
    end
    cb('ok')
end)

RegisterNUICallback('closeHeistPlanning', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getAvailableHeists', function(data, cb)
    TriggerServerEvent('cnr:getAvailableHeists')
    cb('ok')
end)

RegisterNUICallback('startHeistPlanning', function(data, cb)
    if data and data.heistId then
        TriggerServerEvent('cnr:startHeistPlanning', data.heistId)
    end
    cb('ok')
end)

RegisterNUICallback('joinHeistCrew', function(data, cb)
    if data and data.crewId and data.role then
        TriggerServerEvent('cnr:joinHeistCrew', data.crewId, data.role)
    end
    cb('ok')
end)

RegisterNUICallback('purchaseHeistEquipment', function(data, cb)
    local quantity = tonumber(data and data.quantity) or 1
    if data and data.itemId and quantity > 0 then
        TriggerServerEvent('cnr:purchaseHeistEquipment', data.itemId, quantity)
    end
    cb('ok')
end)

RegisterNUICallback('startEnhancedHeist', function(data, cb)
    TriggerServerEvent('cnr:startEnhancedHeist')
    cb('ok')
end)

RegisterNUICallback('leaveHeistCrew', function(data, cb)
    TriggerServerEvent('cnr:leaveHeistCrew')
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Helper function to show help text
function ShowHelpText(text)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

-- Initialize banking system when resource starts
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Wait for game to load then initialize banking
        Citizen.Wait(5000)
        InitializeBankingProps()
    end
end)

-- Clean up banking props when resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up ATM props
        for _, atm in pairs(atmProps) do
            if atm.prop and DoesEntityExist(atm.prop) then
                DeleteEntity(atm.prop)
            end
        end
        
        -- Clean up bank teller peds
        for _, teller in pairs(bankTellerPeds) do
            if teller.ped and DoesEntityExist(teller.ped) then
                DeleteEntity(teller.ped)
            end
        end
    end
end)

-- =====================================
--     CONSOLIDATED EVENT HANDLERS
-- =====================================

-- Event handlers for inventory system
AddEventHandler('cnr:receiveMyInventory', function(minimalInventoryData, equippedItemsArray)
    Log("Received cnr:receiveMyInventory event. Processing inventory data...", "info", "CNR_INV_CLIENT")
    
    if equippedItemsArray and type(equippedItemsArray) == "table" then
        Log("Received equipped items list with " .. #equippedItemsArray .. " items", "info", "CNR_INV_CLIENT")
        
        localPlayerEquippedItems = {}
        for _, itemId in ipairs(equippedItemsArray) do
            localPlayerEquippedItems[itemId] = true
        end
    end
    
    UpdateFullInventory(minimalInventoryData)
end)

AddEventHandler('cnr:syncInventory', function(minimalInventoryData)
    Log("Received cnr:syncInventory event. Processing inventory data...", "info", "CNR_INV_CLIENT")
    UpdateFullInventory(minimalInventoryData)
end)

AddEventHandler('cnr:inventoryUpdated', function(updatedMinimalInventory)
    Log("Received cnr:inventoryUpdated. This event might need review if cnr:syncInventory is primary.", "warn", "CNR_INV_CLIENT")
    UpdateFullInventory(updatedMinimalInventory)
end)

AddEventHandler('cnr:createDroppedWorldItem', function(dropData)
    CreateDroppedWorldItem(dropData)
end)

AddEventHandler('cnr:removeDroppedWorldItem', function(dropId)
    RemoveDroppedWorldItem(tonumber(dropId))
end)

AddEventHandler('cnr:receiveConfigItems', function(receivedConfigItems)
    clientConfigItems = receivedConfigItems
    Log("Received Config.Items from server. Item count: " .. tablelength(clientConfigItems or {}), "info", "CNR_INV_CLIENT")

    SendNUIMessage({
        action = 'storeFullItemConfig',
        itemConfig = clientConfigItems
    })
    Log("Sent Config.Items to NUI via SendNUIMessage.", "info", "CNR_INV_CLIENT")

    if localPlayerInventory and next(localPlayerInventory) then
        local firstItemId = next(localPlayerInventory)
        if localPlayerInventory[firstItemId] and (localPlayerInventory[firstItemId].name == firstItemId or localPlayerInventory[firstItemId].name == nil) then
             Log("Config.Items received after minimal inventory was stored. Attempting full reconstruction.", "info", "CNR_INV_CLIENT")
             UpdateFullInventory(localPlayerInventory)
        else
             Log("Config.Items received, inventory appears processed. Re-equipping weapons to ensure visibility.", "info", "CNR_INV_CLIENT")
             EquipInventoryWeapons()
        end
    else
        Log("Config.Items received but no pending inventory to reconstruct.", "info", "CNR_INV_CLIENT")
    end
end)

-- Event handlers for progression system
AddEventHandler('cnr:xpGained', function(amount, reason)
    local newTotalXp = (playerData and playerData.xp or currentXP or 0) + (amount or 0)
    local roleName = playerData and playerData.role or role

    playerData.xp = newTotalXp
    ShowNotification(string.format("~g~+%d XP! (Total: %d)", amount or 0, newTotalXp))
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = newTotalXp,
        currentLevel = playerData.level,
        xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, roleName),
        xpGained = amount or 0
    })
    UpdateXPDisplayElements(
        newTotalXp,
        playerData.level,
        CalculateXpForNextLevelClient(playerData.level, roleName),
        amount or 0
    )

    if reason then
        ShowProgressionNotification(string.format("+%d XP (%s)", amount or 0, reason), "xp", 3000)
    end
end)

AddEventHandler('cnr:levelUp', function(newLevel, newTotalXp)
    local roleName = playerData and playerData.role or role

    playerData.level = newLevel
    playerData.xp = newTotalXp
    ShowNotification("~g~LEVEL UP!~w~ You reached Level " .. newLevel .. "!")
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = newTotalXp,
        currentLevel = newLevel,
        xpForNextLevel = CalculateXpForNextLevelClient(newLevel, roleName),
        xpGained = 0
    })

    currentLevel = newLevel
    currentXP = newTotalXp
    PlayLevelUpEffects(newLevel)
    UpdateXPDisplayElements(
        newTotalXp,
        newLevel,
        CalculateXpForNextLevelClient(newLevel, roleName),
        0
    )
    ShowProgressionNotification(string.format("🎉 LEVEL UP! You reached Level %d!", newLevel), "levelup", 7000)
end)

AddEventHandler('cnr:playLevelUpEffects', function(newLevel)
    PlayLevelUpEffects(newLevel)
end)

-- Event handlers for character editor
AddEventHandler('cnr:openCharacterEditor', function(role, characterSlot)
    OpenCharacterEditor(role, characterSlot)
end)

AddEventHandler('cnr:loadedPlayerCharacters', function(characters)
    playerCharacters = DeepCopyCharacterData(characters or {})
end)

AddEventHandler('cnr:applyCharacterData', function(characterData)
    local ped = PlayerPedId()
    ApplyCharacterData(characterData, ped)
end)

-- Character editor result handlers
AddEventHandler('cnr:characterSaveResult', function(success, message)
    if success then
        TriggerEvent('chat:addMessage', { args = {"^2[Character Editor]", message or "Character saved successfully!"} })
    else
        TriggerEvent('chat:addMessage', { args = {"^1[Character Editor]", message or "Failed to save character."} })
    end
end)

AddEventHandler('cnr:characterDeleteResult', function(success, message)
    if success then
        TriggerEvent('chat:addMessage', { args = {"^2[Character Editor]", message or "Character deleted successfully!"} })
    else
        TriggerEvent('chat:addMessage', { args = {"^1[Character Editor]", message or "Failed to delete character."} })
    end
end)

AddEventHandler('cnr:receiveCharacterForRole', function(characterData)
    -- Handle character data received for role selection
    if characterData then
        currentCharacterData = DeepCopyCharacterData(characterData)
        local ped = PlayerPedId()
        ApplyCharacterData(currentCharacterData, ped)
    end
end)

-- Performance test event handlers
AddEventHandler('cnr:performUITest', function()
    -- Perform UI performance test
    local startTime = GetGameTimer()
    
    -- Simulate UI operations
    for i = 1, 100 do
        SendNUIMessage({
            action = 'testPerformance',
            iteration = i
        })
        Wait(1)
    end
    
    local endTime = GetGameTimer()
    local duration = endTime - startTime
    
    TriggerServerEvent('cnr:uiTestResults', {
        domOperations = 100,
        averageRenderTime = duration / 100,
        cacheHitRate = 0,
        totalDuration = duration
    })
end)

AddEventHandler('cnr:getUITestResults', function()
    -- Send UI test results back to server
    TriggerServerEvent('cnr:uiTestResults', {
        fps = GetFrameCount(),
        memory = collectgarbage("count"),
        timestamp = GetGameTimer()
    })
end)

-- Inventory UI event handlers
AddEventHandler('cnr:openInventory', function()
    Log("Received cnr:openInventory event", "info", "CNR_INV_CLIENT")

    if not clientConfigItems or not next(clientConfigItems) then
        TriggerEvent('chat:addMessage', { args = {"^1[Inventory]", "Inventory system is still loading. Please try again in a few seconds."} })
        Log("Inventory open failed: Config.Items not yet available", "warn", "CNR_INV_CLIENT")
        return
    end

    if not isInventoryOpen then
        isInventoryOpen = true
        SendNUIMessage({
            action = 'openInventory',
            inventory = localPlayerInventory
        })
        SetNuiFocus(true, true)
        Log("Inventory UI opened via event", "info", "CNR_INV_CLIENT")
    end
end)

AddEventHandler('cnr:closeInventory', function()
    Log("Received cnr:closeInventory event", "info", "CNR_INV_CLIENT")
    if isInventoryOpen then
        isInventoryOpen = false
        SendNUIMessage({
            action = 'closeInventory'
        })
        
        SetNuiFocus(false, false)
        SetPlayerControl(PlayerId(), true, 0)
        
        Log("Inventory UI closed via event", "info", "CNR_INV_CLIENT")
    end
end)

-- =====================================
--     CONSOLIDATED NUI CALLBACKS
-- =====================================

-- NUI callbacks for inventory system
RegisterNUICallback('getPlayerInventoryForUI', function(data, cb)
    Log("NUI requested inventory via getPlayerInventoryForUI", "info", "CNR_INV_CLIENT")
    local playerInfo = {
        cash = playerData.money or playerCash or 0,
        playerCash = playerData.money or playerCash or 0,
        level = playerData.level or 1,
        playerLevel = playerData.level or 1,
        role = playerData.role or role or "citizen"
    }
    
    if localPlayerInventory and next(localPlayerInventory) then
        local equippedItems = {}
        local playerPed = PlayerPedId()
        
        for itemId, itemData in pairs(localPlayerInventory) do
            if itemData.type == "weapon" and itemData.weaponHash then
                if HasPedGotWeapon(playerPed, itemData.weaponHash, false) then
                    table.insert(equippedItems, itemId)
                    localPlayerEquippedItems[itemId] = true
                else
                    localPlayerEquippedItems[itemId] = false
                end
            end
        end
        
        Log("Returning inventory with " .. tablelength(localPlayerInventory) .. " items and " .. #equippedItems .. " equipped items", "info", "CNR_INV_CLIENT")
        
        cb({
            success = true,
            inventory = localPlayerInventory,
            equippedItems = equippedItems,
            playerInfo = playerInfo
        })
    else
        TriggerServerEvent('cnr:requestMyInventory')
        
        cb({
            success = false,
            error = "Inventory data not available, requesting from server",
            inventory = {},
            equippedItems = {},
            playerInfo = playerInfo
        })
    end
end)

RegisterNUICallback('getPlayerInventory', function(data, cb)
    Log("NUI requested inventory via getPlayerInventory", "info", "CNR_INV_CLIENT")
    
    if localPlayerInventory and next(localPlayerInventory) then
        Log("Returning inventory with " .. tablelength(localPlayerInventory) .. " items for sell tab", "info", "CNR_INV_CLIENT")
        
        cb({
            success = true,
            inventory = localPlayerInventory
        })
    else
        TriggerServerEvent('cnr:requestMyInventory')
        
        cb({
            success = false,
            error = "Inventory data not available, requesting from server",
            inventory = {}
        })
    end
end)

RegisterNUICallback('setNuiFocus', function(data, cb)
    Log("NUI requested SetNuiFocus: " .. tostring(data.hasFocus) .. ", " .. tostring(data.hasCursor), "info", "CNR_INV_CLIENT")

    SetMenuFocus(data.hasFocus or false, data.hasCursor or false)

    if not data.hasFocus then
        adminPanelVisible = false
        activeRoleActionMenu = nil
        ClearAdminPanelRequest()
    end
    
    cb({
        success = true
    })
end)

RegisterNUICallback('closeInventory', function(data, cb)
    Log("NUI requested to close inventory", "info", "CNR_INV_CLIENT")
    
    TriggerEvent('cnr:closeInventory')
    
    cb({
        success = true
    })
end)

RegisterNUICallback('closeAdminPanel', function(data, cb)
    adminPanelVisible = false
    ClearAdminPanelRequest()
    SetNuiFocus(false, false)
    cb({ success = true })
end)

RegisterNUICallback('adminKickPlayer', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    if not targetId or targetId <= 0 then
        cb({ success = false, error = "Invalid player ID." })
        return
    end

    TriggerServerEvent('cnr:adminKickPlayer', targetId)
    cb({ success = true })
end)

RegisterNUICallback('adminBanPlayer', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    local reason = tostring(data and data.reason or "Banned by admin.")
    if not targetId or targetId <= 0 then
        cb({ success = false, error = "Invalid player ID." })
        return
    end

    TriggerServerEvent('cnr:adminBanPlayer', targetId, reason)
    cb({ success = true })
end)

RegisterNUICallback('teleportToPlayerAdminUI', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    if not targetId or targetId <= 0 then
        cb({ success = false, error = "Invalid player ID." })
        return
    end

    TriggerServerEvent('cnr:adminTeleportToPlayer', targetId)
    cb({ success = true })
end)

RegisterNUICallback('adminToggleNoClip', function(data, cb)
    local enabled = SetAdminNoClipState(not adminNoClipEnabled)
    if enabled then
        ShowNotification("~b~Admin no clip enabled.")
    else
        ShowNotification("~g~Admin no clip disabled.")
    end

    cb({ success = true, enabled = enabled })
end)

RegisterNUICallback('adminToggleInvisible', function(data, cb)
    local enabled = SetAdminInvisibleState(not adminInvisibleEnabled)
    if enabled then
        ShowNotification("~b~Admin invisibility enabled.")
    else
        ShowNotification("~g~Admin invisibility disabled.")
    end

    cb({ success = true, enabled = enabled })
end)

RegisterNUICallback('adminSpectatePlayer', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    local success, errorMessage = StartAdminSpectate(targetId)
    cb({ success = success, error = errorMessage })
end)

RegisterNUICallback('adminStopSpectate', function(data, cb)
    local stopped = StopAdminSpectate()
    cb({ success = true, active = not stopped and adminSpectateTargetServerId ~= nil })
end)

RegisterNUICallback('adminAddInventoryItem', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    local itemId = tostring(data and data.itemId or "")
    local quantity = tonumber(data and data.quantity) or 1

    if not targetId or targetId <= 0 or itemId == "" then
        cb({ success = false, error = "Invalid admin inventory request." })
        return
    end

    TriggerServerEvent('cnr:adminAddInventoryItem', targetId, itemId, quantity)
    cb({ success = true })
end)

RegisterNUICallback('adminRemoveInventoryItem', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    local itemId = tostring(data and data.itemId or "")
    local quantity = tonumber(data and data.quantity) or 1

    if not targetId or targetId <= 0 or itemId == "" then
        cb({ success = false, error = "Invalid admin inventory request." })
        return
    end

    TriggerServerEvent('cnr:adminRemoveInventoryItem', targetId, itemId, quantity)
    cb({ success = true })
end)

local function SpawnRequestedRoleVehicle(requestedRole)
    local normalizedRole = requestedRole == "civilian" and "citizen" or (requestedRole or role or playerData.role or "citizen")
    local modelName = nil
    local platePrefix = "CNR"

    if normalizedRole == "cop" then
        modelName = (Config.PoliceVehicles and Config.PoliceVehicles[1]) or "police"
        platePrefix = "PD"
    elseif normalizedRole == "robber" then
        modelName = (Config.RobberVehicleSpawns and Config.RobberVehicleSpawns[1] and Config.RobberVehicleSpawns[1].model)
            or (Config.CivilianVehicles and Config.CivilianVehicles[1])
            or "sultan"
        platePrefix = "RB"
    else
        modelName = (Config.CivilianVehicles and Config.CivilianVehicles[1]) or "blista"
        platePrefix = "CV"
    end

    local playerPed = PlayerPedId()
    local spawnCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 6.0, 0.0)
    local spawnHeading = GetEntityHeading(playerPed)
    local vehicleSpawn = {
        location = vector4(spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnHeading),
        model = modelName
    }

    return CreatePersistentRoleVehicle(vehicleSpawn, modelName, platePrefix)
end

local function RemoveTrackedSpikeStrip(spikeStrip)
    for i = #currentSpikeStrips, 1, -1 do
        if currentSpikeStrips[i] == spikeStrip or not DoesEntityExist(currentSpikeStrips[i]) then
            table.remove(currentSpikeStrips, i)
        end
    end
end

local function CollectActiveSpikeStrips()
    local strips = {}
    local seen = {}

    for i = #currentSpikeStrips, 1, -1 do
        local spikeStrip = currentSpikeStrips[i]
        if spikeStrip and DoesEntityExist(spikeStrip) then
            local key = tostring(NetworkGetEntityIsNetworked(spikeStrip) and NetworkGetNetworkIdFromEntity(spikeStrip) or spikeStrip)
            if not seen[key] then
                seen[key] = true
                strips[#strips + 1] = spikeStrip
            end
        else
            table.remove(currentSpikeStrips, i)
        end
    end

    if type(GetGamePool) == "function" then
        for _, object in ipairs(GetGamePool('CObject') or {}) do
            if object and object ~= 0 and DoesEntityExist(object) and GetEntityModel(object) == spikeStripModelHash then
                local key = tostring(NetworkGetEntityIsNetworked(object) and NetworkGetNetworkIdFromEntity(object) or object)
                if not seen[key] then
                    seen[key] = true
                    strips[#strips + 1] = object
                end
            end
        end
    end

    return strips
end

local function DeleteTrackedSpikeStrip(spikeStrip)
    if not spikeStrip or spikeStrip == 0 or not DoesEntityExist(spikeStrip) then
        RemoveTrackedSpikeStrip(spikeStrip)
        return true
    end

    if NetworkGetEntityIsNetworked(spikeStrip) and not NetworkHasControlOfEntity(spikeStrip) then
        NetworkRequestControlOfEntity(spikeStrip)
        local attempts = 0
        while not NetworkHasControlOfEntity(spikeStrip) and attempts < 20 do
            Citizen.Wait(25)
            NetworkRequestControlOfEntity(spikeStrip)
            attempts = attempts + 1
        end
    end

    if DoesEntityExist(spikeStrip) then
        SetEntityAsMissionEntity(spikeStrip, true, true)
        DeleteObject(spikeStrip)
        if DoesEntityExist(spikeStrip) then
            DeleteEntity(spikeStrip)
        end
    end

    RemoveTrackedSpikeStrip(spikeStrip)
    return not DoesEntityExist(spikeStrip)
end

local function ApplyInventoryUseEffect(itemId)
    local playerPed = PlayerPedId()

    if itemId == "armor" then
        SetPedArmour(playerPed, 100)
        return { success = true, consumed = true }
    end

    if itemId == "heavy_armor" then
        SetPedArmour(playerPed, 100)
        SetEntityHealth(playerPed, math.min(GetEntityMaxHealth(playerPed), GetEntityHealth(playerPed) + 25))
        return { success = true, consumed = true }
    end

    if itemId == "medkit" then
        SetEntityHealth(playerPed, GetEntityMaxHealth(playerPed))
        return { success = true, consumed = true }
    end

    if itemId == "firstaidkit" then
        SetEntityHealth(playerPed, math.min(GetEntityMaxHealth(playerPed), GetEntityHealth(playerPed) + 50))
        return { success = true, consumed = true }
    end

    if itemId == "spikestrip_item" then
        local maxSpikeStrips = (Config.MaxDeployedSpikeStrips or 3) + (playerData.extraSpikeStrips or 0)
        for i = #currentSpikeStrips, 1, -1 do
            if not DoesEntityExist(currentSpikeStrips[i]) then
                table.remove(currentSpikeStrips, i)
            end
        end

        if #currentSpikeStrips >= maxSpikeStrips then
            return { success = false, error = "Maximum deployed spike strips reached." }
        end

        RequestModel(spikeStripModelHash)
        while not HasModelLoaded(spikeStripModelHash) do
            Citizen.Wait(50)
        end

        local deployCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 3.5, -1.0)
        local spikeStrip = CreateObject(spikeStripModelHash, deployCoords.x, deployCoords.y, deployCoords.z, true, true, false)
        if spikeStrip and DoesEntityExist(spikeStrip) then
            SetEntityHeading(spikeStrip, GetEntityHeading(playerPed))
            FreezeEntityPosition(spikeStrip, true)
            PlaceObjectOnGroundProperly(spikeStrip)
            table.insert(currentSpikeStrips, spikeStrip)
            ShowNotification("~g~Spike strip deployed.")

            SetTimeout(Config.SpikeStripDuration or 120000, function()
                if DoesEntityExist(spikeStrip) then
                    DeleteTrackedSpikeStrip(spikeStrip)
                else
                    RemoveTrackedSpikeStrip(spikeStrip)
                end
            end)

            return { success = true, consumed = true }
        end

        return { success = false, error = "Unable to deploy spike strip." }
    end

    return { success = false, error = "This item cannot be used directly." }
end

local function GetLocalInventoryItemCount(itemId)
    local itemData = localPlayerInventory and localPlayerInventory[itemId]
    if type(itemData) == "table" then
        return tonumber(itemData.count or itemData.quantity or 0) or 0
    end

    return tonumber(itemData) or 0
end

local function PushLocalInventoryToNui()
    SendNUIMessage({
        action = 'updateInventory',
        inventory = localPlayerInventory
    })

    SendNUIMessage({
        action = 'refreshSellListIfNeeded'
    })
end

local function ApplyLocalInventoryDelta(itemId, delta)
    if not localPlayerInventory or not localPlayerInventory[itemId] then
        return
    end

    local itemData = localPlayerInventory[itemId]
    if type(itemData) == "table" then
        local newCount = math.max(0, (tonumber(itemData.count or itemData.quantity or 0) or 0) + delta)
        itemData.count = newCount
        itemData.quantity = nil

        if newCount <= 0 then
            localPlayerInventory[itemId] = nil
        end
    else
        local newCount = math.max(0, (tonumber(itemData) or 0) + delta)
        if newCount <= 0 then
            localPlayerInventory[itemId] = nil
        else
            localPlayerInventory[itemId] = newCount
        end
    end

    PushLocalInventoryToNui()
end

local function UseLocalInventoryItem(itemId)
    if GetLocalInventoryItemCount(itemId) <= 0 then
        return false, "Item not found in inventory."
    end

    local result = ApplyInventoryUseEffect(itemId)
    if not result.success then
        return false, result.error or "Unable to use item."
    end

    if result.consumed then
        ApplyLocalInventoryDelta(itemId, -1)
        TriggerServerEvent('cnr:useInventoryItem', itemId)
    end

    return true
end

RegisterCommand('+cnr_deployspikestrip', function()
    if role ~= "cop" then
        ShowNotification("~r~Only cops can deploy spike strips.")
        return
    end

    local success, errorMessage = UseLocalInventoryItem("spikestrip_item")
    if not success then
        ShowNotification("~r~" .. (errorMessage or "You need a spike strip."))
    end
end, false)

RegisterCommand('-cnr_deployspikestrip', function() end, false)
RegisterKeyMapping('+cnr_deployspikestrip', 'Deploy Spike Strip', 'keyboard', 'G')

Citizen.CreateThread(function()
    local recentlySpikedVehicles = {}
    local wheelBoneToTyreIndex = {
        wheel_lf = 0,
        wheel_rf = 1,
        wheel_lm1 = 2,
        wheel_rm1 = 3,
        wheel_lm2 = 4,
        wheel_rm2 = 5,
        wheel_lm3 = 4,
        wheel_rm3 = 5,
        wheel_lr = 4,
        wheel_rr = 5,
        wheel_bf = 0,
        wheel_br = 4
    }

    local function getVehiclesToCheck()
        if type(GetGamePool) == "function" then
            return GetGamePool('CVehicle') or {}
        end

        local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if playerVehicle and playerVehicle ~= 0 then
            return { playerVehicle }
        end

        return {}
    end

    local function burstVehicleTyres(vehicle, tyreIndices)
        if not NetworkHasControlOfEntity(vehicle) then
            NetworkRequestControlOfEntity(vehicle)
        end

        for _, tyreIndex in ipairs(tyreIndices) do
            SetVehicleTyreBurst(vehicle, tyreIndex, true, 1000.0)
        end
    end

    local function getVehicleTrackingKey(vehicle)
        if NetworkGetEntityIsNetworked(vehicle) then
            local netId = NetworkGetNetworkIdFromEntity(vehicle)
            if netId and netId ~= 0 then
                return ("net:%s"):format(netId)
            end
        end

        return ("ent:%s"):format(vehicle)
    end

    local function getSpikeStripHitTyres(vehicle, spikeStrip)
        local minDim, maxDim = GetModelDimensions(GetEntityModel(spikeStrip))
        local paddingX = 0.45
        local paddingY = 0.75
        local paddingZ = 0.65
        local tyreIndices = {}
        local seenTyres = {}

        for boneName, tyreIndex in pairs(wheelBoneToTyreIndex) do
            local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
            if boneIndex and boneIndex ~= -1 then
                local wheelCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
                local localCoords = GetOffsetFromEntityGivenWorldCoords(spikeStrip, wheelCoords.x, wheelCoords.y, wheelCoords.z)
                local withinX = localCoords.x >= (minDim.x - paddingX) and localCoords.x <= (maxDim.x + paddingX)
                local withinY = localCoords.y >= (minDim.y - paddingY) and localCoords.y <= (maxDim.y + paddingY)
                local withinZ = localCoords.z >= (minDim.z - paddingZ) and localCoords.z <= (maxDim.z + paddingZ)

                if withinX and withinY and withinZ and not seenTyres[tyreIndex] then
                    seenTyres[tyreIndex] = true
                    tyreIndices[#tyreIndices + 1] = tyreIndex
                end
            end
        end

        return tyreIndices
    end

    while true do
        Citizen.Wait(150)

        local spikeStrips = CollectActiveSpikeStrips()
        if #spikeStrips > 0 then
            local vehicles = getVehiclesToCheck()

            for _, spikeStrip in ipairs(spikeStrips) do
                if DoesEntityExist(spikeStrip) then
                    for _, vehicle in ipairs(vehicles) do
                        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                            local vehicleKey = getVehicleTrackingKey(vehicle)

                            if (recentlySpikedVehicles[vehicleKey] or 0) < GetGameTimer() then
                                local hitTyres = getSpikeStripHitTyres(vehicle, spikeStrip)
                                if #hitTyres > 0 then
                                    burstVehicleTyres(vehicle, hitTyres)
                                    recentlySpikedVehicles[vehicleKey] = GetGameTimer() + 1500
                                end
                            end
                        end
                    end
                end
            end
        else
            Citizen.Wait(600)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local waitTime = 400

        if role == "cop" and playerPed and playerPed ~= 0 and DoesEntityExist(playerPed) then
            local playerCoords = GetEntityCoords(playerPed)
            local nearestSpikeStrip = nil
            local nearestDistance = 2.25

            for _, spikeStrip in ipairs(CollectActiveSpikeStrips()) do
                if DoesEntityExist(spikeStrip) then
                    local stripCoords = GetEntityCoords(spikeStrip)
                    local distance = #(playerCoords - stripCoords)
                    if distance < nearestDistance then
                        nearestDistance = distance
                        nearestSpikeStrip = spikeStrip
                    end
                end
            end

            if nearestSpikeStrip then
                waitTime = 0
                DisplayHelpText("Press ~INPUT_CONTEXT~ to recover spike strip")
                if IsControlJustPressed(0, 38) then
                    if DeleteTrackedSpikeStrip(nearestSpikeStrip) then
                        TriggerServerEvent('cnr:recoverSpikeStrip')
                    else
                        ShowNotification("~r~Unable to recover spike strip right now.")
                    end
                    Citizen.Wait(250)
                end
            end
        end

        Citizen.Wait(waitTime)
    end
end)

RegisterNUICallback('equipInventoryItem', function(data, cb)
    local itemId = tostring(data and data.itemId or "")
    local equip = not (data and data.equip == false)
    local itemData = localPlayerInventory[itemId]

    if itemId == "" or not itemData then
        cb({ success = false, error = "Item not found." })
        return
    end

    local playerPed = PlayerPedId()
    local isWeaponItem = itemData.category == "Weapons"
        or itemData.category == "Melee Weapons"
        or (itemData.category == "Utility" and string.find(itemId, "weapon_") ~= nil)

    if itemData.category == "Armor" then
        if equip then
            SetPedArmour(playerPed, 100)
            localPlayerEquippedItems[itemId] = true
        else
            SetPedArmour(playerPed, 0)
            localPlayerEquippedItems[itemId] = false
        end

        cb({ success = true })
        return
    end

    if isWeaponItem then
        local weaponHash = GetHashKey(itemId)
        local ammoCount = (Config.DefaultWeaponAmmo and Config.DefaultWeaponAmmo[itemId]) or 250

        if equip then
            GiveWeaponToPed(playerPed, weaponHash, ammoCount, false, true)
            SetPedAmmo(playerPed, weaponHash, ammoCount)
            localPlayerEquippedItems[itemId] = true
        else
            RemoveWeaponFromPed(playerPed, weaponHash)
            localPlayerEquippedItems[itemId] = false
        end

        cb({ success = true })
        return
    end

    localPlayerEquippedItems[itemId] = equip
    cb({ success = true })
end)

RegisterNUICallback('useInventoryItem', function(data, cb)
    local itemId = tostring(data and data.itemId or "")
    local itemData = localPlayerInventory[itemId]

    if itemId == "" or not itemData then
        cb({ success = false, error = "Item not found." })
        return
    end

    local success, errorMessage = UseLocalInventoryItem(itemId)
    if not success then
        cb({ success = false, error = errorMessage })
        return
    end

    cb({
        success = true,
        consumed = true
    })
end)

RegisterNUICallback('dropInventoryItem', function(data, cb)
    local itemId = tostring(data and data.itemId or "")
    local quantity = math.max(1, tonumber(data and data.quantity) or 1)

    if itemId == "" or not localPlayerInventory[itemId] then
        cb({ success = false, error = "Item not found." })
        return
    end

    if localPlayerEquippedItems[itemId] then
        local weaponHash = GetHashKey(itemId)
        if weaponHash ~= 0 then
            RemoveWeaponFromPed(PlayerPedId(), weaponHash)
        end
        localPlayerEquippedItems[itemId] = false
    end

    TriggerServerEvent('cnr:dropInventoryItem', itemId, quantity)
    cb({ success = true })
end)

RegisterNUICallback('callRoleVehicle', function(data, cb)
    local vehicle = SpawnRequestedRoleVehicle(data and data.role)
    if vehicle and DoesEntityExist(vehicle) then
        cb({ success = true })
    else
        cb({ success = false, error = "Unable to spawn a vehicle nearby." })
    end
end)

RegisterNUICallback('requestPoliceAssistance', function(data, cb)
    TriggerServerEvent('cnr:requestPoliceAssistance', data and data.urgent == true)
    cb({ success = true })
end)

RegisterNUICallback('lookupRobberInfo', function(data, cb)
    local targetId = tonumber(data and data.targetId)
    if not targetId or targetId <= 0 then
        cb({ success = false, error = "Enter a valid player ID." })
        return
    end

    local requestId = ("lookup_%s_%s"):format(GetGameTimer(), math.random(1000, 9999))
    pendingPoliceLookupCallbacks[requestId] = cb
    TriggerServerEvent('cnr:lookupRobberInfo', targetId, requestId)
end)

RegisterNUICallback('requestPoliceCadData', function(data, cb)
    local requestId = ("cad_%s_%s"):format(GetGameTimer(), math.random(1000, 9999))
    pendingPoliceCadCallbacks[requestId] = cb
    TriggerServerEvent('cnr:requestPoliceCadData', requestId)
end)

RegisterNUICallback('requestAdminLiveMapData', function(data, cb)
    local requestId = ("adminmap_%s_%s"):format(GetGameTimer(), math.random(1000, 9999))
    pendingAdminLiveMapCallbacks[requestId] = cb
    TriggerServerEvent('cnr:requestAdminLiveMapData', requestId)
end)

RegisterNUICallback('createCadCall', function(data, cb)
    TriggerServerEvent(
        'cnr:createCadCall',
        tostring(data and data.title or ""),
        tostring(data and data.details or ""),
        tostring(data and data.priority or "Medium"),
        data and data.requestBackup == true,
        data and data.urgent == true
    )
    cb({ success = true })
end)

RegisterNUICallback('updateCadCallStatus', function(data, cb)
    TriggerServerEvent(
        'cnr:updateCadCallStatus',
        tonumber(data and data.callId),
        tostring(data and data.status or ""),
        tostring(data and data.details or "")
    )
    cb({ success = true })
end)

RegisterNUICallback('issuePoliceCitation', function(data, cb)
    TriggerServerEvent(
        'cnr:issuePoliceCitation',
        tonumber(data and data.targetId),
        tostring(data and data.citationId or ""),
        tonumber(data and data.amount) or 0
    )
    cb({ success = true })
end)

RegisterNUICallback('sendRoleTextMessage', function(data, cb)
    TriggerServerEvent(
        'cnr:sendRoleTextMessage',
        tonumber(data and data.targetId),
        tostring(data and data.message or "")
    )
    cb({ success = true })
end)

RegisterNUICallback('getRobberStatus', function(data, cb)
    cb({
        success = true,
        wantedLevel = currentWantedPointsClient or 0,
        wantedStars = currentWantedStarsClient or 0,
        isWanted = (currentWantedStarsClient or 0) > 0
    })
end)

RegisterNUICallback('findHideout', function(data, cb)
    TriggerEvent('cnr:findHideout')
    cb({ success = true })
end)

RegisterNUICallback('requestRobberAssistance', function(data, cb)
    TriggerServerEvent('cnr:requestRobberAssistance', data and data.urgent == true)
    cb({ success = true })
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearestDropId = nil
        local nearestDistance = 2.0

        for dropId, drop in pairs(droppedWorldItems) do
            local dropCoords = GetDroppedWorldItemCoords(drop)
            if dropCoords then
                local distance = #(playerCoords - dropCoords)

                if distance <= 20.0 then
                    DrawMarker(20, dropCoords.x, dropCoords.y, dropCoords.z + 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.18, 0.18, 0.18, 80, 220, 120, 180, false, true, 2, false, nil, nil, false)
                end

                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestDropId = dropId
                end
            end
        end

        if nearestDropId then
            local drop = droppedWorldItems[nearestDropId]
            local helpText = string.format("Press ~INPUT_CONTEXT~ to pick up %s", drop.name or "item")
            DisplayHelpText(helpText)
            activeDroppedItemHelpText = helpText

            if IsControlJustPressed(0, 38) then
                TriggerServerEvent('cnr:pickupDroppedWorldItem', nearestDropId)
                Citizen.Wait(250)
            end
        else
            ClearDroppedWorldItemHelpText()
            Citizen.Wait(250)
        end
    end
end)

-- Initialize consolidated client systems
Citizen.CreateThread(function()
    -- Wait for player to be fully spawned
    while not NetworkIsPlayerActive(PlayerId()) do
        Citizen.Wait(500)
    end

    Citizen.Wait(3000)

    local attempts = 0
    local maxAttempts = 10

    while not clientConfigItems and attempts < maxAttempts do
        attempts = attempts + 1
        TriggerServerEvent('cnr:requestConfigItems')
        Log("Requested Config.Items from server (attempt " .. attempts .. "/" .. maxAttempts .. ")", "info", "CNR_INV_CLIENT")

        Citizen.Wait(3000)
    end

    if not clientConfigItems then
        Log("Failed to receive Config.Items from server after " .. maxAttempts .. " attempts", "error", "CNR_INV_CLIENT")
    end
    
    -- Initialize character editor
    TriggerServerEvent('cnr:loadPlayerCharacters')
    UpdateActivityBlips()
    
    Log("Consolidated client systems initialized", "info", "CNR_CLIENT")
end)

-- Export consolidated functions for other scripts
exports('EquipInventoryWeapons', EquipInventoryWeapons)
exports('GetClientConfigItems', GetClientConfigItems)
exports('UpdateFullInventory', UpdateFullInventory)
exports('ToggleInventoryUI', ToggleInventoryUI)
exports('ApplyCharacterData', ApplyCharacterData)
exports('GetDefaultCharacterData', GetDefaultCharacterData)
exports('UpdateXPDisplayElements', UpdateXPDisplayElements)
exports('ShowXPGainAnimation', ShowXPGainAnimation)
exports('PlayLevelUpEffects', PlayLevelUpEffects)
