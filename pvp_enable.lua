local function EnablePvP()
    local playerPed = PlayerPedId()

    -- Allows players to damage each other
    NetworkSetFriendlyFireOption(true)

    -- Allows this player's ped to attack other friendly/player peds
    SetCanAttackFriendly(playerPed, true, true)
end

CreateThread(function()
    while true do
        EnablePvP()

        -- Run every few seconds in case another script resets it
        Wait(5000)
    end
end)

AddEventHandler('playerSpawned', function()
    Wait(1000)
    EnablePvP()
end)