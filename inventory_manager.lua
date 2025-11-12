-- inventory_manager.lua
-- This module is the single source of truth for all player inventory operations.
-- It ensures data integrity, handles all inventory modifications, and syncs state with the client.

InventoryManager = {}

-- =============================================================================
--                            PRIVATE HELPER FUNCTIONS
-- =============================================================================

--- Logs a message with a standardized InventoryManager prefix.
---@param playerId number The source player ID for the log entry.
---@param operation string A short descriptor of the operation (e.g., "add_item", "sync").
---@param message string The detailed log message.
---@param level string (Optional) The log level ('info', 'warn', 'error'). Defaults to 'info'.
local function LogInventoryManager(playerId, operation, message, level)
    level = level or "info"
    Log(string.format("[InventoryManager] P:%s | Op:%s | %s", playerId, operation, message), level, "CNR_SERVER")
end

--- Retrieves the inventory for a given player directly from the PlayerManager's cache.
---@param playerId number The ID of the player.
---@return table | nil The player's inventory table, or nil if the player or inventory doesn't exist.
local function GetInventory(playerId)
    local pData = PlayerManager.GetPlayerData(playerId)
    if not pData then
        LogInventoryManager(playerId, "get_inventory", "Could not get inventory: Player data not found.", "warn")
        return nil
    end
    -- Ensure an inventory table exists.
    if not pData.inventory then
        pData.inventory = {}
    end
    return pData.inventory
end

--- Validates if an item exists in the server's configuration.
---@param itemId string The unique identifier for the item.
---@return table | nil The item's configuration table from Config.Items, or nil if not found.
local function GetItemConfig(itemId)
    if Config.Items and Config.Items[itemId] then
        return Config.Items[itemId]
    end
    return nil
end

-- =============================================================================
--                              CORE INVENTORY LOGIC
-- =============================================================================

--- Adds a specified quantity of an item to a player's inventory.
---@param playerId number The ID of the player.
---@param itemId string The unique ID of the item to add.
---@param quantity number The number of items to add. Must be a positive integer.
---@return boolean, string True and a success message if the item was added, otherwise false and an error message.
function InventoryManager.AddItem(playerId, itemId, quantity)
    quantity = tonumber(quantity)
    if not quantity or quantity <= 0 then
        return false, "Invalid quantity."
    end

    local itemConfig = GetItemConfig(itemId)
    if not itemConfig then
        return false, "Invalid item ID."
    end

    local inventory = GetInventory(playerId)
    if not inventory then
        return false, "Player inventory not accessible."
    end

    local currentQuantity = inventory[itemId] and inventory[itemId].count or 0
    local newQuantity = currentQuantity + quantity

    -- Optional: Check against item stack limit from config
    -- if itemConfig.maxStack and newQuantity > itemConfig.maxStack then
    --     return false, "Item stack limit exceeded."
    -- end

    inventory[itemId] = {
        count = newQuantity,
        name = itemConfig.name, -- Store some denormalized data for convenience
        category = itemConfig.category
    }

    LogInventoryManager(playerId, "add_item", string.format("Added %d of %s. New total: %d.", quantity, itemId, newQuantity))
    InventoryManager.SyncInventory(playerId)
    DataManager.MarkPlayerForSave(playerId)
    return true, "Item added successfully."
end

--- Removes a specified quantity of an item from a player's inventory.
---@param playerId number The ID of the player.
---@param itemId string The unique ID of the item to remove.
---@param quantity number The number of items to remove. Must be a positive integer.
---@return boolean, string True and a success message if the item was removed, otherwise false and an error message.
function InventoryManager.RemoveItem(playerId, itemId, quantity)
    quantity = tonumber(quantity)
    if not quantity or quantity <= 0 then
        return false, "Invalid quantity."
    end

    local inventory = GetInventory(playerId)
    if not inventory then
        return false, "Player inventory not accessible."
    end

    if not inventory[itemId] or inventory[itemId].count < quantity then
        return false, "Insufficient quantity of item."
    end

    local newQuantity = inventory[itemId].count - quantity
    LogInventoryManager(playerId, "remove_item", string.format("Removed %d of %s. New total: %d.", quantity, itemId, newQuantity))

    if newQuantity > 0 then
        inventory[itemId].count = newQuantity
    else
        inventory[itemId] = nil -- Remove the item entry completely if count is zero or less.
    end

    InventoryManager.SyncInventory(playerId)
    DataManager.MarkPlayerForSave(playerId)
    return true, "Item removed successfully."
end

