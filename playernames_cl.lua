local mpGamerTags = {}
local mpGamerTagSettings = {}
local playerNameRuntime = {}
local playerNameSettings = {}
local playerIndexByServerId = {}

local ACTIVE_PLAYERS_INTERVAL = 250
local TAG_CHECK_INTERVAL = 250
local DISTANCE_INTERVAL = 100
local LOS_INTERVAL = 125
local VOICE_INTERVAL = 50
local IDLE_UPDATE_INTERVAL = 500
local ACTIVE_UPDATE_INTERVAL = 50
local DISPLAY_DISTANCE_SQUARED = 250.0 * 250.0
local STATUS_HEIGHT_OFFSET = 1.15
local STATUS_TEXT_SCALE_MAX = 0.38
local STATUS_TEXT_SCALE_MIN = 0.24
local STATUS_TEXT_SCALE_RATIO = 0.82
local LABEL_LINE_SPACING = 0.026
local LABEL_SCREEN_SMOOTHING = 0.35
local LABEL_SCREEN_SNAP_DISTANCE_SQUARED = 0.04

local activePlayers = {}
local activePlayerSet = {}
local playerLabelDrawEntries = {}
local nameDisplayCandidateSet = {}
local nextActivePlayersRefresh = 0
local nextDistanceUpdate = 0
local nextVoiceUpdate = 0
local updateScheduleId = 0

local localSettings = {
    status = '',
    statusColor = 'white',
    displayName = '',
    nameColor = 'white',
    achievement = 'coming_soon',
    showSelf = false,
    showOthers = false,
    maxVisibleNames = 5
}

local textColors = {
    white = { hud = 1, red = 240, green = 240, blue = 240 },
    red = { hud = 6, red = 224, green = 50, blue = 50 },
    blue = { hud = 9, red = 93, green = 182, blue = 229 },
    yellow = { hud = 12, red = 240, green = 200, blue = 80 },
    orange = { hud = 15, red = 255, green = 133, blue = 85 },
    green = { hud = 18, red = 114, green = 204, blue = 114 },
    purple = { hud = 21, red = 132, green = 102, blue = 226 },
    pink = { hud = 24, red = 203, green = 54, blue = 148 },
    gray = { hud = 67, red = 140, green = 140, blue = 140 }
}

local DEFAULT_TEXT_COLOR = '#f0f0f0'

local function normalizeTextColor(value)
    if type(value) ~= 'string' then
        return DEFAULT_TEXT_COLOR
    end

    local normalized = value:lower()
    local legacyColor = textColors[normalized]

    if legacyColor then
        return ('#%02x%02x%02x'):format(legacyColor.red, legacyColor.green, legacyColor.blue)
    end

    local hex = normalized:match('^#(%x%x%x%x%x%x)$')
    return hex and ('#%s'):format(hex) or DEFAULT_TEXT_COLOR
end

local function getTextColor(value)
    local hex = normalizeTextColor(value):sub(2)

    return {
        red = tonumber(hex:sub(1, 2), 16),
        green = tonumber(hex:sub(3, 4), 16),
        blue = tonumber(hex:sub(5, 6), 16)
    }
end

local function normalizeVisibleNameLimit(value)
    local limit = tonumber(value)
    if not limit then
        return 5
    end

    limit = math.floor(limit)
    return math.max(1, math.min(21, limit))
end

local settingsMenuOpen = false
local updatePlayerNames
local scheduleNextUpdate

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

local function makeSettings(serverId)
    return {
        serverId = serverId,
        alphas = {},
        colors = {},
        healthColor = false,
        toggles = {},
        wantedLevel = false
    }
end

local function makeRuntime(serverId)
    return {
        serverId = serverId,
        ped = nil,
        distanceSquared = math.huge,
        hasDistance = false,
        hasLos = false,
        los = false,
        talking = false,
        lastVisible = false,
        name = '',
        status = '',
        statusColor = getTextColor(DEFAULT_TEXT_COLOR),
        nameColor = getTextColor(DEFAULT_TEXT_COLOR),
        drawX = nil,
        drawY = nil,
        nextTagCheck = 0,
        nextLosCheck = 0,
        applied = {
            visibility = {},
            alphas = {},
            colors = {},
            wantedLevel = nil,
            healthColor = nil
        }
    }
