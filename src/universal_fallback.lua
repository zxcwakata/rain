-- Universal fallback hub: opens on any place that is not a supported Deepwoken
-- place (and not the main menu). UI-only path: Settings tab + Universal tab
-- with inert placeholder toggles. No gameplay modules load here by design.
local ACCENT = Color3.fromRGB(8, 147, 201)
local BG = Color3.fromRGB(20, 20, 24)
local PANEL = Color3.fromRGB(28, 28, 34)
local ROW = Color3.fromRGB(34, 34, 42)
local FONT_C = Color3.fromRGB(220, 220, 220)
local DIM = Color3.fromRGB(130, 130, 140)

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

return { start = function(place_id)
    local gui_parent = nil
    pcall(function()
        gui_parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
    if not gui_parent then gui_parent = LP:WaitForChild("PlayerGui") end

    local function mk(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do pcall(function() o[k] = v end) end
        o.Parent = parent
        return o
    end

    local switches = { false, false }
    local gui = mk("ScreenGui", { Name = "RainUniversal", ResetOnSpawn = false }, gui_parent)
    local main = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(320, 260), BackgroundColor3 = BG, BorderSizePixel = 0,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, main)
    mk("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.4 }, main)
    local title = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = PANEL, BorderSizePixel = 0,
        Text = "  Project Rain — Universal", Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = FONT_C, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    do
        local drag, sp, si = false, nil, nil
        title.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                drag, sp, si = true, main.Position, i.Position
                i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then drag = false end end)
            end
        end)
        UIS.InputChanged:Connect(function(i)
            if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
                local d = i.Position - si
                main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end)
    end
    mk("TextLabel", {
        Position = UDim2.new(0, 10, 0, 36), Size = UDim2.new(1, -20, 0, 20),
        BackgroundTransparency = 1, Text = "Place " .. tostring(place_id) .. " is not supported.",
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = DIM,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    mk("TextLabel", {
        Position = UDim2.new(0, 10, 0, 58), Size = UDim2.new(1, -20, 0, 20),
        BackgroundTransparency = 1, Text = "Universal tab (placeholders, no game effect):",
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = FONT_C,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    for n = 1, 2 do
        local b = mk("TextButton", {
            Position = UDim2.new(0, 10, 0, 60 + n * 32), Size = UDim2.new(1, -20, 0, 28),
            BackgroundColor3 = ROW, BorderSizePixel = 0,
            Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = FONT_C,
        }, main)
        local function paint() b.Text = (switches[n] and "[ON]  " or "[OFF] ") .. "Universal Toggle " .. n end
        paint()
        b.MouseButton1Click:Connect(function()
            switches[n] = not switches[n]
            paint()
        end)
    end
    local close = mk("TextButton", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 3),
        Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromRGB(110, 40, 40),
        BorderSizePixel = 0, Text = "X", Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = FONT_C,
    }, main)
    close.MouseButton1Click:Connect(function() gui:Destroy() end)
    print("[restore] universal fallback UI for place " .. tostring(place_id))
end }
