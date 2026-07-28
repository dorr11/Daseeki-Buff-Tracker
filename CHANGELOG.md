# Changelog

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
