-- Neck Slot: which items can hang on the neck.
-- Masks and helmets get an attachment type at boot, so the hotbar can hold them (vanilla
-- reads InventoryItem.attachmentType from the script item when an item is made or loaded).
-- A hung item is not drawn: vanilla draws attached items by StaticModel, and these have none.

NeckSlot = NeckSlot or {}

NeckSlot.SLOT_TYPE = "NeckSlot"              -- ISHotbarAttachDefinition type
NeckSlot.ATTACHMENT_TYPE = "NeckSlotItem"    -- item script AttachmentType
NeckSlot.LOCATION = "NeckSlot Neck"          -- AttachedLocations "Human" location

-- the body locations of masks and full-head gear
local function maskLocations()
	return {
		ItemBodyLocation.MASK,
		ItemBodyLocation.MASK_EYES,
		ItemBodyLocation.MASK_FULL,
		ItemBodyLocation.FULL_HAT,
	}
end

local function isMaskLocation(location)
	for _, loc in ipairs(maskLocations()) do
		if location == loc then return true end
	end
	return false
end

-- script item -> can it hang on the neck?
function NeckSlot.isEligibleScript(scriptItem)
	if not scriptItem then return false end
	local location = scriptItem:getBodyLocation()
	if not location then return false end
	local eligible = isMaskLocation(location)
	-- hats: only helmets (bicycle, crash, riot, hockey, ... helmets are all in "hat")
	if not eligible and location == ItemBodyLocation.HAT then
		eligible = string.find(string.lower(scriptItem:getName()), "helmet", 1, true) ~= nil
	end
	if not eligible then return false end
	-- another mod already gave it a hotbar slot (e.g. gas masks on the belt): leave it alone.
	-- The script item has no getter for AttachmentType, so read it from a sample item.
	local ok, sample = pcall(instanceItem, scriptItem)
	if ok and sample then
		local current = sample:getAttachmentType()
		if current and current ~= "" and current ~= NeckSlot.ATTACHMENT_TYPE then return false end
	end
	return true
end

function NeckSlot.isNeckItem(item)
	return item ~= nil and item:getAttachmentType() == NeckSlot.ATTACHMENT_TYPE
end

local function applyAttachmentTypes()
	local items = getScriptManager():getAllItems()
	local count = 0
	for i = 0, items:size() - 1 do
		local scriptItem = items:get(i)
		if NeckSlot.isEligibleScript(scriptItem) then
			scriptItem:DoParam("AttachmentType = " .. NeckSlot.ATTACHMENT_TYPE)
			count = count + 1
		end
	end
	print("[NeckSlot] neck items: " .. tostring(count))
end

Events.OnGameBoot.Add(applyAttachmentTypes)
