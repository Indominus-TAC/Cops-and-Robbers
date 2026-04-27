// html/scripts.js
// Handles NUI interactions for Cops and Robbers game mode.

const CNRConfig = {
    resourceName: null,
    isInitialized: false,
    getResourceName() {
        if (!this.isInitialized) {
            console.warn('Resource name accessed before initialization');
        }
        return this.resourceName || 'unknown-resource';
    },
    init(name) {
        this.resourceName = name;
        this.isInitialized = true;
        console.log(`Resource name initialized: ${name}`);
    }
};
window.CNRConfig = CNRConfig;

if (typeof GetParentResourceName === 'function') {
    const parentResourceName = GetParentResourceName();
    if (parentResourceName) {
        CNRConfig.init(parentResourceName);
    }
}

window.fullItemConfig = null; // Will store Config.Items

// Inventory state variables
window.isInventoryOpen = window.isInventoryOpen || false;
let currentInventoryData = null;
let currentEquippedItems = null;

// Character Editor state variables
let characterEditorData = {
    isOpen: false,
    currentRole: null,
    currentSlot: 1,
    characterData: {},
    uniformPresets: [],
    customizationRanges: {},
    selectedUniformPreset: null,
    selectedCharacterSlot: null
};

// Jail Timer UI elements
const jailTimerContainer = document.getElementById('jail-timer-container');
const jailTimeRemainingElement = document.getElementById('jail-time-remaining');

// ====================================================================
// NUI Message Handling & Security
// ====================================================================
const allowedOrigins = [
    `nui://cops-and-robbers`,
    "http://localhost:3000", // For local development if applicable
    "nui://game" // General game NUI origin
];

window.addEventListener('message', function(event) {
    const currentResourceOrigin = `nui://${CNRConfig.getResourceName()}`;
    if (!allowedOrigins.includes(event.origin) && event.origin !== currentResourceOrigin) {
        console.warn(`Security: Received message from untrusted origin: ${event.origin}. Expected: ${currentResourceOrigin} or predefined. Ignoring.`);
        return;
    }
  
    const data = event.data;
    
    // Validate message data
    if (!data || typeof data !== 'object') {
        console.error('[CNR_NUI] Invalid message data received:', data);
        return;
    }

    if (data.resourceName) {
        CNRConfig.init(data.resourceName);
        const dynamicOrigin = `nui://${CNRConfig.getResourceName()}`;
        if (!allowedOrigins.includes(dynamicOrigin)) {
            allowedOrigins.push(dynamicOrigin);
        }
    }
    
    const action = data.action || data.type;

    // Ensure action is defined
    if (!action || typeof action !== 'string') {
        console.error('[CNR_NUI] Message missing or invalid action/type field:', data);
        return;
    }
  
    switch (action) {
        case 'showRoleSelection':
            if (data.resourceName) {
                CNRConfig.init(data.resourceName);
                if (!allowedOrigins.includes(`nui://${CNRConfig.getResourceName()}`)) {
                    allowedOrigins.push(`nui://${CNRConfig.getResourceName()}`);
                }
            }
            showRoleSelection();
            break;        case 'updateMoney':
            // Update cash display dynamically when money changes
            if (typeof data.cash === 'number') {
                const playerCashEl = document.getElementById('player-cash-amount');
                if (playerCashEl) {
                    playerCashEl.textContent = `$${data.cash.toLocaleString()}`;
                }
                
                // Show cash notification if cash changed and store is open
                const storeMenuElement = document.getElementById('store-menu');
                if (storeMenuElement && storeMenuElement.style.display === 'block' && previousCash !== null && previousCash !== data.cash) {
                    showCashNotification(data.cash, previousCash);
                }
                
                // Update stored values
                previousCash = data.cash;
                if (window.playerInfo) {
                    window.playerInfo.cash = data.cash;
                }
            }
            break;
        case 'showStoreMenu':
        case 'openStore':
            if (data.resourceName) {
                CNRConfig.init(data.resourceName);
                const currentResourceOriginDynamic = `nui://${CNRConfig.getResourceName()}`;
                if (!allowedOrigins.includes(currentResourceOriginDynamic)) {
                    allowedOrigins.push(currentResourceOriginDynamic);
                }
            }
            openStoreMenu(data.storeName, data.items, data.playerInfo);
            break;        case 'updateStoreData':
            if (data.items && data.items.length > 0) {
                // Update the current store data
                window.items = normalizeStoreItems(data.items); // Fix: Set window.items so loadGridItems() can access it
                window.currentStoreItems = window.items;
                loadCategories();
                window.playerInfo = data.playerInfo; // Fix: Set window.playerInfo for level checks
                window.currentPlayerInfo = data.playerInfo;
                // Refresh the currently displayed tab
                if (window.currentTab === 'buy') {
                    loadGridItems(); // Fix: Call without parameters
                } else if (window.currentTab === 'sell') {
                    loadSellItems();
                }
            } else {
                console.warn('[CNR_NUI] updateStoreData called with no items or empty items array');
            }
            break;
        case 'buyResult':
            if (data.success) {
                showToast(data.message || 'Purchase successful!', 'success');
                // Refresh the sell tab in case new items were added to inventory
                if (window.currentTab === 'sell') {
                    loadSellItems();
                }
            } else {
                showToast(data.message || 'Purchase failed!', 'error');
            }
            break;
        case 'sellResult':
            if (data.success) {
                showToast(data.message || 'Sale successful!', 'success');
                // Refresh the sell tab to update inventory
                if (window.currentTab === 'sell') {
                    loadSellItems();
                }
            } else {
                showToast(data.message || 'Sale failed!', 'error');
            }
            break;
        case 'closeStore':
            closeStoreMenu();
            break;
        case 'startHeistTimer':
            startHeistTimer(data.duration, data.bankName);
            break;        case 'updateXPBar':
            updateXPDisplayElements(data.currentXP, data.currentLevel, data.xpForNextLevel, data.xpGained);
            break;
        case 'refreshSellListIfNeeded':
            const storeMenu = document.getElementById('store-menu');
            if (storeMenu && storeMenu.style.display === 'block' && window.currentTab === 'sell') {
                loadSellItems();
            }
            break;
        case 'showAdminPanel':
            if (data.resourceName) {
                CNRConfig.init(data.resourceName);
                 if (!allowedOrigins.includes(`nui://${CNRConfig.getResourceName()}`)) {
                    allowedOrigins.push(`nui://${CNRConfig.getResourceName()}`);
                }
            }
            showAdminPanel(data.players, data.liveMapData || null);
            break;        case 'showBountyBoard':
            if (data.resourceName) {
                CNRConfig.init(data.resourceName);
                if (!allowedOrigins.includes(`nui://${CNRConfig.getResourceName()}`)) {
                    allowedOrigins.push(`nui://${CNRConfig.getResourceName()}`);
                }
            }
            if (typeof showBountyBoardUI === 'function') showBountyBoardUI(data.bounties);
            break;
        case 'hideBountyBoard':
             if (typeof hideBountyBoardUI === 'function') hideBountyBoardUI();
            break;
        case 'updateBountyList':
             if (typeof updateBountyListUI === 'function') updateBountyListUI(data.bounties);
            break;        case 'showBountyList':
            showBountyList(data.bounties || []);
            break;
        case 'updateSpeedometer':
            updateSpeedometer(data.speed);
            break;
        case 'toggleSpeedometer':
            toggleSpeedometer(data.show);
            break;
        case 'hideRoleSelection':
            hideRoleSelection();
            break;
        case 'roleSelectionFailed':
            showToast(data.error || 'Failed to select role. Please try again.', 'error', 4000);
            showRoleSelection();
            break;
        case 'storeFullItemConfig':
            if (data.itemConfig) {
                const rawItemConfig = data.itemConfig;
                window.fullItemConfig = {};

                if (Array.isArray(rawItemConfig)) {
                    rawItemConfig.forEach((item) => {
                        if (item && item.itemId) {
                            window.fullItemConfig[item.itemId] = item;
                        }
                    });
                } else {
                    window.fullItemConfig = rawItemConfig;
                }
                
                // Keep configured images only. Missing files spam NUI logs, so use icons as the fallback.
                for (const itemId in window.fullItemConfig) {
                    if (window.fullItemConfig.hasOwnProperty(itemId)) {
                        const item = window.fullItemConfig[itemId];
                        item.itemId = item.itemId || itemId;
                        item.icon = item.icon || getItemIcon(item);

                        if (!item.image || item.image.includes('404') || item.image === 'img/default.png' || item.image === 'img/items/default.png') {
                            item.image = null;
                        }
                    }
                }
                
                // Refresh the store if it's open
                const storeMenuElement = document.getElementById('store-menu');
                if (storeMenuElement && storeMenuElement.style.display === 'block') {
                    if (window.currentTab === 'buy') {
                        loadGridItems();
                    } else if (window.currentTab === 'sell') {
                        loadSellItems();
                    }
                }
            }
            break;        case 'refreshInventory':
            // Refresh the sell tab if it's currently active
            const storeMenuElement = document.getElementById('store-menu');
            if (storeMenuElement && storeMenuElement.style.display === 'block' && window.currentTab === 'sell') {
                loadSellItems();
            }
            break;        case 'showWantedNotification':
            showWantedNotification(data.stars, data.points, data.level);
            break;        case 'hideWantedNotification':
            hideWantedNotification();
            break;
        case 'openInventory':
        case 'closeInventory':
        case 'updateInventory':
        case 'updateEquippedItems':
            handleInventoryMessage(data);
            break;
        case 'showRobberMenu':
            showRobberMenu();
            break;
        case 'showPoliceMenu':
            showPoliceMenu(data);
            break;
        case 'showPdGarageMenu':
            showPdGarageMenu(data.garage || data);
            break;
        case 'hideRoleActionMenus':
            hideRoleActionMenus();
            break;
        case 'updatePoliceCadData':
            updatePoliceCadData(data.cadData || {}, data.citationReasons || []);
            break;
        case 'updateAdminLiveMapData':
            updateAdminLiveMapData(data.liveMapData || {});
            break;
        case 'updateBankingDetails':
            if (bankingSystem) {
                bankingSystem.updateBankingDetails(data.details || {});
            }
            break;
        // Jail Timer UI Logic
        case 'showJailTimer':
            if (jailTimerContainer && jailTimeRemainingElement) {
                jailTimeRemainingElement.textContent = formatJailTime(data.initialTime || 0);
                jailTimerContainer.classList.remove('hidden');
            } else {
            }
            break;
        case 'updateJailTimer':
            if (jailTimerContainer && jailTimeRemainingElement && !jailTimerContainer.classList.contains('hidden')) {
                jailTimeRemainingElement.textContent = formatJailTime(data.time || 0);
            }
            break;
        case 'hideJailTimer':
            if (jailTimerContainer) {
                jailTimerContainer.classList.add('hidden');
            }
            break;
        case 'openCharacterEditor':
            openCharacterEditor(data);
            break;
        case 'closeCharacterEditor':
            closeCharacterEditor();
            break;
        case 'updateCharacterSlot':
            updateCharacterSlot(data.characterKey, data.characterData);
            break;
        case 'syncCharacterEditorData':
            characterEditorData.characterData = data.characterData || {};
            if (Array.isArray(data.uniformPresets)) {
                characterEditorData.uniformPresets = data.uniformPresets;
            }
            if (window.enhancedCharacterEditor) {
                if (Array.isArray(data.uniformPresets)) {
                    window.enhancedCharacterEditor.syncUniformPresets(data.uniformPresets);
                }
                window.enhancedCharacterEditor.syncCharacterData(data.characterData || {});
            }
            break;
        case 'testCharacterEditor':
            const testEditor = document.getElementById('character-editor-container');
            if (testEditor) {
                console.log('[CNR_CHARACTER_EDITOR] Character editor element found');
                fetch(`https://${CNRConfig.getResourceName()}/characterEditor_test_result`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ 
                        success: true, 
                        message: 'Character editor element found',
                        elementFound: true
                    })
                });
            } else {
                console.error('[CNR_CHARACTER_EDITOR] Character editor element NOT found');
                fetch(`https://${CNRConfig.getResourceName()}/characterEditor_test_result`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ 
                        success: false, 
                        message: 'Character editor element missing',
                        elementFound: false
                    })
                });
            }
            break;
        case 'hideWantedUI':
            // Hide wanted level UI elements
            const wantedContainer = document.getElementById('wanted-container');
            const wantedLevel = document.getElementById('wanted-level');
            const wantedStars = document.getElementById('wanted-stars');
            
            if (wantedContainer) {
                wantedContainer.style.display = 'none';
            }
            if (wantedLevel) {
                wantedLevel.style.display = 'none';
            }
            if (wantedStars) {
                wantedStars.style.display = 'none';
            }
            
            break;
        case 'showWantedUI':
            // Show wanted level UI elements
            const wantedContainerShow = document.getElementById('wanted-container');
            const wantedLevelShow = document.getElementById('wanted-level');
            const wantedStarsShow = document.getElementById('wanted-stars');
            
            if (wantedContainerShow) {
                wantedContainerShow.style.display = 'block';
            }
            if (wantedLevelShow) {
                wantedLevelShow.style.display = 'block';
                // Update wanted level if provided
                if (data.wantedLevel !== undefined) {
                    wantedLevelShow.textContent = data.wantedLevel + ' Star' + (data.wantedLevel !== 1 ? 's' : '');
                }
            }
            if (wantedStarsShow) {
                wantedStarsShow.style.display = 'block';
                // Update stars display if provided
                if (data.wantedLevel !== undefined) {
                    let starsHtml = '';
                    for (let i = 0; i < Math.min(data.wantedLevel, 5); i++) {
                        starsHtml += '★';
                    }
                    wantedStarsShow.innerHTML = starsHtml;
                }
            }
            
            break;
        default:
            if (window.Config && window.Config.JSDebugLogging) {
                console.warn(`[CNR_NUI] Unhandled NUI action: "${data.action}" with data:`, data);
            }
    }
});

// Helper function to format seconds into MM:SS
function formatJailTime(totalSeconds) {
    if (isNaN(totalSeconds) || totalSeconds < 0) {
        totalSeconds = 0;
    }
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function dataNumber(...values) {
    for (const value of values) {
        const numberValue = Number(value);
        if (Number.isFinite(numberValue)) {
            return numberValue;
        }
    }
    return 0;
}

// NUI Focus Helper Function (remains unchanged)
async function fetchSetNuiFocus(hasFocus, hasCursor) {
    try {
        const resName = CNRConfig.getResourceName();
        await fetch(`https://${resName}/setNuiFocus`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ hasFocus: hasFocus, hasCursor: hasCursor })
        });
    } catch (error) {
        const resNameForError = CNRConfig.getResourceName();
        console.error(`Error calling setNuiFocus NUI callback (URL attempted: https://${resNameForError}/setNuiFocus):`, error);
    }
}

// Enhanced XP Display with Animation and Auto-Hide
let xpDisplayTimeout;
let currentXP = 0;
let currentLevel = 1;
let currentNextLvlXP = 100;
let roleSelectionPending = false;

function updateXPDisplayElements(xp, level, nextLvlXp, xpGained = null) {
    const levelTextElement = document.getElementById('level-text');
    const xpTextElement = document.getElementById('xp-text');
    const xpBarFillElement = document.getElementById('xp-bar-fill');
    const xpLevelContainer = document.getElementById('xp-level-container');
    const xpGainIndicator = document.getElementById('xp-gain-indicator');

    // Store previous values to detect changes
    const previousXP = currentXP;
    const previousLevel = currentLevel;
    
    // Update current values
    currentXP = xp;
    currentLevel = level;
    currentNextLvlXP = nextLvlXp;

    // Calculate XP gained if not provided
    if (xpGained === null && previousXP !== 0) {
        xpGained = currentXP - previousXP;
    }    // Only show XP bar if there's actual XP gain or level change
    const shouldShow = xpGained !== null && (xpGained > 0 || previousLevel !== currentLevel);
    
    if (!shouldShow) {
        if (window.Config && window.Config.JSDebugLogging) {
            console.log('[CNR_NUI] No XP change detected, not showing XP bar');
        }
        return;
    }

    // Show XP bar with slide-in animation
    if (xpLevelContainer) {
        xpLevelContainer.style.display = 'flex';
        xpLevelContainer.classList.remove('hide');
        xpLevelContainer.classList.add('show');
        if (window.Config && window.Config.JSDebugLogging) {
            console.log('[CNR_NUI] Showing XP bar with animation');
        }
    }

    // Update level text with animation if level changed
    if (levelTextElement) {
        if (level !== previousLevel && previousLevel !== 0) {
            // Level up animation
            levelTextElement.style.transition = 'transform 0.5s ease-out, color 0.5s ease-out';
            levelTextElement.style.transform = 'scale(1.2)';
            levelTextElement.style.color = '#4CAF50';
            setTimeout(() => {
                levelTextElement.style.transform = 'scale(1)';
                levelTextElement.style.color = '#e94560';
            }, 500);
            if (window.Config && window.Config.JSDebugLogging) {
                console.log(`[CNR_NUI] Level up animation: ${previousLevel} -> ${level}`);
            }
        }
        levelTextElement.textContent = "LVL " + level;
    }

    // Update XP text
    if (xpTextElement) {
        xpTextElement.textContent = xp + " / " + nextLvlXp + " XP";
    }

    // Animate XP bar fill
    if (xpBarFillElement) {
        let percentage = 0;
        if (typeof nextLvlXp === 'number' && nextLvlXp > 0 && xp < nextLvlXp) {
            percentage = (xp / nextLvlXp) * 100;
        } else if (typeof nextLvlXp !== 'number' || xp >= nextLvlXp) {
            percentage = 100;
        }
        
        // Smooth animation to new percentage
        setTimeout(() => {
            xpBarFillElement.style.width = Math.max(0, Math.min(100, percentage)) + '%';
            if (window.Config && window.Config.JSDebugLogging) {
                console.log(`[CNR_NUI] XP bar animated to ${percentage.toFixed(1)}%`);
            }
        }, 200);
    }

    // Show XP gain indicator if XP was gained
    if (xpGained && xpGained > 0 && xpGainIndicator) {
        xpGainIndicator.textContent = `+${xpGained} XP`;
        xpGainIndicator.style.display = 'block';
        xpGainIndicator.classList.remove('show');
        // Force reflow to restart animation
        xpGainIndicator.offsetHeight;
        xpGainIndicator.classList.add('show');
        
        if (window.Config && window.Config.JSDebugLogging) {
            console.log(`[CNR_NUI] Showing +${xpGained} XP indicator`);
        }
        
        // Remove animation class after animation completes
        setTimeout(() => {
            xpGainIndicator.classList.remove('show');
            xpGainIndicator.style.display = 'none';
        }, 3000);
    }

    // Clear existing timeout
    if (xpDisplayTimeout) {
        clearTimeout(xpDisplayTimeout);
    }

    // Set new timeout to hide XP bar after 10 seconds
    xpDisplayTimeout = setTimeout(() => {
        if (xpLevelContainer) {
            xpLevelContainer.classList.remove('show');
            xpLevelContainer.classList.add('hide');
            
            if (window.Config && window.Config.JSDebugLogging) {
                console.log('[CNR_NUI] Hiding XP bar after 10 seconds');
            }
            
            // Actually hide the element after animation
            setTimeout(() => {
                if (xpLevelContainer.classList.contains('hide')) {
                    xpLevelContainer.style.display = 'none';
                    xpLevelContainer.classList.remove('hide');
                }
            }, 500);
        }
    }, 10000);
}

function showToast(message, type = 'info', duration = 3000) {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = message;
    toast.className = 'toast-notification';
    if (type === 'success') toast.classList.add('success');
    else if (type === 'error') toast.classList.add('error');

    toast.style.display = 'block';
    const fadeOutDelay = duration - 500;
    toast.style.animation = `fadeInNotification 0.5s ease-out, fadeOutNotification 0.5s ease-in ${fadeOutDelay > 0 ? fadeOutDelay : 0}ms forwards`;

    setTimeout(() => {
        toast.style.display = 'none';
        toast.style.animation = '';    }, duration);
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function formatCurrencyDisplay(value) {
    const numericValue = Number(value);
    if (!Number.isFinite(numericValue)) {
        return '0';
    }

    return Math.round(numericValue).toLocaleString();
}

function showRoleSelection() {
    const roleSelectionUI = document.getElementById('role-selection');
    if (roleSelectionUI) {
        roleSelectionPending = false;
        roleSelectionUI.querySelectorAll('button[data-role]').forEach((button) => {
            button.disabled = false;
        });
        document.body.style.display = 'block';
        document.body.style.visibility = 'visible';
        roleSelectionUI.classList.remove('hidden');
        roleSelectionUI.style.display = '';
        roleSelectionUI.style.visibility = 'visible';
        document.body.style.backgroundColor = '';
        fetchSetNuiFocus(true, true);
    }
}
function hideRoleSelection() {
    if (window.Config && window.Config.JSDebugLogging) {
        console.log('[CNR_NUI_ROLE] hideRoleSelection called.');
    }
    const roleSelectionUI = document.getElementById('role-selection');
    if (roleSelectionUI) {
        // Force blur on any active NUI element
        if (document.activeElement && typeof document.activeElement.blur === 'function') {
            document.activeElement.blur();
            if (window.Config && window.Config.JSDebugLogging) {
                console.log('[CNR_NUI_ROLE] Blurred active NUI element.');
            }
        }

        roleSelectionUI.classList.add('hidden');
        roleSelectionUI.style.display = 'none'; 
        roleSelectionUI.style.visibility = 'hidden'; // Explicitly set visibility
        roleSelectionPending = false;
        roleSelectionUI.querySelectorAll('button[data-role]').forEach((button) => {
            button.disabled = false;
        });
        if (window.Config && window.Config.JSDebugLogging) {
            console.log('[CNR_NUI_ROLE] roleSelectionUI display set to none and visibility to hidden. Current display:', roleSelectionUI.style.display, 'Visibility:', roleSelectionUI.style.visibility);
        }

        document.body.style.backgroundColor = 'transparent';

        // Temporarily comment out the NUI-side focus call to rely on Lua's SetNuiFocus
        // console.log('[CNR_NUI_ROLE] Attempting fetchSetNuiFocus(false, false) from hideRoleSelection...');
        // fetchSetNuiFocus(false, false);
        // console.log('[CNR_NUI_ROLE] fetchSetNuiFocus(false, false) call from hideRoleSelection TEMPORARILY DISABLED.');
        if (window.Config && window.Config.JSDebugLogging) {
            console.log('[CNR_NUI_ROLE] NUI part of hideRoleSelection complete. Lua (SetNuiFocus) should now take full effect.');
        }

    } else {
        console.error('[CNR_NUI_ROLE] role-selection UI element not found in hideRoleSelection.');
    }
}
function openStoreMenu(storeName, storeItems, playerInfo) {
    if (window.Config && window.Config.JSDebugLogging) {
        console.log('[CNR_NUI_DEBUG] openStoreMenu called with:', { storeName, storeItems, playerInfo });
    }
    
    const storeMenuUI = document.getElementById('store-menu');
    const storeTitleEl = document.getElementById('store-title');
    const playerCashEl = document.getElementById('player-cash-amount');
    const playerLevelEl = document.getElementById('player-level-text');
    
    if (storeMenuUI && storeTitleEl) {
        storeTitleEl.textContent = storeName || 'Store';
        window.items = normalizeStoreItems(storeItems || []);
        
        playerInfo = playerInfo || {
            cash: dataNumber(window.playerInfo?.cash, window.currentPlayerInfo?.cash, previousCash, 0),
            level: dataNumber(window.playerInfo?.level, window.currentPlayerInfo?.level, 1),
            role: window.playerInfo?.role || window.currentPlayerInfo?.role || 'citizen'
        };

        // Better handling of undefined playerInfo
        if (!playerInfo) {
            console.warn('[CNR_NUI_WARNING] No playerInfo provided to openStoreMenu, using fallback');
            window.playerInfo = { level: 1, role: "citizen", cash: 0 };
        } else {
            window.playerInfo = playerInfo;
        }
        
        if (window.Config && window.Config.JSDebugLogging) {
            console.log('[CNR_NUI_DEBUG] playerInfo received:', window.playerInfo);
        }
        
        // Handle both property name formats (cash/playerCash, level/playerLevel)
        const newCash = window.playerInfo.cash || window.playerInfo.playerCash || 0;
        const newLevel = window.playerInfo.level || window.playerInfo.playerLevel || 1;
        
        if (window.Config && window.Config.JSDebugLogging) {
            console.log('[CNR_NUI_DEBUG] cash value:', newCash);
            console.log('[CNR_NUI_DEBUG] level value:', newLevel);
        }
        
        // Debug log for level display issues
        if (newLevel === 1 && playerInfo && playerInfo.level && playerInfo.level !== 1) {
            console.error('[CNR_NUI_ERROR] Level fallback triggered! Original level:', playerInfo.level, 'but showing:', newLevel);
        }
        
        // Update player info display and check for cash changes
        if (playerCashEl) {
            playerCashEl.textContent = `$${newCash.toLocaleString()}`;
            if (window.Config && window.Config.JSDebugLogging) {
                console.log('[CNR_NUI_DEBUG] Updated cash display to:', `$${newCash.toLocaleString()}`);
            }
        }
        if (playerLevelEl) {
            playerLevelEl.textContent = `Level ${newLevel}`;
            if (window.Config && window.Config.JSDebugLogging) {
                console.log('[CNR_NUI_DEBUG] Updated level display to:', `Level ${newLevel}`);
            }
        }
          // Show cash notification if cash changed (only when store is opened)
        if (previousCash !== null && previousCash !== newCash) {
            console.log('[CNR_NUI_DEBUG] Cash changed in store from', previousCash, 'to', newCash);
            showCashNotification(newCash, previousCash);
        }
        previousCash = newCash;
        
        window.currentCategory = null;
        window.currentTab = 'buy';
        setStoreTab('buy');
        loadCategories();
        loadGridItems();
        storeMenuUI.style.display = 'block';
        storeMenuUI.classList.remove('hidden');
        fetchSetNuiFocus(true, true);
    }
}

function normalizeStoreItems(storeItems) {
    if (!Array.isArray(storeItems)) {
        return [];
    }

    return storeItems.map((item) => {
        if (typeof item === 'string') {
            const configItem = window.fullItemConfig && window.fullItemConfig[item];
            if (configItem) {
                return {
                    ...configItem,
                    itemId: configItem.itemId || item,
                    price: configItem.price || configItem.basePrice || 0
                };
            }

            return null;
        }

        return item;
    }).filter(Boolean);
}

function setStoreTab(tabName) {
    const storeMenu = document.getElementById('store-menu');
    if (!storeMenu) return;

    window.currentTab = tabName;

    storeMenu.querySelectorAll('#tab-menu .tab-btn').forEach((button) => {
        const isActive = button.dataset.tab === tabName;
        button.classList.toggle('active', isActive);
        button.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });

    storeMenu.querySelectorAll('#buy-section, #sell-section').forEach((content) => {
        content.classList.remove('active');
    });

    const activeTabContent = storeMenu.querySelector(`#${tabName}-section`);
    if (activeTabContent) {
        activeTabContent.classList.add('active');
    }
}

function closeStoreMenu() {
    const storeMenuUI = document.getElementById('store-menu');
    if (storeMenuUI) {
        storeMenuUI.classList.add('hidden');
        storeMenuUI.style.display = '';
        
        // Notify Lua client that store is closing
        const resName = CNRConfig.getResourceName();
        fetch(`https://${resName}/closeStore`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(error => {
            console.error('Error calling closeStore callback:', error);
        });
        
        fetchSetNuiFocus(false, false);
    }
}

// Store Tab and Category Management
document.querySelectorAll('#store-menu #tab-menu .tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        setStoreTab(btn.dataset.tab);
        if (window.currentTab === 'sell') loadSellGridItems();
        else loadGridItems();
    });
});

