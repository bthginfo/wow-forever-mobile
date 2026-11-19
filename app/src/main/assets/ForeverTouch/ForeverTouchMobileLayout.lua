local _, addon = ...
local Actions = addon.actions
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
local activeEditBox

local groups = {}
for _, side in ipairs(SIDES) do
    local panel = CreateFrame("Frame", side == "left" and "ForeverTouchLeft" or "ForeverTouchRight", UIParent)
    panel:SetClampedToScreen(true)
    panel:Hide()
    local editor = CreateFrame("Frame", nil, editShield)
    editor:SetMovable(true)
    editor:SetClampedToScreen(true)
    groups[side] = { side = side, panel = panel, editor = editor, buttons = {}, previews = {} }
end

local live, defaults, desktopRecords, preferences
local draft, selected, dragFrom, moving
local refreshSlots, updateEditor
local pendingRefresh, refreshQueued = false, false

local function preferenceRevision(profile)
    if type(profile) ~= "table" or not next(profile) then return -1 end
    return type(profile.revision) == "number" and profile.revision or 0
end

local function loadPreferences()
    local character = UnitGUID("player")
    if type(ForeverTouchProfiles) ~= "table" then ForeverTouchProfiles = {} end
    local profiles = ForeverTouchProfiles
    local key = not isSecret(character) and type(character) == "string" and character ~= "" and character or nil
    local primary, backup = ForeverTouchPreferences, key and profiles[key]

    -- Keep the legacy character file and a second copy scoped to the same character.
    if preferenceRevision(backup) > preferenceRevision(primary) then primary = backup end
    preferences = type(primary) == "table" and primary or {}
    ForeverTouchPreferences = preferences
    if key then profiles[key] = preferences end
end

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
    local name = (group.side == "left" and "ForeverTouchLeftAction" or "ForeverTouchRightAction") .. index
    local button = CreateFrame("Button", name, group.panel, "SecureActionButtonTemplate")
    button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("LeftButtonUp")
    makeSkillArt(button)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:EnableMouse(false)
    button.cooldown:SetSwipeTexture(CIRCLE)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
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

