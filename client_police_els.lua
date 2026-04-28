-- FiveM-native police ELS controller.
-- This reproduces the key ideas of classic ELS for multiplayer police vehicles
-- without relying on single-player ScriptHook/ASI binaries.

local bridge = _G.CNRPoliceElsBridge or {}
local localPoliceElsFallbackState = {}
local policeElsProfileCache = {}
local policeElsAllowedModelNames = nil
local policeElsAllowedModelHashes = nil
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

local function CloneNumericList(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end

    for _, value in ipairs(source) do
        local numericValue = tonumber(value)
        if numericValue and numericValue >= 1 then
            result[#result + 1] = math.floor(numericValue)
        end
    end

    return result
end

local function BuildPoliceElsModelLookups()
    if policeElsAllowedModelNames and policeElsAllowedModelHashes then
        return
    end

    policeElsAllowedModelNames = {}
    policeElsAllowedModelHashes = {}

    local function registerModel(modelName)
        if type(modelName) ~= "string" then
            return
        end

        local normalized = string.lower(modelName)
        if normalized == "" or policeElsAllowedModelNames[normalized] then
            return
        end

        policeElsAllowedModelNames[normalized] = true
        policeElsAllowedModelHashes[GetHashKey(normalized)] = normalized
    end

    for _, modelName in ipairs(Config.PoliceVehicles or {}) do
        registerModel(modelName)
    end

    local elsConfig = GetPoliceElsConfig()
    if elsConfig and type(elsConfig.vehicleProfiles) == "table" then
        for modelName, _ in pairs(elsConfig.vehicleProfiles) do
            registerModel(modelName)
        end
    end
end

local function ResolvePoliceElsModelName(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local trackedData = GetTrackedPdGarageVehicle(vehicle)
    if trackedData and trackedData.model then
        local trackedModel = string.lower(tostring(trackedData.model))
        if trackedModel ~= "" then
            return trackedModel
        end
    end

    BuildPoliceElsModelLookups()
    return policeElsAllowedModelHashes[GetEntityModel(vehicle)]
end

local function GetPoliceElsProfile(vehicle)
    local elsConfig = GetPoliceElsConfig()
    if not elsConfig or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local modelName = ResolvePoliceElsModelName(vehicle)
    if not modelName then
        local isEmergencyFallback = elsConfig.allowEmergencyClassFallback == true and GetVehicleClass(vehicle) == 18
        if not isEmergencyFallback then
            return nil
        end
        modelName = "__emergency_fallback__"
    end

    if policeElsProfileCache[modelName] then
        return policeElsProfileCache[modelName]
    end

    local baseProfile = CloneShallowTable(elsConfig.defaultProfile)
    local override = type(elsConfig.vehicleProfiles) == "table" and elsConfig.vehicleProfiles[modelName] or nil
    if type(override) == "table" then
        for key, value in pairs(override) do
            baseProfile[key] = value
        end
    end

    baseProfile.modelName = modelName
    baseProfile.cruiseExtras = CloneNumericList(baseProfile.cruiseExtras)
    baseProfile.primaryExtras = CloneNumericList(baseProfile.primaryExtras)
    baseProfile.warningExtras = CloneNumericList(baseProfile.warningExtras)
    baseProfile.secondaryExtras = CloneNumericList(baseProfile.secondaryExtras)
    baseProfile.takedownExtras = CloneNumericList(baseProfile.takedownExtras)
    baseProfile.sceneExtras = CloneNumericList(baseProfile.sceneExtras)
    baseProfile.flashIntervals = CloneNumericList(baseProfile.flashIntervals)

    if #baseProfile.flashIntervals <= 0 then
        baseProfile.flashIntervals = { 240, 150, 95 }
    end

    policeElsProfileCache[modelName] = baseProfile
    return baseProfile
end

local function GetPoliceElsStateKey()
    local elsConfig = GetPoliceElsConfig()
    return (elsConfig and tostring(elsConfig.stateBagKey or "cnrEls")) or "cnrEls"
end

local function SanitizePoliceElsState(state)
    local sanitized = {
        stage = 0,
        siren = false,
        warning = true,
        secondary = true,
        takedown = false,
        scene = false,
        pattern = 1
    }

    if type(state) == "table" then
        sanitized.stage = math.max(0, math.min(3, math.floor(tonumber(state.stage) or 0)))
        sanitized.siren = state.siren == true
        sanitized.warning = state.warning ~= false
        sanitized.secondary = state.secondary ~= false
        sanitized.takedown = state.takedown == true
        sanitized.scene = state.scene == true
        sanitized.pattern = math.max(1, math.min(3, math.floor(tonumber(state.pattern) or 1)))
    end

    if sanitized.stage < 3 then
        sanitized.siren = false
    end

    return sanitized
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
        return nil, nil
    end

    local playerPed = PlayerPedId()
    if not playerPed or playerPed == 0 or not IsPedInAnyVehicle(playerPed, false) then
        return nil, nil
    end

    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= playerPed then
        return nil, nil
    end

    local profile = GetPoliceElsProfile(vehicle)
    if not profile then
        return nil, nil
    end

    return vehicle, profile
end

local function SetVehicleExtraSafe(vehicle, extraId, enabled)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    local numericExtra = math.floor(tonumber(extraId) or 0)
    if numericExtra <= 0 or numericExtra > 14 then
        return
    end

    if type(DoesExtraExist) == "function" and not DoesExtraExist(vehicle, numericExtra) then
        return
    end

    SetVehicleExtra(vehicle, numericExtra, enabled and 0 or 1)
end

local function SetVehicleExtraGroupState(vehicle, extras, isEnabled)
    for _, extraId in ipairs(extras or {}) do
        SetVehicleExtraSafe(vehicle, extraId, isEnabled)
    end
end

local function ShouldPoliceElsPatternLight(index, count, pattern, phase)
    if count <= 0 then
        return false
    end

    if pattern == 2 then
        local split = math.max(1, math.ceil(count / 2))
        if (phase % 4) < 2 then
            return index <= split
        end

        return index > split
    end

    if pattern == 3 then
        return phase == 0 or phase == 1
    end

    return ((index + phase) % 2) == 0
end

local function ApplyPoliceElsFlashingGroup(vehicle, extras, pattern, phase, enabled)
    if not enabled then
        SetVehicleExtraGroupState(vehicle, extras, false)
        return
    end

    local count = #extras
    for index, extraId in ipairs(extras) do
        SetVehicleExtraSafe(vehicle, extraId, ShouldPoliceElsPatternLight(index, count, pattern, phase))
    end
end

local function ApplyPoliceElsStateToVehicle(vehicle, profile, state, now)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not profile then
        return
    end

    state = SanitizePoliceElsState(state)

    local interval = profile.flashIntervals[state.pattern] or profile.flashIntervals[#profile.flashIntervals] or 150
    if state.stage >= 3 then
        interval = math.max(75, interval - 25)
    end

    local phase = math.floor((now or GetGameTimer()) / interval) % 4

    ApplyPoliceElsFlashingGroup(vehicle, profile.primaryExtras, state.pattern, phase, state.stage >= 2)
    ApplyPoliceElsFlashingGroup(vehicle, profile.warningExtras, state.pattern, phase + 1, state.stage >= 2 and state.warning)
    ApplyPoliceElsFlashingGroup(
        vehicle,
        profile.secondaryExtras,
        state.pattern,
        phase + 2,
        (state.stage >= 3 and state.secondary) or (state.stage == 2 and state.secondary and profile.allowSecondaryAtStage2 == true)
    )

    SetVehicleExtraGroupState(vehicle, profile.cruiseExtras, state.stage == 1)
    SetVehicleExtraGroupState(vehicle, profile.takedownExtras, state.takedown)
    SetVehicleExtraGroupState(vehicle, profile.sceneExtras, state.scene)

    if profile.useNativeEmergencyLights ~= false then
        SetVehicleSiren(vehicle, state.stage > 0 or state.takedown or state.scene)
        if type(SetVehicleHasMutedSirens) == "function" then
            SetVehicleHasMutedSirens(vehicle, not (state.stage >= 3 and state.siren))
        end
        if type(SetSirenWithNoDriver) == "function" then
            SetSirenWithNoDriver(vehicle, state.stage > 0)
        end
    end

    if type(SetVehicleLights) == "function" then
        SetVehicleLights(vehicle, (state.stage > 0 or state.takedown or state.scene) and 2 or 0)
    end

    if type(SetVehicleInteriorlight) == "function" then
        SetVehicleInteriorlight(vehicle, state.scene)
    end
end

local function FormatPoliceElsStageLabel(stage)
    if stage == 1 then
        return "Cruise"
    elseif stage == 2 then
        return "Code 2"
    elseif stage == 3 then
        return "Code 3"
    end

    return "Off"
end

local function UpdateLocalPoliceElsState(mutator, notificationText)
    local vehicle, profile = GetLocalPoliceElsVehicle()
    if not vehicle then
        return false
    end

    local nextState = CloneShallowTable(GetPoliceElsState(vehicle))
    mutator(nextState, profile)
    nextState = SetPoliceElsState(vehicle, nextState)
    if nextState and notificationText then
        Notify("~b~ELS~s~ " .. notificationText(nextState, profile))
    end

    return nextState ~= nil
end

local function ShowPoliceElsEntryHint()
    local elsConfig = GetPoliceElsConfig()
    if not elsConfig or elsConfig.showEntryHint == false then
        return
    end

    local vehicle = select(1, GetLocalPoliceElsVehicle())
    if vehicle and vehicle ~= lastPoliceElsHintVehicle then
        lastPoliceElsHintVehicle = vehicle
        Notify("~b~ELS ready~s~ J stage | L siren | O warning | P secondary | U pattern | ] takedown | N scene")
    elseif not vehicle then
        lastPoliceElsHintVehicle = 0
    end
end

Citizen.CreateThread(function()
    while true do
        local waitTime = 250
        local elsConfig = GetPoliceElsConfig()

        if elsConfig and type(GetGamePool) == "function" then
            local now = GetGameTimer()
            local localVehicle = select(1, GetLocalPoliceElsVehicle())

            for _, vehicle in ipairs(GetGamePool('CVehicle') or {}) do
                if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                    local rawState = GetRawPoliceElsState(vehicle)
                    if rawState or vehicle == localVehicle then
                        local profile = GetPoliceElsProfile(vehicle)
                        if profile then
                            waitTime = 75
                            ApplyPoliceElsStateToVehicle(vehicle, profile, rawState or GetPoliceElsState(vehicle), now)
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
        state.stage = (state.stage + 1) % 4
        if state.stage < 3 then
            state.siren = false
        end
    end, function(state)
        return ("Stage %s"):format(FormatPoliceElsStageLabel(state.stage))
    end)
end, false)
RegisterCommand('-cnr_els_stagecycle', function() end, false)
RegisterKeyMapping(
    '+cnr_els_stagecycle',
    'Police ELS - Cycle lighting stage',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.stageCycleKey) or 'J'
)

RegisterCommand('+cnr_els_siren', function()
    UpdateLocalPoliceElsState(function(state)
        if state.stage < 3 then
            state.stage = 3
        end
        state.siren = not state.siren
    end, function(state)
        return state.siren and "Siren enabled" or "Siren muted"
    end)
end, false)
RegisterCommand('-cnr_els_siren', function() end, false)
RegisterKeyMapping(
    '+cnr_els_siren',
    'Police ELS - Toggle main siren',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.sirenToggleKey) or 'L'
)

RegisterCommand('+cnr_els_warning', function()
    UpdateLocalPoliceElsState(function(state)
        if state.stage < 2 then
            state.stage = 2
        end
        state.warning = not state.warning
    end, function(state)
        return state.warning and "Warning lights enabled" or "Warning lights disabled"
    end)
end, false)
RegisterCommand('-cnr_els_warning', function() end, false)
RegisterKeyMapping(
    '+cnr_els_warning',
    'Police ELS - Toggle warning group',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.warningToggleKey) or 'O'
)