function loadCategories() {
    const categoryList = document.getElementById('category-list');
    if (!categoryList) return;
    const categories = [...new Set((window.items || []).map(item => item.category))];
    categoryList.innerHTML = '';
    
    const allBtn = document.createElement('button');
    allBtn.className = 'category-btn active';
    allBtn.textContent = 'All';
    allBtn.onclick = () => {
        window.currentCategory = null;
        categoryList.querySelectorAll('.category-btn').forEach(b => b.classList.remove('active'));
        allBtn.classList.add('active');
        if (window.currentTab === 'buy') loadGridItems();
    };
    categoryList.appendChild(allBtn);
    
    categories.forEach(category => {
        const btn = document.createElement('button');
        btn.className = 'category-btn';
        btn.textContent = category;
        btn.onclick = () => {
            window.currentCategory = category;
            categoryList.querySelectorAll('.category-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            if (window.currentTab === 'buy') loadGridItems();
        };
        categoryList.appendChild(btn);
    });
}

// New Grid-Based Item Loading
function loadGridItems() {
    const gridContainer = document.getElementById('inventory-grid');
    if (!gridContainer) {
        console.error('[CNR_NUI_DEBUG] inventory-grid element not found!');
        return;
    }
    
    // Clear existing items
    gridContainer.innerHTML = '';
      console.log('[CNR_NUI_DEBUG] loadGridItems called. Items count:', window.items ? window.items.length : 0);
    console.log('[CNR_NUI_DEBUG] currentCategory:', window.currentCategory);
    console.log('[CNR_NUI_DEBUG] currentTab:', window.currentTab);
    console.log('[CNR_NUI_DEBUG] Sample items:', window.items ? window.items.slice(0, 3).map(item => ({id: item.itemId, name: item.name})) : 'No items');
    
    // If items is an object rather than an array, convert it to an array
    let itemsArray = window.items || [];
    if (!Array.isArray(itemsArray) && typeof itemsArray === 'object') {
        itemsArray = Object.keys(itemsArray).map(key => itemsArray[key]);
    }
    
    // Filter by category if one is selected
    if (window.currentCategory) {
        itemsArray = itemsArray.filter(item => item.category === window.currentCategory);
        console.log('[CNR_NUI_DEBUG] Filtered items by category', window.currentCategory, ':', itemsArray.length);
    }
    
    if (itemsArray.length === 0) {
        console.log('[CNR_NUI_DEBUG] No items to render, showing empty message');
        gridContainer.innerHTML = '<div style="grid-column: 1 / -1; text-align: center; color: rgba(255,255,255,0.6); padding: 40px;">No items available.</div>';
        return;
    }
    
    const fragment = document.createDocumentFragment();
    
    itemsArray.forEach((item, index) => {
        if (!item) {
            console.error('[CNR_NUI_DEBUG] Null item at index', index);
            return;
        }
        
        if (!item.itemId) {
            console.warn('[CNR_NUI_DEBUG] Item missing itemId at index', index, 'attempting to fix...', item);
            item.itemId = item.name ? item.name.toLowerCase().replace(/\s+/g, '_') : 'unknown_item_' + index;
        }
        
        if (!item.name) {
            item.name = item.itemId;
        }
        
        const slot = createInventorySlot(item, 'buy');
        if (slot) {
            fragment.appendChild(slot);
        }
    });
    
    gridContainer.appendChild(fragment);
    console.log('[CNR_NUI_DEBUG] Rendered', itemsArray.length, 'items to grid');
    console.log('[CNR_NUI_DEBUG] Grid container children count:', gridContainer.children.length);
}

function loadSellGridItems() {
    const sellGrid = document.getElementById('sell-inventory-grid');
    if (!sellGrid) {
        console.error('[CNR_NUI] sell-inventory-grid element not found!');
        return;
    }
    
    console.log('[CNR_NUI] Loading sell grid items...');
    
    // Show loading state
    sellGrid.innerHTML = '<div style="grid-column: 1 / -1; text-align: center; color: rgba(255,255,255,0.6); padding: 40px;">Loading inventory...</div>';
    
    // Fetch player inventory from server
    const resName = CNRConfig.getResourceName();
    console.log('[CNR_NUI] Fetching inventory from resource:', resName);
    
    fetch(`https://${resName}/getPlayerInventory`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).then(response => {
        console.log('[CNR_NUI] Received response from getPlayerInventory:', response.status);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response.json();    }).then(data => {
        console.log('[CNR_NUI] Inventory data received:', data);
        sellGrid.innerHTML = '';
        let minimalInventory = data.inventory || []; // Server returns { inventory: [...] }
        
        // Convert object to array if necessary (for backward compatibility)
        if (typeof minimalInventory === 'object' && !Array.isArray(minimalInventory)) {
            console.log('[CNR_NUI] Converting inventory object to array format');
            const inventoryArray = [];
            for (const [itemId, itemData] of Object.entries(minimalInventory)) {
                if (itemData && itemData.count > 0) {
                    inventoryArray.push({
                        itemId: itemId,
                        count: itemData.count
                    });
                }
            }
            minimalInventory = inventoryArray;
        }
        
        if (!window.fullItemConfig) {
            console.error('[CNR_NUI] fullItemConfig not available. Cannot reconstruct sell list details.');
            console.log('[CNR_NUI] fullItemConfig is:', window.fullItemConfig);
            sellGrid.innerHTML = '<div style="grid-column: 1 / -1; text-align: center; color: rgba(255,255,255,0.6); padding: 40px;">Error: Item configuration not loaded. Please try reopening the store.</div>';
            return;
        }
        
        console.log('[CNR_NUI] Processing', Array.isArray(minimalInventory) ? minimalInventory.length : 'unknown', 'inventory items');
        console.log('[CNR_NUI] fullItemConfig type:', typeof window.fullItemConfig, 'has items:', window.fullItemConfig ? Object.keys(window.fullItemConfig).length : 0);
        
        if (!minimalInventory || !Array.isArray(minimalInventory) || minimalInventory.length === 0) {
            sellGrid.innerHTML = '<div style="grid-column: 1 / -1; text-align: center; color: rgba(255,255,255,0.6); padding: 40px;">Your inventory is empty.</div>';
            return;
        }
        
        const fragment = document.createDocumentFragment();
        let itemsProcessed = 0;
        
        minimalInventory.forEach(minItem => {
            if (minItem && minItem.count > 0) {
                // Look up full item details from config
                let itemDetails = null;
                
                if (Array.isArray(window.fullItemConfig)) {
                    // If fullItemConfig is an array
                    itemDetails = window.fullItemConfig.find(configItem => configItem.itemId === minItem.itemId);
                } else if (typeof window.fullItemConfig === 'object' && window.fullItemConfig !== null) {
                    // If fullItemConfig is an object
                    itemDetails = window.fullItemConfig[minItem.itemId];
                }
                
                if (itemDetails) {
                    // Calculate sell price (50% of base price by default)
                    let sellPrice = Math.floor((itemDetails.price || itemDetails.basePrice || 0) * 0.5);
                    
                    // Apply dynamic economy if available
                    if (window.cnrDynamicEconomySettings && window.cnrDynamicEconomySettings.enabled && typeof window.cnrDynamicEconomySettings.sellPriceFactor === 'number') {
                        sellPrice = Math.floor((itemDetails.price || itemDetails.basePrice || 0) * window.cnrDynamicEconomySettings.sellPriceFactor);
                    }
                    
                    const richItem = {
                        itemId: minItem.itemId,
                        name: itemDetails.name || minItem.itemId,
                        count: minItem.count,
                        category: itemDetails.category || 'Miscellaneous',
                        sellPrice: sellPrice,
                        image: itemDetails.image || null,
                        icon: itemDetails.icon || getItemIcon({ ...itemDetails, itemId: minItem.itemId })
                    };
                    
                    const slotElement = createInventorySlot(richItem, 'sell');
                    if (slotElement) {
                        fragment.appendChild(slotElement);
                        itemsProcessed++;
                    }
                } else {
                    console.warn(`[CNR_NUI] ItemId ${minItem.itemId} from inventory not found in fullItemConfig. Creating fallback display.`);
                    // Create a fallback display for the item
                    const fallbackItem = {
                        itemId: minItem.itemId,
                        name: minItem.itemId,
                        count: minItem.count,
                        category: 'Unknown',
                        sellPrice: 0
                    };
                    fragment.appendChild(createInventorySlot(fallbackItem, 'sell'));
                    itemsProcessed++;
                }
            }
        });
        
        console.log('[CNR_NUI] Created', itemsProcessed, 'sell item slots');
        sellGrid.appendChild(fragment);
        
        if (itemsProcessed === 0) {
            sellGrid.innerHTML = '<div style="grid-column: 1 / -1; text-align: center; color: rgba(255,255,255,0.6); padding: 40px;">No sellable items in inventory.</div>';
        }
    }).catch(error => {
        console.error('[CNR_NUI] Error loading sell inventory:', error);
        // Create error message safely to prevent XSS
        const errorDiv = document.createElement('div');
        errorDiv.style.cssText = 'grid-column: 1 / -1; text-align: center; color: rgba(255,255,255,0.8); padding: 40px;';
        errorDiv.innerHTML = 'Error loading inventory. Please try again.<br><small>Error: </small>';
        const errorSpan = document.createElement('span');
        errorSpan.textContent = error.message; // Use textContent to prevent XSS
        errorDiv.querySelector('small').appendChild(errorSpan);
        sellGrid.innerHTML = '';
        sellGrid.appendChild(errorDiv);
    });
}

// Legacy Support Functions (for backward compatibility)
function loadItems() {
    console.log('[CNR_NUI] loadItems() called - redirecting to loadGridItems()');
    loadGridItems();
}

function loadSellItems() {
    console.log('[CNR_NUI] loadSellItems() called - redirecting to loadSellGridItems()');
    loadSellGridItems();
}

// Legacy createItemElement function for backward compatibility
function createItemElement(item, type = 'buy') {
    console.log('[CNR_NUI] createItemElement() called - redirecting to createInventorySlot()');
    return createInventorySlot(item, type);
}

// Modern Grid-Based Inventory Slot Creation
function createInventorySlot(item, type = 'buy') {
    console.log('[CNR_NUI_DEBUG] createInventorySlot called for:', item.itemId, 'type:', type, 'item data:', JSON.stringify(item));
    
    if (!item || !item.itemId) {
        console.error('[CNR_NUI_ERROR] Invalid item data provided to createInventorySlot:', item);
        return null;
    }
    
    const slot = document.createElement('div');
    slot.className = 'inventory-slot';
    slot.dataset.itemId = item.itemId;
    
    // Check if item is level-locked for buy tab
    let isLocked = false;
    let lockReason = '';
    
    if (type === 'buy' && window.playerInfo) {
        const playerLevel = window.playerInfo.level || 1;
        const playerRole = window.playerInfo.role || 'citizen';
        
        if (playerRole === 'cop' && item.minLevelCop && playerLevel < item.minLevelCop) {
            isLocked = true;
            lockReason = `Level ${item.minLevelCop}`;
        } else if (playerRole === 'robber' && item.minLevelRobber && playerLevel < item.minLevelRobber) {
            isLocked = true;
            lockReason = `Level ${item.minLevelRobber}`;
        }
    }
    
    if (isLocked) {
        slot.classList.add('locked');
    }
    
    // Item Icon Container
    const iconContainer = document.createElement('div');
    iconContainer.className = 'item-icon-container';
    
    // Check if item has a valid image
    if (item.image && typeof item.image === 'string' && !item.image.includes('404')) {
        const imgElement = document.createElement('img');
        imgElement.src = item.image;
        imgElement.className = 'item-image';
        imgElement.alt = item.name || item.itemId;
        imgElement.onerror = function() {
            console.log(`[CNR_NUI] Image load error for ${item.itemId}, using fallback`);
            this.style.display = 'none';
            appendStoreItemIcon(this.parentNode, item);
        };
        iconContainer.appendChild(imgElement);
    } else {
        appendStoreItemIcon(iconContainer, item);
    }
      // Add level requirement badge if locked
    if (isLocked) {
        const levelBadge = document.createElement('div');
        levelBadge.className = 'level-requirement';
        levelBadge.textContent = lockReason;
        iconContainer.appendChild(levelBadge);
    }
    
    // Add quantity badge for sell items
    if (type === 'sell' && item.count !== undefined && item.count > 1) {
        const quantityBadge = document.createElement('div');
        quantityBadge.className = 'quantity-badge';
        quantityBadge.textContent = `x${item.count}`;
        iconContainer.appendChild(quantityBadge);
    }
    
    slot.appendChild(iconContainer);
    
    // Item Info
    const itemInfo = document.createElement('div');
    itemInfo.className = 'item-info';
    
    const itemName = document.createElement('div');
    itemName.className = 'item-name';
    itemName.textContent = item.name || item.itemId || 'Unknown Item';
    itemInfo.appendChild(itemName);
    
    const itemPrice = document.createElement('div');
    itemPrice.className = 'item-price';
    const priceValue = type === 'buy' ? (item.price || item.basePrice || 0) : (item.sellPrice || 0);
    itemPrice.textContent = `$${priceValue ? priceValue.toLocaleString() : '0'}`;
    itemInfo.appendChild(itemPrice);
    
    slot.appendChild(itemInfo);
    
    // Action Overlay (only show on hover for unlocked items)
    if (!isLocked) {
        const actionOverlay = document.createElement('div');
        actionOverlay.className = 'action-overlay';
        
        const quantityInput = document.createElement('input');
        quantityInput.type = 'number';
        quantityInput.className = 'quantity-input';
        quantityInput.min = '1';
        quantityInput.max = (type === 'buy') ? '100' : (item.count ? item.count.toString() : '1');
        quantityInput.value = '1';
        actionOverlay.appendChild(quantityInput);
        
        const actionBtn = document.createElement('button');
        actionBtn.className = 'action-btn';
        actionBtn.textContent = type === 'buy' ? 'Buy' : 'Sell';
        actionBtn.onclick = (e) => {
            e.stopPropagation();
            const quantity = parseInt(quantityInput.value) || 1;
            handleItemAction(item.itemId, quantity, type);
        };
        actionOverlay.appendChild(actionBtn);
        
        slot.appendChild(actionOverlay);
    }
    
    console.log('[CNR_NUI_DEBUG] Successfully created slot for:', item.itemId);
    return slot;
}

function appendStoreItemIcon(container, item) {
    const icon = document.createElement('div');
    icon.className = 'item-icon';
    icon.setAttribute('aria-hidden', 'true');
    icon.textContent = item?.icon || getItemIcon(item);
    container.appendChild(icon);
}

function getStoreItemIconClass(item) {
    const itemId = String(item?.itemId || '').toLowerCase();
    const category = String(item?.category || '').toLowerCase();
    const name = String(item?.name || '').toLowerCase();

    const exact = {
        ammo_pistol: 'fa-box',
        ammo_rifle: 'fa-boxes-stacked',
        ammo_shotgun: 'fa-box',
        ammo_sniper: 'fa-crosshairs',
        armor: 'fa-shield-halved',
        heavy_armor: 'fa-shield',
        medkit: 'fa-kit-medical',
        firstaidkit: 'fa-briefcase-medical',
        lockpick: 'fa-key',
        adv_lockpick: 'fa-unlock-keyhole',
        hacking_device: 'fa-laptop-code',
        drill: 'fa-screwdriver-wrench',
        thermite: 'fa-fire',
        c4: 'fa-bomb',
        speedradar_gun: 'fa-satellite-dish',
        spikestrip_item: 'fa-triangle-exclamation',
        k9whistle: 'fa-volume-high',
        weapon_nightstick: 'fa-grip-lines-vertical',
        weapon_flashlight: 'fa-lightbulb',
        weapon_stungun: 'fa-bolt',
        weapon_stunrod: 'fa-bolt',
        weapon_fireextinguisher: 'fa-fire-extinguisher',
        weapon_flare: 'fa-wand-sparkles',
        weapon_flaregun: 'fa-wand-sparkles',
        weapon_smokegrenade: 'fa-cloud',
        weapon_bzgas: 'fa-cloud',
        weapon_stickybomb: 'fa-bomb',
        weapon_grenade: 'fa-bomb',
        weapon_rpg: 'fa-rocket',
        weapon_hominglauncher: 'fa-rocket',
        gadget_parachute: 'fa-parachute-box'
    };

    if (exact[itemId]) return exact[itemId];
    if (itemId.includes('ammo') || name.includes('ammo')) return 'fa-box';
    if (itemId.includes('shotgun') || name.includes('shotgun')) return 'fa-gun';
    if (itemId.includes('rifle') || name.includes('rifle')) return 'fa-gun';
    if (itemId.includes('pistol') || name.includes('pistol')) return 'fa-gun';
    if (itemId.includes('weapon_') || category.includes('weapon')) return 'fa-gun';
    if (category.includes('armor')) return 'fa-shield-halved';
    if (category.includes('cop')) return 'fa-shield';
    if (category.includes('utility')) return 'fa-screwdriver-wrench';
    if (category.includes('accessor')) return 'fa-mask';

    return 'fa-cube';
}

// Get appropriate icon for item based on category and name
function getItemIcon(category, itemName) {
    let itemId = null;

    if (category && typeof category === 'object') {
        const item = category;
        itemId = item.itemId || item.id || null;
        category = item.category || item.type || 'Unknown';
        itemName = item.name || item.label || item.itemId || 'Unknown';
    }

    category = category || 'Unknown';
    itemName = itemName || 'Unknown';

    const normalizedCategory = String(category).toLowerCase();
    const normalizedName = String(itemName).toLowerCase();
    const normalizedItemId = itemId ? String(itemId).toLowerCase() : '';
    const itemSpecificIcons = {
        ammo_pistol: '▣',
        ammo_rifle: '▦',
        ammo_shotgun: '▥',
        ammo_sniper: '◈',
        armor: '🛡️',
        heavy_armor: '🛡️',
        medkit: '✚',
        firstaidkit: '✚',
        speedradar_gun: '📡',
        spikestrip_item: '⚠',
        weapon_nightstick: '▌',
        weapon_flashlight: '🔦',
        weapon_stungun: '⚡',
        weapon_stunrod: '⚡',
        weapon_flare: '✹',
        weapon_flaregun: '✹',
        weapon_pumpshotgun: '💥',
        weapon_combatpistol: '🔫',
        weapon_revolver_mk2: '🔫',
        weapon_heavyrevolver_mk2: '🔫',
        weapon_combatmg: '💥',
        weapon_combatmg_mk2: '💥',
        weapon_smokegrenade: '💨',
        k9whistle: '🐕'
    };

    if (normalizedItemId && itemSpecificIcons[normalizedItemId]) {
        return itemSpecificIcons[normalizedItemId];
    }

    for (const [key, icon] of Object.entries(itemSpecificIcons)) {
        if (normalizedName === key || normalizedName.includes(key.replace('weapon_', '').replace('_item', '').replace('_', ' '))) {
            return icon;
        }
    }

    const icons = {
        'Weapons': {
            'Pistol': '🔫',
            'SMG': '💥',
            'Assault Rifle': '🔫',
            'Sniper': '🎯',
            'Shotgun': '💥',
            'Heavy Weapon': '💥',
            'Melee': '🗡️',
            'Thrown': '💣'
        },
        'Equipment': {
            'Armor': '🛡️',
            'Parachute': '🪂',
            'Health': '❤️',
            'Radio': '📻'
        },
        'Vehicles': {
            'Car': '🚗',
            'Motorcycle': '🏍️',
            'Boat': '🚤',
            'Aircraft': '✈️'
        },
        'Tools': {
            'Lockpick': '🗝️',
            'Drill': '🔧',
            'Hacking': '💻',
            'Explosive': '💣'
        }
    };
    
    // Try to find specific item first
    if (icons[category] && icons[category][itemName]) {
        return icons[category][itemName];
    }
    
    // Fallback to category icons
    const categoryIcons = {
        'Weapons': '🔫',
        'weapons': '🔫',
        'Melee Weapons': '▌',
        'Ammunition': '▣',
        'Equipment': '🎒',
        'Armor': '🛡️',
        'Cop Gear': '🚓',
        'Police Equipment': '🚓',
        'Vehicles': '🚗',
        'Tools': '🔧',
        'Utility': '⚙',
        'Consumables': '💊',
        'Medical': '✚',
        'Ammo': '▣',
        'ammo': '▣'
    };
    
    if (normalizedCategory.includes('ammo') || normalizedName.includes('ammo')) return '▣';
    if (normalizedCategory.includes('armor')) return '🛡️';
    if (normalizedCategory.includes('cop') || normalizedCategory.includes('police')) return '🚓';
    if (normalizedCategory.includes('weapon')) return '🔫';

    return categoryIcons[category] || '📦';
}

// MODIFIED handleItemAction function
async function handleItemAction(itemId, quantity, actionType) {
    const endpoint = actionType === 'buy' ? 'buyItem' : 'sellItem';
    const resName = CNRConfig.getResourceName();
    const url = `https://${resName}/${endpoint}`;

    try {
        const rawResponse = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ itemId: itemId, quantity: quantity })
        });

        const jsonData = await rawResponse.json(); // jsonData is what cb({ success: ... }) sends

        if (!rawResponse.ok) { // HTTP error (e.g. 500, 404)
            throw new Error(jsonData.error || jsonData.message || `HTTP error ${rawResponse.status}`);
        }

        if (!jsonData.success) {
            showToast(jsonData.message || `${actionType === 'buy' ? 'Purchase' : 'Sell'} request failed.`, 'error');
        }

    } catch (error) {
        console.error(`[CNR_NUI_FETCH] Error ${actionType}ing item (URL: ${url}):`, error);
        showToast(`Request to ${actionType} item failed: ${error.message || 'Check F8 console.'}`, 'error');
    }
}
window.handleItemAction = handleItemAction;

// Cash notification system
let previousCash = null;

function showCashNotification(newCash, oldCash = null) {
    const parsedNewCash = Number(newCash);
    const parsedOldCash = oldCash === null ? null : Number(oldCash);

    if (!Number.isFinite(parsedNewCash) || (oldCash !== null && !Number.isFinite(parsedOldCash))) {
        const fallbackType = typeof oldCash === 'string' ? oldCash : 'info';
        showToast(String(newCash ?? ''), fallbackType);
        return;
    }

    const difference = parsedOldCash !== null ? parsedNewCash - parsedOldCash : 0;
    
    if (difference === 0) return;
    
    const notification = document.createElement('div');
    notification.className = 'cash-notification';
    notification.innerHTML = `
        <div class="cash-amount">${difference > 0 ? '+' : ''}$${formatCurrencyDisplay(Math.abs(difference))}</div>
        <div class="cash-total">Total: $${formatCurrencyDisplay(parsedNewCash)}</div>
    `;
    
    document.body.appendChild(notification);
    
    // Trigger animation
    setTimeout(() => {
        notification.classList.add('show');
    }, 10);
    
    // Remove after animation
    setTimeout(() => {
        notification.classList.remove('show');
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 300);
    }, 3000);
}

// ====================================================================
// Wanted Level Notification Functions
// ====================================================================

let wantedNotificationTimeout = null;
let lastKnownStars = 0; // Track previous star level to only show notifications on changes

function showWantedNotification(stars, points, levelLabel) {
    // Only show notification if stars have actually changed
    if (stars !== lastKnownStars) {
        console.log('[CNR_NUI] Showing wanted notification - Stars changed from', lastKnownStars, 'to', stars, 'Points:', points, 'Level:', levelLabel);
        lastKnownStars = stars; // Update tracked stars
        
        const notification = document.getElementById('wanted-notification');
        if (!notification) {
            console.error('[CNR_NUI] Wanted notification element not found');
            return;
        }

        // Clear any existing timeout
        if (wantedNotificationTimeout) {
            clearTimeout(wantedNotificationTimeout);
            wantedNotificationTimeout = null;
        }

        // Update notification content
        const wantedIcon = notification.querySelector('.wanted-icon');
        const wantedLevelEl = notification.querySelector('.wanted-level');
        const wantedPointsEl = notification.querySelector('.wanted-points');

        if (wantedIcon) wantedIcon.textContent = '⭐';
        if (wantedLevelEl) {
            wantedLevelEl.textContent = levelLabel || generateStarDisplay(stars);
        }
        if (wantedPointsEl) {
            wantedPointsEl.textContent = `${points} Points`;
        }

        // Remove existing level classes and add new one
        notification.className = 'wanted-notification';
        if (stars > 0) {
            notification.classList.add(`level-${Math.min(stars, 5)}`);        }

        // Show notification
        notification.style.display = 'block';
        notification.style.opacity = '1';

        // Keep the current wanted level visible until the server clears it.
        if (stars <= 0) {
            wantedNotificationTimeout = setTimeout(() => {
                hideWantedNotification();
            }, 3000);
        }
    } else {
        // Stars haven't changed, but the current wanted state still needs to stay accurate.
        const notification = document.getElementById('wanted-notification');
        if (notification) {
            const wantedLevelEl = notification.querySelector('.wanted-level');
            const wantedPointsEl = notification.querySelector('.wanted-points');

            if (wantedLevelEl) {
                wantedLevelEl.textContent = levelLabel || generateStarDisplay(stars);
            }
            if (wantedPointsEl) {
                wantedPointsEl.textContent = `${points} Points`;
            }
            if (stars > 0) {
                notification.style.display = 'block';
                notification.style.opacity = '1';
            }
        }

        console.log('[CNR_NUI] Wanted level sync (no star change) - Stars:', stars, 'Points:', points);
    }
}

function hideWantedNotification() {
    const notification = document.getElementById('wanted-notification');
    if (!notification) return;

    // Reset star tracking when notification is hidden (wanted level cleared)
    lastKnownStars = 0;

    // Clear timeout if it exists
    if (wantedNotificationTimeout) {
        clearTimeout(wantedNotificationTimeout);
        wantedNotificationTimeout = null;
    }

    // Add removing animation class
    notification.classList.add('removing');
    
    // Hide after animation completes
    setTimeout(() => {
        notification.classList.add('hidden');
        notification.classList.remove('removing');
    }, 300);
}

function generateStarDisplay(stars) {
    if (stars <= 0) return '';
    const maxStars = 5;
    let display = '';
    for (let i = 1; i <= maxStars; i++) {
        display += i <= stars ? '★' : '☆';
    }
    return display;
}

// Event listeners and other functions (DOMContentLoaded, selectRole, Escape key, Heist Timer, Admin Panel, Bounty Board) remain unchanged from the previous version.
// ... (assuming the rest of the file content from the last read_files output is here)
document.addEventListener('click', function(event) {
    const target = event.target;
    const itemDiv = target.closest('.item');
    if (!itemDiv) return;
    
    // Check if this is a locked item
    if (itemDiv.classList.contains('locked-item') && target.dataset.action === 'buy') {
        showToast('This item is locked. You need a higher level to purchase it.', 'error');
        return;
    }
    
    const itemId = itemDiv.dataset.itemId;
    const actionType = target.dataset.action;
    if (itemId && (actionType === 'buy' || actionType === 'sell')) {
        const quantityInput = itemDiv.querySelector('.quantity-input');
        if (!quantityInput) { console.error('Quantity input not found for item:', itemId); return; }
        const quantity = parseInt(quantityInput.value);
        const maxQuantity = parseInt(quantityInput.max);
        if (isNaN(quantity) || quantity < 1 || quantity > maxQuantity) {
            console.warn(`[CNR_NUI_INPUT_VALIDATION] Invalid quantity input: ${quantity}. Max allowed: ${maxQuantity}. ItemId: ${itemId}`);
            return;
        }
        handleItemAction(itemId, quantity, actionType);
    }
});

function selectRole(selectedRole) {
    if (roleSelectionPending) {
        return;
    }

    roleSelectionPending = true;
    const roleSelectionUI = document.getElementById('role-selection');
    if (roleSelectionUI) {
        roleSelectionUI.querySelectorAll('button[data-role]').forEach((button) => {
            button.disabled = true;
        });
    }

    const resName = CNRConfig.getResourceName();
    const fetchURL = `https://${resName}/selectRole`;
    fetch(fetchURL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ role: selectedRole })
    })
    .then(resp => {
        if (!resp.ok) {
            return resp.text().then(text => {
                throw new Error(`HTTP error ${resp.status} (${resp.statusText}): ${text}`);
            }).catch(() => {
                 throw new Error(`HTTP error ${resp.status} (${resp.statusText})`);
            });
        }
        return resp.json();
    })
    .then(response => { // This 'response' is the data from the NUI callback cb({success=true}) in client.lua
        console.log('[CNR_NUI_ROLE] selectRole NUI callback response from Lua:', response);
        // The original script called another function: handleRoleSelectionResponse(response)
        // Let's assume that function is still there or integrate its logic.
        // For logging, we want to see if hideRoleSelection is called.
        // Original handleRoleSelectionResponse:
        // function handleRoleSelectionResponse(response) {
        //   console.log("Response from selectRole NUI callback:", response);
        //   if (response && response.success) {
        //     hideRoleSelection();
        //   } else if (response && response.error) { ... } else { ... }
        // }
        // Directly integrate for clarity or ensure handleRoleSelection is called:
        if (response && response.success) {
            console.log('[CNR_NUI_ROLE] selectRole request accepted by Lua. Waiting for server confirmation.');
            hideRoleSelection();
        } else if (response && response.error) {
            roleSelectionPending = false;
            if (roleSelectionUI) {
                roleSelectionUI.querySelectorAll('button[data-role]').forEach((button) => {
                    button.disabled = false;
                });
            }
            console.error("[CNR_NUI_ROLE] Role selection failed via NUI callback: " + response.error);
            showToast(response.error, 'error'); // Keep toast for user feedback
        } else {
            roleSelectionPending = false;
            if (roleSelectionUI) {
                roleSelectionUI.querySelectorAll('button[data-role]').forEach((button) => {
                    button.disabled = false;
                });
            }
            console.error("[CNR_NUI_ROLE] Role selection failed: Unexpected server response from NUI callback", response);
            showToast("Unexpected server response", 'error'); // Keep toast
        }
    })
    .catch(error => {
        roleSelectionPending = false;
        if (roleSelectionUI) {
            roleSelectionUI.querySelectorAll('button[data-role]').forEach((button) => {
                button.disabled = false;
            });
        }
        const resNameForError = CNRConfig.getResourceName();
        console.error(`Error in selectRole NUI callback (URL attempted: https://${resNameForError}/selectRole):`, error);
        showToast(`Failed to select role: ${error.message || 'See F8 console.'}`, 'error');
    });
}

