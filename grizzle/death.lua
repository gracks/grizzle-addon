-- Grizzle death (doc/grizzle/death.md): releasing leaves part of your soul in a tombstone where you
-- fell. No buff marks it; the world map shows a pin at your tombstone, and the XP bar shades the XP
-- it holds, past your current XP, in a pale spectral silver-white. The server says where it is in an
-- addon whisper "GRZ_TOMB" <zone>\t<x>\t<y>\t<xp>[\tshade] (x, y 0-100 on the zone's map; "shade" when
-- Death.Shades shows it as your shade), or an empty one for none, after login and on each release and
-- reclaim. Kept per character for /reload.

local PREFIX = "GRZ_TOMB";
local SILVER_R, SILVER_G, SILVER_B = 0.85, 0.88, 0.95;

GrizzleTombstone = GrizzleTombstone or nil;   -- { zone, x, y, xp, shade } (SavedVariablesPerCharacter)

local function StoneName(stone)
    return stone and stone.shade and "shade" or "tombstone";
end

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
    GameTooltip:AddLine(pct .. "% of a level lingers at your " .. StoneName(stone) .. " (" .. stone.zone .. ")",
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
-- the stock corpse tombstone, taken from the map's own corpse frame (path and crop as the client has them)
local stockCorpse = WorldMapCorpse and WorldMapCorpse.GetRegions and WorldMapCorpse:GetRegions();
if stockCorpse and stockCorpse.GetTexture and stockCorpse:GetTexture() then
    pinTexture:SetTexture(stockCorpse:GetTexture());
    pinTexture:SetTexCoord(stockCorpse:GetTexCoord());
else
    pinTexture:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull");
    pinTexture:SetVertexColor(SILVER_R, SILVER_G, SILVER_B);
end
pin:SetScript("OnEnter", function(self)
    WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT");
    WorldMapTooltip:SetText("Your " .. StoneName(GrizzleTombstone), SILVER_R, SILVER_G, SILVER_B);
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
        local zone, x, y, xp, kind = strsplit("\t", message or "");
        xp = tonumber(xp);
        if zone and zone ~= "" and xp then
            GrizzleTombstone = { zone = zone, x = tonumber(x) or 0, y = tonumber(y) or 0, xp = xp, shade = kind == "shade" };
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

-- --- a level lost --------------------------------------------------------------------------------
-- The server sends an addon whisper "GRZ_LVLLOSS" for a level lost to death. "lost", as the ghost reaches the
-- graveyard: this sound plays (with Death.LevelLossVisual, the red level-up model, from the server). "mute", just
-- before the level drops at the revive: the client plays its level-up ding on any change of the level, a drop
-- included, so sound effects go off until 4.5 s after the drop (the ding is over by then), or 3 s without one.
-- Music and ambience play on. GrizzleSfxMuted (SavedVariables) turns them back on after a /reload in between.

local LEVEL_LOSS_PREFIX = "GRZ_LVLLOSS";
local LEVEL_LOSS_SOUND = "Interface\\AddOns\\grizzle\\sounds\\levelloss.wav";

GrizzleSfxMuted = GrizzleSfxMuted or nil;

local levelLoss = CreateFrame("Frame");
local levelBefore, timeLeft;

local function Unmute()
    levelLoss:SetScript("OnUpdate", nil);
    levelBefore = nil;
    if GrizzleSfxMuted then
        GrizzleSfxMuted = nil;
        SetCVar("Sound_EnableSFX", 1);
    end
end

local function OnUpdate(self, elapsed)
    if levelBefore and UnitLevel("player") < levelBefore then
        levelBefore = nil;
        timeLeft = 4.5;
    end
    timeLeft = timeLeft - elapsed;
    if timeLeft <= 0 then
        Unmute();
    end
end

levelLoss:RegisterEvent("CHAT_MSG_ADDON");
levelLoss:RegisterEvent("PLAYER_LOGIN");
levelLoss:RegisterEvent("PLAYER_LOGOUT");
levelLoss:SetScript("OnEvent", function(self, event, prefix, message, channel)
    if event == "CHAT_MSG_ADDON" then
        if prefix ~= LEVEL_LOSS_PREFIX or channel ~= "WHISPER" then
            return;
        end
        if message == "lost" then
            PlaySoundFile(LEVEL_LOSS_SOUND);
        elseif message == "mute" then
            if GetCVar("Sound_EnableSFX") == "1" then
                GrizzleSfxMuted = true;
                SetCVar("Sound_EnableSFX", 0);
            end
            levelBefore = UnitLevel("player");
            timeLeft = 3;
            self:SetScript("OnUpdate", OnUpdate);
        end
    else
        Unmute();
    end
end);
