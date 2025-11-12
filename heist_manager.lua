-- heist_manager.lua
-- This module manages all heist-related activities, from initiation to completion.
-- It ensures that all heist conditions are met and handles rewards and cooldowns.

HeistManager = {}

local activeHeists = {} -- In-memory cache for active heists.

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized HeistManager prefix.
---@param heistType string The type of heist (e.g., "bank", "jewelry").
---@param operation string A short descriptor of the operation (e.g., "initiate", "complete").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogHeistManager(heistType, operation, message, level)
    level = level or "info"
    Log(string.format("[HeistManager] Heist:%s | Op:%s | %s", heistType, operation, message), level, "CNR_SERVER")
end

--- Counts the number of players currently assigned to the "cop" role.
---@return number The total number of online police officers.
function HeistManager.GetOnlinePoliceCount()
    local count = 0
    for _, playerId in ipairs(GetPlayers()) do
        if PlayerManager.GetPlayerRole(tonumber(playerId)) == "cop" then
            count = count + 1
        end
    end
    return count
end


-- =============================================================================
--                              CORE HEIST LOGIC
-- =============================================================================

--- Initiates a heist, checking all necessary conditions first.
---@param playerId number The ID of the player starting the heist.
---@param heistType string The type of heist to initiate.
function HeistManager.InitiateHeist(playerId, heistType)
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then
        SafeTriggerClientEvent('cnr:notification', playerId, "Cannot start heist: Player data not found.", "error")
        return
    end

    if pData.role ~= "robber" then
        SafeTriggerClientEvent('cnr:notification', playerId, "Only robbers can start heists.", "error")
        return
    end

    local heistConfig = Config.Heists[heistType]
    if not heistConfig then
        LogHeistManager(heistType, "initiate", "Invalid heist type specified by player " .. playerId, "warn")
        return
    end

    -- BUG FIX: Check for the required number of police online.
    local requiredPolice = heistConfig.requiredPolice or 2
    local onlinePolice = HeistManager.GetOnlinePoliceCount()
    if onlinePolice < requiredPolice then
        local message = string.format("Cannot start heist: %d police officers required, but only %d are online.", requiredPolice, onlinePolice)
        SafeTriggerClientEvent('cnr:notification', playerId, message, "error")
        LogHeistManager(heistType, "initiate", "Heist start failed for player " .. playerId .. ": " .. message)
        return
    end

    -- Additional checks (cooldowns, etc.) would go here.

    -- Logic to start the heist would follow.
    LogHeistManager(heistType, "initiate", "Heist initiated by player " .. playerId)
    SafeTriggerClientEvent('cnr:notification', playerId, "Heist started!", "success")
    -- ... start timers, alert police, etc.
end

-- =============================================================================
--                                  EVENT HANDLERS
-- =============================================================================

RegisterNetEvent('cnr:initiateHeist')
AddEventHandler('cnr:initiateHeist', function(heistType)
    local src = source
    HeistManager.InitiateHeist(src, heistType)
end)

Log("[HeistManager] Module loaded and initialized.", "info", "CNR_SERVER")