document.addEventListener('DOMContentLoaded', () => {
    const roleSelectionContainer = document.getElementById('role-selection');
    if (roleSelectionContainer) {
        roleSelectionContainer.addEventListener('click', function(event) {
            const button = event.target.closest('button[data-role]');
            if (button) {
                const role = button.getAttribute('data-role');
                
                // Check if it's a role selection or character editor button
                if (button.classList.contains('role-editor-btn') || button.id.includes('editor')) {
                    // Open character editor
                    fetch(`https://${CNRConfig.getResourceName()}/openCharacterEditor`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ role: role, characterSlot: 1 })
                    }).then(resp => resp.json()).then(response => {
                        console.log('[CNR_CHARACTER_EDITOR] Character editor request response:', response);
                        if (response.success) {
                            hideRoleSelection();
                        }
                    }).catch(error => {
                        console.error('[CNR_CHARACTER_EDITOR] Error opening character editor:', error);
                    });
                } else {
                    // Regular role selection
                    selectRole(role);
                }
            }
        });
    } else {
        document.querySelectorAll('.menu button[data-role]').forEach(button => {
            button.addEventListener('click', () => {
                const role = button.getAttribute('data-role');
                if (button.classList.contains('role-editor-btn') || button.id.includes('editor')) {
                    // Open character editor
                    fetch(`https://${CNRConfig.getResourceName()}/openCharacterEditor`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ role: role, characterSlot: 1 })
                    }).then(resp => resp.json()).then(response => {
                        console.log('[CNR_CHARACTER_EDITOR] Character editor request response:', response);
                        if (response.success) {
                            hideRoleSelection();
                        }
                    }).catch(error => {
                        console.error('[CNR_CHARACTER_EDITOR] Error opening character editor:', error);
                    });
                } else {
                    selectRole(role);
                }
            });
        });
    }

    const adminPlayerListBody = document.getElementById('admin-player-list-body');
    if (adminPlayerListBody) {
        adminPlayerListBody.addEventListener('click', function(event) {
            const target = event.target.closest('.admin-action-btn');
            if (target) {
                const targetId = target.dataset.targetId;
                if (!targetId) return;
                const resName = CNRConfig.getResourceName();
                if (target.classList.contains('admin-kick-btn')) {
                    if (confirm(`Kick player ID ${targetId}?`)) {
                        fetch(`https://${resName}/adminKickPlayer`, {
                            method: 'POST', headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ targetId: targetId })
                        }).then(resp => resp.json()).then(res => console.log('[CNR_NUI_ADMIN] Kick response:', res.message || (res.success ? 'Kicked.' : 'Failed.')));
                    }
                } else if (target.classList.contains('admin-ban-btn')) {
                    currentAdminTargetPlayerId = targetId;
                    document.getElementById('admin-ban-reason-container')?.classList.remove('hidden');
                    document.getElementById('admin-ban-reason')?.focus();
                } else if (target.classList.contains('admin-teleport-btn')) {
                    if (confirm(`Teleport to player ID ${targetId}?`)) {
                         fetch(`https://${resName}/teleportToPlayerAdminUI`, {
                            method: 'POST', headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ targetId: targetId })
                        }).then(resp => resp.json()).then(res => {
                            console.log('[CNR_NUI_ADMIN] Teleport response:', res.message || (res.success ? 'Teleporting.' : 'Failed.'));
                            hideAdminPanel();
                        });
                    }
                } else if (target.classList.contains('admin-spectate-btn')) {
                    fetch(`https://${resName}/adminSpectatePlayer`, {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ targetId: targetId })
                    }).then(resp => resp.json()).then(res => {
                        console.log('[CNR_NUI_ADMIN] Spectate response:', res.error || (res.success ? 'Spectating.' : 'Failed.'));
                        if (res.success) hideAdminPanel();
                    });
                } else if (target.classList.contains('admin-add-item-btn') || target.classList.contains('admin-remove-item-btn')) {
                    const itemId = (prompt(`Enter item id for player ${targetId}`) || '').trim();
                    if (!itemId) return;

                    const quantityInput = prompt(`Enter quantity of ${itemId}`, '1');
                    const quantity = Number.parseInt(quantityInput || '1', 10);
                    if (!Number.isFinite(quantity) || quantity <= 0) return;

                    const endpoint = target.classList.contains('admin-add-item-btn') ? 'adminAddInventoryItem' : 'adminRemoveInventoryItem';
                    fetch(`https://${resName}/${endpoint}`, {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ targetId: targetId, itemId, quantity })
                    }).then(resp => resp.json()).then(res => {
                        console.log(`[CNR_NUI_ADMIN] ${endpoint} response:`, res.error || (res.success ? 'Success.' : 'Failed.'));
                    });
                }
            }
        });
    }

    document.getElementById('admin-live-map-filters')?.addEventListener('click', function(event) {
        const filterBtn = event.target.closest('.live-map-filter-btn');
        if (!filterBtn) return;

        adminLiveMapFilter = filterBtn.dataset.filter || 'all';
        this.querySelectorAll('.live-map-filter-btn').forEach((button) => {
            button.classList.toggle('active', button === filterBtn);
        });
        renderAdminLiveMap();
    });

    document.addEventListener('click', function(event) {
        const marker = event.target.closest('.live-map-marker');
        if (!marker) return;

        const context = marker.dataset.mapContext;
        const markerId = marker.dataset.markerId;
        if (!context || !markerId) return;

        liveMapSelectionByContext[context] = markerId;
        if (context === 'admin') {
            renderAdminLiveMap();
        } else if (context === 'police') {
            renderPoliceLiveMap();
        }
    });

    document.getElementById('admin-confirm-ban-btn')?.addEventListener('click', function() {
        if (currentAdminTargetPlayerId) {
            const reasonInput = document.getElementById('admin-ban-reason');
            const reason = reasonInput ? reasonInput.value.trim() : "Banned by Admin via UI.";
            const resName = CNRConfig.getResourceName();
            fetch(`https://${resName}/adminBanPlayer`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ targetId: currentAdminTargetPlayerId, reason: reason })
            }).then(resp => resp.json()).then(res => {
                console.log('[CNR_NUI_ADMIN] Ban response:', res.message || (res.success ? 'Banned.' : 'Failed.'));
                hideAdminPanel();
            });
        }
    });

    document.getElementById('admin-cancel-ban-btn')?.addEventListener('click', function() {
        document.getElementById('admin-ban-reason-container')?.classList.add('hidden');
        const banReasonInput = document.getElementById('admin-ban-reason');
        if (banReasonInput) banReasonInput.value = '';
        currentAdminTargetPlayerId = null;
    });

    document.getElementById('admin-close-btn')?.addEventListener('click', hideAdminPanel);
    document.getElementById('admin-toggle-noclip-btn')?.addEventListener('click', async function() {
        const resName = CNRConfig.getResourceName();
        const response = await fetch(`https://${resName}/adminToggleNoClip`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        const result = await response.json();
        if (result && result.success) {
            this.innerHTML = result.enabled
                ? '<span class="icon">🪽</span>Disable No Clip'
                : '<span class="icon">🪽</span>No Clip';
        }
    });
    document.getElementById('admin-toggle-invisible-btn')?.addEventListener('click', async function() {
        const resName = CNRConfig.getResourceName();
        const response = await fetch(`https://${resName}/adminToggleInvisible`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        const result = await response.json();
        if (result && result.success) {
            this.innerHTML = result.enabled
                ? '<span class="icon">👁️</span>Visible'
                : '<span class="icon">👁️</span>Invisible';
        }
    });
    document.getElementById('admin-stop-spectate-btn')?.addEventListener('click', async function() {
        const resName = CNRConfig.getResourceName();
        await fetch(`https://${resName}/adminStopSpectate`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    });
    const storeCloseButton = document.getElementById('close-btn');
    if (storeCloseButton) storeCloseButton.addEventListener('click', closeStoreMenu);
    const bountyCloseButton = document.getElementById('bounty-close-btn');
    if (bountyCloseButton) bountyCloseButton.addEventListener('click', hideBountyBoardUI);
});

window.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' || event.keyCode === 27) {
        const storeMenu = document.getElementById('store-menu');
        const adminPanel = document.getElementById('admin-panel');
        const bountyBoardPanel = document.getElementById('bounty-board');
        const pdGarageMenu = document.getElementById('pd-garage-menu');
        if (storeMenu && storeMenu.style.display === 'block') closeStoreMenu();
        else if (adminPanel && adminPanel.style.display !== 'none' && !adminPanel.classList.contains('hidden')) hideAdminPanel();
        else if (bountyBoardPanel && bountyBoardPanel.style.display !== 'none' && !bountyBoardPanel.classList.contains('hidden')) hideBountyBoardUI();
        else if (pdGarageMenu && !pdGarageMenu.classList.contains('hidden')) hidePdGarageMenu();
    }
});

// Global escape key listener for inventory
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' && window.isInventoryOpen) {
        closeInventoryUI();
    }
});

let heistTimerInterval = null;
function startHeistTimer(duration, bankName) {
    const heistTimerEl = document.getElementById('heist-timer');
    if (!heistTimerEl) return;
    heistTimerEl.style.display = 'block';
    const timerTextEl = document.getElementById('timer-text');
    if (!timerTextEl) { heistTimerEl.style.display = 'none'; return; }
    let remainingTime = duration;
    timerTextEl.textContent = `Heist at ${bankName}: ${formatTime(remainingTime)}`;
    if (heistTimerInterval) clearInterval(heistTimerInterval);
    heistTimerInterval = setInterval(function() {
        remainingTime--;
        if (remainingTime <= 0) {
            clearInterval(heistTimerInterval);
            heistTimerInterval = null;
            heistTimerEl.style.display = 'none';
            return;
        }
        timerTextEl.textContent = `Heist at ${bankName}: ${formatTime(remainingTime)}`;
    }, 1000);
}

function formatTime(seconds) {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
}

const LIVE_MAP_WORLD_MIN_X = -4200;
const LIVE_MAP_WORLD_MAX_X = 4500;
const LIVE_MAP_WORLD_MIN_Y = -4200;
const LIVE_MAP_WORLD_MAX_Y = 8500;

let latestAdminLiveMapData = { players: [], generatedAt: 0 };
let adminLiveMapRefreshInterval = null;
let adminLiveMapFilter = 'all';
const liveMapSelectionByContext = {
    admin: null,
    police: null
};
const liveMapMarkersByContext = {
    admin: [],
    police: []
};

function capitalizeLiveMapRole(role) {
    if (role === 'cop') return 'Cop';
    if (role === 'robber') return 'Robber';
    if (role === 'citizen' || role === 'civilian') return 'Civilian';
    return String(role || 'Unknown').charAt(0).toUpperCase() + String(role || 'unknown').slice(1);
}

function formatLiveMapTimestamp(timestamp) {
    if (!timestamp) {
        return 'Waiting for live telemetry.';
    }

    const rendered = new Date(Number(timestamp) * 1000);
    if (Number.isNaN(rendered.getTime())) {
        return 'Waiting for live telemetry.';
    }

    return `Updated ${rendered.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })}`;
}

function worldCoordsToLiveMapPosition(coords) {
    if (!coords || !Number.isFinite(Number(coords.x)) || !Number.isFinite(Number(coords.y))) {
        return null;
    }

    const normalizedX = (Number(coords.x) - LIVE_MAP_WORLD_MIN_X) / (LIVE_MAP_WORLD_MAX_X - LIVE_MAP_WORLD_MIN_X);
    const normalizedY = (Number(coords.y) - LIVE_MAP_WORLD_MIN_Y) / (LIVE_MAP_WORLD_MAX_Y - LIVE_MAP_WORLD_MIN_Y);
    const left = normalizedX * 100;
    const top = (1 - normalizedY) * 100;

    if (left < -8 || left > 108 || top < -8 || top > 108) {
        return null;
    }

    return {
        left: Math.max(0, Math.min(100, left)),
        top: Math.max(0, Math.min(100, top))
    };
}

function renderLiveMapDetails(context, marker, metaText) {
    const detailsContainer = document.getElementById(`${context}-live-map-details`);
    if (!detailsContainer) return;

    if (!marker) {
        detailsContainer.innerHTML = `
            <div class="live-map-details-empty">
                <h3>No telemetry selected</h3>
                <p>${escapeHtml(metaText || 'Select a marker to inspect a player, suspect, or active scene.')}</p>
            </div>
        `;
        return;
    }

    const detailRows = (marker.detailRows || []).map((row) => `
        <div class="live-map-detail-row">
            <span>${escapeHtml(row.label)}</span>
            <strong>${escapeHtml(row.value)}</strong>
        </div>
    `).join('');

    const chips = (marker.chips || []).map((chip) => `
        <span class="live-map-detail-chip${chip.variant ? ` live-map-detail-chip--${chip.variant}` : ''}">${escapeHtml(chip.label)}</span>
    `).join('');

    detailsContainer.innerHTML = `
        <div class="live-map-detail-card">
            <p class="live-map-detail-kicker">${escapeHtml(marker.kicker || 'Live telemetry')}</p>
            <h3>${escapeHtml(marker.title || 'Unknown marker')}</h3>
            <p class="live-map-detail-subtitle">${escapeHtml(marker.subtitle || metaText || '')}</p>
            <div class="live-map-detail-chip-row">${chips}</div>
            <div class="live-map-detail-grid">${detailRows}</div>
            <p class="live-map-detail-meta">${escapeHtml(metaText || '')}</p>
        </div>
    `;
}

function renderLiveMapCanvas(context, markers, metaText) {
    const canvas = document.getElementById(`${context}-live-map`);
    if (!canvas) return;

    liveMapMarkersByContext[context] = markers;
    const positionedMarkers = markers
        .map((marker) => {
            const position = worldCoordsToLiveMapPosition(marker.coords);
            return position ? { ...marker, position } : null;
        })
        .filter(Boolean);

    if (!positionedMarkers.length) {
        liveMapSelectionByContext[context] = null;
        canvas.innerHTML = `
            <div class="live-map-stage">
                <div class="live-map-empty-state">
                    <h3>No active telemetry on map</h3>
                    <p>${escapeHtml(metaText || 'Players and scenes will appear here when data is available.')}</p>
                </div>
            </div>
        `;
        renderLiveMapDetails(context, null, metaText);
        return;
    }

    if (!positionedMarkers.some((marker) => marker.id === liveMapSelectionByContext[context])) {
        liveMapSelectionByContext[context] = positionedMarkers[0].id;
    }

    const selectedMarker = positionedMarkers.find((marker) => marker.id === liveMapSelectionByContext[context]) || positionedMarkers[0];
    const markerHtml = positionedMarkers.map((marker) => `
        <button
            type="button"
            class="live-map-marker live-map-marker--${escapeHtml(marker.markerClass || 'default')}${selectedMarker.id === marker.id ? ' is-active' : ''}"
            data-map-context="${escapeHtml(context)}"
            data-marker-id="${escapeHtml(marker.id)}"
            style="left:${marker.position.left}%; top:${marker.position.top}%;"
            title="${escapeHtml(marker.title || '')}"
        >
            <span class="live-map-marker-core"></span>
            <span class="live-map-marker-tag">${escapeHtml(marker.tag || '')}</span>
        </button>
    `).join('');

    canvas.innerHTML = `
        <div class="live-map-stage">
            <div class="live-map-grid"></div>
            <div class="live-map-zone live-map-zone--paleto">Paleto Bay</div>
            <div class="live-map-zone live-map-zone--grape">Grapeseed</div>
            <div class="live-map-zone live-map-zone--sandy">Sandy Shores</div>
            <div class="live-map-zone live-map-zone--vinewood">Vinewood</div>
            <div class="live-map-zone live-map-zone--downtown">Downtown LS</div>
            <div class="live-map-zone live-map-zone--vespucci">Vespucci</div>
            ${markerHtml}
            <div class="live-map-status-bar">${escapeHtml(metaText || '')}</div>
        </div>
    `;

    renderLiveMapDetails(context, selectedMarker, metaText);
}

function buildAdminLiveMapMarkers() {
    const filterRole = adminLiveMapFilter;
    return (latestAdminLiveMapData.players || [])
        .filter((player) => filterRole === 'all' || player.role === filterRole)
        .map((player) => {
            const vehicleLabel = player.vehicleModel
                ? `${player.vehicleType || 'Vehicle'}: ${player.vehicleModel}`
                : 'On foot';
            const wantedLabel = player.wantedStars > 0
                ? `${'★'.repeat(Math.min(player.wantedStars || 0, 5))} Heat ${player.wantedLevel || 0}`
                : 'Clean';
            return {
                id: `player-${player.serverId}`,
                tag: `#${player.serverId}`,
                markerClass: player.role === 'cop' ? 'cop' : player.role === 'robber' ? 'robber' : 'civilian',
                kicker: `${capitalizeLiveMapRole(player.role)} telemetry`,
                title: `${player.name || 'Unknown'} (#${player.serverId})`,
                subtitle: `${vehicleLabel} • ${Math.round(Number(player.speedMph) || 0)} mph`,
                coords: player.coords,
                chips: [
                    { label: capitalizeLiveMapRole(player.role), variant: player.role === 'cop' ? 'cop' : player.role === 'robber' ? 'robber' : 'civilian' },
                    { label: vehicleLabel },
                    { label: wantedLabel, variant: (player.wantedStars || 0) > 0 ? 'warning' : '' }
                ],
                detailRows: [
                    { label: 'Role', value: capitalizeLiveMapRole(player.role) },
                    { label: 'Level', value: String(player.level || 1) },
                    { label: 'Cash', value: `$${formatCurrencyDisplay(player.cash || 0)}` },
                    { label: 'Speed', value: `${Math.round(Number(player.speedMph) || 0)} mph` },
                    { label: 'Equipped', value: player.equipped || 'Unarmed' },
                    { label: 'Vehicle', value: vehicleLabel },
                    { label: 'Wanted', value: wantedLabel },
                    { label: 'Coords', value: player.coords ? `${Math.floor(player.coords.x)}, ${Math.floor(player.coords.y)}` : 'Unknown' }
                ]
            };
        });
}

function renderAdminLiveMap() {
    const players = latestAdminLiveMapData.players || [];
    const roleCounts = players.reduce((counts, player) => {
        const roleKey = player.role || 'citizen';
        counts[roleKey] = (counts[roleKey] || 0) + 1;
        return counts;
    }, {});
    const metaText = `${formatLiveMapTimestamp(latestAdminLiveMapData.generatedAt)} • ${players.length} tracked • ${roleCounts.cop || 0} cops • ${roleCounts.robber || 0} robbers • ${roleCounts.citizen || 0} civilians`;
    renderLiveMapCanvas('admin', buildAdminLiveMapMarkers(), metaText);
}

function buildPoliceLiveMapMarkers() {
    const markers = [];

    (latestPoliceCadData.officers || []).forEach((officer) => {
        const vehicleLabel = officer.vehicleModel
            ? `${officer.vehicleType || 'Vehicle'}: ${officer.vehicleModel}`
            : 'On foot';
        markers.push({
            id: `officer-${officer.serverId}`,
            tag: `P${officer.serverId}`,
            markerClass: 'cop',
            kicker: 'Officer telemetry',
            title: `${officer.rank || 'Officer'} ${officer.name || 'Unknown'} (#${officer.serverId})`,
            subtitle: `${vehicleLabel} • ${Math.round(Number(officer.speedMph) || 0)} mph`,
            coords: officer.coords,
            chips: [
                { label: 'Officer', variant: 'cop' },
                { label: vehicleLabel },
                { label: officer.equipped || 'Unarmed' }
            ],
            detailRows: [
                { label: 'Rank', value: officer.rank || 'Officer' },
                { label: 'Level', value: String(officer.level || 1) },
                { label: 'Speed', value: `${Math.round(Number(officer.speedMph) || 0)} mph` },
                { label: 'Equipped', value: officer.equipped || 'Unarmed' },
                { label: 'Vehicle', value: vehicleLabel },
                { label: 'Location', value: officer.locationLabel || (officer.coords ? `${Math.floor(officer.coords.x)}, ${Math.floor(officer.coords.y)}` : 'Unknown') }
            ]
        });
    });

    (latestPoliceCadData.calls || []).forEach((call) => {
        markers.push({
            id: `call-${call.id}`,
            tag: `C${call.id}`,
            markerClass: 'call',
            kicker: 'CAD scene',
            title: `#${call.id} ${call.title || 'Untitled Call'}`,
            subtitle: `${call.priority || 'Medium'} • ${call.status || 'Open'}`,
            coords: call.coords,
            chips: [
                { label: call.priority || 'Medium', variant: (call.priority || 'medium').toLowerCase() === 'critical' ? 'danger' : 'warning' },
                { label: call.status || 'Open' },
                ...(call.requestBackup ? [{ label: 'Backup requested', variant: 'warning' }] : []),
                ...(call.urgent ? [{ label: 'ASAP', variant: 'danger' }] : [])
            ],
            detailRows: [
                { label: 'Status', value: call.status || 'Open' },
                { label: 'Priority', value: call.priority || 'Medium' },
                { label: 'Location', value: call.locationLabel || 'Unknown' },
                { label: 'Requested By', value: call.createdByName || 'Unknown' },
                { label: 'Backup', value: call.requestBackup ? 'Requested' : 'Not requested' },
                { label: 'Urgency', value: call.urgent ? 'ASAP' : 'Standard' },
                { label: 'Details', value: call.details || 'No additional notes' }
            ]
        });
    });

    (latestPoliceCadData.suspects || []).forEach((suspect) => {
        const stars = (suspect.wantedStars || 0) > 0 ? '★'.repeat(Math.min(suspect.wantedStars || 0, 5)) : 'No stars';
        markers.push({
            id: `suspect-${suspect.playerId}`,
            tag: `W${suspect.playerId}`,
            markerClass: 'suspect',
            kicker: 'Wanted suspect',
            title: `${suspect.name || 'Unknown'} (#${suspect.playerId})`,
            subtitle: `${stars} • Bounty $${formatCurrencyDisplay(suspect.bounty || 0)}`,
            coords: suspect.coords,
            chips: [
                { label: stars, variant: 'danger' },
                { label: `Heat ${suspect.wantedLevel || 0}`, variant: 'warning' },
                { label: `Bounty $${formatCurrencyDisplay(suspect.bounty || 0)}` }
            ],
            detailRows: [
                { label: 'Wanted Level', value: String(suspect.wantedLevel || 0) },
                { label: 'Stars', value: stars },
                { label: 'Bounty', value: `$${formatCurrencyDisplay(suspect.bounty || 0)}` },
                { label: 'Location', value: suspect.locationLabel || (suspect.coords ? `${Math.floor(suspect.coords.x)}, ${Math.floor(suspect.coords.y)}` : 'Unknown') }
            ]
        });
    });

    return markers;
}

function renderPoliceLiveMap() {
    const cadPayload = latestPoliceCadData || { officers: [], calls: [], suspects: [], generatedAt: 0 };
    const metaText = `${formatLiveMapTimestamp(cadPayload.generatedAt)} • ${cadPayload.officers?.length || 0} units • ${cadPayload.calls?.length || 0} active calls • ${cadPayload.suspects?.length || 0} wanted suspects`;
    renderLiveMapCanvas('police', buildPoliceLiveMapMarkers(), metaText);
}

async function loadAdminLiveMapData(showErrors = true) {
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/requestAdminLiveMapData`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        const result = await response.json();
        if (result.success) {
            updateAdminLiveMapData(result.liveMapData || {});
        } else if (showErrors) {
            showToast(result.error || 'Unable to load the admin live map.', 'error');
        }
    } catch (error) {
        if (showErrors) {
            showToast('Unable to load the admin live map.', 'error');
        }
    }
}

function updateAdminLiveMapData(liveMapData = {}) {
    latestAdminLiveMapData = {
        players: liveMapData.players || [],
        generatedAt: liveMapData.generatedAt || 0
    };
    renderAdminLiveMap();
}

let currentAdminTargetPlayerId = null;
function showAdminPanel(playerList, liveMapData = null) {
    const adminPanel = document.getElementById('admin-panel');
    const playerListBody = document.getElementById('admin-player-list-body');
    if (!adminPanel || !playerListBody) return;
    hideRoleActionMenus();
    playerListBody.innerHTML = '';
    if (playerList && playerList.length > 0) {
        playerList.forEach(player => {
            const row = playerListBody.insertRow();
            row.insertCell().textContent = player.name;
            row.insertCell().textContent = player.serverId;
            row.insertCell().textContent = player.role;
            row.insertCell().textContent = '$' + (player.cash || 0);
            const actionsCell = row.insertCell();
            const kickBtn = document.createElement('button');
            kickBtn.innerHTML = '<span class="icon">👢</span>Kick'; kickBtn.className = 'admin-action-btn admin-kick-btn';
            kickBtn.dataset.targetId = player.serverId; actionsCell.appendChild(kickBtn);
            const banBtn = document.createElement('button');
            banBtn.innerHTML = '<span class="icon">🚫</span>Ban'; banBtn.className = 'admin-action-btn admin-ban-btn';
            banBtn.dataset.targetId = player.serverId; actionsCell.appendChild(banBtn);
            const teleportBtn = document.createElement('button');
            teleportBtn.innerHTML = '<span class="icon">➡️</span>TP to'; teleportBtn.className = 'admin-action-btn admin-teleport-btn';
            teleportBtn.dataset.targetId = player.serverId; actionsCell.appendChild(teleportBtn);
            const spectateBtn = document.createElement('button');
            spectateBtn.innerHTML = '<span class="icon">📺</span>Spectate'; spectateBtn.className = 'admin-action-btn admin-spectate-btn';
            spectateBtn.dataset.targetId = player.serverId; actionsCell.appendChild(spectateBtn);
            const addItemBtn = document.createElement('button');
            addItemBtn.innerHTML = '<span class="icon">➕</span>+Item'; addItemBtn.className = 'admin-action-btn admin-add-item-btn';
            addItemBtn.dataset.targetId = player.serverId; actionsCell.appendChild(addItemBtn);
            const removeItemBtn = document.createElement('button');
            removeItemBtn.innerHTML = '<span class="icon">➖</span>-Item'; removeItemBtn.className = 'admin-action-btn admin-remove-item-btn';
            removeItemBtn.dataset.targetId = player.serverId; actionsCell.appendChild(removeItemBtn);
        });
    } else {
        playerListBody.innerHTML = '<tr><td colspan="5" style="text-align:center;">No players online or data unavailable.</td></tr>';
    }

    if (liveMapData) {
        updateAdminLiveMapData(liveMapData);
    } else {
        renderAdminLiveMap();
    }

    if (adminLiveMapRefreshInterval) {
        clearInterval(adminLiveMapRefreshInterval);
    }

    loadAdminLiveMapData(false);
    adminLiveMapRefreshInterval = setInterval(() => {
        const panelIsVisible = adminPanel && !adminPanel.classList.contains('hidden');
        if (panelIsVisible) {
            loadAdminLiveMapData(false);
        }
    }, 5000);

    adminPanel.classList.remove('hidden');
    fetchSetNuiFocus(true, true);
}

function hideAdminPanel() {
    const adminPanel = document.getElementById('admin-panel');
    if (adminPanel) adminPanel.classList.add('hidden');
    if (adminLiveMapRefreshInterval) {
        clearInterval(adminLiveMapRefreshInterval);
        adminLiveMapRefreshInterval = null;
    }
    const banReasonContainer = document.getElementById('admin-ban-reason-container');
    if (banReasonContainer) banReasonContainer.classList.add('hidden');
    const banReasonInput = document.getElementById('admin-ban-reason');
    if (banReasonInput) banReasonInput.value = '';
    currentAdminTargetPlayerId = null;
    fetchSetNuiFocus(false, false);
}

function showBountyBoardUI(bounties) {
    const bountyBoardElement = document.getElementById('bounty-board');
    if (bountyBoardElement) {
        bountyBoardElement.style.display = 'block';
        updateBountyListUI(bounties);
        fetchSetNuiFocus(true, true);
    }
}

function hideBountyBoardUI() {
    const bountyBoardElement = document.getElementById('bounty-board');
    if (bountyBoardElement) {
        bountyBoardElement.style.display = 'none';
        fetchSetNuiFocus(false, false);
    }
}

function updateBountyListUI(bounties) {
    const bountyListUL = document.getElementById('bounty-list');
    if (bountyListUL) {
        bountyListUL.innerHTML = '';
        if (Object.keys(bounties).length === 0) {
            const noBountiesLi = document.createElement('li');
            noBountiesLi.className = 'no-bounties';
            noBountiesLi.textContent = 'No active bounties.';
            bountyListUL.appendChild(noBountiesLi);
            return;
        }
        for (const targetId in bounties) {
            const data = bounties[targetId];
            const li = document.createElement('li');
            const avatarDiv = document.createElement('div');
            avatarDiv.className = 'bounty-target-avatar';
            const nameInitial = data.name ? data.name.charAt(0).toUpperCase() : '?';
            avatarDiv.textContent = nameInitial;
            li.appendChild(avatarDiv);
            const textContainer = document.createElement('div');
            textContainer.className = 'bounty-text-content';
            let amountClass = 'bounty-amount-low';
            if (data.amount > 50000) amountClass = 'bounty-amount-high';
            else if (data.amount > 10000) amountClass = 'bounty-amount-medium';
            const formatNumber = (num) => num.toLocaleString();
            const bountyAmountHTML = `<span class="${amountClass}">$${formatNumber(data.amount || 0)}</span>`;
            const targetInfo = document.createElement('div');
            targetInfo.textContent = `Target: ${data.name || 'Unknown'} (ID: ${targetId})`;
            const rewardInfo = document.createElement('div');
            rewardInfo.innerHTML = `Reward: ${bountyAmountHTML}`;
            textContainer.appendChild(targetInfo);
            textContainer.appendChild(rewardInfo);
            li.appendChild(textContainer);
            bountyListUL.appendChild(li);
            li.classList.add('new-item-animation');
            setTimeout(() => {
                li.classList.remove('new-item-animation');
            }, 300);
        }
    }
}

function safeSetTableByPlayerId(tbl, playerId, value) {
    if (tbl && typeof tbl === 'object' && playerId !== undefined && playerId !== null && (typeof playerId === 'string' || typeof playerId === 'number')) {
        tbl[playerId] = value;
        return true;
    }
    return false;
}

function safeGetTableByPlayerId(tbl, playerId) {
    if (tbl && typeof tbl === 'object' && playerId !== undefined && playerId !== null && (typeof playerId === 'string' || typeof playerId === 'number')) {
        return tbl[playerId];
    }
    return undefined;
}

// ====================================================================
// Player Inventory System
// ====================================================================

let currentInventoryTab = 'all';
let selectedInventoryItem = null;
let playerInventoryData = {};
let equippedItems = new Set();

// Initialize inventory system
function initInventorySystem() {
    console.log('[CNR_INVENTORY] Initializing inventory system...');
    
    // Add event listeners
    const inventoryCloseBtn = document.getElementById('inventory-close-btn');
    if (inventoryCloseBtn && !inventoryCloseBtn.hasEventListener) {
        inventoryCloseBtn.addEventListener('click', closeInventoryMenu);
        inventoryCloseBtn.hasEventListener = true;
    }
    
    // Add action button listeners
    const equipBtn = document.getElementById('equip-item-btn');
    const useBtn = document.getElementById('use-item-btn');
    const dropBtn = document.getElementById('drop-item-btn');
    
    if (equipBtn && !equipBtn.hasEventListener) {
        equipBtn.addEventListener('click', equipSelectedItem);
        equipBtn.hasEventListener = true;
    }
    if (useBtn && !useBtn.hasEventListener) {
        useBtn.addEventListener('click', useSelectedItem);
        useBtn.hasEventListener = true;
    }
    if (dropBtn && !dropBtn.hasEventListener) {
        dropBtn.addEventListener('click', dropSelectedItem);
        dropBtn.hasEventListener = true;
    }
    
    console.log('[CNR_INVENTORY] Inventory system initialized');
}

// Show inventory menu
function showInventoryMenu() {
    console.log('[CNR_INVENTORY] Opening inventory menu...');
    
    const inventoryMenu = document.getElementById('inventory-menu');
    if (inventoryMenu) {
        inventoryMenu.style.display = 'block';
        inventoryMenu.classList.add('show');
        
        // Update player info
        updateInventoryPlayerInfo();
        
        // Request current inventory from server
        requestPlayerInventoryForUI();
        
        // Set focus
        fetchSetNuiFocus(true, true);
        
        console.log('[CNR_INVENTORY] Inventory menu opened');
    }
}

// Close inventory menu
function closeInventoryMenu() {
    console.log('[CNR_INVENTORY] Closing inventory menu...');
    
    const inventoryMenu = document.getElementById('inventory-menu');
    if (inventoryMenu) {
        inventoryMenu.style.display = 'none';
        inventoryMenu.classList.remove('show');
        
        // Clear selection
        clearItemSelection();
        
        // Release focus
        fetchSetNuiFocus(false, false);
        
        console.log('[CNR_INVENTORY] Inventory menu closed');
    }
}

function closeInventoryUI() {
    if (!window.isInventoryOpen) return;

    window.isInventoryOpen = false;
    console.log('[CNR_INVENTORY] Closing inventory UI');
    
    const inventoryMenu = document.getElementById('inventory-menu');
    if (inventoryMenu) {
        inventoryMenu.style.display = 'none';
        inventoryMenu.classList.add('hidden');
        document.body.classList.remove('inventory-open');
    }
    
    // Remove NUI focus
    fetchSetNuiFocus(false, false);
    
    // Send close message to Lua
    fetch(`https://${CNRConfig.getResourceName()}/closeInventory`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).catch(error => {
        console.error('[CNR_INVENTORY] Failed to send close message:', error);
    });
}

// Update player info in inventory
function updateInventoryPlayerInfo() {
    const cashElement = document.getElementById('inventory-player-cash-amount');
    const levelElement = document.getElementById('inventory-player-level-text');
    const resolvedCash = dataNumber(window.playerInfo?.cash, window.playerInfo?.playerCash, window.currentPlayerInfo?.cash, window.currentPlayerInfo?.playerCash, previousCash, 0);
    const resolvedLevel = dataNumber(window.playerInfo?.level, window.playerInfo?.playerLevel, window.currentPlayerInfo?.level, window.currentPlayerInfo?.playerLevel, 1);
    
    if (cashElement) {
        cashElement.textContent = `$${Number(resolvedCash || 0).toLocaleString()}`;
    }
    
    if (levelElement) {
        levelElement.textContent = `Level ${Number(resolvedLevel || 1)}`;
    }
}

