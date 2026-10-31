-- Grizzle Addon
-- Custom tooltip overrides for Basic Campfire and Cozy Fire

-- Spell IDs (from worldserver.conf)
local CAMPFIRE_SPELL_ID = 818;    -- Basic Campfire (ColdSystem.CampfireSpellId)
local WARMTH_SPELL_ID = 7358;     -- Cozy Fire: the campfire rest buff (CampfireRest.SpellId)
local REST_TEXT = "Spirit increased by 8. Rain takes 5 min to drench you, and you dry off in 15 sec.";
local WET_SPELL_ID = 61870;       -- Drenched (Wet.SpellId)

-- Campfire values (from worldserver.conf)
local CAMPFIRE_CAST_TIME = 5;     -- Cast time in seconds (ColdSystem.CampfireCastTime = 5000ms)
local CAMPFIRE_COOLDOWN = 5;      -- Cooldown in minutes (ColdSystem.CampfireCooldown = 300000ms)

-- Function to modify campfire tooltip
local function ModifyCampfireTooltip()
    local spellID = select(2, GameTooltip:GetSpell());
    if spellID ~= CAMPFIRE_SPELL_ID then
        return;
    end
    
    local numLines = GameTooltip:NumLines();
    local modified = false;
    
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
    
    if modified then
        GameTooltip:Show();
    end
end

-- Function to override the Cozy Fire tooltip (campfire rest buff: adds what it does to Drenched)
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
                        if string.find(lowerText, "cozy") then
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
                            if string.find(lowerText, "cozy") then
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
                if spellId == WARMTH_SPELL_ID then
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
                end
            end);
        end
    end
end);

-- Grizzle's borrowed marker spells: the game's own tooltip text doesn't fit (or is missing), so
-- replace it with what the marker actually does. The buff bar uses SetUnitAura; target and party
-- frames use SetUnitBuff / SetUnitDebuff. mobOld / mobText: the same for auras on mobs, whose
-- weather markers do different things (they shorten the mob's aggro range; build-client-patch.py
-- has the player wording).
local MARKER_TEXT = {
    [WET_SPELL_ID] = {   -- Drenched (Wet.SpellId)
        old = "Drenched!",
        text = "You take 10% less Fire damage and 10% more Frost damage. Health and mana regenerate 35% slower. Dry off indoors or by a fire.",
    },
    [90000] = {          -- Snowbound (Snowbound.SpellId)
        mobOld = "Deep snow slows movement, attacks, and casting.",
        mobText = "Deep snow slows movement, attacks, and casting. Shortens how far enemies are noticed.",
    },
    [90001] = {          -- Sandblasted (Sandblasted.SpellId)
        mobOld = "Blowing sand makes attacks and spells against distant targets miss more often. Mana regenerates more slowly unless sitting.",
        mobText = "Blowing sand makes attacks and spells against distant targets miss more often. Shortens how far enemies are noticed.",
    },
    -- Cozy Fire (CampfireRest.SpellId) is handled by ModifyWarmthTooltip above
};

local function AddMarkerText(tooltip, unit, spellId)
    local marker = spellId and MARKER_TEXT[spellId];
    if not marker then return end
    local old, text = marker.old, marker.text;
    if marker.mobText and not UnitIsPlayer(unit) then
        old, text = marker.mobOld, marker.mobText;
    end
    if not text then return end
    if old then
        for i = 2, tooltip:NumLines() do
            local line = _G["GameTooltipTextLeft" .. i];
            if line and line:GetText() == old then
                line:SetText(text);
                tooltip:Show();
                return;
            end
        end
    end
    tooltip:AddLine(text, 1, 0.82, 0, true);
    tooltip:Show();
end

