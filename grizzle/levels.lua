-- Grizzle hidden levels (doc/grizzle/unknown.md "Not seeing a mob's level"): a creature's level number is gone from
-- the target and focus frames, the unit tooltip and the nameplates. The danger color takes its place: on the target
-- frame in one of several styles (below), a dot on nameplates, the rest of the tooltip's level line. The "??" skull
-- stays. Players and what they control (pets, totems) keep their numbers.
-- /moblevels <n> picks the target frame's style, 0 shows the numbers again (to compare on Test).

GrizzleMobLevelStyle = GrizzleMobLevelStyle or nil;   -- 0: numbers; nil: DEFAULT_STYLE (SavedVariables)

local TEXTURES = "Interface\\AddOns\\grizzle\\textures\\";
local DOT = TEXTURES .. "level_dot";                  -- apps/grizzle/gen_level_dot.py

-- ring: a ring over the portrait's gold one (attackable creatures only), bright: how much of the color it shows.
-- dot: a dot this big where the level circle was; keepCircle: in the stock circle, socket: in a smaller one.
local STYLES = {
    { name = "thin ring", ring = "target_ring_thin", bright = 0.85 },
    { name = "medium ring, dimmer", ring = "target_ring_medium", bright = 0.7 },
    { name = "small dot in the level circle", dot = 11, keepCircle = true },
    { name = "dot in a smaller level circle", dot = 13, socket = 22 },
    { name = "dot on the portrait's ring, no level circle", dot = 13 },
    { name = "thin ring, darker", ring = "target_ring_thin", bright = 0.65 },
    { name = "thin ring, darker still", ring = "target_ring_thin", bright = 0.45 },
};
local DEFAULT_STYLE = 1;

local function Style()
    local n = GrizzleMobLevelStyle or DEFAULT_STYLE;
    return n ~= 0 and STYLES[n] or nil;
end

local function Hiding(unit)
    return Style() and unit and not UnitIsPlayer(unit) and not UnitPlayerControlled(unit);
end

local function MakeDot(parent, anchor, size)
    local dot = parent:CreateTexture(nil, "OVERLAY");
    dot:SetTexture(DOT);
    dot:SetSize(size, size);
    dot:SetPoint("CENTER", anchor, "CENTER", 0, 0);
    dot:Hide();
    return dot;
end

-- --- target and focus frames ----------------------------------------------------------------------

-- The level circle is painted into the frame art, so styles without it use copies that leave it out
-- (apps/grizzle/gen_target_frames.py). Keyed by the art Blizzard picked (normal, elite, rare, rare elite).
local FRAME_ART = {
    ["interface\\targetingframe\\ui-targetingframe"] = TEXTURES .. "target_frame",
    ["interface\\targetingframe\\ui-targetingframe-elite"] = TEXTURES .. "target_frame_elite",
    ["interface\\targetingframe\\ui-targetingframe-rare"] = TEXTURES .. "target_frame_rare",
    ["interface\\targetingframe\\ui-targetingframe-rare-elite"] = TEXTURES .. "target_frame_rare_elite",
};
local FRIENDLY = { r = 1, g = 0.82, b = 0 };           -- Blizzard's color for levels of units you can't attack

local function MakeParts(self)
    local border = self.borderTexture;
    -- their own frame just above the art, so they draw over it
    local frame = CreateFrame("Frame", nil, border:GetParent());
    frame:SetAllPoints(border:GetParent());
    frame:SetFrameLevel(border:GetParent():GetFrameLevel() + 1);
    local parts = {
        ring = frame:CreateTexture(nil, "BACKGROUND"),
        socket = frame:CreateTexture(nil, "ARTWORK"),
        dot = frame:CreateTexture(nil, "OVERLAY"),
        skull = frame:CreateTexture(nil, "OVERLAY"),
    };
    parts.ring:SetAllPoints(border);
    parts.socket:SetTexture(TEXTURES .. "level_socket");
    parts.dot:SetTexture(DOT);
    parts.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull");
    self.grizzleParts = parts;
    return parts;
end

-- puts a part where the level circle's center is: Blizzard centers the number there, shown or not. (Working it out
-- from the art's texture coordinates landed about 20 px low and right in game.)
local function AtCircle(self, part, size)
    part:ClearAllPoints();
    part:SetPoint("CENTER", self.levelText, "CENTER", 0, 0);
    part:SetSize(size, size);
    part:Show();
end

