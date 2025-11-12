-- data_manager.lua
-- This module is the sole authority for all file-based data persistence.
-- It provides a simple, robust API for saving and loading player and system data.
-- Features a batched, asynchronous save queue to prevent I/O bottlenecks and data loss.

DataManager = {}

local saveQueue = {} -- A queue of data blobs waiting to be written to disk. [ { key, data, callback} ]
local isSaveInProgress = false -- A lock to prevent concurrent save operations.

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized DataManager prefix.
---@param operation string A short descriptor of the operation (e.g., "save_queue", "load_file").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogDataManager(operation, message, level)
    level = level or "info"
    Log(string.format("[DataManager] Op:%s | %s", operation, message), level, "CNR_SERVER")
end

--- Generates a standardized file path for a given player's data.
---@param playerId number The ID of the player.
---@return string The resource-relative path to the player's data file (e.g., "player_data/license_123.json").
local function GetPlayerKey(playerId)
    local license = PlayerManager.GetPlayerLicense(playerId)
    if not license then
        LogDataManager("get_player_key", "Could not generate key: Player license is nil for ID: " .. playerId, "error")
        return nil
    end
    -- Sanitize the license to use it as a filename.
    local sanitizedLicense = license:gsub(":", "_")
    return "player_data/" .. sanitizedLicense .. ".json"
end

-- =============================================================================
--                              CORE SAVE/LOAD LOGIC
-- =============================================================================

--- Asynchronously saves player data. Adds the data to a queue which is processed periodically.
---@param playerId number The ID of the player whose data is being saved.
---@param playerData table The complete data table for the player.
---@param callback function (Optional) A function to call upon completion. `callback(success)`
function DataManager.SavePlayerData(playerId, playerData, callback)
    local key = GetPlayerKey(playerId)
    if not key then
        if callback then callback(false) end
        return
    end

    -- To prevent duplicate entries, we can overwrite any existing pending save for the same key.
    -- However, for simplicity and robustness, we'll let the queue process them.
    -- A more advanced implementation could use a map `saveQueue[key] = { ... }` to auto-debounce.
    table.insert(saveQueue, { key = key, data = playerData, callback = callback })
    LogDataManager("save_player_data", "Queued save for player " .. playerId .. ". Queue size: " .. #saveQueue)
end

--- Asynchronously loads player data from a file.
---@param playerId number The ID of the player whose data is being loaded.
---@param callback function The function to call with the loaded data. `callback(pData, success)`
function DataManager.LoadPlayerData(playerId, callback)
    local key = GetPlayerKey(playerId)
    if not key then
        if callback then callback(nil, false) end
        return
    end

    -- Use a coroutine to handle the file I/O without blocking the main thread.
    Citizen.CreateThread(function()
        local fileContent = LoadResourceFile(GetCurrentResourceName(), key)
        if not fileContent or fileContent == "" then
            LogDataManager("load_player_data", "No existing data file found for player " .. playerId, "info")
            if callback then callback(nil, false) end
            return
        end

        local success, data = pcall(json.decode, fileContent)
        if not success then
            LogDataManager("load_player_data", "Failed to decode JSON for player " .. playerId .. ". Error: " .. tostring(data), "error")
            -- TODO: Implement corrupted data backup/recovery logic here.
            if callback then callback(nil, false) end
            return
        end

        LogDataManager("load_player_data", "Successfully loaded data for player " .. playerId)
        if callback then callback(data, true) end
    end)
end

--- Periodically processes the save queue, writing data to files.
--- This runs on a timer to batch I/O operations and reduce disk contention.
local function ProcessSaveQueue()
    if isSaveInProgress or #saveQueue == 0 then
        return -- Don't process if already running or if queue is empty.
    end

    isSaveInProgress = true
    local startTime = GetGameTimer()
    local itemsToProcess = {}

    -- Move items from the global queue to a local one to avoid blocking new save requests.
    for i = 1, #saveQueue do
        table.insert(itemsToProcess, table.remove(saveQueue, 1))
    end
    -- Clear the queue by reference in case of any stragglers (shouldn't happen with the loop above)
    saveQueue = {}


    LogDataManager("process_queue", string.format("Starting save batch for %d items.", #itemsToProcess), "info")

    -- Use a coroutine for the file I/O part.
    Citizen.CreateThread(function()
        local successCount = 0
        for _, item in ipairs(itemsToProcess) do
            local jsonData = json.encode(item.data)
            local success = SaveResourceFile(GetCurrentResourceName(), item.key, jsonData, -1)

            if success then
                successCount = successCount + 1
            else
                LogDataManager("process_queue", "Failed to save file for key: " .. item.key, "error")
            end

            if item.callback then
                item.callback(success)
            end
        end

        local duration = GetGameTimer() - startTime
        LogDataManager("process_queue", string.format("Save batch finished. %d/%d items saved successfully in %d ms.", successCount, #itemsToProcess, duration), "info")
        isSaveInProgress = false
    end)
end


-- =============================================================================
--                             PUBLIC API & INITIALIZATION
-- =============================================================================

--- A function for other modules to mark a player's data as needing a save, without providing the data itself.
--- The PlayerManager will later call SavePlayerData with the full, up-to-date data object.
--- This is now effectively a wrapper for `SavePlayerData` which will be called with the actual data.
--- In this refactored design, the responsibility shifts: the module owning the data (`PlayerManager`) should call `SavePlayerData`.
--- This function is kept for conceptual clarity but its direct use should be phased out.
---@param playerId number The ID of the player to mark for saving.
function DataManager.MarkPlayerForSave(playerId)
    -- This function now acts as a trigger. The actual data must be fetched and passed.
    -- This highlights a design improvement: the caller with the data should initiate the save.
    -- Example of how it should be used by PlayerManager:
    -- local pData = PlayerManager.GetPlayerData(playerId)
    -- if pData then DataManager.SavePlayerData(playerId, pData) end
    LogDataManager("mark_for_save", "Player " .. playerId .. " marked for save. Note: The owning module must now call SavePlayerData with the data.", "info")
end

--- Timer to process the save queue every `Config.SaveInterval` milliseconds.
-- Optimized timer to process the save queue.
-- This loop runs at a lower frequency and is managed by the PerformanceOptimizer.
-- It has a low priority, as data saving is a background task that can be deferred
-- slightly to prioritize core gameplay loops.
PerformanceOptimizer.CreateOptimizedLoop(
    ProcessSaveQueue,
    Config.SaveInterval or 15000, -- Base interval (e.g., 15 seconds)
    (Config.SaveInterval or 15000) * 3, -- Max interval (e.g., 45 seconds)
    5 -- Low priority
)

Log("[DataManager] Module loaded. Save queue processor is running.", "info", "CNR_SERVER")
