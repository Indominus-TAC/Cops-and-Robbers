-- player_manager.lua
-- This module is the authoritative source for managing player data, roles, sessions, and characters.
-- It interfaces with DataManager for persistence and orchestrates other managers when player state changes.

PlayerManager = {}

local playerDataCache = {} -- In-memory cache for all online players' data. [Key: playerId, Value: pData table]
local playerLoadingStates = {} -- Tracks players currently being loaded to prevent race conditions. [Key: playerId, Value: boolean]

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized PlayerManager prefix.
---@param playerId number The source player ID for the log entry.
---@param operation string A short descriptor of the operation (e.g., "load", "save").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogPlayerManager(playerId, operation, message, level)
    level = level or "info"
    local playerName = SafeGetPlayerName(playerId) or "Unknown"
    Log(string.format("[PlayerManager] P:%s(%s) | Op:%s | %s", playerId, playerName, operation, message), level, "CNR_SERVER")
end

--- Creates a default data structure for a new player.
---@param playerId number The ID of the new player.
---@return table A fully-formed player data table.
local function CreateDefaultPlayerData(playerId)
    local pData = {
        -- Core Identifiers
        playerId = playerId,
        license = PlayerManager.GetPlayerLicense(playerId), -- Get license early

        -- Core Stats
        role = "citizen",
        level = 1,
        xp = 0,
        money = Config.DefaultStartMoney or 5000,

        -- State & Data
        inventory = {},
        lastKnownPosition = vector3(0.0, 0.0, 0.0), -- Will be updated on first spawn
        jailData = nil, -- { remainingTime, originalDuration, jailedByOfficer, jailedTimestamp }
        perks = {},
        bountyCooldownUntil = 0,

        -- Metadata
        isDataLoaded = false, -- Flag to prevent actions on partially loaded data
        dataVersion = "1.0", -- For future data migrations
        firstJoined = os.time(),
        lastSeen = os.time()
    }
    LogPlayerManager(playerId, "create_default_data", "Created new default player data structure.")
    return pData
end

-- =============================================================================
--                            PLAYER LIFECYCLE HANDLERS
-- =============================================================================

--- Handles the initial connection of a player, performing ban checks.
---@param playerId number The connecting player's ID.
---@param playerName string The player's name.
---@return boolean, string Returns true if the player can connect, otherwise false and a kick reason.
function PlayerManager.OnPlayerConnecting(playerId, playerName)
    -- Delegate ban check to SecurityManager
    local isBanned, banReason = SecurityManager.CheckBan(playerId)
    if isBanned then
        return false, banReason
    end

    -- Potentially add whitelist check here in the future
    -- local isWhitelisted = SecurityManager.CheckWhitelist(playerId)
    -- if not isWhitelisted then
    --     return false, "You are not whitelisted on this server."
    -- end

    return true, ""
end


--- Handles all logic when a player spawns into the world.
--- This is the primary entry point for loading and initializing a player's session.
---@param playerId number The ID of the player who spawned.
function PlayerManager.OnPlayerSpawned(playerId)
    if playerLoadingStates[playerId] then
        LogPlayerManager(playerId, "spawn", "Attempted to spawn while already loading. Request ignored.", "warn")
        return
    end

    if playerDataCache[playerId] and playerDataCache[playerId].isDataLoaded then
        LogPlayerManager(playerId, "spawn", "Player already has loaded data. Re-syncing client state.")
        PlayerManager.SyncPlayerDataToClient(playerId)
        return
    end

    LogPlayerManager(playerId, "spawn", "Player has spawned. Initiating data load sequence.")
    playerLoadingStates[playerId] = true

    -- Asynchronously load data from the DataManager
    DataManager.LoadPlayerData(playerId, function(pData, success)
        if not success or not pData then
            LogPlayerManager(playerId, "load_callback", "Data loading failed or returned nil. Creating fresh data.", "warn")
            pData = CreateDefaultPlayerData(playerId)
        else
            LogPlayerManager(playerId, "load_callback", "Successfully loaded player data from persistence.")
        end

        pData.isDataLoaded = true
        playerDataCache[playerId] = pData
        playerLoadingStates[playerId] = nil -- Loading complete

        -- Finalize setup now that data is loaded
        PlayerManager.FinalizePlayerSetup(playerId)
    end)
end

