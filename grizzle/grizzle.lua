-- Grizzle Addon
-- Custom tooltip overrides for cold system spells and Bright Campfire

-- Spell IDs (from worldserver.conf)
local CAMPFIRE_SPELL_ID = 25085;  -- Bright Campfire (ColdSystem.CampfireSpellId)
local WARNING_SPELL_ID = 38639;   -- Biting Cold warning (ColdSystem.WarningSpellId)
local COLD_SPELL_ID = 68510;      -- Penetrating Cold (ColdSystem.ColdSpellId)
local WARMTH_SPELL_ID = 7358;     -- Cozy Fire: the campfire rest buff (CampfireRest.SpellId)
local REST_TEXT = "Rested by a campfire: +15% health, +3% critical strike chance, and faster health and mana regeneration out of combat.";
local WET_SPELL_ID = 61870;       -- Drenched (Wet.SpellId)

-- Global tooltip scanner - runs on every frame to catch any tooltip
-- This is a fallback that should catch tooltips regardless of how they're created
local tooltipScannerFrame = CreateFrame("Frame");
tooltipScannerFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed;
    -- Only check every 0.03 seconds to avoid performance issues but still be responsive
    if self.elapsed < 0.03 then
        return;
    end
    self.elapsed = 0;
    
    -- Check GameTooltip (main tooltip)
    if GameTooltip:IsVisible() then
        local firstLine = _G["GameTooltipTextLeft1"];
        if firstLine then
            local text = firstLine:GetText();
            if text then
                local lowerText = string.lower(text);
                -- Check if this is Penetrating Cold and hasn't been modified yet
                if string.find(lowerText, "penetrating") and not string.find(lowerText, "shivering") then
                    -- Check if we've already modified this tooltip
                    if not GameTooltip._grizzleColdModified then
                        GameTooltip._grizzleColdModified = true;
                        ModifyColdTooltip();
                    end
                elseif string.find(lowerText, "biting") and not GameTooltip._grizzleWarningModified then
                    GameTooltip._grizzleWarningModified = true;
                    ModifyWarningTooltip();
                elseif string.find(lowerText, "cozy") and not GameTooltip._grizzleWarmthModified then
                    GameTooltip._grizzleWarmthModified = true;
                    ModifyWarmthTooltip();
                end
            end
        end
    else
        -- Reset flags when tooltip is hidden
        GameTooltip._grizzleColdModified = nil;
        GameTooltip._grizzleWarningModified = nil;
        GameTooltip._grizzleWarmthModified = nil;
    end
end);

-- Campfire values (from worldserver.conf)
local CAMPFIRE_CAST_TIME = 5;     -- Cast time in seconds (ColdSystem.CampfireCastTime = 5000ms)
local CAMPFIRE_COOLDOWN = 15;     -- Cooldown in minutes (ColdSystem.CampfireCooldown = 900000ms)
local REAGENT_ITEM_ID = 4470;    -- Simple Wood (item ID)
local REAGENT_QUANTITY = 1;       -- Quantity required

-- Function to get item name from item ID
-- Simple Wood (4470) is a common crafting material
local function GetItemName(itemID)
    if itemID == 4470 then
        -- Try to get item info (may return nil if not loaded yet)
        local itemName, itemLink = GetItemInfo(itemID);
        if itemName then
            return itemName;
        end
        if itemLink then
            -- Extract item name from item link (format: |cff...|Hitem:ID:...|h[Name]|h|r)
            local name = string.match(itemLink, "%[(.-)%]");
            if name then
                return name;
            end
        end
        -- Fallback - Simple Wood is the common name for item 4470
        return "Simple Wood";
    end
    -- For other items, try GetItemInfo
    local itemName = GetItemInfo(itemID);
    return itemName or "Item " .. itemID;
end

