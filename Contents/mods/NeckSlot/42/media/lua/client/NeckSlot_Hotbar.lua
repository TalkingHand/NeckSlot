-- Neck Slot: an always-present hotbar slot for a mask or helmet.
-- Its key wears the hung item, or takes the worn one off and hangs it back. When wearing it
-- pushes another mask/helmet off, that one hangs on the neck instead (swap).

require "Hotbar/ISHotbarAttachDefinition"
require "Hotbar/ISHotbar"
require "NeckSlot_Items"

NeckSlot = NeckSlot or {}

local slotDef = {
	type = NeckSlot.SLOT_TYPE,
	name = "Neck",
	animset = "holster left",
	attachments = {
		[NeckSlot.ATTACHMENT_TYPE] = NeckSlot.LOCATION,
	},
}

local function addSlotDef()
	for _, def in ipairs(ISHotbarAttachDefinition) do
		if def.type == NeckSlot.SLOT_TYPE then return end
	end
	table.insert(ISHotbarAttachDefinition, slotDef)
end
addSlotDef()

-- slot ------------------------------------------------------------------------------------

local function neckSlotIndex(hotbar)
	return hotbar:getThisSlotIndex(NeckSlot.SLOT_TYPE)
end
NeckSlot.slotIndex = neckSlotIndex

-- the neck slot is always there, like the vanilla back slot: vanilla refresh() drops every
-- slot that no worn item provides, so it must count as provided
NeckSlot.origHaveThisSlot = NeckSlot.origHaveThisSlot or ISHotbar.haveThisSlot
function ISHotbar:haveThisSlot(slotType, list)
	if slotType == NeckSlot.SLOT_TYPE and list ~= nil and list ~= self.availableSlot then
		return true
	end
	return NeckSlot.origHaveThisSlot(self, slotType, list)
end

local function ensureNeckSlot(hotbar)
	if neckSlotIndex(hotbar) then return end
	hotbar.availableSlot[#hotbar.availableSlot + 1] = { slotType = slotDef.type, name = slotDef.name, def = slotDef }
	hotbar:savePosition()
	local width = #hotbar.availableSlot * hotbar.slotWidth + (#hotbar.availableSlot - 1) * 2
	hotbar:setWidth(width + 10)
	hotbar:reloadIcons()
end

NeckSlot.origRefresh = NeckSlot.origRefresh or ISHotbar.refresh
function ISHotbar:refresh()
	NeckSlot.origRefresh(self)
	ensureNeckSlot(self)
end

-- toggle and swap -------------------------------------------------------------------------

local function wornList(chr)
	local list = {}
	local worn = chr:getWornItems()
	for i = 0, worn:size() - 1 do
		list[#list + 1] = worn:getItemByIndex(i)
	end
	return list
end

-- key or click on the neck slot
function NeckSlot.activate(hotbar, item)
	local chr = hotbar.chr
	if chr:isEquippedClothing(item) then
		-- take it off with the clothing animation; hotbar:update() hangs it back once it is off
		local action = ISUnequipAction:new(chr, item, 50)
		action.fromHotbar = false
		ISTimedActionQueue.add(action)
		return
	end
	if chr:isHandItem(item) then
		ISTimedActionQueue.add(ISUnequipAction:new(chr, item, 20))
	end
	hotbar.neckSlotPending = { item = item, before = wornList(chr) }
	ISInventoryPaneContextMenu.onWearItems({ item }, chr:getPlayerNum())
end

-- after a wear from the neck finished: hang the mask/helmet it pushed off
local function finishPending(hotbar)
	local pending = hotbar.neckSlotPending
	if not pending then return end
	local queue = ISTimedActionQueue.queues[hotbar.chr]
	if queue and #queue.queue > 0 then return end
	hotbar.neckSlotPending = nil

	local chr = hotbar.chr
	local item = pending.item
	if not chr:isEquippedClothing(item) then return end -- cancelled
	local index = neckSlotIndex(hotbar)
	if not index or hotbar.attachedItems[index] ~= item then return end

	for _, old in ipairs(pending.before) do
		if old ~= item and NeckSlot.isNeckItem(old) and not chr:isEquippedClothing(old)
				and chr:getInventory():contains(old) and not hotbar:isInHotbar(old) and not old:isBroken() then
			hotbar:removeItem(item, false)
			hotbar:attachItem(old, slotDef.attachments[NeckSlot.ATTACHMENT_TYPE], index, slotDef, false)
			if isClient() then
				syncItemFields(chr, item)
				syncItemFields(chr, old)
			end
			print("[NeckSlot] swapped: wearing " .. item:getFullType() .. ", hung " .. old:getFullType())
			return
		end
	end
end
NeckSlot.finishPending = finishPending

NeckSlot.origActivateSlot = NeckSlot.origActivateSlot or ISHotbar.activateSlot
function ISHotbar:activateSlot(slotIndex)
	local slot = self.availableSlot[slotIndex]
	local item = self.attachedItems[slotIndex]
	if slot and slot.slotType == NeckSlot.SLOT_TYPE and item and NeckSlot.isNeckItem(item) then
		NeckSlot.activate(self, item)
		return
	end
	return NeckSlot.origActivateSlot(self, slotIndex)
end

NeckSlot.origUpdate = NeckSlot.origUpdate or ISHotbar.update
function ISHotbar:update()
	NeckSlot.origUpdate(self)
	finishPending(self)
end
