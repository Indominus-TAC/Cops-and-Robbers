-- bounty_manager.lua
-- This module manages the bounty system, including placing, updating, and claiming bounties.

BountyManager = {}

local activeBounties = {} -- In-memory cache for active bounties. [Key: playerId, Value: bountyData table]

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized BountyManager prefix.
local function LogBountyManager(playerId, operation, message, level)
    level = level or "info"
    Log(string.format("[BountyManager] P:%s | Op:%s | %s", playerId, operation, message), level, "CNR_SERVER")
end

-- =============================================================================
--                              CORE BOUNTY LOGIC
-- =============================================================================

--- Checks if a player meets the criteria for a bounty and places one if they do.
function BountyManager.CheckAndPlaceBounty(playerId)
    local pData = PlayerManager.GetPlayerData(playerId)
    local wantedData = WantedManager.GetWantedData(playerId)
    if not pData or not wantedData then return end

    if pData.role == "robber" and wantedData.stars >= Config.BountySettings.wantedLevelThreshold then
        if not activeBounties[playerId] then
            local bountyAmount = Config.BountySettings.baseAmount + (wantedData.stars * 100)
            activeBounties[playerId] = {
                amount = bountyAmount,
                placer = "System",
                timestamp = os.time()
            }
            LogBountyManager(playerId, "place_bounty", string.format("System placed a $%d bounty.", bountyAmount))
            -- Notify all players of the new bounty
            TriggerClientEvent('cnr:bountyUpdate', -1, activeBounties)
        end
    end
end

--- Periodically updates all active bounties, increasing their value.
local function UpdateBounties()
    for playerId, bountyData in pairs(activeBounties) do
        -- Increase bounty amount over time
        bountyData.amount = bountyData.amount + (Config.BountySettings.increasePerMinute or 50)
    end
    -- Notify all players of the updated bounty list
    TriggerClientEvent('cnr:bountyUpdate', -1, activeBounties)
end

-- =============================================================================
--                             INITIALIZATION
-- =============================================================================

-- Timer to periodically check for new bounties.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(30000) -- Check every 30 seconds
        for _, playerId in ipairs(GetPlayers()) do
            BountyManager.CheckAndPlaceBounty(tonumber(playerId))
        end
    end
end)

-- Timer to periodically update existing bounties.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- Update every minute
        UpdateBounties()
    end
end)

Log("[BountyManager] Module loaded and initialized.", "info", "CNR_SERVER")
