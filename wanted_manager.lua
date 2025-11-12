-- wanted_manager.lua
-- This module manages all aspects of the wanted system, including wanted levels, crimes,
-- decay, and police notifications. It is the single source of truth for a player's wanted status.

WantedManager = {}

local wantedPlayers = {} -- In-memory cache for wanted data of online players. [Key: playerId, Value: wantedData table]

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized WantedManager prefix.
---@param playerId number | string The source player ID for the log entry. Can be "System".
---@param operation string A short descriptor of the operation (e.g., "update_level", "decay").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogWantedManager(playerId, operation, message, level)
    level = level or "info"
    Log(string.format("[WantedManager] P:%s | Op:%s | %s", playerId, operation, message), level, "CNR_SERVER")
end

--- Retrieves or creates the wanted data for a player.
---@param playerId number The ID of the player.
---@return table The player's wanted data table.
local function GetWantedData(playerId)
    if not wantedPlayers[playerId] then
        wantedPlayers[playerId] = {
            wantedLevel = 0, -- Numerical wanted points
            stars = 0,       -- Calculated stars (0-5)
            lastCrimeTime = 0,
            crimesCommitted = {}
        }
    end
    return wantedPlayers[playerId]
end

--- Calculates the number of wanted stars based on the numerical wanted level.
---@param wantedLevel number The numerical wanted level points.
---@return number The number of stars (integer from 0 to 5).
local function CalculateStars(wantedLevel)
    local stars = 0
    -- The levels are checked in reverse to find the highest bracket the player falls into.
    for i = #Config.WantedSettings.levels, 1, -1 do
        if wantedLevel >= Config.WantedSettings.levels[i].threshold then
            stars = Config.WantedSettings.levels[i].stars
            break
        end
    end
    return stars
end

--- Alerts all online police officers about a wanted player's activity.
---@param criminalId number The ID of the wanted player.
---@param crimeDescription string A description of the crime committed.
function WantedManager.AlertPolice(criminalId, crimeDescription)
    local criminalData = PlayerManager.GetPlayerData(criminalId)
    local wantedData = GetWantedData(criminalId)
    if not criminalData or not wantedData then return end

    local criminalName = criminalData.name or "Unknown Suspect"
    local criminalPed = GetPlayerPed(tostring(criminalId))
    local criminalCoords = criminalPed and GetEntityCoords(criminalPed) or nil

    -- Use a server-wide loop, but PlayerManager checks if they are a cop.
    for _, playerId in ipairs(GetPlayers()) do
        if PlayerManager.GetPlayerRole(playerId) == "cop" then
            local copId = tonumber(playerId)
            SafeTriggerClientEvent('chat:addMessage', copId, { args = {"^1Police Alert", string.format("Suspect %s is now %d-star wanted for %s.", criminalName, wantedData.stars, crimeDescription)} })
            if criminalCoords then
                -- Send blip update to the cop's client
                SafeTriggerClientEvent('cnr:updatePoliceBlip', copId, criminalId, criminalCoords, wantedData.stars, true)
            end
        end
    end
    LogWantedManager(criminalId, "alert_police", string.format("Alert sent to all online cops about %d-star wanted status.", wantedData.stars))
end


-- =============================================================================
--                              CORE WANTED LOGIC
-- =============================================================================

--- Updates a player's wanted level for committing a specific crime.
--- This is the primary entry point for increasing a wanted level.
---@param playerId number The ID of the player who committed the crime.
---@param crimeKey string The key of the crime from `Config.WantedSettings.crimes`.
function WantedManager.UpdateWantedLevel(playerId, crimeKey)
    -- Only robbers can get a wanted level.
    if PlayerManager.GetPlayerRole(playerId) ~= "robber" then
        return
    end

    local crimeConfig = Config.WantedSettings.crimes[crimeKey]
    if not crimeConfig then
        LogWantedManager(playerId, "update_level", "Invalid crime key: " .. crimeKey, "warn")
        return
    end

    local wantedData = GetWantedData(playerId)
    local oldStars = wantedData.stars

    wantedData.wantedLevel = wantedData.wantedLevel + crimeConfig.wantedPoints
    wantedData.lastCrimeTime = os.time()
    wantedData.crimesCommitted[crimeKey] = (wantedData.crimesCommitted[crimeKey] or 0) + 1

    local newStars = CalculateStars(wantedData.wantedLevel)
    wantedData.stars = newStars

    LogWantedManager(playerId, "update_level", string.format("Crime: %s. Points: +%d. New Level: %d. New Stars: %d.", crimeKey, crimeConfig.wantedPoints, wantedData.wantedLevel, newStars))

    WantedManager.SyncWantedLevel(playerId)

    -- If the star level has increased, alert the police.
    if newStars > oldStars then
        WantedManager.AlertPolice(playerId, crimeConfig.description)
    end

    -- Check if a bounty should be placed.
    -- This can be its own manager in the future (BountyManager).
    -- For now, a simple check here is sufficient.
    if newStars >= Config.BountySettings.wantedLevelThreshold then
        -- Placeholder for PlaceBounty(playerId) call
    end
