-- Menu banner: clickable image centered above the main window.
-- THREE ways to provide the picture (first filled one wins):
--   1. IMAGE_ID   — Roblox decal/image id, e.g. "rbxassetid://123456789".
--      Upload at roblox.com (Create -> Decals/Images). Works everywhere.
--   2. IMAGE_PATH — local file next to the script, e.g. "RainBanner.png".
--      Needs getcustomasset (most executors have it, check yours).
--   3. IMAGE_URL  — direct link (Discord/GitHub/Imgur ...png), downloads once
--      into your executor workspace, then uses it like (2).
--   4. Write what the click should do into ON_CLICK.
-- Size: your source is 756x505 (ratio ~3:2). The menu window is 550 wide, so a
-- full-size banner would overhang — defaults below keep the ratio at 300x200.
-- Change BANNER_W/H freely (H = W * 505 / 756 to keep proportions).

local IMAGE_ID = "" -- e.g. "rbxassetid://123456789"
local IMAGE_PATH = "RainBanner.png" -- e.g. "RainBanner.png" (in executor workspace folder)
local IMAGE_URL = "" -- e.g. "https://.../banner.png"
local BANNER_W, BANNER_H = 550, 100

local function resolve_image()
    -- restore: executor globals (getcustomasset/isfile/writefile) may be
    -- invisible to loadstring chunks by bare name — resolve via getgenv().
    local gg = (typeof(getgenv) == "function" and getgenv()) or {}
    local gca = (typeof(gg.getcustomasset) == "function" and gg.getcustomasset)
        or (typeof(getcustomasset) == "function" and getcustomasset)
    local g_isfile = (typeof(gg.isfile) == "function" and gg.isfile)
        or (typeof(isfile) == "function" and isfile)
    if IMAGE_PATH ~= "" and gca then
        local ok, asset = pcall(gca, IMAGE_PATH)
        if ok and asset then return asset end
    end
    if IMAGE_URL ~= "" and gca then
        local ok = pcall(function()
            local has = g_isfile and g_isfile("RainBanner.png")
            if not has then
                local wf = (typeof(gg.writefile) == "function" and gg.writefile)
                    or (typeof(writefile) == "function" and writefile)
                wf("RainBanner.png", game:HttpGet(IMAGE_URL))
            end
        end)
        if ok then
            local ok2, asset = pcall(gca, "RainBanner.png")
            if ok2 and asset then return asset end
        end
    end
    if IMAGE_ID ~= "" then return IMAGE_ID end
    return nil
end

local function ON_CLICK()
    -- TODO: your function, e.g.:
    -- Library:Notify("banner clicked");
end

return { initialize = function()
    local Lib = (typeof(getgenv) == "function" and getgenv().Library) or Library
    local win = Lib and Lib.PRWindow
    local holder = win and win.Holder
    if not holder then return warn("[restore] menu_banner: window not ready") end
    if holder:FindFirstChild("RainBanner") then return end

    local btn = Instance.new("ImageButton")
    btn.Name = "RainBanner"
    btn.AnchorPoint = Vector2.new(0.5, 1)
    btn.Position = UDim2.new(0.5, 0, 0, -8)
    btn.Size = UDim2.new(0, BANNER_W, 0, BANNER_H)
    btn.BackgroundTransparency = 1
    btn.BorderSizePixel = 0
    local img = resolve_image()
    if not img then return warn("[restore] menu_banner: no image (fill IMAGE_ID/PATH/URL)") end
    btn.Image = img
    btn.ScaleType = Enum.ScaleType.Fit
    btn.ZIndex = 5
    btn.AutoButtonColor = true
    btn.Parent = holder

    btn.MouseButton1Click:Connect(function()
        xpcall(ON_CLICK, warn)
    end)
end }
