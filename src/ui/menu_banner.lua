local IMAGE_ID = "" -- e.g. "rbxassetid://123456789"
local IMAGE_PATH = "RainBanner.png" -- e.g. "RainBanner.png" (in executor workspace folder)
local IMAGE_URL = "" -- e.g. "https://.../banner.png"
local BANNER_W, BANNER_H = 300, 200

local function resolve_image()
    if IMAGE_PATH ~= "" and typeof(getcustomasset) == "function" then
        local ok, asset = pcall(getcustomasset, IMAGE_PATH)
        if ok and asset then return asset end
    end
    if IMAGE_URL ~= "" and typeof(getcustomasset) == "function" then
        local ok = pcall(function()
            if not isfile("RainBanner.png") then
                writefile("RainBanner.png", game:HttpGet(IMAGE_URL))
            end
        end)
        if ok then
            local ok2, asset = pcall(getcustomasset, "RainBanner.png")
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
