-- Grizzle hidden levels (doc/grizzle/unknown.md "Not seeing a mob's level"): a creature's level number is gone from
-- the target and focus frames, the unit tooltip and the nameplates. The danger color takes its place: a thin ring
-- round the target's portrait, a dot on nameplates, the rest of the tooltip's level line. The "??" skull stays.
-- Players and what they control (pets, totems) keep their numbers. No switch to show them: players don't get one.

local TEXTURES = "Interface\\AddOns\\grizzle\\textures\\";
local DOT = TEXTURES .. "level_dot";                  -- apps/grizzle/gen_level_dot.py
local RING_BRIGHTNESS = 0.85;                         -- how much of the danger color the ring shows

local function Hiding(unit)
    return unit and not UnitIsPlayer(unit) and not UnitPlayerControlled(unit);
end

local function MakeDot(parent, anchor, size)
    local dot = parent:CreateTexture(nil, "OVERLAY");
    dot:SetTexture(DOT);
    dot:SetSize(size, size);
    dot:SetPoint("CENTER", anchor, "CENTER", 0, 0);
    dot:Hide();
    return dot;
end

-- --- target and focus frames: the portrait's ring in the danger color ----------------------------

-- The level circle is painted into the frame art, so creatures get copies that leave it out, and a thin ring over the
-- portrait's gold one, tinted for creatures you can attack (apps/grizzle/gen_target_frames.py). The "??" skull sits
-- on the ring where the circle was. Keyed by the art Blizzard picked (normal, elite, rare, rare elite).
local FRAME_ART = {
    ["interface\\targetingframe\\ui-targetingframe"] = TEXTURES .. "target_frame",
    ["interface\\targetingframe\\ui-targetingframe-elite"] = TEXTURES .. "target_frame_elite",
    ["interface\\targetingframe\\ui-targetingframe-rare"] = TEXTURES .. "target_frame_rare",
    ["interface\\targetingframe\\ui-targetingframe-rare-elite"] = TEXTURES .. "target_frame_rare_elite",
};

local function MakeParts(self)
    local border = self.borderTexture;
    -- their own frame just above the art, so they draw over it
    local frame = CreateFrame("Frame", nil, border:GetParent());
    frame:SetAllPoints(border:GetParent());
    frame:SetFrameLevel(border:GetParent():GetFrameLevel() + 1);
    local parts = {
        ring = frame:CreateTexture(nil, "ARTWORK"),
        dot = frame:CreateTexture(nil, "OVERLAY"),
        skull = frame:CreateTexture(nil, "OVERLAY"),
    };
    parts.ring:SetTexture(TEXTURES .. "target_ring");
    parts.ring:SetAllPoints(border);
    parts.dot:SetTexture(DOT);
    parts.dot:SetSize(12, 12);
    -- Blizzard centers the number in the level circle, shown or not. (Working the spot out from the art's texture
    -- coordinates landed about 20 px low and right in game.)
    parts.dot:SetPoint("CENTER", self.levelText, "CENTER", 0, 0);
    parts.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull");
    parts.skull:SetSize(16, 16);
    parts.skull:SetPoint("CENTER", self.levelText, "CENTER", 0, 0);
    self.grizzleParts = parts;
    return parts;
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
    local unit = self.unit;
    if not Hiding(unit) or UnitIsCorpse(unit) then
        if art then
            border:SetTexture(stock);
        end
        return;
    end
    if not art then
        -- other art (boss frames): a dot where the number was
        if text:IsShown() then
            parts.dot:SetVertexColor(text:GetTextColor());
            parts.dot:Show();
            text:Hide();
        end
        return;
    end
    border:SetTexture(art);
    text:Hide();
    local level = UnitLevel(unit);
    if level <= 0 then
        self.highLevelTexture:Hide();          -- the skull goes on the ring instead
        parts.skull:Show();
    end
    if UnitCanAttack("player", unit) then
        local color = level > 0 and GetQuestDifficultyColor(level) or QuestDifficultyColors["impossible"];
        parts.ring:SetTexCoord(border:GetTexCoord());
        parts.ring:SetVertexColor(color.r * RING_BRIGHTNESS, color.g * RING_BRIGHTNESS, color.b * RING_BRIGHTNESS);
        parts.ring:Show();
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
    plate.level:SetAlpha(0);
    if plate.level:IsShown() then
        plate.dot:SetVertexColor(plate.level:GetTextColor());
        plate.dot:Show();
    else
        plate.dot:Hide();
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