-- Function to modify campfire tooltip
local function ModifyCampfireTooltip()
    local spellID = select(2, GameTooltip:GetSpell());
    if spellID ~= CAMPFIRE_SPELL_ID then
        return;
    end
    
    local numLines = GameTooltip:NumLines();
    local modified = false;
    
    -- Simple, direct reagent text - always use plain text for maximum compatibility
    local reagentText = "Requires: Simple Wood";
    
    -- First pass: modify existing lines
    for i = 1, numLines do
        local leftText = _G["GameTooltipTextLeft" .. i];
        if leftText then
            local text = leftText:GetText();
            if text then
                -- Replace cast time
                if string.find(string.lower(text), "cast") and (string.find(string.lower(text), "time") or string.find(string.lower(text), "sec")) then
                    local newText = string.gsub(text, "%d+%.?%d*%s*sec%.?", CAMPFIRE_CAST_TIME .. " sec");
                    if newText ~= text then
                        leftText:SetText(newText);
                        modified = true;
                    end
                end
                -- Replace cooldown
                if string.find(string.lower(text), "cooldown") then
                    local newText = string.gsub(text, "%d+%.?%d*%s*min%.?", CAMPFIRE_COOLDOWN .. " min");
                    if newText ~= text then
                        leftText:SetText(newText);
                        modified = true;
                    end
                end
            end
        end
    end
    
    -- ALWAYS add reagent line at the end - don't check if it exists, just add it
    -- This ensures it's always visible
    GameTooltip:AddLine(" ");
    GameTooltip:AddLine(reagentText, 1, 0.82, 0, true);  -- Gold color like other requirements
    modified = true;
    
    if modified then
        GameTooltip:Show();
    end
end

-- Function to override Biting Cold (warning) tooltip
local function ModifyWarningTooltip()
    -- Find the description line and replace it
    local numLines = GameTooltip:NumLines();
    local foundDescription = false;
    
    for i = 1, numLines do
        local leftText = _G["GameTooltipTextLeft" .. i];
        if leftText then
            local text = leftText:GetText();
            if text and not foundDescription then
                -- Look for the main description (usually the first non-empty line after the title)
                -- Replace it with our custom description
                if string.len(text) > 10 and not string.find(text, "Rank") and not string.find(text, "Requires") then
                    leftText:SetText("You are growing cold. If you don't find warmth soon, you will suffer from Penetrating Cold, which slows your attack speed, casting speed, and cooldown recovery.");
                    foundDescription = true;
                end
            end
        end
    end
    
    -- If we didn't find a description line, add one at the end
    if not foundDescription then
        GameTooltip:AddLine("You are growing cold. If you don't find warmth soon, you will suffer from Penetrating Cold, which slows your attack speed, casting speed, and cooldown recovery.", 1, 1, 1, true);
        GameTooltip:Show();
    end
end

-- Function to override Penetrating Cold (cold debuff) tooltip
local function ModifyColdTooltip()
    local numLines = GameTooltip:NumLines();
    local foundTitle = false;
    local foundDescription = false;
    
    -- First, always replace the first line if it contains "Penetrating"
    local firstLine = _G["GameTooltipTextLeft1"];
    if firstLine then
        local text = firstLine:GetText();
        if text and string.find(string.lower(text), "penetrating") then
            firstLine:SetText("Shivering");
            foundTitle = true;
        end
    end
    
    -- Then scan all lines for damage/frost text to replace
    for i = 1, numLines do
        local leftText = _G["GameTooltipTextLeft" .. i];
        if leftText then
            local text = leftText:GetText();
            if text then
                local lowerText = string.lower(text);
                -- Replace any line that mentions damage, frost, or the original description
                if not foundDescription and (string.find(lowerText, "damage") or string.find(lowerText, "frost") or string.find(lowerText, "inflicted") or string.find(lowerText, "every") or string.find(lowerText, "sec")) then
                    leftText:SetText("Attack rate, cast time, and cooldowns are slowed by 40%. Find a warm campfire.");
                    foundDescription = true;
                end
            end
        end
    end
    
    -- If we didn't find the title in first line, replace it anyway
    if not foundTitle and firstLine then
        firstLine:SetText("Shivering");
        foundTitle = true;
    end
    
    -- If we didn't find the description, add it at the end
    if not foundDescription then
        GameTooltip:AddLine("Attack rate, cast time, and cooldowns are slowed by 40%. Find a warm campfire.", 1, 0.82, 0, true);  -- Yellow color
    end
    
    -- Always show the tooltip after modification
    GameTooltip:Show();
