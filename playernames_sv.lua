local curTemplate
local curTags = {}

local activePlayers = {}
local playerSettings = {}

local allowedTextColors = {
    white = true,
    red = true,
    green = true,
    blue = true,
    yellow = true,
    orange = true,
    purple = true,
    pink = true,
    gray = true
}

local function normalizeTextColor(value)
    return allowedTextColors[value] and value or 'white'
end

local function truncateUtf8(value, maxCharacters)
    local ok, nextByte = pcall(utf8.offset, value, maxCharacters + 1)
    if ok and nextByte then
        return value:sub(1, nextByte - 1)
    end

    return ok and value or value:sub(1, maxCharacters)
end

local function getCharacterName(playerId)
    if GetResourceState('qbx_core') ~= 'started' then
        return ''
    end

    local player = exports.qbx_core:GetPlayer(playerId)
    local charInfo = player and player.PlayerData and player.PlayerData.charinfo

    if not charInfo then
        return ''
    end

    local firstName = type(charInfo.firstname) == 'string' and charInfo.firstname or ''
    local lastName = type(charInfo.lastname) == 'string' and charInfo.lastname or ''

    local characterName = (firstName .. ' ' .. lastName):gsub('^%s*(.-)%s*$', '%1')
    return truncateUtf8(characterName, 32)
end

local function getPersistenceKey(playerId)
    local identifier = GetPlayerIdentifierByType(playerId, 'license')

    if not identifier then
        identifier = GetPlayerIdentifierByType(playerId, 'license2')
    end

    if not identifier then
        identifier = GetPlayerIdentifierByType(playerId, 'fivem')
    end

    if not identifier then
        return nil
    end

    return ('playernames:%s'):format(identifier:gsub('[^%w_.%-]', '_'))
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
        characterName = type(settings.characterName) == 'string' and settings.characterName or ''
    }
end

local function loadPersistentSettings(playerId)
    local key = getPersistenceKey(playerId)

    if not key then
        return normalizeSettings({})
    end

    local encoded = GetResourceKvpString(key)
    if not encoded or encoded == '' then
        return normalizeSettings({})
    end

    local ok, decoded = pcall(json.decode, encoded)
    if not ok or type(decoded) ~= 'table' then
        return normalizeSettings({})
    end

    return normalizeSettings(decoded)
end

local function savePersistentSettings(playerId, settings)
    local key = getPersistenceKey(playerId)

    if key then
        SetResourceKvp(key, json.encode(settings))
    end
end

local function publicSettings(settings)
    return {
        status = settings.status,
        statusColor = settings.statusColor,
        displayName = settings.displayName,
        nameColor = settings.nameColor,
        achievement = settings.achievement,
        characterName = settings.characterName
    }
end

local function broadcastPlayerSettings(playerId, includeLocalSettings)
    local settings = playerSettings[playerId]
    if not settings then
        return
    end

    TriggerClientEvent('playernames:settingsUpdated', -1, playerId, publicSettings(settings))

    if includeLocalSettings then
        TriggerClientEvent('playernames:settingsUpdated', playerId, playerId, settings)
    end
end

local function refreshCharacterName(playerId, notifyPlayer)
    local settings = playerSettings[playerId]
    if not settings then
        settings = loadPersistentSettings(playerId)
        playerSettings[playerId] = settings
    end

    local characterName = getCharacterName(playerId)
    if characterName == '' then
        return
    end

    if settings.characterName == characterName then
        return
    end

    settings.characterName = characterName
    savePersistentSettings(playerId, settings)
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

AddEventHandler('playerDropped', function()
    curTags[source] = nil
    activePlayers[source] = nil
    playerSettings[source] = nil
    TriggerClientEvent('playernames:settingsUpdated', -1, source, false)
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
        local data = id == playerId and settings or publicSettings(settings)
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
    refreshCharacterName(playerId, true)
end)

detectUpdates()
