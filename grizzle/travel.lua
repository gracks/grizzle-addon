-- Grizzle travel (doc/grizzle/travel.md): no minimap and no map position. The world is found by
-- looking at it: the minimap is hidden, and the world map shows no arrow for you or your party.
-- What the minimap cluster carried that's still wanted (day/night and calendar, clock, mail,
-- PvP queue) moves to the top right corner, and a small compass sits at the top of the screen.
-- The Dungeon Finder is off on the server, so its button goes too.

-- --- minimap: hide it, keep the useful buttons ------------------------------------------------

local corner = CreateFrame("Frame", "GrizzleCornerFrame", UIParent);
corner:SetSize(120, 40);
corner:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -4);

local function Keep(frame, ...)
    if not frame then
        return;
    end
    frame:SetParent(corner);
    frame:ClearAllPoints();
    frame:SetPoint(...);
end

local function KeepClock()
    if TimeManagerClockButton then
        Keep(TimeManagerClockButton, "TOPRIGHT", GameTimeFrame, "TOPLEFT", 4, -6);
    end
end

local function HideMinimap()
    MinimapCluster:Hide();
    Keep(GameTimeFrame, "TOPRIGHT", corner, "TOPRIGHT", 0, 0);
    KeepClock();
    Keep(MiniMapMailFrame, "TOPRIGHT", GameTimeFrame, "BOTTOMRIGHT", 2, 2);
    Keep(MiniMapBattlefieldFrame, "TOPRIGHT", MiniMapMailFrame, "TOPLEFT", 2, 0);
end

MinimapCluster:HookScript("OnShow", function(self) self:Hide(); end);

-- the clock comes from Blizzard_TimeManager, which can load after us
local minimapFrame = CreateFrame("Frame");
minimapFrame:RegisterEvent("PLAYER_LOGIN");
minimapFrame:RegisterEvent("ADDON_LOADED");
minimapFrame:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" then
        HideMinimap();
    elseif name == "Blizzard_TimeManager" then
        KeepClock();
    end
end);

-- the zone map (Shift-M) is a minimap too
ToggleBattlefieldMinimap = function() end;

-- --- world map: no arrow for you or your party --------------------------------------------

local function HideIfShown(frame)
    if frame and frame:IsShown() then
        frame:Hide();
    end
end

-- nor the ping that marks you when the map opens
if WorldMapFrame_PingPlayerPosition then
    WorldMapFrame_PingPlayerPosition = function() end;
end

-- runs after Blizzard's WorldMapButton_OnUpdate has placed them
WorldMapButton:HookScript("OnUpdate", function()
    HideIfShown(WorldMapPlayer);
    HideIfShown(WorldMapPing);
    if ShowWorldMapArrowFrame then
        ShowWorldMapArrowFrame(nil);
    end
    for i = 1, MAX_PARTY_MEMBERS do
        HideIfShown(_G["WorldMapParty" .. i]);
    end
    for i = 1, MAX_RAID_MEMBERS do
        HideIfShown(_G["WorldMapRaid" .. i]);
    end
end);

-- --- Dungeon Finder button ----------------------------------------------------------------

LFDMicroButton:Hide();
LFDMicroButton:HookScript("OnShow", function(self) self:Hide(); end);
MainMenuMicroButton:ClearAllPoints();
MainMenuMicroButton:SetPoint("BOTTOMLEFT", PVPMicroButton, "BOTTOMRIGHT", -3, 0);

-- --- compass ------------------------------------------------------------------------------

local COMPASS_WIDTH = 220;      -- shows 90 degrees either side of where you face
local POINTS = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" };

local compass = CreateFrame("Frame", "GrizzleCompass", UIParent);
compass:SetSize(COMPASS_WIDTH, 18);
compass:SetPoint("TOP", UIParent, "TOP", 0, -6);
compass:SetAlpha(0.8);

local line = compass:CreateTexture(nil, "BACKGROUND");
line:SetTexture(0, 0, 0, 0.35);
line:SetPoint("LEFT");
line:SetPoint("RIGHT");
line:SetHeight(1);

local mark = compass:CreateTexture(nil, "ARTWORK");
mark:SetTexture(1, 0.82, 0, 0.9);
mark:SetSize(1, 6);
mark:SetPoint("BOTTOM", compass, "BOTTOM", 0, 0);

local labels = {};
for bearing, text in pairs(POINTS) do
    local label = compass:CreateFontString(nil, "OVERLAY", bearing % 90 == 0 and "GameFontNormalSmall" or "GameFontHighlightSmall");
    label:SetText(text);
    labels[bearing] = label;
end

local lastFacing;
compass:SetScript("OnUpdate", function()
    local facing = GetPlayerFacing();
    if not facing or facing == lastFacing then
        return;
    end
    lastFacing = facing;
    -- GetPlayerFacing: radians, 0 = north, counter-clockwise; compass bearings run clockwise
    local heading = (360 - math.deg(facing)) % 360;
    for bearing, label in pairs(labels) do
        local delta = (bearing - heading + 540) % 360 - 180;
        if math.abs(delta) <= 90 then
            label:ClearAllPoints();
            label:SetPoint("CENTER", compass, "CENTER", delta * COMPASS_WIDTH / 180, 0);
            label:SetAlpha(1 - (math.abs(delta) / 90) ^ 2);
            label:Show();
        else
            label:Hide();
        end
    end
end);
