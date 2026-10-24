-- Grizzle weather overlay (doc/grizzle/weather-overlay.md): out in heavy weather, the edges of the screen show it.
-- Frost creeps in during snow, drops gather in rain (and run in heavy rain), thunderstorms darken the edges, and
-- sandstorms blow grit across a dusty haze. The heavier the weather, the stronger and further in it reaches.
-- The server sends the weather the player is out in (outdoors, alive, once it has arrived) in an addon whisper
-- "GRZ_WEATHER" <rain|storm|snow|sand, or empty>\t<grade 0-100>, when it changes and every 30s anyway.
-- After the rain, drops linger while Drenched dries off. The overlay hangs off the game world, not the UI,
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
local function Layer(name, speed)
    local texture = overlay:CreateTexture(nil, "ARTWORK");
    texture:SetTexture(TEXTURES .. name);
    texture:SetAllPoints(overlay);
    texture:SetAlpha(0);
    texture:Hide();
    local layer = { texture = texture, speed = speed, alpha = 0, target = 0 };
    layers[name] = layer;
    return layer;
end

local stormDark = Layer("storm_dark", 0.3);
local sandHaze = Layer("sand_haze", 0.3);
local sandGrit = Layer("sand_grit", 0.4);
local frostLight = Layer("frost_light", 0.1);
local frostHeavy = Layer("frost_heavy", 0.07);
local rainA = Layer("rain_a", 0.5);
local rainB = Layer("rain_b", 0.5);
local rainC = Layer("rain_c", 0.4);
local rainStreaks = Layer("rain_streaks", 0.4);

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
            stormDark.target = 0.6;
        end
        rainA.target = 0.4 + 0.6 * t;
        rainB.target = rainA.target;
        rainC.target = Ramp(t, 0.45, 1);
        rainStreaks.target = Ramp(t, 0.6, 1) * 0.8;
    elseif kind == "sand" then
        sandHaze.target = 0.35 + 0.55 * t;
        sandGrit.target = 0.2 + 0.6 * t;
    else
        -- drops linger while Drenched dries off (swimming leaves them too)
        local drying = Drying();
        rainA.target = 0.6 * drying;
        rainB.target = rainA.target;
    end
end

local sinceTargets = 0;
overlay:SetScript("OnUpdate", function(self, elapsed)
    sinceTargets = sinceTargets + elapsed;
    if sinceTargets >= 0.5 then
        sinceTargets = 0;
        SetTargets();
    end

    local now = GetTime();
    -- drops come and go: the two sets crossfade over 7 seconds
    local shimmer = 0.4 * math.sin(now * 2 * math.pi / 7);
    -- running drops slide down a screen in 12 seconds, grit blows across one in 1.5 (both textures repeat halfway)
    local run = (now / 24) % 0.5;
    rainStreaks.texture:SetTexCoord(0, 1, 0.5 - run, 1 - run);
    local blow = (now / 3) % 0.5;
    sandGrit.texture:SetTexCoord(blow, blow + 0.5, 0, 1);

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
        if layer == rainA then
            alpha = alpha * (0.6 + shimmer);
        elseif layer == rainB then
            alpha = alpha * (0.6 - shimmer);
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
