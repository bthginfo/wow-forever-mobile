local _, addon = ...
local Actions = addon.actions
local Chat = addon.chat
local ArcSave = addon.arcSave
local SIDES = Actions.sides
local DESIGN_HEIGHT = 720
local ICON_SIZE = 62
local ICON_GAP = 7
local ROW_GAP = 10
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ARC_MARGIN = 14
local HANDLE_HEIGHT = 35

local german = addon.german
local moveLabel = german and "Bogen verschieben" or "Move arc"
local isSecret = issecretvalue or function() return false end

local events = CreateFrame("Frame")
local editShield = CreateFrame("Frame", nil, UIParent)
editShield:SetFrameStrata("DIALOG")
editShield:SetAllPoints(UIParent)
editShield:EnableMouse(true)
editShield:Hide()

local shade = editShield:CreateTexture(nil, "BACKGROUND")
shade:SetAllPoints()
shade:SetColorTexture(.07, .05, .03, .32)
local picker = addon.createSlotPicker(editShield)

local groups = {}
for _, side in ipairs(SIDES) do
    local editor = CreateFrame("Frame", nil, editShield)
    editor:SetMovable(true)
    editor:SetClampedToScreen(true)
    groups[side] = { side = side, editor = editor, previews = {} }
end

local livePages, defaults, desktopKeys, desktopRecords, preferences
local profileKey, alternateProfileKey, confirmSaved, retainedAfterReload
local actionPages = {}
local draft, selected, dragFrom, moving
local refreshSlots, refreshLiveButtons, updateEditor
local pendingRefresh, refreshQueued = false, false
local pendingSave, reloadRequested = false, false
local staleSetBindings = false
local spellRanks, spellRanksDirty = nil, true

local switcher = CreateFrame("Button", "ForeverTouchCycleSet", UIParent, "UIPanelButtonTemplate,SecureHandlerClickTemplate")
switcher:SetFrameStrata("HIGH")
switcher:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 20)
switcher:SetSize(132, 41)
switcher:RegisterForClicks("LeftButtonUp")
switcher:Hide()
-- Each set has its own pre-bound buttons. The secure click only changes visibility.
switcher:SetAttribute("_onclick", [[
    if down or button ~= "LeftButton" then return end
    local count = self:GetAttribute("pageCount")
    if not count or count < 2 then return end
    local current = self:GetAttribute("page")
    local nextPage = current % count + 1
    self:GetFrameRef("page" .. current):Hide()
    self:GetFrameRef("page" .. nextPage):Show()
    self:SetAttribute("page", nextPage)
]])

local saveRetry = CreateFrame("Button", "ForeverTouchRetrySave", UIParent, "UIPanelButtonTemplate")
saveRetry:SetFrameStrata("HIGH")
saveRetry:SetPoint("BOTTOM", UIParent, "BOTTOM", 139, 20)
saveRetry:SetSize(128, 32)
saveRetry:SetText(german and "Arc speichern" or "Save arcs")
saveRetry:Hide()

local function setLabel(index, count)
    return string.format("Set %d / %d", index, count)
end

local function pageIndex(value, count)
    if type(value) ~= "number" or value % 1 ~= 0 then return 1 end
    return math.max(1, math.min(value, count))
end

local function createActionPage(index)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    local page = { frame = frame, groups = {} }
    for _, side in ipairs(SIDES) do
        local prefix = side == "left" and "ForeverTouchLeft" or "ForeverTouchRight"
        if index > 1 then prefix = prefix .. "Set" .. index end
        local panel = CreateFrame("Frame", prefix, frame)
        panel:SetClampedToScreen(true)
        page.groups[side] = { panel = panel, prefix = prefix, buttons = {} }
    end
    actionPages[index] = page
    switcher:SetFrameRef("page" .. index, frame)
    return page
end

local function preferenceRevision(profile)
    if type(profile) ~= "table" or not next(profile) then return -1 end
    return type(profile.revision) == "number" and profile.revision or 0
end

local arcFields = { "mobileSlots", "mobileArcPositions", "mobileArcPages", "mobileArcPage", "order", "favorites" }
local function arcRevision(profile)
    if type(profile) ~= "table" then return -1 end
    if type(profile.arcRevision) == "number" then return profile.arcRevision end
    for _, field in ipairs(arcFields) do
        if profile[field] ~= nil then return preferenceRevision(profile) end
    end
    return -1
end

local function readableName(value)
    if not isSecret(value) and type(value) == "string" and value ~= "" then return value end
end

-- The Forever client can write SavedVariables but skip loading them during a
-- UI reload. An in-memory CVar carries the current profile across that reload.
-- For a fresh game process the Android launcher supplies the files from disk.
local SESSION_PROFILE = "foreverTouchSessionProfile"
local SESSION_CHUNK = 220
local MAX_SESSION_CHUNKS = 128

local function readSessionProfile(guid, nameKey)
    if not C_CVar or not C_EncodingUtil then return end
    local ok, state = pcall(function()
        local count = tonumber(C_CVar.GetCVar(SESSION_PROFILE .. "Count"))
        if not count or count % 1 ~= 0 or count < 1 or count > MAX_SESSION_CHUNKS then return end
        local parts = {}
        for index = 1, count do
            local part = C_CVar.GetCVar(SESSION_PROFILE .. index)
            if not part or part == "" then return end
            parts[index] = part
        end
        return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(table.concat(parts)))
    end)
    if ok and type(state) == "table" and (
        (guid and state.guid == guid) or (nameKey and (state.nameKey == nameKey or state.guid == nameKey))
    ) and type(state.profile) == "table" then return state.profile end