// Request player inventory from server
async function requestPlayerInventoryForUI() {
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/getPlayerInventoryForUI`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        });
        
        const result = await response.json();
        if (result?.playerInfo) {
            window.playerInfo = {
                ...(window.playerInfo || {}),
                ...result.playerInfo
            };
            window.currentPlayerInfo = {
                ...(window.currentPlayerInfo || {}),
                ...result.playerInfo
            };
            updateInventoryPlayerInfo();
        }

        if (result && result.success) {
            updateInventoryUI(result.inventory || {});
            updateEquippedItemsUI(result.equippedItems || []);
        } else {
            console.error('[CNR_INVENTORY] Failed to get inventory:', result.error);
            showToast('Failed to load inventory', 'error', 3000);
        }
    } catch (error) {
        console.error('[CNR_INVENTORY] Error requesting inventory:', error);
        showToast('Error loading inventory', 'error', 3000);
    }
}

// Create inventory UI elements if they don't exist
function createInventoryUI() {
    // Check if inventory menu already exists
    const existingInventory = document.getElementById('inventory-menu');
    if (existingInventory) {
        console.log('[CNR_INVENTORY] Inventory UI already exists, setting up event listeners');
        
        // Add close button event listener if not already added
        const closeBtn = document.getElementById('inventory-close-btn');
        if (closeBtn && !closeBtn.hasEventListener) {
            closeBtn.addEventListener('click', closeInventoryUI);
            closeBtn.hasEventListener = true;
        }
        initInventorySystem();
        
        return;
    }
    
    console.log('[CNR_INVENTORY] Creating inventory UI');
    
    // Create the main inventory container
    const inventoryMenu = document.createElement('div');
    inventoryMenu.id = 'inventory-menu';
    inventoryMenu.className = 'inventory-container';
    inventoryMenu.style.display = 'none';
    
    inventoryMenu.innerHTML = `
        <div class="inventory-panel">
            <div class="inventory-header">
                <h2>Inventory</h2>
                <button id="inventory-close-btn" class="close-btn">×</button>
            </div>
            <div class="inventory-content">
                <div class="inventory-player-info">
                    <div class="player-stats">
                        <span id="inventory-player-cash-amount">$0</span>
                        <span id="inventory-player-level-text">Level 1</span>
                    </div>
                </div>
                <div class="inventory-categories">
                    <div id="inventory-category-list" class="category-buttons">
                        <button class="category-btn active" data-category="all">All</button>
                    </div>
                </div>
                <div class="inventory-grid" id="inventory-grid">
                    <!-- Inventory items will be populated here -->
                </div>
                <div class="equipped-items" id="equipped-items">
                    <h3>Equipped Items</h3>
                    <div id="equipped-items-container">
                        <!-- Equipped items will be populated here -->
                    </div>
                </div>
            </div>
        </div>
    `;
    
    document.body.appendChild(inventoryMenu);
    
    // Add close button event listener
    const closeBtn = document.getElementById('inventory-close-btn');
    if (closeBtn) {
        closeBtn.addEventListener('click', closeInventoryUI);
        closeBtn.hasEventListener = true;
    }
    initInventorySystem();
}

// Update inventory UI with new inventory data
function updateInventoryUI(inventory) {
    console.log('[CNR_INVENTORY] Updating inventory UI', inventory);
    
    const normalizedInventory = {};
    if (Array.isArray(inventory)) {
        inventory.forEach((item, index) => {
            if (!item) return;
            const itemId = item.itemId || item.id || `item_${index}`;
            normalizedInventory[itemId] = { ...item, itemId };
        });
    } else if (inventory && typeof inventory === 'object') {
        Object.entries(inventory).forEach(([itemId, item]) => {
            if (!item) return;
            normalizedInventory[itemId] = {
                ...item,
                itemId: item.itemId || itemId
            };
        });
    }

    currentInventoryData = normalizedInventory;
    playerInventoryData = normalizedInventory;
    
    // Update player info
    updateInventoryPlayerInfo();
    
    // Render inventory grid
    renderInventoryGrid();
    renderCategoryFilter();
}

// Update equipped items UI
function updateEquippedItemsUI(equippedItemList) {
    console.log('[CNR_INVENTORY] Updating equipped items UI', equippedItemList);
    
    currentEquippedItems = equippedItemList || [];
    equippedItems = new Set(Array.isArray(equippedItemList) ? equippedItemList : Object.keys(equippedItemList || {}));
    
    // Render equipped items
    renderEquippedItems();
}

// Render category filter buttons
function renderCategoryFilter() {
    const categoryList = document.getElementById('inventory-category-list');
    if (!categoryList) return;
    
    // Get unique categories from inventory
    const categories = new Set(['all']);
    
    if (window.fullItemConfig && Array.isArray(window.fullItemConfig)) {
        Object.values(playerInventoryData).forEach(item => {
            if (item.category) {
                categories.add(item.category);
            }
        });
    }
    
    categoryList.innerHTML = '';
    
    categories.forEach(category => {
        const btn = document.createElement('button');
        btn.className = 'category-btn';
        btn.textContent = category === 'all' ? 'All' : category;
        btn.dataset.category = category;
        
        if (category === currentInventoryTab) {
            btn.classList.add('active');
        }
        
        btn.addEventListener('click', () => {
            currentInventoryTab = category;
            renderInventoryGrid();
            
            // Update active button
            document.querySelectorAll('.category-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
        });
        
        categoryList.appendChild(btn);
    });
}

// Render inventory grid
function renderInventoryGrid() {
    const grid = document.getElementById('player-inventory-grid');
    if (!grid) return;
    
    grid.innerHTML = '';
    
    // Filter items based on current tab
    const filteredItems = Object.entries(playerInventoryData).filter(([itemId, itemData]) => {
        if (currentInventoryTab === 'all') return true;
        return itemData.category === currentInventoryTab;
    });
    
    if (filteredItems.length === 0) {
        const emptyState = document.createElement('div');
        emptyState.className = 'inventory-empty';
        emptyState.innerHTML = `
            <span class="empty-icon">📦</span>
            <div>No items in ${currentInventoryTab === 'all' ? 'inventory' : currentInventoryTab}</div>
        `;
        grid.appendChild(emptyState);
        return;
    }
    
    filteredItems.forEach(([itemId, itemData]) => {
        const itemElement = createInventoryItemElement(itemId, itemData);
        grid.appendChild(itemElement);
    });
}

// Create inventory item element
function createInventoryItemElement(itemId, itemData) {
    const item = document.createElement('div');
    item.className = 'inventory-item';
    item.dataset.itemId = itemId;
    
    // Check if item is equipped
    if (equippedItems.has(itemId)) {
        item.classList.add('equipped');
    }
    
    // Get item icon
    const icon = getItemIcon(itemData);
    
    item.innerHTML = `
        <span class="item-icon">${icon}</span>
        <div class="item-name">${itemData.name || itemId}</div>
        <div class="item-count">x${itemData.count || 0}</div>
    `;
    
    // Add click event
    item.addEventListener('click', () => selectInventoryItem(itemId, itemData, item));
    
    return item;
}

// Select inventory item
function selectInventoryItem(itemId, itemData, element) {
    // Clear previous selection
    document.querySelectorAll('.inventory-item').forEach(item => {
        item.classList.remove('selected');
    });
    
    // Select new item
    element.classList.add('selected');
    selectedInventoryItem = { itemId, itemData };
    
    // Show item actions panel
    showItemActionsPanel(itemId, itemData);
}

// Show item actions panel
function showItemActionsPanel(itemId, itemData) {
    const panel = document.getElementById('item-actions-panel');
    const nameEl = document.getElementById('selected-item-name');
    const descEl = document.getElementById('selected-item-description');
    const countEl = document.getElementById('selected-item-count');
    
    if (!panel || !nameEl || !descEl || !countEl) return;
    
    nameEl.textContent = itemData.name || itemId;
    descEl.textContent = getItemDescription(itemData);
    countEl.textContent = `Count: ${itemData.count || 0}`;
    
    // Update button states
    updateActionButtonStates(itemId, itemData);
    
    panel.classList.remove('hidden');
}

// Get item description
function getItemDescription(itemData) {
    const descriptions = {
        'Weapons': 'Combat weapon that can be equipped and used',
        'Melee Weapons': 'Close-range weapon for combat',
        'Ammunition': 'Ammunition for weapons',
        'Armor': 'Protective gear to reduce damage',
        'Utility': 'Useful item with special functions',
        'Explosives': 'Explosive device for combat',
        'Accessories': 'Cosmetic or minor functional item',
        'Cop Gear': 'Law enforcement equipment'
    };
    
    return descriptions[itemData.category] || 'Inventory item';
}

// Update action button states
function updateActionButtonStates(itemId, itemData) {
    const equipBtn = document.getElementById('equip-item-btn');
    const useBtn = document.getElementById('use-item-btn');
    const dropBtn = document.getElementById('drop-item-btn');
    
    if (!equipBtn || !useBtn || !dropBtn) return;
    
    const isEquipped = equippedItems.has(itemId);
    const canEquip = canItemBeEquipped(itemData);
    const canUse = canItemBeUsed(itemData);
    
    // Equip button
    equipBtn.disabled = !canEquip;
    equipBtn.textContent = isEquipped ? '🔓 Unequip' : '⚡ Equip';
    
    // Use button
    useBtn.disabled = !canUse;
    
    // Drop button
    dropBtn.disabled = false; // Can always drop items
}

// Check if item can be equipped
function canItemBeEquipped(itemData) {
    const equipableCategories = ['Weapons', 'Melee Weapons', 'Armor', 'Cop Gear', 'Utility'];
    return equipableCategories.includes(itemData.category);
}

// Check if item can be used
function canItemBeUsed(itemData) {
    const usableCategories = ['Utility', 'Armor', 'Cop Gear'];
    const usableItems = ['medkit', 'firstaidkit', 'armor', 'heavy_armor', 'spikestrip_item'];
    
    return usableCategories.includes(itemData.category) || usableItems.includes(itemData.itemId);
}

// Clear item selection
function clearItemSelection() {
    document.querySelectorAll('.inventory-item').forEach(item => {
        item.classList.remove('selected');
    });
    
    selectedInventoryItem = null;
    
    const panel = document.getElementById('item-actions-panel');
    if (panel) {
        panel.classList.add('hidden');
    }
}

// Equip/unequip selected item
async function equipSelectedItem() {
    if (!selectedInventoryItem) return;
    
    const { itemId, itemData } = selectedInventoryItem;
    const isEquipped = equippedItems.has(itemId);
    
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/equipInventoryItem`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({
                itemId: itemId,
                equip: !isEquipped
            })
        });
        
        const result = await response.json();
        if (result && result.success) {
            if (isEquipped) {
                equippedItems.delete(itemId);
                showToast(`Unequipped ${itemData.name}`, 'success', 2000);
            } else {
                equippedItems.add(itemId);
                showToast(`Equipped ${itemData.name}`, 'success', 2000);
            }
            
            // Update UI
            renderInventoryGrid();
            renderEquippedItems();
            updateActionButtonStates(itemId, itemData);
        } else {
            showToast(result.error || 'Failed to equip item', 'error', 3000);
        }
    } catch (error) {
        console.error('[CNR_INVENTORY] Error equipping item:', error);
        showToast('Error equipping item', 'error', 3000);
    }
}

// Use selected item
async function useSelectedItem() {
    if (!selectedInventoryItem) return;
    
    const { itemId, itemData } = selectedInventoryItem;
    
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/useInventoryItem`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({
                itemId: itemId
            })
        });
        
        const result = await response.json();
        if (result && result.success) {
            showToast(`Used ${itemData.name}`, 'success', 2000);
            
            // Refresh inventory if item was consumed
            if (result.consumed) {
                requestPlayerInventoryForUI();
                clearItemSelection();
            }
        } else {
            showToast(result.error || 'Failed to use item', 'error', 3000);
        }
    } catch (error) {
        console.error('[CNR_INVENTORY] Error using item:', error);
        showToast('Error using item', 'error', 3000);
    }
}

// Drop selected item
async function dropSelectedItem() {
    if (!selectedInventoryItem) return;
    
    const { itemId, itemData } = selectedInventoryItem;
    
    // Confirm drop
    const confirmed = confirm(`Are you sure you want to drop ${itemData.name}?`);
    if (!confirmed) return;
    
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/dropInventoryItem`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({
                itemId: itemId,
                quantity: 1
            })
        });
        
        const result = await response.json();
        if (result && result.success) {
            showToast(`Dropped ${itemData.name}`, 'success', 2000);
            requestPlayerInventoryForUI();
            clearItemSelection();
        } else {
            showToast(result.error || 'Failed to drop item', 'error', 3000);
        }
    } catch (error) {
        console.error('[CNR_INVENTORY] Error dropping item:', error);
        showToast('Error dropping item', 'error', 3000);
    }
}

// Render equipped items panel
function renderEquippedItems() {
    const container = document.getElementById('equipped-items');
    if (!container) return;
    
    container.innerHTML = '';
    
    if (equippedItems.size === 0) {
        const emptyState = document.createElement('div');
        emptyState.className = 'equipped-empty';
        emptyState.innerHTML = '<div style="text-align: center; color: #7f8c8d; font-size: 12px;">No items equipped</div>';
        container.appendChild(emptyState);
        return;
    }
    
    equippedItems.forEach(itemId => {
        const itemData = playerInventoryData[itemId];
        if (!itemData) return;
        
        const equippedItem = document.createElement('div');
        equippedItem.className = 'equipped-item';
        
        const icon = getItemIcon(itemData);
        
        equippedItem.innerHTML = `
            <span class="item-icon">${icon}</span>
            <div class="item-details">
                <div class="item-name">${itemData.name || itemId}</div>
                <div class="item-count">x${itemData.count || 0}</div>
            </div>
        `;
        
        container.appendChild(equippedItem);
    });
}

// Handle NUI messages for inventory
function handleInventoryMessage(data) {
    switch (data.action) {
        case 'openInventory':
            openInventoryUI(data);
            break;
        case 'closeInventory':
            closeInventoryUI();
            break;
        case 'updateInventory':
            updateInventoryUI(data.inventory);
            break;
        case 'updateEquippedItems':
            updateEquippedItemsUI(data.equippedItems);
            break;
    }
}

function openInventoryUI(data) {
    if (window.isInventoryOpen) return;

    window.isInventoryOpen = true;
    console.log('[CNR_INVENTORY] Opening inventory UI');
    
    // Set up inventory UI (this will handle both existing and new UI creation)
    createInventoryUI();
    
    // Show the inventory
    const inventoryContainer = document.getElementById('inventory-menu');
    if (inventoryContainer) {
        inventoryContainer.style.display = 'block';
        inventoryContainer.classList.remove('hidden');
        document.body.classList.add('inventory-open');
        
        // Set NUI focus
        fetchSetNuiFocus(true, true);
    }
    
    // Request initial inventory data
    fetch(`https://${CNRConfig.getResourceName()}/getPlayerInventoryForUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    }).then(response => response.json())
    .then(result => {
        if (result.success) {
            updateInventoryUI(result.inventory);
            updateEquippedItemsUI(result.equippedItems || []);
        }
    }).catch(error => {
        console.error('[CNR_INVENTORY] Failed to load inventory:', error);
    });
}

// ==============================================
// Robber Menu Functions
// ==============================================
let isRobberMenuOpen = false;

function showRobberMenu() {
    console.log('[CNR_ROBBER_MENU] Opening robber menu');

    hideRoleActionMenus();

    // Display the menu
    const robberMenu = document.getElementById('robber-menu');
    if (robberMenu) {
        robberMenu.classList.remove('hidden');
        document.body.classList.add('menu-open');
        isRobberMenuOpen = true;
        
        // Set up event listeners if they don't exist yet
        setupRobberMenuListeners();
    } else {
        console.error('[CNR_ROBBER_MENU] Could not find robber-menu element in the DOM');
    }
}

let isPoliceMenuOpen = false;
let policeCadRefreshInterval = null;
let latestPoliceCadData = { officers: [], calls: [], suspects: [] };
let latestCitationReasons = [];
let isPdGarageMenuOpen = false;

function hideRoleActionMenus() {
    const policeMenu = document.getElementById('police-menu');
    if (policeMenu) {
        policeMenu.classList.add('hidden');
    }

    const robberMenu = document.getElementById('robber-menu');
    if (robberMenu) {
        robberMenu.classList.add('hidden');
    }

    const pdGarageMenu = document.getElementById('pd-garage-menu');
    if (pdGarageMenu) {
        pdGarageMenu.classList.add('hidden');
    }

    if (policeCadRefreshInterval) {
        clearInterval(policeCadRefreshInterval);
        policeCadRefreshInterval = null;
    }

    document.body.classList.remove('menu-open');
    isPoliceMenuOpen = false;
    isRobberMenuOpen = false;
    isPdGarageMenuOpen = false;
}

function renderPdGarageVehicleList(vehicles = []) {
    if (!Array.isArray(vehicles) || vehicles.length === 0) {
        return `
            <div class="menu-result role-status-panel">
                No PD vehicles are currently authorized for your rank.
            </div>
        `;
    }

    return vehicles.map((vehicle) => `
        <button class="menu-btn pd-garage-vehicle-btn" data-model="${escapeHtml(vehicle.model || '')}">
            <span class="icon">🚓</span>
            <span>
                <strong>${escapeHtml(vehicle.label || vehicle.model || 'PD Vehicle')}</strong><br>
                <small>${escapeHtml(`${vehicle.category || 'PD Vehicle'} • ${vehicle.accessLabel || 'Authorized'}`)}</small>
            </span>
        </button>
    `).join('');
}

function updatePdGarageMenu(garage = {}) {
    const titleEl = document.getElementById('pd-garage-title');
    const subtitleEl = document.getElementById('pd-garage-subtitle');
    const summaryEl = document.getElementById('pd-garage-summary');
    const listEl = document.getElementById('pd-garage-vehicle-list');

    if (titleEl) {
        titleEl.textContent = garage.title || 'PD Garage';
    }
    if (subtitleEl) {
        subtitleEl.textContent = garage.subtitle || 'Authorized police vehicles and support services.';
    }
    if (summaryEl) {
        const activeCount = Number(garage.activeVehicleCount || 0);
        const maxCount = Number(garage.maxActiveVehicles || 0);
        summaryEl.textContent = maxCount > 0
            ? `Active issued vehicles: ${activeCount}/${maxCount}`
            : `Active issued vehicles: ${activeCount}`;
    }
    if (listEl) {
        listEl.innerHTML = renderPdGarageVehicleList(garage.vehicles || []);
    }
}

function showPdGarageMenu(garage = {}) {
    hideRoleActionMenus();

    let menu = document.getElementById('pd-garage-menu');
    if (!menu) {
        menu = document.createElement('section');
        menu.id = 'pd-garage-menu';
        menu.className = 'menu role-action-menu role-action-menu--police hidden';
        menu.setAttribute('role', 'dialog');
        menu.setAttribute('aria-modal', 'true');
        menu.setAttribute('aria-labelledby', 'pdGarageHeading');
        menu.innerHTML = `
            <div class="menu-header role-menu-header">
                <div>
                    <p class="role-menu-kicker">Mission Row Motor Pool</p>
                    <h1 id="pdGarageHeading">PD Garage</h1>
                    <p id="pd-garage-subtitle" class="role-menu-subtitle">Authorized police vehicles and support services.</p>
                </div>
                <button id="pd-garage-close-btn" class="close-btn" aria-label="Close PD Garage">
                    <span class="close-icon">✕</span>
                </button>
            </div>
            <div class="role-menu-layout role-menu-layout--single">
                <div class="role-menu-main">
                    <section class="role-card">
                        <div class="role-card-heading">
                            <div>
                                <h2 id="pd-garage-title">PD Garage</h2>
                                <p id="pd-garage-summary">Active issued vehicles: 0</p>
                            </div>
                        </div>
                        <div id="pd-garage-vehicle-list" class="role-action-grid"></div>
                    </section>
                    <section class="role-card">
                        <div class="role-card-heading">
                            <div>
                                <h2>Garage Actions</h2>
                                <p>Return issued units, service patrol cars, and clean up abandoned PD vehicles.</p>
                            </div>
                        </div>
                        <div class="role-action-grid">
                            <button id="pd-garage-store-btn" class="menu-btn"><span class="icon">📥</span>Store Current Vehicle</button>
                            <button id="pd-garage-repair-btn" class="menu-btn"><span class="icon">🔧</span>Repair Vehicle</button>
                            <button id="pd-garage-refuel-btn" class="menu-btn"><span class="icon">⛽</span>Refuel Vehicle</button>
                            <button id="pd-garage-delete-btn" class="menu-btn"><span class="icon">🧹</span>Delete Abandoned PD Vehicle</button>
                        </div>
                    </section>
                </div>
            </div>
        `;
        document.body.appendChild(menu);
    }

    updatePdGarageMenu(garage);
    menu.classList.remove('hidden');
    document.body.classList.add('menu-open');
    isPdGarageMenuOpen = true;
    setupPdGarageMenuListeners();
}

function hidePdGarageMenu() {
    const menu = document.getElementById('pd-garage-menu');
    if (menu) {
        menu.classList.add('hidden');
    }
    document.body.classList.remove('menu-open');
    isPdGarageMenuOpen = false;
    fetchSetNuiFocus(false, false);
}

async function performPdGarageAction(endpoint, payload = {}, successMessage = 'Garage action completed.') {
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const result = await response.json();
        if (result && result.success) {
            showToast(successMessage, 'success');
            return true;
        }

        showToast((result && result.error) || 'Garage action failed.', 'error');
        return false;
    } catch (error) {
        showToast('Garage action failed.', 'error');
        return false;
    }
}

function setupPdGarageMenuListeners() {
    const bindOnce = (id, handler) => {
        const el = document.getElementById(id);
        if (el && !el.hasEventListener) {
            el.addEventListener('click', handler);
            el.hasEventListener = true;
        }
    };

    bindOnce('pd-garage-close-btn', hidePdGarageMenu);
    bindOnce('pd-garage-store-btn', () => performPdGarageAction('pdGarageStoreVehicle', {}, 'PD vehicle stored.'));
    bindOnce('pd-garage-repair-btn', () => performPdGarageAction('pdGarageRepairVehicle', {}, 'PD vehicle repaired.'));
    bindOnce('pd-garage-refuel-btn', () => performPdGarageAction('pdGarageRefuelVehicle', {}, 'PD vehicle refueled.'));
    bindOnce('pd-garage-delete-btn', () => performPdGarageAction('pdGarageDeleteAbandoned', {}, 'Abandoned PD vehicle deleted.'));

    const menu = document.getElementById('pd-garage-menu');
    if (menu && !menu.hasVehicleListener) {
        menu.addEventListener('click', async (event) => {
            const vehicleButton = event.target.closest('.pd-garage-vehicle-btn');
            if (!vehicleButton) {
                return;
            }

            const model = vehicleButton.dataset.model;
            if (!model) {
                showToast('Invalid PD vehicle selection.', 'error');
                return;
            }

            const success = await performPdGarageAction('pdGarageSpawnVehicle', { model }, 'PD vehicle deployed.');
            if (success) {
                hidePdGarageMenu();
            }
        });
        menu.hasVehicleListener = true;
    }
}

function showPoliceMenu(data = {}) {
    hideRoleActionMenus();

    let policeMenu = document.getElementById('police-menu');
    if (!policeMenu) {
        policeMenu = document.createElement('section');
        policeMenu.id = 'police-menu';
        policeMenu.className = 'menu role-action-menu role-action-menu--police hidden';
        policeMenu.setAttribute('role', 'dialog');
        policeMenu.setAttribute('aria-modal', 'true');
        policeMenu.setAttribute('aria-labelledby', 'policeMenuHeading');
        policeMenu.innerHTML = `
            <div class="menu-header role-menu-header">
                <div>
                    <p class="role-menu-kicker">Law Enforcement Operations</p>
                    <h1 id="policeMenuHeading">Police Menu</h1>
                    <p class="role-menu-subtitle">Coordinate units, manage live dispatch traffic, and control the scene without losing visibility.</p>
                </div>
                <button id="police-menu-close-btn" class="close-btn" aria-label="Close Police Menu">
                    <span class="close-icon">✕</span>
                </button>
            </div>
            <div class="role-menu-layout">
                <div class="role-menu-main">
                    <section class="role-card role-card--featured role-scroll-section">
                        <div class="role-card-heading">
                            <div>
                                <h2>Active CAD Calls</h2>
                                <p>Current scenes, priority levels, response history, and backup traffic.</p>
                            </div>
                        </div>
                        <div id="police-cad-calls-list" class="dispatch-list dispatch-list--featured"></div>
                    </section>
                    <section class="role-card role-live-map-card">
                        <div class="role-card-heading">
                            <div>
                                <h2>Live Operations Map</h2>
                                <p>Visualize on-duty units, active scenes, and wanted suspects in one shared command view.</p>
                            </div>
                        </div>
                        <div class="live-map-shell">
                            <div id="police-live-map" class="live-map-canvas"></div>
                            <div id="police-live-map-details" class="live-map-details"></div>
                        </div>
                    </section>
                    <section class="role-card">
                        <div class="role-card-heading">
                            <div>
                                <h2>Quick Actions</h2>
                                <p>Immediate tools for field support and suspect tracking.</p>
                            </div>
                        </div>
                        <div class="role-action-grid">
                            <button id="police-call-vehicle-btn" class="menu-btn"><span class="icon">🚓</span>Open PD Garage</button>
                            <button id="police-request-assist-btn" class="menu-btn"><span class="icon">📻</span>Request Assistance</button>
                            <button id="police-request-urgent-assist-btn" class="menu-btn"><span class="icon">🚨</span>Urgent Backup</button>
                            <button id="police-view-bounties-btn" class="menu-btn"><span class="icon">🔎</span>Wanted Players</button>
                        </div>
                    </section>
                    <section class="role-card">
                        <div class="role-card-heading">
                            <div>
                                <h2>Lookup & Communications</h2>
                                <p>Run checks, send updates, and issue citations from one place.</p>
                            </div>
                        </div>
                        <div class="menu-inline-form menu-inline-form--compact">
                            <input id="police-lookup-player-id" type="number" min="1" placeholder="Robber player ID">
                            <button id="police-lookup-btn" class="menu-btn">Look Up</button>
                        </div>
                        <div class="menu-inline-form">
                            <input id="police-text-target-id" type="number" min="1" placeholder="Player ID">
                            <input id="police-text-message" type="text" maxlength="180" placeholder="Text message">
                            <button id="police-send-text-btn" class="menu-btn">Send Text</button>
                        </div>
                        <div class="menu-inline-form menu-inline-form--citation">
                            <input id="police-citation-target-id" type="number" min="1" placeholder="Target ID">
                            <select id="police-citation-reason"></select>
                            <input id="police-citation-amount" type="number" min="0" placeholder="Fine">
                            <button id="police-issue-citation-btn" class="menu-btn">Issue Citation</button>
                        </div>
                        <div id="police-lookup-result" class="menu-result role-status-panel">Lookup results will appear here.</div>
                    </section>
                    <section class="role-card">
                        <div class="role-card-heading">
                            <div>
                                <h2>CAD Call Intake</h2>
                                <p>Create new incidents and flag scenes that need backup right away.</p>
                            </div>
                        </div>
                        <div class="menu-inline-form">
                            <input id="police-cad-title" type="text" maxlength="80" placeholder="CAD call title">
                            <input id="police-cad-details" type="text" maxlength="240" placeholder="Details">
                        </div>
                        <div class="menu-inline-form menu-inline-form--cad">
                            <select id="police-cad-priority">
                                <option value="Low">Low</option>
                                <option value="Medium">Medium</option>
                                <option value="High">High</option>
                                <option value="Critical">Critical</option>
                            </select>
                            <label class="menu-toggle"><input id="police-cad-backup" type="checkbox"> Backup</label>
                            <label class="menu-toggle"><input id="police-cad-urgent" type="checkbox"> ASAP</label>
                            <button id="police-create-cad-call-btn" class="menu-btn">Create CAD Call</button>
                        </div>
                        <div id="police-cad-status" class="menu-result role-status-panel">Create, update, and coordinate active calls from here.</div>
                    </section>
                </div>
                <aside class="role-menu-sidebar">
                    <section class="role-card role-scroll-section">
                        <div class="role-card-heading">
                            <div>
                                <h2>On-Duty Units</h2>
                                <p>Live telemetry for every active officer.</p>
                            </div>
                        </div>
                        <div id="police-cad-units-list" class="dispatch-list"></div>
                    </section>
                    <section class="role-card role-scroll-section">
                        <div class="role-card-heading">
                            <div>
                                <h2>Wanted Snapshot</h2>
                                <p>Fast reference for the hottest suspects in the city.</p>
                            </div>
                        </div>
                        <div id="police-cad-suspects-list" class="dispatch-list"></div>
                    </section>
                    <section class="role-card role-scroll-section">
                        <div class="role-card-heading">
                            <div>
                                <h2>Player Directory</h2>
                                <p>Quick ID roster for locating, messaging, and citing players.</p>
                            </div>
                        </div>
                        <div id="police-player-directory" class="dispatch-list"></div>
                    </section>
                </aside>
            </div>
        `;
        document.body.appendChild(policeMenu);
    }

    policeMenu.classList.remove('hidden');
    document.body.classList.add('menu-open');
    isPoliceMenuOpen = true;
    setupPoliceMenuListeners();
    updatePoliceCadData(data.cadData || latestPoliceCadData, data.citationReasons || latestCitationReasons);
    loadPoliceCadData();

    if (policeCadRefreshInterval) {
        clearInterval(policeCadRefreshInterval);
    }
    policeCadRefreshInterval = setInterval(() => {
        if (isPoliceMenuOpen) {
            loadPoliceCadData(false);
        }
    }, 5000);
}

function hidePoliceMenu() {
    const policeMenu = document.getElementById('police-menu');
    if (policeMenu) {
        policeMenu.classList.add('hidden');
    }
    document.body.classList.remove('menu-open');
    isPoliceMenuOpen = false;
    if (policeCadRefreshInterval) {
        clearInterval(policeCadRefreshInterval);
        policeCadRefreshInterval = null;
    }
    fetchSetNuiFocus(false, false);
}

function updatePoliceCadData(cadData = {}, citationReasons = []) {
    latestPoliceCadData = cadData || { officers: [], calls: [], suspects: [] };
    latestCitationReasons = citationReasons || [];
    const renderChip = (label, variant = '') => `<span class="dispatch-chip${variant ? ` dispatch-chip--${variant}` : ''}">${escapeHtml(label)}</span>`;
    const renderEmptyCard = (title, detail) => `
        <article class="dispatch-card dispatch-card--empty">
            <h3 class="dispatch-card-title">${escapeHtml(title)}</h3>
            ${detail ? `<p class="dispatch-card-body">${escapeHtml(detail)}</p>` : ''}
        </article>
    `;
    const formatLocation = (entryOrCoords) => (
        entryOrCoords?.locationLabel
            ? entryOrCoords.locationLabel
            : entryOrCoords && Number.isFinite(Number(entryOrCoords.x)) && Number.isFinite(Number(entryOrCoords.y))
                ? `${Math.floor(Number(entryOrCoords.x))}, ${Math.floor(Number(entryOrCoords.y))}`
                : 'Unknown'
    );
    const formatTimestamp = (timestamp) => (
        timestamp
            ? new Date(Number(timestamp) * 1000).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })
            : 'Unknown'
    );

    const citationSelect = document.getElementById('police-citation-reason');
    if (citationSelect) {
        const previousValue = citationSelect.value;
        citationSelect.innerHTML = '';
        latestCitationReasons.forEach(reason => {
            const option = document.createElement('option');
            option.value = reason.id;
            option.textContent = `${reason.label} ($${reason.fine || 0})`;
            option.dataset.fine = reason.fine || 0;
            citationSelect.appendChild(option);
        });
        if (previousValue && latestCitationReasons.some(reason => reason.id === previousValue)) {
            citationSelect.value = previousValue;
        }
    }

    const unitsList = document.getElementById('police-cad-units-list');
    if (unitsList) {
        const officers = latestPoliceCadData.officers || [];
        unitsList.innerHTML = officers.length > 0
            ? officers.map((officer) => {
                const coords = formatLocation(officer);
                const vehicleInfo = officer.vehicleModel
                    ? `${officer.vehicleType || 'Vehicle'}: ${officer.vehicleModel}`
                    : 'On foot';
                const speed = `${Math.round(Number(officer.speedMph) || 0)} mph`;
                const rank = officer.rank || 'Officer';
                const name = officer.name || 'Unknown';
                const level = officer.level ? `Level ${officer.level}` : 'On duty';
                return `
                    <article class="dispatch-card">
                        <div class="dispatch-card-header">
                            <div>
                                <h3 class="dispatch-card-title">${escapeHtml(`${rank} ${name} (#${officer.serverId || '?'})`)}</h3>
                                <p class="dispatch-card-subtitle">${escapeHtml(level)}</p>
                            </div>
                            <span class="dispatch-pill">${escapeHtml(officer.equipped || 'Unarmed')}</span>
                        </div>
                        <div class="dispatch-chip-row">
                            ${renderChip(vehicleInfo)}
                            ${renderChip(speed)}
                            ${renderChip(coords)}
                        </div>
                    </article>
                `;
            }).join('')
            : renderEmptyCard('No police units online.', 'Active officers will appear here once they are on duty.');
    }

    const callsList = document.getElementById('police-cad-calls-list');
    if (callsList) {
        const calls = latestPoliceCadData.calls || [];
        callsList.innerHTML = calls.length > 0
            ? calls.map((call) => {
                const location = formatLocation(call);
                const priorityClass = String(call.priority || 'medium').toLowerCase();
                const detail = call.details || 'No additional notes entered.';
                const history = Array.isArray(call.history) ? call.history : [];
                const historyHtml = history.length > 0
                    ? `
                        <div class="dispatch-history">
                            ${history.slice().reverse().map((entry) => `
                                <div class="dispatch-history-item">
                                    <span class="dispatch-history-status">${escapeHtml(entry.status || 'Update')}</span>
                                    <span class="dispatch-history-meta">${escapeHtml(`${entry.byName || 'Unknown'} • ${formatTimestamp(entry.timestamp)}`)}</span>
                                </div>
                            `).join('')}
                        </div>
                    `
                    : '';
                return `
                    <article class="dispatch-card dispatch-card--call">
                        <div class="dispatch-card-header">
                            <div>
                                <h3 class="dispatch-card-title">${escapeHtml(`#${call.id} ${call.title || 'Untitled Call'}`)}</h3>
                                <p class="dispatch-card-subtitle">${escapeHtml(`By ${call.createdByName || 'Unknown'}`)}</p>
                            </div>
                            <span class="dispatch-pill dispatch-pill--${escapeHtml(priorityClass)}">${escapeHtml(call.priority || 'Medium')}</span>
                        </div>
                        <div class="dispatch-chip-row">
                            ${renderChip(call.status || 'Open')}
                            ${renderChip(location)}
                            ${call.requestBackup ? renderChip('Backup requested', 'warning') : ''}
                            ${call.urgent ? renderChip('ASAP', 'danger') : ''}
                        </div>
                        <p class="dispatch-card-body">${escapeHtml(detail)}</p>
                        ${historyHtml}
                        <div class="dispatch-action-row">
                            <button class="menu-btn cad-status-btn" data-call-id="${call.id}" data-status="En Route">En Route</button>
                            <button class="menu-btn cad-status-btn" data-call-id="${call.id}" data-status="On Scene">On Scene</button>
                            <button class="menu-btn cad-status-btn" data-call-id="${call.id}" data-status="Resolved">Resolve</button>
                        </div>
                    </article>
                `;
            }).join('')
            : renderEmptyCard('No active CAD calls.', 'New incidents and backup requests will populate this feed.');
    }

    const suspectsList = document.getElementById('police-cad-suspects-list');
    if (suspectsList) {
        const suspects = latestPoliceCadData.suspects || [];
        suspectsList.innerHTML = suspects.length > 0
            ? suspects.map((suspect) => {
                const starCount = Math.min(Number(suspect.wantedStars) || 0, 5);
                const stars = starCount > 0 ? '★'.repeat(starCount) : 'No stars';
                const location = formatLocation(suspect);
                return `
                    <article class="dispatch-card">
                        <div class="dispatch-card-header">
                            <div>
                                <h3 class="dispatch-card-title">${escapeHtml(`${suspect.name || 'Unknown'} (#${suspect.playerId || '?'})`)}</h3>
                                <p class="dispatch-card-subtitle">${escapeHtml(`Wanted level ${suspect.wantedLevel || 0}`)}</p>
                            </div>
                            <span class="dispatch-pill dispatch-pill--danger">${escapeHtml(stars)}</span>
                        </div>
                        <div class="dispatch-chip-row">
                            ${renderChip(`Bounty $${formatCurrencyDisplay(suspect.bounty || 0)}`, 'warning')}
                            ${renderChip(`Heat ${suspect.wantedLevel || 0}`)}
                            ${renderChip(location)}
                        </div>
                    </article>
                `;
            }).join('')
            : renderEmptyCard('No wanted suspects right now.', 'When suspects build heat, they will show up here.');
    }

    const playerDirectory = document.getElementById('police-player-directory');
    if (playerDirectory) {
        const players = latestPoliceCadData.players || [];
        playerDirectory.innerHTML = players.length > 0
            ? players.map((player) => `
                <article class="dispatch-card dispatch-card--roster">
                    <div class="dispatch-card-header">
                        <div>
                            <h3 class="dispatch-card-title">${escapeHtml(`${player.name || 'Unknown'} (#${player.serverId || '?'})`)}</h3>
                            <p class="dispatch-card-subtitle">${escapeHtml(player.role || 'citizen')}</p>
                        </div>
                        <span class="dispatch-pill">ID ${escapeHtml(String(player.serverId || '?'))}</span>
                    </div>
                    <div class="dispatch-chip-row">
                        ${renderChip(player.role === 'cop' ? 'Cop' : player.role === 'robber' ? 'Robber' : 'Civilian', player.role === 'cop' ? 'cop' : player.role === 'robber' ? 'warning' : '')}
                    </div>
                    <div class="dispatch-action-row">
                        <button class="menu-btn police-roster-fill-btn" data-player-id="${player.serverId}">Use ID</button>
                        <button class="menu-btn police-roster-lookup-btn" data-player-id="${player.serverId}">Look Up</button>
                    </div>
                </article>
            `).join('')
            : renderEmptyCard('No online players found.', 'Connected players will appear here.');
    }

    const selectedReason = latestCitationReasons.find(reason => reason.id === (citationSelect && citationSelect.value));
    const citationAmount = document.getElementById('police-citation-amount');
    if (selectedReason && citationAmount && !citationAmount.dataset.userEdited) {
        citationAmount.value = selectedReason.fine || 0;
    }

    renderPoliceLiveMap();
}

async function loadPoliceCadData(showErrors = true) {
    try {
        const response = await fetch(`https://${CNRConfig.getResourceName()}/requestPoliceCadData`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        const result = await response.json();
        if (result.success) {
            updatePoliceCadData(result.cadData || {}, result.citationReasons || []);
        } else if (showErrors) {
            showToast(result.error || 'Unable to load CAD data.', 'error');
        }
    } catch (error) {
        if (showErrors) {
            showToast('Unable to load CAD data.', 'error');
        }
    }
}

