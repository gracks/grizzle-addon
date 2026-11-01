-- Grizzle hidden levels (doc/grizzle/unknown.md "Not seeing a mob's level"): a creature's level number is gone from
-- the target and focus frames, the unit tooltip and the nameplates. The danger color takes its place: the ring round
-- the target's portrait, a dot on nameplates, the rest of the tooltip's level line. The "??" skull stays.
-- Players and what they control (pets, totems) keep their numbers. /moblevels shows the numbers again (to compare).

GrizzleShowMobLevels = GrizzleShowMobLevels or nil;   -- true: show numbers (SavedVariables)

local DOT = "Interface\\AddOns\\grizzle\\textures\\level_dot";   -- apps/grizzle/gen_level_dot.py

local function Hiding(unit)
    return not GrizzleShowMobLevels and unit and not UnitIsPlayer(unit) and not UnitPlayerControlled(unit);
end

local function MakeDot(parent, anchor, size)
    local dot = parent:CreateTexture(nil, "OVERLAY");
    dot:SetTexture(DOT);
    dot:SetSize(size, size);
    dot:SetPoint("CENTER", anchor, "CENTER", 0, 0);
    dot:Hide();
    return dot;
end

-- --- target and focus frames: the portrait's ring in the danger color ---------------------------

-- The level circle is painted into the frame art, so a creature gets a copy without it (apps/grizzle/gen_target_frames.py)
-- and a ring over the portrait's thin gold one, tinted for creatures you can attack. The "??" skull sits on the ring
-- where the circle was. Keyed by the art Blizzard picked (normal, elite, rare, rare elite).
local TEXTURES = "Interface\\AddOns\\grizzle\\textures\\";
local FRAME_ART = {
    ["interface\\targetingframe\\ui-targetingframe"] = TEXTURES .. "target_frame",
    ["interface\\targetingframe\\ui-targetingframe-elite"] = TEXTURES .. "target_frame_elite",
    ["interface\\targetingframe\\ui-targetingframe-rare"] = TEXTURES .. "target_frame_rare",
    ["interface\\targetingframe\\ui-targetingframe-rare-elite"] = TEXTURES .. "target_frame_rare_elite",
};

-- other art (boss frames): a dot where the number was
local function UpdateDot(self)
    local text = self.levelText;
    if not self.grizzleLevelDot then
        self.grizzleLevelDot = MakeDot(text:GetParent(), text, 12);
    end
    if text:IsShown() and Hiding(self.unit) then
        self.grizzleLevelDot:SetVertexColor(text:GetTextColor());
        self.grizzleLevelDot:Show();
        text:Hide();
    else
        self.grizzleLevelDot:Hide();
    end
end

local function MakeRing(self)
    local border = self.borderTexture;
    -- its own frame just above the art, so the ring and the skull draw over it
    local frame = CreateFrame("Frame", nil, border:GetParent());
    frame:SetAllPoints(border:GetParent());
    frame:SetFrameLevel(border:GetParent():GetFrameLevel() + 1);
    local ring = frame:CreateTexture(nil, "ARTWORK");
    ring:SetTexture(TEXTURES .. "target_ring");
    ring:SetAllPoints(border);
    local skull = frame:CreateTexture(nil, "OVERLAY");
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull");
    skull:SetSize(16, 16);
    skull:SetPoint("CENTER", self.highLevelTexture, "CENTER", 0, 0);
    self.grizzleRing, self.grizzleSkull = ring, skull;
end

-- runs after Blizzard has set the art, the number and its color, or the skull
local function UpdateFrame(self)
    local border = self.borderTexture;
    if not self.levelText or not border then
        return;
    end
    local stock = self.grizzleStockArt;
    local art = stock and FRAME_ART[stock:lower():gsub("%.blp$", "")];
    if not art then
        UpdateDot(self);
        return;
    end
    if not self.grizzleRing then
        MakeRing(self);
    end
    local unit = self.unit;
    if not Hiding(unit) or UnitIsCorpse(unit) then
        border:SetTexture(stock);
        self.grizzleRing:Hide();
        self.grizzleSkull:Hide();
        return;
    end
    border:SetTexture(art);
    self.levelText:Hide();
    local level = UnitLevel(unit);
    if level > 0 then
        self.grizzleSkull:Hide();
    else
        self.highLevelTexture:Hide();
        self.grizzleSkull:Show();
    end
    if UnitCanAttack("player", unit) then
        local color = level > 0 and GetQuestDifficultyColor(level) or QuestDifficultyColors["impossible"];
        self.grizzleRing:SetTexCoord(border:GetTexCoord());
        self.grizzleRing:SetVertexColor(color.r, color.g, color.b);
        self.grizzleRing:Show();
    else
        self.grizzleRing:Hide();
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
    if not GrizzleShowMobLevels and plate.level:IsShown() then
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

SLASH_GRIZZLEMOBLEVELS1 = "/moblevels";
SlashCmdList["GRIZZLEMOBLEVELS"] = function()
    GrizzleShowMobLevels = not GrizzleShowMobLevels or nil;
    for _, frame in ipairs({ TargetFrame, FocusFrame }) do
        if frame and frame:IsShown() then
            TargetFrame_CheckLevel(frame);
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Veilmoor:|r creature levels "
        .. (GrizzleShowMobLevels and "shown as numbers." or "hidden (danger color only)."));
end;
