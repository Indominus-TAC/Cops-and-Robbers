fx_version 'cerulean'
game 'gta5'

name 'Cops and Robbers - Refactored'
description 'An immersive Cops and Robbers game mode with a modular, manager-based architecture.'
author 'The Axiom Collective'
version '2.0.0'

-- Define shared scripts, loaded first on both server and client.
-- These provide foundational utilities and configurations.
shared_scripts {
    'version.lua',
    'config.lua',
    'constants.lua',
}

-- Define server-side scripts. The order is critical for correct dependency resolution.
server_scripts {
    -- 1. Utilities (no dependencies)
    'utils/log_utils.lua',
    'utils/safe_utils.lua',

    -- 2. Core Managers (must be loaded before gameplay logic)
    'data_manager.lua',
    'security_manager.lua',
    'player_manager.lua',
    'inventory_manager.lua',
    'wanted_manager.lua',
    'jail_manager.lua',
    'progression_manager.lua',
    'heist_manager.lua',
    'bounty_manager.lua',
    
    -- 3. Main Server Logic (depends on all managers)
    'server.lua',
}

-- Define client-side scripts.
client_scripts {
    'client.lua',
}

-- Define the NUI page.
ui_page 'html/main_ui.html'

-- Define files to be included with the resource.
files {
    'html/main_ui.html',
    'html/styles.css',
    'html/scripts.js',
    -- Note: player_data, bans.json etc. are now handled by the DataManager
    -- and do not need to be explicitly listed here for client access.
}

-- Declare resource dependencies, if any.
dependencies {
}

-- Exports for interoperability with other resources.
exports {
    'GetPlayerData',
    'UpdateMoney',
    'GetPlayerRole',
    'SetPlayerRole'
}