RegisterCommand('+cnr_els_secondary', function()
    UpdateLocalPoliceElsState(function(state)
        if state.stage < 3 then
            state.stage = 3
        end
        state.secondary = not state.secondary
    end, function(state)
        return state.secondary and "Secondary lights enabled" or "Secondary lights disabled"
    end)
end, false)
RegisterCommand('-cnr_els_secondary', function() end, false)
RegisterKeyMapping(
    '+cnr_els_secondary',
    'Police ELS - Toggle secondary group',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.secondaryToggleKey) or 'P'
)

RegisterCommand('+cnr_els_pattern', function()
    UpdateLocalPoliceElsState(function(state)
        state.pattern = (state.pattern % 3) + 1
    end, function(state)
        return ("Flash pattern %d"):format(state.pattern)
    end)
end, false)
RegisterCommand('-cnr_els_pattern', function() end, false)
RegisterKeyMapping(
    '+cnr_els_pattern',
    'Police ELS - Cycle flash pattern',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.patternCycleKey) or 'U'
)

RegisterCommand('+cnr_els_takedown', function()
    UpdateLocalPoliceElsState(function(state)
        state.takedown = not state.takedown
    end, function(state)
        return state.takedown and "Takedowns enabled" or "Takedowns disabled"
    end)
end, false)
RegisterCommand('-cnr_els_takedown', function() end, false)
RegisterKeyMapping(
    '+cnr_els_takedown',
    'Police ELS - Toggle takedowns',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.takedownToggleKey) or 'RBRACKET'
)

RegisterCommand('+cnr_els_scene', function()
    UpdateLocalPoliceElsState(function(state)
        state.scene = not state.scene
    end, function(state)
        return state.scene and "Scene lights enabled" or "Scene lights disabled"
    end)
end, false)
RegisterCommand('-cnr_els_scene', function() end, false)
RegisterKeyMapping(
    '+cnr_els_scene',
    'Police ELS - Toggle scene lights',
    'keyboard',
    (Config.PoliceELS and Config.PoliceELS.keybinds and Config.PoliceELS.keybinds.sceneToggleKey) or 'N'
)
