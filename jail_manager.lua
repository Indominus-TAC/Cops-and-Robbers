-- jail_manager.lua
-- This module handles all logic related to the jail system, including sending players to jail,
-- managing their sentences, and releasing them.

JailManager = {}

local jailedPlayers = {} -- In-memory cache for currently jailed players. [Key: playerId, Value: jailData table]

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized JailManager prefix.
---@param playerId number | string The source player ID for the log entry. Can be "System".
---@param operation string A short descriptor of the operation (e.g., "send_to_jail", "release").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogJailManager(playerId, operation, message, level)
    level = level or "info"
    Log(string.format("[JailManager] P:%s | Op:%s | %s", playerId, operation, message), level, "CNR_SERVER")
end

--- Calculates the jail term in seconds based on a player's wanted stars.
---@param stars number The number of wanted stars (0-5).
---@return number The calculated jail sentence duration in seconds.
local function CalculateJailTerm(stars)
    local minPunishment = 60 -- Default minimum
    local maxPunishment = 120 -- Default maximum

    if Config.WantedSettings and Config.WantedSettings.levels then
        for _, levelData in ipairs(Config.WantedSettings.levels) do
            if levelData.stars == stars then
                minPunishment = levelData.minPunishment or minPunishment
                maxPunishment = levelData.maxPunishment or maxPunishment
                break
            end
        end
    end
    return math.random(minPunishment, maxPunishment)
end

-- =============================================================================
--                              CORE JAIL LOGIC
-- =============================================================================

--- Sends a player to jail for a specified duration.
---@param playerId number The ID of the player to be jailed.
---@param arrestingOfficerId number | nil The ID of the arresting officer, if any.
function JailManager.SendToJail(playerId, arrestingOfficerId)
    local pData = PlayerManager.GetPlayerData(playerId)
    local wantedData = WantedManager.GetWantedData(playerId) -- Assume WantedManager exposes this
    if not pData or not wantedData then
        LogJailManager(playerId, "send_to_jail", "Failed: Player or wanted data not found.", "error")
        return
    end

    local jailDuration = CalculateJailTerm(wantedData.stars)

    -- Store jail info in the player's main data for persistence
    pData.jailData = {
        remainingTime = jailDuration,
        originalDuration = jailDuration,
        jailedByOfficer = arrestingOfficerId,
        jailedTimestamp = os.time()
    }

    -- Add to the in-memory cache for the sentence countdown
    jailedPlayers[playerId] = pData.jailData

    LogJailManager(playerId, "send_to_jail", string.format("Jailed for %d seconds. Officer: %s.", jailDuration, arrestingOfficerId or "N/A"))

    -- Clear wanted level
    WantedManager.ClearWantedLevel(playerId, "Jailed by officer " .. (arrestingOfficerId or "System"))

    -- Teleport player to jail and notify their client
    SafeTriggerClientEvent('cnr:sendToJail', playerId, jailDuration, Config.PrisonLocation)
    SafeTriggerClientEvent('chat:addMessage', playerId, { args = {"^1Jail", string.format("You have been jailed for %d seconds.", jailDuration)} })

    -- Notify police
    local criminalName = pData.name or "A suspect"
    local officerName = (arrestingOfficerId and PlayerManager.GetPlayerData(arrestingOfficerId).name) or "System"
    for _, pid in ipairs(GetPlayers()) do
        if PlayerManager.GetPlayerRole(pid) == "cop" then
            SafeTriggerClientEvent('chat:addMessage', tonumber(pid), { args = {"^5Police Info", string.format("%s was jailed by %s.", criminalName, officerName)} })
        end
    end

    -- Award arresting officer
    if arrestingOfficerId then
        ProgressionManager.AwardArrestXP(arrestingOfficerId, wantedData.stars)
        -- Placeholder for bounty claims: BountyManager.ClaimBounty(arrestingOfficerId, playerId)
    end

    DataManager.MarkPlayerForSave(playerId)
