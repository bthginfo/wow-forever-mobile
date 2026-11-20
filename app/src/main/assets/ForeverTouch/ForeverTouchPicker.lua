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

    local categories = {
        { kind = "spell", label = german and "Zauberbuch" or "Spellbook", choices = Actions.spellChoices,
            empty = german and "Keine aktiven Zauber im Zauberbuch." or "No active spells in your spellbook." },
        { kind = "profession", label = german and "Berufe" or "Professions", choices = Actions.professionChoices,
            empty = german and "Keine aktiven Berufsaktionen gelernt." or "No learned profession actions." },
        { kind = "item", label = german and "Taschen" or "Bags", choices = Actions.itemChoices,
            empty = german and "Keine benutzbaren Gegenstände in den Taschen." or "No usable items in your bags." },
    }
    local previous, nextPage
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
        for _, category in ipairs(categories) do
            local active = currentKind == category.kind
            category.button:SetEnabled(not active)
            if active then empty:SetText(category.empty) end
        end
        pages:SetText(total > 1 and string.format("%d / %d", page, total) or "")
        empty:SetShown(#choices == 0)
    end

    local function showCategory(kind)
        for _, category in ipairs(categories) do
            if kind == category.kind then
                currentKind, page = kind, 1
                choices = category.choices()
                render()
                return
            end
        end
    end

    for index, category in ipairs(categories) do
        category.button = control(category.label, 138, 16 + (index - 1) * 146, 51, function()
            showCategory(category.kind)
        end)
    end
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
