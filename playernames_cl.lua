local mpGamerTags = {}
local mpGamerTagSettings = {}
local playerNameSettings = {}

local localSettings = {
    displayName = '',
    achievement = 'coming_soon',
    showSelf = true,
    showOthers = true
}

local settingsMenuOpen = false

local gtComponent = {
    GAMER_NAME = 0,
    CREW_TAG = 1,
    healthArmour = 2,
    BIG_TEXT = 3,
    AUDIO_ICON = 4,
    MP_USING_MENU = 5,
    MP_PASSIVE_MODE = 6,
    WANTED_STARS = 7,
    MP_DRIVER = 8,
    MP_CO_DRIVER = 9,
    MP_TAGGED = 10,
    GAMER_NAME_NEARBY = 11,
    ARROW = 12,
    MP_PACKAGES = 13,
    INV_IF_PED_FOLLOWING = 14,
    RANK_TEXT = 15,
    MP_TYPING = 16
}

local function makeSettings()
    return {
        alphas = {},
        colors = {},
        healthColor = false,
        toggles = {},
        wantedLevel = false
    }
end

local function removePlayerTag(i)
    if mpGamerTags[i] then
        RemoveMpGamerTag(mpGamerTags[i].tag)
        mpGamerTags[i] = nil
    end
end

local function closeSettingsMenu()
    if not settingsMenuOpen then
        return
    end

    settingsMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openSettingsMenu()
    settingsMenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        settings = localSettings
    })

    -- The NUI page may still be initializing on the first command after resource start.
    -- Send the open message again after it has had a chance to register its listener.
    SetTimeout(100, function()
        if settingsMenuOpen then
            SendNUIMessage({
                action = 'open',
                settings = localSettings
            })
        end
    end)
end

local function normalizeLocalSettings(settings)
    settings = type(settings) == 'table' and settings or {}

    local displayName = type(settings.displayName) == 'string' and settings.displayName or ''
    displayName = displayName:gsub('[\r\n\t]', ' '):match('^%s*(.-)%s*$') or ''

    return {
        displayName = displayName:sub(1, 32),
        achievement = 'coming_soon',
        showSelf = settings.showSelf ~= false,
        showOthers = settings.showOthers ~= false
    }
end

RegisterCommand('playernames', openSettingsMenu, false)
RegisterCommand('namesettings', openSettingsMenu, false)

RegisterNUICallback('close', function(_, cb)
    closeSettingsMenu()
    cb({ ok = true })
end)

RegisterNUICallback('ready', function(_, cb)
    if settingsMenuOpen then
        SendNUIMessage({
            action = 'open',
            settings = localSettings
        })
    end

    cb({ ok = true })
end)

RegisterNUICallback('saveSettings', function(data, cb)
    localSettings = normalizeLocalSettings(data)
    TriggerServerEvent('playernames:saveSettings', {
        displayName = localSettings.displayName,
        achievement = localSettings.achievement
    })

    closeSettingsMenu()
    cb({ ok = true })
end)

RegisterNetEvent('playernames:settingsUpdated')
AddEventHandler('playernames:settingsUpdated', function(serverId, settings)
    serverId = tonumber(serverId)

    if not serverId then
        return
    end

    if settings == false then
        playerNameSettings[serverId] = nil
    else
        playerNameSettings[serverId] = settings

        if serverId == GetPlayerServerId(PlayerId()) then
            localSettings.displayName = settings.displayName or ''
            localSettings.achievement = settings.achievement or 'coming_soon'
        end
    end

    for _, settingsForTag in pairs(mpGamerTagSettings) do
        settingsForTag.rename = true
    end
end)

local templateStr

