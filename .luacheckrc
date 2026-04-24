-- Luacheck configuration for FiveM Cops and Robbers resource
std = 'lua53'
globals = {
    -- FiveM shared globals
    'AddBlipForCoord', 'AddBlipForEntity', 'AddEventHandler', 'BeginTextCommandDisplayHelp',
    'BeginTextCommandSetBlipName', 'Citizen', 'ClearGpsPlayerWaypoint', 'ClearPedTasks',
    'CloseAllMenus', 'CreateObject', 'CreatePed', 'CreateThread', 'CreateVehicle',
    'DeleteEntity', 'DeleteObject', 'DisplayHelpTextThisFrame', 'DoesBlipExist',
    'DoesEntityExist', 'DrawMarker', 'EndTextCommandDisplayHelp', 'EndTextCommandSetBlipName',
    'ExecuteCommand', 'exports', 'GetCurrentResourceName', 'GetEntityCoords',
    'GetEntityHeading', 'GetEntityMaxHealth', 'GetEntityModel', 'GetEntitySpeed',
    'GetFrameCount', 'GetGameTimer', 'GetHashKey', 'GetPedArmour', 'GetPlayerIdentifier',
    'GetPlayerIdentifiers', 'GetPlayerName', 'GetPlayerPed', 'GetPlayerPing',
    'GetPlayers', 'GetPlayerServerId', 'GetSelectedPedWeapon', 'GetVehicleClass',
    'GetVehiclePedIsIn', 'IsControlJustPressed', 'IsDuplicityVersion', 'IsEntityDead',
    'IsModelInCdimage', 'IsModelValid', 'IsPedArmed', 'IsPedDeadOrDying', 'IsPedInAnyVehicle',
    'IsPedSittingInVehicle', 'IsPlayerDead', 'json', 'NetworkGetEntityOwner',
    'NetworkGetNetworkIdFromEntity', 'NetworkGetPlayerIndexFromPed', 'NetworkHasControlOfEntity',
    'NetworkRegisterEntityAsNetworked', 'PerformHttpRequest', 'PlayerId', 'PlayerPedId',
    'RegisterCommand', 'RegisterNetEvent', 'RegisterNUICallback', 'RegisterServerEvent',
    'RemoveBlip', 'RequestModel', 'SendNUIMessage', 'SetBlipColour', 'SetBlipRoute',
    'SetBlipScale', 'SetBlipSprite', 'SetEntityAsMissionEntity', 'SetEntityCoords',
    'SetEntityHeading', 'SetEntityHealth', 'SetModelAsNoLongerNeeded', 'SetNewWaypoint',
    'SetNuiFocus', 'SetPedArmour', 'SetPedCanRagdoll', 'SetPedIntoVehicle', 'SetPedMaxHealth',
    'SetPedRelationshipGroupHash', 'SetTimeout', 'TaskCombatPed', 'TaskEnterVehicle',
    'TaskLeaveVehicle', 'TaskVehicleDriveWander', 'TerminateThread', 'TriggerClientEvent',
    'TriggerEvent', 'TriggerServerEvent', 'vector3', 'Wait', '_G', 'source',

    -- UI and notification helpers
    'BeginTextCommandThefeedPost', 'EndTextCommandThefeedPostTicker',
    'SetNotificationTextEntry', 'AddTextComponentString', 'BeginTextCommandPrint',
    'EndTextCommandPrint', 'BeginTextCommandDisplayText', 'EndTextCommandDisplayText',
    'SetTextCentre', 'SetTextColour', 'SetTextEntry', 'SetTextFont', 'SetTextOutline',
    'SetTextScale', 'SetTextWrap', 'World3dToScreen2d', 'GetScreenCoordFromWorldCoord',

    -- Resource globals
    'activeBounties', 'activeCooldowns', 'AddItem', 'AddItemToPlayerInventory',
    'AddPlayerMoney', 'AddPlayerXP', 'AddTransactionHistory', 'ApplyCharacterToPlayer',
    'ApplyPerks', 'AwardXP', 'bannedPlayers', 'CanCarryItem',
    'CheckPlayerWantedLevel', 'ClaimBounty', 'ClearPlayerNameCache', 'Config',
    'Constants', 'copsOnDuty', 'CreateHeistCrew', 'DataManager', 'DeletePlayerCharacterSlot',
    'DropPlayer', 'EquipInventoryWeapons', 'FailHeist',
    'ForceReleasePlayerFromJail', 'GetActiveBounties', 'GetBankAccount',
    'GetCharacterForRoleSelection', 'GetClientConfigItems',
    'GetCnrPlayerData', 'GetPlayerCharacterSlots', 'GetPlayerLevel',
    'GetPlayerLicense', 'GetPlayerMoney', 'GetPlayerPerk', 'GetPlayerRole',
    'GetPlayerRoleSelectionSummary',
    'InitializeBankAccount', 'InitializePlayerInventory', 'LoadBankingData',
    'LoadPlayerCharacters', 'LoadPlayerData', 'LoadResourceFile', 'Log',
    'MarkPlayerForInventorySave', 'MemoryManager', 'MinimizeInventoryForSync',
    'PerformanceManager', 'PerformanceOptimizer', 'PerformanceTest', 'PlaceBounty',
    'PlayerManager', 'playersData', 'playersSavePending',
    'playerDeployedSpikeStripsCount', 'ProcessHeistStages', 'purchaseHistory',
    'RemoveItem', 'RemoveItemFromPlayerInventory', 'RemovePlayerMoney',
    'ResetDailyWithdrawals', 'RewardArrestXP', 'RewardEscapeXP',
    'RewardHeistXP', 'SafeGetPlayerIdentifiers', 'SafeGetPlayerName',
    'SafeTriggerClientEvent', 'SanitizeCharacterData', 'SaveBankingData',
    'SavePlayerCharacterSlot', 'SavePlayerData', 'SavePlayerDataImmediate',
    'SavePlayerCharacters', 'SaveResourceFile', 'SecureInventory',
    'SecureTransactions', 'SecurityEnhancements', 'SecurityTest',
    'SetPlayerRole', 'shallowcopy', 'SystemTest', 'tablelength',
    'TriggerAbilityEffect', 'UpdateFullInventory', 'UpdatePlayerNameCache',
    'ValidateCharacterData', 'Validation', 'Version', 'jail', 'k9Engagements',
    'robbersActive', 'wantedPlayers', 'HasCharacterForRole', 'IsAdmin',
    'IsPlayerAceAllowed', 'IsPlayerAdmin', 'IsPlayerCop', 'IsPlayerRobber',
    'GetPlayerInventory', 'GetVehicleEngineHealth',

    -- fxmanifest DSL
    'author', 'client_scripts', 'dependencies', 'description', 'export', 'files',
    'fx_version', 'game', 'name', 'server_export', 'server_scripts', 'shared_scripts',
    'ui_page', 'version'
}
ignore = {
    '212', -- Unused argument
    '213', -- Unused loop variable
    '631'  -- Line is too long
}
