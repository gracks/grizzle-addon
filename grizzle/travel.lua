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

-- the buffs sat left of the minimap; move them right, up to the clock. Blizzard re-places them
-- (UIParent_UpdateTopFramePositions), so this runs after it and remembers where it put each frame.
local BUFF_SHIFT = 70;      -- pixels to the right

local function ShiftBuffs()
    for _, name in ipairs({ "ConsolidatedBuffs", "BuffFrame", "TemporaryEnchantFrame" }) do
        local frame = _G[name];
        local relativeTo = frame and select(2, frame:GetPoint(1));
        -- only frames Blizzard anchors to the screen or the minimap (the rest follow them), and only once per placing
        if relativeTo == UIParent or relativeTo == MinimapCluster then
            local right, top = frame:GetRight(), frame:GetTop();
            if right and top and (not frame.grizzleRight or math.abs(frame.grizzleRight - right) > 0.5) then
                frame:ClearAllPoints();
                frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", right - UIParent:GetRight() + BUFF_SHIFT, top - UIParent:GetTop());
                frame.grizzleRight = right + BUFF_SHIFT;
            end
        end
    end
end

if UIParent_UpdateTopFramePositions then
    hooksecurefunc("UIParent_UpdateTopFramePositions", ShiftBuffs);
end
local buffFrame = CreateFrame("Frame");
buffFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
buffFrame:SetScript("OnEvent", ShiftBuffs);

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
    -- N/E/S/W yellow at 13, the diagonals white at 9 (the stock font objects are too close in size to tell apart)
    local cardinal = bearing % 90 == 0;
    local label = compass:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    local font, _, flags = label:GetFont();
    label:SetFont(font, cardinal and 13 or 9, flags);
    label:SetText(text);
    if not cardinal then
        label:SetTextColor(1, 1, 1);
    end
    labels[bearing] = label;
end

-- The Twinned Bindstone's marker (doc/grizzle/bindstone.md "On the compass"): toward the other half, brighter the
-- closer it is. The server whispers GRZ_BIND <angle>\t<step 1-4>\t<ok|trouble|pulled>, or nothing for no marker.
local BIND_PREFIX = "GRZ_BIND";
local BIND_ALPHA = { 0.25, 0.4, 0.6, 0.85 };    -- by step, far to near
local BIND_SIZE = 14;
local bind;                                     -- { bearing, step, state }, or nil
local heading = 0;

local marker = compass:CreateTexture(nil, "ARTWORK");
marker:SetTexture("Interface\\AddOns\\grizzle\\textures\\compass_marker");
marker:SetVertexColor(0.75, 0.7, 1);
marker:SetBlendMode("ADD");
marker:SetSize(BIND_SIZE, BIND_SIZE);
marker:Hide();
local markerAlpha = 0;

local function PlaceMarker()
    if not bind then
        marker:Hide();
        return;
    end
    local delta = (bind.bearing - heading + 540) % 360 - 180;
    local alpha = BIND_ALPHA[bind.step] or BIND_ALPHA[1];
    if math.abs(delta) > 90 then
        -- behind you: at the nearer end of the strip, dimmer
        delta = delta > 0 and 90 or -90;
        alpha = alpha * 0.6;
    end
    marker:ClearAllPoints();
    marker:SetPoint("CENTER", compass, "CENTER", delta * COMPASS_WIDTH / 180, 0);
    markerAlpha = alpha;
    marker:Show();
end

-- trouble (holder dead or fighting): a slow, uneven flicker; pulled (they're coming to you): a pulse
local markerAnim = CreateFrame("Frame");
markerAnim:SetScript("OnUpdate", function()
    if not bind then
        return;
    end
    local t = GetTime();
    local alpha, size = markerAlpha, BIND_SIZE;
    if bind.state == "trouble" then
        alpha = alpha * (0.6 + 0.4 * math.sin(t * 2.5) * math.sin(t * 4.1));
    elseif bind.state == "pulled" then
        local beat = 0.5 + 0.5 * math.sin(t * 6);
        alpha = math.min(1, alpha * (1 + 0.6 * beat));
        size = BIND_SIZE * (1 + 0.3 * beat);
    end
    marker:SetAlpha(alpha);
    marker:SetSize(size, size);
end);

local bindEvents = CreateFrame("Frame");
bindEvents:RegisterEvent("CHAT_MSG_ADDON");
bindEvents:SetScript("OnEvent", function(self, event, prefix, message, channel)
    if prefix ~= BIND_PREFIX or channel ~= "WHISPER" then
        return;
    end
    local angle, step, state = strsplit("\t", message or "");
    angle = tonumber(angle);
    if angle then
        -- the server's angle runs like GetPlayerFacing: 0 = north, counter-clockwise
        bind = { bearing = (360 - math.deg(angle)) % 360, step = tonumber(step) or 1, state = state or "ok" };
    else
        bind = nil;
    end
    PlaceMarker();
end);

local lastFacing;
compass:SetScript("OnUpdate", function()
    local facing = GetPlayerFacing();
    if not facing or facing == lastFacing then
        return;
    end
    lastFacing = facing;
    -- GetPlayerFacing: radians, 0 = north, counter-clockwise; compass bearings run clockwise
    heading = (360 - math.deg(facing)) % 360;
    PlaceMarker();
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
