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
}
local labels = {}
for _, tab in ipairs(tabs) do labels[tab[1]] = tab[2] end
local enabled, expanded, fullscreen, layoutQueued = false, false, false, false
local onChange, widthRatio, heightRatio
local category, peer, contactPage = "ALL", nil, 1
local docked, hooked = {}, {}
local stockChat = false
local input, sizing
local controlHeight, contactWidth
local refresh, layoutContacts

-- Keep WoW collecting messages for its own chat. Restoring the parent brings
-- back exactly the native layout, including any changes made in Edit Mode.
local parked = CreateFrame("Frame", nil, UIParent)
parked:Hide()

local panel = CreateFrame("Frame", "ForeverTouchChatPanel", UIParent, "BackdropTemplate")
panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
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

local function label(parent, anchor, font)
    local fontString = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fontString:SetJustifyH(anchor or "LEFT")
    fontString:SetWordWrap(false)
    fontString:SetTextColor(.88, .94, .97)
    return fontString
end

local function button(parent, name, caption, action)
    local control = CreateFrame("Button", name, parent)
    control:RegisterForClicks("LeftButtonUp")
    control.fill = paint(control, "BACKGROUND", .11, .20, .25, .88)
    control.highlight = paint(control, "HIGHLIGHT", .59, .83, .87, .18)
    control.caption = label(control, "CENTER")
    control.caption:SetPoint("TOPLEFT", 4, 0)
    control.caption:SetPoint("BOTTOMRIGHT", -4, 0)
    control.caption:SetText(caption)
    control:SetScript("OnClick", action)
    return control
end

