local _, addon = ...
local Actions = addon.actions
local PAGE_SIZE = 6

function addon.createSlotPicker(parent)
    local german = addon.german
    local picker = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(parent:GetFrameLevel() + 12)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 35)
    picker:SetSize(475, 392)
    picker:EnableMouse(true)
    picker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    picker:SetBackdropColor(.09, .075, .052, .98)
    picker:SetBackdropBorderColor(.61, .46, .26, .94)
    picker:Hide()

    local choices, page, onSelect = {}, 1, nil
    local currentKind = "spell"
    local rows = {}
    local function control(text, width, x, y, handler)
        local button = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
        button:SetSize(width, 35)
        button:SetPoint("TOPLEFT", picker, "TOPLEFT", x, -y)
        button:SetText(text)
        button:SetScript("OnClick", handler)
        return button
    end

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 16, -14)
    title:SetText(german and "Slot belegen" or "Assign slot")
    control(CLOSE or (german and "Schließen" or "Close"), 106, 353, 8, function() picker:Hide() end)

    local empty = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    empty:SetPoint("CENTER")
    local pages = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pages:SetPoint("BOTTOM", picker, "BOTTOM", 0, 19)

    local previous, nextPage, spellTab, itemTab
    local function render()
        local total = math.max(1, math.ceil(#choices / PAGE_SIZE))
        page = math.min(page, total)
        for index, row in ipairs(rows) do
            local choice = choices[(page - 1) * PAGE_SIZE + index]
            row.binding = choice
            if choice then
                row.icon:SetTexture(choice.icon or Actions.texture(choice, {}))
                row.label:SetText(choice.name)
            end
            row:SetShown(choice ~= nil)
        end
        previous:SetEnabled(page > 1)
        nextPage:SetEnabled(page < total)
        spellTab:SetEnabled(currentKind ~= "spell")
        itemTab:SetEnabled(currentKind ~= "item")
        pages:SetText(total > 1 and string.format("%d / %d", page, total) or "")
        empty:SetText(currentKind == "spell"
            and (german and "Keine aktiven Zauber im Zauberbuch." or "No active spells in your spellbook.")
            or (german and "Keine benutzbaren Gegenstände in den Taschen." or "No usable items in your bags."))
        empty:SetShown(#choices == 0)
    end

    local function showCategory(kind)
        currentKind, page = kind, 1
        if kind == "spell" then
            choices = Actions.spellChoices()
        else
            choices = Actions.itemChoices()
        end
        render()
    end

    spellTab = control(german and "Zauberbuch" or "Spellbook", 138, 16, 51, function() showCategory("spell") end)
    itemTab = control(german and "Taschen" or "Bags", 138, 162, 51, function() showCategory("item") end)
    previous = control("‹", 54, 16, 345, function() page = page - 1; render() end)
    nextPage = control("›", 54, 405, 345, function() page = page + 1; render() end)

    for index = 1, PAGE_SIZE do
        local row = CreateFrame("Button", nil, picker)
        row:SetSize(441, 37)
        row:SetPoint("TOPLEFT", picker, "TOPLEFT", 17, -95 - (index - 1) * 40)
        row:RegisterForClicks("LeftButtonUp")
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(.34, .27, .17, .38)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(31, 31)
        row.icon:SetPoint("LEFT", 4, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            if not self.binding or not onSelect then return end
            local callback = onSelect
            local binding = { kind = self.binding.kind, id = self.binding.id }
            picker:Hide()
            callback(binding)
        end)
        rows[index] = row
    end

    picker:SetScript("OnHide", function() onSelect = nil end)
    function picker:Open(callback, initialKind)
        onSelect = callback
        self:SetScale(UIParent:GetHeight() / 720)
        showCategory(initialKind or currentKind)
        self:Show()
    end

    return picker
end
