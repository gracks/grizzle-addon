-- One launcher, one realm (doc/grizzle/launcher.md): the launcher copies in the chosen realm's client patch and pins
-- that realm. The patch only matches the server it came with, so if the realm list was used to go elsewhere, say so.

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
    local text = "You started WoW with the launcher set to " .. expected .. ", but you're on " .. realm
        .. ". Some spells and items will be missing or wrong. Quit WoW, start Play Grizzle and pick "
        .. ((realm == "Veilmoor" or realm == "Veilmoor Test") and realm or "the realm you want") .. ".";
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Grizzle:|r " .. text);
    StaticPopup_Show("GRIZZLE_WRONG_REALM", text);
end);
