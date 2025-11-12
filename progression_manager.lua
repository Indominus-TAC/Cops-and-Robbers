-- progression_manager.lua
-- This module manages player progression, including experience points (XP),
-- leveling, and the application of level-based perks.

ProgressionManager = {}

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized ProgressionManager prefix.
---@param playerId number | string The source player ID for the log entry. Can be "System".
---@param operation string A short descriptor of the operation (e.g., "add_xp", "apply_perks").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogProgressionManager(playerId, operation, message, level)
    level = level or "info"
    Log(string.format("[ProgressionManager] P:%s | Op:%s | %s", playerId, operation, message), level, "CNR_SERVER")
end

--- Calculates a player's level based on their total XP.
---@param xp number The total experience points of the player.
---@return number The calculated level.
local function CalculateLevel(xp)
    if not Config.LevelingSystemEnabled then return 1 end

    local level = 1
    local requiredXp = 0

    -- Iterate through the XP table to determine the player's current level
    for i = 1, (Config.MaxLevel or 50) - 1 do
        requiredXp = requiredXp + (Config.XPTable[i] or 1000)
        if xp >= requiredXp then
            level = i + 1
        else
            break
        end
    end

    return math.min(level, Config.MaxLevel or 50)
end

-- =============================================================================
--                              CORE PROGRESSION LOGIC
-- =============================================================================

--- Adds XP to a player and handles level-ups.
---@param playerId number The ID of the player.
---@param amount number The amount of XP to add.
---@param reason string (Optional) A reason for the XP gain, for logging.
function ProgressionManager.AddXP(playerId, amount, reason)
    reason = reason or "Generic"
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then
        LogProgressionManager(playerId, "add_xp", "Failed: Player data not found.", "error")
        return
    end

    local oldLevel = pData.level
    pData.xp = pData.xp + amount
    local newLevel = CalculateLevel(pData.xp)

    LogProgressionManager(playerId, "add_xp", string.format("Awarded %d XP for %s. Total XP: %d.", amount, reason, pData.xp))

    if newLevel > oldLevel then
        pData.level = newLevel
        LogProgressionManager(playerId, "level_up", string.format("Player leveled up to level %d!", newLevel))
        SafeTriggerClientEvent('cnr:levelUp', playerId, newLevel)

        -- Apply any new perks the player has unlocked.
        ProgressionManager.ApplyPerks(playerId)
    end

    -- Always sync the XP gain to the client for UI updates.
    SafeTriggerClientEvent('cnr:xpGained', playerId, amount)
    PlayerManager.SyncPlayerDataToClient(playerId) -- Sync the whole data package to be safe
    DataManager.MarkPlayerForSave(playerId)
end

--- Applies all unlocked perks to a player based on their current level and role.
--- This function should be called on level-up and role change.
function ProgressionManager.ApplyPerks(playerId)
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then return end

    -- Reset current perks to start fresh
    pData.perks = {}

    local unlocks = Config.LevelUnlocks[pData.role]
    if not unlocks then return end -- No perks for this role

    for levelKey, levelUnlocksTable in pairs(unlocks) do
        if pData.level >= levelKey then
            for _, perkDetail in ipairs(levelUnlocksTable) do
                if perkDetail.type == "passive_perk" and perkDetail.perkId then
                    pData.perks[perkDetail.perkId] = perkDetail.value or true
                    LogProgressionManager(playerId, "apply_perks", string.format("Unlocked perk '%s' at level %d.", perkDetail.perkId, levelKey))
                end
            end
        end
    end

    LogProgressionManager(playerId, "apply_perks", "Finished applying all eligible perks.")
    DataManager.MarkPlayerForSave(playerId)
    -- No need to sync here, as this is usually called from a function that will sync.
end

--- Awards XP to a cop for making a successful arrest.
--- The amount of XP is based on the suspect's wanted level.
---@param officerId number The ID of the arresting officer.
---@param suspectStars number The number of wanted stars the suspect had.
function ProgressionManager.AwardArrestXP(officerId, suspectStars)
    local xpAmount = 0
    if suspectStars >= 4 then
        xpAmount = Config.XPActionsCop.successful_arrest_high_wanted or 50
    elseif suspectStars >= 2 then
        xpAmount = Config.XPActionsCop.successful_arrest_medium_wanted or 30
    else
        xpAmount = Config.XPActionsCop.successful_arrest_low_wanted or 15
    end

    ProgressionManager.AddXP(officerId, xpAmount, "Successful Arrest")
    SafeTriggerClientEvent('chat:addMessage', officerId, { args = {"^2XP", string.format("Gained %d XP for the arrest.", xpAmount)} })
end

-- =============================================================================
--                             INITIALIZATION
-- =============================================================================

Log("[ProgressionManager] Module loaded and initialized.", "info", "CNR_SERVER")
