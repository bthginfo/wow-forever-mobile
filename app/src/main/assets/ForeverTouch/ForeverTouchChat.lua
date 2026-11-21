local _, addon = ...
local Chat = {}
addon.chat = Chat

local german = addon.german
local isSecret = issecretvalue or function() return false end
local expanded, enabled, layoutQueued = false, false, false
local onToggle, primaryLayout, inputLayout
local docked = {}

-- A hidden parent leaves WoW's chat windows logically shown and receiving messages.
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetAllPoints(UIParent)
panel:Hide()

local toggle = CreateFrame("Button", "ForeverTouchChatToggle", UIParent, "UIPanelButtonTemplate")
toggle:SetFrameStrata("HIGH")
toggle:RegisterForClicks("LeftButtonUp")
toggle:Hide()
local unread = toggle:CreateTexture("ForeverTouchUnreadWhisper", "OVERLAY")
unread:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
unread:SetVertexColor(1, .19, .20, 1)
unread:Hide()

local controls = CreateFrame("Frame", nil, UIParent)
controls:SetFrameStrata("DIALOG")
controls:Hide()

local function canMove(frame)
    return frame and not frame:IsForbidden() and not (InCombatLockdown() and frame:IsProtected())
end

local function captureLayout(frame)
    local points = {}
    for index = 1, frame:GetNumPoints() do points[index] = {frame:GetPoint(index)} end
    return {frame = frame, points = points, width = frame:GetWidth(), height = frame:GetHeight()}
end

local function restoreLayout(layout)
    if not layout then return end
    local frame = layout.frame
    if not canMove(frame) then return layout end
    frame:ClearAllPoints()
    for _, point in ipairs(layout.points) do frame:SetPoint(unpack(point, 1, 5)) end
    frame:SetSize(layout.width, layout.height)
end

local function setParent(frame, parent)
    if FrameUtil and FrameUtil.SetParentMaintainRenderLayering then
        FrameUtil.SetParentMaintainRenderLayering(frame, parent)
    else
        frame:SetParent(parent)
    end
end

local function syncDock(primary)
    local wanted = {}
    if primary then
        wanted[primary] = true
        local dock = GENERAL_CHAT_DOCK
        if dock then
            wanted[dock] = true
            local windows = FCFDock_GetChatFrames and FCFDock_GetChatFrames(dock)
            for _, window in ipairs(windows or {}) do wanted[window] = true end
        end
    end
    for frame in pairs(docked) do
        if not wanted[frame] then
            if frame:GetParent() ~= panel then
                docked[frame] = nil
            elseif canMove(frame) then
                setParent(frame, UIParent)
                docked[frame] = nil
            end
        end
    end
    for frame in pairs(wanted) do
        -- A protected child would make toggling its parent during combat unsafe.
        if canMove(frame) and not frame:IsProtected() and frame:GetParent() == UIParent then
            setParent(frame, panel)
            docked[frame] = true
        end
    end
end

local function rightInset(width, height)
    local map = MinimapCluster
    if map and not map:IsForbidden() then
        local left = map:GetLeft()
        if left then
            left = left * map:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local screenLeft = UIParent:GetLeft() or 0
            -- Follow the left edge of a minimap positioned on the right side.
            if left - screenLeft > width * .52 then
                return (UIParent:GetRight() or screenLeft + width) - left + height * .02
            end
        end
    end
    return math.min(width * .30, height * .36)
end

local function place(frame, right, top, width, height)
    if frame:GetNumPoints() == 1 then
        local point, relative, relativePoint, x, y = frame:GetPoint()
        if point == "TOPRIGHT" and relative == UIParent and relativePoint == "TOPRIGHT"
                and math.abs((x or 0) + right) < .1 and math.abs((y or 0) + top) < .1
                and math.abs(frame:GetWidth() - width) < .1 and math.abs(frame:GetHeight() - height) < .1 then return end
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -right, -top)
    frame:SetSize(width, height)
end

