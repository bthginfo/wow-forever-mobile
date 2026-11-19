-- Run with: lua tools/test_forever_touch_profiles.lua [add-on source directory]
local source = (arg and arg[1]) or "app/src/main/assets/ForeverTouch"
local frames, event, choose, player, combat, reloads, disk

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, element in pairs(value) do result[key] = copy(element) end
    return result
end

local methods = {
    SetScript = function(self, name, callback)
        self.scripts[name] = callback
        if name == "OnEvent" then event = callback end
    end,
    SetAttribute = function(self, name, value) self.attributes[name] = value end,
    GetAttribute = function(self, name) return self.attributes[name] end,
    SetText = function(self, value) self.text = value end,
    GetName = function(self) return self.name end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    GetSize = function(self) return self.width, self.height end,
    SetSize = function(self, width, height) self.width, self.height = width, height end,
    SetScale = function(self, scale) self.scale = scale end,
    GetEffectiveScale = function(self) return rawget(self, "scale") or 1 end,
    GetLeft = function(self) return rawget(self, "left") or 0 end,
    GetBottom = function(self) return rawget(self, "bottom") or 0 end,
    SetPoint = function(self, ...) self.point = {...} end,
    IsShown = function(self) return self.shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, shown) self.shown = shown end,
}

local function noop() end
local frameType = { __index = function(_, key) return methods[key] or noop end }
function CreateFrame(_, name, parent)
    local frame = setmetatable({ name = name, parent = parent, shown = false, scripts = {}, attributes = {} }, frameType)
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
    ForeverTouchPreferences, ForeverTouchProfiles = nil, nil
    UIParent = CreateFrame("Frame", "UIParent")
    UIParent:SetSize(1536, 720)
    local addon = {
        createSlotPicker = function()
            local picker = CreateFrame("Frame")
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

local function addItem()
    local add = control("+")
    add.scripts.OnClick(add)
    choose({ kind = "item", id = 501 })
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
print("Forever Touch profiles passed: legacy data, save/relog, file fallback, character separation, cancel, reset and combat.")
