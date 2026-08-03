local curTemplate
local curTags = {}

local activePlayers = {}
local playerSettings = {}
local nameVisibilityOverrides = {}

local legacyTextColors = {
    white = '#f0f0f0',
    red = '#e03232',
    green = '#72cc72',
    blue = '#5db6e5',
    yellow = '#f0c850',
    orange = '#ff8555',
    purple = '#8466e2',
    pink = '#cb3694',
    gray = '#8c8c8c'
}

local function normalizeTextColor(value)
    if type(value) ~= 'string' then
        return '#f0f0f0'
    end

    local normalized = value:lower()
    if legacyTextColors[normalized] then
        return legacyTextColors[normalized]
    end

    local hex = normalized:match('^#(%x%x%x%x%x%x)$')
    return hex and ('#%s'):format(hex) or '#f0f0f0'
end

local function normalizeVisibleNameLimit(value)
    local limit = tonumber(value)
    if not limit then
        return 5
    end

    limit = math.floor(limit)
    return math.max(1, math.min(20, limit))
end

local function truncateUtf8(value, maxCharacters)
    local ok, nextByte = pcall(utf8.offset, value, maxCharacters + 1)
    if ok and nextByte then
        return value:sub(1, nextByte - 1)
    end

    return ok and value or value:sub(1, maxCharacters)
end

local function getPlayerData(playerId)
    if GetResourceState('qbx_core') ~= 'started' then
        return nil
    end

    local player = exports.qbx_core:GetPlayer(playerId)
    return player and player.PlayerData or nil
end

local function getCharacterId(playerId)
    local playerData = getPlayerData(playerId)
    local characterId = playerData and playerData.citizenid

    if type(characterId) ~= 'string' or characterId == '' then
        return nil
    end

    return characterId
end

local function getCharacterName(playerId)
    local playerData = getPlayerData(playerId)
    local charInfo = playerData and playerData.charinfo

    if not charInfo then
        return ''
    end

    local firstName = type(charInfo.firstname) == 'string' and charInfo.firstname or ''
    local lastName = type(charInfo.lastname) == 'string' and charInfo.lastname or ''

    local characterName = (firstName .. ' ' .. lastName):gsub('^%s*(.-)%s*$', '%1')
    return truncateUtf8(characterName, 32)
end

local function getAccountIdentifier(playerId)
    local identifier = GetPlayerIdentifierByType(playerId, 'license')

    if not identifier then
        identifier = GetPlayerIdentifierByType(playerId, 'license2')
    end

    if not identifier then
        identifier = GetPlayerIdentifierByType(playerId, 'fivem')
    end

    return identifier
end

local function getLegacyPersistenceKey(playerId)
    local identifier = getAccountIdentifier(playerId)

    if not identifier then
        return nil
    end

    return ('playernames:%s'):format(identifier:gsub('[^%w_.%-]', '_'))
end

local function getPersistenceKey(playerId)
    local characterId = getCharacterId(playerId)

    if not characterId then
        return nil
    end

    return ('playernames:character:%s'):format(characterId:gsub('[^%w_.%-]', '_'))
end

local function getMigrationKey(playerId)
    local identifier = getAccountIdentifier(playerId)

    if not identifier then
        return nil
    end

    return ('playernames:migration:character-v1:%s'):format(identifier:gsub('[^%w_.%-]', '_'))
end

local function trimDisplayName(value)
    if type(value) ~= 'string' then
        return ''
    end

    value = value:gsub('[\r\n\t]', ' ')
    value = value:match('^%s*(.-)%s*$') or ''

    return truncateUtf8(value, 32)
end

local function trimStatus(value)
    if type(value) ~= 'string' then
        return ''
    end

    value = value:gsub('[\r\n\t]', ' ')
    value = value:match('^%s*(.-)%s*$') or ''

    return truncateUtf8(value, 32)
end

local function normalizeSettings(settings)
    settings = type(settings) == 'table' and settings or {}

    local achievement = settings.achievement
    if achievement ~= 'coming_soon' then
        achievement = 'coming_soon'
    end

    return {
        status = trimStatus(settings.status),
        statusColor = normalizeTextColor(settings.statusColor),
        displayName = trimDisplayName(settings.displayName),
        nameColor = normalizeTextColor(settings.nameColor),
        achievement = achievement,
        showSelf = settings.showSelf == true,
        showOthers = settings.showOthers == true,
        maxVisibleNames = normalizeVisibleNameLimit(settings.maxVisibleNames),
        characterName = type(settings.characterName) == 'string' and settings.characterName or ''
    }
end

local function readPersistentSettings(key)
    if not key then
        return nil
    end

    local encoded = GetResourceKvpString(key)
    if not encoded or encoded == '' then
        return nil
    end

    local ok, decoded = pcall(json.decode, encoded)
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    return normalizeSettings(decoded)
end