hooksecurefunc(GameTooltip, "SetUnitAura", function(self, unit, index, filter)
    AddMarkerText(self, unit, select(11, UnitAura(unit, index, filter)));
end);
hooksecurefunc(GameTooltip, "SetUnitBuff", function(self, unit, index, filter)
    AddMarkerText(self, unit, select(11, UnitBuff(unit, index, filter)));
end);
hooksecurefunc(GameTooltip, "SetUnitDebuff", function(self, unit, index, filter)
    AddMarkerText(self, unit, select(11, UnitDebuff(unit, index, filter)));
end);

-- Weather markers (Drenched, Snowbound, Sandblasted, Charged Air) come and go on every mob in the weather, so
-- the combat log only reports them on players: they would give away what's nearby. Wraps Blizzard_CombatLog's
-- CombatLog_AddEvent (3.3.5: timestamp, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, ...)
-- for new lines, and COMBATLOG:AddMessage while the log refilters (redraws its history after a filter or settings
-- change), when the line being drawn is still CombatLogGetCurrentEntry().
local WEATHER_MARKERS = { [WET_SPELL_ID] = true, [90000] = true, [90001] = true, [90060] = true };
local MARKER_LOG_EVENTS = { SPELL_AURA_APPLIED = true, SPELL_AURA_REMOVED = true, SPELL_AURA_REFRESH = true };

local function IsHiddenMarkerEvent(...)
    local _, event, _, _, _, _, _, dstFlags, spellId = ...;
    return MARKER_LOG_EVENTS[event] and WEATHER_MARKERS[spellId]
        and bit.band(dstFlags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) == 0;
end

local addingLiveEvent = false;

local function HookCombatLog()
    if type(CombatLog_AddEvent) ~= "function" or CombatLog_AddEvent_Grizzle then return end
    CombatLog_AddEvent_Grizzle = CombatLog_AddEvent;
    CombatLog_AddEvent = function(...)
        if IsHiddenMarkerEvent(...) then return; end
        -- a new line can arrive mid-refilter; it isn't the current entry, so AddMessage mustn't check it
        addingLiveEvent = true;
        local ok, err = pcall(CombatLog_AddEvent_Grizzle, ...);
        addingLiveEvent = false;
        if not ok then error(err, 0); end
    end
    if COMBATLOG and CombatLogUpdateFrame then
        local addMessage = COMBATLOG.AddMessage;
        COMBATLOG.AddMessage = function(self, ...)
            if CombatLogUpdateFrame.refiltering and not addingLiveEvent
                and IsHiddenMarkerEvent(CombatLogGetCurrentEntry()) then
                return;
            end
            return addMessage(self, ...);
        end
    end
end

-- The combat log always shows everything: its quick-button bar (Self, Everything, What happened to me?) is hidden,
-- since a stray click there left a player wondering why half the fight was missing, and its room goes to log lines
-- (Greg's playtest, Oct 28 2026).
local function SimplifyCombatLog()
    local bar = CombatLogQuickButtonFrame_Custom;
    if bar and not bar.grizzleHidden then
        bar.grizzleHidden = true;
        bar:Hide();
        bar:HookScript("OnShow", bar.Hide);
        -- Blizzard_CombatLog drops the log's top edge (and lifts its background) by the bar's height, hidden or
        -- not, whenever FCF_DockUpdate runs; with the bar flat the log's text starts at the top
        bar:SetHeight(0.001);
        if type(FCF_DockUpdate) == "function" then
            FCF_DockUpdate();
        end
        -- FCF_SetButtonSide raises the log's button column (scroll buttons) by the bar's height too, and Blizzard_CombatLog
        -- places it while the bar is still full height; without this the column stuck up past the log's top edge
        if type(FCF_SetButtonSide) == "function" and COMBATLOG and COMBATLOG.buttonSide then
            FCF_SetButtonSide(COMBATLOG, COMBATLOG.buttonSide, true);
        end
    end
    local filters = Blizzard_CombatLog_Filters and Blizzard_CombatLog_Filters.filters;
    if filters and type(Blizzard_CombatLog_QuickButton_OnClick) == "function" then
        for i, filter in ipairs(filters) do
            if filter.name == QUICKBUTTON_NAME_EVERYTHING then
                if Blizzard_CombatLog_Filters.currentFilter ~= i then
                    Blizzard_CombatLog_QuickButton_OnClick(i);
                end
                break;
            end
        end
    end
end

local function SetUpCombatLog()
    HookCombatLog();
    SimplifyCombatLog();
end

local combatLogFrame = CreateFrame("Frame");
combatLogFrame:RegisterEvent("ADDON_LOADED");
combatLogFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
combatLogFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_ENTERING_WORLD" then
        if IsAddOnLoaded("Blizzard_CombatLog") then SimplifyCombatLog(); end
    elseif addonName == "Blizzard_CombatLog" then
        SetUpCombatLog();
    end
end);
if IsAddOnLoaded("Blizzard_CombatLog") then SetUpCombatLog(); end