function setupPoliceMenuListeners() {
    const bindOnce = (id, handler) => {
        const el = document.getElementById(id);
        if (el && !el.hasEventListener) {
            el.addEventListener('click', handler);
            el.hasEventListener = true;
        }
    };

    bindOnce('police-menu-close-btn', hidePoliceMenu);
    bindOnce('police-call-vehicle-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/requestPdGarageMenu`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        hidePoliceMenu();
    });
    bindOnce('police-request-assist-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/requestPoliceAssistance`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ urgent: false })
        });
        hidePoliceMenu();
    });
    bindOnce('police-request-urgent-assist-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/requestPoliceAssistance`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ urgent: true })
        });
        hidePoliceMenu();
    });
    bindOnce('police-view-bounties-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/viewBounties`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        hidePoliceMenu();
    });
    bindOnce('police-lookup-btn', async () => {
        const input = document.getElementById('police-lookup-player-id');
        const resultEl = document.getElementById('police-lookup-result');
        const targetId = parseInt(input?.value || '0');
        if (!targetId) {
            if (resultEl) resultEl.textContent = 'Enter a valid player ID.';
            return;
        }

        try {
            const response = await fetch(`https://${CNRConfig.getResourceName()}/lookupRobberInfo`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ targetId })
            });
            const result = await response.json();
            if (resultEl) {
                if (result.success) {
                    resultEl.textContent = `${result.name || 'Player'} | Wanted: ${result.wantedLevel || 0} | Arrests: ${result.arrests || 0}`;
                } else {
                    resultEl.textContent = result.error || 'No record found.';
                }
            }
        } catch (error) {
            if (resultEl) resultEl.textContent = 'Lookup failed.';
        }
    });
    bindOnce('police-send-text-btn', async () => {
        const targetId = parseInt(document.getElementById('police-text-target-id')?.value || '0');
        const message = (document.getElementById('police-text-message')?.value || '').trim();
        if (!targetId || !message) {
            showToast('Enter a target player and a message.', 'error');
            return;
        }

        await fetch(`https://${CNRConfig.getResourceName()}/sendRoleTextMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ targetId, message })
        });
        document.getElementById('police-text-message').value = '';
        showToast('Message sent.', 'success');
    });
    bindOnce('police-issue-citation-btn', async () => {
        const targetId = parseInt(document.getElementById('police-citation-target-id')?.value || '0');
        const citationId = document.getElementById('police-citation-reason')?.value;
        const amount = parseInt(document.getElementById('police-citation-amount')?.value || '0');
        if (!targetId || !citationId) {
            showToast('Choose a target and citation reason.', 'error');
            return;
        }

        await fetch(`https://${CNRConfig.getResourceName()}/issuePoliceCitation`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ targetId, citationId, amount })
        });
        showToast('Citation submitted.', 'success');
    });
    bindOnce('police-create-cad-call-btn', async () => {
        const title = (document.getElementById('police-cad-title')?.value || '').trim();
        const details = (document.getElementById('police-cad-details')?.value || '').trim();
        const priority = document.getElementById('police-cad-priority')?.value || 'Medium';
        const requestBackup = document.getElementById('police-cad-backup')?.checked === true;
        const urgent = document.getElementById('police-cad-urgent')?.checked === true;
        if (!title) {
            showToast('Enter a CAD call title.', 'error');
            return;
        }

        await fetch(`https://${CNRConfig.getResourceName()}/createCadCall`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title, details, priority, requestBackup, urgent })
        });
        document.getElementById('police-cad-title').value = '';
        document.getElementById('police-cad-details').value = '';
        showToast('CAD call created.', 'success');
    });

    const citationReason = document.getElementById('police-citation-reason');
    if (citationReason && !citationReason.hasChangeListener) {
        citationReason.addEventListener('change', () => {
            const selectedReason = latestCitationReasons.find(reason => reason.id === citationReason.value);
            const citationAmount = document.getElementById('police-citation-amount');
            if (selectedReason && citationAmount) {
                citationAmount.dataset.userEdited = '';
                citationAmount.value = selectedReason.fine || 0;
            }
        });
        citationReason.hasChangeListener = true;
    }

    const citationAmount = document.getElementById('police-citation-amount');
    if (citationAmount && !citationAmount.hasInputListener) {
        citationAmount.addEventListener('input', () => {
            citationAmount.dataset.userEdited = 'true';
        });
        citationAmount.hasInputListener = true;
    }

    const policeMenu = document.getElementById('police-menu');
    if (policeMenu && !policeMenu.hasCadListener) {
        policeMenu.addEventListener('click', async (event) => {
            const rosterButton = event.target.closest('.police-roster-fill-btn, .police-roster-lookup-btn');
            if (rosterButton) {
                const playerId = parseInt(rosterButton.dataset.playerId || '0');
                if (!playerId) return;

                ['police-lookup-player-id', 'police-text-target-id', 'police-citation-target-id'].forEach((inputId) => {
                    const input = document.getElementById(inputId);
                    if (input) {
                        input.value = playerId;
                    }
                });

                if (rosterButton.classList.contains('police-roster-lookup-btn')) {
                    document.getElementById('police-lookup-btn')?.click();
                } else {
                    showToast(`Loaded player #${playerId} into police actions.`, 'info');
                }
                return;
            }

            const statusButton = event.target.closest('.cad-status-btn');
            if (!statusButton) return;

            const callId = parseInt(statusButton.dataset.callId || '0');
            const status = statusButton.dataset.status || 'Open';
            if (!callId) return;

            await fetch(`https://${CNRConfig.getResourceName()}/updateCadCallStatus`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ callId, status })
            });
            showToast(`CAD call #${callId} updated to ${status}.`, 'success');
        });
        policeMenu.hasCadListener = true;
    }
}

function hideRobberMenu() {
    console.log('[CNR_ROBBER_MENU] Closing robber menu');
    
    const robberMenu = document.getElementById('robber-menu');
    if (robberMenu) {
        robberMenu.classList.add('hidden');
        document.body.classList.remove('menu-open');
        isRobberMenuOpen = false;
    }
    
    // Reset NUI focus
    fetchSetNuiFocus(false, false);
}

function setupRobberMenuListeners() {
    const bindOnce = (id, handler) => {
        const el = document.getElementById(id);
        if (el && !el.hasEventListener) {
            el.addEventListener('click', handler);
            el.hasEventListener = true;
        }
    };

    // Close button
    bindOnce('robber-menu-close-btn', hideRobberMenu);
    bindOnce('robber-call-vehicle-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/callRoleVehicle`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ role: 'robber' })
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error requesting vehicle:', error));
        hideRobberMenu();
    });
    bindOnce('robber-create-crew-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/startHeist`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error creating crew:', error));
        hideRobberMenu();
    });
    bindOnce('start-heist-btn', () => {
        console.log('[CNR_ROBBER_MENU] Start heist button clicked');
        fetch(`https://${CNRConfig.getResourceName()}/startHeist`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error triggering heist:', error));
        hideRobberMenu();
    });
    bindOnce('robber-wanted-status-btn', async () => {
        const resultEl = document.getElementById('robber-status-result');
        try {
            const response = await fetch(`https://${CNRConfig.getResourceName()}/getRobberStatus`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            const result = await response.json();
            if (resultEl) {
                if (result.success) {
                    resultEl.textContent = result.isWanted
                        ? `Wanted: ${result.wantedStars || 0} stars (${result.wantedLevel || 0} heat)`
                        : 'You are currently clean.';
                } else {
                    resultEl.textContent = result.error || 'Unable to fetch your status.';
                }
            }
        } catch (error) {
            if (resultEl) {
                resultEl.textContent = 'Unable to fetch your status.';
            }
        }
    });
    bindOnce('view-bounties-btn', () => {
        console.log('[CNR_ROBBER_MENU] View bounties button clicked');
        fetch(`https://${CNRConfig.getResourceName()}/viewBounties`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error viewing bounties:', error));
        hideRobberMenu();
    });
    bindOnce('find-hideout-btn', () => {
        console.log('[CNR_ROBBER_MENU] Find hideout button clicked');
        fetch(`https://${CNRConfig.getResourceName()}/findHideout`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error finding hideout:', error));
        hideRobberMenu();
    });
    bindOnce('buy-contraband-btn', () => {
        console.log('[CNR_ROBBER_MENU] Buy contraband button clicked');
        fetch(`https://${CNRConfig.getResourceName()}/buyContraband`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error buying contraband:', error));
        hideRobberMenu();
    });
    bindOnce('robber-request-assist-btn', () => {
        fetch(`https://${CNRConfig.getResourceName()}/requestRobberAssistance`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ urgent: false })
        }).catch(error => console.error('[CNR_ROBBER_MENU] Error requesting assistance:', error));
        hideRobberMenu();
    });
    bindOnce('robber-send-text-btn', async () => {
        const targetId = parseInt(document.getElementById('robber-text-target-id')?.value || '0');
        const message = (document.getElementById('robber-text-message')?.value || '').trim();
        if (!targetId || !message) {
            showToast('Enter a target player and message.', 'error');
            return;
        }

        await fetch(`https://${CNRConfig.getResourceName()}/sendRoleTextMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ targetId, message })
        });
        document.getElementById('robber-text-message').value = '';
        showToast('Message sent.', 'success');
    });
}

// ====================================================================
// Bounty List Functionality
// ====================================================================

/**
 * Shows the bounty list UI with provided bounty data
 * @param {Array} bounties - Array of bounty objects with player info
 */
function showBountyList(bounties) {
    console.log('[CNR_UI] Showing bounty list with', bounties.length, 'bounties');
    
    const container = document.getElementById('bounty-list-container');
    const list = document.getElementById('bounty-list');
    
    // Clear existing items
    list.innerHTML = '';
    
    if (bounties.length === 0) {
        list.innerHTML = '<div class="bounty-item"><div class="bounty-info"><span class="bounty-name">No wanted criminals at this time</span></div></div>';
    } else {
        // Sort bounties by wanted level/reward (highest first)
        bounties.sort((a, b) => (b.wantedLevel || 0) - (a.wantedLevel || 0));
        
        bounties.forEach(bounty => {
            const bountyItem = document.createElement('div');
            bountyItem.className = 'bounty-item';
            
            // Calculate reward based on wanted level (if not provided)
            const reward = bounty.reward || (bounty.wantedLevel * 500);
            
            // Create wanted level display (stars based on level)
            const starsHTML = '⭐'.repeat(Math.min(bounty.wantedLevel || 0, 5));
            
            bountyItem.innerHTML = `
                <div class="bounty-info">
                    <span class="bounty-name">${bounty.name || 'Unknown Criminal'}</span>
                    <span class="bounty-wanted-level">${starsHTML} Wanted Level: ${bounty.wantedLevel || 0}</span>
                </div>
                <div class="bounty-reward">$${reward.toLocaleString()}</div>
            `;
            
            list.appendChild(bountyItem);
        });
    }
    
    // Show the container
    container.classList.remove('hidden');
    
    // Set up close button
    const closeBtn = document.getElementById('close-bounty-list-btn');
    if (closeBtn) {
        closeBtn.onclick = hideBountyList;
    }
    
    // Set NUI focus
    fetchSetNuiFocus(true, true);
}

/**
 * Hides the bounty list UI
 */
function hideBountyList() {
    console.log('[CNR_UI] Hiding bounty list');
    const container = document.getElementById('bounty-list-container');
    container.classList.add('hidden');
    
    // Release NUI focus
    fetchSetNuiFocus(false, false);
}

// ====================================================================
// Speedometer Functionality
// ====================================================================

/**
 * Updates the speedometer display with the current speed
 * @param {number} speed - Current speed in MPH
 */
function updateSpeedometer(speed) {
    const speedValueEl = document.getElementById('speed-value');
    if (speedValueEl) {
        speedValueEl.textContent = Math.round(speed);
    }
}

/**
 * Shows or hides the speedometer based on whether player is in an appropriate vehicle
 * @param {boolean} show - Whether to show the speedometer
 */
function toggleSpeedometer(show) {
    const speedometerEl = document.getElementById('speedometer');
    if (speedometerEl) {
        if (show) {
            speedometerEl.classList.remove('hidden');
        } else {
            speedometerEl.classList.add('hidden');
        }
    }
}

// Initialize speedometer update when the script loads
document.addEventListener('DOMContentLoaded', function() {
    // We'll receive speed updates from client.lua, no need to poll here
    
    // Set up the close button for bounty list if it exists
    const closeBountyBtn = document.getElementById('close-bounty-list-btn');
    if (closeBountyBtn) {
        closeBountyBtn.addEventListener('click', hideBountyList);
    }
    
    // Initialize character editor
    initializeCharacterEditor();
});

// ====================================================================
// Character Editor Functions
// ====================================================================

// Character editor data is already declared at the top of the file

function initializeCharacterEditor() {
    window.characterEditorLegacyUiInitialized = true;
    window.characterEditorLegacyHandlersSetup = true;
}

function switchCustomizationTab(category) {
    // Update tab buttons
    document.querySelectorAll('.customization-tabs .tab-btn').forEach(btn => {
        btn.classList.remove('active');
        if (btn.getAttribute('data-category') === category) {
            btn.classList.add('active');
        }
    });

    // Update tab content
    document.querySelectorAll('.customization-tab').forEach(tab => {
        tab.classList.remove('active');
    });

    const targetTab = document.getElementById(category + '-tab');
    if (targetTab) {
        targetTab.classList.add('active');
    }
}

function syncClothingControl(entryType, targetId, valueType, value) {
    const slider = document.getElementById(`${entryType}-${targetId}-${valueType}-slider`);
    if (!slider) {
        return;
    }

    slider.value = value;

    const valueDisplay = slider.parentElement.querySelector('.slider-value');
    if (valueDisplay) {
        valueDisplay.textContent = value.toString();
    }
}

function ensureEnhancedCharacterEditor() {
    if (window.enhancedCharacterEditor && window.enhancedCharacterEditor.editorElement) {
        return window.enhancedCharacterEditor;
    }

    const editorElement = document.getElementById('character-editor-container');
    if (!editorElement) {
        return null;
    }

    window.enhancedCharacterEditor = new EnhancedCharacterEditor();
    return window.enhancedCharacterEditor;
}

function openCharacterEditor(data) {
    const editor = ensureEnhancedCharacterEditor();
    if (!editor) {
        console.error('[CNR_CHARACTER_EDITOR] Enhanced character editor is not initialized');
        return;
    }

    editor.openEditor(data);
}

function closeCharacterEditor() {
    const editor = ensureEnhancedCharacterEditor();
    if (editor) {
        editor.closeEditor(false, false);
    }
}

function updateCharacterSlot(characterKey, characterData) {
    console.log('[CNR_CHARACTER_EDITOR] Updating character slot:', characterKey);
    
    try {
        // Update the character slots display in role selection
        const roleSelectionUI = document.getElementById('role-selection-ui');
        if (roleSelectionUI) {
            // Find character slot elements and update them
            const slotElements = roleSelectionUI.querySelectorAll(`[data-character-key="${characterKey}"]`);
            slotElements.forEach(element => {
                element.classList.remove('empty');
                element.classList.add('filled');
                
                // Update slot display text if it exists
                const slotText = element.querySelector('.slot-status');
                if (slotText) {
                    slotText.textContent = 'Character Created';
                }
            });
        }

        if (window.enhancedCharacterEditor) {
            window.enhancedCharacterEditor.updateCharacterSlot(characterKey, characterData);
        }
        
        console.log('[CNR_CHARACTER_EDITOR] Successfully updated character slot UI');
    } catch (error) {
        console.error('[CNR_CHARACTER_EDITOR] Error updating character slot:', error);
    }
}

function updateUniformPresets() {
    const presetList = document.getElementById('uniform-preset-list');
    if (!presetList || !characterEditorData.uniformPresets) return;

    presetList.innerHTML = '';
    characterEditorData.selectedUniformPreset = null;

    const previewBtn = document.getElementById('preview-uniform-btn');
    const applyBtn = document.getElementById('apply-uniform-btn');
    const cancelBtn = document.getElementById('cancel-uniform-btn');
    if (previewBtn) previewBtn.disabled = true;
    if (applyBtn) applyBtn.disabled = true;
    if (cancelBtn) cancelBtn.disabled = true;

    characterEditorData.uniformPresets.forEach((preset, index) => {
        const presetElement = document.createElement('div');
        presetElement.className = 'preset-item';
        presetElement.innerHTML = `
            <h4>${preset.name}</h4>
            <p>${preset.description}</p>
        `;

        presetElement.addEventListener('click', function() {
            // Remove selection from other presets
            document.querySelectorAll('.preset-item').forEach(item => {
                item.classList.remove('selected');
            });
            
            // Select this preset
            this.classList.add('selected');
            characterEditorData.selectedUniformPreset = index;
            
            // Enable preview button
            const previewBtn = document.getElementById('preview-uniform-btn');
            if (previewBtn) previewBtn.disabled = false;
        });

        presetList.appendChild(presetElement);
    });
}

function updateSlidersFromCharacterData() {
    if (!characterEditorData.characterData) {
        console.log('[CNR_CHARACTER_EDITOR] No character data to update sliders');
        return;
    }
    
    const data = characterEditorData.characterData;
    console.log('[CNR_CHARACTER_EDITOR] Updating sliders with character data:', data);
    
    // Update basic appearance sliders
    const basicSliders = [
        'face', 'skin', 'hair', 'hairColor', 'hairHighlight', 'eyeColor',
        'beard', 'beardColor', 'beardOpacity', 'eyebrows', 'eyebrowsColor', 'eyebrowsOpacity',
        'blush', 'blushColor', 'blushOpacity', 'lipstick', 'lipstickColor', 'lipstickOpacity',
        'makeup', 'makeupColor', 'makeupOpacity', 'ageing', 'ageingOpacity',
        'complexion', 'complexionOpacity', 'sundamage', 'sundamageOpacity',
        'freckles', 'frecklesOpacity', 'bodyBlemishes', 'bodyBlemishesOpacity',
        'chesthair', 'chesthairColor', 'chesthairOpacity'
    ];
    
    basicSliders.forEach(sliderName => {
        const slider = document.getElementById(`${sliderName}-slider`);
        const valueDisplay = document.getElementById(`${sliderName}-value`);
        
        if (slider && data[sliderName] !== undefined) {
            slider.value = data[sliderName];
            if (valueDisplay) {
                valueDisplay.textContent = data[sliderName];
            }
        }
    });
    
    // Update face feature sliders
    if (data.faceFeatures) {
        Object.keys(data.faceFeatures).forEach(featureName => {
            const slider = document.getElementById(`${featureName}-slider`);
            const valueDisplay = document.getElementById(`${featureName}-value`);
            
            if (slider && data.faceFeatures[featureName] !== undefined) {
                slider.value = data.faceFeatures[featureName];
                if (valueDisplay) {
                    valueDisplay.textContent = data.faceFeatures[featureName].toFixed(2);
                }
            }
        });
    }
    
    console.log('[CNR_CHARACTER_EDITOR] Successfully updated sliders');
}

// Character Editor Slider Event Handlers
function setupCharacterEditorEventHandlers() {
    if (window.characterEditorLegacyHandlersSetup) {
        return;
    }

    console.log('[CNR_CHARACTER_EDITOR] Setting up event handlers');
    
    // Basic appearance sliders
    const basicSliders = [
        'face', 'skin', 'hair', 'hairColor', 'hairHighlight', 'eyeColor',
        'beard', 'beardColor', 'beardOpacity', 'eyebrows', 'eyebrowsColor', 'eyebrowsOpacity',
        'blush', 'blushColor', 'blushOpacity', 'lipstick', 'lipstickColor', 'lipstickOpacity',
        'makeup', 'makeupColor', 'makeupOpacity', 'ageing', 'ageingOpacity',
        'complexion', 'complexionOpacity', 'sundamage', 'sundamageOpacity',
        'freckles', 'frecklesOpacity', 'bodyBlemishes', 'bodyBlemishesOpacity',
        'chesthair', 'chesthairColor', 'chesthairOpacity'
    ];
    
    basicSliders.forEach(sliderName => {
        const slider = document.getElementById(`${sliderName}-slider`);
        if (slider) {
            slider.addEventListener('input', function() {
                const value = parseFloat(this.value);
                const valueDisplay = document.getElementById(`${sliderName}-value`);
                
                if (valueDisplay) {
                    valueDisplay.textContent = value;
                }
                
                // Update character data
                if (characterEditorData.characterData) {
                    characterEditorData.characterData[sliderName] = value;
                    
                    // Send update to client
                    fetch(`https://${CNRConfig.getResourceName()}/characterEditor_updateFeature`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ 
                            category: 'appearance', 
                            feature: sliderName, 
                            value: value 
                        })
                    }).catch(error => {
                        console.error('[CNR_CHARACTER_EDITOR] Error updating feature:', error);
                    });
                }
            });
        }
    });
    
    // Face feature sliders
    const faceFeatures = [
        'noseWidth', 'noseHeight', 'noseLength', 'noseBridge', 'noseTip', 'noseShift',
        'browHeight', 'browWidth', 'cheekboneHeight', 'cheekboneWidth', 'cheeksWidth',
        'eyesOpening', 'lipsThickness', 'jawWidth', 'jawHeight', 'chinLength',
        'chinPosition', 'chinWidth', 'chinShape', 'neckWidth'
    ];
    
    faceFeatures.forEach(featureName => {
        const slider = document.getElementById(`${featureName}-slider`);
        if (slider) {
            slider.addEventListener('input', function() {
                const value = parseFloat(this.value);
                const valueDisplay = document.getElementById(`${featureName}-value`);
                
                if (valueDisplay) {
                    valueDisplay.textContent = value.toFixed(2);
                }
                
                // Update character data
                if (characterEditorData.characterData) {
                    if (!characterEditorData.characterData.faceFeatures) {
                        characterEditorData.characterData.faceFeatures = {};
                    }
                    characterEditorData.characterData.faceFeatures[featureName] = value;
                    
                    // Send update to client
                    fetch(`https://${CNRConfig.getResourceName()}/characterEditor_updateFeature`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ 
                            category: 'faceFeatures', 
                            feature: featureName, 
                            value: value 
                        })
                    }).catch(error => {
                        console.error('[CNR_CHARACTER_EDITOR] Error updating face feature:', error);
                    });
                }
            });
        }
    });
    
    // Character editor buttons
    const saveBtn = document.getElementById('character-editor-save-btn');
    if (saveBtn) {
        saveBtn.addEventListener('click', function() {
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_save`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ success: true })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error saving character:', error);
            });
        });
    }
    
    const cancelBtn = document.getElementById('character-editor-cancel-btn');
    if (cancelBtn) {
        cancelBtn.addEventListener('click', function() {
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_cancel`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ success: true })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error canceling character editor:', error);
            });
        });
    }
    
    // Camera mode buttons
    const faceViewBtn = document.getElementById('camera-face-btn');
    if (faceViewBtn) {
        faceViewBtn.addEventListener('click', function() {
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_changeCamera`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ mode: 'face' })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error changing camera:', error);
            });
        });
    }
    
    const bodyViewBtn = document.getElementById('camera-body-btn');
    if (bodyViewBtn) {
        bodyViewBtn.addEventListener('click', function() {
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_changeCamera`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ mode: 'body' })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error changing camera:', error);
            });
        });
    }
    
    const fullViewBtn = document.getElementById('camera-full-btn');
    if (fullViewBtn) {
        fullViewBtn.addEventListener('click', function() {
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_changeCamera`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ mode: 'full' })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error changing camera:', error);
            });
        });
    }
    
    // Gender switch buttons
    const maleBtn = document.getElementById('gender-male-btn');
    const femaleBtn = document.getElementById('gender-female-btn');
    
    if (maleBtn) {
        maleBtn.addEventListener('click', function() {
            document.getElementById('gender-female-btn')?.classList.remove('active');
            this.classList.add('active');
            
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_switchGender`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ gender: 'male' })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error switching gender:', error);
            });
        });
    }
    
    if (femaleBtn) {
        femaleBtn.addEventListener('click', function() {
            document.getElementById('gender-male-btn')?.classList.remove('active');
            this.classList.add('active');
            
            fetch(`https://${CNRConfig.getResourceName()}/characterEditor_switchGender`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ gender: 'female' })
            }).catch(error => {
                console.error('[CNR_CHARACTER_EDITOR] Error switching gender:', error);
            });
        });
    }
    
    console.log('[CNR_CHARACTER_EDITOR] Event handlers setup complete');
}