end

local function resetRuntime(i)
    playerNameRuntime[i] = nil
end

local function getBoundServerId(i)
    local settings = mpGamerTagSettings[i]
    if settings and settings.serverId then
        return settings.serverId
    end

    local runtime = playerNameRuntime[i]
    if runtime and runtime.serverId then
        return runtime.serverId
    end

    local gamerTag = mpGamerTags[i]
    return gamerTag and gamerTag.serverId
end

local function removePlayerTag(i)
    if mpGamerTags[i] then
        RemoveMpGamerTag(mpGamerTags[i].tag)
        mpGamerTags[i] = nil
    end

    resetRuntime(i)
end

local function removePlayerState(i)
    removePlayerTag(i)
    mpGamerTagSettings[i] = nil

    for serverId, playerIndex in pairs(playerIndexByServerId) do
        if playerIndex == i then
            playerIndexByServerId[serverId] = nil
        end
    end
end

local function shouldDisplayPlayerName(i)
    -- showOthers is the local master switch for both self and other labels.
    if not localSettings.showOthers then
        return false
    end

    -- Keep the local view consistent with the player's public visibility choice.
    if i == PlayerId() then
        return localSettings.showSelf
    end

    local serverId = GetPlayerServerId(i)
    local settings = playerNameSettings[serverId]
    return settings and settings.showSelf == true
end

local function buildNameDisplayCandidateSet(localPlayer, localPed)
    if not localPed or localPed == 0 or not DoesEntityExist(localPed) then
        return {}
    end

    local localCoords = GetEntityCoords(localPed)
    local candidates = {}

    for _, i in ipairs(activePlayers) do
        if shouldDisplayPlayerName(i) then
            local ped = i == localPlayer and localPed or GetPlayerPed(i)

            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                local dx = coords.x - localCoords.x
                local dy = coords.y - localCoords.y
                local dz = coords.z - localCoords.z

                candidates[#candidates + 1] = {
                    playerIndex = i,
                    ped = ped,
                    distanceSquared = dx * dx + dy * dy + dz * dz
                }
            end
        end
    end

    table.sort(candidates, function(left, right)
        if left.distanceSquared == right.distanceSquared then
            return left.playerIndex < right.playerIndex
        end

        return left.distanceSquared < right.distanceSquared
    end)

    local limit = normalizeVisibleNameLimit(localSettings.maxVisibleNames)
    local candidateCount = limit == 21 and #candidates or math.min(limit, #candidates)
    local candidateSet = {}

    for index = 1, candidateCount do
        local candidate = candidates[index]
        candidateSet[candidate.playerIndex] = candidate
    end

    return candidateSet
end

local function removeHiddenPlayerTags()
    for i in pairs(mpGamerTags) do
        if not shouldDisplayPlayerName(i) then
            removePlayerTag(i)
        end
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

    local status = type(settings.status) == 'string' and settings.status or ''
    status = status:gsub('[\r\n\t]', ' '):match('^%s*(.-)%s*$') or ''

    local displayName = type(settings.displayName) == 'string' and settings.displayName or ''
    displayName = displayName:gsub('[\r\n\t]', ' '):match('^%s*(.-)%s*$') or ''

    local statusColor = normalizeTextColor(settings.statusColor)
    local nameColor = normalizeTextColor(settings.nameColor)

    local function truncateUtf8(value, maxCharacters)
        local ok, nextByte = pcall(utf8.offset, value, maxCharacters + 1)
        if ok and nextByte then
            return value:sub(1, nextByte - 1)
        end

        return ok and value or value:sub(1, maxCharacters)
    end

    return {
        status = truncateUtf8(status, 32),
        statusColor = statusColor,
        displayName = truncateUtf8(displayName, 32),
        nameColor = nameColor,
        achievement = 'coming_soon',
        showSelf = settings.showSelf == true,
        showOthers = settings.showOthers == true,
        maxVisibleNames = normalizeVisibleNameLimit(settings.maxVisibleNames)
    }
