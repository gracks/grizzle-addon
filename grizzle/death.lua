-- Grizzle death (doc/grizzle/death.md): releasing leaves part of your soul in a tombstone where you
-- fell. No buff marks it; the world map shows a pin at your tombstone, and the XP bar shades the XP
-- it holds, past your current XP, in a pale spectral silver-white. The server says where it is in an
-- addon whisper "GRZ_TOMB" <zone>\t<x>\t<y>\t<xp> (x, y 0-100 on the zone's map), or an empty one
-- for none, after login and on each release and reclaim. Kept per character for /reload.

local PREFIX = "GRZ_TOMB";
local SILVER_R, SILVER_G, SILVER_B = 0.85, 0.88, 0.95;

GrizzleTombstone = GrizzleTombstone or nil;   -- { zone, x, y, xp } (SavedVariablesPerCharacter)

-- --- XP bar ----------------------------------------------------------------------------------

local shade = MainMenuExpBar:CreateTexture(nil, "ARTWORK");
shade:SetTexture("Interface\\TargetingFrame\\UI-StatusBar");
shade:SetVertexColor(SILVER_R, SILVER_G, SILVER_B, 0.55);
shade:Hide();

local function UpdateBar()
    local stone = GrizzleTombstone;
    local max = UnitXPMax("player");
    if not stone or not max or max == 0 then
        shade:Hide();
        return;
    end
    local cur = UnitXP("player");
    local width = MainMenuExpBar:GetWidth();
    local from = cur / max * width;
    local to = math.min(cur + stone.xp, max) / max * width;
    if to - from < 1 then
        shade:Hide();
        return;
    end
    shade:ClearAllPoints();
    shade:SetPoint("TOPLEFT", MainMenuExpBar, "TOPLEFT", from, 0);
    shade:SetPoint("BOTTOMLEFT", MainMenuExpBar, "BOTTOMLEFT", from, 0);
    shade:SetWidth(to - from);
    shade:Show();
end

-- The stock tooltip is rebuilt about once a second by ExhaustionToolTipText (ExhaustionTick's
-- OnUpdate), which drops added lines, so the line is added again after each rebuild.
local function AddTombstoneLine()
    local stone = GrizzleTombstone;
    local max = UnitXPMax("player");
    if not stone or not max or max == 0 then
        return;
    end
    local pct = math.floor(stone.xp * 100 / max + 0.5);
    GameTooltip:AddLine(pct .. "% of a level lingers at your tombstone (" .. stone.zone .. ")",
        SILVER_R, SILVER_G, SILVER_B, true);
    GameTooltip:Show();
end

MainMenuExpBar:HookScript("OnEnter", function(self)
    if not GrizzleTombstone then
        return;
    end
    if not GameTooltip:IsOwned(self) then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    end
    AddTombstoneLine();
end);

hooksecurefunc("ExhaustionToolTipText", function()
    if GameTooltip:IsOwned(MainMenuExpBar) or GameTooltip:IsOwned(ExhaustionTick) then
        AddTombstoneLine();
    end
end);

-- --- world map pin ---------------------------------------------------------------------------

local pin = CreateFrame("Frame", "GrizzleTombstonePin", WorldMapButton);
pin:SetSize(16, 16);
pin:SetFrameLevel(WorldMapButton:GetFrameLevel() + 5);
pin:EnableMouse(true);
local pinTexture = pin:CreateTexture(nil, "OVERLAY");
pinTexture:SetAllPoints();
pinTexture:SetTexture("Interface\\WorldMap\\WorldMapCorpse");   -- the stock corpse tombstone
pin:SetScript("OnEnter", function(self)
    WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT");
    WorldMapTooltip:SetText("Your tombstone", SILVER_R, SILVER_G, SILVER_B);
    WorldMapTooltip:Show();
end);
pin:SetScript("OnLeave", function() WorldMapTooltip:Hide(); end);
pin:Hide();

local function ShownZoneName()
    local zone = GetCurrentMapZone();
    if not zone or zone == 0 then
        return nil;
    end
    return (select(zone, GetMapZones(GetCurrentMapContinent())));
end

local function UpdatePin()
    local stone = GrizzleTombstone;
    if not stone or ShownZoneName() ~= stone.zone then
        pin:Hide();
        return;
    end
    pin:ClearAllPoints();
    pin:SetPoint("CENTER", WorldMapButton, "TOPLEFT",
        stone.x / 100 * WorldMapButton:GetWidth(), -stone.y / 100 * WorldMapButton:GetHeight());
    pin:Show();
end

-- WORLD_MAP_UPDATE alone missed opening the map on the zone it already showed.
hooksecurefunc("WorldMapFrame_Update", UpdatePin);
WorldMapFrame:HookScript("OnShow", UpdatePin);

-- --- server messages -------------------------------------------------------------------------

local events = CreateFrame("Frame");
events:RegisterEvent("CHAT_MSG_ADDON");
events:RegisterEvent("PLAYER_ENTERING_WORLD");
events:RegisterEvent("PLAYER_XP_UPDATE");
events:RegisterEvent("PLAYER_LEVEL_UP");
events:RegisterEvent("WORLD_MAP_UPDATE");
events:SetScript("OnEvent", function(self, event, prefix, message, channel)
    if event == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or channel ~= "WHISPER" then
            return;
        end
        local zone, x, y, xp = strsplit("\t", message or "");
        xp = tonumber(xp);
        if zone and zone ~= "" and xp then
            GrizzleTombstone = { zone = zone, x = tonumber(x) or 0, y = tonumber(y) or 0, xp = xp };
        else
            GrizzleTombstone = nil;
        end
        UpdatePin();
        UpdateBar();
    elseif event == "WORLD_MAP_UPDATE" then
        UpdatePin();
    else
        UpdateBar();
    end
end);
