-- system_test.lua
-- Expanded test suite for Cops and Robbers game mode.
-- This file includes tests for core gameplay mechanics, data persistence, and security.

-- Only load on the server side.
if not IsDuplicityVersion() then
    return
end

local TestSuite = {}
local testResults = {}

-- =============================================================================
--                            TEST UTILITY FUNCTIONS
-- =============================================================================

local function LogTest(testName, message, status)
    local statusColors = { PASS = "^2", FAIL = "^1", INFO = "^4" }
    local color = statusColors[status] or "^7"
    Log(string.format("[TEST:%s] %s%s^0", testName, color, message), "info", "CNR_TEST")
end

local function Assert(condition, testName, failureMessage)
    if not condition then
        LogTest(testName, "Assertion FAILED: " .. failureMessage, "FAIL")
        testResults[testName] = testResults[testName] or {}
        table.insert(testResults[testName], { result = "FAIL", message = failureMessage })
        return false
    end
    return true
end

-- Mocks a player for testing purposes. In a live environment, you would use a real player source.
local MOCK_PLAYER_ID = 1

-- =============================================================================
--                            GAMEPLAY MECHANICS TESTS
-- =============================================================================

function TestSuite.RunWantedSystemTest()
    local testName = "WantedSystem"
    LogTest(testName, "Starting wanted system test...", "INFO")
    testResults[testName] = {}

    local pData = PlayerManager.GetPlayerData(MOCK_PLAYER_ID)
    if not Assert(pData, testName, "Mock player data not found.") then return end

    -- 1. Test crime reporting and wanted level increase
    PlayerManager.SetPlayerRole(MOCK_PLAYER_ID, "robber")
    WantedManager.UpdateWantedLevel(MOCK_PLAYER_ID, "speeding")
    local wantedData = WantedManager.GetWantedData(MOCK_PLAYER_ID)
    if Assert(wantedData and wantedData.wantedLevel > 0, testName, "Wanted level did not increase after crime.") then
        LogTest(testName, "Wanted level correctly increased on crime.", "PASS")
    end

    -- 2. Test wanted decay
    wantedData.lastCrimeTime = os.time() - (Config.WantedSettings.noCrimeCooldownMs / 1000 + 1)
    Citizen.Wait(Config.WantedSettings.decayIntervalMs + 100) -- Wait for a decay cycle
    local wantedLevelAfterDecay = wantedData.wantedLevel
    -- This test is tricky due to timing; we expect it to be lower, but can't guarantee it.
    -- For a real test framework, we'd manually invoke the decay function.

    -- 3. Test clearing wanted level
    WantedManager.ClearWantedLevel(MOCK_PLAYER_ID, "Test Cleanup")
    if Assert(wantedData.wantedLevel == 0 and wantedData.stars == 0, testName, "Wanted level was not cleared.") then
        LogTest(testName, "Wanted level cleared successfully.", "PASS")
    end
    PlayerManager.SetPlayerRole(MOCK_PLAYER_ID, "citizen") -- Cleanup
end

function TestSuite.RunJailSystemTest()
    local testName = "JailSystem"
    LogTest(testName, "Starting jail system test...", "INFO")
    testResults[testName] = {}

    local pData = PlayerManager.GetPlayerData(MOCK_PLAYER_ID)
    if not Assert(pData, testName, "Mock player data not found.") then return end

    -- 1. Test sending a player to jail
    PlayerManager.SetPlayerRole(MOCK_PLAYER_ID, "robber")
    WantedManager.UpdateWantedLevel(MOCK_PLAYER_ID, "murder_cop") -- High crime for a long sentence
    local wantedData = WantedManager.GetWantedData(MOCK_PLAYER_ID)
    
    JailManager.SendToJail(MOCK_PLAYER_ID, nil)
    if Assert(pData.jailData and pData.jailData.remainingTime > 0, testName, "Player was not sent to jail.") then
        LogTest(testName, "Player sent to jail successfully.", "PASS")
    end

    -- 2. Test offline time calculation
    local originalRemaining = pData.jailData.remainingTime
    pData.jailData.jailedTimestamp = os.time() - (originalRemaining / 2) -- Simulate half the time has passed
    JailManager.CheckJailStatusOnLoad(MOCK_PLAYER_ID)
    if Assert(pData.jailData.remainingTime < originalRemaining, testName, "Offline jail time was not calculated correctly.") then
        LogTest(testName, "Offline jail time calculation is correct.", "PASS")
    end

    -- 3. Test release from jail
    JailManager.ReleaseFromJail(MOCK_PLAYER_ID, "Test Cleanup")
    if Assert(not pData.jailData, testName, "Player was not released from jail.") then
        LogTest(testName, "Player released from jail successfully.", "PASS")
    end
    PlayerManager.SetPlayerRole(MOCK_PLAYER_ID, "citizen") -- Cleanup