--- Centralized disconnection logic. Saves player data and cleans up memory.
---@param playerId number The ID of the disconnected player.
---@param reason string The reason for disconnection.
function PlayerManager.OnPlayerDisconnected(playerId, reason)
    local pData = playerDataCache[playerId]

    if pData and pData.isDataLoaded then
        LogPlayerManager(playerId, "disconnect", "Player has loaded data. Performing immediate save.")
        -- Update last known position before saving
        local playerPed = GetPlayerPed(tostring(playerId))
        if playerPed and playerPed ~= 0 then
            pData.lastKnownPosition = GetEntityCoords(playerPed)
        end
        pData.lastSeen = os.time()

        DataManager.SavePlayerData(playerId, pData, function(success)
            if success then
                LogPlayerManager(playerId, "save_on_disconnect", "Data saved successfully.")
            else
                LogPlayerManager(playerId, "save_on_disconnect", "Failed to save data on disconnect.", "error")
            end
            -- Cleanup happens regardless of save success to prevent memory leaks.
            PlayerManager.CleanupPlayer(playerId)
        end)
    else
        LogPlayerManager(playerId, "disconnect", "Player has no loaded data or was still loading. Skipping save.")
        PlayerManager.CleanupPlayer(playerId)
    end
end

-- =============================================================================
--                            CORE DATA & STATE MANAGEMENT
-- =============================================================================

--- Performs the final setup steps for a player after their data has been loaded into the cache.
---@param playerId number The ID of the player to set up.
function PlayerManager.FinalizePlayerSetup(playerId)
    local pData = playerDataCache[playerId]
    if not pData then
        LogPlayerManager(playerId, "finalize_setup", "Cannot finalize setup, player data not in cache.", "error")
        return
    end

    LogPlayerManager(playerId, "finalize_setup", "Finalizing player setup. Role: " .. pData.role)

    -- Set the player's role, which also handles team/group assignments.
    PlayerManager.SetPlayerRole(playerId, pData.role, true) -- `true` to skip initial notification

    -- Apply perks and other level-based benefits.
    ProgressionManager.ApplyPerks(playerId)

    -- Check if the player should still be in jail.
    JailManager.CheckJailStatusOnLoad(playerId)

    -- Sync all necessary data to the client to ensure the UI is up to date.
    PlayerManager.SyncPlayerDataToClient(playerId)

    LogPlayerManager(playerId, "finalize_setup", "Player setup complete. Client data synchronized.")
end

--- Synchronizes the authoritative server data with the client.
--- This should be called whenever critical player data changes.
---@param playerId number The ID of the player to sync.
function PlayerManager.SyncPlayerDataToClient(playerId)
    local pData = playerDataCache[playerId]
    if not pData or not pData.isDataLoaded then
        LogPlayerManager(playerId, "sync_client", "Aborted sync: Player data not loaded.", "warn")
        return
    end

    -- Send core player data (HUD info)
    local coreData = {
        money = pData.money,
        xp = pData.xp,
        level = pData.level,
        role = pData.role,
    }
    SafeTriggerClientEvent('cnr:updatePlayerData', playerId, coreData)

    -- Sync full inventory state
    InventoryManager.SyncInventory(playerId)

    -- Sync wanted level
    WantedManager.SyncWantedLevel(playerId)

    LogPlayerManager(playerId, "sync_client", "Core data, inventory, and wanted level synced to client.")
end

--- Safely retrieves a player's data from the cache.
---@param playerId number The ID of the player.
---@return table | nil The player's data table, or nil if not found or not loaded.
function PlayerManager.GetPlayerData(playerId)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return nil end

    local pData = playerDataCache[pIdNum]
    if pData and pData.isDataLoaded then
        return pData
    end
    return nil
end

--- Cleans up all in-memory data associated with a player.
--- Called on disconnect or when a player's session is terminated.
---@param playerId number The ID of the player to clean up.
function PlayerManager.CleanupPlayer(playerId)
    playerDataCache[playerId] = nil
    playerLoadingStates[playerId] = nil
    -- Also inform other managers to clean up their caches for this player
    WantedManager.CleanupPlayer(playerId)
    JailManager.CleanupPlayer(playerId)
    InventoryManager.CleanupPlayer(playerId)
    LogPlayerManager(playerId, "cleanup", "All cached data for player has been cleared.")
end

-- =============================================================================
--                            PUBLIC API & HELPER FUNCTIONS
-- =============================================================================

--- Retrieves a player's license identifier (e.g., "license:123...").
---@param playerId number The ID of the player.
---@return string | nil The license identifier or nil if not found.
function PlayerManager.GetPlayerLicense(playerId)
    local identifiers = GetPlayerIdentifiers(tostring(playerId))
    if identifiers then
        for _, identifier in ipairs(identifiers) do
            if string.match(identifier, "^license:") then
                return identifier
            end
        end
    end
    LogPlayerManager(playerId, "get_license", "Could not find license identifier.", "warn")
    return nil
end

