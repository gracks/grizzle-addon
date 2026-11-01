-- Grizzle hidden levels (doc/grizzle/unknown.md "Not seeing a mob's level"): a creature's level number is gone from
-- the target and focus frames, the unit tooltip and the nameplates. The danger color stays where the number was: a
-- dot on the frames and nameplates, the rest of the tooltip's level line in that color. The "??" skull stays.
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

-- --- target, focus and boss frames ------------------------------------------------------------

-- runs after Blizzard has set the number and its color, or swapped it for the skull
hooksecurefunc("TargetFrame_CheckLevel", function(self)
    local text = self.levelText;
    if not text then
        return;
    end
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
end);

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
