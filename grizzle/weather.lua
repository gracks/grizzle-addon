-- Grizzle weather overlay (doc/grizzle/weather-overlay.md): out in heavy weather, the edges of the screen show it.
-- Frost creeps in during snow and sandstorms leave a dusty haze (the world's own blowing sand does the rest). In rain,
-- drops land on the screen, bead, and dry up or run down; heavier rain lands more and runs more, and thunderstorms
-- add wind and darker corners. The heavier the weather, the stronger and further in it reaches.
-- The server sends the weather the player is out in (outdoors, alive, once it has arrived) in an addon whisper
-- "GRZ_WEATHER" <rain|storm|snow|sand, or empty>\t<grade 0-100>, when it changes and every 30s anyway.
-- After the rain (or a swim), drops dry up one by one while Drenched dries off. The overlay hangs off the game
-- world, not the UI, so hiding the UI (Alt-Z) keeps it.

local PREFIX = "GRZ_WEATHER";
local WET_SPELL_ID = 61870;   -- Drenched (Wet.SpellId)
local TEXTURES = "Interface\\AddOns\\grizzle\\textures\\";

local overlay = CreateFrame("Frame", "GrizzleWeatherOverlay", WorldFrame);
overlay:SetAllPoints(WorldFrame);
overlay:SetFrameStrata("BACKGROUND");
overlay:EnableMouse(false);

-- whole-screen layers; speed is how much alpha a layer gains or loses per second (frost forms and melts slowly)
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
local sandHaze = Layer("sand_haze", 0.3);
local frostLight = Layer("frost_light", 0.1);
local frostHeavy = Layer("frost_heavy", 0.07);

-- Rain: each drop is its own texture. Sizes and positions are in screen heights (y 0 at the top, x from 0 to the
-- screen's width over its height). Tuned in a browser preview (Oct 2026); the values are for heavy rain, and light
-- rain and thunderstorms are scaled from them.
local SPAWN = 8;                  -- drops landing per second
local MAX_DROPS = 50;             -- most drops on screen
local RUN_CHANCE = 0.35;          -- chance a drop runs down instead of drying up (bigger drops run more)
local SIZE_MIN, SIZE_MAX = 0.011, 0.032;
local HOLD_MAX = 8;               -- longest a drop sits before it runs or dries up, in seconds
local RUN_SPEED = 0.45;           -- how fast a running drop slides while it's moving, per second
local WIND = 0.10;                -- thunderstorm wind pushing running drops sideways, per second
local OPACITY = 0.85;
local CLEAR_MIDDLE = 0.42;        -- drops land within this far of an edge, thinning out further in
local LIGHT, STORM = 0.2, 1.6;    -- light rain lands this share of heavy rain's drops, a thunderstorm this many times
local LAND_TIME, FADE_TIME = 0.18, 0.9;
local MAX_TRAILS = 60;           -- past this many pieces of trail, the old ones fade out fast

local kind, grade = "", 0;
local raining = false;
local rain = { spawn = 0, max = 0, run = 0, wind = 0, t = 0 };
-- 1 in the rain; after it, how far Drenched has left to dry: each drop dries up when this falls below its dryAt.
-- It never falls faster than over DRY_MIN seconds, so drops don't all vanish when Drenched's timer starts a moment
-- after the rain stops, or when there's no Drenched at all (an oiled cloak, or Wet off).
local dry, dryCheckedAt = 0, 0;
local DRY_MIN = 15;
local spawnDebt = 0;
local drops, trails = {}, {};

local function Ramp(t, from, to)
    return math.max(0, math.min(1, (t - from) / (to - from)));
end

local function Random(from, to)
    return from + math.random() * (to - from);
end

-- textures are reused: a dried drop's texture goes back here for the next drop
local spare = { drop = {}, trail = {} };
local function TakeTexture(pool, file, drawLayer)
    local texture = table.remove(spare[pool]);
    if not texture then
        texture = overlay:CreateTexture(nil, drawLayer);
        texture:SetTexture(TEXTURES .. file);
    end
    texture:Show();
    return texture;
end

local function GiveBack(pool, texture)
    texture:Hide();
    table.insert(spare[pool], texture);
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

-- distance to the nearest screen edge, rounder into the corners
local function EdgeDistance(x, y, aspect)
    local dx, dy = math.max(0.001, math.min(x, aspect - x)), math.max(0.001, math.min(y, 1 - y));
    return (dx ^ -3 + dy ^ -3) ^ (-1 / 3);
end

local function Spawn(aspect)
    for _ = 1, 30 do
        local x, y = math.random() * aspect, math.random();
        -- mostly towards the edges; the middle of the screen stays almost clear
        local near = Ramp(EdgeDistance(x, y, aspect), CLEAR_MIDDLE, CLEAR_MIDDLE * 0.3);
        if math.random() <= near * near * (3 - 2 * near) + 0.03 then
            local variant = math.random(0, 3);
            local texture = TakeTexture("drop", "rain_drops", "OVERLAY");
            texture:SetTexCoord(variant * 0.25, (variant + 1) * 0.25, 0, 1);
            table.insert(drops, {
                x = x, y = y, texture = texture, state = "land", age = 0,
                size = SIZE_MIN + (SIZE_MAX - SIZE_MIN) * math.random() ^ 2.2,
                hold = Random(1.5, HOLD_MAX), dryAt = Random(0.05, 1),
            });
            return;
        end
    end
end

local function StartTrail(drop)
    drop.trail = { x = drop.x, top = drop.y, bottom = drop.y, w = drop.size * 0.9, alpha = 1, attached = true,
        texture = TakeTexture("trail", "rain_trail", "BORDER") };
    table.insert(trails, drop.trail);
end

local function EndTrail(drop)
    if drop.trail then
        drop.trail.attached = false;
        drop.trail = nil;
    end
end

local function StartRun(drop)
    drop.state = "run";
    drop.stuck, drop.slip, drop.phase = 0, 0, math.random() * 6;
    StartTrail(drop);
end

local function UpdateRunning(drop, dt)
    -- stick-slip: a running drop catches, then lets go and slides
    if drop.stuck > 0 then
        drop.stuck = drop.stuck - dt;
        return;
    end
    if drop.slip <= 0 then
        drop.slip = Random(0.08, 0.35);
    end
    drop.slip = drop.slip - dt;
    local dy = RUN_SPEED * Random(0.7, 1.3) * math.sqrt(drop.size / (SIZE_MAX * 0.6)) * dt;
    drop.y = drop.y + dy;
    drop.x = drop.x + rain.wind * dt + math.sin(drop.age * 7 + drop.phase) * drop.size * 1.2 * dt;
    drop.size = drop.size * math.exp(-dy / 1.6);   -- it leaves water on its trail
    if drop.slip <= 0 then
        drop.stuck = Random(0.05, 0.6) * (1 - 0.5 * rain.t) / math.max(0.6, drop.size / (SIZE_MAX * 0.6));
    end
    -- the trail follows; sideways drift starts a new piece of trail
    if drop.trail then
        if math.abs(drop.x - drop.trail.x) > drop.trail.w * 0.6 then
            EndTrail(drop);
            StartTrail(drop);
        end
        drop.trail.bottom = drop.y;
        drop.trail.top = math.max(drop.trail.top, drop.y - 0.45);
    end
    -- a running drop gathers the drops in its way
    for _, other in ipairs(drops) do
        if other ~= drop and not other.dead and (other.state == "land" or other.state == "bead") then
            local dx, dy2 = other.x - drop.x, other.y - drop.y;
            local reach = (other.size + drop.size) * 0.4;
            if dx * dx + dy2 * dy2 < reach * reach then
                drop.size = math.min(math.sqrt(drop.size ^ 2 + other.size ^ 2), SIZE_MAX * 1.3);
                other.dead = true;
                drop.stuck = 0;
            end
        end
    end
end

local function UpdateRain(dt, aspect)
    spawnDebt = spawnDebt + rain.spawn * dt;
    while spawnDebt >= 1 do
        spawnDebt = spawnDebt - 1;
        if #drops < rain.max then
            Spawn(aspect);
        end
    end

    for _, drop in ipairs(drops) do
        drop.age = drop.age + dt;
        if drop.state == "land" then
            if drop.age >= LAND_TIME then
                drop.state, drop.age = "bead", 0;
            end
        elseif drop.state == "bead" then
            drop.size = drop.size * (1 - 0.015 * dt);   -- evaporating
            if not raining then
                if dry < drop.dryAt then
                    drop.state, drop.age = "fade", 0;
                end
            elseif drop.age >= drop.hold then
                if math.random() < rain.run * (0.5 + drop.size / SIZE_MAX) then
                    StartRun(drop);
                else
                    drop.state, drop.age = "fade", 0;
                end
            end
        elseif drop.state == "run" then
            UpdateRunning(drop, dt);
            if drop.y - drop.size > 1 then
                drop.dead = true;
                EndTrail(drop);
            elseif drop.size < SIZE_MIN * 0.7 then
                -- run out of water: it stops and beads again
                EndTrail(drop);
                drop.state, drop.age, drop.hold = "bead", 0, Random(1, 3);
                drop.dryAt = math.min(drop.dryAt, dry);
            end
        elseif drop.age >= FADE_TIME then
            drop.dead = true;
        end
    end

    local kept = {};
    for _, drop in ipairs(drops) do
        if drop.dead then
            EndTrail(drop);
            GiveBack("drop", drop.texture);
        else
            table.insert(kept, drop);
        end
    end
    drops = kept;

    kept = {};
    for _, trail in ipairs(trails) do
        if not trail.attached then
            trail.alpha = trail.alpha - dt / (#trails > MAX_TRAILS and 0.4 or 3.5);
        end
        if trail.alpha > 0 then
            table.insert(kept, trail);
        else
            GiveBack("trail", trail.texture);
        end
    end
    trails = kept;
end

local function DrawRain(h)
    for _, trail in ipairs(trails) do
        local length = (trail.bottom - trail.top) * h;
        if length < 2 then
            trail.texture:Hide();
        else
            trail.texture:SetWidth(trail.w * h);
            trail.texture:SetHeight(length);
            trail.texture:ClearAllPoints();
            trail.texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", (trail.x - trail.w / 2) * h, -trail.top * h);
            trail.texture:SetAlpha(trail.alpha * OPACITY);
            trail.texture:Show();
        end
    end
    for _, drop in ipairs(drops) do
        local scale, alpha = 1, 1;
        if drop.state == "land" then
            -- a splat that grows past its size and settles back
            local t = drop.age / LAND_TIME;
            scale = t < 0.6 and 0.45 + 0.65 * t / 0.6 or 1.1 - 0.1 * (t - 0.6) / 0.4;
            alpha = math.min(1, drop.age / 0.06);
        elseif drop.state == "fade" then
            alpha = math.max(0, 1 - drop.age / FADE_TIME);
        end
        local w, ht = drop.size * scale * h, drop.size * scale * h;
        if drop.state == "run" and drop.stuck <= 0 then
            w, ht = w * 0.92, ht * 1.15;   -- stretched while it slides
        end
        drop.texture:SetWidth(w);
        drop.texture:SetHeight(ht);
        drop.texture:ClearAllPoints();
        drop.texture:SetPoint("TOPLEFT", overlay, "TOPLEFT", drop.x * h - w / 2, -(drop.y * h - ht * 0.55));
        drop.texture:SetAlpha(alpha * OPACITY);
    end
end

local function SetTargets()
    for _, layer in pairs(layers) do
        layer.target = 0;
    end
    -- 0 at the lightest weather the client shows (grade 0.27), 1 at the heaviest
    local t = Ramp(grade, 0.27, 1);
    raining = kind == "rain" or kind == "storm";
    rain.spawn, rain.max, rain.wind, rain.t = 0, 0, 0, t;
    if kind == "snow" then
        frostLight.target = 0.5 + 0.5 * t;
        frostHeavy.target = Ramp(t, 0.3, 1);
    elseif kind == "rain" then
        local f = LIGHT + (1 - LIGHT) * t;
        rain.spawn, rain.max = SPAWN * f, math.floor(MAX_DROPS * f + 0.5);
        rain.run = RUN_CHANCE * (0.25 + 0.75 * t);
    elseif kind == "storm" then
        local f = STORM * (0.75 + 0.25 * t);
        rain.spawn, rain.max = SPAWN * f, math.floor(MAX_DROPS * f + 0.5);
        rain.run, rain.wind = math.min(0.9, RUN_CHANCE * STORM), WIND;
        stormVignette.target = 0.6 + 0.4 * t;
    elseif kind == "sand" then
        sandHaze.target = 0.35 + 0.55 * t;
    end

    local now = GetTime();
    local sinceDry = now - dryCheckedAt;
    dryCheckedAt = now;
    if raining then
        dry = 1;
    else
        rain.run = RUN_CHANCE * 0.5;
        local drying = Drying();
        -- just out of the water after a swim: a splash of drops to dry off
        if dry == 0 and drying > 0.9 and #drops == 0 then
            local aspect = overlay:GetWidth() / math.max(1, overlay:GetHeight());
            for _ = 1, math.floor(MAX_DROPS * 0.6) do
                Spawn(aspect);
            end
        end
        dry = math.max(drying, dry - sinceDry / DRY_MIN);
    end
end

local sinceTargets = 0;
overlay:SetScript("OnUpdate", function(self, elapsed)
    sinceTargets = sinceTargets + elapsed;
    if sinceTargets >= 0.5 then
        sinceTargets = 0;
        SetTargets();
    end

    for _, layer in pairs(layers) do
        if layer.alpha ~= layer.target then
            local step = layer.speed * elapsed;
            if layer.alpha < layer.target then
                layer.alpha = math.min(layer.target, layer.alpha + step);
            else
                layer.alpha = math.max(layer.target, layer.alpha - step);
            end
        end
        if layer.alpha > 0 then
            layer.texture:SetAlpha(layer.alpha);
            layer.texture:Show();
        else
            layer.texture:Hide();
        end
    end

    local h = self:GetHeight();
    if h > 0 and (raining or #drops > 0 or #trails > 0) then
        -- a long frame (loading, a hitch) mustn't throw the drops across the screen
        UpdateRain(math.min(elapsed, 0.05), self:GetWidth() / h);
        DrawRain(h);
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