end

RegisterCommand('name', openSettingsMenu, false)

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
        status = localSettings.status,
        statusColor = localSettings.statusColor,
        displayName = localSettings.displayName,
        nameColor = localSettings.nameColor,
        achievement = localSettings.achievement,
        showSelf = localSettings.showSelf,
        showOthers = localSettings.showOthers,
        maxVisibleNames = localSettings.maxVisibleNames
    })

    -- Hide tags immediately when the display mode changes instead of waiting
    -- for the next maintenance pass.
    removeHiddenPlayerTags()
    if scheduleNextUpdate then
        scheduleNextUpdate(0)
    end

    closeSettingsMenu()
    cb({ ok = true })
end)

RegisterNetEvent('playernames:settingsUpdated')
AddEventHandler('playernames:settingsUpdated', function(serverId, settings)
    serverId = tonumber(serverId)

    if not serverId then
        return
    end

    local playerIndex = GetPlayerFromServerId(serverId)

    if settings == false then
        playerNameSettings[serverId] = nil

        -- The server sends this for a dropped player. Remove the tag and all
        -- slot-indexed state immediately, before the next active-player scan.
        if not playerIndex or playerIndex < 0 then
            playerIndex = playerIndexByServerId[serverId]
        end

        if playerIndex and getBoundServerId(playerIndex) == serverId then
            removePlayerState(playerIndex)
        end

        playerIndexByServerId[serverId] = nil
    else
        playerNameSettings[serverId] = settings

        if serverId == GetPlayerServerId(PlayerId()) then
            local previousShowSelf = localSettings.showSelf
            local previousShowOthers = localSettings.showOthers
            local previousMaxVisibleNames = localSettings.maxVisibleNames
            local normalized = normalizeLocalSettings(settings)

            -- The public event includes showSelf because it controls whether
            -- this player's name may be rendered by other clients. The local
            -- showOthers master switch remains private to this client.
            if settings.showOthers == nil then
                normalized.showOthers = previousShowOthers
            end

            if settings.maxVisibleNames == nil then
                normalized.maxVisibleNames = previousMaxVisibleNames
            end

            localSettings = normalized

            if localSettings.showSelf ~= previousShowSelf
                or localSettings.showOthers ~= previousShowOthers then
                removeHiddenPlayerTags()
            end
        end

        -- Only the tag belonging to the changed server ID needs a rename.
        if playerIndex and playerIndex >= 0 and mpGamerTagSettings[playerIndex] then
            mpGamerTagSettings[playerIndex].rename = true
        end
    end

    if scheduleNextUpdate then
        scheduleNextUpdate(0)
    end
end)

local templateStr

local function refreshActivePlayers(now)
    activePlayers = GetActivePlayers()
    activePlayerSet = {}
    local refreshedPlayerIndexByServerId = {}

    for _, i in ipairs(activePlayers) do
        activePlayerSet[i] = true

        local serverId = GetPlayerServerId(i)
        if serverId and serverId >= 0 then
            local boundServerId = getBoundServerId(i)

            -- The index may have stayed active while being reassigned between
            -- maintenance passes. Treat an ID change as a completely new slot.
            if boundServerId and boundServerId ~= serverId then
                removePlayerState(i)
            end

            refreshedPlayerIndexByServerId[serverId] = i
        end
    end

    -- A client index can be reused. Remove every cache associated with an
    -- index which is no longer active before it can be assigned to someone else.
    for i in pairs(mpGamerTags) do
        if not activePlayerSet[i] then
            removePlayerState(i)
        end
    end

    for i in pairs(mpGamerTagSettings) do
        if not activePlayerSet[i] then
            removePlayerState(i)
        end
    end

    for i in pairs(playerNameRuntime) do
        if not activePlayerSet[i] then
            resetRuntime(i)
        end
    end

    playerIndexByServerId = refreshedPlayerIndexByServerId
    nextActivePlayersRefresh = now + ACTIVE_PLAYERS_INTERVAL