function updateCharacterSlots() {
    const slotList = document.getElementById('character-slot-list');
    if (!slotList) return;

    slotList.innerHTML = '';
    characterEditorData.selectedCharacterSlot = null;

    const loadBtn = document.getElementById('load-character-btn');
    const deleteBtn = document.getElementById('delete-character-btn');
    if (loadBtn) loadBtn.disabled = true;
    if (deleteBtn) deleteBtn.disabled = true;

    // Create slots for current role
    for (let i = 1; i <= 2; i++) {
        const slotKey = `${characterEditorData.currentRole}_${i}`;
        const hasCharacter = characterEditorData.playerCharacters && characterEditorData.playerCharacters[slotKey];
        
        const slotElement = document.createElement('div');
        slotElement.className = `character-slot ${hasCharacter ? '' : 'empty'}`;
        slotElement.innerHTML = `
            <h4>Slot ${i}</h4>
            <p>${hasCharacter ? 'Character Created' : 'Empty Slot'}</p>
        `;

        if (hasCharacter) {
            slotElement.addEventListener('click', function() {
                // Remove selection from other slots
                document.querySelectorAll('.character-slot').forEach(slot => {
                    slot.classList.remove('selected');
                });
                
                // Select this slot
                this.classList.add('selected');
                characterEditorData.selectedCharacterSlot = slotKey;
                
                // Enable character management buttons
                const loadBtn = document.getElementById('load-character-btn');
                const deleteBtn = document.getElementById('delete-character-btn');
                if (loadBtn) loadBtn.disabled = false;
                if (deleteBtn) deleteBtn.disabled = false;
            });
        }

        slotList.appendChild(slotElement);
    }
}

function updateSlidersFromCharacterData() {
    const characterData = characterEditorData.characterData;
    if (!characterData) return;

    document.querySelectorAll('#character-editor .clothing-slider').forEach(slider => {
        const resetValue = slider.min === '-1' ? -1 : 0;
        slider.value = resetValue;

        const valueDisplay = slider.parentElement.querySelector('.slider-value');
        if (valueDisplay) {
            valueDisplay.textContent = resetValue.toString();
        }
    });

    document.querySelectorAll('#character-editor .customization-slider').forEach(slider => {
        const feature = slider.getAttribute('data-feature');
        const category = slider.getAttribute('data-category');
        const source = category === 'faceFeatures'
            ? (characterData.faceFeatures || {})
            : characterData;

        if (!feature || source[feature] === undefined) {
            return;
        }

        slider.value = source[feature];

        const valueDisplay = slider.parentElement.querySelector('.slider-value');
        if (valueDisplay) {
            const numericValue = source[feature];
            valueDisplay.textContent = slider.step && slider.step.includes('.')
                ? Number(numericValue).toFixed(1)
                : numericValue.toString();
        }
    });

    const genderButtons = {
        male: document.getElementById('gender-male-btn'),
        female: document.getElementById('gender-female-btn')
    };
    const isFemaleModel = characterData.model === 'mp_f_freemode_01';
    genderButtons.male?.classList.toggle('active', !isFemaleModel);
    genderButtons.female?.classList.toggle('active', isFemaleModel);

    const componentEntries = characterData.components || {};
    Object.keys(componentEntries).forEach(componentId => {
        const component = componentEntries[componentId] || {};
        syncClothingControl('component', componentId, 'drawable', component.drawable ?? 0);
        syncClothingControl('component', componentId, 'texture', component.texture ?? 0);
    });

    const propEntries = characterData.props || {};
    Object.keys(propEntries).forEach(propId => {
        const prop = propEntries[propId] || {};
        syncClothingControl('prop', propId, 'drawable', prop.drawable ?? -1);
        syncClothingControl('prop', propId, 'texture', prop.texture ?? 0);
    });
}

// Character Editor Frame Management
function createCharacterEditorFrame() {
    // Remove existing frame if it exists
    const existingFrame = document.getElementById('character-editor-frame');
    if (existingFrame) {
        existingFrame.remove();
    }
    
    // Create iframe for character editor
    const iframe = document.createElement('iframe');
    iframe.id = 'character-editor-frame';
    iframe.src = 'character_editor.html';
    iframe.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        border: none;
        z-index: 2000;
        background: rgba(0, 0, 0, 0.95);
    `;
    
    document.body.appendChild(iframe);
    
    // Forward messages to the iframe
    iframe.onload = function() {
        // Send character editor data to iframe
        if (window.pendingCharacterEditorData) {
            iframe.contentWindow.postMessage({
                action: 'openCharacterEditor',
                ...window.pendingCharacterEditorData
            }, '*');
            window.pendingCharacterEditorData = null;
        }
    };
    
    return iframe;
}

function removeCharacterEditorFrame() {
    const frame = document.getElementById('character-editor-frame');
    if (frame) {
        frame.remove();
    }
}

// Character editor frame handling (keep only frame-specific handlers)
function handleCharacterEditorFrameMessage(data) {
    switch (data.action) {
        case 'openCharacterEditorFrame':
            // Store data for iframe
            window.pendingCharacterEditorData = data;
            createCharacterEditorFrame();
            // Hide main UI
            document.body.style.display = 'none';
            break;
        case 'closeCharacterEditorFrame':
            removeCharacterEditorFrame();
            // Show main UI
            document.body.style.display = 'block';
            break;
        case 'hideMainUI':
            document.body.style.display = 'none';
            break;
        case 'showMainUI':
            document.body.style.display = 'block';
            break;
    }
}

// Handle messages from character editor iframe
window.addEventListener('message', function(event) {
    // Forward character editor messages to FiveM client
    if (event.data && event.data.action && event.data.action.startsWith('characterEditor_')) {
        fetch(`https://${CNRConfig.getResourceName()}/${event.data.action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(event.data)
        });
    }
});

// ====================================================================
// Enhanced Character Editor Class
// ====================================================================

class EnhancedCharacterEditor {
    constructor() {
        this.isOpen = false;
        this.currentRole = null;
        this.currentSlot = 1;
        this.characterData = {};
        this.uniformPresets = [];
        this.characterSlots = {};
        this.selectedUniformPreset = null;
        this.selectedCharacterSlot = null;
        this.confirmationTimeouts = {};
        this.resourceName = CNRConfig.getResourceName();
        this.editorElement = document.getElementById('character-editor-container');
        this.clothingComponentDefinitions = [
            { id: 1, label: 'Mask', min: 0 },
            { id: 3, label: 'Arms', min: 0 },
            { id: 4, label: 'Pants', min: 0 },
            { id: 5, label: 'Bag', min: 0 },
            { id: 6, label: 'Shoes', min: 0 },
            { id: 7, label: 'Accessories', min: 0 },
            { id: 8, label: 'Undershirt', min: 0 },
            { id: 9, label: 'Armor', min: 0 },
            { id: 10, label: 'Decals', min: 0 },
            { id: 11, label: 'Top', min: 0 }
        ];
        this.clothingPropDefinitions = [
            { id: 0, label: 'Hat', min: -1 },
            { id: 1, label: 'Glasses', min: -1 },
            { id: 2, label: 'Ear Accessory', min: -1 },
            { id: 6, label: 'Watch', min: -1 },
            { id: 7, label: 'Bracelet', min: -1 }
        ];
        
        this.init();
    }

    init() {
        this.populateClothingControls();
        this.setupEventListeners();
        this.setupSliderHandlers();
        this.enhanceSliderControls();
        console.log('[CNR_CHARACTER_EDITOR] Enhanced Character Editor initialized');
    }

    getRolePresetKey(roleName) {
        if (roleName === 'civilian') {
            return 'citizen';
        }

        return roleName || 'citizen';
    }

    getRoleDisplayLabel(roleName) {
        const normalizedRole = this.getRolePresetKey(roleName);
        if (normalizedRole === 'cop') {
            return 'Cop';
        }

        if (normalizedRole === 'robber') {
            return 'Robber';
        }

        return 'Civilian';
    }

