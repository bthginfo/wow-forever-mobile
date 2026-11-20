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
local frameType = { __index = function(_, key) return methods[key] or noop end }
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
assert(itemCooldown.timer.duration == 60, "an inactive set waits until it becomes visible")
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
chat:ClearAllPoints()
chat:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -45, -110)
chat:SetSize(390, 142)
callbacks["EditMode.Exit"]()
event(nil, "UI_SCALE_CHANGED")
assert(chat:GetPoint() == "TOPRIGHT" and chat:GetWidth() == 390, "the game owns the saved chat position")
local entry = CreateFrame("EditBox", nil, UIParent)
entry:SetSize(390, 28)
entry:SetPoint("TOP", chat, "BOTTOM", 0, -3)
entry.chatFrame = chat
entry.foreverTouchOriginalPoints, entry.foreverTouchHooks = false, false
entry.HasFocus = function() return true end
ChatFrameUtil = { GetActiveWindow = function() return entry end, OpenChat = function() return entry end }
click("OpenChat")
assert(chat:GetPoint() == "TOPLEFT" and entry:GetPoint() == "TOPLEFT", "typing temporarily brings chat above the keyboard")
entry.scripts.OnEditFocusLost(entry)
local point, relative, relativePoint, x, y = chat:GetPoint()
assert(point == "TOPRIGHT" and relative == UIParent and relativePoint == "TOPRIGHT" and x == -45 and y == -110)
assert(chat:GetWidth() == 390 and chat:GetHeight() == 142 and entry:GetPoint() == "TOP")

print("Forever Touch passed: profile persistence, arc sets, secure switching, cooldowns, professions and chat placement.")
