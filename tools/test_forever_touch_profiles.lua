-- Run with: lua tools/test_forever_touch_profiles.lua [add-on source directory]
local source = (arg and arg[1]) or "app/src/main/assets/ForeverTouch"
local frames, event, choose, player, combat, reloads, disk
local playerName, playerRealm, bindings, callbacks, messages
local secureClick, hardwareEvent, registered

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, element in pairs(value) do result[key] = copy(element) end
    return result
end

CopyTable = copy
unpack = table.unpack
date = os.date

local function guarded(frame)
    assert(not (combat and frame.protected and not secureClick), "insecure change to a protected frame during combat")
end

local methods = {
    RegisterEvent = function(_, name) registered[name] = true end,
    GetParent = function(self) return rawget(self, "parent") end,
    SetParent = function(self, parent) guarded(self); self.parent = parent end,
    IsVisible = function(self)
        if not self.shown then return false end
        local parent = rawget(self, "parent")
        return not parent or parent:IsVisible()
    end,
    GetRight = function(self) return self:GetLeft() + self:GetWidth() end,
    SetScript = function(self, name, callback)
        self.scripts[name] = callback
        if name == "OnEvent" then event = callback end
    end,
    GetScript = function(self, name) return self.scripts[name] end,
    HookScript = function(self, name, callback) self.scripts[name] = callback end,
    SetAttribute = function(self, name, value)
        guarded(self)
        local old = self.attributes[name]
        self.attributes[name] = value
        if old ~= value and self.scripts.OnAttributeChanged then
            local fromSecureClick = secureClick
            secureClick = false
            self.scripts.OnAttributeChanged(self, name, value)
            secureClick = fromSecureClick
        end
    end,
    GetAttribute = function(self, name) return self.attributes[name] end,
    SetFrameRef = function(self, name, frame) guarded(self); self.refs[name] = frame end,
    GetFrameRef = function(self, name) return self.refs[name] end,
    GetFrameLevel = function(self) return rawget(self, "level") or 1 end,
    GetFrameStrata = function(self) return rawget(self, "strata") or "MEDIUM" end,
    SetFrameStrata = function(self, value) self.strata = value end,
    SetChatType = function(self, value) self.chatType = value end,
    SetTellTarget = function(self, value) self.tellTarget = value end,
    SetFocus = function(self) self.focused = true end,
    HasFocus = function(self) return self.focused == true end,
    ClearFocus = function(self)
        self.focused = false
        if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end,
    AddMessage = function(self, value) self.lines[#self.lines + 1] = value end,
    SetText = function(self, value) self.text = value end,
    GetText = function(self) return self.text end,
    SetSwipeColor = function(self, _, _, _, alpha) self.swipeAlpha = alpha end,
    SetVertexColor = function(self, red) self.red = red end,
    SetColorTexture = function(self, r, g, b) self.rasterColor = math.floor(r * 8 + g * 6 + b + .5) end,
    SetEnabled = function(self, enabled) self.enabled = enabled end,
    SetFrameLevel = function(self, level) self.level = level end,
    SetDrawSwipe = function(self, enabled) self.drawSwipe = enabled end,
    SetHideCountdownNumbers = function(self, hidden) self.hideNumbers = hidden end,
    SetMinimumCountdownDuration = function(self, milliseconds) self.minimumCountdown = milliseconds end,
    SetCooldown = function(self, start, duration, rate)
        assert(not issecretvalue(start) and not issecretvalue(duration) and not issecretvalue(rate))
        self.timer = { start = start, duration = duration, rate = rate }
    end,
    SetCooldownFromDurationObject = function(self, timer, clearIfZero)
        assert(not issecretvalue(timer) and clearIfZero)
        self.timer = timer
    end,
    Clear = function(self) self.timer = nil; self.lines = {} end,
    GetName = function(self) return self.name end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    GetSize = function(self) return self.width, self.height end,
    SetSize = function(self, width, height) guarded(self); self.width, self.height = width, height end,
    SetScale = function(self, scale) guarded(self); self.scale = scale end,
    GetEffectiveScale = function(self) return rawget(self, "scale") or 1 end,
    GetLeft = function(self) return rawget(self, "left") or 0 end,
    GetBottom = function(self) return rawget(self, "bottom") or 0 end,
    SetPoint = function(self, ...)
        guarded(self)
        local points = rawget(self, "points") or {}
        points[#points + 1] = {...}
        self.points = points
    end,
    ClearAllPoints = function(self) guarded(self); self.points = {} end,
    GetNumPoints = function(self) return #(rawget(self, "points") or {}) end,
    GetPoint = function(self, index) return table.unpack(self.points[index or 1]) end,
    SetWidth = function(self, width) guarded(self); self.width = width end,
    SetHeight = function(self, height) guarded(self); self.height = height end,
    IsProtected = function(self) return self.protected end,
    IsShown = function(self) return self.shown end,
    Show = function(self) guarded(self); self.shown = true end,
    Hide = function(self) guarded(self); self.shown = false end,
    SetShown = function(self, shown) guarded(self); self.shown = shown end,
}

local function noop() end
local frameType = { __index = function(_, key)
    if key:match("^foreverTouch") then return nil end
    return methods[key] or noop
end }
function CreateFrame(_, name, parent, template)
    local frame = setmetatable({
        name = name, parent = parent, shown = true, scripts = {}, attributes = {}, refs = {},
        protected = type(template) == "string" and template:find("Secure") ~= nil,
    }, frameType)
    if frame.protected then
        local ancestor = parent
        while ancestor and ancestor ~= UIParent do
            ancestor.protected = true
            ancestor = ancestor.parent
        end
    end
    frames[#frames + 1] = frame
    if name then frames[name] = frame end
    return frame
end
methods.CreateTexture = function(self, name) return CreateFrame("Texture", name, self) end
methods.CreateLine = methods.CreateTexture
methods.CreateMaskTexture = methods.CreateTexture
methods.CreateFontString = methods.CreateTexture

function GetLocale() return "enUS" end
function UnitGUID() return player end
function UnitFullName() return playerName, playerRealm end
function InCombatLockdown() return combat end
function GetActionInfo(slot) if slot == 1 then return "spell", 101 end end
function GetActionTexture(slot) if slot == 1 then return 1001 end end
function SetOverrideBinding(_, _, key, command) bindings[key] = command end
function SetOverrideBindingClick(_, _, key, button) bindings[key] = button end
function SaveBindings() error("The HUD must leave WoW's keyboard bindings alone") end
function IsInGroup() return false end
function IsInRaid() return false end
function IsInGuild() return false end
C_Timer = { After = function(_, callback)
    local previous = hardwareEvent
    hardwareEvent = false
    callback()
    hardwareEvent = previous
end }
C_UI = {
    Reload = function()
        if not hardwareEvent then return end -- The WoW client can ignore an unprotected reload.
        reloads = reloads + 1
        event(nil, "PLAYER_LOGOUT")
        disk = { character = copy(ForeverTouchPreferences), account = copy(ForeverTouchProfiles) }
    end,
}
EventRegistry = { RegisterCallback = function(_, key, callback) callbacks[key] = callback end }
local secret = setmetatable({}, { __index = function() error("A restricted value must not be indexed") end })
function issecretvalue(value) return rawequal(value, secret) end

local cooldownInfoForTest
local actionTimers, spellTimers, spellInfo, chargeTimers, chargeInfo, itemTimers = {}, {}, {}, {}, {}, {}
C_ActionBar = {
    GetActionCooldownDuration = function(slot) return actionTimers[slot] end,
}
C_Spell = {
    GetSpellName = tostring,
    GetSpellCooldownDuration = function(id) return spellTimers[id] end,
    GetSpellCooldown = function(id) return spellInfo[id] end,
    GetSpellChargeDuration = function(id) return chargeTimers[id] end,
    GetSpellCharges = function(id) return chargeInfo[id] end,
}
C_Item = {
    GetItemCooldown = function(id)
        if cooldownInfoForTest then cooldownInfoForTest() end
        local timer = itemTimers[id]
        if timer then return timer.start, timer.duration, timer.enabled end
    end,
}

local function login(guid, characterSaved, accountSaved, options)
    options = options or {}
    frames, player, combat, reloads, disk = {}, guid, false, 0, nil
    playerName, playerRealm = options.name, options.realm
    bindings, callbacks, messages, registered = {}, {}, {}, {}
    secureClick, hardwareEvent, choose = false, false, nil
    ForeverTouchPreferences, ForeverTouchProfiles = nil, nil
    UIParent = CreateFrame("Frame", "UIParent")
    UIParent:SetSize(1536, 720)
    DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1", UIParent)
    DEFAULT_CHAT_FRAME:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 20)
    DEFAULT_CHAT_FRAME:SetSize(430, 180)
    hooksecurefunc = nil
    if options.nativeMessages then
        local nativeMessages = copy(options.nativeMessages)
        function hooksecurefunc(frame, method, callback)
            local original = frame[method]
            frame[method] = function(self, ...)
                original(self, ...)
                callback(self, ...)
            end
        end
        function DEFAULT_CHAT_FRAME:AddMessage(...)
            nativeMessages[#nativeMessages + 1] = {...}
        end
        function DEFAULT_CHAT_FRAME:GetNumMessages() return #nativeMessages end
        function DEFAULT_CHAT_FRAME:GetMessageInfo(index) return table.unpack(nativeMessages[index]) end
    end
    GENERAL_CHAT_DOCK = CreateFrame("Frame", "GeneralDockManager", UIParent)
    GENERAL_CHAT_DOCK.windows = {DEFAULT_CHAT_FRAME}
    FCFDock_GetChatFrames = function(dock) return dock.windows end
    MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    MinimapCluster.left = 1270
    UIErrorsFrame = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    local addon = {
        recoveredProfiles = options.recoveredProfiles,
        createSlotPicker = function()
            local picker = CreateFrame("Frame")
            picker:Hide()
            function picker:Open(callback)
                choose = function(binding)
                    self:Hide()
                    callback(binding)
                end
                self:Show()
            end
            return picker
        end,
    }
    local addons = C_AddOns
    if options.nativeKeyboard or options.arcSession then
        C_AddOns = { GetAddOnMetadata = function(_, key)
            if key == "X-ForeverTouch-Keyboard" and options.nativeKeyboard then return "native" end
            if key == "X-ForeverTouch-ArcSession" then return options.arcSession end
        end }
    end
    assert(loadfile(source .. "/ForeverTouchActions.lua"))("ForeverTouch", addon)
    if options.realPicker then assert(loadfile(source .. "/ForeverTouchPicker.lua"))("ForeverTouch", addon) end
    assert(loadfile(source .. "/ForeverTouchChatHistory.lua"))("ForeverTouch", addon)
    assert(loadfile(source .. "/ForeverTouchChat.lua"))("ForeverTouch", addon)
    if options.arcSession then
        assert(loadfile(source .. "/ForeverTouchArcSave.lua"))("ForeverTouch", addon)
    end
    C_AddOns = addons
    assert(loadfile(source .. "/ForeverTouchMobileLayout.lua"))("ForeverTouch", addon)
    -- The client loads SavedVariables after running the add-on's Lua chunks.
    ForeverTouchPreferences, ForeverTouchProfiles = copy(characterSaved), copy(accountSaved)
    event(nil, "PLAYER_LOGIN")
    event(nil, "PLAYER_ENTERING_WORLD")
    return addon
end

local function click(name)
    local frame = frames["ForeverTouch" .. name]
    hardwareEvent = true
    frame.scripts.OnClick(frame)
    hardwareEvent = false
end

local function control(text)
    for _, frame in ipairs(frames) do
        if frame.text == text then return frame end
    end
    error("Missing editor control: " .. text)
end

local function addItem(id)
    local add = control("+")
    add.scripts.OnClick(add)
    choose({ kind = "item", id = id or 501 })
end

local function cycleSet(down)
    local frame = frames.ForeverTouchCycleSet
    local run = assert(load(frame:GetAttribute("_onclick"), "secure switch", "t",
        { self = frame, button = "LeftButton", down = down }))
    secureClick = true
    run()
    secureClick = false
end

local first, second = "Player-1-123", "Player-2-123"
local legacy = { mobileSlots = { left = {}, right = {{ kind = "spell", id = 201 }} } }

local function preview(side, index)
    for _, frame in ipairs(frames) do
        if rawget(frame, "mobileSide") == side and rawget(frame, "mobileIndex") == index and frame:IsShown() then
            return frame
        end
    end
    error("Missing preview slot: " .. side .. " " .. index)
end

local function replaceRight(binding)
    local slot = preview("right", 1)
    slot.scripts.OnClick(slot)
    local assign = control("Assign")
    assign.scripts.OnClick(assign)
    choose(binding)
end

login(first, legacy)
click("OpenEditor")
replaceRight({ kind = "item", id = 502 })
assert(ForeverTouchPreferences.mobileSlots.right[1].kind == "item")
assert(ForeverTouchProfiles[first].mobileSlots.right[1].id == 502 and reloads == 0,
    "replacing a spell checkpoints the item even with the editor open")
replaceRight({ kind = "spell", id = 202 })
assert(ForeverTouchPreferences.mobileSlots.right[1].id == 202 and reloads == 0,
    "multiple replacements autosave without reloading while editing")
addItem(503)
local left, right = preview("left", 1), preview("right", 1)
left.IsMouseOver = function() return true end
right.scripts.OnDragStart(right)
right.scripts.OnDragStop(right)
assert(ForeverTouchPreferences.mobileSlots.left[1].id == 202 and ForeverTouchPreferences.mobileSlots.right[1].id == 503,
    "dragging one slot onto another checkpoints both slots")
right.scripts.OnClick(right)
local remove = control("Remove")
remove.scripts.OnClick(remove)
assert(#ForeverTouchPreferences.mobileSlots.right == 0 and reloads == 0)
click("SaveEditor")
click("SaveEditor")
assert(reloads == 1 and disk.character.mobileSlots.left[1].id == 202 and #disk.character.mobileSlots.right == 0,
    "closing the editor flushes all autosaved changes once")

login(first, legacy)
click("OpenEditor")
replaceRight({ kind = "item", id = 502 })
click("CancelEditor")
assert(reloads == 0 and ForeverTouchPreferences.mobileSlots.right[1].id == 201
    and ForeverTouchProfiles[first].mobileSlots.right[1].id == 201, "explicit discard restores the opening snapshot")

login(first, legacy)
click("OpenEditor")
replaceRight({ kind = "item", id = 502 })
event(nil, "PLAYER_LOGOUT")
local logoutProfile = copy(ForeverTouchPreferences)
local logoutAccount = copy(ForeverTouchProfiles)
login(first, logoutProfile, logoutAccount)
assert(frames.ForeverTouchRightAction1.attributes.item == "item:502", "logout preserves edits from an open editor")
click("OpenEditor")
replaceRight({ kind = "item", id = 502 })
click("SaveEditor")
assert(reloads == 0, "matching assignments leave the profile alone")

login(first, legacy)
combat = true
click("OpenEditor")
replaceRight({ kind = "item", id = 502 })
click("SaveEditor")
click("OpenEditor")
addItem(503)
click("SaveEditor")
assert(reloads == 0 and ForeverTouchPreferences.mobileSlots.right[1].id == 502,
    "reopening during combat uses the autosaved profile while live buttons still show the old slots")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
assert(reloads == 0 and frames.ForeverTouchRetrySave:IsShown(), "leaving combat is not an input event")
click("RetrySave")
assert(reloads == 1 and disk.character.mobileSlots.left[1].id == 503 and disk.character.mobileSlots.right[1].id == 502)

login(first, legacy)
assert(frames.ForeverTouchRightAction1.attributes.spell == 201, "legacy slots must load")
click("OpenEditor")
addItem()
local move = control("Move arc")
move.scripts.OnDragStart(move)
move.parent.left, move.parent.bottom = 100, 150
move.scripts.OnDragStop(move)
click("SaveEditor")
assert(reloads == 1, "saving changes must request a write to disk")
local primary, backup = disk.character, disk.account
assert(primary.mobileArcPositions.left and primary.mobileSlots.left[1].id == 501)

login(first, nil, backup)
assert(frames.ForeverTouchLeftAction1.attributes.item == "item:501", "missing character file must recover from backup")
assert(ForeverTouchPreferences.mobileArcPositions.left.x == primary.mobileArcPositions.left.x)
event(nil, "PLAYER_ENTERING_WORLD")
assert(frames.ForeverTouchLeftAction1.attributes.item == "item:501", "changing zones must preserve the layout")
click("OpenEditor")
click("SaveEditor")
click("OpenEditor")
click("ResetEditor")
click("CancelEditor")
assert(reloads == 0 and ForeverTouchPreferences.mobileSlots.left[1].id == 501,
    "unchanged saves and cancelled resets must leave the saved layout alone")

login(second, nil, backup)
assert(not frames.ForeverTouchLeftAction1, "another character must have its own layout")
assert(ForeverTouchProfiles[first].mobileSlots.left[1].id == 501)

login(first, primary, nil)
assert(frames.ForeverTouchLeftAction1.attributes.item == "item:501", "the character file must work independently")
click("OpenEditor")
click("ResetEditor")
click("SaveEditor")
assert(reloads == 1 and ForeverTouchPreferences.mobileSlots == nil)
login(first, primary, ForeverTouchProfiles)
assert(ForeverTouchPreferences.mobileSlots == nil, "a newer reset must win over an older character file")
assert(frames.ForeverTouchRightAction1.attributes.action == 1, "reset returns to automatic slots")

click("OpenEditor")
addItem()
combat = true
click("SaveEditor")
assert(reloads == 0, "saving during combat must skip reloading the client UI")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
assert(reloads == 0 and frames.ForeverTouchRetrySave:IsShown())
click("RetrySave")
assert(reloads == 1 and disk.character.mobileSlots.left[1].id == 501, "a tap after combat saves the layout")
assert(frames.ForeverTouchLeftAction1.attributes.item == "item:501")

login(first, primary, nil)
local switcher = frames.ForeverTouchCycleSet
assert(not switcher:IsShown(), "the game needs no switcher for a single set")
click("OpenEditor")
click("AddSet")
addItem(502)
click("AddSet")
addItem(503)
click("PreviousSet")
click("SaveEditor")
assert(reloads == 1 and disk.character.mobileArcPage == 2)
assert(disk.character.mobileSlots.left[1].id == 501, "creating more sets preserves legacy slots")
assert(disk.character.mobileArcPositions.left.x == primary.mobileArcPositions.left.x, "creating more sets preserves arc positions")
assert(disk.character.mobileArcPages[1].slots.left[1].id == 502)
assert(disk.character.mobileArcPages[2].slots.left[1].id == 503)

local savedSets = disk
login(first, nil, savedSets.account)
switcher = frames.ForeverTouchCycleSet
assert(switcher:IsShown() and switcher:GetAttribute("page") == 2, "the backup restores the selected set")
assert(switcher.text == "Set 2 / 3" and switcher.refs.page2.shown)
assert(frames.ForeverTouchLeftSet2Action1.attributes.item == "item:502")
assert(not switcher.refs.page1.shown and not switcher.refs.page3.shown, "only the active set is visible")
combat = true
cycleSet(true)
assert(switcher:GetAttribute("page") == 2, "mouse down must not change the set")
cycleSet()
assert(switcher:GetAttribute("page") == 3 and switcher.refs.page3.shown and not switcher.refs.page2.shown)
assert(frames.ForeverTouchLeftSet3Action1.attributes.item == "item:503")
cycleSet()
assert(switcher:GetAttribute("page") == 1 and switcher.refs.page1.shown and not switcher.refs.page3.shown)
assert(frames.ForeverTouchLeftAction1.attributes.item == "item:501" and reloads == 0)
assert(ForeverTouchPreferences.mobileArcPage == nil, "the change is written by the next normal save")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")

click("OpenEditor")
click("NextSet")
click("RemoveSet")
click("CancelEditor")
assert(#ForeverTouchPreferences.mobileArcPages == 2 and switcher:GetAttribute("page") == 1)
click("OpenEditor")
click("NextSet")
click("RemoveSet")
click("SaveEditor")
assert(reloads == 1 and #ForeverTouchPreferences.mobileArcPages == 1)
assert(ForeverTouchPreferences.mobileArcPages[1].slots.left[1].id == 503 and not switcher.refs.page3.shown)
click("OpenEditor")
click("ResetEditor")
click("SaveEditor")
assert(frames.ForeverTouchLeftSet2Action1.attributes.type == nil, "reset clears only the selected extra set")
assert(ForeverTouchPreferences.mobileSlots.left[1].id == 501)

login(first, nil, nil)
click("OpenEditor")
click("AddSet")
addItem(504)
combat = true
click("SaveEditor")
assert(reloads == 0 and ForeverTouchPreferences.mobileArcPages[1].slots.left[1].id == 504)
assert(not frames.ForeverTouchLeftSet2Action1, "new secure buttons are prepared after combat")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
assert(frames.ForeverTouchLeftSet2Action1.attributes.item == "item:504")
assert(ForeverTouchPreferences.mobileSlots == nil, "adding a set preserves automatic slots on the first set")

login(first, primary)
click("OpenEditor")
click("DuplicateSet")
local copiedSet = ForeverTouchPreferences.mobileArcPages[1]
assert(ForeverTouchPreferences.mobileArcPage == 2 and reloads == 0, "copying selects and checkpoints the new set")
assert(copiedSet.slots.left[1].id == 501 and copiedSet.slots.right[1].id == 201)
assert(copiedSet.positions.left.x == primary.mobileArcPositions.left.x)
assert(copiedSet.positions.left.y == primary.mobileArcPositions.left.y)
replaceRight({ kind = "spell", id = 202 })
click("SaveEditor")
assert(reloads == 1 and disk.character.mobileSlots.right[1].id == 201, "editing the copy leaves its source intact")
assert(disk.character.mobileArcPages[1].slots.right[1].id == 202)
login(first, disk.character, disk.account)
assert(frames.ForeverTouchRightSet2Action1.attributes.spell == 202 and frames.ForeverTouchCycleSet.refs.page2.shown)

login(first)
click("OpenEditor")
click("DuplicateSet")
local copiedSpell = ForeverTouchPreferences.mobileArcPages[1].slots.right[1]
assert(copiedSpell.kind == "spell" and copiedSpell.id == 101, "copying captures automatically mirrored spells")
assert(ForeverTouchPreferences.mobileSlots == nil, "the first set still mirrors the desktop bars")
click("CancelEditor")
assert(reloads == 0 and ForeverTouchPreferences.mobileArcPages == nil, "discard rolls back the duplicated set")

actionTimers[1], spellTimers[201] = {}, {}
spellInfo[201] = secret
itemTimers[501] = { start = 100, duration = 60, enabled = 1 }
login(first, {
    mobileSlots = { left = {{ kind = "spell", id = 201 }}, right = {{ kind = "desktop", key = "spell:101:" }} },
    mobileArcPages = {{ slots = { left = {{ kind = "item", id = 501 }}, right = {} } }},
})
local spellButton = frames.ForeverTouchLeftAction1
local actionCooldown = frames.ForeverTouchRightAction1.cooldown
local itemCooldown = frames.ForeverTouchLeftSet2Action1.cooldown
assert(spellButton.cooldown.drawSwipe and spellButton.cooldown.hideNumbers == false)
assert(spellButton.cooldown.minimumCountdown == 2000, "brief global cooldowns should only show the sweep")
assert(rawget(spellButton.cooldown, "timer") == spellTimers[201], "spells use the native duration object")
assert(rawget(actionCooldown, "timer") == actionTimers[1], "mirrored action slots use the native duration object")

combat = true
chargeTimers[201] = {}
chargeInfo[201] = { currentCharges = secret, maxCharges = 2, isActive = true, cooldownDuration = secret }
event(nil, "SPELL_UPDATE_CHARGES")
assert(rawget(spellButton.cooldown, "timer") == chargeTimers[201], "restricted recharges still render during combat")
assert(spellButton.count.text == "")
chargeInfo[201].currentCharges = 1
event(nil, "SPELL_UPDATE_CHARGES")
assert(spellButton.count.text == 1, "a single remaining charge is shown alongside the recharge timer")

itemTimers[501].duration = 45
event(nil, "BAG_UPDATE_COOLDOWN")
assert(not rawget(itemCooldown, "timer"), "an inactive set does no timer work before it becomes visible")
cycleSet()
assert(itemCooldown.timer.duration == 45 and itemCooldown.timer.rate == 1, "switching sets refreshes item timers")
itemTimers[501].enabled = 0
event(nil, "BAG_UPDATE_COOLDOWN")
assert(rawget(itemCooldown, "timer") == nil, "an item cooldown on hold is cleared")

spellTimers[201], chargeTimers[201] = nil, nil
chargeInfo[201].isActive = false
spellInfo[201] = { startTime = 120, duration = 12, modRate = .75, isActive = true }
cycleSet()
assert(spellButton.cooldown.timer.duration == 12 and spellButton.cooldown.timer.rate == .75)
spellInfo[201].duration = secret
event(nil, "SPELL_UPDATE_COOLDOWN")
assert(rawget(spellButton.cooldown, "timer") == nil, "restricted numeric data is never fed to the widget")
spellInfo[201] = { startTime = 120, duration = 12, isActive = false }
event(nil, "SPELL_UPDATE_COOLDOWN")
assert(rawget(spellButton.cooldown, "timer") == nil, "inactive timers must not leave a stale sweep")

local spellBook = {
    [1] = { itemType = 1, spellID = 201, name = "Heal" },
    [6] = { itemType = 1, spellID = 301, name = "Smelting" },
    [7] = { itemType = 1, spellID = 302, name = "Toughness", isPassive = true },
    [10] = { itemType = 1, spellID = 303, name = "Fishing" },
    [13] = { itemType = 1, spellID = 301, name = "Smelting" },
}
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
    GetSpellBookItemInfo = function(slot, bank) assert(bank == 0); return spellBook[slot] end,
}
function GetProfessions() return nil, 31, nil, 54, nil, nil, 73 end
function GetProfessionInfo(index)
    local ranges = { [31] = {2, 5}, [54] = {1, 9}, [73] = {1, 12} }
    return nil, nil, nil, nil, table.unpack(ranges[index])
end

local miner = { name = "Miner", realm = "Silver Moon", realPicker = true }
local addon = login(nil, nil, nil, miner)
local professions = addon.actions.professionChoices()
assert(#professions == 2 and professions[1].id == 303 and professions[2].id == 301,
    "the profession list includes learned actions across gaps without passives or duplicates")
assert(bindings["CTRL-SHIFT-INSERT"] == "TOGGLEPROFESSIONBOOK")
assert(bindings["CTRL-SHIFT-END"] == "TOGGLEFRIENDSTAB")
assert(bindings["CTRL-SHIFT-PAGEUP"] == "TOGGLEGUILDTAB")
assert(bindings["CTRL-SHIFT-PAGEDOWN"] == "ForeverTouchGroupFinder")
assert(bindings["CTRL-SHIFT-DELETE"] == "TOGGLECOLLECTIONS")
local groupFinderOpens = 0
ToggleGroupFinderFrame = function() groupFinderOpens = groupFinderOpens + 1 end
local groupFinder = frames.ForeverTouchGroupFinder
groupFinder.scripts.OnClick(groupFinder, "LeftButton", true)
click("GroupFinder")
assert(groupFinderOpens == 1, "the panel delegates one toggle per tap to WoW")

click("OpenEditor")
local add = control("+")
add.scripts.OnClick(add)
local professionTab = control("Professions")
professionTab.scripts.OnClick(professionTab)
local found = false
for _, frame in ipairs(frames) do
    local binding = rawget(frame, "binding")
    if binding and binding.id == 301 and frame:IsShown() then
        found = true
        frame.scripts.OnClick(frame)
        break
    end
end
assert(found, "the profession picker offers a bindable Smelting button")
combat = true
click("SaveEditor")
assert(messages[1] == "Tap Save arcs after combat." and reloads == 0)
event(nil, "PLAYER_ENTERING_WORLD")
assert(#messages == 1, "changing zones is not confirmation of a pending save")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
click("RetrySave")
assert(reloads == 1 and disk.character.mobileSlots.left[1].id == 301)
local account = disk.account
local key = "character:0/silvermoon/miner"
assert(account[key].mobileSlots.left[1].id == 301)
assert(ForeverTouchProfiles[key] ~= ForeverTouchPreferences, "the account snapshot is independent of the live profile")
login(nil, nil, account, miner)
assert(frames.ForeverTouchLeftAction1.attributes.spell == 301 and messages[1] == "Arc layout saved.")
login(nil, nil, account, { name = "Miner", realm = "Other Realm" })
assert(not frames.ForeverTouchLeftAction1, "the same character name on another realm must not share a profile")

-- The new dock preserves existing layout and uses the same message model in both views.
local chatAddon = login(first, {useSavedChatLayout = true})
local post, history = chatAddon.chat.onMessage, chatAddon.chatHistory
local native = DEFAULT_CHAT_FRAME
local panel = frames.ForeverTouchChatPanel
local transcript = frames.ForeverTouchChatTranscript
local toggleChat = frames.ForeverTouchChatToggle
local dot = frames.ForeverTouchUnreadWhisper
local party = CreateFrame("Frame", "CompactPartyFrame", UIParent)
party:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -100)

local function assertBesideMap(frame)
    local point, relative, relativePoint, x = frame:GetPoint()
    assert(point == "TOPRIGHT" and relative == UIParent and relativePoint == "TOPRIGHT")
    assert(UIParent:GetWidth() + x < MinimapCluster:GetLeft(), "chat must sit to the left of the minimap")
    assert(UIParent:GetWidth() + x - frame:GetWidth() >= UIParent:GetWidth() * .22, "keep the group area free")
end

assertBesideMap(toggleChat)
assert(native:IsShown() and not native:IsVisible() and not panel:IsVisible())
post("CHAT_MSG_WHISPER", secret, secret)
assert(dot:IsShown() and not panel:IsVisible(), "restricted whispers still signal")
click("ChatToggle")
assert(frames.ForeverTouchChatStock:IsVisible(), "the native chat remains available for restricted whispers")
click("ChatStock")
assert(native:IsVisible() and not panel:IsVisible() and not dot:IsShown())
click("ChatToggle")
assert(panel:IsVisible() and not native:IsVisible())
click("ChatToggle")

post("CHAT_MSG_PARTY", "Party hello", "PartyFriend")
post("CHAT_MSG_RAID_LEADER", "Raid hello", "RaidLead")
post("CHAT_MSG_GUILD", "Guild hello", "GuildFriend")
post("CHAT_MSG_WHISPER", "A", "Aria-Moon")
post("CHAT_MSG_WHISPER", "B", "Aria-Sun")
post("CHAT_MSG_BN_WHISPER_INFORM", "My BN reply", "Aria-Moon")
post("CHAT_MSG_WHISPER_INFORM", "My realm reply", "Aria-Moon")
assert(dot:IsVisible() and not panel:IsVisible())
assert(registered.CHAT_MSG_WHISPER_INFORM and registered.CHAT_MSG_BN_WHISPER_INFORM)
assert(#history.contacts == 3, "cross-realm players and Battle.net contacts stay separate")
assert(history.peers["BN_WHISPER:aria-moon"].unread == 0, "outgoing whispers must never flag unread")
click("ChatToggle")
assertBesideMap(panel)
assert(panel:IsVisible() and dot:IsVisible(), "only the displayed conversation is marked read")
assert(#transcript.lines == 2 and transcript.lines[2]:find("My realm reply", 1, true))
click("FullscreenChat")
assert(panel:GetWidth() > UIParent:GetWidth() * .9 and not toggleChat:IsVisible())
click("ChatTabPARTY")
assert(#transcript.lines == 1 and transcript.lines[1]:find("Party hello", 1, true))
click("ChatTabRAID")
assert(#transcript.lines == 1 and transcript.lines[1]:find("Raid hello", 1, true))
click("ChatTabGUILD")
assert(#transcript.lines == 1 and transcript.lines[1]:find("Guild hello", 1, true))
click("ChatTabWHISPER")
assert(#transcript.lines == 0, "select a contact to read individual messages")
click("ChatContact3")
assert(#transcript.lines == 1 and transcript.lines[1]:find("Aria-Sun", 1, true) and not dot:IsShown())

local entry = CreateFrame("EditBox", "ChatFrame1EditBox", native)
entry:SetSize(390, 28)
entry:SetPoint("TOP", native, "BOTTOM", 0, -3)
entry.chatFrame = native
local active
ChatFrame_OpenChat = function()
    active = entry
    entry:SetFocus()
end
ChatEdit_GetActiveWindow = function() return active end
click("OpenChat")
assert(entry:GetParent() == panel and entry.chatType == "WHISPER" and entry.tellTarget == "Aria-Sun")
click("ChatTabGUILD")
assert(#transcript.lines == 1 and transcript.lines[1]:find("Aria-Sun", 1, true),
    "switching chats while typing cannot change or mislabel the recipient")
entry:ClearFocus()
assert(entry:GetParent() == native and entry:GetPoint() == "TOP" and entry:GetWidth() == 390)
click("ChatTabGUILD")
IsInGuild = function() return true end
click("OpenChat")
assert(entry.chatType == "GUILD")
entry:ClearFocus()
IsInGuild = function() return false end

local requests = 0
C_FriendList = {
    ShowFriends = function() requests = requests + 1 end,
    GetNumFriends = function() return 3 end,
    GetFriendInfoByIndex = function(index)
        return ({
            { name = "Offline-Sun", connected = false },
            { name = "Aria-Sun", connected = true, area = "Elwynn" },
            { name = secret, connected = true },
        })[index]
    end,
}
BNGetNumFriends = function() return 1 end
C_BattleNet = { GetFriendAccountInfo = function()
    return { bnetAccountID = 70, accountName = "BnetFriend", gameAccountInfo = { isOnline = true } }
end }
BNet_GetBNetIDAccount = function(name) return name == "BnetFriend" and 70 end
click("ChatTabFRIENDS")
assert(requests == 1)
assert(frames.ForeverTouchChatContact1.caption.text == "Aria-Sun")
assert(frames.ForeverTouchChatContact2.caption.text == "BnetFriend")
assert(frames.ForeverTouchChatContact3.caption.text == "Offline-Sun")
click("ChatContact1")
assert(#transcript.lines == 1 and transcript.lines[1]:find("Aria-Sun", 1, true))
click("ChatContact2")
click("OpenChat")
assert(entry.chatType == "BN_WHISPER" and entry.tellTarget == "BnetFriend")
entry:ClearFocus()
click("ChatContact3")
assert(not chatAddon.chat.open(), "an offline friend cannot be selected as a send target")
C_FriendList, C_BattleNet, BNGetNumFriends, BNet_GetBNetIDAccount = nil, nil, nil, nil

ChatFrame_OpenChat, ChatEdit_GetActiveWindow = nil, nil

click("CompactChat")
assertBesideMap(panel)
local resizeHandle = frames.ForeverTouchChatResize
resizeHandle.scripts.OnMouseDown(resizeHandle, "LeftButton")
panel:SetSize(490, 280)
resizeHandle.scripts.OnMouseUp(resizeHandle)
assert(ForeverTouchPreferences.mobileChatSize.width == 490 / 720)
assert(ForeverTouchPreferences.mobileChatSize.height == 280 / 720)
assert(reloads == 0, "resizing never reloads the game")

UIParent:SetSize(1200, 900)
MinimapCluster.left = 935
event(nil, "DISPLAY_SIZE_CHANGED")
assertBesideMap(toggleChat)
assertBesideMap(panel)
assert(party:GetPoint() == "TOPLEFT" and party:GetParent() == UIParent)

local conversation = CreateFrame("Frame", "ChatFrame4", UIParent)
table.insert(GENERAL_CHAT_DOCK.windows, conversation)
event(nil, "UPDATE_CHAT_WINDOWS")
assert(not conversation:IsVisible(), "new docked conversations follow the active mobile chat")
table.remove(GENERAL_CHAT_DOCK.windows)
event(nil, "UPDATE_CHAT_WINDOWS")
assert(conversation:GetParent() == UIParent, "an undocked window keeps its independent visibility")

local editing = true
EditModeManagerFrame = {IsEditModeActive = function() return editing end}
callbacks["EditMode.Enter"]()
assert(native:GetPoint() == "BOTTOMLEFT" and native:GetParent() == UIParent and not toggleChat:IsVisible())
native:ClearAllPoints()
native:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 35, -40)
editing = false
callbacks["EditMode.Exit"]()
assertBesideMap(panel)
assert(not native:IsVisible() and toggleChat:IsVisible())
EditModeManagerFrame = nil

combat = true
click("ChatToggle")
assert(not panel:IsVisible() and reloads == 0, "the toggle works during combat without reloading")
combat = false
click("ChatToggle")
local savedChat = copy(ForeverTouchPreferences)
event(nil, "PLAYER_LOGOUT")
assert(native:GetParent() == UIParent and native:GetPoint() == "TOPLEFT", "the saved native edit is preserved")
local restored = login(first, savedChat)
assert(frames.ForeverTouchChatPanel:IsVisible() and frames.ForeverTouchChatPanel:GetHeight() == 280)
assert(not frames.ForeverTouchUnreadWhisper:IsShown() and #restored.chatHistory.contacts == 0,
    "window size is saved, private messages are session only")

for accountID = 10, 11 do
    restored.chat.onMessage("CHAT_MSG_BN_WHISPER", "Hello", "Same name",
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, accountID)
end
assert(#restored.chatHistory.contacts == 2, "Battle.net accounts with identical labels stay separate")
for index = 1, 40 do restored.chat.onMessage("CHAT_MSG_WHISPER", "Hello", "Player-" .. index) end
assert(#restored.chatHistory.contacts == 32, "the in-memory inbox is bounded")
for index = 1, 200 do restored.chat.onMessage("CHAT_MSG_GUILD", "Hello " .. index, "GuildFriend") end
assert(#restored.chatHistory.lines.GUILD == 100 and #restored.chatHistory.lines.ALL == 180)

-- General mirrors the messages the native chat really shows, including text
-- written even when there is no CHAT_MSG event for the line.
local mirrored = login(first, {mobileChatOpen = true}, nil, {nativeMessages = {{"Joined [1. General]", .8, .6, .4}}})
local general = frames.ForeverTouchChatTranscript
assert(general.lines[1] == "Joined [1. General]", "channel membership must appear on the initial render")
local loot = "You receive loot: |cffffffff|Hitem:501|h[Practice Stone]|h|r."
DEFAULT_CHAT_FRAME:AddMessage(loot, .1, .8, .2)
mirrored.chat.onMessage("CHAT_MSG_LOOT", loot)
DEFAULT_CHAT_FRAME:AddMessage("You gain 30 experience.", .5, .5, 1)
assert(#general.lines == 3 and general.lines[2] == loot and general.lines[3] == "You gain 30 experience.",
    "loot, item links and system lines use the actual native transcript without duplicated events")
mirrored.chat.onMessage("CHAT_MSG_WHISPER", "hello", "Pat")
DEFAULT_CHAT_FRAME:AddMessage("[Pat] whispers: hello", 1, .4, 1)
assert(#general.lines == 4 and mirrored.chatHistory.contacts[1].name == "Pat")
mirrored.chat.setFullscreen(true)
assert(general.lines[2] == loot and #general.lines == 4, "the same native lines must be available in full chat")
DEFAULT_CHAT_FRAME:AddMessage(secret)
assert(#general.lines == 4 and frames.ForeverTouchChatStock:IsShown(), "restricted messages stay accessible in native chat")

-- A secure set switch must be recoverable from the account snapshot during play.
local twoSets = { revision = 8, mobileSlots = legacy.mobileSlots,
    mobileArcPages = {{ slots = { left = {}, right = {{ kind = "item", id = 501 }} } }} }
login(first, twoSets, nil, {name = "Tester", realm = "Silver Moon"})
combat = true
cycleSet()
local nameKey = "character:0/silvermoon/tester"
assert(ForeverTouchProfiles[first] and ForeverTouchProfiles[first].mobileArcPage == 2
    and ForeverTouchProfiles[nameKey].revision == 9 and reloads == 0, "set switch missed the character backup")
local accountAfterSwitch = copy(ForeverTouchProfiles)
login(first, twoSets, accountAfterSwitch)
assert(frames.ForeverTouchCycleSet:GetAttribute("page") == 2, "stale character file overrode the selected set")
cycleSet()
assert(reloads == 0, "switching sets during play must not reload the game UI")
click("SaveEditor") -- Also sent when the app goes to the background.
assert(reloads == 1 and disk.character.mobileArcPage == nil, "background save persists the latest active set")
local backgroundSave = disk
login(first, backgroundSave.character, backgroundSave.account)
assert(frames.ForeverTouchCycleSet:GetAttribute("page") == 1)

-- WoW may deliver these notifications together before the next rendered frame.
local addon = login(first, twoSets)
local refresh = addon.actions.refresh
local visits, timers = 0, {}
addon.actions.refresh = function(...) visits = visits + 1; return refresh(...) end
local immediate = C_Timer.After
C_Timer.After = function(_, run) timers[#timers + 1] = run end
for _, name in ipairs({"ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
        "SPELL_UPDATE_USABLE", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "BAG_UPDATE_DELAYED"}) do
    event(nil, name)
end
assert(#timers == 1 and visits == 0, "cooldown burst repeated work before the next frame")
timers[1]()
assert(visits == 1, "one visible button should be updated once for a seven-event burst")
C_Timer.After = immediate

-- A phone can close immediately after Done, before any queued timers run.
login(first, legacy)
timers = {}
C_Timer.After = function(_, run) timers[#timers + 1] = run end
click("OpenEditor")
replaceRight({kind = "spell", id = 202})
click("SaveEditor")
assert(reloads == 1 and disk.character.mobileSlots.right[1].id == 202, "Done must write before the game leaves the input handler")
local restartSave = disk
C_Timer.After = immediate
login(first, restartSave.character, restartSave.account)
assert(frames.ForeverTouchRightAction1.attributes.spell == 202 and messages[1] == "Arc layout saved.")

-- A reload can fail silently. Keep the edit pending and confirm only from the reloaded profile.
login(first, legacy)
local realReload = C_UI.Reload
C_UI.Reload = function() end
click("OpenEditor")
replaceRight({kind = "spell", id = 202})
click("SaveEditor")
assert(reloads == 0 and not disk and frames.ForeverTouchRetrySave:IsShown())
assert(messages[1] == "Arc changes pending. Try saving again or log out in game.")
C_UI.Reload = realReload
click("RetrySave")
assert(reloads == 1 and disk.character.mobileSlots.right[1].id == 202)

-- The Forever client can leave both SavedVariables globals nil in a fresh game
-- process, despite having written the real account and character files to disk.
local recoveredArc = {revision = 18, arcRevision = 17,
    mobileSlots = {left = {{kind = "item", id = 501}}, right = {}},
    mobileArcPage = 2, mobileArcPositions = {left = {x = .18, y = .42}},
    mobileArcPages = {
        {slots = {left = {{kind = "item", id = 502}}, right = {}}},
        {slots = {left = {{kind = "item", id = 503}}, right = {}}},
    },
}
local restoredId = "Player-70-AB"
local receipt = {profiles = {[restoredId] = recoveredArc}, characters = {}}
login(restoredId, nil, nil, {recoveredProfiles = receipt})
assert(frames.ForeverTouchCycleSet.text == "Set 2 / 3" and ForeverTouchPreferences.mobileArcPositions.left.x == .18)
assert(frames.ForeverTouchLeftAction1.attributes.item == "item:501"
    and frames.ForeverTouchLeftSet2Action1.attributes.item == "item:502"
    and frames.ForeverTouchLeftSet3Action1.attributes.item == "item:503", "a fresh process restores every set from the launcher")
login("Player-70-CD", nil, nil, {recoveredProfiles = receipt})
assert(not frames.ForeverTouchLeftAction1, "disk recovery must not apply the profile to another character")
login(restoredId, nil, nil, {name = "Händler", realm = "My Realm",
    recoveredProfiles = {profiles = {}, characters = {["70/händler-myrealm"] = recoveredArc}}})
assert(frames.ForeverTouchCycleSet.text == "Set 2 / 3", "legacy character-only saves use the numeric realm directory")

-- A Save-triggered UI reload still shares the temporary CVars with its old
-- Lua state, even when the game reloads without its SavedVariables globals.
local oldCVar, oldEncoding = C_CVar, C_EncodingUtil
local cvars, packet = {}, nil
C_CVar = {
    GetCVar = function(key) return cvars[key] end,
    SetCVar = function(key, value) cvars[key] = value end,
    RegisterCVar = function(key, value) cvars[key] = value end,
}
C_EncodingUtil = {
    SerializeCBOR = function(value) packet = copy(value); return ("x"):rep(460) end,
    EncodeBase64 = function(value) return value end,
    DecodeBase64 = function(value) return value end,
    DeserializeCBOR = function(value) if #value == 460 then return copy(packet) end end,
}
login(first, legacy)
click("OpenEditor")
replaceRight({kind = "spell", id = 203})
click("SaveEditor")
assert(reloads == 1 and cvars.foreverTouchSessionProfileCount == "3")
login(first, nil, nil)
assert(frames.ForeverTouchRightAction1.attributes.spell == 203 and messages[1] == "Arc layout restored after reload.")
login(second, nil, nil)
assert(not frames.ForeverTouchRightAction1 or frames.ForeverTouchRightAction1.attributes.spell ~= 203,
    "temporary reload data is scoped to the edited character")
C_CVar, C_EncodingUtil = oldCVar, oldEncoding

-- The swipe stays light while a charge is available, and items show the last unit and zero.
C_Item.GetItemCount = function() return 1 end
C_Item.IsUsableItem = function() return true end
chargeInfo[201] = { currentCharges = 1, maxCharges = 2 }
login(first, {mobileSlots = {left = {{kind = "spell", id = 201}}, right = {{kind = "item", id = 501}}}})
local charged, consumable = frames.ForeverTouchLeftAction1, frames.ForeverTouchRightAction1
assert(charged.count.text == 1 and charged.cooldown.swipeAlpha == .30 and consumable.count.text == 1)
chargeInfo[201].currentCharges = 0
C_Item.GetItemCount = function() return 0 end
event(nil, "SPELL_UPDATE_CHARGES")
assert(charged.count.text == 0 and charged.cooldown.swipeAlpha == .76 and charged.icon.red == .42)
assert(consumable.count.text == 0 and consumable.icon.red == .42)
C_Item.GetItemCount = function() return secret end
event(nil, "BAG_UPDATE_DELAYED")
assert(consumable.count.text == "" and consumable.icon.red == 1)
assert(charged.count.parent.parent == charged and charged.count.parent.level > charged.cooldown:GetFrameLevel())

-- The optional game frame limit must survive reload, preserve custom settings, and never raise a low limit.
local vars = {maxFPS = "120", useMaxFPS = "0"}
C_CVar = {GetCVar = function(key) return vars[key] end, SetCVar = function(key, value) vars[key] = tostring(value) end}
ForeverTouchFrameLimit = nil
local toggle = frames.ForeverTouchFrameLimit
toggle.scripts.OnClick(toggle, "LeftButton", true)
assert(vars.maxFPS == "120", "a key-down and key-up must only toggle once")
click("FrameLimit")
assert(vars.maxFPS == "30" and vars.useMaxFPS == "1" and ForeverTouchFrameLimit.limit == 120)
login(second, nil, nil)
click("FrameLimit")
assert(vars.maxFPS == "120" and vars.useMaxFPS == "0" and not ForeverTouchFrameLimit)
vars.maxFPS, vars.useMaxFPS = "24", "1"
click("FrameLimit")
assert(vars.maxFPS == "24" and not ForeverTouchFrameLimit)
vars.maxFPS = "90"
click("FrameLimit")
vars.maxFPS = "50"
click("FrameLimit")
assert(vars.maxFPS == "50" and not ForeverTouchFrameLimit)
C_CVar = nil
click("FrameLimit")
assert(messages[#messages] == "Frame limit unavailable on this client.")

-- Replacing a skill opens the picker on its existing page.
local addon = login(first, nil, nil)
addon.actions.spellChoices = function()
    local choices = {}
    for i = 1, 14 do choices[i] = {kind = "spell", id = i, name = "Spell " .. i} end
    return choices
end
assert(loadfile(source .. "/ForeverTouchPicker.lua"))("ForeverTouch", addon)
local picker = addon.createSlotPicker(UIParent)
picker:Open(function() end, "spell", {kind = "spell", id = 13})
assert(control("3 / 3") and control("Spell 13").parent.binding.id == 13)
picker:Open(function() end, "spell", {kind = "spell", id = 301})
assert(control("Smelting").parent.binding.id == 301 and not control("Professions").enabled,
    "replacing a profession spell returns to learned profession actions")

-- Repeated usable events can affect tint without changing any timers.
local profile = {mobileSlots = {left = {{kind = "spell", id = 201}}, right = {{kind = "item", id = 501}}}}
local refreshed = login(first, profile)
local spellButton, itemButton = frames.ForeverTouchLeftAction1, frames.ForeverTouchRightAction1
local writes, timerReads = 0, 0
for _, button in ipairs({spellButton, itemButton}) do
    local targets = {{button.icon, "SetVertexColor"}, {button.count, "SetText"}, {button.cooldown, "SetSwipeColor"},
        {button.cooldown, "SetCooldown"}, {button.cooldown, "SetCooldownFromDurationObject"}, {button.cooldown, "Clear"}}
    for _, pair in ipairs(targets) do
        local frame, method = pair[1], pair[2]
        local original = frame[method]
        frame[method] = function(self, ...)
            writes = writes + 1
            return original(self, ...)
        end
    end
end
local getItemCooldown = cooldownInfoForTest
cooldownInfoForTest = function() timerReads = timerReads + 1 end
for _ = 1, 20 do event(nil, "SPELL_UPDATE_USABLE") end
assert(writes == 0 and timerReads == 0, "unchanged usable events must avoid timer reads and visual writes")
C_Spell.IsSpellUsable = function() return false, true end
event(nil, "SPELL_UPDATE_USABLE")
assert(writes == 1 and spellButton.icon.red == .46 and timerReads == 0)
C_Spell.IsSpellUsable = nil

-- Numeric timers do not restart their swipe unless the values change.
itemTimers[501] = {start = 12, duration = 20, enabled = 1}
event(nil, "BAG_UPDATE_COOLDOWN")
assert(itemButton.cooldown.timer.start == 12 and itemButton.cooldown.timer.duration == 20)
writes, timerReads = 0, 0
for _ = 1, 20 do event(nil, "BAG_UPDATE_COOLDOWN") end
assert(writes == 0 and timerReads == 20, "unchanged numeric timers keep running on the native widget")
itemTimers[501].enabled = 0
event(nil, "BAG_UPDATE_COOLDOWN")
event(nil, "BAG_UPDATE_COOLDOWN")
assert(writes == 1 and not rawget(itemButton.cooldown, "timer"), "a disabled timer clears once")
cooldownInfoForTest = getItemCooldown

local visits, timerCallbacks = 0, {}
local oldRefresh = refreshed.actions.refresh
refreshed.actions.refresh = function(...) visits = visits + 1; return oldRefresh(...) end
C_Timer.After = function(_, run) timerCallbacks[#timerCallbacks + 1] = run end
event(nil, "SPELL_UPDATE_USABLE")
event(nil, "SPELLS_CHANGED")
event(nil, "SPELL_UPDATE_COOLDOWN")
assert(#timerCallbacks == 1 and visits == 0, "rebinding and refreshing share one next-frame callback")
timerCallbacks[1]()
assert(visits == 2, "rebinding updates each visible slot once")
C_Timer.After = immediate

-- Saved spell IDs may refer to ranks that no longer appear in the current spellbook view.
local knownRanks = {
    [201] = { name = "Heilung", text = "Rang 1" },
    [211] = { name = "Heilung", text = "Rang 2" },
    [205] = { name = "Heilung", text = "Rang 10" },
    [251] = { name = "Heilung", text = "Rang 11" },
    [254] = { name = "Heilung", text = "Rang 12" },
    [255] = { name = "Heilung", text = "Rang 13" },
    [256] = { name = "Heilung", text = "Rang 14" },
    [257] = { name = "Heilung" },
    [258] = { name = "Heilung", text = "Rang 16" },
    [301] = { name = "Smelting", text = "" },
    [401] = { name = "Anregen", text = "Rang 3" },
    [402] = { name = "Anregen", text = "Stufe 4" },
}
C_Spell.GetSpellName = function(id) return knownRanks[id] and knownRanks[id].name end
C_Spell.GetSpellSubtext = function(id) return knownRanks[id] and knownRanks[id].text end
local function spellEntry(id, lowRank)
    return { itemType = 1, actionID = id, spellID = id, name = knownRanks[id].name,
        subName = knownRanks[id].text, lowRank = lowRank }
end
local rankBook = { spellEntry(211), spellEntry(251), spellEntry(254), spellEntry(255),
    spellEntry(256), spellEntry(301), spellEntry(402) }
rankBook[2].isPassive, rankBook[3].isOffSpec, rankBook[4].itemType = true, true, 2
rankBook[5].notLearned = true
local scans = 0
C_SpellBook.GetNumSpellBookSkillLines = function() scans = scans + 1; return 1 end
C_SpellBook.GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #rankBook } end
C_SpellBook.GetSpellBookItemInfo = function(slot, bank) assert(bank == 0); return rankBook[slot] end
C_SpellBook.IsSpellKnown = function(id, bank) assert(bank == 0); return id ~= 256 end
C_SpellBook.IsSpellBookItemLowRank = function(slot, bank) assert(bank == 0); return rankBook[slot].lowRank == true end

local rankedProfile = {
    mobileSlots = { left = {{ kind = "spell", id = 201 }, { kind = "spell", id = 401 }},
        right = {{ kind = "item", id = 201 }} },
    mobileArcPositions = { left = { x = .25, y = .55 } },
    mobileArcPages = {{ slots = { left = {{ kind = "spell", id = 301 }, { kind = "desktop", key = "spell:201:" }},
        right = {{ kind = "spell", id = 201 }} }, positions = { right = { x = .4, y = .6 } } }},
}
local rankAddon = login(first, rankedProfile)
assert(registered.SPELLS_CHANGED)
assert(frames.ForeverTouchLeftAction1.attributes.spell == 211, "login upgrades a legacy ID outside the spellbook view")
assert(frames.ForeverTouchRightSet2Action1.attributes.spell == 211, "login also upgrades the inactive set")
assert(frames.ForeverTouchLeftSet2Action1.attributes.spell == 301, "unranked profession actions stay bound")
assert(frames.ForeverTouchLeftSet2Action2.attributes.spell == 211, "a saved desktop reference survives a desktop rank change")
assert(frames.ForeverTouchLeftAction2.attributes.spell == 401, "different subtext series are not treated as ranks of the same ability")
assert(frames.ForeverTouchRightAction1.attributes.item == "item:201", "an item with the same ID does not change")
assert(ForeverTouchPreferences.mobileArcPositions.left.y == .55
    and ForeverTouchPreferences.mobileArcPages[1].positions.right.x == .4)
assert(ForeverTouchProfiles[first].mobileArcPages[1].slots.right[1].id == 211 and reloads == 0)

local scansAtLogin = scans
event(nil, "SPELL_UPDATE_USABLE")
event(nil, "SPELL_UPDATE_COOLDOWN")
event(nil, "ACTIONBAR_SLOT_CHANGED")
assert(scans == scansAtLogin, "cooldowns and desktop changes must not rescan the spellbook")

rankBook[1].lowRank = true
rankBook[#rankBook + 1] = spellEntry(205)
spellTimers[205] = { source = "rank-10" }
combat = true
event(nil, "SPELLS_CHANGED")
assert(frames.ForeverTouchLeftAction1.attributes.spell == 211 and scans == scansAtLogin
    and ForeverTouchPreferences.mobileSlots.left[1].id == 211, "combat defers the rank update")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
assert(frames.ForeverTouchLeftAction1.attributes.spell == 205 and frames.ForeverTouchRightSet2Action1.attributes.spell == 205,
    "learning a higher rank rebinds both sets at the first safe time")
assert(frames.ForeverTouchLeftAction1.cooldown.timer == spellTimers[205], "the upgraded spell supplies its cooldown")
assert(ForeverTouchPreferences.mobileSlots.left[1].id == 205 and reloads == 0)
assert(scans == scansAtLogin + 1)
for _, choice in ipairs(rankAddon.actions.spellChoices()) do
    assert(choice.id ~= 211, "the spell picker shows the highest known rank")
end
local revision = ForeverTouchPreferences.revision
event(nil, "SPELLS_CHANGED")
assert(ForeverTouchPreferences.revision == revision, "rechecking a current profile is idempotent")

local rankTen = rankBook[#rankBook]
rankTen.lowRank = true
local rankFifteen = spellEntry(257)
rankBook[#rankBook + 1] = rankFifteen
event(nil, "SPELLS_CHANGED")
assert(frames.ForeverTouchLeftAction1.attributes.spell == 205, "a rank with unavailable text is not guessed")
knownRanks[257].text = "Rang 15"
event(nil, "SPELL_TEXT_UPDATE", 257)
assert(frames.ForeverTouchLeftAction1.attributes.spell == 257 and reloads == 0,
    "a trainer purchase with late spell data upgrades as soon as the rank can be read")

click("OpenEditor")
rankFifteen.lowRank = true
rankBook[#rankBook + 1] = spellEntry(258)
event(nil, "SPELLS_CHANGED")
assert(frames.ForeverTouchLeftAction1.attributes.spell == 257, "an open editor defers the rank upgrade")
click("CancelEditor")
assert(frames.ForeverTouchLeftAction1.attributes.spell == 258 and reloads == 0)
local upgraded = copy(ForeverTouchPreferences)
local upgradedAccount = copy(ForeverTouchProfiles)
login(first, upgraded, upgradedAccount)
assert(frames.ForeverTouchRightSet2Action1.attributes.spell == 258, "an upgraded inactive set survives logging in again")

-- An untouched default arc follows the current desktop layout and upgrades just its cast button.
GetActionInfo = function(slot) if slot == 1 then return "spell", 201 end end
login(first)
assert(frames.ForeverTouchRightAction1.attributes.spell == 258
    and not frames.ForeverTouchRightAction1.attributes.action
    and not ForeverTouchPreferences.mobileSlots and reloads == 0)
assert(select(2, GetActionInfo(1)) == 201, "the desktop action still has its original rank")

-- A later launcher can have a newer chat-only profile alongside the older arc backup.
local older = { revision = 8, mobileSlots = { left = {{ kind = "spell", id = 301 }}, right = {} } }
local newer = { revision = 9, mobileChatOpen = true, mobileChatSize = { width = .7, height = .37 } }
login(first, newer, { [first] = older })
assert(ForeverTouchPreferences.mobileChatOpen and ForeverTouchPreferences.mobileSlots.left[1].id == 301)
assert(ForeverTouchProfiles[first].mobileSlots.left[1].id == 301)
login(first, { revision = 10, arcRevision = 10 }, { [first] = older })
assert(not ForeverTouchPreferences.mobileSlots, "an intentional arc reset survives migration")

-- Android commits the frame before acknowledging it. WoW never writes the
-- SavedVariables or leaves the editor while the app's write is still pending.
local session = "0123456789abcdef"
GetTimePreciseSec = function() return 123.456 end
login(first, legacy, nil, { name = "Trainer", realm = "Trial", arcSession = session })
click("OpenEditor")
replaceRight({kind = "item", id = 508})
local after = C_Timer.After
C_Timer.After = function(seconds, callback) if seconds == 0 then after(seconds, callback) end end
click("SaveEditor")
assert(reloads == 0 and not disk and frames.ForeverTouchRightAction1.attributes.spell ~= 508)
local raster, transferFrame = {}, nil
for _, frame in ipairs(frames) do
    if frame:IsVisible() and type(frame.rasterColor) == "number" then
        local parent = frame:GetParent()
        if parent and parent:GetFrameStrata() == "TOOLTIP" and parent:GetWidth() == UIParent:GetWidth() / 2 then
            raster[#raster + 1] = frame.rasterColor
            transferFrame = parent
        end
    end
end
assert(transferFrame and #raster > 80)
local data = {}
for i = 17, #raster, 2 do data[#data + 1] = string.char(raster[i] * 16 + raster[i + 1]) end
data = table.concat(data)
assert(data:sub(1, 3) == "FT\1" and data:sub(29):match('508'), "the selected replacement is in the frame")
local fixture = os.getenv("FOREVER_TOUCH_ARC_FRAME")
if fixture then
    local output = assert(io.open(fixture, "wb"))
    output:write(string.char(table.unpack(raster)))
    output:close()
end
click("AcceptArcSave")
assert(reloads == 0 and not disk and not transferFrame:IsShown())
assert(frames.ForeverTouchRightAction1.attributes.item == "item:508", "the receipt applies the arc without reloading")
C_Timer.After = after

-- The Android composer keeps its draft in Android and sends one message to the
-- selected WoW chat. Keyboard layout changes never open or submit the stock editor.
local fullscreenChat = login(first, nil, nil, {nativeKeyboard = true})
click("FullscreenChat")
local bridge = frames.ForeverTouchChatTransport
local mobilePanel = frames.ForeverTouchChatPanel
local mobileTranscript = frames.ForeverTouchChatTranscript
local sendingBox = CreateFrame("EditBox", "ChatFrame1EditBox", DEFAULT_CHAT_FRAME)
sendingBox:SetSize(390, 28)
sendingBox:SetPoint("TOP", DEFAULT_CHAT_FRAME, "BOTTOM", 0, -3)
local delivered, opened = {}, 0
sendingBox:SetScript("OnEnterPressed", function(self)
    assert(hardwareEvent, "the message is dispatched during the keyboard event")
    delivered[#delivered + 1] = { text = self:GetText(), kind = self.chatType, target = self.tellTarget }
    self:ClearFocus()
end)
ChatFrame_OpenChat = function()
    opened = opened + 1
    sendingBox:SetFocus()
    return sendingBox
end
ChatEdit_GetActiveWindow = function() return sendingBox:HasFocus() and sendingBox or nil end
C_Timer.After = function(seconds, callback) if seconds == 0 then after(seconds, callback) end end
local function inputPacket(packet)
    click("NativeChatTransfer")
    assert(bridge:IsShown() and bridge:HasFocus())
    hardwareEvent = true
    for i = 1, #packet do
        bridge:SetText(packet:sub(1, i))
        bridge.scripts.OnTextChanged(bridge, true)
    end
    hardwareEvent = false
end
local function messagePacket(message)
    return ("m%03d"):format(#message) .. message:gsub(".", function(byte) return ("%02x"):format(byte:byte()) end)
end

fullscreenChat.chat.onMessage("CHAT_MSG_SAY", "A visible chat message", "Lina")
inputPacket("h0410")
assert(mobilePanel:GetHeight() < 720 * .41 and #mobileTranscript.lines == 1 and opened == 0,
    "the chat panel reflows above the keyboard and preserves the transcript")
inputPacket("h0890")
assert(mobilePanel:GetHeight() > 720 * .7 and #mobileTranscript.lines == 1 and opened == 0)

local greeting = " Grüße! 😀 "
inputPacket(messagePacket(greeting))
assert(#delivered == 1 and delivered[1].text == greeting and delivered[1].kind == "SAY")
assert(not bridge:IsShown() and mobilePanel:IsShown() and reloads == 0)

fullscreenChat.chat.onMessage("CHAT_MSG_WHISPER", "An invitation", "Aria-Sun")
click("ChatTabWHISPER")
inputPacket(messagePacket("No recipient yet"))
assert(#delivered == 1 and not bridge:IsShown(), "a private message needs a selected contact")
click("ChatContact1")
inputPacket(messagePacket("Danke!"))
assert(#delivered == 2 and delivered[2].kind == "WHISPER" and delivered[2].target == "Aria-Sun")

click("ChatTabGUILD")
inputPacket(messagePacket("No guild"))
assert(#delivered == 2, "unavailable channels never send to Say instead")
IsInGuild = function() return true end
inputPacket("m00663686174")
assert(#delivered == 2, "a truncated packet never sends a message")
inputPacket(messagePacket("Gildenchat"))
assert(#delivered == 3 and delivered[3].kind == "GUILD")
click("CompactChat")
inputPacket(messagePacket("Wrong screen"))
assert(#delivered == 3, "a fullscreen message arriving after a mode change is discarded")
local compactGreeting = " Grüße im kleinen Chat! "
inputPacket("c" .. messagePacket(compactGreeting):sub(2))
assert(#delivered == 4 and delivered[4].text == compactGreeting and delivered[4].kind == "GUILD",
    "the compact composer preserves Unicode and the selected channel")
IsInGuild = function() return false end
ChatFrame_OpenChat, ChatEdit_GetActiveWindow = nil, nil
C_Timer.After = after

print("Passed: Android arc save and recovery, spell ranks and cooldowns, picker paging, professions, full chat keyboard layout and message routing, standard chat, friends, and frame limiting.")
