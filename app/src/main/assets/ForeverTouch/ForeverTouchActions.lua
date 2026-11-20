local name, addon = ...
local Actions = {}
addon.actions = Actions

local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local language = getMetadata and getMetadata(name, "X-ForeverTouch-Language")
addon.german = language == "de" or (language ~= "en" and GetLocale() == "deDE")

local LIMIT = 180
local isSecret = issecretvalue or function() return false end
local actionBar = C_ActionBar or {}
local spell = C_Spell or {}
local item = C_Item or {}
local getAction = GetActionInfo or actionBar.GetActionInfo
local getTexture = GetActionTexture or actionBar.GetActionTexture
local getPage = GetActionBarPage or actionBar.GetActionBarPage
local getCount = GetActionCount or actionBar.GetActionCount
local isUsable = IsUsableAction or actionBar.IsUsableAction
local fallbackIcon = 134400

local cooldowns = {
    action = {
        info = actionBar.GetActionCooldown or GetActionCooldown,
        duration = actionBar.GetActionCooldownDuration,
        charges = actionBar.GetActionCharges,
        recharge = actionBar.GetActionChargeDuration,
    },
    spell = {
        info = spell.GetSpellCooldown or GetSpellCooldown,
        duration = spell.GetSpellCooldownDuration,
        charges = spell.GetSpellCharges,
        recharge = spell.GetSpellChargeDuration,
    },
    item = { info = item.GetItemCooldown or GetItemCooldown },
}

Actions.sides = { "left", "right" }
Actions.limit = LIMIT

local function number(value)
    if not isSecret(value) and type(value) == "number" then return value end
    return 0
end

local function validID(value)
    local id = number(value)
    return id > 0 and id < math.huge and id % 1 == 0
end

