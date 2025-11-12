-- utils/log_utils.lua
-- Provides a centralized and standardized logging utility for the entire resource.

--- A global logging function that adds a prefix and handles different log levels.
--- Can be required and used by any server-side script.
---@param message string The message to log.
---@param level string (Optional) The severity level of the message ('info', 'warn', 'error', 'debug'). Defaults to 'info'.
---@param source string (Optional) The source or module of the log message (e.g., 'CNR_SERVER'). Defaults to 'CNR_SERVER'.
function Log(message, level, source)
    level = level or "info"
    source = source or "CNR_SERVER"

    -- Use ANSI escape codes for colored output in the console for better readability.
    local color = ""
    if level == "error" then
        color = "^1" -- Red
    elseif level == "warn" then
        color = "^3" -- Yellow
    elseif level == "info" then
        color = "^2" -- Green
    elseif level == "debug" then
        color = "^5" -- Purple
    end

    local formattedMessage = string.format("%s[%s] [%s] %s^0", color, string.upper(source), string.upper(level), message)

    -- Using print() is standard for server-side logging in FiveM.
    print(formattedMessage)
end

-- Make the function available to scripts that require this file.
return Log