local function layoutActions()
    if not live or moving then return end
    local width, height = UIParent:GetSize()
    if width <= 0 or height <= 0 then return end
    local scale = height / DESIGN_HEIGHT
    local viewport = width / scale
    local profile = draft and draft.slots or live
    local positions = draft and draft.positions or preferences.mobileArcPositions
    for _, side in ipairs(SIDES) do
        local group = groups[side]
        local arcWidth, arcHeight, points = arcGeometry(#profile[side], viewport, side == "right")
        local parent, buttons = nil, nil
        if draft then
            parent, buttons = group.editor, group.previews
        elseif not InCombatLockdown() then
            parent, buttons = group.panel, group.buttons
        end
        if parent then
            local position = type(positions) == "table" and positions[side]
            placeArc(parent, side, scale, arcWidth, arcHeight, viewport, position)
            for index, point in ipairs(points) do
                local button = buttons[index]
                button:SetSize(point.size, point.size)
                button:ClearAllPoints()
                button:SetPoint("CENTER", parent, "BOTTOMLEFT", point.x, point.y)
            end
        end
    end
end

local function swapSlots(first, second)
    local from, to = draft.slots[first.mobileSide], draft.slots[second.mobileSide]
    local a, b = first.mobileIndex, second.mobileIndex
    from[a], to[b] = to[b], from[a]
    draft.changed = true
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
        for _, side in ipairs(SIDES) do
            for target = 1, #draft.slots[side] do
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
    local list = draft.slots[side]
    local old = list[index]
    picker:Open(function(binding)
        if not draft then return end
        list[index] = binding
        draft.changed = true
        selected = nil
        updateEditor()
    end, old and (old.kind == "item" and "item" or "spell"))
end

local tools = CreateFrame("Frame", nil, editShield)
tools:SetPoint("TOP", UIParent, "TOP", 0, -93)
tools:SetSize(280, 63)
local selection = tools:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
selection:SetPoint("TOP", 0, 2)
selection:SetWidth(280)

local assign = CreateFrame("Button", nil, tools, "UIPanelButtonTemplate")
assign:SetSize(129, 37)
assign:SetPoint("BOTTOMLEFT", 4, 0)
assign:SetText(german and "Belegen" or "Assign")
assign:SetScript("OnClick", function()
    if selected then chooseBinding(selected.mobileSide, selected.mobileIndex) end
end)

local remove = CreateFrame("Button", nil, tools, "UIPanelButtonTemplate")
remove:SetSize(129, 37)
remove:SetPoint("BOTTOMRIGHT", -4, 0)
remove:SetText(german and "Entfernen" or "Remove")
remove:SetScript("OnClick", function()
    if not draft or not selected or picker:IsShown() then return end
    table.remove(draft.slots[selected.mobileSide], selected.mobileIndex)
    draft.changed = true
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
            draft.positions[group.side] = {
                x = normalizedCoordinate(left - (UIParent:GetLeft() or 0) / scale, travelX),
                y = normalizedCoordinate(bottom - (UIParent:GetBottom() or 0) / scale, travelY),
            }
            draft.moved = true
        end
        layoutActions()
    end)

    local add = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    add:SetPoint("LEFT", move, "RIGHT", 4, 0)
    add:SetSize(40, HANDLE_HEIGHT)
    add:SetText("+")
    add:SetClampedToScreen(true)
    add:SetScript("OnClick", function()
        if draft then chooseBinding(group.side, #draft.slots[group.side] + 1) end
    end)
    group.add = add
end

updateEditor = function()
    if not draft then return end
    local mayAdd = #draft.slots.left + #draft.slots.right < Actions.limit
    for _, side in ipairs(SIDES) do
        local group, slots = groups[side], draft.slots[side]
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
    local binding = selected and draft.slots[selected.mobileSide][selected.mobileIndex]
    selection:SetText(binding and (Actions.name(binding, desktopRecords) or "Slot")
        or (german and "Wähle einen Slot oder tippe auf +" or "Select a slot or tap +"))
    assign:SetEnabled(binding ~= nil)
    remove:SetEnabled(binding ~= nil)
    tools:SetScale(UIParent:GetHeight() / DESIGN_HEIGHT)
    layoutActions()
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

local function stopMoving()
    if not moving then return end
    moving.editor:StopMovingOrSizing()
    moving.editor:SetUserPlaced(false)
    moving = nil
end

local function openEditor()
    if draft or not live then return end
    draft = {
        slots = Actions.copyProfile(live),
        positions = copyPositions(preferences.mobileArcPositions),
    }
    for _, side in ipairs(SIDES) do groups[side].panel:SetAlpha(0) end
    updateEditor()
    editShield:Show()
end

local function resetEditor()
    if not draft then return end
    stopMoving()
    picker:Hide()
    draft.slots = Actions.copyProfile(defaults)
    draft.positions = {}
    draft.changed, draft.reset = false, true
    selected, dragFrom = nil, nil
    updateEditor()
end

local function finishEditing(save)
    if not draft then return end
    stopMoving()
    local changed = save and (draft.changed or draft.reset or draft.moved)
    if changed then
        preferences.mobileArcPositions = draft.positions
        if draft.reset then
            preferences.mobileSlots, preferences.order, preferences.favorites = nil, nil, nil
        end
        if draft.changed then
            preferences.mobileSlots = Actions.independentProfile(draft.slots, desktopRecords)
        end
        preferences.revision = preferenceRevision(preferences) + 1
    end
    picker:Hide()
    draft, selected, dragFrom = nil, nil, nil
    editShield:Hide()
    for _, side in ipairs(SIDES) do groups[side].panel:SetAlpha(1) end
    refreshSlots()
    if changed and not InCombatLockdown() then
        -- WoW writes SavedVariables on reload. Call from the Save click so the client can flush immediately.
        local reload = C_UI and C_UI.Reload or ReloadUI
        if reload then reload() end
    end
end

local function editorBinding(name, action)
    local button = CreateFrame("Button", "ForeverTouch" .. name, UIParent)
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    button:EnableMouse(false)
    button:SetScript("OnClick", action)
    return button:GetName()
end

local editorBindings = {
    ["CTRL-SHIFT-F7"] = editorBinding("OpenEditor", openEditor),
    ["CTRL-SHIFT-F1"] = editorBinding("SaveEditor", function() finishEditing(true) end),
    ["CTRL-SHIFT-F2"] = editorBinding("CancelEditor", function() finishEditing(false) end),
    ["CTRL-SHIFT-HOME"] = editorBinding("ResetEditor", resetEditor),
}

local function dockChat(composing)
    local primary = DEFAULT_CHAT_FRAME
    if not primary or (InCombatLockdown() and primary:IsProtected()) then return end
    local height = UIParent:GetHeight()
    primary:ClearAllPoints()
    if composing then
        primary:SetPoint("TOPLEFT", UIParent, "TOPLEFT", height * .075, -height * .225)
        primary:SetSize(height * .82, height * .155)
    else
        primary:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", height * .075, height * .573)
        primary:SetSize(height * .61, height * .155)
    end
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
    dockChat(activeEditBox ~= nil)

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

local chatControls = CreateFrame("Frame", nil, UIParent)
chatControls:SetFrameStrata("DIALOG")
chatControls:SetSize(1, 1)
chatControls:Hide()

local function chatControl(text, x, y, width, action)
    local button = CreateFrame("Button", nil, chatControls, "UIPanelButtonTemplate")
    button:SetSize(width, 49)
    button:SetPoint("TOPLEFT", chatControls, "TOPLEFT", x, -y)
    button:SetText(text)
    button:SetScript("OnClick", function()
        if activeEditBox then action(activeEditBox) end
    end)
    return button
end

local function chooseChatType(editBox, chatType)
    editBox:SetChatType(chatType)
    editBox:UpdateHeader()
end

chatControl(german and "Sagen" or "Say", 0, 129, 91, function(editBox) chooseChatType(editBox, "SAY") end)
local groupChat = chatControl(german and "Gruppe" or "Group", 99, 129, 98, function(editBox)
    local chatType = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or (IsInRaid() and "RAID" or "PARTY")
    chooseChatType(editBox, chatType)
end)
local guildChat = chatControl(german and "Gilde" or "Guild", 205, 129, 94, function(editBox) chooseChatType(editBox, "GUILD") end)
chatControl("↑", 599, 4, 58, function(editBox) editBox.chatFrame:PageUp() end)
chatControl("↓", 599, 56, 58, function(editBox) editBox.chatFrame:PageDown() end)

local chatButton = CreateFrame("Button", "ForeverTouchOpenChat", UIParent)
chatButton:SetSize(1, 1)
chatButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
chatButton:EnableMouse(false)
chatButton:SetScript("OnClick", function()
    if not ChatFrameUtil or not ChatFrameUtil.OpenChat then
        if ChatFrame_OpenChat then ChatFrame_OpenChat("") end
        return
    end
    local editBox = ChatFrameUtil.GetActiveWindow()
    if not editBox or not editBox:HasFocus() then
        editBox = ChatFrameUtil.OpenChat(nil, DEFAULT_CHAT_FRAME)
    end
    if not editBox or not editBox:HasFocus() then return end
    activeEditBox = editBox

    -- Put the real WoW edit box above the landscape Android keyboard without losing its channel or history.
    if not editBox.foreverTouchOriginalPoints then
        local points = {}
        for index = 1, editBox:GetNumPoints() do points[index] = { editBox:GetPoint(index) } end
        editBox.foreverTouchOriginalPoints = points
        editBox.foreverTouchOriginalWidth = editBox:GetWidth()
    end
    if not editBox.foreverTouchHooks then
        editBox.foreverTouchHooks = true
        editBox:HookScript("OnEditFocusLost", function(self)
            if not self.foreverTouchOriginalPoints then return end
            self:ClearAllPoints()
            self:SetWidth(self.foreverTouchOriginalWidth)
            for _, point in ipairs(self.foreverTouchOriginalPoints) do self:SetPoint(unpack(point)) end
            self.foreverTouchOriginalPoints = nil
            activeEditBox = nil
            chatControls:Hide()
            dockChat(false)
        end)
    end
    local height = UIParent:GetHeight()
    dockChat(true)
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", UIParent, "TOPLEFT", height * .075, -height * .147)
    editBox:SetWidth(height * .93)
    if FCF_FadeInChatFrame then FCF_FadeInChatFrame(editBox.chatFrame) end
    chatControls:SetScale(height / DESIGN_HEIGHT)
    chatControls:ClearAllPoints()
    chatControls:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 54, -162)
    groupChat:SetEnabled(IsInGroup())
    guildChat:SetEnabled(IsInGuild())
    chatControls:Show()
end)

refreshSlots = function()
    if not preferences then return end
    if InCombatLockdown() or draft then
        pendingRefresh = true
        return
    end
    pendingRefresh = false

    local keys
    keys, desktopRecords = Actions.desktop()
    defaults = Actions.splitDesktop(keys, desktopRecords)
    if type(preferences.mobileSlots) == "table" then
        live = Actions.copyProfile(preferences.mobileSlots)
    elseif preferences.order or preferences.favorites then
        live = Actions.splitDesktop(keys, desktopRecords, preferences.order or preferences.favorites)
    else
        live = defaults
    end

    for _, side in ipairs(SIDES) do
        local group, slots = groups[side], live[side]
        for index, binding in ipairs(slots) do
            local button = group.buttons[index] or actionButton(group, index)
            Actions.bind(button, binding, desktopRecords)
            Actions.refresh(button, desktopRecords, true)
            button:Show()
        end
        for index = #slots + 1, #group.buttons do
            Actions.bind(group.buttons[index], nil, desktopRecords)
            group.buttons[index]:Hide()
        end
        group.panel:SetShown(#slots > 0)
    end
    layoutActions()
end

local function refreshLiveButtons(updateIcon)
    if not live then return end
    for _, side in ipairs(SIDES) do
        for index = 1, #live[side] do Actions.refresh(groups[side].buttons[index], desktopRecords, updateIcon) end
    end
end

local function installBindings()
    -- Temporary bindings for the Android toolbar. The player's own bindings stay in place.
    SetOverrideBinding(events, true, "CTRL-SHIFT-F3", "TOGGLECHARACTER0")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F4", "TOGGLETALENTS")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F5", "TOGGLEQUESTLOG")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F6", "TOGGLESPELLBOOK")
    for key, button in pairs(editorBindings) do SetOverrideBindingClick(events, true, key, button) end
    SetOverrideBindingClick(events, true, "CTRL-SHIFT-F8", chatButton:GetName())
    SetOverrideBinding(events, true, "CTRL-SHIFT-F9", "OPENALLBAGS")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F10", "INTERACTTARGET")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F11", "TOGGLEWORLDMAP")
    SetOverrideBinding(events, true, "CTRL-SHIFT-F12", "TARGETNEARESTENEMY")
    SetOverrideBinding(events, false, "W", "MOVEFORWARD")
    SetOverrideBinding(events, false, "S", "MOVEBACKWARD")
    SetOverrideBinding(events, false, "Q", "STRAFELEFT")
    SetOverrideBinding(events, false, "E", "STRAFERIGHT")
    SetOverrideBinding(events, false, "SPACE", "JUMP")
end

local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        refreshSlots()
    end)
end

for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_REGEN_ENABLED",
    "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "BAG_UPDATE_DELAYED",
    "SPELLS_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "BAG_UPDATE_COOLDOWN",
}) do
    events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        loadPreferences()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not preferences then loadPreferences() end
        C_Timer.After(0, function()
            if InCombatLockdown() then
                pendingRefresh = true
                return
            end
            installBindings()
            C_Timer.After(0, layoutHUD)
            refreshSlots()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        installBindings()
        layoutHUD()
        if pendingRefresh then queueRefresh() end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        layoutHUD()
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_USABLE" or event == "BAG_UPDATE_DELAYED"
            or event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "SPELL_UPDATE_USABLE"
            or event == "BAG_UPDATE_COOLDOWN" then
        refreshLiveButtons(false)
    elseif event == "ACTIONBAR_SLOT_CHANGED" and InCombatLockdown() then
        pendingRefresh = true
        refreshLiveButtons(true)
    elseif preferences then
        queueRefresh()
    end
end)

if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", function() C_Timer.After(0, updateDesktopBars) end, events)
    EventRegistry:RegisterCallback("EditMode.Exit", function() C_Timer.After(0, layoutHUD) end, events)
end