function Actions.copyProfile(profile)
    local copy, remaining = { left = {}, right = {} }, LIMIT
    if type(profile) ~= "table" then return copy end
    for _, side in ipairs(Actions.sides) do
        if type(profile[side]) == "table" then
            for _, binding in ipairs(profile[side]) do
                if remaining == 0 then return copy end
                if type(binding) == "table" then
                    local kind = binding.kind
                    if (kind == "spell" or kind == "item") and validID(binding.id) then
                        copy[side][#copy[side] + 1] = { kind = kind, id = binding.id }
                        remaining = remaining - 1
                    elseif kind == "desktop" and type(binding.key) == "string" then
                        copy[side][#copy[side] + 1] = { kind = kind, key = binding.key }
                        remaining = remaining - 1
                    end
                end
            end
        end
    end
    return copy
end

function Actions.desktop()
    local ordered, records = {}, {}
    if not getAction or not getTexture then return ordered, records end
    local function append(slot)
        local kind, id, subtype = getAction(slot)
        if isSecret(kind) or isSecret(id) or isSecret(subtype) or not kind or not id then return end
        local texture = getTexture(slot)
        if not isSecret(texture) and not texture then return end
        local key = kind .. ":" .. tostring(id) .. ":" .. tostring(subtype or "")
        if records[key] then return end
        records[key] = { slot = slot, kind = kind, id = id, subtype = subtype }
        ordered[#ordered + 1] = key
    end

    local page = getPage and number(getPage()) or 1
    local first = (math.max(1, math.min(6, page)) - 1) * 12 + 1
    for slot = first, first + 11 do append(slot) end
    for slot = 1, LIMIT do append(slot) end
    return ordered, records
end

function Actions.splitDesktop(ordered, records, preferred)
    local profile, used, count = { left = {}, right = {} }, {}, 0
    local function append(key)
        if not records[key] or used[key] then return end
        count = count + 1
        local side = count % 2 == 1 and profile.right or profile.left
        side[#side + 1] = { kind = "desktop", key = key }
        used[key] = true
    end
    if type(preferred) == "table" then
        for _, key in ipairs(preferred) do append(key) end
    end
    for _, key in ipairs(ordered) do append(key) end
    return profile
end

function Actions.independentProfile(profile, records)
    local copy = Actions.copyProfile(profile)
    for _, side in ipairs(Actions.sides) do
        for index, binding in ipairs(copy[side]) do
            local record = binding.kind == "desktop" and records[binding.key]
            if record and validID(record.id) and (record.kind == "item" or
                    (record.kind == "spell" and record.subtype ~= "pet" and record.subtype ~= "flyout")) then
                copy[side][index] = { kind = record.kind, id = record.id }
            end
        end
    end
    return copy
end

local function shownIcon(texture)
    if isSecret(texture) then return texture end
    return texture or fallbackIcon
end

function Actions.texture(binding, records)
    local kind, id = binding.kind, binding.id
    if kind == "spell" and spell.GetSpellTexture then return shownIcon(spell.GetSpellTexture(id)) end
    if kind == "item" and item.GetItemIconByID then return shownIcon(item.GetItemIconByID(id)) end
    local record = records[binding.key]
    if record and getTexture then return shownIcon(getTexture(record.slot)) end
    return fallbackIcon
end

function Actions.name(binding, records)
    local kind, id = binding.kind, binding.id
    local record = kind == "desktop" and records[binding.key]
    if record then kind, id = record.kind, record.id end
    if kind == "spell" and spell.GetSpellName then return spell.GetSpellName(id) end
    if kind == "item" and item.GetItemNameByID then return item.GetItemNameByID(id) end
    if kind == "macro" and GetMacroInfo then return GetMacroInfo(id) end
end

function Actions.bind(button, binding, records)
    local kind = binding and binding.kind
    local record = kind == "desktop" and records[binding.key]
    local slot = record and record.slot or nil
    local spellID = kind == "spell" and binding.id or nil
    local itemName = kind == "item" and ("item:" .. binding.id) or nil
    local actionType = slot and "action" or spellID and "spell" or itemName and "item" or nil
    button.binding = binding
    button:SetAttribute("type", actionType)
    button:SetAttribute("action", slot)
    button:SetAttribute("spell", spellID)
    button:SetAttribute("item", itemName)
end

local function setNumericCooldown(frame, start, duration, rate)
    if isSecret(start) or isSecret(duration) or isSecret(rate)
            or number(start) <= 0 or number(duration) <= 0 then return false end
    local speed = number(rate)
    frame:SetCooldown(start, duration, speed > 0 and speed or 1)
    return true
end

local function setDurationCooldown(frame, getDuration, id)
    if not getDuration or not frame.SetCooldownFromDurationObject then return false end
    local duration = getDuration(id)
    if isSecret(duration) or not duration then return false end
    -- WoW can render the opaque timer even when Lua cannot read the underlying seconds.
    frame:SetCooldownFromDurationObject(duration, true)
    return true
end

local function refreshCooldown(frame, source, id, charges)
    if charges and not isSecret(charges.isActive) and charges.isActive ~= false then
        if charges.isActive and setDurationCooldown(frame, source.recharge, id) then return end
        if setNumericCooldown(frame, charges.cooldownStartTime, charges.cooldownDuration, charges.chargeModRate) then return end
    end
    if source then
        if setDurationCooldown(frame, source.duration, id) then return end
        if source.info then
            local start, duration, enabled, rate = source.info(id)
            if not isSecret(start) and type(start) == "table" then
                enabled = start.isActive
                if not isSecret(enabled) and enabled == nil then enabled = start.isEnabled end
                start, duration, rate = start.startTime, start.duration, start.modRate
            end
            if not isSecret(enabled) and enabled ~= false and enabled ~= 0
                    and setNumericCooldown(frame, start, duration, rate) then return end
        end
    end
    frame:Clear()
end

function Actions.refresh(button, records, updateIcon)
    local binding = button.binding
    if not binding then return end
    if updateIcon then button.icon:SetTexture(Actions.texture(binding, records)) end

    local count, usable, noPower
    local slot = button:GetAttribute("action")
    local id = slot or binding.id
    local source = cooldowns[slot and "action" or binding.kind]
    local charges = source and source.charges and source.charges(id)
    if isSecret(charges) or type(charges) ~= "table" then charges = nil end
    if slot then
        if getCount then count = getCount(slot) end
        if isUsable then usable, noPower = isUsable(slot) end
    elseif binding.kind == "spell" then
        if spell.IsSpellUsable then usable, noPower = spell.IsSpellUsable(binding.id) end
    elseif binding.kind == "item" then
        if item.GetItemCount then count = item.GetItemCount(binding.id) end
        if item.IsUsableItem then usable = item.IsUsableItem(binding.id) end
    else
        usable = false
    end

    count = number(count)
    if charges and number(charges.maxCharges) > 1 and not isSecret(charges.currentCharges) then
        button.count:SetText(charges.currentCharges)
    else
        button.count:SetText(count > 1 and count or "")
    end
    refreshCooldown(button.cooldown, source, id, charges)
    if not isSecret(usable) and not isSecret(noPower) then
        local intensity = usable == false and .42 or 1
        if noPower then
            button.icon:SetVertexColor(.46, .62, .97)
        else
            button.icon:SetVertexColor(intensity, intensity, intensity)
        end
    end
end

local function sortedChoices(choices)
    table.sort(choices, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    return choices
end

local function appendSpellChoice(choices, seen, entry, spellType)
    if not entry or entry.itemType ~= spellType or entry.isPassive or entry.isOffSpec then return end
    local id = entry.actionID or entry.spellID
    if not validID(id) or seen[id] then return end

    local binding = { kind = "spell", id = id }
    local name = entry.name or Actions.name(binding, {})
    if isSecret(name) or not name then return end
    seen[id] = true
    binding.name, binding.icon = name, entry.iconID
    choices[#choices + 1] = binding
end

function Actions.spellChoices()
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local choices, seen = {}, {}
    if not book or not book.GetNumSpellBookSkillLines or not bank or not spellType then return choices end
    for line = 1, book.GetNumSpellBookSkillLines() do
        local info = book.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide and not info.offSpecID then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                appendSpellChoice(choices, seen, book.GetSpellBookItemInfo(slot, bank), spellType)
            end
        end
    end
    return sortedChoices(choices)
end

function Actions.professionChoices()
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local choices, seen = {}, {}
    if not GetProfessions or not GetProfessionInfo or not book or not book.GetSpellBookItemInfo
            or not bank or not spellType then return choices end

    -- Learned professions can leave gaps between the primary and secondary entries.
    local function appendProfessions(...)
        for index = 1, select("#", ...) do
            local profession = select(index, ...)
            if validID(profession) then
                local _, _, _, _, count, offset = GetProfessionInfo(profession)
                if number(count) > 0 and not isSecret(offset) and type(offset) == "number" and offset >= 0 then
                    for slot = offset + 1, offset + count do
                        appendSpellChoice(choices, seen, book.GetSpellBookItemInfo(slot, bank), spellType)
                    end
                end
            end
        end
    end
    appendProfessions(GetProfessions())
    return sortedChoices(choices)
end

function Actions.itemChoices()
    local container = C_Container
    local choices, seen = {}, {}
    if not container or not container.GetContainerItemInfo or not item.GetItemSpell then return choices end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, container.GetContainerNumSlots(bag) do
            local info = container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if validID(id) and not seen[id] and item.GetItemSpell(id) then
                local binding = { kind = "item", id = id }
                local name = Actions.name(binding, {})
                if not isSecret(name) and name then
                    seen[id] = true
                    binding.name, binding.icon = name, info.iconFileID
                    choices[#choices + 1] = binding
                end
            end
        end
    end
    return sortedChoices(choices)
end