end

-- Function to override the Cozy Fire tooltip (campfire rest buff; it says "Increases Spirit by 7", which is switched off)
local function ModifyWarmthTooltip()
    local numLines = GameTooltip:NumLines();
    local foundDescription = false;
    
    for i = 1, numLines do
        local leftText = _G["GameTooltipTextLeft" .. i];
        if leftText then
            local text = leftText:GetText();
            if text and not foundDescription then
                -- Look for the main description line
                if string.len(text) > 10 and not string.find(text, "Rank") and not string.find(text, "Requires") and not string.find(text, "Cozy") then
                    leftText:SetText(REST_TEXT);
                    foundDescription = true;
                end
            end
        end
    end
    
    -- If we didn't find a description line, add one at the end
    if not foundDescription then
        GameTooltip:AddLine(REST_TEXT, 1, 1, 1, true);
        GameTooltip:Show();
    end
end

-- Hook GameTooltip:SetSpell to override tooltips
local originalSetSpell = GameTooltip.SetSpell;
function GameTooltip:SetSpell(spellID, rank)
    originalSetSpell(self, spellID, rank);
    if spellID == CAMPFIRE_SPELL_ID then
        -- Use a small delay to ensure tooltip is populated
        local frame = CreateFrame("Frame");
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed;
            if self.elapsed >= 0.1 then
                ModifyCampfireTooltip();
                self:SetScript("OnUpdate", nil);
            end
        end);
    elseif spellID == WARNING_SPELL_ID then
        ModifyWarningTooltip();
    elseif spellID == COLD_SPELL_ID then
        -- Use a small delay to ensure tooltip is populated
        local frame = CreateFrame("Frame");
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed;
            if self.elapsed >= 0.1 then
                ModifyColdTooltip();
                self:SetScript("OnUpdate", nil);
            end
        end);
    elseif spellID == WARMTH_SPELL_ID then
        ModifyWarmthTooltip();
    end
end

-- Also hook SetSpellByID for spell links
if GameTooltip.SetSpellByID then
    local originalSetSpellByID = GameTooltip.SetSpellByID;
    function GameTooltip:SetSpellByID(spellID)
        originalSetSpellByID(self, spellID);
        if spellID == CAMPFIRE_SPELL_ID then
            ModifyCampfireTooltip();
        elseif spellID == WARNING_SPELL_ID then
            ModifyWarningTooltip();
        elseif spellID == COLD_SPELL_ID then
            ModifyColdTooltip();
        elseif spellID == WARMTH_SPELL_ID then
            ModifyWarmthTooltip();
        end
    end
end

