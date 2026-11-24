local _, addon = ...
local history = {}
addon.chatHistory = history

local isSecret = issecretvalue or function() return false end
local public = {
    CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL", CHAT_MSG_CHANNEL = "CHANNEL",
    CHAT_MSG_EMOTE = "EMOTE", CHAT_MSG_TEXT_EMOTE = "EMOTE", CHAT_MSG_SYSTEM = "SYSTEM",
    CHAT_MSG_LOOT = "LOOT", CHAT_MSG_MONEY = "MONEY", CHAT_MSG_OFFICER = "OFFICER",
}
local scopes = {
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_INSTANCE_CHAT = "PARTY", CHAT_MSG_INSTANCE_CHAT_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID", CHAT_MSG_RAID_WARNING = "RAID",
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_BN_WHISPER = "BN_WHISPER", CHAT_MSG_BN_WHISPER_INFORM = "BN_WHISPER",
}
local sent = { CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER_INFORM = true }

history.events = {}
for event in pairs(public) do history.events[#history.events + 1] = event end
for event in pairs(scopes) do history.events[#history.events + 1] = event end

local function readable(value)
    if not isSecret(value) and type(value) == "string" and value ~= "" then return value end
end

local function append(lines, line, limit)
    lines[#lines + 1] = line
    if #lines > limit then table.remove(lines, 1) end
end

local function whisperThread(name, kind, accountID)
    local key = kind .. ":" .. (accountID and tostring(accountID) or name:lower())
    local thread = history.peers[key]
    if not thread then
        thread = { key = key, name = name, kind = kind, accountID = accountID, lines = {}, unread = 0 }
        history.peers[key] = thread
    end
    thread.name = name
    for index, contact in ipairs(history.contacts) do
        if contact == thread then
            table.remove(history.contacts, index)
            break
        end
    end
    table.insert(history.contacts, 1, thread)
    if #history.contacts > 32 then
        -- Clear old read conversations before evicting the least recent unread one.
        local index = #history.contacts
        while index > 2 and history.contacts[index].unread > 0 do index = index - 1 end
        if history.contacts[index].unread > 0 then index = #history.contacts end
        local expired = table.remove(history.contacts, index)
        history.peers[expired.key] = nil
    end
    return thread
end

function history.reset()
    history.lines = { ALL = {}, PARTY = {}, RAID = {}, GUILD = {} }
    history.contacts = {}
    history.peers = {}
    history.restrictedUnread = false
end

function history.add(event, body, sender, _, channel, _, _, _, _, channelName, _, _, _, accountID)
    local kind = scopes[event] or public[event]
    if not kind then return end
    local whisper = kind == "WHISPER" or kind == "BN_WHISPER"
    local outgoing = sent[event] == true
    body, sender = readable(body), readable(sender)
    if not body or (whisper and not sender) then
        if whisper and not outgoing then history.restrictedUnread = true end
        return
    end

    local line = {
        text = body, author = sender, kind = kind, outgoing = outgoing,
        channel = readable(channel) or readable(channelName), time = date("%H:%M"),
    }
    append(history.lines.ALL, line, 180)
    if whisper then
        local bnetID = kind == "BN_WHISPER" and not isSecret(accountID)
            and type(accountID) == "number" and accountID > 0 and accountID or nil
        local thread = whisperThread(sender, kind, bnetID)
        append(thread.lines, line, 100)
        if not outgoing then thread.unread = thread.unread + 1 end
        return line, thread
    end
    if history.lines[kind] then append(history.lines[kind], line, 100) end
    return line
end

function history.hasUnread()
    if history.restrictedUnread then return true end
    for _, thread in ipairs(history.contacts) do
        if thread.unread > 0 then return true end
    end
    return false
end

history.reset()