end

--- Releases a player from jail.
---@param playerId number The ID of the player to be released.
---@param reason string A reason for the release, for logging purposes.
function JailManager.ReleaseFromJail(playerId, reason)
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then
        LogJailManager(playerId, "release", "Failed: Player data not found.", "error")
        return
    end

    -- Clear jail data from both persistent and in-memory stores
    pData.jailData = nil
    jailedPlayers[playerId] = nil

    LogJailManager(playerId, "release", "Released from jail. Reason: " .. reason)

    -- Notify the client to release the player
    SafeTriggerClientEvent('cnr:releaseFromJail', playerId)
    SafeTriggerClientEvent('chat:addMessage', playerId, { args = {"^2Jail", "You have been released."} })

    DataManager.MarkPlayerForSave(playerId)
end

--- Checks a player's jail status upon loading into the server.
--- This ensures players who were jailed and logged off are put back in jail.
---@param playerId number The ID of the player to check.
function JailManager.CheckJailStatusOnLoad(playerId)
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData or not pData.jailData then
        return -- Player is not jailed, nothing to do.
    end

    local timeElapsed = os.time() - pData.jailData.jailedTimestamp
    local newRemainingTime = math.max(0, pData.jailData.originalDuration - timeElapsed)

    if newRemainingTime > 0 then
        pData.jailData.remainingTime = newRemainingTime
        jailedPlayers[playerId] = pData.jailData
        LogJailManager(playerId, "check_on_load", string.format("Player is still jailed. %d seconds remaining.", newRemainingTime))
        SafeTriggerClientEvent('cnr:sendToJail', playerId, newRemainingTime, Config.PrisonLocation)
    else
        LogJailManager(playerId, "check_on_load", "Player's jail sentence expired while offline. Releasing.")
        JailManager.ReleaseFromJail(playerId, "Sentence served while offline")
    end
end

--- Clears jail data for a player from the in-memory cache. Called on disconnect.
---@param playerId number The ID of the player to clean up.
function JailManager.CleanupPlayer(playerId)
    if jailedPlayers[playerId] then
        jailedPlayers[playerId] = nil
        LogJailManager(playerId, "cleanup", "Player jail data cleaned from cache.")
    end
end

-- =============================================================================
--                             SENTENCE COUNTDOWN
-- =============================================================================

--- Periodically reduces the remaining sentence for all jailed players.
local function UpdateJailSentences()
    -- Create a copy of the keys to safely iterate while potentially modifying the table
    local jailedPlayerIds = {}
    for id in pairs(jailedPlayers) do
        table.insert(jailedPlayerIds, id)
    end

    for _, playerId in ipairs(jailedPlayerIds) do
        local jailData = jailedPlayers[playerId]
        if jailData then
            jailData.remainingTime = jailData.remainingTime - 1

            if jailData.remainingTime <= 0 then
                JailManager.ReleaseFromJail(playerId, "Sentence served")
            elseif jailData.remainingTime % 60 == 0 then -- Notify every minute
                SafeTriggerClientEvent('chat:addMessage', playerId, { args = {"^3Jail Info", string.format("Time remaining: %d seconds.", jailData.remainingTime)} })
            end
        end
    end
end


-- =============================================================================
--                             INITIALIZATION
-- =============================================================================

-- Timer to process the jail sentence countdown.
-- Optimized timer to process the jail sentence countdown.
-- This loop runs at a high frequency but is managed by the PerformanceOptimizer
-- to ensure it doesn't cause performance issues. It is given a high priority
-- to maintain timer accuracy.
PerformanceOptimizer.CreateOptimizedLoop(
    UpdateJailSentences,
    1000, -- Base interval of 1 second for accuracy
    1500, -- Max interval of 1.5 seconds to allow for minor performance adjustments
    1     -- High priority (1 is highest)
)

Log("[JailManager] Module loaded. Sentence countdown processor is running.", "info", "CNR_SERVER")
