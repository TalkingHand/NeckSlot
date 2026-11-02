-- Neck Slot: the attached location of the neck slot.
-- In shared, not client: a dedicated server handles the attach packet with setAttachedItem, which
-- throws for a location its own "Human" group does not have.

require "NeckSlot_Items"

-- the hotbar needs a location to attach to; nothing is drawn there (the items have no StaticModel)
AttachedLocations.getGroup("Human"):getOrCreateLocation(NeckSlot.LOCATION):setAttachmentName("neckslot_neck")