local buttons = {}
local function control(label, weight, action)
    local button = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
    button:SetText(label)
    button:SetScript("OnClick", function()
        if inputLayout then action(inputLayout.frame) end
    end)
    buttons[#buttons + 1] = {button = button, weight = weight}
    return button
end

local function chooseChannel(entry, chatType)
    entry:SetChatType(chatType)
    entry:UpdateHeader()
end

control(german and "Sagen" or "Say", .17, function(entry) chooseChannel(entry, "SAY") end)
local group = control(german and "Gruppe" or "Group", .20, function(entry)
    local chatType = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or (IsInRaid() and "RAID" or "PARTY")
    chooseChannel(entry, chatType)
end)
local guild = control(german and "Gilde" or "Guild", .17, function(entry) chooseChannel(entry, "GUILD") end)
control(german and "Neueste" or "Latest", .22, function(entry)
    local frame = entry.chatFrame or DEFAULT_CHAT_FRAME
    if frame and frame.ScrollToBottom then frame:ScrollToBottom() end
end)
control("↑", .12, function(entry) if entry.chatFrame then entry.chatFrame:PageUp() end end)
control("↓", .12, function(entry) if entry.chatFrame then entry.chatFrame:PageDown() end end)

function Chat.updateChannels()
    if not inputLayout then return end
    group:SetEnabled(IsInGroup())
    guild:SetEnabled(IsInGuild())
end

function Chat.layout()
    if not enabled or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then return end
    local width, height = UIParent:GetSize()
    if width <= 0 or height <= 0 then return end
    local right = rightInset(width, height)
    local chatWidth = math.min(height * .70, width * .38, width * .74 - right)
    if chatWidth <= 0 then return end

    local primary = DEFAULT_CHAT_FRAME
    if canMove(primary) then
        primaryLayout = primaryLayout or captureLayout(primary)
        place(primary, right, height * .245, chatWidth, height * .155)
    end
    syncDock(primary)

    place(toggle, right, height * .139, height * .153, height * .062)
    unread:SetSize(height * .016, height * .016)
    unread:ClearAllPoints()
    unread:SetPoint("RIGHT", toggle, "RIGHT", -height * .011, 0)
    toggle:SetText(expanded and "Chat ▾" or "Chat ▸")
    toggle:SetShown(not inputLayout)
    panel:SetShown(expanded or inputLayout ~= nil)

    if not inputLayout then return end
    local entry = inputLayout.frame
    if canMove(entry) then place(entry, right, height * .147, chatWidth, inputLayout.height) end
    local buttonHeight, gap = height * .061, height * .005
    place(controls, right, height * .415, chatWidth, buttonHeight)
    local x, available = 0, chatWidth - gap * (#buttons - 1)
    for _, item in ipairs(buttons) do
        local buttonWidth = available * item.weight
        item.button:ClearAllPoints()
        item.button:SetPoint("TOPLEFT", controls, "TOPLEFT", x, 0)
        item.button:SetSize(buttonWidth, buttonHeight)
        x = x + buttonWidth + gap
    end
    Chat.updateChannels()
    controls:Show()
end

function Chat.queueLayout()
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        Chat.layout()
    end)
end

function Chat.initialize(savedOpen, callback)
    expanded, onToggle, enabled = savedOpen == true, callback, true
end

function Chat.resume()
    enabled = true
end

function Chat.suspend()
    enabled = false
    toggle:Hide()
    controls:Hide()
    inputLayout = restoreLayout(inputLayout)
    primaryLayout = restoreLayout(primaryLayout)
    syncDock(nil)
    panel:Hide()
end

function Chat.whisper()
    if not expanded and not inputLayout then unread:Show() end
    -- A whisper may create a new native docked conversation tab.
    Chat.queueLayout()
end

local function fadeChatIn()
    local dock = GENERAL_CHAT_DOCK
    local frame = dock and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(dock) or DEFAULT_CHAT_FRAME
    if frame and FCF_FadeInChatFrame then FCF_FadeInChatFrame(frame) end
end

local function openAlertingConversation()
    local dock = GENERAL_CHAT_DOCK
    if not dock or not FCFDock_GetChatFrames or not FCF_SelectDockFrame
            or not ChatFrameUtil or not ChatFrameUtil.IsTabAlerting then return end
    for _, frame in ipairs(FCFDock_GetChatFrames(dock)) do
        local kind = frame.chatType
        if not isSecret(kind) and (kind == "WHISPER" or kind == "BN_WHISPER") then
            local tab = _G[frame:GetName() .. "Tab"]
            if tab and ChatFrameUtil.IsTabAlerting(tab) then
                FCF_SelectDockFrame(frame)
                return
            end
        end
    end
end

toggle:SetScript("OnClick", function()
    if not enabled then return end
    expanded = not expanded
    if onToggle then onToggle(expanded) end
    Chat.layout()
    if expanded then
        if unread:IsShown() then openAlertingConversation() end
        unread:Hide()
        fadeChatIn()
    end
end)

function Chat.open()
    if not enabled then return end
    -- The real edit box can be a child of the collapsed chat panel.
    panel:Show()
    local getActive = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    local entry = getActive and getActive()
    if (not entry or not entry:HasFocus()) and open then
        entry = open("", DEFAULT_CHAT_FRAME) or (getActive and getActive())
    end
    if not entry or not entry:HasFocus() then
        Chat.layout()
        return
    end
    if not inputLayout or inputLayout.frame ~= entry then
        inputLayout = restoreLayout(inputLayout) or captureLayout(entry)
    end
    if not entry.foreverTouchFocusHook then
        entry.foreverTouchFocusHook = true
        entry:HookScript("OnEditFocusLost", function(self)
            if not inputLayout or inputLayout.frame ~= self then return end
            inputLayout = restoreLayout(inputLayout)
            controls:Hide()
            Chat.layout()
        end)
    end
    unread:Hide()
    Chat.layout()
    fadeChatIn()
end
