# Grizzle Addon

Client-side addon for AzerothCore custom features.

## Features

### Bright Campfire Tooltip Override
Corrects the cast time and cooldown displayed in the tooltip for the Bright Campfire spell (ID: 25085) to match the server-side values:
- Cast time: 5 seconds (instead of 10 seconds)
- Cooldown: 15 minutes (instead of 5 minutes)

### Biting Cold Warning Tooltip
Overrides the tooltip for the Biting Cold warning spell (ID: 38639) to clearly convey that:
- You are growing cold
- If you don't find warmth soon, you will suffer from Penetrating Cold
- Penetrating Cold slows attack speed, casting speed, and cooldown recovery

This helps players understand that the warning is building up to a more severe debuff with actual gameplay consequences.

### Quieter combat log
Drenched, Snowbound and Sandblasted come and go on every mob in rain, snow or sandstorms. The
combat log only reports them on players.

## Installation

1. Copy the `grizzle` folder (containing `grizzle.toc` and `grizzle.lua`) to your World of Warcraft `Interface/AddOns/` directory.

   Example path:
   ```
   World of Warcraft/Interface/AddOns/grizzle/grizzle.toc
   World of Warcraft/Interface/AddOns/grizzle/grizzle.lua
   ```

2. Restart World of Warcraft or type `/reload` in-game.

3. The addon will automatically load and override tooltips when you hover over the affected spells.

## Configuration

To change the displayed values, edit `grizzle.lua` and modify these constants at the top:

```lua
-- Spell IDs (update if you change them in worldserver.conf)
local CAMPFIRE_SPELL_ID = 25085;
local WARNING_SPELL_ID = 38639;
local COLD_SPELL_ID = 68510;
local WARMTH_SPELL_ID = 7358;

-- Campfire values
local CAMPFIRE_CAST_TIME = 5;     -- Cast time in seconds
local CAMPFIRE_COOLDOWN = 15;      -- Cooldown in minutes
```

Make sure these values match your server configuration in `worldserver.conf`:
- `ColdSystem.CampfireSpellId`
- `ColdSystem.WarningSpellId`
- `ColdSystem.CampfireCastTime` (in milliseconds, divide by 1000 for seconds)
- `ColdSystem.CampfireCooldown` (in milliseconds, divide by 60000 for minutes)

## Customizing Tooltip Text

To change the Biting Cold warning message, edit the `ModifyWarningTooltip()` function in `grizzle.lua`:

```lua
leftText:SetText("Your custom warning message here.");
```

## Notes

- This addon only modifies the **display** of tooltips. The actual server-side behavior is controlled by the AzerothCore configuration.
- The tooltip override works for:
  - Spell tooltips (hovering over spells)
  - Spell links in chat
  - Spellbook entries
  - Action bar tooltips
- If you change spell IDs in `worldserver.conf`, remember to update them in `grizzle.lua` as well.

