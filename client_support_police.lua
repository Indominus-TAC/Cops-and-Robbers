-- Client helpers for police-department config, randomized cop spawns, and PD garage resolution.

local function ResolveConfigEntryCoords(entry)
    if not entry then
        return nil
    end

    if type(entry) == "vector3" or type(entry) == "vector4" then
        return vector3(entry.x, entry.y, entry.z)
    end

    local location = entry.location or entry.pos or entry.coords
    if location then
        if type(location) == "vector3" or type(location) == "vector4" then
            return vector3(location.x, location.y, location.z)
        end

        if type(location) == "table" and location.x and location.y and location.z then
            return vector3(location.x, location.y, location.z)
        end
    end

    if entry.x and entry.y and entry.z then
        return vector3(entry.x, entry.y, entry.z)
    end

    return nil
end

function GetPoliceDepartments()
    if Config and type(Config.PoliceDepartments) == "table" then
        return Config.PoliceDepartments
    end

    return {}
end

function BuildMergedPdGarageConfig(baseGarage, department)
    local base = baseGarage or {}
    local overrideGarage = department and department.garage or nil
    if type(overrideGarage) ~= "table" then
        return base
    end

    local merged = {}
    for key, value in pairs(base) do
        merged[key] = value
    end

    for key, value in pairs(overrideGarage) do
        if key ~= "interaction" then
            merged[key] = value
        end
    end

    local mergedInteraction = {}
    if type(base.interaction) == "table" then
        for key, value in pairs(base.interaction) do
            mergedInteraction[key] = value
        end
    end
    if type(overrideGarage.interaction) == "table" then
        for key, value in pairs(overrideGarage.interaction) do
            mergedInteraction[key] = value
        end
    end
    if next(mergedInteraction) then
        merged.interaction = mergedInteraction
    end

    merged.departmentId = department and department.id or merged.departmentId
    merged.departmentName = department and department.name or merged.departmentName
    merged.title = merged.title or (department and department.name and (department.name .. " Garage")) or "PD Garage"
    return merged
end

function GetRandomPoliceDepartment()
    local departments = GetPoliceDepartments()
    if #departments <= 0 then
        return nil
    end

    return departments[math.random(1, #departments)]
end

function GetRoleSpawnEntry(roleName)
    if roleName == "cop" then
        local department = GetRandomPoliceDepartment()
        if department and department.respawn then
            return department.respawn, department
        end
    end

    if Config and Config.SpawnPoints then
        return Config.SpawnPoints[roleName], nil
    end

    return nil, nil
end

function GetNearestPoliceDepartment(originCoords, requireGarage)
    local departments = GetPoliceDepartments()
    if #departments <= 0 then
        return nil
    end

    local searchOrigin = originCoords
    if not searchOrigin then
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 then
            searchOrigin = GetEntityCoords(playerPed)
        end
    end

    if not searchOrigin then
        return departments[1]
    end

    local nearestDepartment = nil
    local nearestDistance = math.huge

    for _, department in ipairs(departments) do
        local candidateEntry = nil
        if requireGarage then
            local garageInteraction = department.garage and department.garage.interaction
            candidateEntry = garageInteraction and garageInteraction.location or nil
        end

        candidateEntry = candidateEntry or department.respawn or department.copStore
        local candidateCoords = ResolveConfigEntryCoords(candidateEntry)
        if candidateCoords then
            local distance = #(searchOrigin - candidateCoords)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestDepartment = department
            end
        end
    end

    return nearestDepartment or departments[1]
end

function GetResolvedPdGarageContext(originCoords)
    local baseGarage = Config and type(Config.PDGarage) == "table" and Config.PDGarage.enabled and Config.PDGarage or nil
    if not baseGarage then
        return nil
    end

    local department = GetNearestPoliceDepartment(originCoords, true)
    local garage = BuildMergedPdGarageConfig(baseGarage, department)
    if not garage or not garage.enabled then
        return nil
    end

    return {
        department = department,
        garage = garage
    }
end

function GetAllResolvedPdGarageContexts()
    local baseGarage = Config and type(Config.PDGarage) == "table" and Config.PDGarage.enabled and Config.PDGarage or nil
    if not baseGarage then
        return {}
    end

    local departments = GetPoliceDepartments()
    if #departments <= 0 then
        return {
            {
                department = nil,
                garage = baseGarage
            }
        }
    end

    local contexts = {}
    for _, department in ipairs(departments) do
        contexts[#contexts + 1] = {
            department = department,
            garage = BuildMergedPdGarageConfig(baseGarage, department)
        }
    end

    return contexts
end