-- Minimap tracking: only tracking spells you know (Find Herbs, Find Minerals, Hunter tracks...).
-- Town tracking (banker, mailbox, trainers, flight master...) is gone: players find those in the
-- world or ask a guard. GetTrackingInfo marks spells "spell" and town entries "other".
local SetTracking_Blizzard = SetTracking;

local function IsTownTracking(id)
    local _, _, _, category = GetTrackingInfo(id);
    return category ~= "spell";
end

SetTracking = function(id, ...)
    if IsTownTracking(id) then
        return;
    end
    return SetTracking_Blizzard(id, ...);
end

local function ToggleTracking(self, id)
    local _, _, active = GetTrackingInfo(id);
    SetTracking(id, not active);
end

local function MiniMapTrackingDropDown_Initialize_Grizzle()
    local info = UIDropDownMenu_CreateInfo();
    local anyActive = false;
    for id = 1, GetNumTrackingTypes() do
        local _, _, active = GetTrackingInfo(id);
        if active and not IsTownTracking(id) then
            anyActive = true;
        end
    end
    info.text = NONE;
    info.checked = not anyActive;
    info.func = ClearAllTracking;
    info.isNotRadio = true;
    info.keepShownOnClick = true;
    UIDropDownMenu_AddButton(info);

    for id = 1, GetNumTrackingTypes() do
        if not IsTownTracking(id) then
            local name, texture, active = GetTrackingInfo(id);
            info = UIDropDownMenu_CreateInfo();
            info.text = name;
            info.checked = active;
            info.func = ToggleTracking;
            info.icon = texture;
            info.arg1 = id;
            info.isNotRadio = true;
            info.tCoordLeft = 0.0625;
            info.tCoordRight = 0.9;
            info.tCoordTop = 0.0625;
            info.tCoordBottom = 0.9;
            info.keepShownOnClick = true;
            UIDropDownMenu_AddButton(info);
        end
    end
end

-- Switch off any town tracking still on (saved from before, or set some other way), and hide the
-- button while the character knows no tracking spell.
local function UpdateTracking()
    local anySpell = false;
    for id = 1, GetNumTrackingTypes() do
        local _, _, active = GetTrackingInfo(id);
        if IsTownTracking(id) then
            if active then
                SetTracking_Blizzard(id, false);
            end
        else
            anySpell = true;
        end
    end
    if anySpell then
        MiniMapTracking:Show();
    else
        MiniMapTracking:Hide();
    end
end

MiniMapTrackingDropDown_Initialize = MiniMapTrackingDropDown_Initialize_Grizzle;
MiniMapTrackingDropDown.initialize = MiniMapTrackingDropDown_Initialize_Grizzle;

local trackingFrame = CreateFrame("Frame");
trackingFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
trackingFrame:RegisterEvent("MINIMAP_UPDATE_TRACKING");
trackingFrame:RegisterEvent("SPELLS_CHANGED");
trackingFrame:SetScript("OnEvent", UpdateTracking);
