-- Simple FiveM-native police emergency lighting controller.
-- This resource only targets stock police vehicles and keeps controls to
-- a synced light toggle plus a synced siren toggle.

local bridge = _G.CNRPoliceElsBridge or {}
local localPoliceElsFallbackState = {}
local policeElsAllowedModelNames = nil
local policeElsAllowedModelHashes = nil
local policeElsRuntimeState = {}
local lastPoliceElsHintVehicle = 0

local function Notify(message)
    local notifier = bridge.notify
    if type(notifier) == "function" then
        notifier(message)
    end
end

local function CanUsePoliceEls()
    local canUse = bridge.canUse
    return type(canUse) == "function" and canUse() or false
end

local function IsElsInputBlocked()
    local isBlocked = bridge.isInputBlocked
    return type(isBlocked) == "function" and isBlocked() or false
end

local function GetTrackedPdGarageVehicle(vehicle)
    local resolver = bridge.getTrackedPdGarageVehicle
    if type(resolver) ~= "function" then
        return nil
    end

    return resolver(vehicle)
end

local function GetPoliceElsConfig()
    if type(Config) ~= "table" or type(Config.PoliceELS) ~= "table" or Config.PoliceELS.enabled == false then
        return nil
    end

    return Config.PoliceELS
end

local function CloneShallowTable(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

local function BuildPoliceElsModelLookups()
    if policeElsAllowedModelNames and policeElsAllowedModelHashes then
        return
    end

    policeElsAllowedModelNames = {}
    policeElsAllowedModelHashes = {}

    for _, modelName in ipairs(Config.PoliceVehicles or {}) do
        if type(modelName) == "string" then
            local normalized = string.lower(modelName)
            if normalized ~= "" and not policeElsAllowedModelNames[normalized] then
                policeElsAllowedModelNames[normalized] = true
                policeElsAllowedModelHashes[GetHashKey(normalized)] = normalized
            end
        end
    end
end

local function SupportsPoliceEls(vehicle)
    local elsConfig = GetPoliceElsConfig()
    if not elsConfig or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local trackedData = GetTrackedPdGarageVehicle(vehicle)
    if trackedData and trackedData.model then
        local trackedModel = string.lower(tostring(trackedData.model))
        if trackedModel ~= "" then
            BuildPoliceElsModelLookups()
            return policeElsAllowedModelNames[trackedModel] == true
        end
    end

    BuildPoliceElsModelLookups()
    if policeElsAllowedModelHashes[GetEntityModel(vehicle)] then
        return true
    end

    return elsConfig.allowEmergencyClassFallback == true and GetVehicleClass(vehicle) == 18
end

local function GetPoliceElsStateKey()
    local elsConfig = GetPoliceElsConfig()
    return (elsConfig and tostring(elsConfig.stateBagKey or "cnrEls")) or "cnrEls"
end

local function SanitizePoliceElsState(state)
    local sanitized = {
        stage = 0,
        siren = false
    }

    if type(state) == "table" then
        sanitized.stage = (tonumber(state.stage) or 0) > 0 and 1 or 0
        sanitized.siren = state.siren == true
    end

    if sanitized.stage == 0 then
        sanitized.siren = false
    end

    return sanitized
end

local function ArePoliceElsStatesEqual(left, right)
    left = SanitizePoliceElsState(left)
    right = SanitizePoliceElsState(right)

    return left.stage == right.stage and left.siren == right.siren
end

local function GetRawPoliceElsState(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local fallbackState = localPoliceElsFallbackState[vehicle]
    if fallbackState then
        return fallbackState
    end

    if type(Entity) ~= "function" or not NetworkGetEntityIsNetworked(vehicle) then
        return nil
    end

    local entityWrapper = Entity(vehicle)
    local entityState = entityWrapper and entityWrapper.state or nil
    if not entityState then
        return nil
    end

    return entityState[GetPoliceElsStateKey()]
end

local function GetPoliceElsState(vehicle)
    return SanitizePoliceElsState(GetRawPoliceElsState(vehicle))
end

local function SetPoliceElsState(vehicle, state)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local sanitized = SanitizePoliceElsState(state)
    localPoliceElsFallbackState[vehicle] = sanitized

    if type(Entity) == "function" and NetworkGetEntityIsNetworked(vehicle) then
        local entityWrapper = Entity(vehicle)
        local entityState = entityWrapper and entityWrapper.state or nil
        if entityState then
            entityState:set(GetPoliceElsStateKey(), sanitized, true)
        end
    end

    return sanitized
end

local function GetLocalPoliceElsVehicle()
    if not CanUsePoliceEls() or IsElsInputBlocked() then
        return nil
    end

    local playerPed = PlayerPedId()
    if not playerPed or playerPed == 0 or not IsPedInAnyVehicle(playerPed, false) then
        return nil
    end

    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= playerPed then
        return nil
    end

    if not SupportsPoliceEls(vehicle) then
        return nil
    end

    return vehicle
end

local function SetVehicleIndicatorState(vehicle, leftEnabled, rightEnabled)
    if type(SetVehicleIndicatorLights) ~= "function" then
        return
    end

    SetVehicleIndicatorLights(vehicle, 0, rightEnabled == true)
    SetVehicleIndicatorLights(vehicle, 1, leftEnabled == true)
end

local function GetPoliceElsRuntime(vehicle)
    local runtime = policeElsRuntimeState[vehicle]
    if runtime then
        return runtime
    end

    runtime = {
        initialized = false,
        stage = -1,
        siren = false
    }
    policeElsRuntimeState[vehicle] = runtime
    return runtime
end

local function ApplyPoliceElsStateToVehicle(vehicle, state)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    state = SanitizePoliceElsState(state)
    local emergencyLightsActive = state.stage > 0
    local sirenAudible = emergencyLightsActive and state.siren
    local runtime = GetPoliceElsRuntime(vehicle)

    if runtime.initialized and runtime.stage == state.stage and runtime.siren == state.siren then
        return
    end

    SetVehicleSiren(vehicle, emergencyLightsActive)

    if type(SetVehicleHasMutedSirens) == "function" then
        SetVehicleHasMutedSirens(vehicle, emergencyLightsActive and not sirenAudible or false)
    end

    if type(SetSirenWithNoDriver) == "function" then
        SetSirenWithNoDriver(vehicle, emergencyLightsActive)
    end

    if type(SetVehicleInteriorlight) == "function" then
        SetVehicleInteriorlight(vehicle, false)
    end

    if type(SetVehicleFullbeam) == "function" then
        SetVehicleFullbeam(vehicle, false)
    end

    SetVehicleIndicatorState(vehicle, false, false)

    runtime.initialized = true
    runtime.stage = state.stage
    runtime.siren = state.siren
end

local function UpdateLocalPoliceElsState(mutator, notificationText)
    local vehicle = GetLocalPoliceElsVehicle()
    if not vehicle then
        return false
    end

    local currentState = GetPoliceElsState(vehicle)
    local nextState = CloneShallowTable(currentState)
    mutator(nextState)

    if ArePoliceElsStatesEqual(currentState, nextState) then
        return false
    end

    nextState = SetPoliceElsState(vehicle, nextState)
    if nextState and notificationText then
        Notify("~b~ELS~s~ " .. notificationText(nextState))
    end

    return nextState ~= nil
end

local function ShowPoliceElsEntryHint()
    local elsConfig = GetPoliceElsConfig()
    if not elsConfig or elsConfig.showEntryHint == false then
        return
    end

    local vehicle = GetLocalPoliceElsVehicle()
    if vehicle and vehicle ~= lastPoliceElsHintVehicle then
        lastPoliceElsHintVehicle = vehicle
        Notify("~b~ELS ready~s~ J lights | L siren")
    elseif not vehicle then
        lastPoliceElsHintVehicle = 0
    end
end

Citizen.CreateThread(function()
    while true do
        local waitTime = 250
        local elsConfig = GetPoliceElsConfig()

        if elsConfig and type(GetGamePool) == "function" then
            local localVehicle = GetLocalPoliceElsVehicle()

            for _, vehicle in ipairs(GetGamePool('CVehicle') or {}) do
                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    local rawState = GetRawPoliceElsState(vehicle)
                    if rawState or vehicle == localVehicle then
                        if SupportsPoliceEls(vehicle) then
                            waitTime = 75
                            ApplyPoliceElsStateToVehicle(vehicle, rawState or GetPoliceElsState(vehicle))
                        end
                    end
                end
            end

            ShowPoliceElsEntryHint()
        end

        Citizen.Wait(waitTime)
    end
end)

RegisterCommand('+cnr_els_stagecycle', function()
    UpdateLocalPoliceElsState(function(state)
        if state.stage > 0 then
            state.stage = 0
            state.siren = false
        else
            state.stage = 1
        end
    end, function(state)
        return state.stage > 0 and "Emergency lights enabled" or "Emergency lights disabled"
    end)
end, false)
RegisterCommand('-cnr_els_stagecycle', function() end, false)
RegisterKeyMapping(
    '+cnr_els_stagecycle',
    'Police lights - Toggle emergency lights',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.lightsToggleKey)
        or (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.stageCycleKey)
        or 'J'
)

RegisterCommand('+cnr_els_siren', function()
    UpdateLocalPoliceElsState(function(state)
        if state.stage <= 0 then
            state.stage = 1
        end

        state.siren = not state.siren
    end, function(state)
        return state.siren and "Siren enabled" or "Siren muted"
    end)
end, false)
RegisterCommand('-cnr_els_siren', function() end, false)
RegisterKeyMapping(
    '+cnr_els_siren',
    'Police lights - Toggle siren',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.sirenToggleKey) or 'L'
)
