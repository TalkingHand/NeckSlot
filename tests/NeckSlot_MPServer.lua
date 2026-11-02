-- Multiplayer test, server side (tools/mptest.sh installs it into the test copy of the mod):
-- answers the client test with what the dedicated server itself sees.
-- pcall: an unknown location throws in the server's attached items ("no such location").

require "NeckSlot_Items"

local function hasLocation()
	return AttachedLocations.getGroup("Human"):getLocation(NeckSlot.LOCATION) ~= nil
end

print("[NeckSlotMP] server location registered: " .. tostring(hasLocation()))

local function wornNeckItem(player)
	local worn = player:getWornItems()
	for i = 0, worn:size() - 1 do
		local item = worn:getItemByIndex(i)
		if NeckSlot.isNeckItem(item) then return item:getFullType() end
	end
	return ""
end

Events.OnClientCommand.Add(function(module, command, player, args)
	if module ~= "NeckSlotMP" or command ~= "query" then return end
	local ok, item = pcall(function() return player:getAttachedItem(NeckSlot.LOCATION) end)
	local state = {
		n = args.n,
		location = hasLocation(),
		ok = ok,
		hung = (ok and item) and item:getFullType() or "",
		worn = wornNeckItem(player),
	}
	print("[NeckSlotMP] server state: location " .. tostring(state.location) .. " ok " .. tostring(ok)
		.. " hung '" .. state.hung .. "' worn '" .. state.worn .. "'")
	sendServerCommand(player, "NeckSlotMP", "state", state)
end)
