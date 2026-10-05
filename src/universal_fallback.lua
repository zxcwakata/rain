-- Universal fallback hub: same Rain UI library as the Deepwoken menu, but a
-- single "Main" tab with game-agnostic Movement functions. Opens on any place
-- outside the Deepwoken allowlist. No Deepwoken modules load here by design.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local state = { fly = false, fly_speed = 120, speed = false, speed_val = 32,
    noclip = false, infjump = false }
local bv = nil

local function char() return LP.Character end
local function hrp() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end

local function tick()
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

    RunService.PreSimulation:Connect(tick)
    UIS.JumpRequest:Connect(function()
        if state.infjump and hum() then
            pcall(function() hum():ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end)
    -- window starts hidden until its toggle key; show once for discovery
    pcall(function()
        if Lib.Toggled ~= true then Lib:Toggle() end
    end)
    print("[restore] universal hub (Main/Movement) for place " .. tostring(place_id))
end }
