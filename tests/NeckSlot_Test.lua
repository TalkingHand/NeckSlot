-- Single-player in-game test, test environment only: pzt installs this file into the test copy
-- of the mod (TEST_FILES in pzt.conf); the script calls NeckSlotTest.start() and .poll().
--   1. items: masks and helmets get the neck attachment type and no hanging model, a cap does not
--   2. slot: the hotbar has the Neck slot without any worn item providing it
--   3. hang: a welding mask attached to the slot (not drawn on the body)
--   4. key: the slot key wears it (model off the neck, item still in the slot), again takes it off
--   5. swap: wearing a respirator, the key puts the welding mask on and hangs the respirator;
--      the key again swaps back
--   6. helmet: a crash helmet hangs and is worn the same way
--   7. not allowed: a baseball cap cannot go in the slot
-- Results: "[NeckSlotTest]" lines (failures also "[PZTest] FAIL"), screenshots pzt_<run>_neck_*.png

require "NeckSlot_Items"

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	print("[NeckSlotTest] " .. table.concat(parts, " "))
end

local T = { phase = 0, wait = 0, pass = 0, fail = 0, done = false }
NeckSlotTest = T

local function check(label, ok, extra)
	if ok then T.pass = T.pass + 1 else T.fail = T.fail + 1 end
	log(ok and "PASS" or "FAIL", label, extra or "")
	if not ok and PZTest then PZTest.fail("NeckSlotTest " .. label .. " " .. tostring(extra or "")) end
end

local function player() return getPlayer() end
local function hotbar() return getPlayerHotbar(0) end
local function inv() return player():getInventory() end

local function slotIndex() return NeckSlot.slotIndex(hotbar()) end
local function slotItem()
	local i = slotIndex()
	return i and hotbar().attachedItems[i] or nil