--- Adds or removes money from a player's balance. Use negative amount to subtract.
---@param playerId number The ID of the player.
---@param amount number The amount of money to add (can be negative).
---@param reason string (Optional) A reason for the transaction for logging purposes.
---@return boolean True if the transaction was successful, false otherwise.
function PlayerManager.UpdateMoney(playerId, amount, reason)
    reason = reason or "Unspecified"
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then
        LogPlayerManager(playerId, "update_money", "Transaction failed: Player data not found.", "error")
        return false
    end

    local newBalance = pData.money + amount
    if newBalance < 0 then
        LogPlayerManager(playerId, "update_money", string.format("Transaction failed: Insufficient funds. Needed %d, had %d.", math.abs(amount), pData.money))
        SafeTriggerClientEvent('cnr:notification', playerId, "You don't have enough money.", "error")
        return false
    end

    pData.money = newBalance
    LogPlayerManager(playerId, "update_money", string.format("Amount: %d. Reason: %s. New Balance: %d.", amount, reason, pData.money))
    PlayerManager.SyncPlayerDataToClient(playerId) -- Sync changes to the client
    DataManager.MarkPlayerForSave(playerId) -- Mark data for periodic saving
    return true
end

--- Retrieves the current role of a player.
---@param playerId number The ID of the player.
---@return string The player's current role (e.g., "cop", "robber", "citizen").
function PlayerManager.GetPlayerRole(playerId)
    local pData = PlayerManager.GetPlayerData(playerId)
    return pData and pData.role or "citizen"
end

--- Sets a player's role and updates all relevant systems.
---@param playerId number The ID of the player.
---@param role string The new role to set.
---@param skipNotify boolean (Optional) If true, a chat notification will not be sent to the player.
function PlayerManager.SetPlayerRole(playerId, role, skipNotify)
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then
        LogPlayerManager(playerId, "set_role", "Failed to set role: Player data not found.", "error")
        return
    end

    -- Validate the role
    if role ~= "cop" and role ~= "robber" and role ~= "citizen" then
        LogPlayerManager(playerId, "set_role", "Attempted to set an invalid role: " .. tostring(role), "warn")
        return
    end

    local oldRole = pData.role
    if oldRole == role then return end -- No change needed

    pData.role = role

    -- If player becomes a cop, clear their wanted level.
    if role == "cop" then
        WantedManager.ClearWantedLevel(playerId, "Switched to cop role")
    end

    -- If player changes role, re-apply perks as they might be role-specific.
    ProgressionManager.ApplyPerks(playerId)

    -- Sync the role change to the client for UI/gameplay updates.
    SafeTriggerClientEvent('cnr:setPlayerRole', playerId, role)

    if not skipNotify then
        SafeTriggerClientEvent('chat:addMessage', playerId, { args = {"^3Role", "You are now a " .. string.upper(role).."."} })
    end

    LogPlayerManager(playerId, "set_role", string.format("Role changed from %s to %s.", oldRole, role))
    DataManager.MarkPlayerForSave(playerId)
    PlayerManager.SyncPlayerDataToClient(playerId)
end

-- =============================================================================
--                            EVENT HANDLERS
-- =============================================================================

-- Handles the client's request to select a role.
-- Handles the client's request to select a role with server-side validation.
RegisterNetEvent('cnr:selectRole')
AddEventHandler('cnr:selectRole', function(selectedRole)
    local src = source
    
    -- SERVER-SIDE VALIDATION: Ensure the role is a valid, expected value.
    if selectedRole ~= "cop" and selectedRole ~= "robber" and selectedRole ~= "citizen" then
        LogPlayerManager(src, "select_role", "Player sent an invalid role: " .. tostring(selectedRole), "warn")
        -- Optional: Kick or flag the player for suspicious activity.
        return
    end

    local pData = PlayerManager.GetPlayerData(src)
    if not pData then
        LogPlayerManager(src, "select_role", "Role selection failed: Data not loaded.", "warn")
        SafeTriggerClientEvent('cnr:roleSelected', src, false, "Player data is not ready. Please wait a moment.")
        return
    end

    PlayerManager.SetPlayerRole(src, selectedRole)

    local spawnPoint = Config.SpawnPoints[selectedRole]
    if spawnPoint then
        SafeTriggerClientEvent('cnr:spawnPlayerAt', src, spawnPoint.coords, spawnPoint.heading)
        LogPlayerManager(src, "select_role", string.format("Spawning player as %s at configured spawn point.", selectedRole))
    else
        LogPlayerManager(src, "select_role", string.format("No spawn point found for role %s. Player will spawn at default location.", selectedRole), "warn")
    end

    SafeTriggerClientEvent('cnr:roleSelected', src, true, "Role selected successfully.")
end)


-- =============================================================================
--                            GLOBAL EXPORTS
-- =============================================================================
-- These exports make key PlayerManager functions available to other resources
-- in a controlled and explicit manner, improving modularity.

exports('GetPlayerData', PlayerManager.GetPlayerData)
exports('UpdateMoney', PlayerManager.UpdateMoney)
exports('GetPlayerRole', PlayerManager.GetPlayerRole)
exports('SetPlayerRole', PlayerManager.SetPlayerRole)

Log("[PlayerManager] Module loaded and initialized.", "info", "CNR_SERVER")