end

local function keepProfileForReload()
    if not profileKey or not C_CVar or not C_EncodingUtil then return end
    pcall(function()
        local function write(name, value)
            if C_CVar.GetCVar(name) == nil then C_CVar.RegisterCVar(name, value) end
            C_CVar.SetCVar(name, value)
            return C_CVar.GetCVar(name) == value
        end
        local data = C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR({
            guid = profileKey, nameKey = alternateProfileKey, profile = preferences,
        }))
        local count = math.ceil(#data / SESSION_CHUNK)
        local counter = SESSION_PROFILE .. "Count"
        if count < 1 or count > MAX_SESSION_CHUNKS or not write(counter, "0") then return end
        for index = 1, count do
            local start = (index - 1) * SESSION_CHUNK + 1
            if not write(SESSION_PROFILE .. index, data:sub(start, start + SESSION_CHUNK - 1)) then return end
        end
        write(counter, tostring(count))
    end)
end

local function characterProfileKeys()
    local guid = readableName(UnitGUID("player"))
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    name, realm = readableName(name), readableName(realm)
    if not realm and GetNormalizedRealmName then realm = readableName(GetNormalizedRealmName()) end
    local region = GetCurrentRegion and GetCurrentRegion()
    if isSecret(region) or type(region) ~= "number" then region = 0 end
    local realmName = realm and realm:gsub("%s+", ""):lower()
    local charName = name and name:lower()
    local nameKey = charName and realmName and ("character:" .. region .. "/" .. realmName .. "/" .. charName)
    return guid, nameKey, realmName, charName
end

local function loadPreferences()
    if type(ForeverTouchProfiles) ~= "table" then ForeverTouchProfiles = {} end
    local profiles = ForeverTouchProfiles
    local guid, nameKey, realmName, charName = characterProfileKeys()

    local primary, arcs = ForeverTouchPreferences, ForeverTouchPreferences
    local function consider(profile)
        if preferenceRevision(profile) > preferenceRevision(primary) then primary = profile end
        if arcRevision(profile) > arcRevision(arcs) then arcs = profile end
    end
    consider(guid and profiles[guid])
    consider(nameKey and profiles[nameKey])
    local recovered = addon.recoveredProfiles
    if recovered then
        consider(guid and recovered.profiles[guid])
        consider(nameKey and recovered.profiles[nameKey])
        if charName then
            local id = GetRealmID and GetRealmID()
            if isSecret(id) or type(id) ~= "number" then id = guid and guid:match("^Player%-(%d+)%-") end
            local function considerPath(directory)
                if not directory then return end
                consider(recovered.characters[directory .. "/" .. charName])
                if realmName then consider(recovered.characters[directory .. "/" .. charName .. "-" .. realmName]) end
            end
            considerPath(id and tostring(id))
            considerPath(realmName)
        end
    end
    local session = readSessionProfile(guid, nameKey)
    consider(session)

    -- Keep the legacy GUID lookup and a name fallback for clients that withhold the GUID.
    profileKey, alternateProfileKey = guid or nameKey, guid and nameKey
    preferences = type(primary) == "table" and CopyTable(primary) or {}
    -- A newer chat setting can be saved while an older backup still holds the last arc edits.
    if arcs ~= primary then
        for _, field in ipairs(arcFields) do
            local value = arcs[field]
            preferences[field] = type(value) == "table" and CopyTable(value) or value
        end
        preferences.arcRevision = arcRevision(arcs)
    end
    retainedAfterReload = preferences.confirmArcSave and session ~= nil and (primary == session or arcs == session)
    confirmSaved = preferences.confirmArcSave and not retainedAfterReload
    preferences.confirmArcSave = nil
    ForeverTouchPreferences = preferences
end

local function checkpointPreferences()
    if not preferences then return end
    ForeverTouchPreferences = preferences
    if profileKey then ForeverTouchProfiles[profileKey] = CopyTable(preferences) end
    if alternateProfileKey then ForeverTouchProfiles[alternateProfileKey] = CopyTable(preferences) end
end

local function saveFeedback(message)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(message, .42, .91, .64, 1) end
end

local function requestReload(reload)
    if not reload then return false end
    local ok, result = pcall(reload)
    return ok and result ~= false
end

local function flushSave()
    if not pendingSave or reloadRequested or draft or InCombatLockdown() then return end
    saveRetry:Hide()
    checkpointPreferences()
    keepProfileForReload()

    -- The game requires the input event that triggered this save. A timer or
    -- PLAYER_REGEN_ENABLED can show the retry button but cannot reload the UI.
    local function reloadDidNotStart()
        reloadRequested = false
        if draft or InCombatLockdown() then return end
        saveRetry:Show()
        saveFeedback(german and "Arc noch offen. Erneut speichern oder im Spiel ausloggen."
            or "Arc changes pending. Try saving again or log out in game.")
    end

    reloadRequested = true
    local reload = C_UI and C_UI.Reload
    if requestReload(reload) or (ReloadUI ~= reload and requestReload(ReloadUI)) then
        if reloadRequested then
            C_Timer.After(2, function()
                if reloadRequested then reloadDidNotStart() end
            end)
        end
    else
        reloadDidNotStart()
    end
end

saveRetry:SetScript("OnClick", flushSave)

local function makeSkillArt(button)
    button.rim = button:CreateTexture(nil, "BACKGROUND")
    button.rim:SetAllPoints()
    button.rim:SetTexture(CIRCLE)
    button.rim:SetVertexColor(.65, .49, .28)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(.05, .95, .05, .95)
    local mask = button:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(button.icon)
    button.icon:AddMaskTexture(mask)