end

local function resetAppliedState(runtime)
    runtime.applied = {
        visibility = {},
        alphas = {},
        colors = {},
        wantedLevel = nil,
        healthColor = nil
    }
end

local function getPlayerTextPresentation(i)
    local settings = playerNameSettings[GetPlayerServerId(i)] or {}
    local status = type(settings.status) == 'string' and settings.status or ''
    local statusColor = getTextColor(settings.statusColor)
    local nameColor = getTextColor(settings.nameColor)

    return status, statusColor, nameColor
end

local function ensurePlayerTag(i, ped, now, shouldCheckPed)
    local serverId = GetPlayerServerId(i)
    if not serverId or serverId < 0 then
        return nil, nil, nil
    end

    local boundServerId = getBoundServerId(i)
    if boundServerId and boundServerId ~= serverId then
        removePlayerState(i)
    end

    playerIndexByServerId[serverId] = i

    local settings = mpGamerTagSettings[i]
    if not settings then
        settings = makeSettings(serverId)
        mpGamerTagSettings[i] = settings
    end

    local runtime = playerNameRuntime[i]
    if not runtime then
        runtime = makeRuntime(serverId)
        playerNameRuntime[i] = runtime
    end

    if shouldCheckPed then
        if not ped then
            ped = GetPlayerPed(i)
        end

        runtime.ped = ped
        runtime.nextTagCheck = now + TAG_CHECK_INTERVAL
    else
        ped = runtime.ped
    end

    if not ped or ped == 0 then
        if mpGamerTags[i] then
            removePlayerTag(i)
        end

        return nil, runtime, settings
    end

    local gamerTag = mpGamerTags[i]
    local needsNewTag = not gamerTag or gamerTag.ped ~= ped

    if gamerTag and shouldCheckPed and not IsMpGamerTagActive(gamerTag.tag) then
        needsNewTag = true
    end

    if needsNewTag then
        if gamerTag then
            RemoveMpGamerTag(gamerTag.tag)
        end

        gamerTag = {
            tag = CreateMpGamerTag(ped, '', false, false, '', 0),
            ped = ped,
            serverId = serverId
        }

        mpGamerTags[i] = gamerTag
        runtime.ped = ped
        runtime.hasDistance = false
        runtime.hasLos = false
        runtime.los = false
        runtime.talking = false
        runtime.lastVisible = false
        runtime.nextLosCheck = now
        runtime.name = formatPlayerNameTag(i, templateStr)
        runtime.status, runtime.statusColor, runtime.nameColor = getPlayerTextPresentation(i)
        runtime.drawX = nil
        runtime.drawY = nil
        SetMpGamerTagBigText(gamerTag.tag, '')
        resetAppliedState(runtime)

        -- The visible name is drawn by the custom renderer. The native tag is
        -- retained only for components such as the voice icon.
        settings.rename = nil
    end

    return gamerTag, runtime, settings
end

local function getComponentId(key)
    if type(key) == 'number' then
        return key
    end

    return gtComponent[key]
end