local toggle = button(UIParent, "ForeverTouchChatToggle", "Chat", function()
    if input then return end
    if stockChat then
        stockChat = false
        Chat.layout()
        refresh()
        return
    end
    expanded = not expanded
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
toggle:Hide()
local unread = toggle:CreateTexture("ForeverTouchUnreadWhisper", "OVERLAY")
unread:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
unread:SetVertexColor(1, .26, .32)
unread:SetPoint("RIGHT", -9, 0)
unread:SetSize(9, 9)
unread:Hide()

local header = CreateFrame("Frame", nil, panel)
local title = label(header, "LEFT", "GameFontNormalLarge")
local back = button(header, "ForeverTouchChatBack", text("All", "Alle"), function()
    if input then return end
    category, peer, contactPage = "ALL", nil, 1
    Chat.layout()
    refresh()
end)
local expand = button(header, "ForeverTouchChatExpand", "↗", function() Chat.setFullscreen(not fullscreen) end)
local write = button(header, "ForeverTouchChatWrite", text("Message…", "Nachricht…"), function() Chat.open() end)
local stock = button(header, "ForeverTouchChatStock", text("WoW chat", "WoW-Chat"), function()
    if input then return end
    stockChat, history.restrictedUnread = true, false
    Chat.layout()
    refresh()
end)

local tabsBar = CreateFrame("Frame", nil, panel)
for _, tab in ipairs(tabs) do
    local key = tab[1]
    tab.button = button(tabsBar, "ForeverTouchChatTab" .. key, tab[2], function()
        if input then return end
        category, peer, contactPage = key, nil, 1
        Chat.layout()
        refresh()
    end)
end

local contacts = CreateFrame("Frame", nil, panel)
paint(contacts, "BACKGROUND", .07, .12, .16, .93)
local rows = {}
for index = 1, 10 do
    local row = button(contacts, "ForeverTouchChatContact" .. index, "", function(self)
        if self.thread and not input then
            peer = self.thread.key
            refresh()
        end
    end)
    row.caption:SetJustifyH("LEFT")
    row.caption:ClearAllPoints()
    row.caption:SetPoint("TOPLEFT", 11, -4)
    row.caption:SetPoint("BOTTOMRIGHT", -36, 18)
    row.preview = label(row, "LEFT", "GameFontDisableSmall")
    row.preview:SetPoint("TOPLEFT", 11, -23)
    row.preview:SetPoint("BOTTOMRIGHT", -11, 2)
    row.badge = label(row, "RIGHT", "GameFontNormalSmall")
    row.badge:SetPoint("RIGHT", -10, 6)
    row.badge:SetTextColor(1, .52, .57)
    rows[index] = row
end
local previous = button(contacts, "ForeverTouchChatContactsPrev", "‹", function()
    contactPage = math.max(1, contactPage - 1)
    layoutContacts()
end)
local nextPage = button(contacts, "ForeverTouchChatContactsNext", "›", function()
    contactPage = contactPage + 1
    layoutContacts()
end)

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
local scrollUp = button(panel, "ForeverTouchChatPageUp", "↑", function() transcript:PageUp() end)
local scrollDown = button(panel, "ForeverTouchChatLatest", "↓", function() transcript:ScrollToBottom() end)
local resize = button(panel, "ForeverTouchChatResize", "↙", function(self)
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
resize:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(text("Drag to resize · Tap for three sizes", "Ziehen zum Skalieren · Tippen für drei Größen"))
    GameTooltip:Show()
end)
resize:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
local unavailable = CreateFrame("EditBox", "ForeverTouchChatUnavailable", panel)
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

layoutContacts = function()
    if not contacts:IsShown() then return end
    local rowHeight = controlHeight * 1.15
    local visible = math.max(1, math.min(#rows, math.floor((contacts:GetHeight() - controlHeight - 8) / rowHeight)))
    local pages = math.max(1, math.ceil(#history.contacts / visible))
    contactPage = math.min(pages, contactPage)
    for index, row in ipairs(rows) do
        local thread = index <= visible and history.contacts[(contactPage - 1) * visible + index]
        row.thread = thread
        row:SetShown(thread ~= nil and thread ~= false)
        if thread then
            place(row, "TOPLEFT", contacts, "TOPLEFT", 4, -4 - (index - 1) * rowHeight,
                contactWidth - 8, rowHeight - 3)
            row.fill:SetColorTexture(.19, .35, .40, thread.key == peer and .94 or .38)
            row.caption:SetText(thread.name)
            row.preview:SetText(cleanPreview(thread.lines[#thread.lines].text))
            row.badge:SetText(thread.unread > 0 and tostring(math.min(thread.unread, 99)) or "")
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
    if category == "WHISPER" then
        local thread = peer and history.peers[peer]
        if not thread then return end
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
    local right = rightInset(width, height)
    local unit, gap = math.max(25, math.min(height * .062, width * .08)), math.max(6, height * .012)
    controlHeight = unit
    place(toggle, "TOPRIGHT", UIParent, "TOPRIGHT", -right, -height * .139,
        math.max(64, height * .14), unit)
    toggle.caption:SetText(stockChat and text("Mobile chat", "Mobiler Chat") or (expanded and "Chat ▾" or "Chat ▸"))
    toggle:SetShown(not fullscreen or stockChat)
    syncDock(stockChat)
    panel:SetShown(not stockChat and (expanded or fullscreen or input ~= nil))
    if not panel:IsShown() then return end

    local minW, maxW, minH, maxH = dimensions(width, height, right)
    if not sizing then
        if fullscreen then
            panel:SetFrameStrata("FULLSCREEN_DIALOG")
            place(panel, "TOPLEFT", UIParent, "TOPLEFT", width * .018, -height * .15,
                width * .964, height * .82)
        else
            panel:SetFrameStrata("HIGH")
            local w = math.min(maxW, math.max(minW, (widthRatio or .67) * height))
            local h = math.min(maxH, math.max(minH, (heightRatio or .31) * height))
            place(panel, "TOPRIGHT", UIParent, "TOPRIGHT", -right, -height * .139 - unit - gap, w, h)
            panel:SetResizeBounds(minW, minH, maxW, maxH)
        end
    end
    panel:SetBackdropColor(.043, .073, .095, fullscreen and .97 or .77)
    panel:SetBackdropBorderColor(.39, .68, .72, .68)

    header:SetPoint("TOPLEFT", gap, -gap)
    header:SetPoint("TOPRIGHT", -gap, -gap)
    header:SetHeight(unit * .75)
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 2, 0)
    local titleInset = managedKeyboard and (category ~= "ALL" and not fullscreen and unit * 1.2 or 0)
        or unit * 4.05
    title:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -titleInset, 0)
    back:SetShown(not fullscreen and category ~= "ALL")
    place(back, "RIGHT", header, "RIGHT", managedKeyboard and 0 or -unit * 4.25, 0, unit * 1.14, unit * .73)
    expand:SetShown(not managedKeyboard)
    place(expand, "RIGHT", header, "RIGHT", 0, 0, unit, unit * .73)
    write:SetShown(not managedKeyboard)
    place(write, "RIGHT", header, "RIGHT", -unit - 4, 0, unit * 3, unit * .73)
    stock:SetShown(history.restrictedUnread and category == "WHISPER")
    place(stock, "RIGHT", header, "RIGHT", -unit * 1.25, 0, unit * 2.1, unit * .73)

    local offset = unit * .75 + gap * 2
    tabsBar:SetShown(fullscreen)
    if fullscreen then
        local available = panel:GetWidth() - gap * 2
        place(tabsBar, "TOPLEFT", panel, "TOPLEFT", gap, -offset, available, unit)
        local tabWidth = (available - (#tabs - 1) * 4) / #tabs
        for index, tab in ipairs(tabs) do
            place(tab.button, "LEFT", tabsBar, "LEFT", (index - 1) * (tabWidth + 4), 0, tabWidth, unit)
            tab.button.fill:SetColorTexture(.18, .33, .39, tab[1] == category and 1 or .68)
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
    local sidebar = fullscreen and category == "WHISPER"
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
    if category ~= "WHISPER" then return history.lines[category] end
    local thread = peer and history.peers[peer]
    return thread and thread.lines
end

local function message(line)
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
    local thread = peer and history.peers[peer]
    if panel:IsShown() then
        if category == "WHISPER" and thread then thread.unread = 0 end
        title:SetText(category == "ALL" and "Chat" or (thread and thread.name or labels[category]))
        transcript:Clear()
        local lines = stream()
        for _, line in ipairs(lines or {}) do message(line) end
        local hint = category == "WHISPER" and not thread
            and (history.restrictedUnread and text("A whisper is available in WoW chat.", "Ein Flüstern ist im WoW-Chat verfügbar.")
                or text("Choose a conversation", "Unterhaltung auswählen"))
            or text("No messages in this session", "Keine Nachrichten in dieser Sitzung")
        empty:SetText(hint)
        empty:SetShown(not lines or #lines == 0)
        transcript:ScrollToBottom()
        layoutContacts()
        Chat.updateChannels()
    end
    updateUnread()
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
    category, peer, contactPage, stockChat = "ALL", nil, 1, false
    expanded, enabled, onChange = preferences.mobileChatOpen == true, true, save
    local size = preferences.mobileChatSize
    if type(size) == "table" then
        if type(size.width) == "number" and size.width > 0 then widthRatio = size.width end
        if type(size.height) == "number" and size.height > 0 then heightRatio = size.height end
    end
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
    toggle:Hide()
    panel:Hide()
end

function Chat.setFullscreen(active)
    if not enabled or input or fullscreen == active then return end
    finishResize()
    stockChat = false
    fullscreen = active
    Chat.layout()
    refresh()
end

function Chat.onMessage(event, ...)
    local line, thread = history.add(event, ...)
    if panel:IsShown() and line then
        local lines = stream()
        if lines and lines[#lines] == line then
            if thread and category == "WHISPER" then thread.unread = 0 end
            empty:Hide()
            message(line)
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
        if managedKeyboard and panel:IsVisible() then
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
reader:SetScript("OnEvent", function(_, event, ...) Chat.onMessage(event, ...) end)