-- Hook for action bar and spellbook tooltips
local frame = CreateFrame("Frame");
frame:RegisterEvent("ADDON_LOADED");
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName:lower() == "grizzle" then
        -- Hook GameTooltip:OnTooltipSetSpell for additional coverage
        GameTooltip:HookScript("OnTooltipSetSpell", function(self)
            local spellID = select(2, self:GetSpell());
            if spellID == CAMPFIRE_SPELL_ID then
                -- Try immediately and also with delay
                ModifyCampfireTooltip();
                local frame = CreateFrame("Frame");
                frame:SetScript("OnUpdate", function(self, elapsed)
                    self.elapsed = (self.elapsed or 0) + elapsed;
                    ModifyCampfireTooltip();  -- Try multiple times
                    if self.elapsed >= 0.2 then
                        self:SetScript("OnUpdate", nil);
                    end
                end);
            elseif spellID == WARNING_SPELL_ID then
                ModifyWarningTooltip();
            elseif spellID == COLD_SPELL_ID then
                ModifyColdTooltip();
            elseif spellID == WARMTH_SPELL_ID then
                ModifyWarmthTooltip();
            end
        end);
        
        -- Hook OnTooltipSetUnitAura for additional coverage
        GameTooltip:HookScript("OnTooltipSetUnitAura", function(self)
            -- Try multiple times with delays to catch the tooltip after it's fully populated
            local attemptCount = 0;
            local frame = CreateFrame("Frame");
            frame:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = (self.elapsed or 0) + elapsed;
                attemptCount = attemptCount + 1;
                
                -- Check the first line of the tooltip to identify the spell
                local firstLine = _G["GameTooltipTextLeft1"];
                if firstLine then
                    local text = firstLine:GetText();
                    if text then
                        local lowerText = string.lower(text);
                        if string.find(lowerText, "penetrating") and not string.find(lowerText, "shivering") then
                            -- This is the cold spell, modify it
                            ModifyColdTooltip();
                            self:SetScript("OnUpdate", nil);
                            return;
                        elseif string.find(lowerText, "biting") then
                            ModifyWarningTooltip();
                            self:SetScript("OnUpdate", nil);
                            return;
                        elseif string.find(lowerText, "cozy") then
                            ModifyWarmthTooltip();
                            self:SetScript("OnUpdate", nil);
                            return;
                        end
                    end
                end
                
                -- Stop after 10 attempts (1 second) to avoid infinite loops
                if attemptCount >= 10 or self.elapsed >= 1.0 then
                    self:SetScript("OnUpdate", nil);
                end
            end);
        end);
        
        -- Also hook OnUpdate for continuous checking (for both spell and unit aura tooltips)
        GameTooltip:HookScript("OnUpdate", function(self)
            -- First check for spell tooltips
            local spellID = select(2, self:GetSpell());
            if spellID == CAMPFIRE_SPELL_ID then
                -- Only modify once per tooltip show to avoid spam
                if not self._grizzleModified then
                    self._grizzleModified = true;
                    ModifyCampfireTooltip();
                end
            elseif spellID == COLD_SPELL_ID then
                if not self._grizzleModified then
                    self._grizzleModified = true;
                    ModifyColdTooltip();
                end
            elseif spellID == WARNING_SPELL_ID then
                if not self._grizzleModified then
                    self._grizzleModified = true;
                    ModifyWarningTooltip();
                end
            elseif spellID == WARMTH_SPELL_ID then
                if not self._grizzleModified then
                    self._grizzleModified = true;
                    ModifyWarmthTooltip();
                end
            elseif not spellID then
                -- This might be a unit aura tooltip - check tooltip text
                -- Only check if we haven't modified it yet
                if not self._grizzleModified then
                    local firstLine = _G["GameTooltipTextLeft1"];
                    if firstLine then
                        local text = firstLine:GetText();
                        if text then
                            local lowerText = string.lower(text);
                            if string.find(lowerText, "penetrating") and not string.find(lowerText, "shivering") then
                                -- This is the cold spell, modify it
                                self._grizzleModified = true;
                                ModifyColdTooltip();
                            elseif string.find(lowerText, "biting") then
                                self._grizzleModified = true;
                                ModifyWarningTooltip();
                            elseif string.find(lowerText, "cozy") then
                                self._grizzleModified = true;
                                ModifyWarmthTooltip();
                            end
                        end
                    end
                end
            end
        end);
        
        -- Reset flag when tooltip is hidden
        GameTooltip:HookScript("OnHide", function(self)
            self._grizzleModified = nil;
        end);
        
        -- Hook Show to catch tooltips that are set after initial display
        local originalShow = GameTooltip.Show;
        function GameTooltip:Show()
            originalShow(self);
            local spellID = select(2, self:GetSpell());
            if spellID == CAMPFIRE_SPELL_ID then
                -- Use multiple update cycles to ensure tooltip is fully populated
                local updateCount = 0;
                local frame = CreateFrame("Frame");
                frame:SetScript("OnUpdate", function(self, elapsed)
                    updateCount = updateCount + 1;
                    -- Try multiple times to catch the tooltip after it's fully populated
                    ModifyCampfireTooltip();
                    if updateCount >= 3 then
                        self:SetScript("OnUpdate", nil);
                    end
                end);
            elseif spellID == WARNING_SPELL_ID then
                ModifyWarningTooltip();
            end
        end
        
        -- Hook SetUnitAura to catch aura tooltips when inspecting units (including yourself)
        local originalSetUnitAura = GameTooltip.SetUnitAura;
        function GameTooltip:SetUnitAura(unit, index, filter)
            originalSetUnitAura(self, unit, index, filter);
            -- Get the spell ID from the aura using UnitAura
            local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitAura(unit, index, filter);
            if not spellId then
                -- Try the other filter
                name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitAura(unit, index, filter == "HELPFUL" and "HARMFUL" or "HELPFUL");
            end
            if spellId then
                if spellId == COLD_SPELL_ID then
                    -- Use a small delay to ensure tooltip is populated
                    local frame = CreateFrame("Frame");
                    frame:SetScript("OnUpdate", function(self, elapsed)
                        self.elapsed = (self.elapsed or 0) + elapsed;
                        if self.elapsed >= 0.1 then
                            ModifyColdTooltip();
                            self:SetScript("OnUpdate", nil);
                        end
                    end);
                elseif spellId == WARNING_SPELL_ID then
                    ModifyWarningTooltip();
                elseif spellId == WARMTH_SPELL_ID then
                    ModifyWarmthTooltip();
                end
            end
        end
        
        -- Hook for spellbook (if available)
        if SpellButton_OnEnter then
            hooksecurefunc("SpellButton_OnEnter", function(button)
                local spellID = button:GetSpellID();
                if spellID == CAMPFIRE_SPELL_ID then
                    ModifyCampfireTooltip();
                elseif spellID == WARNING_SPELL_ID then
                    ModifyWarningTooltip();
                end
            end);
        end
    end
