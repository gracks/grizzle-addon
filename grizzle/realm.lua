-- One launcher, one realm (doc/grizzle/launcher.md): each launcher copies in its branch's client patch and pins its
-- realm. The patch only matches the server it came with, so if the realm list was used to go elsewhere, say so.

local LAUNCHERS = {
    ["Grizzle"] = "play-grizzle.cmd",
    ["Grizzle Test"] = "play-grizzle-test.cmd",
};

StaticPopupDialogs["GRIZZLE_WRONG_REALM"] = {
    text = "%s",
    button1 = OKAY,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:SetScript("OnEvent", function()
    local expected, realm = GrizzleLauncherRealm, GetRealmName();
    if not expected or realm == expected then
        return;
    end
    local fix = LAUNCHERS[realm] and ("Quit WoW and start it with " .. LAUNCHERS[realm] .. ".")
        or ("Quit WoW and start it with " .. (LAUNCHERS[expected] or "your Grizzle launcher") .. ".");
    local text = "You started WoW with the launcher for " .. expected .. ", but you're on " .. realm
        .. ". Some spells and items will be missing or wrong. " .. fix;
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Grizzle:|r " .. text);
    StaticPopup_Show("GRIZZLE_WRONG_REALM", text);
end);