end

--- Reduces a player's wanted level by a specified amount of points.
---@param playerId number The ID of the player.
---@param amount number The number of wanted points to remove.
function WantedManager.ReduceWantedLevel(playerId, amount)
    local wantedData = GetWantedData(playerId)
    if wantedData.wantedLevel == 0 then return end

    wantedData.wantedLevel = math.max(0, wantedData.wantedLevel - amount)
    local newStars = CalculateStars(wantedData.wantedLevel)
    wantedData.stars = newStars

    LogWantedManager(playerId, "reduce_level", string.format("Reduced by %d points. New Level: %d. New Stars: %d.", amount, wantedData.wantedLevel, newStars))
    WantedManager.SyncWantedLevel(playerId)

    if newStars == 0 then
        -- If wanted level is cleared, remove blips from police maps.
        for _, pid in ipairs(GetPlayers()) do
            if PlayerManager.GetPlayerRole(pid) == "cop" then
                SafeTriggerClientEvent('cnr:updatePoliceBlip', tonumber(pid), playerId, nil, 0, false)
            end
        end
    end
end

--- Completely clears a player's wanted level.
---@param playerId number The ID of the player.
---@param reason string A reason for clearing the wanted level, for logging.
function WantedManager.ClearWantedLevel(playerId, reason)
    local wantedData = GetWantedData(playerId)
    if wantedData.wantedLevel == 0 then return end

    wantedData.wantedLevel = 0
    wantedData.stars = 0
    wantedData.crimesCommitted = {}

    LogWantedManager(playerId, "clear_level", "Wanted level cleared. Reason: " .. reason)
    WantedManager.SyncWantedLevel(playerId)

    -- Remove blips from police maps.
    for _, pid in ipairs(GetPlayers()) do
        if PlayerManager.GetPlayerRole(pid) == "cop" then
            SafeTriggerClientEvent('cnr:updatePoliceBlip', tonumber(pid), playerId, nil, 0, false)
        end
    end
end

--- Synchronizes the player's current wanted status with their client.
---@param playerId number The ID of the player.
function WantedManager.SyncWantedLevel(playerId)
    local wantedData = GetWantedData(playerId)
    SafeTriggerClientEvent('cnr:wantedLevelSync', playerId, wantedData)
end

--- Clears wanted data for a player. Called on disconnect.
---@param playerId number The ID of the player to clean up.
function WantedManager.CleanupPlayer(playerId)
    if wantedPlayers[playerId] then
        -- For persistence, wanted levels should be saved with player data.
        -- This cleanup is for the in-memory cache of online players.
        wantedPlayers[playerId] = nil
        LogWantedManager(playerId, "cleanup", "Player wanted data cleaned up.")
    end
end

-- =============================================================================
--                                  WANTED DECAY
-- =============================================================================

--- Periodically decays the wanted level for all applicable online players.
local function DecayWantedLevels()
    local currentTime = os.time()
    local decayRate = Config.WantedSettings.decayRatePoints
    local noCrimeCooldown = Config.WantedSettings.noCrimeCooldownMs / 1000 -- Convert to seconds
    local copSightDistance = Config.WantedSettings.copSightDistance

    for playerId, wantedData in pairs(wantedPlayers) do
        if wantedData.wantedLevel > 0 and PlayerManager.GetPlayerRole(playerId) == "robber" then
            -- Check if enough time has passed since the last crime.
            if (currentTime - wantedData.lastCrimeTime) > noCrimeCooldown then
                -- Check if a cop is nearby.
                local isCopNearby = false
                local robberPed = GetPlayerPed(tostring(playerId))
                if robberPed and robberPed ~= 0 then
                    local robberCoords = GetEntityCoords(robberPed)
                    for _, pid in ipairs(GetPlayers()) do
                        if PlayerManager.GetPlayerRole(pid) == "cop" then
                            local copPed = GetPlayerPed(tostring(pid))
                            if copPed and copPed ~= 0 then
                                local copCoords = GetEntityCoords(copPed)
                                if #(robberCoords - copCoords) < copSightDistance then
                                    isCopNearby = true
                                    break
                                end
                            end
                        end
                    end
                end

                if not isCopNearby then
                    WantedManager.ReduceWantedLevel(playerId, decayRate)
                end
            end
        end
    end
end

-- =============================================================================
--                             INITIALIZATION
-- =============================================================================

-- Timer to process wanted level decay.
-- Optimized timer to process wanted level decay.
-- This uses the PerformanceOptimizer to dynamically adjust the loop's frequency based on server load,
-- ensuring that this background task does not negatively impact core gameplay during peak times.
PerformanceOptimizer.CreateOptimizedLoop(
    DecayWantedLevels,
    Config.WantedSettings.decayIntervalMs or 10000, -- Base interval (e.g., 10 seconds)
    (Config.WantedSettings.decayIntervalMs or 10000) * 3, -- Max interval (e.g., 30 seconds)
    3 -- Medium priority
)

Log("[WantedManager] Module loaded. Wanted decay processor is running.", "info", "CNR_SERVER")
