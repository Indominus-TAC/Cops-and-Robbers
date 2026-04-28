-- Client clipboard / coordinate utility helpers.

function CopyTextToClipboard(text, successMessage)
    if not text or text == "" then
        return false
    end

    SendNUIMessage({
        action = 'copyToClipboard',
        text = text,
        successMessage = successMessage or "Copied to clipboard."
    })

    return true
end

function BuildPlayerCoordsClipboardText(playerPed)
    if not playerPed or playerPed == 0 then
        return nil
    end

    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    if not coords then
        return nil
    end

    return string.format("vector4(%.2f, %.2f, %.2f, %.2f)", coords.x, coords.y, coords.z, heading)
end
