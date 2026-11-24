local name, addon = ...
local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local session = getMetadata and getMetadata(name, "X-ForeverTouch-ArcSession")
if not session or #session ~= 16 or not session:match("^%x+$") then return end

-- The launcher reads this temporary frame from its own game surface. Only
-- this addon's settings are encoded, and no screenshot is written to disk.
local columns, rows = 96, 64
local paletteSize, headerSize = 16, 28
local chunkSize = (columns * rows - paletteSize) / 2 - headerSize
local maxBytes = 64 * 1024
local nonce = session:gsub("%x%x", function(byte) return string.char(tonumber(byte, 16)) end)
local fields = {
    "mobileSlots", "mobileArcPositions", "mobileArcPages", "mobileArcPage", "order", "favorites",
    "revision", "arcRevision", "mobileChatOpen", "mobileChatSize",
}

local function literal(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    local parts = { "{" }
    for key, element in pairs(value) do
        parts[#parts + 1] = "[" .. literal(key) .. "]=" .. literal(element) .. ","
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
end

local function unsigned(value, bytes)
    local result = {}
    for index = bytes, 1, -1 do
        result[index] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(result)
end

local function checksum(data)
    local a, b = 1, 0
    for index = 1, #data do
        a = (a + data:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local frame, cells, pending = nil, {}, nil
local function paint(packet)
    local width, height = UIParent:GetWidth() / 2, UIParent:GetHeight() / 3
    local resized = width ~= frame:GetWidth() or height ~= frame:GetHeight()
    if resized then frame:SetSize(width, height) end
    local function draw(index, color)
        local texture = cells[index]
        local needsLayout = resized or not texture
        if not texture then
            texture = frame:CreateTexture(nil, "ARTWORK")
            cells[index] = texture
        end
        if needsLayout then
            local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", frame, "TOPLEFT", column * width / columns, -row * height / rows)
            texture:SetSize(width / columns, height / rows)
        end
        texture:SetColorTexture(math.floor(color / 8), math.floor(color / 2) % 4 / 3, color % 2, 1)
        texture:Show()
    end
    for index = 1, paletteSize do draw(index, index - 1) end
    for index = 1, #packet do
        local byte = packet:byte(index)
        draw(paletteSize + index * 2 - 1, math.floor(byte / 16))
        draw(paletteSize + index * 2, byte % 16)
    end
    for index = paletteSize + #packet * 2 + 1, #cells do cells[index]:Hide() end
    frame:Show()
end

local function close()
    pending = nil
    if frame then frame:Hide() end
end

local function show(guid, nameKey, preferences)
    close()
    if not guid then return end
    local profile = {}
    for _, key in ipairs(fields) do profile[key] = preferences[key] end
    profile.revision = profile.revision or 0
    profile.arcRevision = profile.arcRevision or profile.revision
    local data = "Arc=" .. literal({ key = guid, nameKey = nameKey, profile = profile })
    if #data > 512 * 1024 then return end
    local compressed = C_EncodingUtil and C_EncodingUtil.CompressString
    local encoding = 0
    if compressed then
        local ok, packed = pcall(compressed, data)
        if ok and packed and #packed < #data then data, encoding = packed, 1 end
    end
    if #data > maxBytes then return end
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(200)
        frame:SetPoint("CENTER")
    end
    local count = math.ceil(#data / chunkSize)
    local serial = math.floor(GetTimePreciseSec() * 1000) % 4294967296
    local header = "FT\1" .. string.char(encoding) .. nonce .. unsigned(serial, 4)
        .. unsigned(#data, 4) .. unsigned(checksum(data), 4)
    local request = {}
    pending = request
    local function showChunk(index)
        if pending ~= request then return end
        local start = (index - 1) * chunkSize + 1
        local chunk = data:sub(start, start + chunkSize - 1)
        paint(header .. unsigned(index - 1, 2) .. unsigned(#chunk, 2) .. chunk)
        if count > 1 then C_Timer.After(.12, function() showChunk(index % count + 1) end) end
    end
    showChunk(1)
    C_Timer.After(4, function() if pending == request then close() end end)
end

addon.arcSave = { show = show, close = close }
