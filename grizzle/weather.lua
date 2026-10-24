-- Grizzle weather overlay (doc/grizzle/weather-overlay.md): out in heavy weather, the edges of the screen show it.
-- Frost creeps in during snow, rain mists the edges, thunderstorms add a dark rim, and sandstorms leave a dusty haze
-- (the world's own rain and blowing sand do the rest). The heavier the weather, the stronger and further in it
-- reaches. The server sends the weather the player is out in (outdoors, alive, once it has arrived) in an addon
-- whisper "GRZ_WEATHER" <rain|storm|snow|sand, or empty>\t<grade 0-100>, when it changes and every 30s anyway.
-- After the rain, the mist fades while Drenched dries off. The overlay hangs off the game world, not the UI,
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

local kind, grade = "", 0;

local function Ramp(t, from, to)
    return math.max(0, math.min(1, (t - from) / (to - from)));
end

-- how far Drenched has left to dry (1 just out of the rain, 0 dry), or 0 while it has no timer (still soaking)
local function Drying()
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        for i = 1, 40 do
            local name, _, _, _, _, duration, expirationTime, _, _, _, spellId = UnitAura("player", i, filter);
            if not name then
                break;
            end
            if spellId == WET_SPELL_ID then
                if duration and duration > 0 and expirationTime then
                    return math.max(0, math.min(1, (expirationTime - GetTime()) / duration));
                end
                return 0;
            end
        end
    end
    return 0;
end

local function SetTargets()
    for _, layer in pairs(layers) do
        layer.target = 0;
    end
    -- 0 at the lightest weather the client shows (grade 0.27), 1 at the heaviest
    local t = Ramp(grade, 0.27, 1);
    if kind == "snow" then
        frostLight.target = 0.5 + 0.5 * t;
        frostHeavy.target = Ramp(t, 0.3, 1);
    elseif kind == "rain" or kind == "storm" then
        if kind == "storm" then
            t = 1;
            stormVignette.target = 1;
            stormRim.target = 0.8;
        end
        mistLight.target = 0.5 + 0.5 * t;
        mistHeavy.target = Ramp(t, 0.3, 1) * 0.85;
    elseif kind == "sand" then
        sandHaze.target = 0.35 + 0.55 * t;
    else
        -- the mist lingers while Drenched dries off
        mistLight.target = 0.6 * Drying();
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
