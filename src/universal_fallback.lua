-- Universal hub: same Rain UI library as the Deepwoken menu, game-agnostic only.
-- Tabs: Main (Movement), Visuals (ESP), UI (menu controls incl. Unload).
-- Opens on any place outside the Deepwoken allowlist. No Deepwoken modules.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local state = { fly = false, fly_speed = 120, speed = false, speed_val = 32,
    noclip = false, infjump = false, esp = false, esp_names = true,
    fullbright = false }
local bv = nil
local conns = {}
local esp_gui = nil

local function char() return LP.Character end
local function hrp() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end

local function physics_tick()
    local c, r, h = char(), hrp(), hum()
    if state.speed and h then pcall(function() h.WalkSpeed = state.speed_val end) end
    if state.noclip and c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then pcall(function() p.CanCollide = false end) end
        end
    end
    if state.fly and r then
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
            if not bv or bv.Parent ~= r then
                pcall(function() if bv then bv:Destroy() end end)
                local b = Instance.new("BodyVelocity")
                b.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                b.Parent = r
                bv = b
            end
            bv.Velocity = cam.CFrame:VectorToWorldSpace(move) * state.fly_speed
        end
    elseif bv then
        pcall(function() bv:Destroy() end)
        bv = nil
    end
    if state.fullbright then
        pcall(function()
            game:GetService("Lighting").Brightness = 2
            game:GetService("Lighting").ClockTime = 14
        end)
    end
end

local function esp_tick()
    if not esp_gui then return end
    if not state.esp then
        if #esp_gui:GetChildren() > 0 then esp_gui:ClearAllChildren() end
        return
    end
    local my_rp = hrp()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local erp = p.Character:FindFirstChild("HumanoidRootPart")
            if erp then
                local box = esp_gui:FindFirstChild(p.Name)
                if not box then
                    box = Instance.new("Highlight")
                    box.Name = p.Name
                    box.FillColor = Color3.fromRGB(8, 147, 201)
                    box.OutlineColor = Color3.fromRGB(8, 147, 201)
                    box.FillTransparency = 0.6
                    box.Adornee = p.Character
                    box.Parent = esp_gui
                elseif box.Adornee ~= p.Character then
                    box.Adornee = p.Character
                end
                local tag = esp_gui:FindFirstChild(p.Name .. "_tag")
                if state.esp_names then
                    local dist = my_rp and math.floor((my_rp.Position - erp.Position).Magnitude) or 0
                    if not tag then
                        tag = Instance.new("BillboardGui")
                        tag.Name = p.Name .. "_tag"
                        tag.Size = UDim2.new(0, 200, 0, 20)
                        tag.StudsOffset = Vector3.new(0, 3, 0)
                        tag.AlwaysOnTop = true
                        local lab = Instance.new("TextLabel")
                        lab.Size = UDim2.new(1, 0, 1, 0)
                        lab.BackgroundTransparency = 1
                        lab.Font = Enum.Font.GothamBold
                        lab.TextSize = 13
                        lab.TextColor3 = Color3.fromRGB(255, 255, 255)
                        lab.TextStrokeTransparency = 0.5
                        lab.Parent = tag
                        tag.Adornee = erp
                        tag.Parent = esp_gui
                    end
                    tag:FindFirstChildOfClass("TextLabel").Text =
                        p.DisplayName .. " (" .. tostring(dist) .. "m)"
                elseif tag then
                    tag:Destroy()
                end
            end
        end
    end
    for _, o in ipairs(esp_gui:GetChildren()) do
        local base = o.Name:gsub("_tag$", "")
        local p = Players:FindFirstChild(base)
        if not p or not p.Character then o:Destroy() end
    end
end

local function unload_all()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    if bv then pcall(function() bv:Destroy() end) bv = nil end
    if esp_gui then pcall(function() esp_gui:Destroy() end) esp_gui = nil end
    local h = hum()
    if h then pcall(function() h.WalkSpeed = 16 end) end
    local Lib = getgenv().Library
    if Lib then
        pcall(function()
            local holder = Lib.PRWindow and Lib.PRWindow.Holder
            local sg = holder and holder:FindFirstAncestorOfClass("ScreenGui")
            if sg then sg:Destroy() end
        end)
    end
    print("[restore] universal hub unloaded")
end

return { start = function(place_id)
    require("@src/utility/librarys/ui")
    local tab_mod = require("@src/utility/ui/wrapper")
    local Lib = getgenv().Library
    if not (Lib and Lib.PRWindow) then
        return warn("[restore] universal: UI window unavailable")
    end
    Lib.PRWindow:SetWindowTitle(string.format(
        'universal <font color="#%s">%s</font>', Lib.AccentColor:ToHex(), tostring(place_id)))

    -- Main / Movement
    local main = tab_mod.new("Main")
    local movement = main:newGroupBox("Movement")
    movement:newToggle("u_fly", "Fly (WASD + Space/Ctrl)", false, "Camera-direction fly.",
        function(v)
            state.fly = v
            if not v and bv then pcall(function() bv:Destroy() end) bv = nil end
        end)
    movement:newSlider("u_fly_speed", "Fly Speed", 120, 20, 400, 0, true, "st/s",
        function(v) state.fly_speed = v end)
    movement:newToggle("u_speed", "WalkSpeed", false, "Constant walk speed.",
        function(v) state.speed = v end)
    movement:newSlider("u_speed_val", "Speed Value", 32, 16, 200, 0, true, "st/s",
        function(v) state.speed_val = v end)
    movement:newToggle("u_noclip", "Noclip", false, "No collision.",
        function(v) state.noclip = v end)
    movement:newToggle("u_infjump", "Infinite Jump", false, "Jump in mid-air.",
        function(v) state.infjump = v end)

    -- Visuals
    local visuals = tab_mod.new("Visuals")
    local espbox = visuals:newGroupBox("ESP")
    espbox:newToggle("u_esp", "Player ESP", false, "Highlight players.",
        function(v) state.esp = v end)
    espbox:newToggle("u_esp_names", "Name Tags + Distance", true, "Billboard nametags.",
        function(v) state.esp_names = v end)
    local world = visuals:newGroupBox("World")
    world:newToggle("u_fullbright", "FullBright", false, "Force daylight.",
        function(v) state.fullbright = v end)

    -- UI tab: menu controls
    local uitab = tab_mod.new("UI")
    local menubox = uitab:newGroupBox("Menu")
    menubox:newButton("Unload Menu", function()
        unload_all()
    end, false, "Unloads the universal hub (all features off, UI destroyed).")

    -- ESP container on its own layer (survives nothing, dies with unload)
    local gui_parent = nil
    pcall(function()
        gui_parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
    if not gui_parent then gui_parent = LP:WaitForChild("PlayerGui") end
    esp_gui = Instance.new("ScreenGui")
    esp_gui.Name = "RainUniversalESP"
    esp_gui.ResetOnSpawn = false
    esp_gui.Parent = gui_parent

    conns[#conns + 1] = RunService.PreSimulation:Connect(physics_tick)
    conns[#conns + 1] = RunService.Heartbeat:Connect(esp_tick)
    conns[#conns + 1] = UIS.JumpRequest:Connect(function()
        if state.infjump and hum() then
            pcall(function() hum():ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end)

    pcall(function()
        if Lib.Toggled ~= true then Lib:Toggle() end
    end)
    print("[restore] universal hub (Main/Visuals/UI) for place " .. tostring(place_id))
end }