end);

-- Grizzle's borrowed marker spells: the game's own tooltip text doesn't fit (or is missing), so
-- replace it with what the marker actually does. The buff bar uses SetUnitAura; target and party
-- frames use SetUnitBuff / SetUnitDebuff.
local MARKER_TEXT = {
    [WET_SPELL_ID] = {   -- Drenched (Wet.SpellId)
        old = "Drenched!",
        text = "Fire hurts you less; frost and nature hurt you more. Slower health regen while standing. Dry off indoors or by a fire.",
    },
    [56489] = {          -- Warming Up (CampfireRest.WarmingSpellId)
        old = "Movement speed increased.",
        text = "Warming up by the fire. Stay seated until this runs out to get Cozy Fire.",
    },
    -- Cozy Fire (CampfireRest.SpellId) is handled by ModifyWarmthTooltip above
};

local function AddMarkerText(tooltip, spellId)
    local marker = spellId and MARKER_TEXT[spellId];
    if not marker then return end
    if marker.old then
        for i = 2, tooltip:NumLines() do
            local line = _G["GameTooltipTextLeft" .. i];
            if line and line:GetText() == marker.old then
                line:SetText(marker.text);
                tooltip:Show();
                return;
            end
        end
    end
    tooltip:AddLine(marker.text, 1, 0.82, 0, true);
    tooltip:Show();
end

hooksecurefunc(GameTooltip, "SetUnitAura", function(self, unit, index, filter)
    AddMarkerText(self, select(11, UnitAura(unit, index, filter)));
end);
hooksecurefunc(GameTooltip, "SetUnitBuff", function(self, unit, index, filter)
    AddMarkerText(self, select(11, UnitBuff(unit, index, filter)));
end);
hooksecurefunc(GameTooltip, "SetUnitDebuff", function(self, unit, index, filter)
    AddMarkerText(self, select(11, UnitDebuff(unit, index, filter)));
end);
