-- Run with: lua tools/test_forever_touch_profiles.lua [add-on source directory]
local source = (arg and arg[1]) or "app/src/main/assets/ForeverTouch"
local frames, event, choose, player, combat, reloads, disk
local playerName, playerRealm, bindings, callbacks, messages
local secureClick

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, element in pairs(value) do result[key] = copy(element) end
    return result
end

CopyTable = copy
unpack = table.unpack

local function guarded(frame)
    assert(not (combat and frame.protected and not secureClick), "insecure change to a protected frame during combat")
end

local methods = {
    SetScript = function(self, name, callback)
        self.scripts[name] = callback
        if name == "OnEvent" then event = callback end
    end,
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
    GetFrameLevel = function() return 1 end,
    SetText = function(self, value) self.text = value end,
    SetSwipeColor = function(self, _, _, _, alpha) self.swipeAlpha = alpha end,
    SetVertexColor = function(self, red) self.red = red end,
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
    Clear = function(self) self.timer = nil end,
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
methods.CreateTexture = function(self) return CreateFrame("Texture", nil, self) end
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
function IsInGuild() return false end
C_Timer = { After = function(_, callback) callback() end }
C_UI = {
    Reload = function()
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
    bindings, callbacks, messages = {}, {}, {}
    secureClick, choose = false, nil
    ForeverTouchPreferences, ForeverTouchProfiles = nil, nil
    UIParent = CreateFrame("Frame", "UIParent")
    UIParent:SetSize(1536, 720)
    DEFAULT_CHAT_FRAME = CreateFrame("Frame", "ChatFrame1", UIParent)
    DEFAULT_CHAT_FRAME:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 20)
    DEFAULT_CHAT_FRAME:SetSize(430, 180)
    UIErrorsFrame = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    local addon = {
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
    assert(loadfile(source .. "/ForeverTouchActions.lua"))("ForeverTouch", addon)
    if options.realPicker then assert(loadfile(source .. "/ForeverTouchPicker.lua"))("ForeverTouch", addon) end
    assert(loadfile(source .. "/ForeverTouchMobileLayout.lua"))("ForeverTouch", addon)
    -- The client loads SavedVariables after running the add-on's Lua chunks.
    ForeverTouchPreferences, ForeverTouchProfiles = copy(characterSaved), copy(accountSaved)
    event(nil, "PLAYER_LOGIN")
    event(nil, "PLAYER_ENTERING_WORLD")
    return addon
end

local function click(name)
    local frame = frames["ForeverTouch" .. name]
    frame.scripts.OnClick(frame)
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
assert(reloads == 1 and disk.character.mobileSlots.left[1].id == 501, "combat saves flush when combat ends")
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
assert(messages[1] == "Arc layout will save after combat." and reloads == 0)
event(nil, "PLAYER_ENTERING_WORLD")
assert(#messages == 1, "changing zones is not confirmation of a pending save")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
assert(reloads == 1 and disk.character.mobileSlots.left[1].id == 301)
local account = disk.account
local key = "character:0/silvermoon/miner"
assert(account[key].mobileSlots.left[1].id == 301)
assert(ForeverTouchProfiles[key] ~= ForeverTouchPreferences, "the account snapshot is independent of the live profile")
login(nil, nil, account, miner)
assert(frames.ForeverTouchLeftAction1.attributes.spell == 301 and messages[1] == "Arc layout saved.")
login(nil, nil, account, { name = "Miner", realm = "Other Realm" })
assert(not frames.ForeverTouchLeftAction1, "the same character name on another realm must not share a profile")

local chat = DEFAULT_CHAT_FRAME
local function assertTopLeft(frame, y)
    local point, relative, relativePoint, x, offset = frame:GetPoint()
    assert(point == "TOPLEFT" and relative == UIParent and relativePoint == "TOPLEFT"
        and x > 0 and math.abs(offset - y) < .001, "chat should use the upper-left corner")
end

assertTopLeft(chat, -162)
local idleWidth, idleHeight = chat:GetSize()
local entry = CreateFrame("EditBox", nil, UIParent)
entry:SetSize(390, 28)
entry:SetPoint("TOP", chat, "BOTTOM", 0, -3)
entry.chatFrame = chat
entry.foreverTouchOriginalPoints, entry.foreverTouchHooks = false, false
entry.HasFocus = function() return true end
ChatFrameUtil = { GetActiveWindow = function() return entry end, OpenChat = function() return entry end }
click("OpenChat")
assertTopLeft(chat, -162)
assertTopLeft(entry, -105.84)
assert(chat:GetWidth() > idleWidth)
entry.scripts.OnEditFocusLost(entry)
assertTopLeft(chat, -162)
assert(chat:GetWidth() == idleWidth and chat:GetHeight() == idleHeight and entry:GetPoint() == "TOP")

UIParent:SetSize(1920, 900)
event(nil, "DISPLAY_SIZE_CHANGED")
assertTopLeft(chat, -202.5)
-- WoW may reapply its saved layout during a zone or layout change.
chat:ClearAllPoints()
chat:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 20)
event(nil, "EDIT_MODE_LAYOUTS_UPDATED")
assertTopLeft(chat, -202.5)

local editing = true
EditModeManagerFrame = {IsEditModeActive = function() return editing end}
callbacks["EditMode.Enter"]()
assert(chat:GetPoint() == "BOTTOMLEFT", "WoW edit mode sees the game's real layout")
callbacks["EditMode.SavedLayouts"]()
editing = false
callbacks["EditMode.Exit"]()
assertTopLeft(chat, -202.5)
assert(not ForeverTouchPreferences.useSavedChatLayout, "saving unrelated edits keeps the mobile default")

editing = true
callbacks["EditMode.Enter"]()
chat:ClearAllPoints()
chat:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -45, -110)
callbacks["EditMode.SavedLayouts"]()
editing = false
callbacks["EditMode.Exit"]()
event(nil, "UI_SCALE_CHANGED")
assert(chat:GetPoint() == "TOPRIGHT" and ForeverTouchPreferences.useSavedChatLayout,
    "a newly saved WoW chat position remains customizable")
click("OpenChat")
assertTopLeft(chat, -202.5)
entry.scripts.OnEditFocusLost(entry)
assert(chat:GetPoint() == "TOPRIGHT", "typing restores the explicitly saved chat position")
EditModeManagerFrame = nil

login(first)
assertTopLeft(DEFAULT_CHAT_FRAME, -162)
DEFAULT_CHAT_FRAME.protected = true
combat = true
event(nil, "DISPLAY_SIZE_CHANGED")
combat = false
event(nil, "PLAYER_REGEN_ENABLED")
assertTopLeft(DEFAULT_CHAT_FRAME, -162)

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

-- During an open edit session an incoming save cannot reload over the user's next edit.
login(first, legacy)
timers = {}
C_Timer.After = function(_, run) timers[#timers + 1] = run end
click("OpenEditor")
replaceRight({kind = "item", id = 501})
click("SaveEditor")
click("OpenEditor")
for _, run in ipairs(timers) do run() end
assert(reloads == 0)
replaceRight({kind = "spell", id = 202})
click("SaveEditor")
local finish = timers[#timers]
finish()
assert(reloads == 1 and disk.character.mobileSlots.right[1].id == 202)
C_Timer.After = immediate

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

-- Direct channel buttons follow membership changes while typing. A legacy open may return nil.
ChatFrameUtil = nil
local active
local entry = CreateFrame("EditBox", nil, UIParent)
entry:SetSize(380, 30)
entry:SetPoint("TOP", UIParent, "TOP", 0, -10)
entry.chatFrame, entry.foreverTouchOriginalPoints, entry.foreverTouchHooks = DEFAULT_CHAT_FRAME, false, false
entry.HasFocus = function() return true end
ChatFrame_OpenChat = function() active = entry end
ChatEdit_GetActiveWindow = function() return active end
click("OpenChat")
assert(rawget(entry, "foreverTouchHooks") == true and control("Guild").enabled == false)
IsInGuild = function() return true end
event(nil, "PLAYER_GUILD_UPDATE")
assert(control("Guild").enabled)
local scrolled = false
entry.chatFrame.ScrollToBottom = function() scrolled = true end
control("Latest").scripts.OnClick()
assert(scrolled, "latest must scroll the active chat window")
entry.scripts.OnEditFocusLost(entry)

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

print("Passed: arc autosave and recovery, saved switches, cooldowns and charges, item counts, event batching, picker paging, professions, chat and frame limiting.")