--- Checks if a player has a sufficient quantity of a specific item.
---@param playerId number The ID of the player.
---@param itemId string The unique ID of the item to check for.
---@param quantity number The required quantity.
---@return boolean True if the player has at least the specified quantity, false otherwise.
function InventoryManager.HasItem(playerId, itemId, quantity)
    quantity = tonumber(quantity) or 1
    local inventory = GetInventory(playerId)
    if not inventory or not inventory[itemId] then
        return false
    end
    return inventory[itemId].count >= quantity
end

--- Synchronizes the player's full inventory state with the client.
--- This is crucial for keeping the client-side UI and logic up-to-date.
---@param playerId number The ID of the player whose inventory needs to be synced.
function InventoryManager.SyncInventory(playerId)
    local inventory = GetInventory(playerId)
    if inventory then
        -- We send a minimal version of the inventory to save bandwidth.
        -- The client reconstructs the full details using its copy of Config.Items.
        local minimalInventory = {}
        for itemId, itemData in pairs(inventory) do
            minimalInventory[itemId] = itemData.count
        end
        SafeTriggerClientEvent('cnr:syncInventory', playerId, minimalInventory)
        LogInventoryManager(playerId, "sync", "Full inventory state synced to client.")
    end
end

--- Clears all cached inventory data for a player. Called on disconnect.
---@param playerId number The ID of the player to clean up.
function InventoryManager.CleanupPlayer(playerId)
    -- Since the inventory is part of the playerDataCache in PlayerManager,
    -- cleaning up the player in PlayerManager handles this implicitly.
    -- This function is here for explicit design clarity and future use if inventory
    -- gets its own separate cache.
    LogInventoryManager(playerId, "cleanup", "Player inventory data cleaned up.")
end

-- =============================================================================
--                                  EVENT HANDLERS
-- =============================================================================
-- These handlers respond to network events from clients, but all core logic is
-- routed through the secure, authoritative functions above.

-- Example handler for a client-side buy request.
-- Secure handler for a client-side buy request.
RegisterNetEvent('cnr:buyItem')
AddEventHandler('cnr:buyItem', function(itemId, quantity)
    local src = source

    -- Server-side validation
    local itemConfig = GetItemConfig(itemId)
    quantity = tonumber(quantity)
    if not itemConfig or not quantity or quantity <= 0 then
        LogInventoryManager(src, "buy_event", string.format("Invalid buy request. Item: %s, Qty: %s", itemId, quantity), "warn")
        return
    end

    -- SERVER is the authority on price. Ignore any price sent from the client.
    local price = itemConfig.basePrice or 0
    local totalCost = price * quantity

    local hasEnoughMoney = PlayerManager.UpdateMoney(src, -totalCost, "Purchase of " .. itemId)
    if hasEnoughMoney then
        local success, message = InventoryManager.AddItem(src, itemId, quantity)
        if not success then
            -- If adding the item fails for any reason (e.g., inventory full), refund the player.
            PlayerManager.UpdateMoney(src, totalCost, "Refund for failed purchase of " .. itemId)
            SafeTriggerClientEvent('cnr:notification', src, "Purchase failed: " .. message, "error")
        else
            SafeTriggerClientEvent('cnr:notification', src, string.format("Purchased %d x %s for $%d", quantity, itemConfig.name, totalCost), "success")
        end
    end
end)

-- Secure handler for a client-side sell request.
RegisterNetEvent('cnr:sellItem')
AddEventHandler('cnr:sellItem', function(itemId, quantity)
    local src = source

    -- Server-side validation
    local itemConfig = GetItemConfig(itemId)
    quantity = tonumber(quantity)
    if not itemConfig or not quantity or quantity <= 0 then
        LogInventoryManager(src, "sell_event", string.format("Invalid sell request. Item: %s, Qty: %s", itemId, quantity), "warn")
        return
    end

    -- SERVER is the authority on price.
    -- Typically, sell price is a fraction of buy price. We'll use 50% from config or default.
    local sellPrice = itemConfig.sellPrice or (itemConfig.basePrice * 0.5)
    local totalPayout = math.floor(sellPrice * quantity)

    local success, message = InventoryManager.RemoveItem(src, itemId, quantity)
    if success then
        PlayerManager.UpdateMoney(src, totalPayout, "Sale of " .. itemId)
        SafeTriggerClientEvent('cnr:notification', src, string.format("Sold %d x %s for $%d", quantity, itemConfig.name, totalPayout), "success")
    else
        SafeTriggerClientEvent('cnr:notification', src, "Sale failed: " .. message, "error")
    end
end)


Log("[InventoryManager] Module loaded and initialized.", "info", "CNR_SERVER")