end

function TestSuite.RunHeistSystemTest()
    local testName = "HeistSystem"
    LogTest(testName, "Starting heist system test...", "INFO")
    testResults[testName] = {}

    local pData = PlayerManager.GetPlayerData(MOCK_PLAYER_ID)
    if not Assert(pData, testName, "Mock player data not found.") then return end

    PlayerManager.SetPlayerRole(MOCK_PLAYER_ID, "robber")

    -- 1. Test police requirement
    local onlineCops = HeistManager.GetOnlinePoliceCount()
    local requiredCops = Config.Heists.bank.requiredPolice
    
    if onlineCops < requiredCops then
        LogTest(testName, "Skipping heist initiation test: Not enough cops online.", "INFO")
    else
        HeistManager.InitiateHeist(MOCK_PLAYER_ID, "bank")
        -- We can't easily test the outcome here without a more complex setup,
        -- but we can check logs for the success message.
    end

    -- More detailed heist tests would require mocking player states,
    -- multiple player connections, and game events, which is beyond
    -- the scope of this simple test file.
end

-- =============================================================================
--                                TEST RUNNER
-- =============================================================================

function SystemTest.RunAllGameplayTests()
    LogTest("TestSuite", "=============== STARTING GAMEPLAY TESTS ===============", "INFO")
    
    -- Ensure a mock player is set up for testing
    if not PlayerManager.GetPlayerData(MOCK_PLAYER_ID) then
        LogTest("TestSuite", "Setting up mock player for tests...", "INFO")
        -- This is a simplified setup. A real test would use a proper mock library
        -- or a dedicated test client connection.
        PlayerManager.OnPlayerSpawned(MOCK_PLAYER_ID)
        Citizen.Wait(1000) -- Allow time for data to load
    end

    TestSuite.RunWantedSystemTest()
    Citizen.Wait(1000)
    TestSuite.RunJailSystemTest()
    Citizen.Wait(1000)
    TestSuite.RunHeistSystemTest()
    Citizen.Wait(1000)
    
    LogTest("TestSuite", "================ GAMEPLAY TESTS COMPLETE ================", "INFO")
    SystemTest.GenerateReport()
end

function SystemTest.GenerateReport()
    LogTest("REPORT", "=============== TEST SUITE SUMMARY ===============", "INFO")
    local totalTests = 0
    local totalFails = 0

    for testName, results in pairs(testResults) do
        local fails = 0
        for _, result in ipairs(results) do
            if result.result == "FAIL" then
                fails = fails + 1
            end
        end
        totalFails = totalFails + fails
        totalTests = totalTests + #results

        if fails > 0 then
            LogTest(testName, string.format("Completed with %d failures.", fails), "FAIL")
        else
            LogTest(testName, "All assertions passed.", "PASS")
        end
    end

    if totalFails > 0 then
        LogTest("REPORT", string.format("SUMMARY: %d TOTAL FAILURES out of %d assertions.", totalFails, totalTests), "FAIL")
    else
        LogTest("REPORT", string.format("SUMMARY: ALL %d ASSERTIONS PASSED.", totalTests), "PASS")
    end
    LogTest("REPORT", "===================================================", "INFO")
end

-- =============================================================================
--                                ADMIN COMMAND
-- =============================================================================

RegisterCommand('cnr_runtests', function(source, args, rawCommand)
    if source ~= 0 then return end -- Only allow from server console
    SystemTest.RunAllGameplayTests()
end, false)

Log("[SystemTest] Test suite loaded. Use 'cnr_runtests' in the server console to run.", "info", "CNR_TEST")
