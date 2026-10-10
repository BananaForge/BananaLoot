--[[
  BananaPresence - tiny shared library (Lua 5.0 / WoW 1.12)

  Lets every Banana addon (BananaCraft, BananaBank, Banana Lootline, Bananaloot, BananaGuild ...)
  announce "I am installed + running" once per login, so the BananaGuild dashboard can build
  an overview + analytics of who uses which addon.

  HOW TO USE IN ANOTHER ADDON
    1. Copy this file next to your addon's .lua files and list it FIRST in your .toc.
       (The first copy that loads wins, all later copies are ignored automatically.)
    2. Somewhere in your addon's load code:
         BananaPresence.Register("bank", "BananaBank", "1.2.0")
       Keys used by the dashboard: craft, bank, lootline, loot, guild
    3. Optional: expose a checkbox in your own UI that calls
         BananaPresence.SetWorldPing(true/false)

  What is sent
    * Guild addon channel (invisible): "H;key=version,key=version"   (once per login, after ~20s)
    * Optional world channel ping (OFF by default): "~BGP~key=version,..."
      Anyone running a Banana addon with this file will not see it in chat (it is filtered),
      players WITHOUT it would see the raw text. That is why it is opt-in.
]]

local LIBVER = 1

if BananaPresence and BananaPresence.libVersion and BananaPresence.libVersion >= LIBVER then
	return
end

BananaPresence = BananaPresence or {}
local P = BananaPresence

P.libVersion   = LIBVER
P.PREFIX       = "BGLD"
P.MARK         = "~BGP~"
P.registry     = P.registry or {}
P.listeners    = P.listeners or {}
P.worldPing    = P.worldPing or false
P.worldChannel = P.worldChannel or 4
P.guildSent    = false
P.worldSent    = false
P.tries        = 0
P.queue        = {}

--------------------------------------------------------------------- API

function P.Register(key, label, version)
	if not key then return end
	P.registry[key] = { label = label or key, version = version or "?" }
end

function P.Listen(fn)
	if type(fn) == "function" then
		table.insert(P.listeners, fn)
	end
end

function P.SetWorldPing(on)
	P.worldPing = on and true or false
end

function P.SetWorldChannel(n)
	n = tonumber(n)
	if n and n > 0 then P.worldChannel = n end
end

function P.Payload()
	local parts = {}
	for key, info in pairs(P.registry) do
		table.insert(parts, key .. "=" .. tostring(info.version or "?"))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function P.Parse(payload)
	local t = {}
	if not payload then return t end
	for k, v in string.gfind(payload, "([^,=]+)=([^,]*)") do
		t[k] = v
	end
	return t
end

local function Notify(sender, payload, source)
	local t = P.Parse(payload)
	for i = 1, table.getn(P.listeners) do
		local ok, err = pcall(P.listeners[i], sender, t, source)
		if not ok and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage("|cffff5555BananaPresence listener error:|r " .. tostring(err))
		end
	end
end

function P.SendGuildHello()
	if not SendAddonMessage or not IsInGuild or not IsInGuild() then return false end
	local payload = P.Payload()
	if payload == "" then return false end
	SendAddonMessage(P.PREFIX, "H;" .. payload, "GUILD")
	return true
end

function P.SendWorldPing()
	if not P.worldPing then return true end -- nothing to do counts as done
	if not GetChannelName or not SendChatMessage then return false end
	local id = GetChannelName(P.worldChannel)
	if not id or id == 0 then return false end
	local payload = P.Payload()
	if payload == "" then return false end
	SendChatMessage(P.MARK .. payload, "CHANNEL", nil, id)
	return true
end

--------------------------------------------------------------------- internals

local function Later(delay, fn)
	table.insert(P.queue, { at = GetTime() + delay, fn = fn })
end

local frame = CreateFrame("Frame", "BananaPresenceFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_CHANNEL")

frame:SetScript("OnEvent", function()
	if event == "PLAYER_LOGIN" then
		P.me = UnitName("player")
		P.loginAt = GetTime()
		-- first announce to the guild after 20s (roster / channels are ready by then)
		Later(20, function()
			if not P.guildSent then P.guildSent = P.SendGuildHello() end
		end)
		Later(35, P.TryWorld)
	elseif event == "CHAT_MSG_ADDON" then
		if arg1 == P.PREFIX and arg2 then
			local _, _, kind, rest = string.find(arg2, "^(%a+);?(.*)$")
			if kind == "H" then
				if arg4 ~= P.me then Notify(arg4, rest, "guild") end
			elseif kind == "Q" then
				-- somebody (dashboard) asks "who is there?" -> answer with a random delay
				Later(0.5 + math.random() * 8, function() P.SendGuildHello() end)
			end
		end
	elseif event == "CHAT_MSG_CHANNEL" then
		if arg1 and string.sub(arg1, 1, string.len(P.MARK)) == P.MARK then
			if arg2 and arg2 ~= P.me then
				Notify(arg2, string.sub(arg1, string.len(P.MARK) + 1), "world")
			end
		end
	end
end)

function P.TryWorld()
	if P.worldSent then return end
	if not P.worldPing then
		-- re-check later in case the user enables it during this session
		Later(60, P.TryWorld)
		return
	end
	if P.SendWorldPing() then
		P.worldSent = true
	else
		P.tries = P.tries + 1
		if P.tries < 8 then Later(30, P.TryWorld) end
	end
end

frame:SetScript("OnUpdate", function()
	local n = table.getn(P.queue)
	if n == 0 then return end
	local now = GetTime()
	for i = n, 1, -1 do
		local item = P.queue[i]
		if item and now >= item.at then
			table.remove(P.queue, i)
			pcall(item.fn)
		end
	end
end)

-- Hide the hidden world pings from every chat frame (also our own echo).
if ChatFrame_OnEvent and not P.hooked then
	P.hooked = true
	local orig = ChatFrame_OnEvent
	ChatFrame_OnEvent = function(ev)
		if ev == "CHAT_MSG_CHANNEL" and arg1 and string.sub(arg1, 1, string.len(P.MARK)) == P.MARK then
			return
		end
		return orig(ev)
	end
end

BananaGuild = BananaGuild or {}
BananaGuild.files = BananaGuild.files or {}
BananaGuild.files.BananaPresence = true
