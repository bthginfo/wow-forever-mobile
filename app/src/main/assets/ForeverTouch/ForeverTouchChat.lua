local _, addon = ...
local Chat = {}
addon.chat = Chat

local history = addon.chatHistory
local german = addon.german
local isSecret = issecretvalue or function() return false end
local function text(en, de) return german and de or en end
local managedKeyboard = C_AddOns and C_AddOns.GetAddOnMetadata
    and C_AddOns.GetAddOnMetadata("ForeverTouch", "X-ForeverTouch-Keyboard") == "native"
local tabs = {
    { "ALL", text("All", "Alle") },
    { "WHISPER", text("Whispers", "Flüstern") },
    { "PARTY", text("Group", "Gruppe") },
    { "RAID", text("Raid", "Schlachtzug") },
    { "GUILD", text("Guild", "Gilde") },
    { "FRIENDS", text("Friends", "Freunde") },
}
local labels = {}
for _, tab in ipairs(tabs) do labels[tab[1]] = tab[2] end
local enabled, expanded, fullscreen, layoutQueued = false, false, false, false
local onChange, widthRatio, heightRatio
local category, peer, contactPage = "ALL", nil, 1
local friends, friendsByKey = {}, {}
local docked, hooked = {}, {}
local nativeChat
local stockChat = false
local input, sizing
local controlHeight, contactWidth
local refresh, layoutContacts
local function isPrivateChat() return category == "WHISPER" or category == "FRIENDS" end
local function activeThread() return peer and (history.peers[peer] or friendsByKey[peer]) end

-- Keep WoW collecting messages for its own chat. Restoring the parent brings
-- back exactly the native layout, including any changes made in Edit Mode.
local parked = CreateFrame("Frame", nil, UIParent)
parked:Hide()

local panel = CreateFrame("Frame", "ForeverTouchChatPanel", UIParent)
panel:SetFrameStrata("HIGH")
panel:EnableMouse(true)
panel:SetResizable(true)
panel:Hide()