-- runs after Blizzard has set the art, the number and its color, or the skull
local function UpdateFrame(self)
    local border, text = self.borderTexture, self.levelText;
    if not border or not text then
        return;
    end
    local parts = self.grizzleParts or MakeParts(self);
    for _, part in pairs(parts) do
        part:Hide();
    end
    local stock = self.grizzleStockArt;
    local art = stock and FRAME_ART[stock:lower():gsub("%.blp$", "")];
    local unit, style = self.unit, Style();
    if not Hiding(unit) or UnitIsCorpse(unit) then
        if art then
            border:SetTexture(stock);
        end
        return;
    end
    if not art then
        -- other art (boss frames): a dot where the number was
        if text:IsShown() then
            parts.dot:ClearAllPoints();
            parts.dot:SetPoint("CENTER", text, "CENTER", 0, 0);
            parts.dot:SetSize(12, 12);
            parts.dot:SetVertexColor(text:GetTextColor());
            parts.dot:Show();
            text:Hide();
        end
        return;
    end
    local level = UnitLevel(unit);
    local attackable = UnitCanAttack("player", unit);
    local color = level <= 0 and QuestDifficultyColors["impossible"]
        or attackable and GetQuestDifficultyColor(level) or FRIENDLY;
    border:SetTexture(style.keepCircle and stock or art);
    text:Hide();
    if level <= 0 and not style.keepCircle then
        self.highLevelTexture:Hide();          -- the skull goes on the ring or in the socket instead
    end
    if style.ring then
        if attackable then
            parts.ring:SetTexture(TEXTURES .. style.ring);
            parts.ring:SetTexCoord(border:GetTexCoord());
            parts.ring:SetVertexColor(color.r * style.bright, color.g * style.bright, color.b * style.bright);
            parts.ring:Show();
        end
        if level <= 0 then
            AtCircle(self, parts.skull, 16);
        end
        return;
    end
    if style.socket then
        AtCircle(self, parts.socket, style.socket);
    end
    if level > 0 then
        AtCircle(self, parts.dot, style.dot);
        parts.dot:SetVertexColor(color.r, color.g, color.b);
    elseif not style.keepCircle then
        AtCircle(self, parts.skull, style.socket and 12 or 14);
    end
end

hooksecurefunc("TargetFrame_CheckClassification", function(self)
    self.grizzleStockArt = self.borderTexture and self.borderTexture:GetTexture();
    UpdateFrame(self);
end);
hooksecurefunc("TargetFrame_CheckLevel", UpdateFrame);

-- --- tooltip: "Level 24 Beast (Elite)" becomes "Beast (Elite)" in the danger color ---------------

local LEVEL_PATTERN = "^" .. LEVEL .. " [%d%?]+%s*(.*)$";

GameTooltip:HookScript("OnTooltipSetUnit", function(self)
    local _, unit = self:GetUnit();
    if not Hiding(unit) then
        return;
    end
    for i = 2, self:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i];
        local text = line and line:GetText();
        local rest = text and text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match(LEVEL_PATTERN);
        if rest then
            if UnitCanAttack("player", unit) then
                local level = UnitLevel(unit);
                local color = level > 0 and GetQuestDifficultyColor(level) or QuestDifficultyColors["impossible"];
                rest = string.format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255), math.floor(color.g * 255),
                    math.floor(color.b * 255), rest);
            end
            line:SetText(rest);
            self:Show();
            return;
        end
    end
end);

-- --- nameplates -------------------------------------------------------------------------------

-- A 3.3.5 nameplate is an unnamed child of WorldFrame wearing the nameplate border; its second font string is the
-- level, which the client recolors and shows or hides (for the skull) as plates are reused. A nameplate can't tell
-- players from creatures, so players' levels go there too.
local plates = {};          -- nameplate -> { level = font string, dot = texture }
local numChildren = 0;

local function AddPlate(frame)
    local _, border = frame:GetRegions();
    if frame:GetName() or not border or border:GetObjectType() ~= "Texture"
            or border:GetTexture() ~= "Interface\\Tooltips\\Nameplate-Border" then
        return;
    end
    local fontStrings = 0;
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            fontStrings = fontStrings + 1;
            if fontStrings == 2 then
                plates[frame] = { level = region, dot = MakeDot(frame, region, 10) };
                return;
            end
        end
    end
end

local function UpdatePlate(plate)
    if Style() and plate.level:IsShown() then
        plate.dot:SetVertexColor(plate.level:GetTextColor());
        plate.dot:Show();
        plate.level:SetAlpha(0);
    else
        plate.dot:Hide();
        plate.level:SetAlpha(1);
    end
end

local elapsedSince = 0;
local plateWatcher = CreateFrame("Frame");
plateWatcher:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed;
    if elapsedSince < 0.1 then
        return;
    end
    elapsedSince = 0;
    local count = WorldFrame:GetNumChildren();
    if count ~= numChildren then
        numChildren = count;
        for _, frame in ipairs({ WorldFrame:GetChildren() }) do
            if not plates[frame] then
                AddPlate(frame);
            end
        end
    end
    for frame, plate in pairs(plates) do
        if frame:IsShown() then
            UpdatePlate(plate);
        end
    end
end);

-- --- /moblevels -------------------------------------------------------------------------------

local function Say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Veilmoor:|r " .. text);
end

SLASH_GRIZZLEMOBLEVELS1 = "/moblevels";
SlashCmdList["GRIZZLEMOBLEVELS"] = function(message)
    local n = tonumber(message);
    if not n or (n ~= 0 and not STYLES[n]) then
        Say("/moblevels <n> picks how creatures' levels show on the target frame (now "
            .. (GrizzleMobLevelStyle or DEFAULT_STYLE) .. "):");
        Say("0: numbers");
        for i, style in ipairs(STYLES) do
            Say(i .. ": " .. style.name .. (i == DEFAULT_STYLE and " (default)" or ""));
        end
        return;
    end
    GrizzleMobLevelStyle = n;
    for _, frame in ipairs({ TargetFrame, FocusFrame }) do
        if frame and frame:IsShown() then
            TargetFrame_CheckLevel(frame);
        end
    end
    Say("creature levels: " .. (n == 0 and "numbers" or STYLES[n].name) .. ".");
end;