local function applyDesiredState(tag, runtime, settings, isVisible)
    local applied = runtime.applied
    local desiredVisibility = {}

    -- Start from an explicit hidden state for every component previously
    -- touched by this resource. This also clears removed overrides and prevents
    -- custom components from remaining visible through distance or LOS changes.
    for component in pairs(applied.visibility) do
        desiredVisibility[component] = false
    end

    desiredVisibility[gtComponent.GAMER_NAME] = false
    desiredVisibility[gtComponent.healthArmour] = false
    desiredVisibility[gtComponent.BIG_TEXT] = false
    -- ponytail: スピーカーアイコンは常に非表示（戻すなら isVisible and runtime.talking or false）
    desiredVisibility[gtComponent.AUDIO_ICON] = false

    local desiredAlphas = {}
    local desiredColors = {}

    if isVisible then
        desiredAlphas[gtComponent.AUDIO_ICON] = 255
        desiredAlphas[gtComponent.healthArmour] = 255
        for key, value in pairs(settings.toggles) do
            local component = getComponentId(key)
            if component ~= nil then
                desiredVisibility[component] = value
            end
        end

        for key, value in pairs(settings.alphas) do
            local component = getComponentId(key)
            if component ~= nil then
                desiredAlphas[component] = value
            end
        end

        for key, value in pairs(settings.colors) do
            local component = getComponentId(key)
            if component ~= nil then
                desiredColors[component] = value
            end
        end
    end

    -- Do not let component overrides re-enable the blank native name or the
    -- legacy big-text status component.
    desiredVisibility[gtComponent.GAMER_NAME] = false
    desiredVisibility[gtComponent.BIG_TEXT] = false

    for component, value in pairs(desiredVisibility) do
        if applied.visibility[component] ~= value then
            SetMpGamerTagVisibility(tag, component, value)
            applied.visibility[component] = value
        end
    end

    for component, value in pairs(desiredAlphas) do
        if applied.alphas[component] ~= value then
            SetMpGamerTagAlpha(tag, component, value)
            applied.alphas[component] = value
        end
    end

    for component, value in pairs(desiredColors) do
        if applied.colors[component] ~= value then
            SetMpGamerTagColour(tag, component, value)
            applied.colors[component] = value
        end
    end

    if isVisible and settings.wantedLevel and applied.wantedLevel ~= settings.wantedLevel then
        SetMpGamerTagWantedLevel(tag, settings.wantedLevel)
        applied.wantedLevel = settings.wantedLevel
    end

    if isVisible and settings.healthColor and applied.healthColor ~= settings.healthColor then
        SetMpGamerTagHealthBarColour(tag, settings.healthColor)
        applied.healthColor = settings.healthColor
    end
end

local function applyPendingRename(i, tag, runtime, settings)
    if settings.rename then
        runtime.name = formatPlayerNameTag(i, templateStr)
        SetMpGamerTagName(tag, '')
        runtime.status, runtime.statusColor, runtime.nameColor = getPlayerTextPresentation(i)
        SetMpGamerTagBigText(tag, '')
        settings.rename = nil
    end
end

local function drawPlayerLabelLine(text, screenX, screenY, scale, color)
    if not text or text == '' then
        return
    end

    SetTextScale(0.0, scale)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(color.red, color.green, color.blue, 255)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

local function drawPlayerLabel(entry)
    if not DoesEntityExist(entry.ped) then
        return
    end

    local coords = GetEntityCoords(entry.ped)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(
        coords.x,
        coords.y,
        coords.z + STATUS_HEIGHT_OFFSET
    )

    if not onScreen then
        entry.runtime.drawX = nil
        entry.runtime.drawY = nil
        return
    end

    local runtime = entry.runtime

    if runtime.drawX and runtime.drawY then
        local dx = screenX - runtime.drawX
        local dy = screenY - runtime.drawY

        if dx * dx + dy * dy > LABEL_SCREEN_SNAP_DISTANCE_SQUARED then
            runtime.drawX = screenX
            runtime.drawY = screenY
        else
            runtime.drawX = runtime.drawX + dx * LABEL_SCREEN_SMOOTHING
            runtime.drawY = runtime.drawY + dy * LABEL_SCREEN_SMOOTHING
        end
    else
        runtime.drawX = screenX
        runtime.drawY = screenY
    end

    local distance = math.sqrt(entry.distanceSquared)
    local scale = STATUS_TEXT_SCALE_MAX - math.max(distance - 25.0, 0.0) * 0.00065
    scale = math.max(STATUS_TEXT_SCALE_MIN, scale)
    local lineSpacing = LABEL_LINE_SPACING * (scale / STATUS_TEXT_SCALE_MAX)

    if entry.status ~= '' then
        -- ponytail: 名前を基準位置に固定し、ステータスは上へ逃がす（ステータス有無で名前がずれない）
        drawPlayerLabelLine(
            entry.status,
            runtime.drawX,
            runtime.drawY - lineSpacing,
            scale * STATUS_TEXT_SCALE_RATIO,
            entry.statusColor
        )
        drawPlayerLabelLine(
            entry.name,
            runtime.drawX,
            runtime.drawY,
            scale,
            entry.nameColor
        )
    else
        drawPlayerLabelLine(entry.name, runtime.drawX, runtime.drawY, scale, entry.nameColor)
    end