local function paint(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local dimmer = CreateFrame("Frame", nil, UIParent)
dimmer:SetAllPoints(UIParent)
dimmer:SetFrameStrata("FULLSCREEN")
dimmer:EnableMouse(true)
paint(dimmer, "BACKGROUND", .016, .024, .038, .76)
dimmer:Hide()

local cornerFile = "Interface\\AddOns\\ForeverTouch\\ChatCorner.tga"
local function roundFill(frame, layer, radius)
    local corners, bands = {}, {}
    for _, point in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
        local flipX, flipY = point:find("RIGHT") ~= nil, point:find("BOTTOM") ~= nil
        local corner = frame:CreateTexture(nil, layer)
        corner:SetTexture(cornerFile)
        corner:SetTexCoord(flipX and 1 or 0, flipX and 0 or 1, flipY and 1 or 0, flipY and 0 or 1)
        corner:SetPoint(point)
        corner:SetSize(radius, radius)
        corners[#corners + 1] = corner
    end
    for _, point in ipairs({"TOP", "BOTTOM"}) do
        local band = frame:CreateTexture(nil, layer)
        band:SetPoint(point .. "LEFT", radius, 0)
        band:SetPoint(point .. "RIGHT", -radius, 0)
        band:SetHeight(radius)
        bands[#bands + 1] = band
    end
    local center = frame:CreateTexture(nil, layer)
    center:SetPoint("TOPLEFT", 0, -radius)
    center:SetPoint("BOTTOMRIGHT", 0, radius)
    bands[#bands + 1] = center
    return { SetColorTexture = function(_, r, g, b, a)
        for _, corner in ipairs(corners) do corner:SetVertexColor(r, g, b, a) end
        for _, band in ipairs(bands) do band:SetColorTexture(r, g, b, a) end
    end }
end
panel.fill = roundFill(panel, "BACKGROUND", 15)

local function label(parent, anchor, font)
    local fontString = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fontString:SetJustifyH(anchor or "LEFT")
    fontString:SetWordWrap(false)
    fontString:SetTextColor(.92, .95, 1)
    fontString:SetShadowColor(0, 0, 0, .92)
    fontString:SetShadowOffset(1, -1)
    return fontString
end

local function button(parent, name, caption, action)
    local control = CreateFrame("Button", name, parent)
    control:RegisterForClicks("LeftButtonUp")
    control.fill = roundFill(control, "BACKGROUND", 7)
    control.fill:SetColorTexture(.10, .13, .19, .78)
    control.highlight = roundFill(control, "HIGHLIGHT", 7)
    control.highlight:SetColorTexture(.70, .81, 1, .16)
    control.caption = label(control, "CENTER")
    control.caption:SetPoint("TOPLEFT", 4, 0)
    control.caption:SetPoint("BOTTOMRIGHT", -4, 0)
    control.caption:SetText(caption)
    control:SetScript("OnClick", action)
    return control
end

local function icon(buttonFrame, segments, offsetX)
    local drawing = CreateFrame("Frame", nil, buttonFrame)
    drawing:SetSize(18, 18)
    drawing:SetPoint("CENTER", offsetX or 0, 0)
    for _, segment in ipairs(segments) do
        local x1, y1, x2, y2 = unpack(segment)
        local line = drawing:CreateLine(nil, "OVERLAY")
        line:SetColorTexture(.9, .95, 1, .94)
        line:SetThickness(1.6)
        line:SetStartPoint("CENTER", drawing, x1, y1)
        line:SetEndPoint("CENTER", drawing, x2, y2)
    end
    return drawing
end
local chevronDown = {{-4, 2, 0, -2}, {0, -2, 4, 2}}
local chevronUp = {{-4, -2, 0, 2}, {0, 2, 4, -2}}
local chevronLeft = {{2, 4, -2, 0}, {-2, 0, 2, -4}}
local chevronRight = {{-2, 4, 2, 0}, {2, 0, -2, -4}}
local expandCorners = {
    {-6, 1, -6, 6}, {-6, 6, -1, 6}, {1, 6, 6, 6}, {6, 6, 6, 1},
    {-6, -1, -6, -6}, {-6, -6, -1, -6}, {1, -6, 6, -6}, {6, -6, 6, -1},
}
local closeCross = {{-4, 4, 4, -4}, {-4, -4, 4, 4}}

local toggle = button(UIParent, "ForeverTouchChatToggle", "Chat", function()
    if input then return end
    if stockChat then
        stockChat = false
        Chat.layout()
        refresh()
        return
    end
    expanded = not expanded
    if not expanded then category, peer, contactPage = "ALL", nil, 1 end
    if expanded then
        if history.restrictedUnread then category, peer, contactPage = "WHISPER", nil, 1 end
        for _, thread in ipairs(history.contacts) do
            if thread.unread > 0 then
                category, peer, contactPage = "WHISPER", thread.key, 1
                break
            end
        end
    end
    onChange(expanded, widthRatio, heightRatio)
    Chat.layout()
    refresh()
end)
toggle:SetFrameStrata("HIGH")
toggle.fill:SetColorTexture(.07, .11, .17, .63)
toggle.caption:SetJustifyH("LEFT")
toggle.caption:SetPoint("TOPLEFT", 10, 0)
toggle.caption:SetPoint("BOTTOMRIGHT", -30, 0)
local toggleArrow = icon(toggle, chevronDown)
toggleArrow:ClearAllPoints()
toggleArrow:SetPoint("RIGHT", -4, 0)
toggle:Hide()
local unread = toggle:CreateTexture("ForeverTouchUnreadWhisper", "OVERLAY")
unread:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
unread:SetVertexColor(1, .26, .32)
unread:SetPoint("RIGHT", -22, 0)
unread:SetSize(9, 9)
unread:Hide()

local header = CreateFrame("Frame", nil, panel)
local title = label(header, "LEFT", "GameFontHighlightLarge")
local back = button(header, "ForeverTouchChatBack", text("All", "Alle"), function()
    if input then return end
    category, peer, contactPage = "ALL", nil, 1
    Chat.layout()
    refresh()
end)
local expand = button(header, "ForeverTouchChatExpand", "", function() Chat.setFullscreen(not fullscreen) end)
local expandIcon, closeIcon = icon(expand, expandCorners), icon(expand, closeCross)
local write = button(header, "ForeverTouchChatWrite", text("Message…", "Nachricht…"), function() Chat.open() end)
local stock = button(header, "ForeverTouchChatStock", text("WoW chat", "WoW-Chat"), function()
    if input then return end
    stockChat, history.restrictedUnread = true, false
    Chat.layout()
    refresh()
end)

local tabsBar = CreateFrame("Frame", nil, panel)
tabsBar.fill = roundFill(tabsBar, "BACKGROUND", 8)
tabsBar.fill:SetColorTexture(.09, .12, .18, .97)
for _, tab in ipairs(tabs) do
    local key = tab[1]
    tab.button = button(tabsBar, "ForeverTouchChatTab" .. key, tab[2], function()
        if input then return end
        category, peer, contactPage = key, nil, 1
        if key == "FRIENDS" then
            if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
            Chat.updateFriends()
        end
        Chat.layout()
        refresh()
    end)
end

local contacts = CreateFrame("Frame", nil, panel)
contacts.fill = roundFill(contacts, "BACKGROUND", 10)
contacts.fill:SetColorTexture(.069, .092, .145, .92)
local sidebarTitle = label(contacts, "LEFT", "GameFontNormalSmall")
local rows = {}
for index = 1, 10 do
    local row = button(contacts, "ForeverTouchChatContact" .. index, "", function(self)
        if self.contact and not input then
            peer = self.contact.key
            refresh()
        end
    end)
    row.caption:SetJustifyH("LEFT")
    row.caption:ClearAllPoints()
    row.caption:SetPoint("TOPLEFT", 32, -4)
    row.caption:SetPoint("BOTTOMRIGHT", -36, 18)
    row.preview = label(row, "LEFT", "GameFontDisableSmall")
    row.preview:SetPoint("TOPLEFT", 32, -23)
    row.preview:SetPoint("BOTTOMRIGHT", -11, 2)
    row.badge = label(row, "RIGHT", "GameFontNormalSmall")
    row.badge:SetPoint("RIGHT", -10, 6)
    row.badge:SetTextColor(1, .52, .57)
    local avatar = CreateFrame("Frame", nil, row)
    avatar:SetSize(18, 18)
    avatar:SetPoint("LEFT", 7, 0)
    row.indicator = roundFill(avatar, "OVERLAY", 9)
    rows[index] = row
end
local previous = button(contacts, "ForeverTouchChatContactsPrev", "", function()
    contactPage = math.max(1, contactPage - 1)
    layoutContacts()
end)
local nextPage = button(contacts, "ForeverTouchChatContactsNext", "", function()
    contactPage = contactPage + 1
    layoutContacts()
end)
icon(previous, chevronLeft)
icon(nextPage, chevronRight)

local transcript = CreateFrame("ScrollingMessageFrame", "ForeverTouchChatTranscript", panel)
transcript:SetFontObject(GameFontHighlight)
transcript:SetJustifyH("LEFT")
transcript:SetMaxLines(180)
transcript:SetFading(false)
transcript:SetInsertMode("BOTTOM")
transcript:SetHyperlinksEnabled(true)
transcript:EnableMouse(true)
transcript:EnableMouseWheel(true)
transcript:SetScript("OnHyperlinkClick", function(self, link, linkText, mouseButton)
    if SetItemRef then SetItemRef(link, linkText, mouseButton, self) end
end)
transcript:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)
local function stopScroll(self)
    self:SetScript("OnUpdate", nil)
end
transcript:SetScript("OnMouseDown", function(self, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    local _, y = GetCursorPosition()
    self:SetScript("OnUpdate", function(frame)
        local _, current = GetCursorPosition()
        local delta = (current - y) / UIParent:GetEffectiveScale()
        if math.abs(delta) < 13 then return end
        y = current
        for _ = 1, math.min(5, math.floor(math.abs(delta) / 13)) do
            if delta < 0 then frame:ScrollUp() else frame:ScrollDown() end
        end
    end)
end)
transcript:SetScript("OnMouseUp", stopScroll)
transcript:SetScript("OnHide", stopScroll)
local empty = label(panel, "CENTER")
empty:SetPoint("CENTER", transcript)
local scrollUp = button(panel, "ForeverTouchChatPageUp", "", function() transcript:PageUp() end)
local scrollDown = button(panel, "ForeverTouchChatLatest", "", function() transcript:ScrollToBottom() end)
icon(scrollUp, chevronUp)
icon(scrollDown, chevronDown)
local resize = button(panel, "ForeverTouchChatResize", "", function(self)
    if self.dragged then return end
    local width = panel:GetWidth() / UIParent:GetHeight()
    if width < .6 then
        widthRatio, heightRatio = .67, .31
    elseif width < .8 and (heightRatio or .31) < .40 then
        widthRatio, heightRatio = .91, .43
    else
        widthRatio, heightRatio = .51, .25
    end
    onChange(expanded, widthRatio, heightRatio)
    Chat.layout()
end)
icon(resize, {{-6, 1, 1, -6}, {-6, 5, 5, -6}})
for _, control in ipairs({scrollUp, scrollDown, resize}) do
    control.fill:SetColorTexture(.06, .09, .13, .54)
end
resize:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(text("Drag to resize · Tap for three sizes", "Ziehen zum Skalieren · Tippen für drei Größen"))
    GameTooltip:Show()
end)
resize:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
local unavailable = CreateFrame("EditBox", "ForeverTouchChatUnavailable", UIParent)
unavailable:SetFrameStrata("FULLSCREEN_DIALOG")
unavailable:SetFontObject(GameFontDisableSmall)
unavailable:SetAutoFocus(false)
unavailable:SetMaxLetters(1)
unavailable:SetTextColor(.44, .53, .55, 0)
unavailable:Hide()
unavailable:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
unavailable:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
unavailable:SetScript("OnEditFocusLost", function(self) self:Hide() end)

local function setParent(frame, parent)
    if FrameUtil and FrameUtil.SetParentMaintainRenderLayering then
        FrameUtil.SetParentMaintainRenderLayering(frame, parent)
    else
        frame:SetParent(parent)
    end
end

local function syncDock(visible)
    local dock = GENERAL_CHAT_DOCK
    local wanted = {}
    local function park(frame)
        if frame then wanted[frame] = true end
    end
    if not visible then
        park(DEFAULT_CHAT_FRAME)
        park(dock)
        if dock and FCFDock_GetChatFrames then
            for _, frame in ipairs(FCFDock_GetChatFrames(dock)) do park(frame) end
        end
    end
    for frame, parent in pairs(docked) do
        if not wanted[frame] and not frame:IsForbidden() then
            if frame:GetParent() ~= parked then
                docked[frame] = nil
            elseif not (InCombatLockdown() and frame:IsProtected()) then
                setParent(frame, parent)
                docked[frame] = nil
            end
        end
    end
    for frame in pairs(wanted) do
        if not frame:IsForbidden() and not frame:IsProtected() and frame:GetParent() == UIParent then
            docked[frame] = UIParent
            setParent(frame, parked)
        end
    end
end

local function place(frame, point, relative, relativePoint, x, y, width, height)
    frame:ClearAllPoints()
    frame:SetPoint(point, relative, relativePoint, x, y)
    if width and height then frame:SetSize(width, height) end
end

local function rightInset(width, height)
    local map = MinimapCluster
    if map and not map:IsForbidden() then
        local left = map:GetLeft()
        if left then
            left = left * map:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local screenLeft = UIParent:GetLeft() or 0
            if left - screenLeft > width * .52 then
                return (UIParent:GetRight() or screenLeft + width) - left + height * .018
            end
        end
    end
    return math.min(width * .28, height * .34)
end

local function dimensions(width, height, right)
    local maximumWidth = math.max(1, math.min(width * .52, width * .78 - right))
    local minimumWidth = math.min(height * .42, maximumWidth)
    local minimumHeight = height * .245
    local maximumHeight = height * .51
    return minimumWidth, maximumWidth, minimumHeight, maximumHeight
end

local function cleanPreview(value)
    return (value:gsub("|H[^|]*|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", ""):gsub("|[TA].-|[ta]", ""):gsub("[\r\n]", " "))
end

local function availableName(value)
    if not isSecret(value) and type(value) == "string" and value ~= "" then return value end
end

function Chat.updateFriends()
    friends, friendsByKey = {}, {}
    local function add(name, kind, accountID, online, detail)
        name, detail = availableName(name), availableName(detail)
        if not name then return end
        local key = history.whisperKey(name, kind, accountID)
        if friendsByKey[key] then return end
        local contact = { key = key, name = name, kind = kind, accountID = accountID,
            online = not isSecret(online) and online == true, detail = detail }
        friends[#friends + 1], friendsByKey[key] = contact, contact
    end
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local count = C_FriendList.GetNumFriends()
        for index = 1, not isSecret(count) and type(count) == "number" and count or 0 do
            local friend = C_FriendList.GetFriendInfoByIndex(index)
            if not isSecret(friend) and friend then
                add(friend.name, "WHISPER", nil, friend.connected, friend.area)
            end
        end
    end
    if C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        local count = BNGetNumFriends()
        for index = 1, not isSecret(count) and type(count) == "number" and count or 0 do
            local account = C_BattleNet.GetFriendAccountInfo(index)
            if not isSecret(account) and account and not isSecret(account.bnetAccountID)
                and type(account.bnetAccountID) == "number" and account.bnetAccountID > 0 then
                local game = account.gameAccountInfo
                local online = not isSecret(game) and game and game.isOnline
                add(account.accountName, "BN_WHISPER", account.bnetAccountID, online, "Battle.net")
            end
        end
    end
    table.sort(friends, function(a, b)
        if a.online ~= b.online then return a.online end
        local first, second = a.name:lower(), b.name:lower()
        if first ~= second then return first < second end
        return a.key < b.key
    end)
    if category == "FRIENDS" and peer and not friendsByKey[peer] then peer = nil end
end

layoutContacts = function()
    if not contacts:IsShown() then return end
    local showingFriends = category == "FRIENDS"
    local entries = showingFriends and friends or history.contacts
    local rowHeight = controlHeight * 1.15
    local visible = math.max(1, math.min(#rows, math.floor((contacts:GetHeight() - controlHeight * 1.65 - 10) / rowHeight)))
    local pages = math.max(1, math.ceil(#entries / visible))
    contactPage = math.min(pages, contactPage)
    place(sidebarTitle, "TOPLEFT", contacts, "TOPLEFT", 12, -4, contactWidth - 24, controlHeight * .67)
    sidebarTitle:SetText(showingFriends and labels.FRIENDS or labels.WHISPER)
    for index, row in ipairs(rows) do
        local contact = index <= visible and entries[(contactPage - 1) * visible + index]
        row.contact = contact
        row:SetShown(contact ~= nil and contact ~= false)
        if contact then
            place(row, "TOPLEFT", contacts, "TOPLEFT", 6, -controlHeight * .77 - (index - 1) * rowHeight,
                contactWidth - 12, rowHeight - 4)
            row.fill:SetColorTexture(.16, .26, .43, contact.key == peer and .98 or .30)
            local thread = history.peers[contact.key]
            row.caption:SetText(contact.name)
            if showingFriends then
                local status = contact.online and text("Online", "Online") or text("Offline", "Offline")
                row.preview:SetText(contact.detail and (status .. " · " .. contact.detail) or status)
                if contact.online then row.indicator:SetColorTexture(.18, .67, .43, .96)
                else row.indicator:SetColorTexture(.29, .34, .45, .9) end
            else
                local line = thread and thread.lines[#thread.lines]
                row.preview:SetText(line and cleanPreview(line.text) or "")
                row.indicator:SetColorTexture(.31, .53, .98, .92)
            end
            row.badge:SetText(thread and thread.unread > 0 and tostring(math.min(thread.unread, 99)) or "")
        end
    end
    local footerHeight = controlHeight * .75
    place(previous, "BOTTOMLEFT", contacts, "BOTTOMLEFT", 4, 4, (contactWidth - 12) / 2, footerHeight)
    place(nextPage, "BOTTOMRIGHT", contacts, "BOTTOMRIGHT", -4, 4, (contactWidth - 12) / 2, footerHeight)
    previous:SetShown(contactPage > 1)
    nextPage:SetShown(contactPage < pages)
end

local function inGroup(categoryID)
    return IsInGroup and IsInGroup(categoryID) == true
end

local function destination()
    if isPrivateChat() then
        local thread = activeThread()
        if not thread then return end
        if category == "FRIENDS" and (not friendsByKey[peer] or not friendsByKey[peer].online) then return end
        if thread.accountID and BNet_GetBNetIDAccount then
            local resolved = BNet_GetBNetIDAccount(thread.name)
            if isSecret(resolved) or resolved ~= thread.accountID then return end
        end
        return thread.kind, thread.name
    elseif category == "PARTY" then
        if inGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if inGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid() then return "PARTY" end
    elseif category == "RAID" then
        if IsInRaid() then return "RAID" end
    elseif category == "GUILD" then
        if IsInGuild() then return "GUILD" end
    else
        return "SAY"
    end
end

function Chat.updateChannels()
    local available = destination() ~= nil
    write:SetEnabled(available)
    write.caption:SetTextColor(available and .89 or .52, available and .95 or .61, available and .98 or .65)
end

local function updateUnread()
    unread:SetShown(history.hasUnread())
end

local function detachInput()
    local saved = input
    if not saved then return end
    input = nil
    local entry = saved.frame
    if entry:IsForbidden() or (InCombatLockdown() and entry:IsProtected()) then
        input = saved
        return
    end
    entry:ClearAllPoints()
    for _, point in ipairs(saved.points) do entry:SetPoint(unpack(point, 1, 5)) end
    entry:SetSize(saved.width, saved.height)
    setParent(entry, saved.parent)
    entry:SetFrameStrata(saved.strata)
    entry:SetFrameLevel(saved.level)
end

function Chat.layout()
    if not enabled or (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive()) then return end
    local width, height = UIParent:GetSize()
    if width <= 0 or height <= 0 then return end
    -- The launcher can place its IME and full-chat buttons alongside this dock.
    local right = managedKeyboard and math.min(width * .28, height * .34) or rightInset(width, height)
    local unit, gap = math.max(25, math.min(height * .062, width * .08)), math.max(6, height * .012)
    controlHeight = unit
    place(toggle, "TOPRIGHT", UIParent, "TOPRIGHT", -right, -height * .16,
        math.max(width * .045, height * .14), unit)
    toggle.caption:SetText(stockChat and text("Mobile", "Mobil") or "Chat")
    toggle:SetShown(not fullscreen or stockChat)
    dimmer:SetShown(fullscreen and not stockChat)
    syncDock(stockChat)
    panel:SetShown(not stockChat and (expanded or fullscreen or input ~= nil))
    if not panel:IsShown() then return end

    local minW, maxW, minH, maxH = dimensions(width, height, right)
    if not sizing then
        if fullscreen then
            panel:SetFrameStrata("FULLSCREEN_DIALOG")
            place(panel, "TOPLEFT", UIParent, "TOPLEFT", width * .025, -height * .035,
                width * .95, height * .93)
        else
            panel:SetFrameStrata("HIGH")
            local w = math.min(maxW, math.max(minW, (widthRatio or .67) * height))
            local h = math.min(maxH, math.max(minH, (heightRatio or .31) * height))
            place(panel, "TOPRIGHT", UIParent, "TOPRIGHT", -right, -height * .16 - unit - gap, w, h)
            panel:SetResizeBounds(minW, minH, maxW, maxH)
        end
    end
    panel.fill:SetColorTexture(.042, .057, .086, fullscreen and .99 or 0)
    panel:EnableMouse(fullscreen)
    transcript:SetFading(not fullscreen and not input)

    header:SetPoint("TOPLEFT", gap, -gap)
    header:SetPoint("TOPRIGHT", -gap, -gap)
    header:SetHeight(unit * .82)
    title:SetPoint("TOPLEFT", header, "TOPLEFT", fullscreen and gap or 2, 0)
    local titleInset = fullscreen and panel:GetWidth() * .3 or (managedKeyboard and unit * 1.35 or unit * 4.1)
    title:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -titleInset, 0)
    title:SetShown(fullscreen or category ~= "ALL")
    back:SetShown(not fullscreen and category ~= "ALL")
    place(back, "RIGHT", header, "RIGHT", managedKeyboard and 0 or -unit * 4.25, 0, unit * 1.14, unit * .73)
    expand:SetShown(not managedKeyboard)
    expandIcon:SetShown(not fullscreen)
    closeIcon:SetShown(fullscreen)
    place(expand, "RIGHT", header, "RIGHT", 0, 0, unit, unit * .73)
    write:SetShown(not managedKeyboard)
    place(write, "RIGHT", header, "RIGHT", -unit - 4, 0, unit * 3, unit * .73)
    stock:SetShown((history.restrictedUnread and category == "WHISPER")
        or (history.restrictedNativeLine and category == "ALL"))
    place(stock, "RIGHT", header, "RIGHT", -unit * 1.25, 0, unit * 2.1, unit * .73)

    local headerVisible = fullscreen or category ~= "ALL" or not managedKeyboard
    local offset = headerVisible and unit * .82 + gap * 2 or gap
    tabsBar:SetShown(fullscreen)
    if fullscreen then
        local available = panel:GetWidth() - gap * 2
        place(tabsBar, "TOPLEFT", panel, "TOPLEFT", gap, -offset, available, unit)
        local tabWidth = (available - (#tabs + 1) * 4) / #tabs
        for index, tab in ipairs(tabs) do
            place(tab.button, "LEFT", tabsBar, "LEFT", 4 + (index - 1) * (tabWidth + 4), 0, tabWidth, unit - 8)
            tab.button.fill:SetColorTexture(.21, .38, .69, tab[1] == category and .98 or 0)
            tab.button.caption:SetTextColor(tab[1] == category and 1 or .76, .86, .98)
        end
        offset = offset + unit + gap
    end

    if input then
        place(input.frame, "TOPLEFT", panel, "TOPLEFT", gap + 4, -offset - 3,
            panel:GetWidth() - gap * 2 - 8, math.min(unit * .75, input.height))
        input.frame:SetFrameStrata(panel:GetFrameStrata())
        input.frame:SetFrameLevel(panel:GetFrameLevel() + 4)
        offset = offset + unit
    end
    local sidebar = fullscreen and isPrivateChat()
    contacts:SetShown(sidebar)
    local left = gap + 3
    if sidebar then
        contactWidth = math.min(panel:GetWidth() * .37, math.max(unit * 4.6, 140))
        place(contacts, "TOPLEFT", panel, "TOPLEFT", gap, -offset, contactWidth,
            math.max(unit * 2, panel:GetHeight() - offset - gap))
        left = left + contactWidth + gap
        layoutContacts()
    end
    transcript:ClearAllPoints()
    transcript:SetPoint("TOPLEFT", panel, "TOPLEFT", left, -offset)
    transcript:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -gap - unit * .7,
        fullscreen and gap + 3 or unit * .65 + 3)
    place(scrollUp, "TOPRIGHT", panel, "TOPRIGHT", -gap, -offset, unit * .65, unit * .75)
    place(scrollDown, "TOPRIGHT", scrollUp, "BOTTOMRIGHT", 0, -4, unit * .65, unit * .75)
    place(resize, "BOTTOMLEFT", panel, "BOTTOMLEFT", gap / 2, 3, unit, unit * .72)
    resize:SetShown(not fullscreen and not input)
    Chat.updateChannels()
end

resize:SetScript("OnMouseDown", function(self, mouseButton)
    if mouseButton ~= "LeftButton" or fullscreen or input then return end
    self.dragged = false
    sizing = { width = panel:GetWidth(), height = panel:GetHeight() }
    panel:StartSizing("BOTTOMLEFT")
end)
local function finishResize()
    if not sizing then return end
    local start = sizing
    sizing = nil
    panel:StopMovingOrSizing()
    local width, height = panel:GetSize()
    resize.dragged = math.abs(width - start.width) > 1 or math.abs(height - start.height) > 1
    local screenHeight = UIParent:GetHeight()
    if resize.dragged and screenHeight > 0 then
        widthRatio, heightRatio = width / screenHeight, height / screenHeight
        onChange(expanded, widthRatio, heightRatio)
    end
end
resize:SetScript("OnMouseUp", function()
    finishResize()
    Chat.layout()
end)
panel:SetScript("OnSizeChanged", function()
    if sizing then Chat.layout() end
end)
resize:SetScript("OnHide", finishResize)

local function stream()
    if not isPrivateChat() then return history.lines[category] end
    local thread = activeThread()
    return thread and thread.lines
end

local function message(line)
    if line.nativeColors then
        transcript:AddMessage(line.text, unpack(line.nativeColors))
        return
    end
    local info = ChatTypeInfo and ChatTypeInfo[line.kind]
    local author = line.outgoing and text("You", "Du") or line.author
    local prefix = author and author .. "  " or ""
    if fullscreen then prefix = "|cff879fa9" .. line.time .. "|r  " .. prefix end
    if category == "ALL" then
        local channel = line.kind == "CHANNEL" and line.channel or labels[line.kind]
        if channel then prefix = "[" .. channel .. "] " .. prefix end
    end
    transcript:AddMessage(prefix .. line.text, info and info.r or .89, info and info.g or .93, info and info.b or .96)
end

refresh = function()
    local thread = activeThread()
    if panel:IsShown() then
        if isPrivateChat() and thread and thread.unread then thread.unread = 0 end
        title:SetText(category == "ALL" and "Chat" or (thread and thread.name or labels[category]))
        transcript:Clear()
        local lines = stream()
        for _, line in ipairs(lines or {}) do message(line) end
        local hint = category == "FRIENDS" and not thread
            and (#friends == 0 and text("No friends to display", "Keine Freunde verfügbar")
                or text("Select a friend", "Freund auswählen"))
            or category == "WHISPER" and not thread
            and (history.restrictedUnread and text("A whisper is available in WoW chat.", "Ein Flüstern ist im WoW-Chat verfügbar.")
                or text("Choose a conversation", "Unterhaltung auswählen"))
            or text("No messages in this session", "Keine Nachrichten in dieser Sitzung")
        empty:SetText(hint)
        local hasLines = lines and #lines > 0
        empty:SetShown(fullscreen and not hasLines)
        scrollUp:SetShown(hasLines == true)
        scrollDown:SetShown(hasLines == true)
        transcript:ScrollToBottom()
        layoutContacts()
        Chat.updateChannels()
    end
    updateUnread()
end

local function appendVisibleLine(line)
    if not line then return end
    empty:Hide()
    scrollUp:Show()
    scrollDown:Show()
    message(line)
end

local function attachDefaultChat()
    local frame = DEFAULT_CHAT_FRAME
    if not frame or not hooksecurefunc or not frame.AddMessage or frame:IsForbidden() then return end
    if nativeChat ~= frame then
        -- The default chat has already formatted and filtered channel notices,
        -- loot, system text, item links, and messages written directly by the UI.
        local attached = pcall(hooksecurefunc, frame, "AddMessage", function(source, body, r, g, b)
            if source ~= nativeChat or not history.nativeSource then return end
            local line = history.addNative(body, r, g, b)
            if category == "ALL" and panel:IsShown() then
                appendVisibleLine(line)
                if history.restrictedNativeLine then stock:Show() end
            end
        end)
        if not attached then return end
        nativeChat = frame
    end
    history.nativeSource = true
    if frame.GetMessageInfo and frame.GetNumMessages then
        local readable, count = pcall(frame.GetNumMessages, frame)
        if readable and not isSecret(count) and type(count) == "number" then
            for index = math.max(1, count - 179), count do
                local ok, body, r, g, b = pcall(frame.GetMessageInfo, frame, index)
                if ok then history.addNative(body, r, g, b) end
            end
        end
    end
end

function Chat.queueLayout()
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        Chat.layout()
    end)
end

function Chat.initialize(preferences, save)
    history.reset()
    friends, friendsByKey = {}, {}
    category, peer, contactPage, stockChat = "ALL", nil, 1, false
    fullscreen, widthRatio, heightRatio = false, nil, nil
    expanded, enabled, onChange = preferences.mobileChatOpen == true, true, save
    local size = preferences.mobileChatSize
    if type(size) == "table" then
        if type(size.width) == "number" and size.width > 0 then widthRatio = size.width end
        if type(size.height) == "number" and size.height > 0 then heightRatio = size.height end
    end
    attachDefaultChat()
    Chat.layout()
    refresh()
end

function Chat.resume()
    enabled = true
    C_Timer.After(0, function()
        Chat.layout()
        refresh()
    end)
end

function Chat.suspend()
    enabled = false
    finishResize()
    unavailable:ClearFocus()
    if input and not input.frame:IsForbidden() then input.frame:ClearFocus() end
    detachInput()
    syncDock(true)
    dimmer:Hide()
    toggle:Hide()
    panel:Hide()
end

function Chat.setFullscreen(active)
    if not enabled or input or fullscreen == active then return end
    finishResize()
    stockChat = false
    fullscreen = active
    if not active and category == "FRIENDS" then category, peer, contactPage = "ALL", nil, 1 end
    Chat.layout()
    refresh()
end

function Chat.onMessage(event, ...)
    local line, thread = history.add(event, ...)
    if panel:IsShown() and line then
        local lines = stream()
        if lines and lines[#lines] == line then
            if thread and isPrivateChat() then thread.unread = 0 end
            appendVisibleLine(line)
        end
        if thread then layoutContacts() end
    end
    if history.restrictedUnread and category == "WHISPER" then stock:Show() end
    if thread or history.restrictedUnread then updateUnread() end
end

function Chat.open()
    if not enabled then return end
    local getActive = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    if not open then return end
    if stockChat then
        local dock = GENERAL_CHAT_DOCK
        open("", dock and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(dock) or DEFAULT_CHAT_FRAME)
        return
    end
    local kind, target = destination()
    if not kind then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(text("Choose an available chat or conversation.", "Wähle einen verfügbaren Chat oder eine Unterhaltung."))
        end
        if managedKeyboard then
            -- The platform keyboard can already be opening. Keep its keys out of gameplay.
            unavailable:SetSize(1, 1)
            unavailable:SetPoint("CENTER")
            unavailable:Show()
            unavailable:SetFocus()
        end
        return
    end

    local entry = input and input.frame
    if entry and entry:HasFocus() then return true end
    parked:Show()
    entry = getActive and getActive()
    if not entry or not entry:HasFocus() then entry = open("", DEFAULT_CHAT_FRAME) or (getActive and getActive()) end
    if not entry or entry:IsForbidden() or (InCombatLockdown() and entry:IsProtected()) then
        parked:Hide()
        return
    end
    local points = {}
    for index = 1, entry:GetNumPoints() do points[index] = {entry:GetPoint(index)} end
    input = {frame = entry, points = points, width = entry:GetWidth(), height = entry:GetHeight(),
        parent = entry:GetParent(), strata = entry:GetFrameStrata(), level = entry:GetFrameLevel()}
    panel:Show()
    setParent(entry, panel)
    parked:Hide()
    entry:SetChatType(kind)
    if target then entry:SetTellTarget(target) end
    entry:UpdateHeader()

    if not hooked[entry] then
        hooked[entry] = true
        entry:HookScript("OnEditFocusLost", function(self)
            if not input or input.frame ~= self then return end
            detachInput()
            Chat.layout()
        end)
    end
    Chat.layout()
    refresh()
    return true
end

local reader = CreateFrame("Frame")
for _, event in ipairs(history.events) do reader:RegisterEvent(event) end
local friendEvents = {
    FRIENDLIST_UPDATE = true, BN_FRIEND_INFO_CHANGED = true, BN_FRIEND_LIST_SIZE_CHANGED = true,
    BN_CONNECTED = true, BN_DISCONNECTED = true,
}
for event in pairs(friendEvents) do reader:RegisterEvent(event) end
reader:SetScript("OnEvent", function(_, event, ...)
    if friendEvents[event] then
        if enabled and fullscreen and category == "FRIENDS" then
            Chat.updateFriends()
            refresh()
        end
    else
        Chat.onMessage(event, ...)
    end
end)
