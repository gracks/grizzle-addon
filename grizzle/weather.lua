-- Grizzle weather overlay (doc/grizzle/weather-overlay.md): out in heavy weather, the edges of the screen show it.
-- Frost creeps in during snow, rain mists the edges, thunderstorms add a dark rim, and sandstorms leave a dusty haze
-- (the world's own rain and blowing sand do the rest). The heavier the weather, the stronger and further in it
-- reaches. The server sends the weather the player is out in (outdoors, alive, once it has arrived) in an addon
-- whisper "GRZ_WEATHER" <rain|storm|snow|sand, or empty>\t<grade 0-100>, when it changes and every 30s anyway.
-- After the rain, the mist clears in the first seconds of Drenched drying off. The overlay hangs off the game world, not the UI,
-- so hiding the UI (Alt-Z) keeps it.

local PREFIX = "GRZ_WEATHER";
local WET_SPELL_ID = 61870;   -- Drenched (Wet.SpellId)
local TEXTURES = "Interface\\AddOns\\grizzle\\textures\\";

local overlay = CreateFrame("Frame", "GrizzleWeatherOverlay", WorldFrame);
overlay:SetAllPoints(WorldFrame);
overlay:SetFrameStrata("BACKGROUND");
overlay:EnableMouse(false);

-- layers bottom to top; speed is how much alpha a layer gains or loses per second (frost forms and melts slowly)
local layers = {};
local function Layer(name, speed, drawLayer)
    local texture = overlay:CreateTexture(nil, drawLayer or "ARTWORK");
    texture:SetTexture(TEXTURES .. name);
    texture:SetAllPoints(overlay);
    texture:SetAlpha(0);
    texture:Hide();
    local layer = { texture = texture, speed = speed, alpha = 0, target = 0 };
    layers[name] = layer;
    return layer;
end

local stormVignette = Layer("storm_vignette", 0.3, "BACKGROUND");
local stormRim = Layer("storm_rim", 0.3, "BORDER");
local sandHaze = Layer("sand_haze", 0.3);
local frostLight = Layer("frost_light", 0.1);
local frostHeavy = Layer("frost_heavy", 0.07);
local mistLight = Layer("mist_light", 0.15);
local mistHeavy = Layer("mist_heavy", 0.12);

local MIST = 0.5;         -- overall strength of the rain mist
local STORM_MIST = 0.18;  -- a thunderstorm's mist, lighter than heavy rain's so its dark rim shows through
local STORM_DARK = 0.6;   -- strength of a thunderstorm's dark rim and corners
local MIST_CLEAR = 9;     -- seconds the mist takes to clear once you start drying off

local kind, grade = "", 0;

local function Ramp(t, from, to)
    return math.max(0, math.min(1, (t - from) / (to - from)));
end

-- seconds since Drenched started drying off, or nil while it has no timer (still soaking) or you're dry
local function Dried()
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        for i = 1, 40 do
            local name, _, _, _, _, duration, expirationTime, _, _, _, spellId = UnitAura("player", i, filter);
            if not name then
                break;
            end
            if spellId == WET_SPELL_ID then
                if duration and duration > 0 and expirationTime then
                    return GetTime() - (expirationTime - duration);
                end
                return nil;
            end
        end
    end
    return nil;
end

local function SetTargets()
    for _, layer in pairs(layers) do
        layer.target = 0;
    end
    -- 0 at the lightest weather the client shows (grade 0.27), 1 at the heaviest
    local t = Ramp(grade, 0.27, 1);
    if kind == "snow" then
        -- frost goes up in steps with the client's light, medium and heavy snow: a faint rim in light snow, a clear
        -- jump as medium snow brings Snowbound, full frost in heavy snow (the layers' speeds smooth each step)
        if grade < 0.40 then
            frostLight.target = 0.25;
        elseif grade < 0.70 then
            frostLight.target = 0.8;
            frostHeavy.target = 0.3;
        else
            frostLight.target = 1;
            frostHeavy.target = 0.8;
        end
    elseif kind == "rain" then
        mistLight.target = MIST * (0.5 + 0.2 * t);
        mistHeavy.target = MIST * Ramp(t, 0.3, 1) * 0.6;
    elseif kind == "storm" then
        stormVignette.target = STORM_DARK;
        stormRim.target = 0.8 * STORM_DARK;
        mistLight.target = STORM_MIST;
        mistHeavy.target = STORM_MIST * 0.85;
    elseif kind == "sand" then
        sandHaze.target = 0.35 + 0.55 * t;
    else
        -- the mist lingers briefly as Drenched starts drying off (Drenched is your clothes, the mist your view)
        local dried = Dried();
        if dried then
            mistLight.target = MIST * 0.6 * (1 - Ramp(dried, 0, MIST_CLEAR));
        end
    end
end

local sinceTargets = 0;
overlay:SetScript("OnUpdate", function(self, elapsed)
    sinceTargets = sinceTargets + elapsed;
    if sinceTargets >= 0.5 then
        sinceTargets = 0;
        SetTargets();
    end

    -- the mist breathes: the two layers trade a little strength over 20 seconds
    local breath = 0.15 * math.sin(GetTime() * 2 * math.pi / 20);

    for _, layer in pairs(layers) do
        if layer.alpha ~= layer.target then
            local step = layer.speed * elapsed;
            if layer.alpha < layer.target then
                layer.alpha = math.min(layer.target, layer.alpha + step);
            else
                layer.alpha = math.max(layer.target, layer.alpha - step);
            end
        end
        local alpha = layer.alpha;
        if layer == mistLight then
            alpha = alpha * (0.85 + breath);
        elseif layer == mistHeavy then
            alpha = alpha * (0.85 - breath);
        end
        if alpha > 0 then
            layer.texture:SetAlpha(alpha);
            layer.texture:Show();
        else
            layer.texture:Hide();
        end
    end
end);

local events = CreateFrame("Frame");
events:RegisterEvent("CHAT_MSG_ADDON");
events:SetScript("OnEvent", function(self, event, prefix, message, channel)
    if prefix ~= PREFIX or channel ~= "WHISPER" then
        return;
    end
    local newKind, newGrade = strsplit("\t", message or "");
    kind = newKind or "";
    grade = (tonumber(newGrade) or 0) / 100;
    SetTargets();
end);

-- Lightning (doc/grizzle/weather.md "Lightning strikes"): the server whispers "GRZ_BOLT" <struck|arc|near> to players
-- within 60 yd of a strike, along with the thunderclap. The screen flashes white twice, the way lightning flickers,
-- brightest for the one struck, who also reads what hit them (Greg's playtest, Oct 28 2026: nobody could tell).
local BOLT_PREFIX = "GRZ_BOLT";
local BOLT_PEAK = { struck = 0.85, arc = 0.6, near = 0.35 };
local BOLT_TIME = 0.8;                  -- seconds from the first flash to dark

local bolt = CreateFrame("Frame", nil, WorldFrame);
bolt:SetAllPoints(WorldFrame);
bolt:SetFrameStrata("HIGH");
bolt:EnableMouse(false);
local boltTexture = bolt:CreateTexture(nil, "OVERLAY");
boltTexture:SetAllPoints(bolt);
boltTexture:SetTexture(0.9, 0.95, 1);
bolt:Hide();
local boltPeak, boltAge = 0, 0;

bolt:SetScript("OnUpdate", function(self, elapsed)
    boltAge = boltAge + elapsed;
    if boltAge >= BOLT_TIME then
        self:Hide();
        return;
    end
    -- flash, a dip, a second flash, then fading out
    local alpha;
    if boltAge < 0.06 then
        alpha = 1;
    elseif boltAge < 0.12 then
        alpha = 0.25;
    else
        alpha = 0.8 * (1 - (boltAge - 0.12) / (BOLT_TIME - 0.12)) ^ 2;
    end
    boltTexture:SetAlpha(boltPeak * alpha);
end);

local boltEvents = CreateFrame("Frame");
boltEvents:RegisterEvent("CHAT_MSG_ADDON");
boltEvents:SetScript("OnEvent", function(self, event, prefix, message, channel)
    if prefix ~= BOLT_PREFIX or channel ~= "WHISPER" then
        return;
    end
    local peak = BOLT_PEAK[message];
    if not peak then
        return;
    end
    boltPeak, boltAge = peak, 0;
    boltTexture:SetAlpha(peak);
    bolt:Show();
    if message == "struck" then
        UIErrorsFrame:AddMessage("Struck by lightning!", 0.75, 0.88, 1, 1, 3);
    end
end);

-- skyCloudLOD stays at 0: at 3 the clouds are smoother but some zones' (Westfall's) turn dark grey. The addon
-- raised it to 3 for a while (doc/grizzle/sky.md), so at login it's put back
local sky = CreateFrame("Frame");
sky:RegisterEvent("PLAYER_LOGIN");
sky:SetScript("OnEvent", function()
    if (tonumber(GetCVar("skyCloudLOD")) or 0) ~= 0 then
        SetCVar("skyCloudLOD", 0);
    end
end);
