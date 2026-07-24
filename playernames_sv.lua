local curTemplate
local curTags = {}

local activePlayers = {}
local playerSettings = {}

local function trimDisplayName(value)
    if type(value) ~= 'string' then
        return ''
    end

    value = value:gsub('[\r\n\t]', ' ')
    value = value:match('^%s*(.-)%s*$') or ''

    return value:sub(1, 32)
end

local function normalizeSettings(settings)
    settings = type(settings) == 'table' and settings or {}

    local achievement = settings.achievement
    if achievement ~= 'coming_soon' then
        achievement = 'coming_soon'
    end

    return {
        displayName = trimDisplayName(settings.displayName),
        achievement = achievement
    }
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
    reconfigure(source)
    activePlayers[source] = true

    for id, settings in pairs(playerSettings) do
        TriggerClientEvent('playernames:settingsUpdated', source, id, settings)
    end
end)

RegisterNetEvent('playernames:saveSettings')
AddEventHandler('playernames:saveSettings', function(settings)
    local playerId = source
    local normalized = normalizeSettings(settings)

    playerSettings[playerId] = normalized
    TriggerClientEvent('playernames:settingsUpdated', -1, playerId, normalized)
end)

detectUpdates()