function updatePlayerNames()
    -- re-run this function the next frame
    SetTimeout(0, updatePlayerNames)

    -- return if no template string is set
    if not templateStr then
        return
    end

    -- get local coordinates to compare to
    local localCoords = GetEntityCoords(PlayerPedId())

    -- for each valid player index
    for _, i in ipairs(GetActivePlayers()) do
        local isSelf = i == PlayerId()
        local shouldShow = isSelf and localSettings.showSelf or (not isSelf and localSettings.showOthers)

        if not shouldShow then
            removePlayerTag(i)
        else
            -- get their ped
            local ped = GetPlayerPed(i)
            local pedCoords = GetEntityCoords(ped)

            -- make a new settings list if needed
            if not mpGamerTagSettings[i] then
                mpGamerTagSettings[i] = makeSettings()
            end

            -- check the ped, because changing player models may recreate the ped
            -- also check gamer tag activity in case the game deleted the gamer tag
            if not mpGamerTags[i] or mpGamerTags[i].ped ~= ped or not IsMpGamerTagActive(mpGamerTags[i].tag) then
                local nameTag = formatPlayerNameTag(i, templateStr)

                -- remove any existing tag
                if mpGamerTags[i] then
                    RemoveMpGamerTag(mpGamerTags[i].tag)
                end

                -- store the new tag
                mpGamerTags[i] = {
                    tag = CreateMpGamerTag(ped, nameTag, false, false, '', 0),
                    ped = ped
                }
            end

            -- store the tag in a local
            local tag = mpGamerTags[i].tag

            -- should the player be renamed? this is set by events
            if mpGamerTagSettings[i].rename then
                SetMpGamerTagName(tag, formatPlayerNameTag(i, templateStr))
                mpGamerTagSettings[i].rename = nil
            end

            -- check distance
            local distance = #(pedCoords - localCoords)

            -- show/hide based on nearbyness/line-of-sight
            -- nearby checks are primarily to prevent a lot of LOS checks
            if distance < 250 and (isSelf or HasEntityClearLosToEntity(PlayerPedId(), ped, 17)) then
                SetMpGamerTagVisibility(tag, gtComponent.GAMER_NAME, true)
                SetMpGamerTagVisibility(tag, gtComponent.healthArmour, IsPlayerTargettingEntity(PlayerId(), ped))
                SetMpGamerTagVisibility(tag, gtComponent.AUDIO_ICON, NetworkIsPlayerTalking(i))

                SetMpGamerTagAlpha(tag, gtComponent.AUDIO_ICON, 255)
                SetMpGamerTagAlpha(tag, gtComponent.healthArmour, 255)

                -- override settings
                local settings = mpGamerTagSettings[i]

                for k, v in pairs(settings.toggles) do
                    SetMpGamerTagVisibility(tag, gtComponent[k], v)
                end

                for k, v in pairs(settings.alphas) do
                    SetMpGamerTagAlpha(tag, gtComponent[k], v)
                end

                for k, v in pairs(settings.colors) do
                    SetMpGamerTagColour(tag, gtComponent[k], v)
                end

                if settings.wantedLevel then
                    SetMpGamerTagWantedLevel(tag, settings.wantedLevel)
                end

                if settings.healthColor then
                    SetMpGamerTagHealthBarColour(tag, settings.healthColor)
                end
            else
                SetMpGamerTagVisibility(tag, gtComponent.GAMER_NAME, false)
                SetMpGamerTagVisibility(tag, gtComponent.healthArmour, false)
                SetMpGamerTagVisibility(tag, gtComponent.AUDIO_ICON, false)
            end
        end
    end
end

local function getSettings(id)
    local i = GetPlayerFromServerId(tonumber(id))

    if not mpGamerTagSettings[i] then
        mpGamerTagSettings[i] = makeSettings()
    end

    return mpGamerTagSettings[i]
end

RegisterNetEvent('playernames:configure')

AddEventHandler('playernames:configure', function(id, key, ...)
    local args = table.pack(...)

    if key == 'tglc' then
        getSettings(id).toggles[args[1]] = args[2]
    elseif key == 'seta' then
        getSettings(id).alphas[args[1]] = args[2]
    elseif key == 'setc' then
        getSettings(id).colors[args[1]] = args[2]
    elseif key == 'setw' then
        getSettings(id).wantedLevel = args[1]
    elseif key == 'sehc' then
        getSettings(id).healthColor = args[1]
    elseif key == 'rnme' then
        getSettings(id).rename = true
    elseif key == 'name' then
        getSettings(id).serverName = args[1]
        getSettings(id).rename = true
    elseif key == 'tpl' then
        for _, v in pairs(mpGamerTagSettings) do
            v.rename = true
        end

        templateStr = args[1]
    end
end)

AddEventHandler('playernames:extendContext', function(i, cb)
    cb('serverName', getSettings(GetPlayerServerId(i)).serverName)

    if not IsDuplicityVersion() then
        local settings = playerNameSettings[GetPlayerServerId(i)]
        cb('displayName', settings and settings.displayName or nil)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        settingsMenuOpen = false
        SendNUIMessage({ action = 'close' })
        SetNuiFocus(false, false)

        for _, v in pairs(mpGamerTags) do
            RemoveMpGamerTag(v.tag)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == GetCurrentResourceName() then
        settingsMenuOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
    end
end)

SetTimeout(0, function()
    TriggerServerEvent('playernames:init')
end)

-- run this function every frame
SetTimeout(0, updatePlayerNames)