end
local function hung() return player():getAttachedItem(NeckSlot.LOCATION) end
local function worn(item) return player():isEquippedClothing(item) end
local function busy()
	local q = ISTimedActionQueue.queues[player()]
	return (q and #q.queue > 0) or hotbar().neckSlotPending ~= nil
end
local function name(item) return item and item:getFullType() or "nil" end

local function give(fullType)
	local item = inv():AddItem(fullType)
	if not item then check("give " .. fullType, false) end
	return item
end

local function attachToSlot(item)
	local hb = hotbar()
	local i = slotIndex()
	local def = hb.availableSlot[i].def
	hb:attachItem(item, def.attachments[item:getAttachmentType()], i, def, false)
end

local function shot(tag)
	-- face the camera (front), close zoom
	player():setDir(IsoDirections.S)
	PZTest.step("shot neck_" .. tag)
	PZTest.step("lua getPlayer():setDir(IsoDirections.E)")
	PZTest.step("shot neck_" .. tag .. "_side")
end

local S = {} -- test state
local phases = {}

-- 1. items
phases[#phases + 1] = function()
	for _, fullType in ipairs({ "Base.WeldingMask", "Base.Hat_BuildersRespirator", "Base.Hat_GasMask", "Base.Hat_CrashHelmet", "Base.Hat_RiotHelmet" }) do
		local item = instanceItem(fullType)
		check("eligible " .. fullType, NeckSlot.isNeckItem(item), item and item:getAttachmentType())
		-- hung items are not drawn: vanilla draws an attached item only by its StaticModel
		check("no hanging model " .. fullType, item and item:getStaticModel() == nil, item and item:getStaticModel())
	end
	local cap = instanceItem("Base.Hat_BaseballCap")
	check("cap not eligible", cap and not NeckSlot.isNeckItem(cap), cap and cap:getAttachmentType())

	-- clean start: no mask or hat worn, nothing in the slot
	local wornItems = player():getWornItems()
	for i = wornItems:size() - 1, 0, -1 do
		local item = wornItems:getItemByIndex(i)
		if item and (NeckSlot.isNeckItem(item) or item:getBodyLocation() == ItemBodyLocation.HAT) then
			player():removeWornItem(item)
		end
	end
	getCore():doZoomScroll(0, -1); getCore():doZoomScroll(0, -1); getCore():doZoomScroll(0, -1)
	return 30
end

-- 2. slot
phases[#phases + 1] = function()
	local hb = hotbar()
	hb:refresh()
	check("neck slot present", slotIndex() ~= nil, "slots " .. tostring(#hb.availableSlot))
	log("slots", #hb.availableSlot, "neck index", tostring(slotIndex()))
	S.weld = give("Base.WeldingMask")
	S.resp = give("Base.Hat_BuildersRespirator")
	S.helmet = give("Base.Hat_CrashHelmet")
	S.cap = give("Base.Hat_BaseballCap")
	return 10
end

-- 3. hang
phases[#phases + 1] = function()
	attachToSlot(S.weld)
	check("slot holds welding mask", slotItem() == S.weld, name(slotItem()))
	check("welding mask hung", hung() == S.weld, name(hung()))
	shot("weld_hung")
	return 60
end

-- 4. key: wear
phases[#phases + 1] = function()
	hotbar():activateSlot(slotIndex())
	return 30, busy
end
phases[#phases + 1] = function()
	check("key wears welding mask", worn(S.weld))
	check("worn mask stays in slot", slotItem() == S.weld, name(slotItem()))
	check("worn mask not drawn on neck", hung() == nil, name(hung()))
	shot("weld_worn")
	return 60
end

-- 4. key: take off
phases[#phases + 1] = function()
	hotbar():activateSlot(slotIndex())
	return 30, busy
end
phases[#phases + 1] = function()
	check("key takes welding mask off", not worn(S.weld))
	check("mask back on neck", hung() == S.weld, name(hung()))
	return 10
end

-- 5. swap: wear the respirator by hand, then the key
phases[#phases + 1] = function()
	ISInventoryPaneContextMenu.onWearItems({ S.resp }, 0)
	return 30, busy
end
phases[#phases + 1] = function()
	check("respirator worn", worn(S.resp))
	hotbar():activateSlot(slotIndex())
	return 30, busy
end
phases[#phases + 1] = function()
	check("swap: welding mask worn", worn(S.weld))
	check("swap: respirator off", not worn(S.resp))
	check("swap: respirator in slot", slotItem() == S.resp, name(slotItem()))
	check("swap: respirator hung", hung() == S.resp, name(hung()))
	check("swap: welding mask out of the hotbar", S.weld:getAttachedSlot() == -1, S.weld:getAttachedSlot())
	shot("swap_resp_hung")
	return 60
end
phases[#phases + 1] = function()
	hotbar():activateSlot(slotIndex())
	return 30, busy
end
phases[#phases + 1] = function()
	check("swap back: respirator worn", worn(S.resp))
	check("swap back: welding mask in slot", slotItem() == S.weld, name(slotItem()))
	check("swap back: welding mask hung", hung() == S.weld, name(hung()))
	return 10
end

-- 6. helmet
phases[#phases + 1] = function()
	hotbar():removeItem(S.weld, false)
	attachToSlot(S.helmet)
	check("helmet in slot", slotItem() == S.helmet, name(slotItem()))
	check("helmet hung", hung() == S.helmet, name(hung()))
	shot("helmet_hung")
	return 60
end
phases[#phases + 1] = function()
	hotbar():activateSlot(slotIndex())
	return 30, busy
end
phases[#phases + 1] = function()
	check("key wears helmet", worn(S.helmet))
	check("helmet not drawn on neck", hung() == nil, name(hung()))
	return 10
end

-- 7. not allowed
phases[#phases + 1] = function()
	local hb = hotbar()
	check("cap cannot attach", not hb:canBeAttached(hb.availableSlot[slotIndex()], S.cap))
	return 10
end

local function run()
	local p = phases[T.phase]
	if not p then T.done = true; return end
	local ok, delay, waitFn = pcall(p)
	if not ok then
		check("phase " .. T.phase .. " error", false, delay)
		delay, waitFn = 10, nil
	end
	T.wait = delay or 10
	T.waitFn = waitFn
end

function NeckSlotTest.start()
	if T.phase > 0 then
		PZTest.fail("NeckSlotTest already ran in this game; pzt stop, then run again")
		return
	end
	log("start")
	T.phase = 1
	run()
end

-- one poll per harness wait: count down, wait for busy() to clear, then the next phase
function NeckSlotTest.poll()
	if T.done then
		PZTest.log("NeckSlotTest pass " .. T.pass .. " fail " .. T.fail)
		return
	end
	T.wait = T.wait - 10
	if T.wait <= 0 then
		if T.waitFn and T.waitFn() then
			T.busyPolls = (T.busyPolls or 0) + 1
			if T.busyPolls > 100 then
				check("phase " .. T.phase .. " timed out", false)
				T.waitFn = nil
			end
		else
			T.busyPolls = 0
			T.phase = T.phase + 1
			run()
		end
	end
	PZTest.step("wait 10")
	PZTest.step("lua NeckSlotTest.poll()")
end
