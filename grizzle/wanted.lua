-- Grizzle wanted lists (doc/grizzle/wanted.md): while a merchant with a wanted list has its shop open, the items it
-- wants say so in their tooltips, with what each one fetches there and whether selling it still pays XP. The server
-- sends the list in an addon whisper "GRZ_WANTED" <item>:<copper each>:<1 if selling pays XP, else 0>, tab-separated,
-- when the shop opens and after each wanted sale or buyback.

local PREFIX = "GRZ_WANTED";
local wanted = {};   -- item id -> { price = copper each, xp = selling pays XP }

local function AddWantedLines(tooltip)
    if not MerchantFrame:IsShown() then
        return;
    end
    local _, link = tooltip:GetItem();
    local id = link and tonumber(link:match("item:(%d+)"));
    local item = id and wanted[id];
    if not item then
        return;
    end
    tooltip:AddLine("Wanted here: fetches " .. GetCoinTextureString(item.price) .. " apiece", 0.1, 1, 0.1);
    if item.xp then
        tooltip:AddLine("Experience to be gained", 0.1, 1, 0.1);
    end
    tooltip:Show();
end

GameTooltip:HookScript("OnTooltipSetItem", AddWantedLines);

local events = CreateFrame("Frame");
events:RegisterEvent("CHAT_MSG_ADDON");
events:RegisterEvent("MERCHANT_CLOSED");
events:SetScript("OnEvent", function(self, event, prefix, message, channel)
    if event == "MERCHANT_CLOSED" then
        wanted = {};
        return;
    end
    if prefix ~= PREFIX or channel ~= "WHISPER" then
        return;
    end
    -- the list arrives just before the shop opens, so it's only cleared when the shop closes
    wanted = {};
    for _, entry in ipairs({ strsplit("\t", message or "") }) do
        local id, price, xp = strsplit(":", entry);
        id, price, xp = tonumber(id), tonumber(price), tonumber(xp);
        if id and price then
            wanted[id] = { price = price, xp = xp == 1 };
        end
    end
end);