    setupEventListeners() {
        if (!this.editorElement) {
            return;
        }

        // Close button
        const closeBtn = document.getElementById('close-editor-btn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.closeEditor(false);
            });
        }

        // Camera controls
        document.querySelectorAll('.camera-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                this.switchCamera(e.target.dataset.camera);
            });
        });

        // Rotation controls
        document.querySelectorAll('.rotate-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                this.rotateCharacter(e.target.dataset.direction);
            });
        });

        // Gender controls
        document.querySelectorAll('.gender-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                this.switchGender(e.target.dataset.gender);
            });
        });

        // Tab navigation
        document.querySelectorAll('.tab-button').forEach(btn => {
            btn.addEventListener('click', (e) => {
                this.switchTab(e.target.dataset.tab);
            });
        });

        // Uniform actions
        const previewUniformBtn = document.getElementById('preview-uniform-btn');
        const applyUniformBtn = document.getElementById('apply-uniform-btn');
        const cancelPreviewBtn = document.getElementById('cancel-preview-btn');

        if (previewUniformBtn) {
            previewUniformBtn.addEventListener('click', () => {
                this.previewUniform();
            });
        }

        if (applyUniformBtn) {
            applyUniformBtn.addEventListener('click', () => {
                this.applyUniform();
            });
        }

        if (cancelPreviewBtn) {
            cancelPreviewBtn.addEventListener('click', () => {
                this.cancelUniformPreview();
            });
        }

        // Character actions
        const loadCharacterBtn = document.getElementById('load-character-btn');
        const deleteCharacterBtn = document.getElementById('delete-character-btn');
        const createNewBtn = document.getElementById('create-new-btn');

        if (loadCharacterBtn) {
            loadCharacterBtn.addEventListener('click', () => {
                this.loadCharacter();
            });
        }

        if (deleteCharacterBtn) {
            deleteCharacterBtn.addEventListener('click', () => {
                this.deleteCharacter();
            });
        }

        if (createNewBtn) {
            createNewBtn.addEventListener('click', () => {
                this.createNewCharacter();
            });
        }

        // Footer actions
        const saveCharacterBtn = document.getElementById('save-character-btn');
        const cancelEditorBtn = document.getElementById('cancel-editor-btn');
        const resetCharacterBtn = document.getElementById('reset-character-btn');

        if (saveCharacterBtn) {
            saveCharacterBtn.addEventListener('click', () => {
                this.saveCharacter();
            });
        }

        if (cancelEditorBtn) {
            cancelEditorBtn.addEventListener('click', () => {
                this.closeEditor(false);
            });
        }

        if (resetCharacterBtn) {
            resetCharacterBtn.addEventListener('click', () => {
                this.resetCharacter();
            });
        }

        // ESC key to close
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.isOpen) {
                this.closeEditor(false);
            }
        });
    }

    setupSliderHandlers() {
        if (!this.editorElement || this.sliderHandlerAttached) {
            return;
        }

        this.editorElement.addEventListener('input', (e) => {
            const slider = e.target.closest('.slider');
            if (!slider || !this.editorElement.contains(slider)) {
                return;
            }

            this.handleSliderChange(slider);
        });

        this.sliderHandlerAttached = true;
    }

    enhanceSliderControls() {
        if (!this.editorElement) {
            return;
        }

        this.editorElement.querySelectorAll('.slider').forEach((slider) => {
            if (slider.closest('.slider-stepper')) {
                return;
            }

            const stepper = document.createElement('div');
            stepper.className = 'slider-stepper';

            const decrementBtn = this.createSliderStepButton('left', '<');
            const incrementBtn = this.createSliderStepButton('right', '>');
            const track = document.createElement('div');
            track.className = 'slider-step-track';

            const parent = slider.parentNode;
            if (!parent) {
                return;
            }

            parent.insertBefore(stepper, slider);
            track.appendChild(slider);
            stepper.appendChild(decrementBtn);
            stepper.appendChild(track);
            stepper.appendChild(incrementBtn);
        });

        if (this.sliderStepHandlerAttached) {
            return;
        }

        this.editorElement.addEventListener('click', (e) => {
            const stepButton = e.target.closest('.slider-step-btn');
            if (!stepButton || !this.editorElement.contains(stepButton)) {
                return;
            }

            const stepper = stepButton.closest('.slider-stepper');
            const slider = stepper?.querySelector('.slider');
            if (!slider) {
                return;
            }

            const direction = stepButton.dataset.direction === 'left' ? -1 : 1;
            const step = parseFloat(slider.step || '1') || 1;
            const min = parseFloat(slider.min);
            const max = parseFloat(slider.max);
            const currentValue = parseFloat(slider.value);
            const precision = this.getSliderPrecision(slider.step);

            let nextValue = currentValue + (step * direction);
            nextValue = Math.min(max, Math.max(min, nextValue));
            nextValue = Number(nextValue.toFixed(precision));

            if (nextValue === currentValue) {
                return;
            }

            slider.value = nextValue.toString();
            slider.dispatchEvent(new Event('input', { bubbles: true }));
        });

        this.sliderStepHandlerAttached = true;
    }

    createSliderStepButton(direction, label) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'slider-step-btn';
        button.dataset.direction = direction;
        button.setAttribute('aria-label', `${direction === 'left' ? 'Decrease' : 'Increase'} value`);
        button.textContent = label;
        return button;
    }

    getSliderPrecision(stepValue) {
        const stepString = String(stepValue || '1');
        const decimalIndex = stepString.indexOf('.');
        return decimalIndex === -1 ? 0 : (stepString.length - decimalIndex - 1);
    }

    handleSliderChange(slider) {
        const feature = slider.dataset.feature;
        const category = slider.dataset.category || 'basic';
        const entryType = slider.dataset.entryType;
        const targetId = slider.dataset.targetId;
        const valueType = slider.dataset.valueType;

        let rawValue = parseFloat(slider.value);
        this.updateSliderDisplay(slider, rawValue);

        if (entryType && targetId && valueType) {
            this.sendNUIMessage('characterEditor_updateComponent', {
                entryType: entryType,
                targetId: parseInt(targetId, 10),
                valueType: valueType,
                value: parseInt(rawValue, 10)
            }).then((result) => {
                if (!result || !result.success) {
                    return;
                }

                const tableName = result.entryType === 'prop' ? 'props' : 'components';
                if (!this.characterData[tableName]) {
                    this.characterData[tableName] = {};
                }

                this.characterData[tableName][result.targetId] = {
                    drawable: result.drawable,
                    texture: result.texture
                };

                this.syncClothingControl(result.entryType, result.targetId, 'drawable', result.drawable);
                this.syncClothingControl(result.entryType, result.targetId, 'texture', result.texture);
            });
            return;
        }

        let value = rawValue;
        if (category === 'faceFeatures') {
            value = rawValue / 100;
            this.characterData.faceFeatures = this.characterData.faceFeatures || {};
            this.characterData.faceFeatures[feature] = value;
        } else {
            if (feature && feature.toLowerCase().includes('opacity')) {
                value = rawValue / 100;
            } else if (!slider.step || !slider.step.includes('.')) {
                value = parseInt(rawValue, 10);
            }

            this.characterData[feature] = value;
        }

        this.sendNUIMessage('characterEditor_updateFeature', {
            category: category,
            feature: feature,
            value: value
        });
    }

    switchCamera(mode, notifyClient = true) {
        // Update active button
        this.editorElement?.querySelectorAll('.camera-btn').forEach(btn => {
            btn.classList.remove('active');
        });
        const activeBtn = this.editorElement?.querySelector(`[data-camera="${mode}"]`);
        if (activeBtn) {
            activeBtn.classList.add('active');
        }

        // Send to client
        if (notifyClient) {
            this.sendNUIMessage('characterEditor_changeCamera', { mode: mode });
        }
    }

    rotateCharacter(direction) {
        this.sendNUIMessage('characterEditor_rotateCharacter', { direction: direction });
    }

    switchGender(gender) {
        // Update active button
        this.editorElement?.querySelectorAll('.gender-btn').forEach(btn => {
            btn.classList.remove('active');
        });
        const activeBtn = this.editorElement?.querySelector(`[data-gender="${gender}"]`);
        if (activeBtn) {
            activeBtn.classList.add('active');
        }

        // Send to client
        this.sendNUIMessage('characterEditor_switchGender', { gender: gender }).then((result) => {
            if (!result || !result.success) {
                console.error('[CNR_CHARACTER_EDITOR] Failed to switch gender:', result?.error || 'Unknown error');
            }
        });
    }

    switchTab(tabName) {
        this.clearAllActionConfirmations();

        // Update active tab button
        this.editorElement?.querySelectorAll('.tab-button').forEach(btn => {
            btn.classList.remove('active');
        });
        const activeBtn = this.editorElement?.querySelector(`[data-tab="${tabName}"]`);
        if (activeBtn) {
            activeBtn.classList.add('active');
        }

        // Update active tab panel
        this.editorElement?.querySelectorAll('.tab-panel').forEach(panel => {
            panel.classList.remove('active');
        });
        const targetTab = this.editorElement?.querySelector(`#${tabName}-tab`);
        if (targetTab) {
            targetTab.classList.add('active');
        }
    }

    populateClothingControls() {
        const componentContainer = document.getElementById('clothing-component-groups');
        const propContainer = document.getElementById('clothing-prop-groups');

        if (componentContainer) {
            componentContainer.innerHTML = this.clothingComponentDefinitions.map((definition) =>
                this.renderClothingControlGroup('component', definition)
            ).join('');
        }

        if (propContainer) {
            propContainer.innerHTML = this.clothingPropDefinitions.map((definition) =>
                this.renderClothingControlGroup('prop', definition)
            ).join('');
        }

        this.enhanceSliderControls();
    }

    renderClothingControlGroup(entryType, definition) {
        const textureMin = 0;
        const drawableMin = definition.min;

        return `
            <div class="component-group">
                <h4>${definition.label}</h4>
                <div class="control-row">
                    <div class="control-group">
                        <label>Style</label>
                        <input
                            type="range"
                            class="slider"
                            min="${drawableMin}"
                            max="255"
                            value="${drawableMin}"
                            data-entry-type="${entryType}"
                            data-target-id="${definition.id}"
                            data-value-type="drawable"
                        >
                        <span class="value-display">${drawableMin === -1 ? 'None' : drawableMin}</span>
                    </div>
                    <div class="control-group">
                        <label>Texture</label>
                        <input
                            type="range"
                            class="slider"
                            min="${textureMin}"
                            max="63"
                            value="0"
                            data-entry-type="${entryType}"
                            data-target-id="${definition.id}"
                            data-value-type="texture"
                        >
                        <span class="value-display">0</span>
                    </div>
                </div>
            </div>
        `;
    }

    updateSliderDisplay(slider, rawValue) {
        const valueDisplay = slider.closest('.control-group')?.querySelector('.value-display');
        if (!valueDisplay) {
            return;
        }

        if (slider.min === '-1' && Number(rawValue) === -1) {
            valueDisplay.textContent = 'None';
            return;
        }

        if (slider.dataset.category === 'faceFeatures') {
            valueDisplay.textContent = Math.round(rawValue).toString();
            return;
        }

        if (slider.dataset.feature && slider.dataset.feature.toLowerCase().includes('opacity')) {
            valueDisplay.textContent = `${Math.round(rawValue)}%`;
            return;
        }

        if (slider.step && slider.step.includes('.')) {
            valueDisplay.textContent = Number(rawValue).toFixed(1);
            return;
        }

        valueDisplay.textContent = rawValue.toString();
    }

    syncClothingControl(entryType, targetId, valueType, value) {
        const slider = this.editorElement?.querySelector(
            `[data-entry-type="${entryType}"][data-target-id="${targetId}"][data-value-type="${valueType}"]`
        );
        if (!slider) {
            return;
        }

        slider.value = value;
        this.updateSliderDisplay(slider, value);
    }

    populateUniformPresets() {
        const container = document.getElementById('uniform-presets-container');
        if (!container) return;
        
        container.innerHTML = '';

        if (!this.uniformPresets || this.uniformPresets.length === 0) {
            container.innerHTML = '<p class="info-text">No uniform presets available for this role.</p>';
            return;
        }

        this.uniformPresets.forEach((preset, index) => {
            const presetElement = document.createElement('button');
            presetElement.type = 'button';
            presetElement.className = 'uniform-preset';
            const roleLabel = this.getRoleDisplayLabel(this.currentRole);
            presetElement.innerHTML = `
                <span class="preset-role-tag">${roleLabel} Outfit</span>
                <h4>${preset.name}</h4>
                <p>${preset.description}</p>
                <span class="preset-select-label">Select Outfit</span>
            `;

            presetElement.addEventListener('click', () => {
                this.clearAllActionConfirmations();
                this.selectUniformPreset(index);
            });

            container.appendChild(presetElement);
        });
    }

    selectUniformPreset(index) {
        this.clearAllActionConfirmations();

        // Remove previous selection
        this.editorElement?.querySelectorAll('.uniform-preset').forEach(preset => {
            preset.classList.remove('selected');
        });

        // Select new preset
        const presets = this.editorElement?.querySelectorAll('.uniform-preset') || [];
        if (presets[index]) {
            presets[index].classList.add('selected');
        }
        this.selectedUniformPreset = index;

        // Enable preview button
        const previewBtn = document.getElementById('preview-uniform-btn');
        if (previewBtn) {
            previewBtn.disabled = false;
        }
    }

    previewUniform() {
        if (this.selectedUniformPreset === null) return;

        console.log('[CNR_CHARACTER_EDITOR] Previewing uniform at JS index:', this.selectedUniformPreset);
        this.sendNUIMessage('characterEditor_previewUniform', {
            presetIndex: this.selectedUniformPreset
        }).then((result) => {
            if (!result || !result.success) {
                console.error('[CNR_CHARACTER_EDITOR] Failed to preview uniform:', result?.error || 'Unknown error');
            }
        });

        // Enable apply and cancel buttons
        const applyBtn = document.getElementById('apply-uniform-btn');
        const cancelBtn = document.getElementById('cancel-preview-btn');
        if (applyBtn) applyBtn.disabled = false;
        if (cancelBtn) cancelBtn.disabled = false;
    }

    applyUniform() {
        if (this.selectedUniformPreset === null) return;

        this.sendNUIMessage('characterEditor_applyUniform', {
            presetIndex: this.selectedUniformPreset
        }).then((result) => {
            if (!result || !result.success) {
                console.error('[CNR_CHARACTER_EDITOR] Failed to apply uniform:', result?.error || 'Unknown error');
            }
        });

        // Disable buttons
        const applyBtn = document.getElementById('apply-uniform-btn');
        const cancelBtn = document.getElementById('cancel-preview-btn');
        if (applyBtn) applyBtn.disabled = true;
        if (cancelBtn) cancelBtn.disabled = true;
    }

    cancelUniformPreview() {
        this.sendNUIMessage('characterEditor_cancelUniformPreview', {}).then((result) => {
            if (!result || !result.success) {
                console.error('[CNR_CHARACTER_EDITOR] Failed to cancel uniform preview:', result?.error || 'Unknown error');
            }
        });

        // Disable buttons
        const applyBtn = document.getElementById('apply-uniform-btn');
        const cancelBtn = document.getElementById('cancel-preview-btn');
        if (applyBtn) applyBtn.disabled = true;
        if (cancelBtn) cancelBtn.disabled = true;
    }

    populateCharacterSlots() {
        const container = document.getElementById('character-slots-container');
        if (!container) return;
        
        container.innerHTML = '';
        this.selectedCharacterSlot = null;
        this.clearAllActionConfirmations();

        const loadBtn = document.getElementById('load-character-btn');
        const deleteBtn = document.getElementById('delete-character-btn');
        if (loadBtn) loadBtn.disabled = true;
        if (deleteBtn) deleteBtn.disabled = true;

        // Create slots for current role (1 main + 1 alternate)
        for (let i = 1; i <= 2; i++) {
            const slotKey = `${this.currentRole}_${i}`;
            const hasCharacter = this.characterSlots[slotKey];
            
            const slotElement = document.createElement('div');
            slotElement.className = `character-slot ${hasCharacter ? '' : 'empty'}`;
            slotElement.innerHTML = `
                <h4>Slot ${i}</h4>
                <p>${hasCharacter ? 'Character Created' : 'Empty Slot'}</p>
                ${i === 1 ? '<small>Main Character</small>' : '<small>Alternate Character</small>'}
            `;

            if (hasCharacter) {
                slotElement.addEventListener('click', () => {
                    this.selectCharacterSlot(slotKey, slotElement);
                });
            }

            container.appendChild(slotElement);
        }
    }

    selectCharacterSlot(slotKey, element) {
        this.clearAllActionConfirmations();

        // Remove previous selection
        this.editorElement?.querySelectorAll('.character-slot').forEach(slot => {
            slot.classList.remove('selected');
        });

        // Select new slot
        element.classList.add('selected');
        this.selectedCharacterSlot = slotKey;

        // Enable character management buttons
        const loadBtn = document.getElementById('load-character-btn');
        const deleteBtn = document.getElementById('delete-character-btn');
        if (loadBtn) loadBtn.disabled = false;
        if (deleteBtn) deleteBtn.disabled = false;
    }

    loadCharacter() {
        if (!this.selectedCharacterSlot) return;
        this.clearAllActionConfirmations();

        this.sendNUIMessage('characterEditor_loadCharacter', {
            characterKey: this.selectedCharacterSlot
        }).then((result) => {
            if (!result || !result.success) {
                console.error('[CNR_CHARACTER_EDITOR] Failed to load character:', result?.error || 'Unknown error');
            }
        });
    }

    deleteCharacter() {
        if (!this.selectedCharacterSlot) return;

        if (!this.requestActionConfirmation('delete-character-btn', 'Click Again to Delete', 'Delete Character')) {
            return;
        }

        const characterKeyToDelete = this.selectedCharacterSlot;
        this.sendNUIMessage('characterEditor_deleteCharacter', {
            characterKey: characterKeyToDelete
        }).then((result) => {
            if (!result || !result.success) {
                return;
            }

            delete this.characterSlots[characterKeyToDelete];
            this.populateCharacterSlots();
        });
    }

    createNewCharacter() {
        this.clearAllActionConfirmations();
        this.resetCharacter();
    }

    saveCharacter() {
        this.clearAllActionConfirmations();
        this.sendNUIMessage('characterEditor_save', {});
    }

    resetCharacter() {
        if (!this.requestActionConfirmation('reset-character-btn', 'Click Again to Reset', 'Reset to Default')) {
            return;
        }

        this.sendNUIMessage('characterEditor_reset', {}).then((result) => {
            if (!result || !result.success) {
                console.error('[CNR_CHARACTER_EDITOR] Failed to reset character:', result?.error || 'Unknown error');
            }
        });
    }

    closeEditor(save = false, notifyClient = true) {
        this.clearAllActionConfirmations();
        this.isOpen = false;
        const container = document.getElementById('character-editor-container');
        if (container) {
            container.classList.add('hidden');
        }

        if (notifyClient) {
            this.sendNUIMessage(save ? 'characterEditor_save' : 'characterEditor_cancel', {});
        } else {
            this.sendNUIMessage('characterEditor_closed', { success: true });
        }
    }

    openEditor(data) {
        this.isOpen = true;
        this.currentRole = data.role;
        this.currentSlot = data.characterSlot || 1;
        this.characterData = data.characterData || {};
        this.uniformPresets = data.uniformPresets || [];
        this.characterSlots = data.playerCharacters || {};
        this.selectedUniformPreset = null;
        this.selectedCharacterSlot = null;
        this.clearAllActionConfirmations();

        document.body.style.display = 'block';
        document.body.style.visibility = 'visible';

        // Update UI
        const roleElement = document.getElementById('current-role');
        const slotElement = document.getElementById('current-slot');
        if (roleElement) roleElement.textContent = this.getRoleDisplayLabel(this.currentRole);
        if (slotElement) slotElement.textContent = `Slot ${this.currentSlot}`;

        // Populate uniform presets and character slots
        this.populateUniformPresets();
        this.populateCharacterSlots();

        // Update sliders with current character data
        this.updateSlidersFromCharacterData();
        this.switchTab('appearance');
        this.switchCamera('full', false);

        // Show editor
        const container = document.getElementById('character-editor-container');
        if (container) {
            container.classList.remove('hidden');
            container.style.display = 'grid';
            container.style.visibility = 'visible';
        }

        fetchSetNuiFocus(true, true);
        this.sendNUIMessage('characterEditor_opened', { success: true });

        console.log('[CNR_CHARACTER_EDITOR] Opened enhanced character editor for', this.currentRole, 'slot', this.currentSlot);
    }

    updateSlidersFromCharacterData() {
        if (!this.characterData) return;

        this.editorElement?.querySelectorAll('.slider[data-feature]').forEach((slider) => {
            const feature = slider.dataset.feature;
            const category = slider.dataset.category;
            const source = category === 'faceFeatures'
                ? (this.characterData.faceFeatures || {})
                : this.characterData;

            let value = source[feature];
            if (value === undefined) {
                value = slider.min === '-1' ? -1 : 0;
            } else if (category === 'faceFeatures') {
                value = Math.round(Number(value) * 100);
            } else if (feature && feature.toLowerCase().includes('opacity')) {
                value = Math.round(Number(value) * 100);
            }

            slider.value = value;
            this.updateSliderDisplay(slider, value);
        });

        const genderButtons = {
            male: document.querySelector('#character-editor-container [data-gender="male"]'),
            female: document.querySelector('#character-editor-container [data-gender="female"]')
        };
        const isFemaleModel = this.characterData.model === 'mp_f_freemode_01';
        genderButtons.male?.classList.toggle('active', !isFemaleModel);
        genderButtons.female?.classList.toggle('active', isFemaleModel);

        this.clothingComponentDefinitions.forEach((definition) => {
            this.syncClothingControl('component', definition.id, 'drawable', 0);
            this.syncClothingControl('component', definition.id, 'texture', 0);
        });

        this.clothingPropDefinitions.forEach((definition) => {
            this.syncClothingControl('prop', definition.id, 'drawable', definition.min);
            this.syncClothingControl('prop', definition.id, 'texture', 0);
        });

        Object.entries(this.characterData.components || {}).forEach(([componentId, component]) => {
            if (!component || typeof component !== 'object') {
                return;
            }

            this.syncClothingControl('component', componentId, 'drawable', component.drawable ?? 0);
            this.syncClothingControl('component', componentId, 'texture', component.texture ?? 0);
        });

        Object.entries(this.characterData.props || {}).forEach(([propId, prop]) => {
            if (!prop || typeof prop !== 'object') {
                return;
            }

            this.syncClothingControl('prop', propId, 'drawable', prop.drawable ?? -1);
            this.syncClothingControl('prop', propId, 'texture', prop.texture ?? 0);
        });
    }

    updateCharacterSlot(characterKey, characterData) {
        this.characterSlots[characterKey] = characterData;
        if (this.isOpen && characterKey.startsWith(`${this.currentRole}_`)) {
            this.populateCharacterSlots();
        }
    }

    syncUniformPresets(uniformPresets) {
        this.uniformPresets = Array.isArray(uniformPresets) ? uniformPresets : [];
        this.selectedUniformPreset = null;
        this.populateUniformPresets();
    }

    syncCharacterData(characterData) {
        this.characterData = characterData || {};
        this.updateSlidersFromCharacterData();
    }

    requestActionConfirmation(buttonId, armedLabel, defaultLabel) {
        const targetButton = document.getElementById(buttonId);
        if (!targetButton) {
            return true;
        }

        const isArmed = targetButton.dataset.confirmArmed === 'true';
        if (isArmed) {
            this.clearActionConfirmation(buttonId, defaultLabel);
            return true;
        }

        this.clearAllActionConfirmations(buttonId);
        targetButton.dataset.confirmArmed = 'true';
        targetButton.classList.add('confirming');
        targetButton.textContent = armedLabel;

        this.confirmationTimeouts[buttonId] = window.setTimeout(() => {
            this.clearActionConfirmation(buttonId, defaultLabel);
        }, 3500);

        return false;
    }

    clearActionConfirmation(buttonId, defaultLabel) {
        const targetButton = document.getElementById(buttonId);
        if (!targetButton) {
            return;
        }

        if (this.confirmationTimeouts[buttonId]) {
            window.clearTimeout(this.confirmationTimeouts[buttonId]);
            delete this.confirmationTimeouts[buttonId];
        }

        targetButton.dataset.confirmArmed = 'false';
        targetButton.classList.remove('confirming');
        targetButton.textContent = defaultLabel;
    }

    clearAllActionConfirmations(excludedButtonId = null) {
        const confirmationButtons = [
            { id: 'delete-character-btn', label: 'Delete Character' },
            { id: 'reset-character-btn', label: 'Reset to Default' }
        ];

        confirmationButtons.forEach((entry) => {
            if (entry.id === excludedButtonId) {
                return;
            }

            this.clearActionConfirmation(entry.id, entry.label);
        });
    }

    sendNUIMessage(action, data) {
        return fetch(`https://${this.resourceName}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        }).then((response) => {
            if (!response.ok) {
                throw new Error(`Request failed with status ${response.status}`);
            }

            return response.json().catch(() => ({}));
        }).catch(error => {
            console.error('[CNR_CHARACTER_EDITOR] Error sending NUI message:', error);
            return { success: false, error: error.message };
        });
    }
}

// Initialize enhanced character editor when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    if (!window.enhancedCharacterEditor) {
        window.enhancedCharacterEditor = new EnhancedCharacterEditor();
    }
});

// Enhanced character editor integration (removed duplicate handler to prevent conflicts)

// ==========================================================================
// ENHANCED PROGRESSION SYSTEM JAVASCRIPT
// ==========================================================================

class ProgressionSystem {
    constructor() {
        this.currentPlayerData = {
            level: 1,
            xp: 0,
            xpForNext: 100,
            prestigeLevel: 0,
            prestigeTitle: "Rookie",
            abilities: {},
            challenges: {},
            seasonalEvent: null
        };
        
        this.notifications = [];
        this.animationQueue = [];
        this.isProgressionMenuOpen = false;
        
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.setupProgressionMenu();
        this.setupAbilityBar();
        this.initializeUI();
        
        console.log('[CNR_PROGRESSION] Enhanced Progression System initialized');
    }
    
    setupEventListeners() {
        // Progression menu toggle
        document.addEventListener('keydown', (e) => {
            if (e.key === 'p' || e.key === 'P') {
                if (!this.isProgressionMenuOpen) {
                    this.toggleProgressionMenu();
                }
            }
            
            // Ability hotkeys
            if (e.key === 'z' || e.key === 'Z') {
                this.useAbility(1);
            }
            if (e.key === 'x' || e.key === 'X') {
                this.useAbility(2);
            }
        });
        
        // Close progression menu
        const closeBtn = document.getElementById('close-progression-btn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.toggleProgressionMenu();
            });
        }
        
        // Progression tabs
        const tabs = document.querySelectorAll('.progression-tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                this.switchProgressionTab(tab.dataset.tab);
            });
        });
        
        // Prestige button
        const prestigeBtn = document.getElementById('prestige-btn');
        if (prestigeBtn) {
            prestigeBtn.addEventListener('click', () => {
                this.requestPrestige();
            });
        }
        
        // Close event banner
        const closeEventBtn = document.getElementById('close-event-banner');
        if (closeEventBtn) {
            closeEventBtn.addEventListener('click', () => {
                this.hideSeasonalEventBanner();
            });
        }
    }
    
    setupProgressionMenu() {
        // Initialize tab content
        this.switchProgressionTab('overview');
    }
    
    setupAbilityBar() {
        const abilitySlots = document.querySelectorAll('.ability-slot');
        abilitySlots.forEach((slot, index) => {
            slot.addEventListener('click', () => {
                this.useAbility(index + 1);
            });
        });
    }
    
    initializeUI() {
        this.updateXPDisplay();
        this.updateProgressionOverview();
    }
    
    // ==========================================================================
    // XP AND LEVEL SYSTEM
    // ==========================================================================
    
    updateProgressionDisplay(data) {
        this.currentPlayerData = { ...this.currentPlayerData, ...data };
        this.updateXPDisplay();
        this.updateProgressionOverview();
        
        // Update prestige indicator
        const prestigeIndicator = document.getElementById('prestige-indicator');
        if (prestigeIndicator) {
            if (data.prestigeInfo && data.prestigeInfo.level > 0) {
                prestigeIndicator.textContent = `★${data.prestigeInfo.level}`;
                prestigeIndicator.classList.remove('hidden');
            } else {
                prestigeIndicator.classList.add('hidden');
            }
        }
        
        // Update seasonal event indicator
        if (data.seasonalEvent) {
            this.showSeasonalEventIndicator(data.seasonalEvent);
        }
    }
    
    updateXPDisplay() {
        const data = this.currentPlayerData;
        
        // Update level text
        const levelText = document.getElementById('level-text');
        if (levelText) {
            levelText.textContent = data.level || 1;
        }
        
        // Update XP text
        const xpText = document.getElementById('xp-text');
        if (xpText) {
            const currentXPInLevel = data.xpInCurrentLevel || 0;
            const xpForNext = data.xpForNextLevel || 100;
            xpText.textContent = `${currentXPInLevel} / ${xpForNext} XP`;
        }
        
        // Update progress bar
        const xpBarFill = document.getElementById('xp-bar-fill');
        if (xpBarFill) {
            const progressPercent = data.progressPercent || 0;
            xpBarFill.style.width = `${Math.min(progressPercent, 100)}%`;
        }
        
        // Update XP gain indicator
        if (data.xpGained && data.xpGained > 0) {
            this.showXPGainIndicator(data.xpGained);
        }
    }
    
    showXPGainIndicator(amount) {
        const indicator = document.getElementById('xp-gain-indicator');
        if (indicator) {
            indicator.textContent = `+${amount}`;
            indicator.classList.remove('hidden');
            
            setTimeout(() => {
                indicator.classList.add('hidden');
            }, 2000);
        }
    }
    
    showXPGainAnimation(amount, reason) {
        const animation = document.getElementById('xp-gain-animation');
        const amountEl = document.getElementById('xp-gain-amount');
        const reasonEl = document.getElementById('xp-gain-reason');
        
        if (animation && amountEl && reasonEl) {
            amountEl.textContent = `+${amount} XP`;
            reasonEl.textContent = reason || 'Action';
            
            animation.classList.remove('hidden');
            animation.classList.add('show');
            
            setTimeout(() => {
                animation.classList.remove('show');
                setTimeout(() => {
                    animation.classList.add('hidden');
                }, 300);
            }, 2000);
        }
    }
    
    showLevelUpAnimation(newLevel) {
        const animation = document.getElementById('level-up-animation');
        const levelText = document.getElementById('level-up-text');
        
        if (animation && levelText) {
            levelText.textContent = `You reached Level ${newLevel}!`;
            
            animation.classList.remove('hidden');
            animation.classList.add('show');
            
            // Play sound effect (if available)
            this.playSound('levelup');
            
            setTimeout(() => {
                animation.classList.remove('show');
                setTimeout(() => {
                    animation.classList.add('hidden');
                }, 500);
            }, 3000);
        }
    }
    
    // ==========================================================================
    // UNLOCK SYSTEM
    // ==========================================================================
    
    showUnlockNotification(unlock, level) {
        const notification = document.getElementById('unlock-notification');
        const iconEl = document.getElementById('unlock-icon-element');
        const titleEl = document.getElementById('unlock-title');
        const messageEl = document.getElementById('unlock-message');
        
        if (notification && iconEl && titleEl && messageEl) {
            // Set icon based on unlock type
            const iconMap = {
                'item_access': 'fas fa-unlock',
                'vehicle_access': 'fas fa-car',
                'ability': 'fas fa-magic',
                'passive_perk': 'fas fa-star',
                'cash_reward': 'fas fa-dollar-sign'
            };
            
            iconEl.className = iconMap[unlock.type] || 'fas fa-unlock';
            titleEl.textContent = `Level ${level} Unlock!`;
            messageEl.textContent = unlock.message;
            
            notification.classList.remove('hidden');
            notification.classList.add('show');
            
            setTimeout(() => {
                notification.classList.remove('show');
                setTimeout(() => {
                    notification.classList.add('hidden');
                }, 300);
            }, 5000);
        }
    }
    
    // ==========================================================================
    // PROGRESSION MENU
    // ==========================================================================
    
    toggleProgressionMenu() {
        const menu = document.getElementById('progression-menu');
        if (menu) {
            this.isProgressionMenuOpen = !this.isProgressionMenuOpen;
            
            if (this.isProgressionMenuOpen) {
                menu.classList.add('show');
                this.updateProgressionMenuContent();
                // Enable cursor for interaction
                this.setNuiFocus(true, true);
            } else {
                menu.classList.remove('show');
                // Disable cursor
                this.setNuiFocus(false, false);
            }
        }
    }
    
    switchProgressionTab(tabName) {
        // Update tab buttons
        const tabs = document.querySelectorAll('.progression-tab');
        tabs.forEach(tab => {
            if (tab.dataset.tab === tabName) {
                tab.classList.add('active');
            } else {
                tab.classList.remove('active');
            }
        });
        
        // Update tab content
        const contents = document.querySelectorAll('.progression-tab-content');
        contents.forEach(content => {
            if (content.id === `${tabName}-tab`) {
                content.classList.add('active');
            } else {
                content.classList.remove('active');
            }
        });
        
        // Load tab-specific content
        switch (tabName) {
            case 'overview':
                this.updateProgressionOverview();
                break;
            case 'unlocks':
                this.updateUnlocksTab();
                break;
            case 'abilities':
                this.updateAbilitiesTab();
                break;
            case 'challenges':
                this.updateChallengesTab();
                break;
            case 'prestige':
                this.updatePrestigeTab();
                break;
        }
    }
    
    updateProgressionMenuContent() {
        this.updateProgressionOverview();
        this.updateUnlocksTab();
        this.updateAbilitiesTab();
        this.updateChallengesTab();
        this.updatePrestigeTab();
    }
    
    updateProgressionOverview() {
        const data = this.currentPlayerData;
        
        // Update stats
        const levelEl = document.getElementById('overview-level');
        const totalXpEl = document.getElementById('overview-total-xp');
        const xpNeededEl = document.getElementById('overview-xp-needed');
        const prestigeEl = document.getElementById('overview-prestige');
        
        if (levelEl) levelEl.textContent = data.level || 1;
        if (totalXpEl) totalXpEl.textContent = (data.xp || 0).toLocaleString();
        if (xpNeededEl) xpNeededEl.textContent = (data.xpForNext || 100).toLocaleString();
        if (prestigeEl) prestigeEl.textContent = data.prestigeLevel || 0;
        
        // Update circular progress
        const progressPercent = data.progressPercent || 0;
        const progressRing = document.getElementById('progress-ring-fill');
        const progressText = document.getElementById('progress-percentage');
        
        if (progressRing) {
            const circumference = 2 * Math.PI * 52; // radius = 52
            const strokeDasharray = (progressPercent / 100) * circumference;
            progressRing.style.strokeDasharray = `${strokeDasharray} ${circumference}`;
        }
        
        if (progressText) {
            progressText.textContent = `${Math.round(progressPercent)}%`;
        }
    }
    
    updateUnlocksTab() {
        const container = document.getElementById('unlock-tree-content');
        if (!container) return;
        
        // This would be populated with actual unlock data from the server
        container.innerHTML = '<p style="color: var(--text-secondary); text-align: center;">Unlock tree will be populated with your progression data.</p>';
    }
    
    updateAbilitiesTab() {
        const container = document.getElementById('abilities-grid');
        if (!container) return;
        
        const abilities = this.currentPlayerData.abilities || {};
        container.innerHTML = '';
        
        // Example abilities (would come from server data)
        const exampleAbilities = [
            { id: 'smoke_bomb', name: 'Smoke Bomb', description: 'Create a smoke screen for quick escapes', unlocked: false, cooldown: 0 },
            { id: 'adrenaline_rush', name: 'Adrenaline Rush', description: 'Temporary speed boost during escapes', unlocked: false, cooldown: 0 }
        ];
        
        exampleAbilities.forEach(ability => {
            const abilityCard = document.createElement('div');
            abilityCard.className = `ability-card ${ability.unlocked ? 'unlocked' : 'locked'} ${ability.cooldown > 0 ? 'on-cooldown' : ''}`;
            
            abilityCard.innerHTML = `
                <div class="ability-icon-large">
                    <i class="fas fa-magic"></i>
                </div>
                <div class="ability-name">${ability.name}</div>
                <div class="ability-description">${ability.description}</div>
                ${ability.cooldown > 0 ? `<div class="ability-cooldown-text">Cooldown: ${Math.ceil(ability.cooldown / 1000)}s</div>` : ''}
            `;
            
            if (ability.unlocked && ability.cooldown === 0) {
                abilityCard.addEventListener('click', () => {
                    this.triggerAbility(ability.id);
                });
            }
            
            container.appendChild(abilityCard);
        });
    }
    
    updateChallengesTab() {
        const dailyContainer = document.getElementById('daily-challenges');
        const weeklyContainer = document.getElementById('weekly-challenges');
        
        if (dailyContainer) {
            dailyContainer.innerHTML = '<p style="color: var(--text-secondary); text-align: center;">Daily challenges will be populated here.</p>';
        }
        
        if (weeklyContainer) {
            weeklyContainer.innerHTML = '<p style="color: var(--text-secondary); text-align: center;">Weekly challenges will be populated here.</p>';
        }
    }
    
    updatePrestigeTab() {
        const data = this.currentPlayerData;
        
        // Update current prestige
        const prestigeLevelEl = document.getElementById('current-prestige-level');
        const prestigeTitleEl = document.getElementById('current-prestige-title');
        const currentLevelEl = document.getElementById('prestige-current-level');
        const prestigeBtn = document.getElementById('prestige-btn');
        
        if (prestigeLevelEl) prestigeLevelEl.textContent = data.prestigeLevel || 0;
        if (prestigeTitleEl) prestigeTitleEl.textContent = data.prestigeTitle || 'Rookie';
        if (currentLevelEl) currentLevelEl.textContent = data.level || 1;
        
        // Update prestige button state
        if (prestigeBtn) {
            const canPrestige = (data.level || 1) >= 50; // Max level requirement
            if (canPrestige) {
                prestigeBtn.classList.remove('disabled');
            } else {
                prestigeBtn.classList.add('disabled');
            }
        }
        
        // Update next prestige rewards
        const rewardsContainer = document.getElementById('next-prestige-rewards');
        if (rewardsContainer) {
            const nextPrestigeLevel = (data.prestigeLevel || 0) + 1;
            rewardsContainer.innerHTML = `
                <div class="reward-item">
                    <i class="fas fa-dollar-sign reward-icon"></i>
                    <span class="reward-text">Cash Bonus: $${(nextPrestigeLevel * 100000).toLocaleString()}</span>
                </div>
                <div class="reward-item">
                    <i class="fas fa-crown reward-icon"></i>
                    <span class="reward-text">Title: Prestige ${nextPrestigeLevel}</span>
                </div>
                <div class="reward-item">
                    <i class="fas fa-chart-line reward-icon"></i>
                    <span class="reward-text">XP Multiplier: ${1 + (nextPrestigeLevel * 0.1)}x</span>
                </div>
            `;
        }
    }
    
    // ==========================================================================
    // ABILITY SYSTEM
    // ==========================================================================
    
    useAbility(slotNumber) {
        const slot = document.querySelector(`.ability-slot[data-slot="${slotNumber}"]`);
        if (!slot) return;
        
        // Check if ability is available and not on cooldown
        const cooldownOverlay = slot.querySelector('.cooldown-overlay');
        if (cooldownOverlay && cooldownOverlay.style.transform !== 'scaleY(0)') {
            this.showNotification('Ability is on cooldown!', 'warning');
            return;
        }
        
        // Trigger ability on server
        this.sendNuiMessage('useAbility', { slot: slotNumber });
        
        // Start cooldown animation
        this.startAbilityCooldown(slotNumber, 60000); // 60 second cooldown
    }
    
    triggerAbility(abilityId) {
        this.sendNuiMessage('triggerAbility', { abilityId: abilityId });
    }
    
    startAbilityCooldown(slotNumber, duration) {
        const slot = document.querySelector(`.ability-slot[data-slot="${slotNumber}"]`);
        if (!slot) return;
        
        const cooldownOverlay = slot.querySelector('.cooldown-overlay');
        const cooldownText = slot.querySelector('.cooldown-text');
        
        if (cooldownOverlay && cooldownText) {
            cooldownOverlay.style.transform = 'scaleY(1)';
            
            let remaining = duration;
            const interval = setInterval(() => {
                remaining -= 100;
                const progress = 1 - (remaining / duration);
                cooldownOverlay.style.transform = `scaleY(${1 - progress})`;
                
                if (remaining <= 0) {
                    clearInterval(interval);
                    cooldownOverlay.style.transform = 'scaleY(0)';
                }
            }, 100);
        }
    }
    
    // ==========================================================================
    // CHALLENGE SYSTEM
    // ==========================================================================
    
    updateChallengeProgress(challengeId, challengeData) {
        // Update challenge in current data
        if (!this.currentPlayerData.challenges) {
            this.currentPlayerData.challenges = {};
        }
        this.currentPlayerData.challenges[challengeId] = challengeData;
        
        // Show progress notification
        const progressPercent = (challengeData.progress / challengeData.target) * 100;
        if (progressPercent >= 25 && progressPercent < 100) {
            this.showChallengeProgressNotification(challengeId, challengeData);
        }
        
        // Update challenges tab if open
        if (this.isProgressionMenuOpen) {
            this.updateChallengesTab();
        }
    }
    
    showChallengeProgressNotification(challengeId, challengeData) {
        const notification = document.getElementById('challenge-progress-notification');
        const nameEl = document.getElementById('challenge-name');
        const progressFill = document.getElementById('challenge-progress-fill');
        const progressText = document.getElementById('challenge-progress-text');
        
        if (notification && nameEl && progressFill && progressText) {
            nameEl.textContent = challengeData.name || 'Challenge';
            progressText.textContent = `${challengeData.progress}/${challengeData.target}`;
            
            const progressPercent = (challengeData.progress / challengeData.target) * 100;
            progressFill.style.width = `${progressPercent}%`;
            
            notification.classList.remove('hidden');
            notification.classList.add('show');
            
            setTimeout(() => {
                notification.classList.remove('show');
                setTimeout(() => {
                    notification.classList.add('hidden');
                }, 300);
            }, 3000);
        }
    }
    
    challengeCompleted(challengeId, challengeData) {
        this.showNotification(`🏆 Challenge Completed: ${challengeData.name || 'Challenge'}!`, 'success');
        this.playSound('challenge_complete');
    }
    
    // ==========================================================================
    // PRESTIGE SYSTEM
    // ==========================================================================
    
    requestPrestige() {
        const data = this.currentPlayerData;
        if ((data.level || 1) < 50) {
            this.showNotification('You must reach level 50 to prestige!', 'warning');
            return;
        }
        
        // Show confirmation dialog
        if (confirm('Are you sure you want to prestige? This will reset your level to 1 but grant powerful bonuses!')) {
            this.sendNuiMessage('requestPrestige', {});
        }
    }
    
    prestigeCompleted(prestigeLevel, prestigeReward) {
        this.showPrestigeAnimation(prestigeLevel, prestigeReward);
        this.currentPlayerData.prestigeLevel = prestigeLevel;
        this.currentPlayerData.prestigeTitle = prestigeReward.title;
        this.updateProgressionDisplay(this.currentPlayerData);
    }
    
    showPrestigeAnimation(prestigeLevel, prestigeReward) {
        const animation = document.getElementById('prestige-animation');
        const prestigeText = document.getElementById('prestige-text');
        
        if (animation && prestigeText) {
            prestigeText.textContent = `You achieved ${prestigeReward.title} (Prestige ${prestigeLevel})!`;
            
            animation.classList.remove('hidden');
            animation.classList.add('show');
            
            this.playSound('prestige');
            
            setTimeout(() => {
                animation.classList.remove('show');
                setTimeout(() => {
                    animation.classList.add('hidden');
                }, 500);
            }, 4000);
        }
    }
    
    // ==========================================================================
    // SEASONAL EVENTS
    // ==========================================================================
    
    showSeasonalEventIndicator(eventData) {
        const indicator = document.getElementById('seasonal-event-indicator');
        const textEl = document.getElementById('seasonal-event-text');
        
        if (indicator && textEl) {
            textEl.textContent = eventData.name;
            indicator.classList.remove('hidden');
        }
        
        this.showSeasonalEventBanner(eventData);
    }
    
    showSeasonalEventBanner(eventData) {
        const banner = document.getElementById('seasonal-event-banner');
        const nameEl = document.getElementById('event-name');
        const descEl = document.getElementById('event-description');
        
        if (banner && nameEl && descEl) {
            nameEl.textContent = eventData.name;
            descEl.textContent = eventData.description;
            
            banner.classList.remove('hidden');
            
            // Auto-hide after 10 seconds
            setTimeout(() => {
                this.hideSeasonalEventBanner();
            }, 10000);
        }
    }
    
    hideSeasonalEventBanner() {
        const banner = document.getElementById('seasonal-event-banner');
        if (banner) {
            banner.classList.add('hidden');
        }
    }
    
    seasonalEventEnded(eventName) {
        const indicator = document.getElementById('seasonal-event-indicator');
        if (indicator) {
            indicator.classList.add('hidden');
        }
        
        this.showNotification(`📅 Event Ended: ${eventName}`, 'info');
    }
    
    // ==========================================================================
    // NOTIFICATION SYSTEM
    // ==========================================================================
    
    showProgressionNotification(message, type, duration = 5000) {
        const container = document.getElementById('notification-container');
        if (!container) return;
        
        const notification = document.createElement('div');
        notification.className = `progression-notification ${type}`;
        
        const iconMap = {
            'xp': 'fas fa-plus-circle',
            'levelup': 'fas fa-trophy',
            'ability': 'fas fa-magic',
            'event': 'fas fa-calendar-star',
            'success': 'fas fa-check-circle',
            'warning': 'fas fa-exclamation-triangle',
            'error': 'fas fa-times-circle',
            'info': 'fas fa-info-circle'
        };
        
        // Create elements safely to prevent XSS
        const notificationContent = document.createElement('div');
        notificationContent.className = 'notification-content';

        const notificationIcon = document.createElement('i');
        notificationIcon.className = iconMap[type] || 'fas fa-info-circle';
        notificationIcon.classList.add('notification-icon');

        const notificationText = document.createElement('span');
        notificationText.className = 'notification-text';
        notificationText.textContent = message; // Use textContent to prevent XSS

        notificationContent.appendChild(notificationIcon);
        notificationContent.appendChild(notificationText);
        notification.appendChild(notificationContent);
        
        container.appendChild(notification);
        
        // Animate in
        setTimeout(() => {
            notification.classList.add('show');
        }, 100);
        
        // Remove after duration
        setTimeout(() => {
            notification.classList.remove('show');
            setTimeout(() => {
                if (notification.parentNode) {
                    notification.parentNode.removeChild(notification);
                }
            }, 300);
        }, duration);
    }
    
    showNotification(message, type = 'info', duration = 5000) {
        this.showProgressionNotification(message, type, duration);
    }
    
    // ==========================================================================
    // UTILITY FUNCTIONS
    // ==========================================================================
    
    playSound(soundType) {
        // This would trigger sound effects in the game
        this.sendNuiMessage('playSound', { soundType: soundType });
    }
    
    setNuiFocus(hasFocus, hasCursor) {
        this.sendNuiMessage('setNuiFocus', { hasFocus: hasFocus, hasCursor: hasCursor });
    }
    
    sendNuiMessage(action, data = {}) {
        fetch(`https://${CNRConfig.getResourceName()}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        }).catch(error => {
            console.error(`[CNR_PROGRESSION] Error sending NUI message ${action}:`, error);
        });
    }
}

// Initialize the progression system
let progressionSystem = null;

// Enhanced message handling for progression system
const originalMessageHandler = window.addEventListener;
window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (!progressionSystem) {
        progressionSystem = new ProgressionSystem();
    }
    
    // Handle progression-specific messages
    switch (data.action) {
        case 'updateProgressionDisplay':
            progressionSystem.updateProgressionDisplay(data.data);
            break;
            
        case 'showXPGainAnimation':
            progressionSystem.showXPGainAnimation(data.amount, data.reason);
            break;
            
        case 'showLevelUpAnimation':
            progressionSystem.showLevelUpAnimation(data.newLevel);
            break;
            
        case 'showUnlockNotification':
            progressionSystem.showUnlockNotification(data.unlock, data.level);
            break;
            
        case 'abilityUnlocked':
            progressionSystem.showNotification(`⚡ New Ability: ${data.ability.name}`, 'ability');
            break;
            
        case 'abilityUsed':
            progressionSystem.startAbilityCooldown(data.slot || 1, data.cooldown || 60000);
            break;
            
        case 'updateChallengeProgress':
            progressionSystem.updateChallengeProgress(data.challengeId, data.challengeData);
            break;
            
        case 'challengeCompleted':
            progressionSystem.challengeCompleted(data.challengeId, data.challengeData);
            break;
            
        case 'prestigeCompleted':
            progressionSystem.prestigeCompleted(data.prestigeLevel, data.prestigeReward);
            break;
            
        case 'seasonalEventStarted':
            progressionSystem.showSeasonalEventIndicator(data.eventData);
            break;
            
        case 'seasonalEventEnded':
            progressionSystem.seasonalEventEnded(data.eventName);
            break;
            
        case 'showProgressionNotification':
            progressionSystem.showProgressionNotification(data.message, data.type, data.duration);
            break;
    }
});

// Initialize progression system when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    if (!progressionSystem) {
        progressionSystem = new ProgressionSystem();
    }
});

console.log('[CNR_PROGRESSION] Enhanced Progression System JavaScript loaded');

// ====================================================================
// Banking System JavaScript
// ====================================================================

class BankingSystem {
    constructor() {
        this.currentBalance = 0;
        this.transactionHistory = [];
        this.activeLoan = null;
        this.activeInvestments = [];
        this.investmentOptions = [];
        this.isATMOpen = false;
        this.isBankOpen = false;
        this.currentTab = 'account';
        
        this.initializeEventListeners();
        console.log('[CNR_BANKING] Banking System initialized');
    }

