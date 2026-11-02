-- Multiplayer test, client side (tools/mptest.sh creates Zomboid/Lua/neckslot_mptest.txt in the
-- client's folder only; without it this file does nothing).
-- Connects to the local dedicated server as admin, skips character creation, then by mode:
--   on:       hang (with the attach action), key wear, key off, swap, swap back, helmet, hang
--             the welding mask for the next run, then quit
--   relog:    new client, same server: the hung mask is kept; key wears it, then the server
--             is asked to save and quit
--   restart:  server restarted too: the worn mask is kept and still in the slot; key takes it
--             off and hangs it back
-- Each state is also compared with what the server reports (tests/NeckSlot_MPServer.lua).
-- Results: "[NeckSlotMP]" lines in the client console.txt and the server log.

require "NeckSlot_Items"

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	print("[NeckSlotMP] " .. table.concat(parts, " "))
end

local r = getFileReader("neckslot_mptest.txt", false)
if not r then return end
local MODE = r:readLine() or "on"
r:close()

local WELD, RESP, HELMET = "Base.WeldingMask", "Base.Hat_BuildersRespirator", "Base.Hat_CrashHelmet"
local T = { fe = 0, tick = 0, phase = 0, at = 0, pass = 0, fail = 0, n = 0 }

local function check(label, ok, extra)
	if ok then T.pass = T.pass + 1 else T.fail = T.fail + 1 end
	log(ok and "PASS" or "FAIL", label, extra or "")
end

-- main menu: connect ---------------------------------------------------------------------

Events.OnFETick.Add(function()
	T.fe = T.fe + 1
	if T.fe == 200 and not T.connecting and MainScreen and MainScreen.instance then
		T.connecting = true
		log("connecting", MODE)
		ConnectToServer.instance:connect(MainScreen.instance, "", "admin", "neckslot", "127.0.0.1", "", "16361", "", false, true, 1)
	end
	if T.connecting and T.fe % 30 == 0 then
		local prof = MainScreen.instance.charCreationProfession
		local main = MainScreen.instance.charCreationMain
		if prof and prof:isVisible() then
			prof:onOptionMouseDown({ internal = "NEXT" })
		elseif main and main:isVisible() then
			main:onOptionMouseDown({ internal = "NEXT" })
		elseif MapSpawnSelect.instance and MapSpawnSelect.instance:isVisible() then
			MapSpawnSelect.instance:onOptionMouseDown({ internal = "NEXT" })
		end
	end
end)
Events.OnConnectFailed.Add(function(msg, detail) log("connect failed", msg, detail) end)

-- helpers --------------------------------------------------------------------------------

Events.OnServerCommand.Add(function(module, command, args)
	if module == "NeckSlotMP" and command == "state" then T.server = args end
end)

local function player() return getSpecificPlayer(0) end
local function hotbar() return getPlayerHotbar(0) end
local function slotIndex() return NeckSlot.slotIndex(hotbar()) end
local function slotItem()
	local i = slotIndex()
	return i and hotbar().attachedItems[i] or nil
end
local function hung() return player():getAttachedItem(NeckSlot.LOCATION) end
local function worn(item) return item ~= nil and player():isEquippedClothing(item) end
local function name(item) return item and item:getFullType() or "" end
local function find(fullType) return player():getInventory():getFirstTypeRecurse(fullType) end
local function busy()
	local q = ISTimedActionQueue.queues[player()]
	return (q and #q.queue > 0) or hotbar().neckSlotPending ~= nil
end
local function idle() return not busy() end

-- the steps -------------------------------------------------------------------------------

local steps = {}

-- each step returns nil to go on after `wait` ticks once `untilFn` is true (or times out)
local function add(fn) steps[#steps + 1] = fn end
local function pause(ticks) add(function() return ticks end) end

-- ask the server, then compare once it answered
local function serverIs(label, wantHung, wantWorn)
	add(function()
		T.server = nil
		T.n = T.n + 1
		sendClientCommand(player(), "NeckSlotMP", "query", { n = T.n })
		return 10, function() return T.server ~= nil end
	end)
	add(function()
		local s = T.server
		if not s then
			check(label .. ": server answered", false)
			return 1
		end
		check(label .. ": server has the location", s.location == true, s.location)
		check(label .. ": server reads the slot without an exception", s.ok == true, s.ok)
		check(label .. ": server hung " .. wantHung, s.hung == wantHung, s.hung)
		check(label .. ": server worn " .. wantWorn, s.worn == wantWorn, s.worn)
		return 1
	end)
end

local function hang(fullType)
	add(function()
		local hb, item = hotbar(), find(fullType)
		local i = slotIndex()
		if not item or not i then
			check("hang " .. fullType .. ": item and slot", false)
			return 1
		end
		local def = hb.availableSlot[i].def
		hb:attachItem(item, def.attachments[item:getAttachmentType()], i, def, true)
		return 30, idle
	end)
	pause(60)
end

local function key()
	add(function()
		hotbar():activateSlot(slotIndex())
		return 30, idle
	end)
	pause(60)
end

-- wornType: what the swap left worn
local function isHung(label, fullType, wornType)
	add(function()
		check(label .. ": slot holds " .. fullType, name(slotItem()) == fullType, name(slotItem()))
		check(label .. ": attached to the neck", name(hung()) == fullType, name(hung()))
		check(label .. ": not worn", not worn(find(fullType)))
		return 1
	end)
	serverIs(label, fullType, wornType or "")
end

local function isWorn(label, fullType)
	add(function()
		check(label .. ": worn", worn(find(fullType)))
		check(label .. ": stays in the slot", name(slotItem()) == fullType, name(slotItem()))
		check(label .. ": not attached while worn", hung() == nil, name(hung()))
		return 1
	end)
	serverIs(label, "", fullType)
end

if MODE == "on" then
	add(function()
		-- nothing near the player interrupts the actions
		SendCommandToServer('/invisible "admin"')
		SendCommandToServer('/godmode "admin"')
		for _, fullType in ipairs({ WELD, RESP, HELMET }) do
			SendCommandToServer('/additem "admin" "' .. fullType .. '"')
		end
		return 30, function() return find(WELD) and find(RESP) and find(HELMET) end
	end)
	add(function()
		check("slot present", slotIndex() ~= nil)
		check("items arrived", find(WELD) and find(RESP) and find(HELMET))
		return 1
	end)
	serverIs("start", "", "")

	hang(WELD)
	isHung("hang", WELD)
	key()
	isWorn("key wears", WELD)
	key()
	isHung("key takes off", WELD)

	add(function()
		ISInventoryPaneContextMenu.onWearItems({ find(RESP) }, 0)
		return 30, idle
	end)
	pause(60)
	key()
	add(function()
		check("swap: welding mask worn", worn(find(WELD)))
		check("swap: respirator off", not worn(find(RESP)))
		return 1
	end)
	isHung("swap", RESP, WELD)
	key()
	add(function()
		check("swap back: respirator worn", worn(find(RESP)))
		check("swap back: welding mask off", not worn(find(WELD)))
		return 1
	end)
	isHung("swap back", WELD, RESP)

	-- the helmet replaces the mask in the slot, is worn and comes off; the mask goes back for the
	-- next run with nothing else worn
	add(function()
		ISTimedActionQueue.add(ISUnequipAction:new(player(), find(RESP), 20))
		return 30, idle
	end)
	hang(HELMET)
	isHung("helmet", HELMET)
	key()
	isWorn("helmet key wears", HELMET)
	key()
	isHung("helmet key takes off", HELMET)
	hang(WELD)
	isHung("before quitting", WELD)
elseif MODE == "relog" then
	isHung("after reconnecting", WELD)
	key()
	isWorn("key wears after reconnecting", WELD)
else
	isWorn("after the server restart", WELD)
	key()
	isHung("key takes off after the server restart", WELD)
end

local function run()
	if T.phase > #steps then
		log("RESULT pass", T.pass, "fail", T.fail)
		log("test done", MODE)
		T.done = true
		-- quitting disconnects, so the server saves the player; /quit saves it and the world
		if MODE == "relog" then SendCommandToServer("/quit") end
		T.quitAt = T.tick + 300
		return
	end
	local ok, ticks, untilFn = pcall(steps[T.phase])
	if not ok then
		check("step " .. T.phase .. " error", false, ticks)
		ticks, untilFn = 1, nil
	end
	T.at = T.tick + (ticks or 1)
	T.untilFn = untilFn
	T.deadline = T.tick + 1200
end

local function onTick()
	T.tick = T.tick + 1
	if T.done then
		if T.tick == T.quitAt then getCore():quitToDesktop() end
		return
	end
	if not player() or not hotbar() then return end
	if T.phase == 0 then
		T.ready = (T.ready or 0) + 1
		if T.ready > 300 then
			log("in game", MODE)
			hotbar():refresh()
			T.phase = 1
			run()
		end
		return
	end
	if T.tick < T.at then return end
	if T.untilFn and not T.untilFn() and T.tick < T.deadline then return end
	if T.untilFn and T.tick >= T.deadline then check("step " .. T.phase .. " timed out", false) end
	T.phase = T.phase + 1
	run()
end

Events.OnRenderTick.Add(function()
	local ok, err = pcall(onTick)
	if not ok and not T.errored then
		T.errored = true
		T.fail = T.fail + 1
		log("FAIL tick", err)
	end
end)
