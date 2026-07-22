# Changelog

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
