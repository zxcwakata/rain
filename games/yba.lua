-- YBA hub (PlaceId 2809202155, Your Bizarre Adventure).
-- Standalone: own UI + generic-safe features only (no game remotes faked).
-- To add functions: extend FEATURES below (toggle/slider/button entries), the
-- window builds itself from that table — no UI code needed per feature.
local ACCENT = Color3.fromRGB(8, 147, 201)
local BG = Color3.fromRGB(20, 20, 24)
local PANEL = Color3.fromRGB(28, 28, 34)
local ROW = Color3.fromRGB(34, 34, 42)
local FONT_C = Color3.fromRGB(220, 220, 220)
local DIM = Color3.fromRGB(130, 130, 140)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local state = { fly = false, fly_speed = 120, speed = false, speed_val = 32,
    noclip = false, infjump = false, esp = false }
local conns = {}
local function track(c) conns[#conns + 1] = c return c end
local function char() return LP.Character end
local function hrp() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end

local FEATURES = {
    { section = "Movement" },
    { id = "fly", type = "toggle", label = "Fly (WASD + Space/Ctrl)", get = function() return state.fly end,
        set = function(v)
            state.fly = v
            if not v and state._bv then pcall(function() state._bv:Destroy() end) state._bv = nil end
        end },
    { id = "fly_speed", type = "slider", label = "Fly Speed", min = 20, max = 400, get = function() return state.fly_speed end,
        set = function(v) state.fly_speed = v end },
    { id = "speed", type = "toggle", label = "WalkSpeed", get = function() return state.speed end, set = function(v) state.speed = v end },
    { id = "speed_val", type = "slider", label = "Speed Value", min = 16, max = 200, get = function() return state.speed_val end,
        set = function(v) state.speed_val = v end },
    { id = "noclip", type = "toggle", label = "Noclip", get = function() return state.noclip end, set = function(v) state.noclip = v end },
    { id = "infjump", type = "toggle", label = "Infinite Jump", get = function() return state.infjump end, set = function(v) state.infjump = v end },
    { section = "Visuals" },
    { id = "esp", type = "toggle", label = "Player ESP", get = function() return state.esp end, set = function(v) state.esp = v end },
    { section = "Combat (soon)" },
    -- add tables like the ones above: { id=..., type="toggle"/"slider"/"button", label=..., ... }
    -- then implement the behavior in the per-frame tick / hooks below.
}

-- per-frame behaviors (extend here as features are added)
track(RunService.PreSimulation:Connect(function()
    local c, r, h = char(), hrp(), hum()
    if state.speed and h then pcall(function() h.WalkSpeed = state.speed_val end) end
    if state.noclip and c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then pcall(function() p.CanCollide = false end) end
        end
    end
    if state.fly and r and h then
        local cam = workspace.CurrentCamera
        if cam then
            local move = Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
            if UIS:IsKeyDown(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
            if UIS:IsKeyDown(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move += Vector3.new(0, -1, 0) end
            if move.Magnitude > 0 then move = move.Unit end
            local vel = cam.CFrame:VectorToWorldSpace(move) * state.fly_speed
            if not state._bv or state._bv.Parent ~= r then
                pcall(function() if state._bv then state._bv:Destroy() end end)
                local bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                bv.Parent = r
                state._bv = bv
            end
            state._bv.Velocity = vel
        end
    elseif state._bv then
        pcall(function() state._bv:Destroy() end)
        state._bv = nil
    end
end))
track(UIS.JumpRequest:Connect(function()
    if state.infjump and hum() then pcall(function() hum():ChangeState(Enum.HumanoidStateType.Jumping) end) end
end))

-- ESP (highlight-based, cleaned up automatically)
local esp_folder = Instance.new("Folder")
esp_folder.Name = "YBA_ESP"
track(RunService.Heartbeat:Connect(function()
    if not state.esp then
        if #esp_folder:GetChildren() > 0 then esp_folder:ClearAllChildren() end
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and not esp_folder:FindFirstChild(p.Name) then
            local hl = Instance.new("Highlight")
            hl.Name = p.Name
            hl.FillColor = ACCENT
            hl.OutlineColor = ACCENT
            hl.FillTransparency = 0.6
            hl.Adornee = p.Character
            hl.Parent = esp_folder
        end
    end
    for _, hl in ipairs(esp_folder:GetChildren()) do
        local p = Players:FindFirstChild(hl.Name)
        if not p or not p.Character or hl.Adornee ~= p.Character then
            hl:Destroy()
        end
    end
end))

-- ============ window (built from FEATURES) ============
local function build_ui()
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

    local gui = mk("ScreenGui", { Name = "YBA", ResetOnSpawn = false }, gui_parent)
    local main = mk("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(340, 420), BackgroundColor3 = BG, BorderSizePixel = 0,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, main)
    mk("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.4 }, main)
    local title = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = PANEL, BorderSizePixel = 0,
        Text = "  YBA Hub", Font = Enum.Font.GothamBold, TextSize = 15,
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
    local scroll = mk("ScrollingFrame", {
        Position = UDim2.new(0, 8, 0, 36), Size = UDim2.new(1, -16, 1, -44),
        BackgroundTransparency = 1, ScrollBarThickness = 4,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, main)
    mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, scroll)

    for _, f in ipairs(FEATURES) do
        if f.section then
            mk("TextLabel", {
                Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1,
                Text = f.section, Font = Enum.Font.GothamBold, TextSize = 13,
                TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left,
            }, scroll)
        elseif f.type == "toggle" then
            local b = mk("TextButton", {
                Size = UDim2.new(1, -8, 0, 28), BackgroundColor3 = ROW, BorderSizePixel = 0,
                Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = FONT_C,
            }, scroll)
            local function paint() b.Text = (f.get() and "[ON]  " or "[OFF] ") .. f.label end
            paint()
            b.MouseButton1Click:Connect(function() f.set(not f.get()) paint() end)
        elseif f.type == "slider" then
            local lab = mk("TextLabel", {
                Size = UDim2.new(1, -8, 0, 18), BackgroundTransparency = 1,
                Text = "", Font = Enum.Font.Gotham,
                TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left,
            }, scroll)
            local function paint_lab() lab.Text = f.label .. ": " .. tostring(f.get()) end
            paint_lab()
            local minus = mk("TextButton", {
                Size = UDim2.new(0.5, -6, 0, 24), BackgroundColor3 = ROW, BorderSizePixel = 0,
                Text = "-", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = FONT_C,
            }, scroll)
            local plus = mk("TextButton", {
                Size = UDim2.new(0.5, -6, 0, 24), BackgroundColor3 = ROW, BorderSizePixel = 0,
                Text = "+", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = FONT_C,
            }, scroll)
            local function step(d)
                local v = math.clamp(f.get() + d, f.min or 0, f.max or 500)
                f.set(v)
                paint_lab()
            end
            minus.MouseButton1Click:Connect(function() step(-5) end)
            plus.MouseButton1Click:Connect(function() step(5) end)
        elseif f.type == "button" then
            local b = mk("TextButton", {
                Size = UDim2.new(1, -8, 0, 28), BackgroundColor3 = ROW, BorderSizePixel = 0,
                Text = f.label, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = ACCENT,
            }, scroll)
            b.MouseButton1Click:Connect(function() xpcall(f.press, warn) end)
        end
    end
    esp_folder.Parent = gui
end

return { start = function()
    xpcall(build_ui, warn)
    print("[yba] hub loaded")
end }