    initializeEventListeners() {
        // ATM Interface
        document.getElementById('close-atm')?.addEventListener('click', () => this.closeATM());
        document.getElementById('atm-deposit-btn')?.addEventListener('click', () => this.processATMDeposit());
        document.getElementById('atm-withdraw-btn')?.addEventListener('click', () => this.processATMWithdraw());
        
        // Quick withdrawal buttons
        document.querySelectorAll('.quick-btn[data-action="withdraw"]').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const amount = parseInt(e.target.closest('.quick-btn').dataset.amount);
                this.quickWithdraw(amount);
            });
        });

        // Bank Interface
        document.getElementById('close-bank')?.addEventListener('click', () => this.closeBank());
        document.getElementById('bank-deposit-btn')?.addEventListener('click', () => this.processBankDeposit());
        document.getElementById('bank-withdraw-btn')?.addEventListener('click', () => this.processBankWithdraw());
        
        // Bank navigation tabs
        document.querySelectorAll('.nav-tab').forEach(tab => {
            tab.addEventListener('click', (e) => {
                const tabName = e.target.dataset.tab;
                this.switchBankTab(tabName);
            });
        });

        // Transfer functionality
        document.getElementById('transfer-submit-btn')?.addEventListener('click', () => this.processTransfer());
        document.getElementById('transfer-amount')?.addEventListener('input', () => this.updateTransferTotal());

        // Loan functionality
        document.getElementById('request-loan-btn')?.addEventListener('click', () => this.requestLoan());
        document.getElementById('repay-loan-btn')?.addEventListener('click', () => this.repayLoan());
        document.getElementById('loan-amount')?.addEventListener('input', () => this.updateLoanCalculator());

        // Investment functionality
        document.addEventListener('click', (e) => {
            if (e.target.closest('.investment-option')) {
                this.selectInvestment(e.target.closest('.investment-option'));
            }
        });
    }

    openATM(atmData) {
        this.isATMOpen = true;
        this.currentBalance = atmData.balance || 0;
        
        document.getElementById('atm-balance').textContent = `$${this.currentBalance.toLocaleString()}`;
        document.getElementById('atm-account-number').textContent = `Account: ****${atmData.id || '0000'}`;
        
        document.getElementById('atm-interface').classList.remove('hidden');
        console.log('[CNR_BANKING] ATM interface opened');
    }

    closeATM() {
        this.isATMOpen = false;
        document.getElementById('atm-interface').classList.add('hidden');
        fetch(`https://${CNRConfig.getResourceName()}/closeBanking`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        console.log('[CNR_BANKING] ATM interface closed');
    }

    openBank(bankData) {
        this.isBankOpen = true;
        this.currentBalance = bankData.balance || 0;
        this.transactionHistory = bankData.transactions || [];
        this.activeLoan = bankData.loan || null;
        this.activeInvestments = bankData.investments || [];
        this.investmentOptions = bankData.investmentOptions || this.investmentOptions || [];
        
        document.getElementById('bank-name').textContent = bankData.tellerName || 'Bank';
        document.getElementById('bank-balance').textContent = `$${this.currentBalance.toLocaleString()}`;
        
        this.updateTransactionHistory();
        this.loadInvestmentOptions();
        this.updateLoanStatus();
        this.updateActiveInvestments();
        
        document.getElementById('bank-interface').classList.remove('hidden');
        console.log('[CNR_BANKING] Bank interface opened');
    }

    updateBankingDetails(details) {
        if (!details || typeof details !== 'object') return;

        if (typeof details.balance === 'number') {
            this.updateBalance(details.balance);
        }

        if (Array.isArray(details.transactions)) {
            this.transactionHistory = details.transactions;
            this.updateTransactionHistory();
        }

        if (Object.prototype.hasOwnProperty.call(details, 'loan')) {
            this.activeLoan = details.loan || null;
            this.updateLoanStatus();
        }

        if (Array.isArray(details.investments)) {
            this.activeInvestments = details.investments;
            this.updateActiveInvestments();
        }

        if (Array.isArray(details.investmentOptions)) {
            this.investmentOptions = details.investmentOptions;
            this.loadInvestmentOptions();
        }
    }

    closeBank() {
        this.isBankOpen = false;
        document.getElementById('bank-interface').classList.add('hidden');
        fetch(`https://${CNRConfig.getResourceName()}/closeBanking`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        console.log('[CNR_BANKING] Bank interface closed');
    }

    switchBankTab(tabName) {
        // Update navigation
        document.querySelectorAll('.nav-tab').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

        // Update content
        document.querySelectorAll('.tab-content').forEach(content => {
            content.classList.remove('active');
        });
        document.getElementById(`${tabName}-tab`).classList.add('active');

        this.currentTab = tabName;
    }

    processATMDeposit() {
        const amount = parseInt(document.getElementById('atm-amount').value);
        if (!amount || amount <= 0) {
            this.showNotification('Please enter a valid amount', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/bankDeposit`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount })
        });

        document.getElementById('atm-amount').value = '';
    }

    processATMWithdraw() {
        const amount = parseInt(document.getElementById('atm-amount').value);
        if (!amount || amount <= 0) {
            this.showNotification('Please enter a valid amount', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/bankWithdraw`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount })
        });

        document.getElementById('atm-amount').value = '';
    }

    quickWithdraw(amount) {
        fetch(`https://${CNRConfig.getResourceName()}/bankWithdraw`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount })
        });
    }

    processBankDeposit() {
        const amount = parseInt(document.getElementById('bank-amount').value);
        if (!amount || amount <= 0) {
            this.showNotification('Please enter a valid amount', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/bankDeposit`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount })
        });

        document.getElementById('bank-amount').value = '';
    }

    processBankWithdraw() {
        const amount = parseInt(document.getElementById('bank-amount').value);
        if (!amount || amount <= 0) {
            this.showNotification('Please enter a valid amount', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/bankWithdraw`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount })
        });

        document.getElementById('bank-amount').value = '';
    }

    processTransfer() {
        const targetId = parseInt(document.getElementById('transfer-target').value);
        const amount = parseInt(document.getElementById('transfer-amount').value);

        if (!targetId || !amount || amount <= 0) {
            this.showNotification('Please enter valid transfer details', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/bankTransfer`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ targetId, amount })
        });

        document.getElementById('transfer-target').value = '';
        document.getElementById('transfer-amount').value = '';
        this.updateTransferTotal();
    }

    updateTransferTotal() {
        const amount = parseInt(document.getElementById('transfer-amount').value) || 0;
        const total = amount + 50; // Transfer fee
        document.getElementById('transfer-total').textContent = `Total: $${total.toLocaleString()}`;
    }

    requestLoan() {
        const amount = parseInt(document.getElementById('loan-amount').value);
        const duration = parseInt(document.getElementById('loan-duration').value);

        if (!amount || amount <= 0) {
            this.showNotification('Please enter a valid loan amount', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/requestLoan`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount, duration })
        });
    }

    repayLoan() {
        const amount = parseInt(document.getElementById('repayment-amount').value);

        if (!amount || amount <= 0) {
            this.showNotification('Please enter a valid repayment amount', 'error');
            return;
        }

        fetch(`https://${CNRConfig.getResourceName()}/repayLoan`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ amount })
        });

        document.getElementById('repayment-amount').value = '';
    }

    updateLoanCalculator() {
        const amount = parseInt(document.getElementById('loan-amount').value) || 0;
        const collateral = Math.floor(amount * 0.5);
        const dailyInterest = Math.floor(amount * 0.005);

        document.getElementById('collateral-required').textContent = `Collateral Required: $${collateral.toLocaleString()}`;
        document.getElementById('daily-interest').textContent = `Daily Interest: $${dailyInterest.toLocaleString()}`;
    }

    selectInvestment(investmentElement) {
        const investmentId = investmentElement.dataset.investmentId;
        const minimumAmount = parseInt(investmentElement.dataset.minAmount || '1');

        this.showAmountDialog('Investment Amount', minimumAmount, (amount) => {
            if (!amount || isNaN(amount) || amount <= 0) {
                this.showNotification('Please enter a valid amount', 'error');
                return;
            }

            fetch(`https://${CNRConfig.getResourceName()}/makeInvestment`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ investmentId, amount: parseInt(amount) })
            });
        });
    }

    showAmountDialog(title, defaultAmount, onConfirm) {
        const existingDialog = document.getElementById('banking-amount-dialog');
        if (existingDialog) existingDialog.remove();

        const host = document.querySelector('#bank-interface .banking-modal-content') || document.body;
        const dialog = document.createElement('div');
        dialog.id = 'banking-amount-dialog';
        dialog.className = 'banking-amount-dialog';
        dialog.innerHTML = `
            <div class="amount-dialog-card">
                <button class="amount-dialog-close" type="button">&times;</button>
                <h3>${title}</h3>
                <label for="banking-amount-input">Amount</label>
                <div class="input-group">
                    <span class="input-prefix">$</span>
                    <input id="banking-amount-input" type="number" min="1" value="${parseInt(defaultAmount) || 1}">
                </div>
                <div class="form-actions">
                    <button class="action-btn secondary amount-dialog-cancel" type="button">Cancel</button>
                    <button class="action-btn primary amount-dialog-confirm" type="button">Confirm</button>
                </div>
            </div>
        `;

        const closeDialog = () => dialog.remove();
        dialog.querySelector('.amount-dialog-close').addEventListener('click', closeDialog);
        dialog.querySelector('.amount-dialog-cancel').addEventListener('click', closeDialog);
        dialog.querySelector('.amount-dialog-confirm').addEventListener('click', () => {
            const amount = parseInt(dialog.querySelector('#banking-amount-input').value);
            closeDialog();
            onConfirm(amount);
        });

        host.appendChild(dialog);
        dialog.querySelector('#banking-amount-input').focus();
    }

    loadInvestmentOptions() {
        const investmentGrid = document.getElementById('investment-options');
        if (!investmentGrid) return;

        const investments = this.investmentOptions && this.investmentOptions.length ? this.investmentOptions : [
            {
                id: 'property_development',
                name: 'Property Development Fund',
                description: 'Invest in Los Santos real estate development',
                minInvestment: 25000,
                expectedReturn: 0.08,
                riskLevel: 'medium',
                duration: 72
            }
        ];

        investmentGrid.innerHTML = investments.map(inv => `
            <div class="investment-option" data-investment-id="${inv.id}" data-min-amount="${inv.minInvestment}">
                <div class="investment-header">
                    <h4 class="investment-name">${inv.name}</h4>
                    <span class="risk-badge ${inv.riskLevel}">${inv.riskLevel}</span>
                </div>
                <p class="investment-description">${inv.description}</p>
                <div class="investment-details">
                    <span>Min: $${inv.minInvestment.toLocaleString()}</span>
                    <span>Return: ${(inv.expectedReturn * 100).toFixed(1)}%</span>
                    <span>Duration: ${inv.duration}h</span>
                </div>
            </div>
        `).join('');
    }

    updateLoanStatus() {
        const application = document.getElementById('loan-application');
        const activeLoan = document.getElementById('active-loan');
        if (!application || !activeLoan) return;

        if (!this.activeLoan) {
            application.classList.remove('hidden');
            activeLoan.classList.add('hidden');
            return;
        }

        const principal = Number(this.activeLoan.principal || 0);
        const owed = Number(this.activeLoan.totalOwed || principal);
        const collateral = Number(this.activeLoan.collateral || 0);
        const repaymentInput = document.getElementById('repayment-amount');

        application.classList.add('hidden');
        activeLoan.classList.remove('hidden');

        const principalEl = document.getElementById('loan-principal');
        const owedEl = document.getElementById('loan-owed');
        const collateralEl = document.getElementById('loan-collateral');
        if (principalEl) principalEl.textContent = `Principal: $${Math.floor(principal).toLocaleString()}`;
        if (owedEl) owedEl.textContent = `Amount Owed: $${Math.floor(owed).toLocaleString()}`;
        if (collateralEl) collateralEl.textContent = `Collateral: $${Math.floor(collateral).toLocaleString()}`;
        if (repaymentInput) {
            repaymentInput.max = Math.max(0, Math.floor(owed));
            repaymentInput.placeholder = `Up to $${Math.floor(owed).toLocaleString()}`;
        }
    }

    updateActiveInvestments() {
        const investmentsList = document.getElementById('investments-list');
        if (!investmentsList) return;

        if (!this.activeInvestments || this.activeInvestments.length === 0) {
            investmentsList.innerHTML = '<div class="empty-state">No active investments.</div>';
            return;
        }

        investmentsList.innerHTML = this.activeInvestments.map(investment => {
            const amount = Number(investment.amount || 0);
            const expectedReturn = Number(investment.expectedReturn || 0);
            const remainingSeconds = Math.max(0, Number(investment.remainingSeconds || 0));
            const remainingHours = Math.ceil(remainingSeconds / 3600);
            const projectedValue = Math.floor(amount + (amount * expectedReturn));

            return `
                <div class="investment-item">
                    <div class="investment-info">
                        <div class="investment-type">${investment.name || investment.type || 'Investment'}</div>
                        <div class="investment-description">${investment.riskLevel || 'standard'} risk | ${remainingHours}h remaining</div>
                    </div>
                    <div class="investment-amount">
                        $${amount.toLocaleString()} -> $${projectedValue.toLocaleString()}
                    </div>
                </div>
            `;
        }).join('');
    }

    updateTransactionHistory() {
        const transactionList = document.getElementById('transaction-list');
        if (!transactionList) return;

        const sortedTransactions = [...(this.transactionHistory || [])].sort((a, b) => {
            return Number(b.timestamp || 0) - Number(a.timestamp || 0);
        });

        if (sortedTransactions.length === 0) {
            transactionList.innerHTML = '<div class="empty-state">No transactions yet.</div>';
            return;
        }

        transactionList.innerHTML = sortedTransactions.map(transaction => {
            const isPositive = ['deposit', 'transfer_in', 'loan', 'investment_return', 'interest'].includes(transaction.type);
            const amountClass = isPositive ? 'positive' : 'negative';
            const amountPrefix = isPositive ? '+' : '-';
            
            return `
                <div class="transaction-item">
                    <div class="transaction-info">
                        <div class="transaction-type">${transaction.type.replace('_', ' ')}</div>
                        <div class="transaction-description">${transaction.description}</div>
                        <div class="transaction-date">${new Date(transaction.timestamp * 1000).toLocaleDateString()}</div>
                    </div>
                    <div class="transaction-amount ${amountClass}">
                        ${amountPrefix}$${Math.abs(transaction.amount).toLocaleString()}
                    </div>
                </div>
            `;
        }).join('');
    }

    updateBalance(balance) {
        this.currentBalance = balance;
        
        // Update all balance displays
        const atmBalance = document.getElementById('atm-balance');
        const bankBalance = document.getElementById('bank-balance');
        
        if (atmBalance) atmBalance.textContent = `$${balance.toLocaleString()}`;
        if (bankBalance) bankBalance.textContent = `$${balance.toLocaleString()}`;
    }

    showProgressBar(duration, label) {
        const progressOverlay = document.getElementById('progress-bar-overlay');
        const progressLabel = document.getElementById('progress-label');
        const progressFill = document.getElementById('progress-fill');
        const progressTime = document.getElementById('progress-time');

        if (!progressOverlay) return;

        progressLabel.textContent = label;
        progressOverlay.classList.remove('hidden');

        let timeRemaining = duration / 1000;
        progressTime.textContent = `${timeRemaining}s`;

        const interval = setInterval(() => {
            timeRemaining--;
            progressTime.textContent = `${timeRemaining}s`;
            
            const progress = (duration / 1000 - timeRemaining) / (duration / 1000) * 100;
            progressFill.style.width = `${progress}%`;

            if (timeRemaining <= 0) {
                clearInterval(interval);
                this.hideProgressBar();
            }
        }, 1000);
    }

    hideProgressBar() {
        const progressOverlay = document.getElementById('progress-bar-overlay');
        if (progressOverlay) {
            progressOverlay.classList.add('hidden');
        }
    }

    showNotification(message, type = 'info') {
        // Integrate with existing notification system
        if (window.showToast) {
            window.showToast(message, type);
        } else {
            console.log(`[CNR_BANKING] ${type.toUpperCase()}: ${message}`);
        }
    }
}

// ====================================================================
// Heist System JavaScript
// ====================================================================

class HeistSystem {
    constructor() {
        this.isHeistPlanningOpen = false;
        this.selectedHeist = null;
        this.currentCrew = null;
        this.activeHeist = null;
        this.availableHeists = [];
        this.crewRoles = [];
        this.equipmentShop = [];
        this.ownedEquipment = {};
        
        this.initializeEventListeners();
        console.log('[CNR_HEIST] Heist System initialized');
    }

    initializeEventListeners() {
        // Heist Planning Interface
        document.getElementById('close-heist-planning')?.addEventListener('click', () => this.closeHeistPlanning());
        
        // Heist navigation tabs
        document.querySelectorAll('.heist-nav-tab').forEach(tab => {
            tab.addEventListener('click', (e) => {
                const tabName = e.target.dataset.tab;
                this.switchHeistTab(tabName);
            });
        });

        // Heist execution
        document.getElementById('start-heist-btn')?.addEventListener('click', () => this.startHeist());
        document.getElementById('leave-crew-btn')?.addEventListener('click', () => this.leaveCrew());

        // Equipment categories
        document.querySelectorAll('.category-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                this.filterEquipment(e.target.dataset.category);
            });
        });

        // Crew recruitment
        document.getElementById('copy-invite-code')?.addEventListener('click', () => this.copyInviteCode());

        // Heist completion modal
        document.getElementById('close-completion-modal')?.addEventListener('click', () => this.closeCompletionModal());

        // Dynamic event listeners for heist cards, equipment items, etc.
        document.addEventListener('click', (e) => {
            if (e.target.closest('.heist-card')) {
                this.selectHeist(e.target.closest('.heist-card'));
            }
            if (e.target.closest('.equipment-item')) {
                this.purchaseEquipment(e.target.closest('.equipment-item'));
            }
            if (e.target.closest('.role-card')) {
                this.selectRole(e.target.closest('.role-card'));
            }
        });
    }

    openHeistPlanning(heistConfig, crewId, crewRoles = [], equipmentShop = []) {
        this.isHeistPlanningOpen = true;
        this.selectedHeist = heistConfig;
        this.currentCrew = { id: crewId };
        this.crewRoles = crewRoles;
        this.equipmentShop = equipmentShop;
        this.ownedEquipment = {};
        
        this.updateHeistDetails();
        this.loadAvailableHeists();
        this.loadCrewRoles();
        this.loadEquipmentShop();
        
        document.getElementById('heist-planning-interface').classList.remove('hidden');
        console.log('[CNR_HEIST] Heist planning opened for:', heistConfig.name);
    }

    closeHeistPlanning() {
        this.isHeistPlanningOpen = false;
        document.getElementById('heist-planning-interface').classList.add('hidden');
        
        fetch(`https://${CNRConfig.getResourceName()}/closeHeistPlanning`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        
        console.log('[CNR_HEIST] Heist planning closed');
    }

    switchHeistTab(tabName) {
        // Update navigation
        document.querySelectorAll('.heist-nav-tab').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

        // Update content
        document.querySelectorAll('.heist-tab-content').forEach(content => {
            content.classList.remove('active');
        });
        document.getElementById(`${tabName}-tab`).classList.add('active');
    }

    selectHeist(heistCard) {
        const heistId = heistCard.dataset.heistId;
        const heist = this.availableHeists.find(h => h.id === heistId);
        
        if (!heist || heist.onCooldown) return;

        // Update selection visually
        document.querySelectorAll('.heist-card').forEach(card => {
            card.classList.remove('selected');
        });
        heistCard.classList.add('selected');

        this.selectedHeist = heist;
        this.updateHeistDetails();

        // Notify server of heist selection
        fetch(`https://${CNRConfig.getResourceName()}/startHeistPlanning`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ heistId })
        });
    }

    updateHeistDetails() {
        if (!this.selectedHeist) return;

        const heist = this.selectedHeist;
        
        document.getElementById('heist-name').textContent = heist.name;
        document.getElementById('heist-type').textContent = heist.type.replace('_', ' ').toUpperCase();
        document.getElementById('heist-difficulty').textContent = heist.difficulty.toUpperCase();
        document.getElementById('heist-crew-size').textContent = heist.requiredCrew;
        document.getElementById('heist-duration').textContent = `${Math.floor(heist.duration / 60)} minutes`;
        document.getElementById('heist-reward').textContent = `$${heist.minReward.toLocaleString()} - $${heist.maxReward.toLocaleString()}`;
        document.getElementById('heist-status').textContent = heist.onCooldown ? 'ON COOLDOWN' : 'AVAILABLE';

        // Update stages
        this.updateHeistStages();
        this.updateRequiredEquipment();
        this.updatePreHeistChecklist();
    }

    updateHeistStages() {
        const stagesList = document.getElementById('heist-stages-list');
        if (!stagesList || !this.selectedHeist?.stages) return;

        stagesList.innerHTML = this.selectedHeist.stages.map((stage, index) => `
            <div class="stage-item">
                <div class="stage-number">${index + 1}</div>
                <div class="stage-description">${stage.description}</div>
                <div class="stage-duration">${Math.floor(stage.duration / 60)}:${(stage.duration % 60).toString().padStart(2, '0')}</div>
            </div>
        `).join('');
    }

    loadAvailableHeists() {
        fetch(`https://${CNRConfig.getResourceName()}/getAvailableHeists`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    }

    updateAvailableHeists(heists) {
        this.availableHeists = heists;
        const heistsGrid = document.getElementById('heists-grid');
        if (!heistsGrid) return;

        heistsGrid.innerHTML = heists.map(heist => `
            <div class="heist-card ${heist.onCooldown ? 'on-cooldown' : ''}" data-heist-id="${heist.id}">
                <div class="heist-card-header">
                    <h4 class="heist-card-name">${heist.name}</h4>
                    <span class="difficulty-badge ${heist.difficulty}">${heist.difficulty}</span>
                </div>
                <div class="heist-card-details">
                    <span>Crew: ${heist.requiredCrew}</span>
                    <span>Reward: $${heist.minReward.toLocaleString()}+</span>
                    <span>${heist.onCooldown ? `Cooldown: ${heist.cooldownRemaining}m` : 'Available'}</span>
                </div>
            </div>
        `).join('');
    }

    loadCrewRoles() {
        const rolesGrid = document.getElementById('crew-roles-grid');
        if (!rolesGrid) return;

        rolesGrid.innerHTML = this.crewRoles.map(role => {
            const assignedRoles = Object.values(this.currentCrew?.roles || {});
            const isAvailable = !assignedRoles.includes(role.id);

            return `
            <div class="role-card ${isAvailable ? 'available' : 'taken'}" data-role-id="${role.id}">
                <div class="role-name">${role.name}</div>
                <div class="role-description">${role.description}</div>
                <div class="role-bonuses">
                    ${Object.entries(role.bonuses || {}).map(([bonusKey, bonusValue]) => `<span class="bonus-tag">${bonusKey.replace(/_/g, ' ')}: ${bonusValue}</span>`).join('')}
                </div>
            </div>
        `;
        }).join('');
    }

    selectRole(roleCard) {
        const roleId = roleCard.dataset.roleId;
        if (!roleCard.classList.contains('available')) return;

        fetch(`https://${CNRConfig.getResourceName()}/joinHeistCrew`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ crewId: this.currentCrew?.id, role: roleId })
        });
    }

    loadEquipmentShop() {
        const equipmentGrid = document.getElementById('equipment-grid');
        if (!equipmentGrid) return;

        equipmentGrid.innerHTML = this.equipmentShop.map(item => `
            <div class="equipment-item" data-equipment-id="${item.id}" data-category="${item.category || 'all'}">
                <div class="equipment-name">${item.name}</div>
                <div class="equipment-description">${item.description}</div>
                <div class="equipment-price">$${item.price.toLocaleString()}</div>
            </div>
        `).join('');
    }

    filterEquipment(category) {
        document.querySelectorAll('.category-btn').forEach(btn => {
            btn.classList.remove('active');
        });
        document.querySelector(`[data-category="${category}"]`).classList.add('active');

        const equipmentItems = document.querySelectorAll('.equipment-item');
        equipmentItems.forEach(item => {
            if (category === 'all' || item.dataset.category === category) {
                item.style.display = 'block';
            } else {
                item.style.display = 'none';
            }
        });
    }

    purchaseEquipment(equipmentItem) {
        const equipmentId = equipmentItem.dataset.equipmentId;
        const quantity = prompt('Enter quantity to purchase:', '1');

        if (!quantity || isNaN(quantity) || quantity <= 0) return;

        fetch(`https://${CNRConfig.getResourceName()}/purchaseHeistEquipment`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ itemId: equipmentId, quantity: parseInt(quantity) })
        });
    }

    updateRequiredEquipment() {
        const requiredList = document.getElementById('required-equipment-list');
        if (!requiredList || !this.selectedHeist?.equipment) return;

        requiredList.innerHTML = this.selectedHeist.equipment.map(item => `
            <div class="equipment-owned">
                <span>${item.replace('_', ' ').toUpperCase()}</span>
                <span class="equipment-quantity ${this.ownedEquipment[item] ? 'owned' : 'missing'}">
                    ${this.ownedEquipment[item] || 0}/1
                </span>
            </div>
        `).join('');
    }

    updatePreHeistChecklist() {
        const checklist = document.getElementById('heist-checklist');
        if (!checklist) return;

        const checklistItems = [
            { text: 'Crew assembled', complete: this.currentCrew?.members?.length >= (this.selectedHeist?.requiredCrew || 1) },
            { text: 'Equipment acquired', complete: this.hasRequiredEquipment() },
            { text: 'Police online', complete: true }, // Would check actual police count
            { text: 'Heist available', complete: !this.selectedHeist?.onCooldown }
        ];

        checklist.innerHTML = checklistItems.map(item => `
            <div class="checklist-item">
                <div class="checklist-icon ${item.complete ? 'complete' : 'incomplete'}">
                    <i class="fas fa-${item.complete ? 'check' : 'times'}"></i>
                </div>
                <div class="checklist-text ${item.complete ? 'complete' : ''}">${item.text}</div>
            </div>
        `).join('');

        // Update start button
        const startBtn = document.getElementById('start-heist-btn');
        if (startBtn) {
            const allComplete = checklistItems.every(item => item.complete);
            startBtn.disabled = !allComplete;
        }
    }

    hasRequiredEquipment() {
        if (!this.selectedHeist?.equipment) return true;
        return this.selectedHeist.equipment.every(item => (this.ownedEquipment[item] || 0) >= 1);
    }

    startHeist() {
        if (!this.selectedHeist) return;

        fetch(`https://${CNRConfig.getResourceName()}/startEnhancedHeist`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });

        this.closeHeistPlanning();
    }

    leaveCrew() {
        fetch(`https://${CNRConfig.getResourceName()}/leaveHeistCrew`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });

        this.closeHeistPlanning();
    }

    copyInviteCode() {
        const inviteCode = document.getElementById('crew-invite-code');
        if (!inviteCode) return;

        navigator.clipboard.writeText(inviteCode.value).then(() => {
            this.showNotification('Invite code copied to clipboard!', 'success');
        });
    }

    startHeistExecution(heistConfig, crew) {
        this.activeHeist = { config: heistConfig, crew };
        
        document.getElementById('active-heist-name').textContent = heistConfig.name;
        document.getElementById('heist-execution-hud').classList.remove('hidden');
        
        console.log('[CNR_HEIST] Heist execution started:', heistConfig.name);
    }

    updateHeistStage(stageData) {
        document.getElementById('current-stage').textContent = `Stage ${stageData.stage}`;
        document.getElementById('stage-description').textContent = stageData.description;
        
        // Update progress bar
        this.updateStageProgress(stageData.duration, stageData.timeRemaining);
    }

    updateStageProgress(totalDuration, timeRemaining) {
        const progress = ((totalDuration - timeRemaining) / totalDuration) * 100;
        document.getElementById('stage-progress-fill').style.width = `${progress}%`;
        
        const minutes = Math.floor(timeRemaining / 60);
        const seconds = timeRemaining % 60;
        document.getElementById('stage-time-remaining').textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;
    }

    showHeistCompletion(data) {
        const modal = document.getElementById('heist-completion-modal');
        const icon = document.getElementById('completion-icon');
        const title = document.getElementById('completion-title');
        const reasonSection = document.getElementById('completion-reason');

        if (data.success) {
            icon.innerHTML = '<i class="fas fa-check-circle"></i>';
            icon.className = 'completion-icon success';
            title.textContent = 'Heist Completed!';
            reasonSection.classList.add('hidden');
        } else {
            icon.innerHTML = '<i class="fas fa-times-circle"></i>';
            icon.className = 'completion-icon failure';
            title.textContent = 'Heist Failed!';
            reasonSection.classList.remove('hidden');
            document.getElementById('failure-reason-text').textContent = data.reason || 'Unknown reason';
        }

        document.getElementById('completed-heist-name').textContent = data.heistName || '-';
        document.getElementById('completion-reward').textContent = `$${(data.reward || 0).toLocaleString()}`;
        document.getElementById('completion-xp').textContent = `${data.xp || 0} XP`;
        document.getElementById('completion-duration').textContent = data.duration || '-';

        modal.classList.remove('hidden');
        
        // Hide heist HUD
        document.getElementById('heist-execution-hud').classList.add('hidden');
    }

    closeCompletionModal() {
        document.getElementById('heist-completion-modal').classList.add('hidden');
        this.activeHeist = null;
    }

    updateCrewInfo(crewData) {
        if (!crewData) {
            this.currentCrew = null;
            this.ownedEquipment = {};
            const crewList = document.getElementById('crew-members-list');
            if (crewList) {
                crewList.innerHTML = '';
            }
            this.updateRequiredEquipment();
            this.updatePreHeistChecklist();
            return;
        }

        this.currentCrew = crewData;
        this.ownedEquipment = crewData?.equipment || {};
        this.updateCrewDisplay();
        this.updateRequiredEquipment();
        this.updatePreHeistChecklist();
    }

    updateCrewDisplay() {
        const crewList = document.getElementById('crew-members-list');
        if (!crewList || !this.currentCrew?.members) return;

        crewList.innerHTML = this.currentCrew.members.map(member => {
            const memberId = typeof member === 'object' ? member.id : member;
            const memberName = typeof member === 'object' ? (member.name || `Player ${memberId}`) : `Player ${memberId}`;
            const memberRoleId = typeof member === 'object'
                ? member.role
                : (this.currentCrew.roles?.[memberId] || this.currentCrew.roles?.[String(memberId)] || 'crew');
            const roleConfig = this.crewRoles.find(role => role.id === memberRoleId);
            const memberRole = roleConfig?.name || memberRoleId.replace(/_/g, ' ');

            return `
            <div class="crew-member">
                <div class="member-info">
                    <div class="member-name">${memberName}</div>
                    <div class="member-role">${memberRole}</div>
                </div>
                <div class="member-status ready">
                    Ready
                </div>
            </div>
        `;
        }).join('');
    }

    showNotification(message, type = 'info') {
        // Integrate with existing notification system
        if (window.showToast) {
            window.showToast(message, type);
        } else {
            console.log(`[CNR_HEIST] ${type.toUpperCase()}: ${message}`);
        }
    }
}

// ====================================================================
// Initialize Systems and Enhanced Message Handling
// ====================================================================

let bankingSystem = null;
let heistSystem = null;

// Initialize systems when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    bankingSystem = new BankingSystem();
    heistSystem = new HeistSystem();
});

// Enhanced message handling for banking and heist systems
const originalMessageListener = window.addEventListener;

window.addEventListener('message', function(event) {
    const data = event.data;
    const messageType = data.action || data.type;
    
    // Banking system messages
    switch (messageType) {
        case 'openATM':
            if (bankingSystem) {
                bankingSystem.openATM(data.atmData);
            }
            break;
            
        case 'openBank':
            if (bankingSystem) {
                bankingSystem.openBank(data.bankData);
            }
            break;
            
        case 'updateBankBalance':
            if (bankingSystem) {
                bankingSystem.updateBalance(data.balance);
            }
            break;
            
        case 'updateTransactionHistory':
            if (bankingSystem) {
                bankingSystem.transactionHistory = data.history;
                bankingSystem.updateTransactionHistory();
            }
            break;

        case 'closeBanking':
            if (bankingSystem) {
                document.getElementById('atm-interface')?.classList.add('hidden');
                document.getElementById('bank-interface')?.classList.add('hidden');
                bankingSystem.isATMOpen = false;
                bankingSystem.isBankOpen = false;
            }
            break;
            
        case 'showProgressBar':
            if (bankingSystem) {
                bankingSystem.showProgressBar(data.duration, data.label);
            }
            break;
            
        case 'hideProgressBar':
            if (bankingSystem) {
                bankingSystem.hideProgressBar();
            }
            break;
            
        case 'showNotification':
            if (bankingSystem) {
                bankingSystem.showNotification(data.message, data.notificationType);
            }
            break;
            
        // Heist system messages
        case 'openHeistPlanning':
            if (heistSystem) {
                heistSystem.openHeistPlanning(data.heistConfig, data.crewId, data.crewRoles, data.equipmentShop);
            }
            break;
            
        case 'updateAvailableHeists':
            if (heistSystem) {
                heistSystem.updateAvailableHeists(data.heists);
            }
            break;
            
        case 'updateCrewInfo':
            if (heistSystem) {
                heistSystem.updateCrewInfo(data.crew);
            }
            break;
            
        case 'startHeistExecution':
            if (heistSystem) {
                heistSystem.startHeistExecution(data.heistConfig, data.crew);
            }
            break;
            
        case 'updateHeistStage':
            if (heistSystem) {
                heistSystem.updateHeistStage(data.stageData);
            }
            break;
            
        case 'heistCompleted':
            if (heistSystem) {
                heistSystem.showHeistCompletion(data);
            }
            break;
    }
});

console.log('[CNR_BANKING_HEIST] Banking and Heist UI systems loaded');
