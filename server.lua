-- server.lua
-- This file is responsible for initializing and coordinating the various manager modules.
-- All core gameplay logic has been refactored into their respective manager scripts.

-- =============================================================================
--                            CORE INITIALIZATION
-- =============================================================================

-- Load and initialize all manager modules in the correct order of dependency.
-- Note: The actual initialization logic is handled within each manager's file.
-- This script simply ensures they are loaded by the FiveM resource system.
-- The execution order is primarily controlled by the fxmanifest.lua file.

Log = require('utils.log_utils') -- Make logger available globally for all server scripts
SafeTriggerClientEvent = require('utils.safe_utils').SafeTriggerClientEvent
SafeGetPlayerName = require('utils.safe_utils').SafeGetPlayerName
UpdatePlayerNameCache = require('utils.safe_utils').UpdatePlayerNameCache
ClearPlayerNameCache = require('utils.safe_utils').ClearPlayerNameCache

Log("Core server script (server.lua) started. Initializing managers...", "info", "CNR_SERVER_MAIN")

-- Managers will be loaded based on fxmanifest.lua `server_scripts` order.
-- We can assume they will be available once this script runs.

-- =_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=
--                         PLAYER CONNECTION HANDLERS
--
-- These handlers are the entry and exit points for players. They delegate
-- all logic to the PlayerManager, which then coordinates with other managers
-- (like DataManager, InventoryManager, etc.) to handle the player's session.
-- =_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    UpdatePlayerNameCache(src, name) -- Cache name early
    Log(string.format("Player connecting: %s (ID: %s)", name, src), "info", "CNR_SERVER_MAIN")

    -- Defer connection to allow managers to perform asynchronous checks (e.g., ban checks).
    deferrals.defer()
    Citizen.Wait(100) -- Small delay to ensure identifiers are available.

    local canConnect, reason = PlayerManager.OnPlayerConnecting(src, name)

    if canConnect then
        deferrals.done()
    else
        deferrals.done(reason)
        Log(string.format("Player %s (ID: %s) connection denied. Reason: %s", name, src, reason), "warn", "CNR_SERVER_MAIN")
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local playerName = SafeGetPlayerName(src) or "Unknown"

    Log(string.format("Player %s (ID: %s) disconnected. Reason: %s", playerName, src, reason), "info", "CNR_SERVER_MAIN")

    -- Delegate all disconnection logic to the PlayerManager.
    PlayerManager.OnPlayerDisconnected(src, reason)

    -- Clear the cached name on disconnect.
    ClearPlayerNameCache(src)
end)

RegisterNetEvent('cnr:playerSpawned')
AddEventHandler('cnr:playerSpawned', function()
    local src = source
    Log(string.format("Player %s has spawned. Finalizing setup.", src), "info", "CNR_SERVER_MAIN")

    -- PlayerManager handles all logic related to a player spawning in the world,
    -- including data loading, inventory syncing, and applying perks/stats.
    PlayerManager.OnPlayerSpawned(src)
end)


-- =_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=
--                         GLOBAL EXPORTS & FUNCTIONS
--
-- Provide globally accessible functions for other resources or for easy access
-- across the framework, ensuring they route through the correct manager.
-- =_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

-- Provides a safe way for other resources to get player data.
---@param playerId number
---@return table | nil
function GetCnrPlayerData(playerId)
    return PlayerManager.GetPlayerData(playerId)
end
_G.exports("GetCnrPlayerData", GetCnrPlayerData)

-- Adds money to a player's account.
---@param playerId number
---@param amount number
---@param reason string
---@return boolean
function AddPlayerMoney(playerId, amount, reason)
    return PlayerManager.AddMoney(playerId, amount, reason)
end
_G.exports("AddPlayerMoney", AddPlayerMoney)

-- Removes money from a player's account.
---@param playerId number
---@param amount number
---@param reason string
---@return boolean
function RemovePlayerMoney(playerId, amount, reason)
    return PlayerManager.RemoveMoney(playerId, amount, reason)
end
_G.exports("RemovePlayerMoney", RemovePlayerMoney)

-- Adds experience points to a player.
---@param playerId number
---@param amount number
---@param reason string
---@return boolean
function AddPlayerXP(playerId, amount, reason)
    return ProgressionManager.AddXP(playerId, amount, reason)
end
_G.exports("AddPlayerXP", AddPlayerXP)

Log("Server.lua initialization complete. All systems delegated to managers.", "info", "CNR_SERVER_MAIN")
