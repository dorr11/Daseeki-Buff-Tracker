# Changelog

## Unreleased

- Fixed: a tracked buff whose name Buff Tracker corrected for you no longer keeps the
  old buff's icon forever. Some buffs are named one thing on the item and another thing
  in your buff bar — "Mageblood" is "Mana Regeneration", "Greater Fire Power" is
  "Greater Firepower" — and Buff Tracker quietly repairs those names when it loads. It
  also remembers each entry's icon the first time it sees the buff on you. What it never
  did was connect the two: the icon was learned under the old name, the name was then
  corrected, and the icon stayed — permanently, and through a profile export and import.
  Each remembered icon now records which buff name taught it to Buff Tracker, and is
  used only while that name still matches. Rename an entry yourself in the settings and
  the same thing happens: the icon is looked up again instead of kept.

- Fixed: a temporary weapon enchant whose remaining time the game will not report is now
  treated as unknown instead of as permanent. Buff Tracker used to answer "infinite" when
  it could not read the timer, which is the wrong way round — your Windfury could be
  seconds from dropping and the reminder icon stayed hidden because, as far as the addon
  was concerned, it never expires. Now the icon appears with a blank timer until the game
  answers, which is usually the very next moment.

- Changed: Daseeki Buff Tracker is now licensed **All Rights Reserved** rather than MIT, matching the rest of the suite. This rides the next release — 2.1.1 was published to CurseForge with the MIT file still in place.
- Changed: if your Daseeki Core is too old for the Buff Tracker settings page, the message now tells you which version you actually have installed, in the same wording every Daseeki addon uses.
- Fixed: dragging a tracked buff to reorder it will keep dropping where you point, whatever
  the settings window is scaled to. Nothing changes for you today — at the scale every
  install runs at right now, the drop bar already sits under the pointer, and it still will.
  This is a repair to the arithmetic behind it, made before it could ever be seen. The window
  measured your cursor against the list using the **screen's** scale rather than the **list's**;
  those are the same number today, so the sum came out right, but they stop being the same the
  moment anything above the list is scaled — and then the error is not a fixed few pixels, it
  grows the further up the list you drag, so the bar drifts away from the mouse and buffs land
  several rows from where the bar said they would. Daseeki Raid Prep shipped this exact shape
  and a player hit it the week a list-scale slider arrived. The cursor is now measured against
  the list at the list's own scale, so the answer is right at any scale, including yours.

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
