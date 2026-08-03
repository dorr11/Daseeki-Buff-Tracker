# Changelog

## Unreleased

- Changed: Daseeki Buff Tracker is now licensed **All Rights Reserved** rather than MIT, matching the rest of the suite. This rides the next release — 2.1.1 was published to CurseForge with the MIT file still in place.

## 2.1.1 — 2026-08-03
- **Your profiles and settings will survive future updates.** Buff Tracker used to
  clear its saved profiles whenever its internal data version changed — so the next
  time the data model needed a change, every profile you had built would have been
  wiped. It now migrates your saved data in place instead: a save from a newer version
  is never downgraded, an older one is converted step by step, and if a conversion step
  is ever missing it stops and leaves your data exactly as it found it rather than
  resetting it. Nothing changes for you in this release — your current profiles are
  already in the right shape — but the wipe can no longer happen.
- Buff Tracker's chat messages now follow your Daseeki Core theme: the addon's tag
  takes the suite brand colour and errors read in your theme's own warning colour
  rather than a fixed one. The HUD countdown numbers are drawn in the suite's
  condensed outlined numeral face so they stay legible over the game world. Nothing
  the HUD does has changed, and without Daseeki Core installed everything looks
  exactly as it did before.

## 2.1.0
- Settings rebuilt on the new Daseeki Core 2.0 interface (requires Daseeki Core 2.0.0+).
- Two-pane layout: profiles and frame settings on the left, tracked-buff list and buff
  editor on the right; the active profile is pinned to the top of the profile list.
- Buff editor redesigned with aligned fields and an Item/Macro toggle (replaces the old
  overlapping rows); tracked-buff list gains aligned Buff / Action / Faction headers.
- Fixed: page scrolling no longer stops while the buff editor is open.
- Fixed: the HUD icon glow, silently broken by the 1.15.9 client patch (Blizzard removed
  the game function it relied on), is back — reimplemented self-contained so future
  client UI changes cannot remove it again.

## 2.0.0
- Spell-ID buff identification: buffs that share the same aura name are now told apart
  by their source spell ID (e.g. Mageblood Potion vs Nightfin Soup, both of which apply
  the aura "Mana Regeneration"). Add either from the buff picker and track them
  independently, each with its own icon and countdown.
- Export/Import format v4 now carries the spellID, so spell-ID-identified entries
  survive export → import → reload without degrading to a bare name match. Older v1/v2/v3
  export strings still import.
- Safer login migration: legacy Mageblood tracking is upgraded to spell ID 24363 only
  when the entry is actually the old Mageblood tracker, so deliberately-created Nightfin
  Soup entries are no longer clobbered.
