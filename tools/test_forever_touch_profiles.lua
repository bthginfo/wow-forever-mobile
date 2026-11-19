-- Run with: lua tools/test_forever_touch_profiles.lua [add-on source directory]
local source = (arg and arg[1]) or "app/src/main/assets/ForeverTouch"
local frames, event, choose, player, combat, reloads, disk
local secureClick

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, element in pairs(value) do result[key] = copy(element) end
    return result
end

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
    SetText = function(self, value) self.text = value end,
    GetName = function(self) return self.name end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    GetSize = function(self) return self.width, self.height end,
    SetSize = function(self, width, height) guarded(self); self.width, self.height = width, height end,
    SetScale = function(self, scale) guarded(self); self.scale = scale end,
    GetEffectiveScale = function(self) return rawget(self, "scale") or 1 end,
    GetLeft = function(self) return rawget(self, "left") or 0 end,
    GetBottom = function(self) return rawget(self, "bottom") or 0 end,
    SetPoint = function(self, ...) guarded(self); self.point = {...} end,
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
function InCombatLockdown() return combat end
function GetActionInfo(slot) if slot == 1 then return "spell", 101 end end
function GetActionTexture(slot) if slot == 1 then return 1001 end end
function SetOverrideBinding() end
function SetOverrideBindingClick() end
function SaveBindings() error("The HUD must leave WoW's keyboard bindings alone") end
C_Timer = { After = function(_, callback) callback() end }
C_UI = {
    Reload = function()
        reloads = reloads + 1
        disk = { character = copy(ForeverTouchPreferences), account = copy(ForeverTouchProfiles) }
    end,
}
C_Spell = { GetSpellName = tostring }

local function login(guid, characterSaved, accountSaved)
    frames, player, combat, reloads, disk = {}, guid, false, 0, nil
    secureClick, choose = false, nil
    ForeverTouchPreferences, ForeverTouchProfiles = nil, nil
    UIParent = CreateFrame("Frame", "UIParent")
    UIParent:SetSize(1536, 720)
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
    assert(loadfile(source .. "/ForeverTouchMobileLayout.lua"))("ForeverTouch", addon)
    -- The client loads SavedVariables after running the add-on's Lua chunks.
    ForeverTouchPreferences, ForeverTouchProfiles = copy(characterSaved), copy(accountSaved)
    event(nil, "PLAYER_LOGIN")
    event(nil, "PLAYER_ENTERING_WORLD")
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
print("Forever Touch profiles passed: persistence, migration, independent arc sets, editor changes and secure switching.")