end

local function renderPlayerLabels()
    local entries = playerLabelDrawEntries

    for _, entry in ipairs(entries) do
        drawPlayerLabel(entry)
    end

    SetTimeout(#entries > 0 and 0 or 250, renderPlayerLabels)
end

local function updatePlayerNamesImpl()
    local now = GetGameTimer()
    local showAny = localSettings.showOthers
    local nextDelay = templateStr and showAny and ACTIVE_UPDATE_INTERVAL or IDLE_UPDATE_INTERVAL

    -- Reserve the next pass before any template, event, or Native work. A
    -- transient error in the current pass must not permanently stop updates.
    scheduleNextUpdate(nextDelay)

    if now >= nextActivePlayersRefresh then
        refreshActivePlayers(now)
    end

    -- Keep this loop alive at a low rate while disabled, but do not perform
    -- player/ped/LOS work until a display option is enabled.
    if not templateStr or not showAny then
        playerLabelDrawEntries = {}
        nameDisplayCandidateSet = {}
        return
    end

    local localPlayer = PlayerId()
    local localPed = PlayerPedId()
    local updateVoice = now >= nextVoiceUpdate

    if now >= nextDistanceUpdate then
        nameDisplayCandidateSet = buildNameDisplayCandidateSet(localPlayer, localPed)
        nextDistanceUpdate = now + DISTANCE_INTERVAL
    end

    if updateVoice then
        nextVoiceUpdate = now + VOICE_INTERVAL
    end

    local nextPlayerLabelDrawEntries = {}

    for _, i in ipairs(activePlayers) do
        local isSelf = i == localPlayer
        local candidate = nameDisplayCandidateSet[i]
        local shouldShow = candidate ~= nil

        if not shouldShow then
            removePlayerTag(i)
        else
            local runtime = playerNameRuntime[i]
            local shouldCheckPed = not runtime or now >= runtime.nextTagCheck

            if isSelf and runtime and runtime.ped ~= localPed then
                shouldCheckPed = true
            end

            local pedForTag = isSelf and localPed or (shouldCheckPed and candidate.ped or nil)
            local gamerTag
            gamerTag, runtime = ensurePlayerTag(i, pedForTag, now, shouldCheckPed)

            if gamerTag then
                local settings = mpGamerTagSettings[i]
                applyPendingRename(i, gamerTag.tag, runtime, settings)

                runtime.distanceSquared = candidate.distanceSquared
                runtime.hasDistance = true

                local isNearby = runtime.hasDistance and runtime.distanceSquared < DISPLAY_DISTANCE_SQUARED

                if isNearby then
                    if isSelf then
                        runtime.hasLos = true
                        runtime.los = true
                    elseif now >= runtime.nextLosCheck or not runtime.hasLos then
                        runtime.los = HasEntityClearLosToEntity(localPed, runtime.ped, 17)
                        runtime.hasLos = true
                        runtime.nextLosCheck = now + LOS_INTERVAL
                    end
                else
                    runtime.hasLos = true
                    runtime.los = false
                    runtime.nextLosCheck = now + LOS_INTERVAL
                end

                local isVisible = isNearby and (isSelf or runtime.los)

                if isVisible and (updateVoice or not runtime.lastVisible) then
                    runtime.talking = NetworkIsPlayerTalking(i)
                elseif not isVisible then
                    runtime.talking = false
                end

                applyDesiredState(gamerTag.tag, runtime, settings, isVisible)

                if isVisible and runtime.name ~= '' then
                    nextPlayerLabelDrawEntries[#nextPlayerLabelDrawEntries + 1] = {
                        ped = runtime.ped,
                        name = runtime.name,
                        nameColor = runtime.nameColor,
                        status = runtime.status,
                        statusColor = runtime.statusColor,
                        distanceSquared = runtime.distanceSquared,
                        runtime = runtime
                    }
                else
                    runtime.drawX = nil
                    runtime.drawY = nil
                end

                runtime.lastVisible = isVisible
            end
        end
    end

    playerLabelDrawEntries = nextPlayerLabelDrawEntries
end

updatePlayerNames = updatePlayerNamesImpl

scheduleNextUpdate = function(delay)
    updateScheduleId = updateScheduleId + 1
    local scheduledId = updateScheduleId

    SetTimeout(delay, function()
        if scheduledId == updateScheduleId then
            updatePlayerNames()
        end
    end)
end

local function wakePlayerNamesUpdate()
    nextActivePlayersRefresh = 0
    nextDistanceUpdate = 0
    nextVoiceUpdate = 0
    scheduleNextUpdate(0)
end

local function getSettings(id)
    local serverId = tonumber(id)
    if not serverId then
        return nil
    end

    local i = GetPlayerFromServerId(serverId)
    if not i or i < 0 then
        return nil
    end

    local boundServerId = getBoundServerId(i)
    if boundServerId and boundServerId ~= serverId then
        removePlayerState(i)
    end

    playerIndexByServerId[serverId] = i

    if not mpGamerTagSettings[i] then
        mpGamerTagSettings[i] = makeSettings(serverId)
    end

    return mpGamerTagSettings[i]
end

RegisterNetEvent('playernames:configure')

AddEventHandler('playernames:configure', function(id, key, ...)
    local args = table.pack(...)
    local settings = getSettings(id)

    if key == 'tpl' then
        for _, value in pairs(mpGamerTagSettings) do
            value.rename = true
        end

        templateStr = args[1]
        wakePlayerNamesUpdate()
        return
    end

    if not settings then
        return
    end

    if key == 'tglc' then
        settings.toggles[args[1]] = args[2]
    elseif key == 'seta' then
        settings.alphas[args[1]] = args[2]
    elseif key == 'setc' then
        settings.colors[args[1]] = args[2]
    elseif key == 'setw' then
        settings.wantedLevel = args[1]
    elseif key == 'sehc' then
        settings.healthColor = args[1]
    elseif key == 'rnme' then
        settings.rename = true
    elseif key == 'name' then
        settings.serverName = args[1]
        settings.rename = true
    end

    wakePlayerNamesUpdate()
end)

AddEventHandler('playernames:extendContext', function(i, cb)
    local serverNameSettings = getSettings(GetPlayerServerId(i))
    cb('serverName', serverNameSettings and serverNameSettings.serverName)

    if not IsDuplicityVersion() then
        local settings = playerNameSettings[GetPlayerServerId(i)]
        local characterName = settings and settings.characterName or ''

        if characterName == '' then
            characterName = GetPlayerName(i)
        end

        local displayName = settings and settings.displayName or ''

        if displayName == '' then
            displayName = characterName
        end

        cb('displayName', displayName)
        cb('characterName', characterName)

        local status = settings and settings.status or ''
        local statusColor = settings and settings.statusColor or 'white'
        local nameColor = settings and settings.nameColor or 'white'

        cb('status', status)
        cb('statusColor', statusColor)
        cb('nameColor', nameColor)
        cb('statusLine', '')
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        settingsMenuOpen = false
        SendNUIMessage({ action = 'close' })
        SetNuiFocus(false, false)

        for i in pairs(mpGamerTags) do
            removePlayerTag(i)
        end

        mpGamerTagSettings = {}
        playerNameRuntime = {}
        playerIndexByServerId = {}
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

scheduleNextUpdate(0)
SetTimeout(0, renderPlayerLabels)