end

local function actionButton(group, index)
    local name = group.prefix .. "Action" .. index
    local button = CreateFrame("Button", name, group.panel, "SecureActionButtonTemplate")
    button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("LeftButtonUp")
    makeSkillArt(button)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:EnableMouse(false)
    button.cooldown:SetSwipeTexture(CIRCLE)
    button.cooldown:SetDrawSwipe(true)
    button.cooldown:SetHideCountdownNumbers(false)
    button.cooldown:SetMinimumCountdownDuration(2000)
    local labels = CreateFrame("Frame", nil, button)
    labels:SetAllPoints(button)
    labels:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    labels:EnableMouse(false)
    button.count = labels:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", labels, "BOTTOMRIGHT", -3, 3)
    group.buttons[index] = button
    return button
end

local function normalizedPosition(p)
    return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
        and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1
end

local function arcTravel(width, height, viewport)
    return math.max(0, viewport - width - 2 * ARC_MARGIN),
        math.max(0, DESIGN_HEIGHT - height - HANDLE_HEIGHT - 2 * ARC_MARGIN)
end

-- Two staggered curved bands grow into additional bands only when the player has more slots.
local function arcGeometry(count, viewport, mirrored)
    local maxWidth = math.max(110, viewport * .307)
    local maxHeight = DESIGN_HEIGHT * .325
    local maxCurve = math.min(52, maxWidth * .12)
    local width, height = math.min(205, maxWidth), 52
    local points = {}
    if count == 0 then return width, height, points end

    local columns, rows, diameter = 1, count, 0
    for candidate = 1, count do
        local bands = math.ceil(count / candidate)
        local size = math.min(
            ICON_SIZE,
            (maxWidth + ICON_GAP) / (candidate + .10) - ICON_GAP,
            (maxHeight - maxCurve + ROW_GAP) / bands - ROW_GAP
        )
        if size > diameter or (size == diameter and bands < rows) then
            columns, rows, diameter = candidate, bands, size
        end
    end
    if diameter <= 0 then return width, height, points end

    local stepX, stepY = diameter + ICON_GAP, diameter + ROW_GAP
    width = (columns + .10) * stepX - ICON_GAP
    local curve = math.min(maxCurve, (width - diameter) * .13)
    height = rows * stepY - ROW_GAP + curve
    for row = 1, rows do
        local perRow = math.ceil((count - #points) / (rows - row + 1))
        local inset = (columns - perRow) * stepX + (row % 2 == 1 and .10 * stepX or 0)
        local scale = math.max(.84, 1 - .065 * (row - 1))
        -- The high point sits toward the screen edge; inner ends sweep down toward each thumb.
        for index = 1, perRow do
            local x = diameter / 2 + inset + (index - 1) * stepX
            local ratio = (x - diameter / 2) / math.max(1, width - diameter)
            local y = diameter / 2 + (row - 1) * stepY + curve * (1 - ((ratio - .30) / .70) ^ 2)
            points[#points + 1] = { x = mirrored and width - x or x, y = y, size = diameter * scale }
        end
    end
    return width, height, points
end

local function placeArc(frame, side, scale, width, height, viewport, position)
    frame:SetScale(scale)
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    local x = math.max(ARC_MARGIN, viewport * .027)
    if side == "right" then x = viewport - x - width end
    local y = DESIGN_HEIGHT * .230
    if normalizedPosition(position) then
        local travelX, travelY = arcTravel(width, height, viewport)
        x, y = ARC_MARGIN + position.x * travelX, ARC_MARGIN + position.y * travelY
    end
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function layoutPage(page, pageGroups, editing, scale, viewport)
    for _, side in ipairs(SIDES) do
        local group = pageGroups[side]
        local arcWidth, arcHeight, points = arcGeometry(#page.slots[side], viewport, side == "right")
        local parent, buttons = group.panel, group.buttons
        if editing then parent, buttons = group.editor, group.previews end
        local position = type(page.positions) == "table" and page.positions[side]
        placeArc(parent, side, scale, arcWidth, arcHeight, viewport, position)
        for index, point in ipairs(points) do
            local button = buttons[index]
            button:SetSize(point.size, point.size)
            button:ClearAllPoints()
            button:SetPoint("CENTER", parent, "BOTTOMLEFT", point.x, point.y)
        end
    end
end

local function layoutActions()
    if not livePages or moving then return end
    local width, height = UIParent:GetSize()
    if width <= 0 or height <= 0 then return end
    local scale = height / DESIGN_HEIGHT
    local viewport = width / scale
    if draft then
        layoutPage(draft.pages[draft.index], groups, true, scale, viewport)
    elseif not InCombatLockdown() then
        for index, page in ipairs(livePages) do
            layoutPage(page, actionPages[index].groups, false, scale, viewport)
        end
        switcher:SetScale(scale)
    end
end

local function copyPositions(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for _, side in ipairs(SIDES) do
        local p = source[side]
        if normalizedPosition(p) then result[side] = { x = p.x, y = p.y } end
    end
    return result
end

local function savedPage(profile, positions)
    local slots = Actions.copyProfile(profile)
    local upgraded = Actions.upgradeSpellRanks(slots, desktopRecords, spellRanks)
    return { slots = slots, positions = copyPositions(positions) }, upgraded
end

local function savedPages(persistUpgrades)
    local first = defaults
    if type(preferences.mobileSlots) == "table" then
        first = preferences.mobileSlots
    elseif preferences.order or preferences.favorites then
        first = Actions.splitDesktop(desktopKeys, desktopRecords, preferences.order or preferences.favorites)
    end
    local firstPage, upgraded = savedPage(first, preferences.mobileArcPositions)
    local pages = { firstPage }
    local saved = persistUpgrades and upgraded and first == preferences.mobileSlots
    if saved then preferences.mobileSlots = firstPage.slots end
    if type(preferences.mobileArcPages) == "table" then
        for _, page in ipairs(preferences.mobileArcPages) do
            if type(page) == "table" then
                local livePage, changed = savedPage(page.slots, page.positions)
                pages[#pages + 1] = livePage
                if persistUpgrades and changed then
                    page.slots = livePage.slots
                    saved = true
                end
            end
        end
    end
    if saved then
        preferences.revision = preferenceRevision(preferences) + 1
        preferences.arcRevision = preferences.revision
        checkpointPreferences()
    end
    return pages
end

local function checkpointDraft()
    local first = draft.pages[1]
    preferences.mobileArcPositions = copyPositions(first.positions)
    if first.reset then
        preferences.mobileSlots, preferences.order, preferences.favorites = nil, nil, nil
    end
    if first.changed then
        preferences.mobileSlots = Actions.independentProfile(first.slots, desktopRecords)
    end
    local more = {}
    for index = 2, #draft.pages do
        local page = draft.pages[index]
        more[#more + 1] = { slots = Actions.independentProfile(page.slots, desktopRecords), positions = copyPositions(page.positions) }
    end
    preferences.mobileArcPages = #more > 0 and more or nil
    preferences.mobileArcPage = draft.index > 1 and draft.index or nil
    preferences.revision = preferenceRevision(preferences) + 1
    preferences.arcRevision = preferences.revision
    preferences.confirmArcSave = true
    checkpointPreferences()
    draft.edited, pendingSave, staleSetBindings = true, true, true
end

local function swapSlots(first, second)
    local page = draft.pages[draft.index]
    local from, to = page.slots[first.mobileSide], page.slots[second.mobileSide]
    local a, b = first.mobileIndex, second.mobileIndex
    from[a], to[b] = to[b], from[a]
    page.changed = true
    checkpointDraft()
end

local function previewButton(group, index)
    local button = CreateFrame("Button", nil, group.editor)
    button.mobileSide, button.mobileIndex = group.side, index
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    makeSkillArt(button)
    button:SetScript("OnClick", function()
        if not draft or dragFrom or picker:IsShown() then return end
        if selected and selected ~= button then
            swapSlots(selected, button)
            selected = nil
        else
            selected = selected ~= button and button or nil
        end
        updateEditor()
    end)
    button:SetScript("OnDragStart", function()
        if not draft or picker:IsShown() then return end
        selected, dragFrom = nil, button
        updateEditor()
    end)
    button:SetScript("OnDragStop", function()
        if not draft or dragFrom ~= button then return end
        local destination
        local slots = draft.pages[draft.index].slots
        for _, side in ipairs(SIDES) do
            for target = 1, #slots[side] do
                local other = groups[side].previews[target]
                if other ~= button and other:IsMouseOver() then
                    destination = other
                    break
                end
            end
            if destination then break end
        end
        if destination then swapSlots(button, destination) end
        dragFrom = nil
        updateEditor()
    end)
    group.previews[index] = button
    return button
end

local function chooseBinding(side, index)
    if not draft or picker:IsShown() then return end
    local page = draft.pages[draft.index]
    local list = page.slots[side]
    local old = list[index]
    local current = old
    if old and old.kind == "desktop" then current = desktopRecords[old.key] end
    picker:Open(function(binding)
        if not draft or draft.pages[draft.index] ~= page then return end
        if not old or old.kind ~= binding.kind or old.id ~= binding.id then
            list[index] = binding
            page.changed = true
            checkpointDraft()
        end
        selected = nil
        updateEditor()
    end, current and (current.kind == "item" and "item" or "spell"), current)
end

local tools = CreateFrame("Frame", nil, editShield)
tools:SetPoint("TOP", UIParent, "TOP", 0, -93)
tools:SetSize(280, 146)
local selection = tools:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
selection:SetPoint("TOP", 0, 2)
selection:SetWidth(280)

local assign = CreateFrame("Button", nil, tools, "UIPanelButtonTemplate")
assign:SetSize(129, 37)
assign:SetPoint("TOPLEFT", 4, -25)
assign:SetText(german and "Belegen" or "Assign")
assign:SetScript("OnClick", function()
    if selected then chooseBinding(selected.mobileSide, selected.mobileIndex) end
end)

local remove = CreateFrame("Button", nil, tools, "UIPanelButtonTemplate")
remove:SetSize(129, 37)
remove:SetPoint("TOPRIGHT", -4, -25)
remove:SetText(german and "Entfernen" or "Remove")
remove:SetScript("OnClick", function()
    if not draft or not selected or picker:IsShown() then return end
    local page = draft.pages[draft.index]
    table.remove(page.slots[selected.mobileSide], selected.mobileIndex)
    page.changed = true
    checkpointDraft()
    selected = nil
    updateEditor()
end)

local function normalizedCoordinate(value, travel)
    if travel <= 0 then return .5 end
    return math.min(1, math.max(0, (value - ARC_MARGIN) / travel))
end

for _, side in ipairs(SIDES) do
    local group = groups[side]
    local editor = group.editor
    local move = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    move:SetPoint("BOTTOM", editor, "TOP", -22, 5)
    move:SetSize(154, HANDLE_HEIGHT)
    move:SetClampedToScreen(true)
    move:SetText(moveLabel)
    move:RegisterForDrag("LeftButton")
    move:SetScript("OnDragStart", function()
        if not draft or picker:IsShown() then return end
        moving = group
        editor:StartMoving()
    end)
    move:SetScript("OnDragStop", function()
        if not draft or moving ~= group then return end
        editor:StopMovingOrSizing()
        editor:SetUserPlaced(false)
        moving = nil
        local scale = editor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local travelX, travelY = arcTravel(editor:GetWidth(), editor:GetHeight(), UIParent:GetWidth() / scale)
        local left, bottom = editor:GetLeft(), editor:GetBottom()
        if left and bottom then
            local page = draft.pages[draft.index]
            page.positions[group.side] = {
                x = normalizedCoordinate(left - (UIParent:GetLeft() or 0) / scale, travelX),
                y = normalizedCoordinate(bottom - (UIParent:GetBottom() or 0) / scale, travelY),
            }
            checkpointDraft()
        end
        layoutActions()
    end)

    local add = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    add:SetPoint("LEFT", move, "RIGHT", 4, 0)
    add:SetSize(40, HANDLE_HEIGHT)
    add:SetText("+")
    add:SetClampedToScreen(true)
    add:SetScript("OnClick", function()
        if draft then chooseBinding(group.side, #draft.pages[draft.index].slots[group.side] + 1) end
    end)
    group.add = add
end

local previousSet, nextSet, removeSet, setCaption

updateEditor = function()
    if not draft then return end
    local profile = draft.pages[draft.index].slots
    local mayAdd = #profile.left + #profile.right < Actions.limit
    for _, side in ipairs(SIDES) do
        local group, slots = groups[side], profile[side]
        for index, binding in ipairs(slots) do
            local button = group.previews[index] or previewButton(group, index)
            button.icon:SetTexture(Actions.texture(binding, desktopRecords))
            if button == selected or button == dragFrom then
                button.rim:SetVertexColor(1, .83, .45)
            else
                button.rim:SetVertexColor(.68, .51, .28)
            end
            button:Show()
        end
        for index = #slots + 1, #group.previews do group.previews[index]:Hide() end
        group.add:SetEnabled(mayAdd)
    end
    local binding = selected and profile[selected.mobileSide][selected.mobileIndex]
    selection:SetText(binding and (Actions.name(binding, desktopRecords) or "Slot")
        or (german and "Wähle einen Slot oder tippe auf +" or "Select a slot or tap +"))
    assign:SetEnabled(binding ~= nil)
    remove:SetEnabled(binding ~= nil)
    local caption = setLabel(draft.index, #draft.pages)
    if draft.edited then caption = caption .. (german and " · Übernommen" or " · Applied") end
    setCaption:SetText(caption)
    previousSet:SetEnabled(draft.index > 1)
    nextSet:SetEnabled(draft.index < #draft.pages)
    removeSet:SetEnabled(draft.index > 1)
    tools:SetScale(UIParent:GetHeight() / DESIGN_HEIGHT)
    layoutActions()
end

local function stopMoving()
    if not moving then return end
    moving.editor:StopMovingOrSizing()
    moving.editor:SetUserPlaced(false)
    moving = nil
end

local function setControl(name, label, point, x, y, width, action)
    local button = CreateFrame("Button", "ForeverTouch" .. name, tools, "UIPanelButtonTemplate")
    button:SetSize(width, 35)
    button:SetPoint(point, x, y)
    button:SetText(label)
    button:SetScript("OnClick", function()
        if not draft or moving or dragFrom or picker:IsShown() then return end
        action()
        selected = nil
        updateEditor()
    end)
    return button
end

setCaption = tools:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
setCaption:SetPoint("TOP", 0, -78)
previousSet = setControl("PreviousSet", "‹", "TOPLEFT", 4, -68, 42, function()
    draft.index = math.max(1, draft.index - 1)
end)
nextSet = setControl("NextSet", "›", "TOPRIGHT", -4, -68, 42, function()
    draft.index = math.min(#draft.pages, draft.index + 1)
end)
local function appendSet(slots)
    local current = draft.pages[draft.index]
    draft.pages[#draft.pages + 1] = { slots = slots, positions = copyPositions(current.positions) }
    draft.index = #draft.pages
    checkpointDraft()
end

setControl("AddSet", german and "Neues Set" or "Add set", "BOTTOMLEFT", 4, 0, 88, function()
    appendSet(Actions.copyProfile())
end)
setControl("DuplicateSet", german and "Kopieren" or "Duplicate", "BOTTOM", 0, 0, 88, function()
    local current = draft.pages[draft.index]
    appendSet(Actions.independentProfile(current.slots, desktopRecords))
end)
removeSet = setControl("RemoveSet", german and "Löschen" or "Delete set", "BOTTOMRIGHT", -4, 0, 88, function()
    if draft.index == 1 then return end
    table.remove(draft.pages, draft.index)
    draft.index = math.min(draft.index, #draft.pages)
    checkpointDraft()
end)

local function setActionAlpha(alpha)
    switcher:SetAlpha(alpha)
    for _, page in ipairs(actionPages) do page.frame:SetAlpha(alpha) end
end

local function openEditor()
    if draft or not livePages then return end
    saveRetry:Hide()
    local pages = savedPages()
    draft = {
        pages = pages,
        index = pageIndex(preferences.mobileArcPage, #pages),
        original = CopyTable(preferences),
        originalPendingSave = pendingSave,
        originalStaleBindings = staleSetBindings,
    }
    setActionAlpha(0)
    updateEditor()
    editShield:Show()
end

local function resetEditor()
    if not draft then return end
    stopMoving()
    picker:Hide()
    draft.pages[draft.index] = {
        slots = Actions.copyProfile(draft.index == 1 and defaults or nil),
        positions = {},
        reset = true,
    }
    checkpointDraft()
    selected, dragFrom = nil, nil
    updateEditor()
end

local function finishEditing(keepChanges)
    if not draft then
        if keepChanges then flushSave() end
        return
    end
    stopMoving()
    if keepChanges then
        local selectedSet = draft.index > 1 and draft.index or nil
        if selectedSet ~= preferences.mobileArcPage then checkpointDraft() end
    elseif draft.edited then
        preferences, pendingSave, staleSetBindings = draft.original, draft.originalPendingSave, draft.originalStaleBindings
        checkpointPreferences()
    end
    picker:Hide()
    draft, selected, dragFrom = nil, nil, nil
    editShield:Hide()
    setActionAlpha(1)
    refreshSlots()
    if keepChanges then
        if pendingSave and InCombatLockdown() then
            saveFeedback(german and "Tippe nach dem Kampf auf Arc speichern." or "Tap Save arcs after combat.")
        else
            flushSave()
        end
    elseif pendingSave and preferences.confirmArcSave and not InCombatLockdown() and not reloadRequested then
        saveRetry:Show()
    end
end

local function saveFromToolbar()
    if not ArcSave then
        finishEditing(true)
        return
    end
    if not draft then return end
    if not profileKey then
        local guid, nameKey = characterProfileKeys()
        profileKey, alternateProfileKey = guid or nameKey, guid and nameKey
    end
    local selectedSet = draft.index > 1 and draft.index or nil
    if selectedSet ~= preferences.mobileArcPage then checkpointDraft() end
    ArcSave.show(profileKey, alternateProfileKey, preferences)
end

local function acceptToolbarSave()
    if not ArcSave or not draft then return end
    ArcSave.close()
    pendingSave, preferences.confirmArcSave = false, nil
    checkpointPreferences()
    finishEditing(true)
    keepProfileForReload()
end

local function clickBinding(name, action)
    local button = CreateFrame("Button", "ForeverTouch" .. name, UIParent)
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    button:EnableMouse(false)
    button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    button:SetScript("OnClick", function(self, mouse, down)
        if not down then action(self, mouse) end
    end)
    return button:GetName()
end

-- The graphics CVars apply to this WoW installation, across characters.
local function toggleFrameLimit()
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    local limit = get and tonumber(get("maxFPS"))
    local enabled = get and tonumber(get("useMaxFPS"))
    if not set or not limit or not enabled then
        saveFeedback(german and "FPS-Limit hier nicht verfügbar." or "Frame limit unavailable on this client.")
        return
    end
    local prior = ForeverTouchFrameLimit
    if type(prior) == "table" and type(prior.limit) == "number" and type(prior.enabled) == "number" then
        ForeverTouchFrameLimit = nil
        if limit == prior.applied and enabled == 1 then
            set("maxFPS", prior.limit)
            set("useMaxFPS", prior.enabled)
            saveFeedback(german and "Vorheriges FPS-Limit wiederhergestellt." or "Previous frame limit restored.")
        else
            saveFeedback(german and "Deine manuelle FPS-Einstellung bleibt aktiv." or "Your manual frame limit is active.")
        end
        return
    end
    local target = enabled == 1 and limit > 0 and math.min(30, limit) or 30
    if enabled == 1 and limit == target then
        saveFeedback(string.format(german and "Bereits auf %d FPS begrenzt." or "Already limited to %d FPS.", target))
        return
    end
    set("maxFPS", target)
    set("useMaxFPS", 1)
    if tonumber(get("maxFPS")) == target and tonumber(get("useMaxFPS")) == 1 then
        ForeverTouchFrameLimit = { limit = limit, enabled = enabled, applied = target }
        saveFeedback(string.format(german and "FPS-Limit auf %d gesetzt." or "Frame limit set to %d FPS.", target))
    else
        set("maxFPS", limit)
        set("useMaxFPS", enabled)
        saveFeedback(german and "FPS-Limit konnte nicht gesetzt werden." or "Could not set the frame limit.")
    end
end

local clickBindings = {
    ["CTRL-SHIFT-F"] = clickBinding("FrameLimit", toggleFrameLimit),
    ["CTRL-SHIFT-F7"] = clickBinding("OpenEditor", openEditor),
    ["CTRL-SHIFT-F8"] = clickBinding("OpenChat", Chat.open),
    ["CTRL-SHIFT-M"] = clickBinding("FullscreenChat", function() Chat.setFullscreen(true) end),
    ["CTRL-SHIFT-C"] = clickBinding("CompactChat", function() Chat.setFullscreen(false) end),
    ["CTRL-SHIFT-F1"] = clickBinding("SaveEditor", saveFromToolbar),
    ["CTRL-SHIFT-F2"] = clickBinding("CancelEditor", function()
        if ArcSave then ArcSave.close() end
        finishEditing(false)
    end),
    ["CTRL-SHIFT-HOME"] = clickBinding("ResetEditor", resetEditor),
    ["CTRL-SHIFT-PAGEDOWN"] = clickBinding("GroupFinder", function()
        if ToggleGroupFinderFrame then ToggleGroupFinderFrame() end
    end),
}
if ArcSave then
    clickBindings["CTRL-SHIFT-END"] = clickBinding("AcceptArcSave", acceptToolbarSave)
    clickBindings["CTRL-SHIFT-DELETE"] = clickBinding("CancelArcTransfer", ArcSave.close)
end

local desktopBarNames = {
    "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "MultiBar5", "MultiBar6", "MultiBar7", "MicroMenuContainer", "MicroMenu", "BagsBar",
}
local barAlpha, barMouse, barHooks = {}, {}, {}

local function muteBarMouse(frame)
    if frame:IsForbidden() then return end
    local clicks, motion = frame:IsMouseClickEnabled(), frame:IsMouseMotionEnabled()
    if clicks or motion then
        local state = barMouse[frame] or {}
        state.clicks = state.clicks or clicks
        state.motion = state.motion or motion
        barMouse[frame] = state
        if clicks then frame:SetMouseClickEnabled(false) end
        if motion then frame:SetMouseMotionEnabled(false) end
    end
    for _, child in ipairs({frame:GetChildren()}) do muteBarMouse(child) end
end

local function updateDesktopBars()
    if InCombatLockdown() then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then
        for bar, alpha in pairs(barAlpha) do
            barAlpha[bar] = nil
            bar:SetAlpha(alpha)
        end
        for frame, state in pairs(barMouse) do
            if state.clicks then frame:SetMouseClickEnabled(true) end
            if state.motion then frame:SetMouseMotionEnabled(true) end
        end
        barMouse = {}
        return
    end

    -- Keep the real bars logically active for WoW bindings and page selection, with no invisible tap targets.
    for _, name in ipairs(desktopBarNames) do
        local bar = _G[name]
        if bar and not bar:IsForbidden() then
            if not barHooks[bar] then
                hooksecurefunc(bar, "SetAlpha", function(frame, alpha)
                    if barAlpha[frame] and not isSecret(alpha) and alpha ~= 0 then frame:SetAlpha(0) end
                end)
                bar:HookScript("OnShow", function(frame)
                    C_Timer.After(0, function()
                        if barAlpha[frame] and not InCombatLockdown() then muteBarMouse(frame) end
                    end)
                end)
                barHooks[bar] = true
            end
            if barAlpha[bar] == nil then barAlpha[bar] = bar:GetAlpha() end
            bar:SetAlpha(0)
            muteBarMouse(bar)
        end
    end
end

local trackerHooked
local function limitTrackerHeight(tracker)
    if InCombatLockdown() and tracker:IsProtected() then return end
    local maximum = UIParent:GetHeight() * .137
    if maximum > 0 and tracker:GetHeight() > maximum then tracker:SetHeight(maximum) end
end

local function layoutHUD()
    if InCombatLockdown() then return end
    local height = UIParent:GetHeight()
    updateDesktopBars()
    Chat.layout()

    -- Leave room below quests for the right thumb arc even after WoW refreshes the tracker.
    local tracker = ObjectiveTrackerFrame
    if tracker and tracker.Update then
        if not trackerHooked and tracker.UpdateHeight then
            hooksecurefunc(tracker, "UpdateHeight", limitTrackerHeight)
            trackerHooked = true
        end
        if tracker.SetClipsChildren then tracker:SetClipsChildren(true) end
        tracker:ClearAllPoints()
        tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -height * .055, -height * .266)
        tracker:SetHeight(height * .137)
        tracker:Update()
    end
    layoutActions()
end

refreshSlots = function()
    if not preferences then return end
    if InCombatLockdown() or draft then
        pendingRefresh = true
        return
    end
    pendingRefresh, staleSetBindings = false, false

    desktopKeys, desktopRecords = Actions.desktop()
    defaults = Actions.splitDesktop(desktopKeys, desktopRecords)
    if spellRanksDirty then
        spellRanks = Actions.spellRanks()
        spellRanksDirty = false
    end
    livePages = savedPages(true)
    local activeIndex = pageIndex(preferences.mobileArcPage, #livePages)

    for index, page in ipairs(livePages) do
        local frame = actionPages[index] or createActionPage(index)
        for _, side in ipairs(SIDES) do
            local group, slots = frame.groups[side], page.slots[side]
            for slot, binding in ipairs(slots) do
                local button = group.buttons[slot] or actionButton(group, slot)
                Actions.bind(button, binding, desktopRecords)
                button:Show()
            end
            for slot = #slots + 1, #group.buttons do
                Actions.bind(group.buttons[slot], nil, desktopRecords)
                group.buttons[slot]:Hide()
            end
            group.panel:SetShown(#slots > 0)
        end
    end
    for index, page in ipairs(actionPages) do page.frame:SetShown(index == activeIndex) end
    switcher:SetAttribute("pageCount", #livePages)
    local samePage = switcher:GetAttribute("page") == activeIndex
    switcher:SetAttribute("page", activeIndex)
    if samePage then refreshLiveButtons(true, true) end
    switcher:SetText(setLabel(activeIndex, #livePages))
    switcher:SetShown(#livePages > 1)
    layoutActions()
    return true
end

refreshLiveButtons = function(updateIcon, updateCooldown)
    local index = switcher:GetAttribute("page")
    local page = livePages and livePages[index]
    if not page then return end
    local liveGroups = actionPages[index].groups
    for _, side in ipairs(SIDES) do
        for slot = 1, #page.slots[side] do
            Actions.refresh(liveGroups[side].buttons[slot], desktopRecords, updateIcon, updateCooldown)
        end
    end
end

switcher:HookScript("OnAttributeChanged", function(_, name, index)
    if name ~= "page" or not livePages then return end
    local active = index > 1 and index or nil
    if preferences.mobileArcPage ~= active and not staleSetBindings then
        preferences.mobileArcPage = active
        preferences.revision = preferenceRevision(preferences) + 1
        preferences.arcRevision = preferences.revision
        checkpointPreferences()
        pendingSave = true
    end
    switcher:SetText(setLabel(index, #livePages))
    refreshLiveButtons(true, true)
end)

local function installBindings()
    -- Temporary bindings for the Android toolbar. The player's own bindings stay in place.
    SetOverrideBinding(events, true, "CTRL-SHIFT-F3", "TOGGLECHARACTER0")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F4", "TOGGLETALENTS")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F5", "TOGGLEQUESTLOG")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F6", "TOGGLESPELLBOOK")
    for key, button in pairs(clickBindings) do SetOverrideBindingClick(events, true, key, button) end
    SetOverrideBinding(events, true, "CTRL-SHIFT-F9", "OPENALLBAGS")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F10", "INTERACTTARGET")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F11", "TOGGLEWORLDMAP")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F12", "TARGETNEARESTENEMY")
    SetOverrideBinding(events, true, "CTRL-SHIFT-INSERT", "TOGGLEPROFESSIONBOOK")
    SetOverrideBinding(events, true, "CTRL-SHIFT-END", "TOGGLEFRIENDSTAB")
    SetOverrideBinding(events, true, "CTRL-SHIFT-PAGEUP", "TOGGLEGUILDTAB")
    SetOverrideBinding(events, true, "CTRL-SHIFT-DELETE", "TOGGLECOLLECTIONS")
    SetOverrideBinding(events, false, "W", "MOVEFORWARD")
    SetOverrideBinding(events, false, "S", "MOVEBACKWARD")
    SetOverrideBinding(events, false, "Q", "STRAFELEFT")
    SetOverrideBinding(events, false, "E", "STRAFERIGHT")
    SetOverrideBinding(events, false, "SPACE", "JUMP")
end

local queuedRebind, queuedLive, queuedIcons, queuedTimers = false, false, false, false
local function queueRefresh(rebind, updateIcon, updateCooldown)
    queuedRebind = queuedRebind or rebind
    queuedLive = queuedLive or not rebind
    queuedIcons = queuedIcons or updateIcon
    queuedTimers = queuedTimers or updateCooldown
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        local rebindNow, liveNow, icons, timers = queuedRebind, queuedLive, queuedIcons, queuedTimers
        refreshQueued = false
        queuedRebind, queuedLive, queuedIcons, queuedTimers = false, false, false, false
        if rebindNow and refreshSlots() then return end
        if liveNow then refreshLiveButtons(icons, timers) end
    end)
end

local function loadHudPreferences()
    loadPreferences()
    checkpointPreferences()
    Chat.initialize(preferences, function(expanded, width, height)
        local size = preferences.mobileChatSize
        if preferences.mobileChatOpen == expanded and size
                and size.width == width and size.height == height then return end
        preferences.mobileChatOpen = expanded
        preferences.mobileChatSize = width and height and { width = width, height = height } or nil
        preferences.revision = preferenceRevision(preferences) + 1
        checkpointPreferences()
    end)
end

for _, event in ipairs({
    "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "EDIT_MODE_LAYOUTS_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS",
    "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "BAG_UPDATE_DELAYED",
    "SPELLS_CHANGED", "SPELL_TEXT_UPDATE", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "BAG_UPDATE_COOLDOWN",
}) do
    events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event, spellID)
    if event == "PLAYER_LOGIN" then
        loadHudPreferences()
    elseif event == "PLAYER_LOGOUT" then
        if ArcSave then ArcSave.close() end
        Chat.suspend()
        checkpointPreferences()
        if pendingSave and not reloadRequested then keepProfileForReload() end
        pendingSave, reloadRequested = false, false
        saveRetry:Hide()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not preferences or (not profileKey and not draft) then loadHudPreferences() end
        if confirmSaved then
            confirmSaved = nil
            saveFeedback(german and "Arc-Belegung gespeichert." or "Arc layout saved.")
        elseif retainedAfterReload then
            retainedAfterReload = nil
            saveFeedback(german and "Arc-Belegung übernommen." or "Arc layout restored after reload.")
        end
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingRefresh = true
                return
            end
            installBindings()
            C_Timer.After(0, layoutHUD)
            refreshSlots()
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        saveRetry:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingSave and preferences.confirmArcSave and not draft and not reloadRequested then saveRetry:Show() end
        installBindings()
        layoutHUD()
        if pendingRefresh then queueRefresh(true) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        Chat.updateChannels()
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        layoutHUD()
    elseif event == "SPELLS_CHANGED" or event == "SPELL_TEXT_UPDATE" then
        if event == "SPELLS_CHANGED" or (spellRanks and not isSecret(spellID) and spellRanks.pending[spellID]) then
            spellRanksDirty = true
            if preferences then queueRefresh(true) end
        end
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "UPDATE_CHAT_WINDOWS" or event == "UPDATE_FLOATING_CHAT_WINDOWS" then
        Chat.queueLayout()
    elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE" then
        queueRefresh(false, false, false)
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "BAG_UPDATE_DELAYED" or event == "SPELL_UPDATE_COOLDOWN"
            or event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
        queueRefresh(false, false, true)
    elseif event == "ACTIONBAR_SLOT_CHANGED" and InCombatLockdown() then
        pendingRefresh = true
        queueRefresh(false, true, true)
    elseif preferences then
        queueRefresh(true)
    end
end)

if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        Chat.suspend()
        C_Timer.After(0, updateDesktopBars)
    end, events)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        Chat.resume()
        C_Timer.After(0, layoutHUD)
    end, events)
end