local function loadPersistentSettings(playerId)
    local key = getPersistenceKey(playerId)

    if not key then
        return normalizeSettings({})
    end

    local settings = readPersistentSettings(key)
    if settings then
        return settings
    end

    -- Migrate the old account-level settings only once. This preserves existing
    -- settings without making them the fallback for every character.
    local migrationKey = getMigrationKey(playerId)
    if migrationKey and GetResourceKvpString(migrationKey) ~= '1' then
        local legacySettings = readPersistentSettings(getLegacyPersistenceKey(playerId))
        if legacySettings then
            SetResourceKvp(key, json.encode(legacySettings))
        end

        SetResourceKvp(migrationKey, '1')
        return legacySettings or normalizeSettings({})
    end

    return normalizeSettings({})
end

local function savePersistentSettings(playerId, settings)
    local key = getPersistenceKey(playerId)

    if key then
        SetResourceKvp(key, json.encode(settings))
    end
end

local function publicSettings(playerId, settings)
    local showSelf = settings.showSelf
    if nameVisibilityOverrides[playerId] == false then
        showSelf = false
    end

    return {
        status = settings.status,
        statusColor = settings.statusColor,
        displayName = settings.displayName,
        nameColor = settings.nameColor,
        showSelf = showSelf,
        achievement = settings.achievement,
        characterName = settings.characterName
    }
end

local function broadcastPlayerSettings(playerId, includeLocalSettings)
    local settings = playerSettings[playerId]
    if not settings then
        return
    end

    TriggerClientEvent('playernames:settingsUpdated', -1, playerId, publicSettings(playerId, settings))

    if includeLocalSettings then
        TriggerClientEvent('playernames:settingsUpdated', playerId, playerId, settings)
    end
end

local function refreshCharacterSettings(playerId, notifyPlayer)
    local characterId = getCharacterId(playerId)
    if not characterId then
        return
    end

    local settings = loadPersistentSettings(playerId)
    local characterName = getCharacterName(playerId)
    if characterName ~= '' and settings.characterName ~= characterName then
        settings.characterName = characterName
        savePersistentSettings(playerId, settings)
    end

    playerSettings[playerId] = settings
    activePlayers[playerId] = true
    reconfigure(playerId)
    broadcastPlayerSettings(playerId, notifyPlayer)
end

local function detectUpdates()
    SetTimeout(500, detectUpdates)

    local template = GetConvar('playerNames_template', '{{name}}')
    
    if curTemplate ~= template then
        setNameTemplate(-1, template)

        curTemplate = template
    end

    template = GetConvar('playerNames_svTemplate', '{{name}}')

    for v, _ in pairs(activePlayers) do
        local newTag = formatPlayerNameTag(v, template)
        if newTag ~= curTags[v] then
            setName(v, newTag)
            
            curTags[v] = newTag
        end
    end

    for i, tag in pairs(curTags) do
        if not activePlayers[i] then
            curTags[i] = nil -- in case curTags doesnt get cleared when the player left, clear it now.
        end
    end
end

RegisterNetEvent("playernames:setSelfNameVisible")
AddEventHandler("playernames:setSelfNameVisible", function(visible)
    local playerId = source
    local nameVisible = visible == true

    if nameVisible then
        if nameVisibilityOverrides[playerId] == nil then
            return
        end

        nameVisibilityOverrides[playerId] = nil
    else
        if nameVisibilityOverrides[playerId] == false then
            return
        end

        nameVisibilityOverrides[playerId] = false
    end

    broadcastPlayerSettings(playerId, true)
end)

AddEventHandler("playerDropped", function()
    curTags[source] = nil
    activePlayers[source] = nil
    playerSettings[source] = nil
    nameVisibilityOverrides[source] = nil
    TriggerClientEvent('playernames:settingsUpdated', -1, source, false)
end)

local function unloadCharacter(playerId)
    curTags[playerId] = nil
    activePlayers[playerId] = nil
    playerSettings[playerId] = nil
    nameVisibilityOverrides[playerId] = nil
    TriggerClientEvent('playernames:settingsUpdated', -1, playerId, false)
end

AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerId)
    playerId = tonumber(playerId) or tonumber(source)
    if not playerId then
        return
    end

    unloadCharacter(playerId)
end)

RegisterNetEvent('playernames:init')
AddEventHandler('playernames:init', function()
    local playerId = source
    local settings = loadPersistentSettings(playerId)
    local characterName = getCharacterName(playerId)

    if characterName ~= '' and settings.characterName ~= characterName then
        settings.characterName = characterName
        savePersistentSettings(playerId, settings)
    end

    playerSettings[playerId] = settings

    reconfigure(playerId)
    activePlayers[playerId] = true

    for id, settings in pairs(playerSettings) do
        local data = id == playerId and settings or publicSettings(id, settings)
        TriggerClientEvent('playernames:settingsUpdated', playerId, id, data)
    end

    broadcastPlayerSettings(playerId, true)
end)

RegisterNetEvent('playernames:saveSettings')
AddEventHandler('playernames:saveSettings', function(settings)
    local playerId = source
    local normalized = normalizeSettings(settings)
    normalized.characterName = getCharacterName(playerId)

    playerSettings[playerId] = normalized
    savePersistentSettings(playerId, normalized)

    broadcastPlayerSettings(playerId, true)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded')
AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
    local playerId = source
    refreshCharacterSettings(playerId, true)
end)

detectUpdates()
