# Neck Slot

A Project Zomboid Build 42 mod that adds an always-present **Neck** slot to the hotbar for masks and helmets.

- Hang a welding mask, respirator, gas mask or helmet on your neck (right-click it > Attach > Neck, or right-click the Neck slot).
- Press the slot's hotbar key: the hung item goes on. Press again: it comes off and hangs on your neck again.
- Switching: if putting it on pushes off another mask or helmet (welding mask over a respirator, for example), that one hangs on your neck instead. Press again to switch back.
- The hung item is not drawn on the character; the slot icon shows what is hung.

Items: everything worn on the mask, mask-and-eyes, full-mask or full-hat locations, and hats whose name contains "Helmet". Items another mod already made attachable (e.g. gas masks for the belt) are left to that mod.

## Install

- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3829684092
- Manual: copy `Contents/mods/NeckSlot` to `%USERPROFILE%\Zomboid\mods\`.

## Compatibility

- Lua only. Single player and a local dedicated server tested. In multiplayer, install it on the server and every client.
- Can be added to or removed from an existing save. When removed, the Neck slot disappears and a hung item goes back to the inventory.

## Testing

`pzt run` (PZTestHarness) runs `tests/NeckSlot_Test.lua`: eligibility, the slot, hanging, the key, swapping, helmets, and that a cap is refused.

`bash tools/mptest.sh` runs `tests/NeckSlot_MPTest.lua` against a local dedicated server (port 16361): hanging, the key, swapping and helmets, then a reconnect and a server restart, comparing each state with what the server reports.

## Support

If this mod helps you, you can support it via [Ko-fi](https://ko-fi.com/talkinghands2285) or [PayPal](https://www.paypal.com/paypalme/TalkingHands619/3). It's optional; every feature stays free.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/talkinghands2285)
