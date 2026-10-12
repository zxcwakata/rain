-- Universal hub: same Rain UI library as the Deepwoken menu, game-agnostic only.
-- Tabs: Main (Movement/Fun), Combat (Silent Aim), Visuals (ESP/World/Camera/Crosshair),
--       UI (Themes/Configs/Menu). Opens on any place outside the Deepwoken allowlist.
-- No Deepwoken modules, no game-specific remotes — everything is generic.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local LP = Players.LocalPlayer

local unpack = table.unpack or unpack

local state = {
    -- movement
    fly = false, fly_speed = 120, speed = false, speed_val = 175, jump_power = 50,
    noclip = false, infjump = false, jerk = false,
    -- visuals
    esp = false, esp_names = true, esp_dist = 1000, esp_enemies = false,
    esp_health = true, chams = false, chams_fill = 0.35,
    box = false, box_thick = 1, tracer = false, tracer_thick = 1,
    skeleton = false, bone_thick = 1,
    npc_esp = false, npc_dist = 300,
    fullbright = false, no_shadows = false, no_fog = false,
    fov_on = false, fov = 70, zoom = false,
    crosshair = false, cross_thick = 2, cross_gap = 4, cross_dot = false,
    hide_default_cross = false,
    cross_color = Color3.fromRGB(255, 255, 255),
    esp_color = Color3.fromRGB(8, 147, 201),
    chams_color = Color3.fromRGB(255, 90, 90),
    tracer_color = Color3.fromRGB(255, 255, 255),
    bone_color = Color3.fromRGB(255, 255, 255),
    npc_color = Color3.fromRGB(255, 170, 40),
    -- silent aim
    silent = false, sa_fov = 120, sa_part = "Best", sa_smooth = 100, sa_chance = 100,
    sa_enemies = false, sa_los = true, sa_dist = 1000, sa_activate = "Always",
    sa_aimkey = "", sa_engine = "Both", sa_circle = true,
}

local bv = nil
local conns = {}
local esp_gui = nil
local saved_fov, saved_zoom = nil, nil
local saved_light = nil
local hidden_cross = {}

-- restore: jerk-off tool state (mirrors Jerk OFF.lua: u4 run-flag, t1 conns)
local jerk_tool = nil
local jerk_running = false
local jerk_conns = {}
local jerk_char_conn = nil

-- visuals registry + npc cache
local vis = {}
local npc_cache = {}
local cross_ui = nil
local circle_ui = nil

-- silent aim runtime
local silent_target = nil
local saved_cam_cf = nil
local remote_state = { hooked = {}, installed = false, ok = false }

local function clamp(v, a, b) return math.min(math.max(v, a), b) end

-- on-screen notify with a console fallback (hud needs the lexend font, which may
-- be missing in the universal branch)
local function notify(txt)
    local ok = pcall(function()
        local Lib = getgenv().Library
        if Lib and Lib.Notify then Lib:Notify(txt) end
    end)
    print("[rain] " .. txt)
    return ok
end

local function char() return LP.Character end
local function hrp() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end
local function same_team(a, b)
    local ok, r = pcall(function()
        return a.Team ~= nil and b.Team ~= nil and a.Team == b.Team
    end)
    return ok and r
end

local function gui_inset()
    local ok, v = pcall(function() return GuiService:GetGuiInset() end)
    if ok and type(v) == "Vector2" then return v end
    return Vector2.new(0, 36)
end

-- =====================================================================
--  SILENT AIM
-- =====================================================================

local PART_MAP = {
    ["Best"] = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" },
    ["Head"] = { "Head" },
    ["HumanoidRootPart"] = { "HumanoidRootPart" },
    ["UpperTorso"] = { "UpperTorso", "Torso" },
    ["Torso"] = { "Torso", "UpperTorso" },
    ["Humanoid"] = { "HumanoidRootPart", "Head" },
}

local function pick_part(ch, cam, mp)
    local mode = PART_MAP[state.sa_part] and state.sa_part or "Best"
    local names = PART_MAP[mode]
    if mode == "Best" then
        local best, best_d = nil, math.huge
        for _, n in ipairs(names) do
            local p = ch:FindFirstChild(n)
            if p and p:IsA("BasePart") then
                local v = cam:WorldToViewportPoint(p.Position)
                if v.Z > 0 then
                    local d = (Vector2.new(v.X, v.Y + gui_inset().Y) - mp).Magnitude
                    if d < best_d then best, best_d = p, d end
                end
            end
        end
        if best then return best end
    end
    for _, n in ipairs(names) do
        local p = ch:FindFirstChild(n)
        if p and p:IsA("BasePart") then return p end
    end
    return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Head")
end

local function visible_to(ch, part, cam)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local c = char()
    params.FilterDescendantsInstances = c and { c, ch } or { ch }
    local dir = part.Position - cam.CFrame.Position
    local hit = workspace:Raycast(cam.CFrame.Position, dir, params)
    return (hit ~= nil and hit.Instance:IsDescendantOf(ch))
end

local function acquire_target()
    local cam = workspace.CurrentCamera
    local my = hrp()
    if not cam or not my then return nil end
    local mp = UIS:GetMouseLocation()
    local best, best_score = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local skip = state.sa_enemies and same_team(LP, p)
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            local anchor = p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Head")
            if not skip and h and h.Health > 0 and anchor then
                local dist = (my.Position - anchor.Position).Magnitude
                if dist <= state.sa_dist then
                    local part = pick_part(p.Character, cam, mp)
                    if part then
                        local v = cam:WorldToViewportPoint(part.Position)
                        if v.Z > 0 then
                            local d = (Vector2.new(v.X, v.Y + gui_inset().Y) - mp).Magnitude
                            if d <= state.sa_fov then
                                if not state.sa_los or visible_to(p.Character, part, cam) then
                                    -- closest to the crosshair wins, slightly favouring nearer players
                                    local score = d + (dist / state.sa_dist) * 10
                                    if score < best_score then best, best_score = part, score end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function silent_armed()
    if not state.silent then return false end
    local act = state.sa_activate
    if act == "Mouse1" then
        return UIS:IsMouseButtonPressed(Enum.MouseButton1)
    elseif act == "Key" then
        local name = tostring(state.sa_aimkey or ""):gsub("%s", "")
        if name == "" then return true end
        if name:sub(1, 10) == "MouseButton" then
            local n = tonumber(name:match("(%d+)$")) or 1
            return UIS:IsMouseButtonPressed(n)
        end
        local kc = Enum.KeyCode[name]
        return kc ~= nil and kc ~= Enum.KeyCode.Unknown and UIS:IsKeyDown(kc)
    end
    return true
end

-- camera engine: swap CurrentCamera for one simulation window (invisible to
-- the player, visible to anything raycasting during that frame)
local function apply_camera_aim(part)
    local cam = workspace.CurrentCamera
    if not cam or not part then return end
    local cf = cam.CFrame
    saved_cam_cf = cf
    local look = part.Position - cf.Position
    if look.Magnitude < 0.01 then return end
    if state.sa_smooth > 0 then
        local f = clamp(state.sa_smooth / 100, 0, 1)
        look = cf.LookVector:Lerp(look.Unit, f)
    end
    cam.CFrame = CFrame.lookAt(cf.Position, cf.Position + look.Unit)
end

local function restore_camera_aim()
    if saved_cam_cf then
        local cam = workspace.CurrentCamera
        if cam then pcall(function() cam.CFrame = saved_cam_cf end) end
        saved_cam_cf = nil
    end
end

-- remote engine: rewrite aim args of attack remotes
local function hook_fn()
    local gg = getgenv()
    for _, k in ipairs({ "hookmetamethod", "hookmetamethod_ex" }) do
        if type(gg[k]) == "function" then return gg[k] end
    end
    if type(hookmetamethod) == "function" then return hookmetamethod end
    return nil
end

local function redirect_args(args, cam, part)
    local limit = math.min(args.n, 4)
    for i = 1, limit do
        local a = args[i]
        local t = typeof(a)
        if t == "Vector3" then
            if a.Magnitude <= 2 and cam and (a - cam.CFrame.LookVector).Magnitude < 0.4 then
                args[i] = (part.Position - cam.CFrame.Position).Unit
                return true
            end
        elseif t == "Ray" then
            args[i] = Ray.new(a.Origin, (part.Position - a.Origin).Unit)
            return true
        elseif t == "CFrame" then
            if not cam or (a.LookVector - cam.CFrame.LookVector).Magnitude < 0.4 then
                args[i] = CFrame.new(a.Position, part.Position)
                return true
            end
        end
    end
    return false
end

local function hook_remote(r)
    if remote_state.hooked[r] ~= nil then return end
    remote_state.hooked[r] = false
    local hm = hook_fn()
    if not hm then return end
    local ok = pcall(hm, r, "__namecall", function(self, method, ...)
        if (method == "FireServer" or method == "InvokeServer")
            and state.silent and state.sa_engine ~= "Camera" and silent_target then
            if state.sa_chance >= 100 or math.random() * 100 <= state.sa_chance then
                local args = table.pack(...)
                if redirect_args(args, workspace.CurrentCamera, silent_target) then
                    return self[method](self, unpack(args, 1, args.n))
                end
            end
        end
        return self[method](self, ...)
    end)
    remote_state.hooked[r] = ok and true or false
end

local function scan_remotes(force)
    -- restore: full descendant walks are expensive — throttle to 5s unless forced
    local now = os.clock()
    if not force and remote_state.last and (now - remote_state.last) < 15 then return end
    remote_state.last = now
    if not remote_state.installed then
        local hm = hook_fn()
        if not hm then return end
        remote_state.installed = true
        remote_state.ok = true
    end
    local roots = { ReplicatedStorage }
    local sp = StarterPlayer and StarterPlayer:FindFirstChild("StarterPlayerScripts")
    if sp then roots[#roots + 1] = sp end
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then roots[#roots + 1] = pg end
    for _, root in ipairs(roots) do
        pcall(function()
            for _, d in ipairs(root:GetDescendants()) do
                if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and remote_state.hooked[d] == nil then
                    hook_remote(d)
                end
            end
        end)
    end
end

local function aim_tick()
    silent_target = nil
    if not silent_armed() then return end
    if UIS:GetFocusedTextBox() then return end
    silent_target = acquire_target()
    if not silent_target then return end
    if state.sa_engine == "Remote" then
        scan_remotes()
    elseif state.sa_engine == "Camera" then
        apply_camera_aim(silent_target)
    else
        scan_remotes()
        apply_camera_aim(silent_target)
    end
end

-- =====================================================================
--  VISUALS
-- =====================================================================

local BONES_R15 = {
    { "HumanoidRootPart", "LowerTorso" }, { "LowerTorso", "UpperTorso" },
    { "UpperTorso", "Head" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" },
}
local BONES_R6 = {
    { "HumanoidRootPart", "Torso" }, { "Torso", "Head" },
    { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local function new_line(parent, z)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 0
    f.BorderSizePixel = 0
    f.AnchorPoint = Vector2.new(0, 0.5)
    f.ZIndex = z or 5
    f.Parent = parent
    return f
end

local function set_line(fr, a, b, thick, color)
    local dx, dy = b.X - a.X, b.Y - a.Y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then fr.Visible = false return end
    fr.Visible = true
    fr.Size = UDim2.fromOffset(len, thick)
    fr.Position = UDim2.fromOffset(a.X, a.Y)
    fr.Rotation = math.deg(math.atan2(dy, dx))
    fr.BackgroundColor3 = color
end

local function kill_entry(e)
    for _, k in ipairs({ "hl", "chams", "sb", "tag", "tracer" }) do
        if e[k] then pcall(function() e[k]:Destroy() end) e[k] = nil end
    end
    e.lab, e.bar, e.fill = nil, nil, nil
    for _, f in ipairs(e.bones or {}) do pcall(function() f:Destroy() end) end
    e.bones, e.bone_set = nil, nil
end

local function build_tag(e, model, name)
    local tag = Instance.new("BillboardGui")
    tag.Name = "tag"
    tag.Size = UDim2.new(0, 200, 0, 34)
    tag.StudsOffset = Vector3.new(0, 3, 0)
    tag.AlwaysOnTop = true
    tag.MaxDistance = 1e6
    tag.ZIndex = 20
    local lab = Instance.new("TextLabel")
    lab.Name = "label"
    lab.Size = UDim2.new(1, 0, 0, 20)
    lab.BackgroundTransparency = 1
    lab.Font = Enum.Font.GothamBold
    lab.TextSize = 13
    lab.TextColor3 = Color3.fromRGB(255, 255, 255)
    lab.TextStrokeTransparency = 0.5
    lab.Text = name
    lab.Parent = tag
    local bg = Instance.new("Frame")
    bg.Name = "barbg"
    bg.Position = UDim2.new(0, 8, 0, 22)
    bg.Size = UDim2.new(1, -16, 0, 4)
    bg.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    bg.BorderSizePixel = 0
    bg.Visible = state.esp_health
    local fill = Instance.new("Frame")
    fill.Name = "barfill"
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
    fill.BorderSizePixel = 0
    fill.Parent = bg
    tag.Adornee = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head") or model
    tag.Parent = esp_gui
    e.tag = tag
    e.lab = lab
    e.bar = bg
    e.fill = fill
    e.tag_anchor = tag.Adornee
    e.tag_name = name
end

local function update_health(e, h)
    if not e.bar then return end
    e.bar.Visible = state.esp_health
    if not state.esp_health or not h then return end
    local max = math.max(h.MaxHealth or 100, 1)
    local ratio = clamp(h.Health / max, 0, 1)
    e.fill.Size = UDim2.fromScale(ratio, 1)
    e.fill.BackgroundColor3 = Color3.fromRGB(
        math.floor(255 * (1 - ratio)),
        math.floor(60 + 195 * ratio),
        60
    )
end

local function draw_entity(e, ent, cam, inset, view)
    local model, h = ent.model, ent.hum
    local anchor = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
    if not anchor then return end
    local is_player = ent.player ~= nil
    -- nothing to draw for this entity -> drop any leftovers and bail
    local want
    if is_player then
        want = state.esp or state.esp_names or state.chams or state.box
            or state.tracer or state.skeleton
    else
        want = state.npc_esp
    end
    if not want then
        kill_entry(e)
        return
    end
    local my = hrp()
    local dist = my and (my.Position - anchor.Position).Magnitude or 0
    local color = is_player and state.esp_color or state.npc_color

    if dist > (is_player and state.esp_dist or state.npc_dist) then
        kill_entry(e)
        return
    end

    if not e.hl then
        e.hl = Instance.new("Highlight")
        e.hl.Name = "hl"
        e.hl.FillTransparency = 0.6
        e.hl.OutlineTransparency = 0
        e.hl.Parent = esp_gui
    end
    e.hl.Visible = is_player and state.esp or state.npc_esp
    e.hl.Adornee = model
    e.hl.FillColor = color
    e.hl.OutlineColor = color

    if state.chams and is_player then
        if not e.chams then
            e.chams = Instance.new("Highlight")
            e.chams.Name = "chams"
            e.chams.OutlineTransparency = 0
            pcall(function() e.chams.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
            e.chams.Parent = esp_gui
        end
        e.chams.Adornee = model
        e.chams.FillColor = state.chams_color
        e.chams.OutlineColor = state.chams_color
        e.chams.FillTransparency = state.chams_fill
    elseif e.chams then
        e.chams:Destroy() e.chams = nil
    end

    if state.box then
        if not e.sb then
            e.sb = Instance.new("SelectionBox")
            e.sb.Name = "box"
            e.sb.Transparency = 1
            pcall(function() e.sb.SurfaceTransparency = 1 end)
            e.sb.Visible = true
            e.sb.Parent = esp_gui
        end
        e.sb.Adornee = model
        e.sb.LineColor = color
        e.sb.LineThickness = state.box_thick
    elseif e.sb then
        e.sb:Destroy() e.sb = nil
    end

    local vp = cam:WorldToViewportPoint(anchor.Position)
    if not state.esp_names then
        if e.tag then e.tag:Destroy() e.tag, e.lab, e.bar, e.fill = nil, nil, nil, nil end
    else
        if not e.tag or e.tag.Parent == nil or e.tag.Adornee == nil then
            build_tag(e, model, ent.name)
        end
        if e.tag then
            e.tag.Adornee = anchor
            if vp.Z > 0 then
                e.tag.Visible = true
                e.lab.Text = string.format("%s  %dm", ent.name, math.floor(dist))
            else
                e.tag.Visible = false
            end
            update_health(e, h)
        end
    end

    if state.tracer and vp.Z > 0 then
        if not e.tracer then
            e.tracer = new_line(esp_gui, 6)
        end
        set_line(e.tracer,
            Vector2.new(view.X * 0.5, view.Y),
            Vector2.new(vp.X, vp.Y + inset.Y),
            state.tracer_thick, state.tracer_color)
    elseif e.tracer then
        e.tracer:Destroy() e.tracer = nil
    end

    if state.skeleton and is_player and vp.Z > 0 then
        local set = model:FindFirstChild("UpperTorso") and BONES_R15 or BONES_R6
        if not e.bones or e.bone_set ~= set or #e.bones ~= #set then
            if e.bones then for _, f in ipairs(e.bones) do pcall(function() f:Destroy() end) end end
            e.bones = {}
            for i = 1, #set do e.bones[i] = new_line(esp_gui, 7) end
            e.bone_set = set
        end
        for i, pair in ipairs(set) do
            local a, b = model:FindFirstChild(pair[1]), model:FindFirstChild(pair[2])
            if a and b then
                local pa = cam:WorldToViewportPoint(a.Position)
                local pb = cam:WorldToViewportPoint(b.Position)
                if pa.Z > 0 and pb.Z > 0 then
                    set_line(e.bones[i],
                        Vector2.new(pa.X, pa.Y + inset.Y),
                        Vector2.new(pb.X, pb.Y + inset.Y),
                        state.bone_thick, state.bone_color)
                else
                    e.bones[i].Visible = false
                end
            else
                e.bones[i].Visible = false
            end
        end
    elseif e.bones then
        for _, f in ipairs(e.bones) do pcall(function() f:Destroy() end) end
        e.bones, e.bone_set = nil, nil
    end
end

local function draw_crosshair()
    if not cross_ui then return end
    if not state.crosshair then
        cross_ui.Visible = false
        return
    end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local inset = gui_inset()
    local view = cam.ViewportSize
    local cx, cy = view.X * 0.5, view.Y * 0.5 + inset.Y
    cross_ui.Visible = true
    cross_ui.Position = UDim2.fromOffset(cx, cy)
    cross_ui.Size = UDim2.fromOffset(state.cross_gap * 2 + 20, state.cross_gap * 2 + 20)
    local g, t = state.cross_gap, state.cross_thick
    cross_ui.top.Size = UDim2.fromOffset(1, g)
    cross_ui.top.Position = UDim2.fromOffset(-1, -g - t)
    cross_ui.bottom.Size = UDim2.fromOffset(1, g)
    cross_ui.bottom.Position = UDim2.fromOffset(-1, t)
    cross_ui.left.Size = UDim2.fromOffset(g, 1)
    cross_ui.left.Position = UDim2.fromOffset(-g - t, -1)
    cross_ui.right.Size = UDim2.fromOffset(g, 1)
    cross_ui.right.Position = UDim2.fromOffset(t, -1)
    cross_ui.dot.Visible = state.cross_dot
    cross_ui.dot.Size = UDim2.fromOffset(t, t)
    cross_ui.dot.Position = UDim2.fromOffset(-t * 0.5, -t * 0.5)
    for _, k in ipairs({ "top", "bottom", "left", "right", "dot" }) do
        cross_ui[k].BackgroundColor3 = state.cross_color
    end
end

local function build_crosshair()
    cross_ui = Instance.new("Frame")
    cross_ui.Name = "RainCrosshair"
    cross_ui.BackgroundTransparency = 1
    cross_ui.AnchorPoint = Vector2.new(0.5, 0.5)
    cross_ui.ZIndex = 30
    cross_ui.Visible = false
    cross_ui.Parent = esp_gui
    for _, k in ipairs({ "top", "bottom", "left", "right", "dot" }) do
        local f = Instance.new("Frame")
        f.Name = k
        f.BackgroundTransparency = 0
        f.BorderSizePixel = 0
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BackgroundColor3 = state.cross_color
        f.ZIndex = 31
        f.Parent = cross_ui
        cross_ui[k] = f
    end
    circle_ui = Instance.new("Frame")
    circle_ui.Name = "RainFovCircle"
    circle_ui.BackgroundTransparency = 1
    circle_ui.AnchorPoint = Vector2.new(0.5, 0.5)
    circle_ui.ZIndex = 29
    circle_ui.Visible = false
    circle_ui.Parent = esp_gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = circle_ui
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 60, 60)
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = circle_ui
    circle_ui.stroke = stroke
end

local function draw_circle()
    if not circle_ui then return end
    if not (state.silent and state.sa_circle and silent_target) then
        circle_ui.Visible = false
        return
    end
    local mp = UIS:GetMouseLocation()
    circle_ui.Visible = true
    circle_ui.Position = UDim2.fromOffset(mp.X, mp.Y)
    circle_ui.Size = UDim2.fromOffset(state.sa_fov * 2, state.sa_fov * 2)
end

local function hide_default_crosshair(enable)
    if enable then
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local names = { crosshair = true, reticle = true, mouseicon = true, mousepointer = true, cursoricon = true }
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("GuiObject") and names[string.lower(d.Name)] and d.Visible then
                hidden_cross[d] = true
                pcall(function() d.Visible = false end)
            end
        end
    else
        for d in pairs(hidden_cross) do
            pcall(function() d.Visible = true end)
        end
        table.clear(hidden_cross)
    end
end

local function draw_target_dot()
    if not (state.silent and state.sa_circle and silent_target) then
        if esp_gui then
            local d = esp_gui:FindFirstChild("RainTargetDot")
            if d then d:Destroy() end
        end
        return
    end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local inset = gui_inset()
    local v = cam:WorldToViewportPoint(silent_target.Position)
    if v.Z <= 0 then return end
    local d = esp_gui:FindFirstChild("RainTargetDot")
    if not d then
        d = Instance.new("Frame")
        d.Name = "RainTargetDot"
        d.Size = UDim2.fromOffset(6, 6)
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
        d.BorderSizePixel = 0
        d.ZIndex = 32
        Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
        d.Parent = esp_gui
    end
    d.Position = UDim2.fromOffset(v.X, v.Y + inset.Y)
end

local function entity_list()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            local hide = state.esp_enemies and same_team(LP, p)
            if h and not hide then
                list[#list + 1] = { model = p.Character, hum = h, name = p.DisplayName or p.Name, player = p }
            end
        end
    end
    if state.npc_esp then
        local n = 0
        for model, h in pairs(npc_cache) do
            if n > 200 then break end
            if model.Parent and h and h.Health > 0 then
                list[#list + 1] = { model = model, hum = h, name = model.Name, player = nil }
                n = n + 1
            end
        end
    end
    return list
end

local function esp_tick()
    if not esp_gui then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local inset = gui_inset()
    local view = cam.ViewportSize
    local any = state.esp or state.npc_esp or state.chams or state.box
        or state.tracer or state.skeleton or state.esp_names or state.crosshair
    local seen = {}
    if any then
        for _, ent in ipairs(entity_list()) do
            local e = vis[ent.player or ent.model]
            if not e then e = {} vis[ent.player or ent.model] = e end
            seen[ent.player or ent.model] = true
            pcall(draw_entity, e, ent, cam, inset, view)
        end
    end
    for k, e in pairs(vis) do
        if not seen[k] or (k.Parent == nil and (k.Character == nil)) then
            kill_entry(e)
            vis[k] = nil
        end
    end
    draw_crosshair()
    draw_circle()
    draw_target_dot()
end

-- initial npc sweep, 3 levels deep — a full GetDescendants() walk freezes big maps,
-- anything spawning later is caught by the DescendantAdded signal instead
local function scan_npcs()
    local function sweep(container, depth)
        if depth > 3 then return end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Model") or child:IsA("Humanoid") then track_npc(child) end
            if depth < 3 and (child:IsA("Model") or child:IsA("Folder")) then
                sweep(child, depth + 1)
            end
        end
    end
    pcall(sweep, workspace, 1)
end

-- incremental npc/mob cache: signal-driven, no per-frame workspace walks
local function track_npc(d)
    if not (d:IsA("Model") or d:IsA("Humanoid")) then return end
    task.defer(function()
        local model = d:IsA("Model") and d or d.Parent
        if not model or not model:IsA("Model") then return end
        local h = model:FindFirstChildOfClass("Humanoid")
        if not h then return end
        if not model:FindFirstChild("HumanoidRootPart") and not model:FindFirstChild("Head") then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character == model then return end
        end
        npc_cache[model] = h
    end)
end

-- =====================================================================
--  MOVEMENT
-- =====================================================================

local function physics_tick()
    local c, r, h = char(), hrp(), hum()
    -- restore: Deepwoken speed.lua — velocity-based, skipped while flying
    if state.speed and not state.fly and r and h then
        pcall(function()
            local dir = Vector3.zero
            if h.MoveDirection.Magnitude > 0 then dir = h.MoveDirection.Unit end
            r.AssemblyLinearVelocity *= Vector3.new(0, 1, 0)
            r.AssemblyLinearVelocity += dir * state.speed_val
        end)
    end
    -- restore: Deepwoken infinite_jump.lua — hold Space to rise
    if state.infjump and not state.fly and r
        and UIS:IsKeyDown(Enum.KeyCode.Space) and not UIS:GetFocusedTextBox() then
        pcall(function()
            r.AssemblyLinearVelocity *= Vector3.new(1, 0, 1)
            r.AssemblyLinearVelocity += Vector3.new(0, state.jump_power, 0)
        end)
    end
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
    if state.fullbright or state.no_shadows or state.no_fog then
        if not saved_light then
            saved_light = {
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                Ambient = Lighting.Ambient,
                FogEnd = Lighting.FogEnd,
                FogStart = Lighting.FogStart,
                GlobalShadows = Lighting.GlobalShadows,
                shadows = {},
            }
            for _, child in ipairs(Lighting:GetChildren()) do
                if child:IsA("Atmosphere") or child:IsA("Clouds") or child:IsA("BloomEffect")
                    or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
                    saved_light.shadows[child] = child.Enabled
                    if state.no_fog then child.Enabled = false end
                end
            end
        end
        if state.fullbright then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        end
        if state.no_fog then
            Lighting.FogEnd = 100000
            Lighting.FogStart = 0
        end
        if state.no_shadows then
            Lighting.GlobalShadows = false
        end
    elseif saved_light then
        pcall(function()
            Lighting.Brightness = saved_light.Brightness
            Lighting.ClockTime = saved_light.ClockTime
            Lighting.Ambient = saved_light.Ambient
            Lighting.FogEnd = saved_light.FogEnd
            Lighting.FogStart = saved_light.FogStart
            Lighting.GlobalShadows = saved_light.GlobalShadows
        end)
        for child, was in pairs(saved_light.shadows) do
            pcall(function() child.Enabled = was end)
        end
        saved_light = nil
    end
    local cam = workspace.CurrentCamera
    if cam then
        if state.fov_on then
            if saved_fov == nil then saved_fov = cam.FieldOfView end
            pcall(function() cam.FieldOfView = state.fov end)
        elseif saved_fov ~= nil then
            pcall(function() cam.FieldOfView = saved_fov end)
            saved_fov = nil
        end
        if state.zoom then
            if saved_zoom == nil then
                saved_zoom = { cam.MaxZoomDistance, cam.MinZoomDistance }
            end
            pcall(function()
                cam.MaxZoomDistance = 1000
                cam.MinZoomDistance = 0.5
            end)
        elseif saved_zoom ~= nil then
            pcall(function()
                cam.MaxZoomDistance = saved_zoom[1]
                cam.MinZoomDistance = saved_zoom[2]
            end)
            saved_zoom = nil
        end
    end
end

-- restore: Jerk Off tool toggle (mirrors Jerk OFF.lua). ON gives the Tool and
-- wires equip/unequip + respawn; OFF stops tracks, drops the Tool, unwires.
local function jerk_anim_loop(anim_id, time_pos, threshold, slot)
    local c = char()
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not h then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. anim_id
    local track = nil
    pcall(function() track = h:LoadAnimation(anim) end)
    pcall(function() anim:Destroy() end)
    if not track then return end
    jerk_conns[slot] = RunService.RenderStepped:Connect(function()
        pcall(function()
            if not jerk_running then
                track:Stop()
            elseif track.TimePosition >= threshold or track.IsPlaying == false then
                track:Play()
                track.TimePosition = time_pos
            end
        end)
    end)
    pcall(function() track:Play() track.TimePosition = time_pos end)
end

local function jerk_start_anims()
    jerk_anim_loop("72042024", 0.5, 0.9, 1)
    jerk_anim_loop("168268306", 1, 1.001, 2)
    jerk_running = true
end

local function jerk_stop_anims()
    jerk_running = false
    for _, conn in pairs(jerk_conns) do pcall(function() conn:Disconnect() end) end
    table.clear(jerk_conns)
end

local function jerk_give_tool()
    local bp = LP:FindFirstChildOfClass("Backpack")
    if not bp then
        local ok, b = pcall(function() return LP:WaitForChild("Backpack", 5) end)
        if ok then bp = b else return nil end
    end
    local old = bp:FindFirstChild("Jerk Off")
    if old then pcall(function() old:Destroy() end) end
    local tool = Instance.new("Tool")
    tool.Name = "Jerk Off"
    tool.RequiresHandle = false
    tool.Parent = bp
    tool.Equipped:Connect(function() if state.jerk then jerk_start_anims() end end)
    tool.Unequipped:Connect(function() jerk_stop_anims() end)
    return tool
end

local function jerk_stop()
    jerk_stop_anims()
    if jerk_char_conn then
        pcall(function() jerk_char_conn:Disconnect() end)
        jerk_char_conn = nil
    end
    pcall(function()
        local bp = LP:FindFirstChildOfClass("Backpack")
        local t = bp and bp:FindFirstChild("Jerk Off")
        if t then t:Destroy() end
    end)
    jerk_tool = nil
end

local function jerk_start()
    jerk_stop()
    jerk_tool = jerk_give_tool()
    jerk_char_conn = LP.CharacterAdded:Connect(function()
        if not state.jerk then return end
        jerk_tool = jerk_give_tool()
    end)
end

local function unload_all()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    if bv then pcall(function() bv:Destroy() end) bv = nil end
    state.silent = false
    restore_camera_aim()
    hide_default_crosshair(false)
    jerk_stop()
    for _, e in pairs(vis) do kill_entry(e) end
    table.clear(vis)
    table.clear(npc_cache)
    if esp_gui then pcall(function() esp_gui:Destroy() end) esp_gui = nil end
    -- restore world/lighting
    state.fullbright, state.no_fog, state.no_shadows = false, false, false
    if saved_light then
        pcall(function()
            Lighting.Brightness = saved_light.Brightness
            Lighting.ClockTime = saved_light.ClockTime
            Lighting.Ambient = saved_light.Ambient
            Lighting.FogEnd = saved_light.FogEnd
            Lighting.FogStart = saved_light.FogStart
            Lighting.GlobalShadows = saved_light.GlobalShadows
        end)
        for child, was in pairs(saved_light.shadows) do
            pcall(function() child.Enabled = was end)
        end
        saved_light = nil
    end
    local cam = workspace.CurrentCamera
    if cam then
        if saved_fov then pcall(function() cam.FieldOfView = saved_fov end) end
        if saved_zoom then
            pcall(function()
                cam.MaxZoomDistance = saved_zoom[1]
                cam.MinZoomDistance = saved_zoom[2]
            end)
        end
    end
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
    -- restore: keybind toggles need loaded_signal, which the Deepwoken boot
    -- creates after place routing — universal returns earlier, so make it here.
    if not getgenv().loaded_signal then
        local ok, sig = pcall(require, "@src/utility/signal")
        if ok and sig and sig.new then
            getgenv().loaded_signal = sig.new()
        end
    end
    local tab_mod = require("@src/utility/ui/wrapper")
    local Lib = getgenv().Library
    if not (Lib and Lib.PRWindow) then
        return warn("[restore] universal: UI window unavailable")
    end
    -- the UI lib instance must exist for Theme/Save managers
    env = getgenv()
    if env.aztup and not env.aztup.ui then
        env.aztup.ui = Lib
    end
    Lib.PRWindow:SetWindowTitle(string.format(
        'universal <font color="#%s">%s</font>', Lib.AccentColor:ToHex(), tostring(place_id)))

    -- =====================  MAIN  =====================
    local main = tab_mod.new("Main")
    local movement = main:newGroupBox("Movement")
    movement:newToggleWithKeybind("u_fly", "Fly", false, "WASD + Space/Ctrl, camera direction.",
        function(v)
            state.fly = v
            if not v and bv then pcall(function() bv:Destroy() end) bv = nil end
        end, true)
    movement:newSlider("u_fly_speed", "Fly Speed", 120, 20, 400, 0, true, "st/s",
        function(v) state.fly_speed = v end)
    movement:newToggleWithKeybind("u_speed", "WalkSpeed", false, "Velocity-based, like Deepwoken.",
        function(v) state.speed = v end, true)
    movement:newSlider("u_speed_val", "Speed Value", 175, 1, 250, 0, true, "st/s",
        function(v) state.speed_val = v end)
    movement:newToggleWithKeybind("u_noclip", "Noclip", false, "No collision.",
        function(v) state.noclip = v end, true)
    movement:newToggle("u_infjump", "Infinite Jump", false, "Hold Space to rise, like Deepwoken.",
        function(v) state.infjump = v end)
    movement:newSlider("u_jump_power", "Jump Power", 50, 1, 500, 0, true, "",
        function(v) state.jump_power = v end)

    local fun = main:newGroupBox("Fun")
    fun:newToggle("u_jerk", "Jerk", false, "Gives the Jerk Off tool; removing the toggle takes it back.",
        function(v)
            state.jerk = v
            if v then jerk_start() else jerk_stop() end
        end)

    -- =====================  COMBAT  =====================
    local combat = tab_mod.new("Combat")
    local aim = combat:newGroupBox("Silent Aim")
    aim:newToggleWithKeybind("u_silent", "Silent Aim", false,
        "Redirects attacks to the closest player in FOV. Works via camera raycast swap + remote arg rewrite.",
        function(v)
            state.silent = v
            if v then
                -- hook attack remotes up front so the first shot already redirects
                task.spawn(function() scan_remotes(true) end)
            else
                restore_camera_aim()
            end
        end, true)
    aim:newSlider("u_sa_fov", "FOV Radius", 120, 10, 500, 0, true, "px",
        function(v) state.sa_fov = v end)
    aim:newDropdown("u_sa_part", "Target Part", { "Best", "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Humanoid" },
        "Best", false, "Best = whichever bone is closest to your crosshair.", function(v) state.sa_part = v end)
    aim:newSlider("u_sa_smooth", "Smoothness", 100, 0, 100, 0, true, "%",
        function(v) state.sa_smooth = v end, "100% = instant snap, 0% = free rotation.")
    aim:newSlider("u_sa_chance", "Hit Chance", 100, 1, 100, 0, true, "%",
        function(v) state.sa_chance = v end, "Applies to the remote engine (rolls per shot).")
    aim:newSlider("u_sa_dist", "Max Distance", 1000, 10, 5000, 0, true, "st",
        function(v) state.sa_dist = v end)
    aim:newDropdown("u_sa_activate", "Activation", { "Always", "Mouse1", "Key" }, "Always", false,
        "Always / hold Mouse1 / hold a key.", function(v) state.sa_activate = v end)
    aim:newTextbox("u_sa_aimkey", "Aim Key", false, "", true,
        "Key name (Q / E / MouseButton2). Only used with Activation = Key.",
        "", function(v) state.sa_aimkey = tostring(v) end)
    aim:newDropdown("u_sa_engine", "Engine", { "Both", "Camera", "Remote" }, "Both", false,
        "Camera = per-frame raycast swap. Remote = rewrites aim args on attack remotes.",
        function(v) state.sa_engine = v end)
    aim:newToggle("u_sa_enemies", "Enemies Only", false, "Skip teammates (where Teams exist).",
        function(v) state.sa_enemies = v end)
    aim:newToggle("u_sa_los", "Line of Sight", true, "Only lock targets you can actually see.",
        function(v) state.sa_los = v end)
    aim:newToggle("u_sa_circle", "Show FOV Circle + Target Dot", true, "Draws the aim radius and the locked point.",
        function(v) state.sa_circle = v end)

    local misc_c = combat:newGroupBox("Utility")
    misc_c:newButton("Re-Scan Remotes", function()
        table.clear(remote_state.hooked)
        scan_remotes(true)
        local n = 0
        for r, ok in pairs(remote_state.hooked) do
            if ok then n = n + 1 end
        end
        notify(string.format("remote scan done — %d hooked", n))
    end, false, "Re-hooks remotes (use after a game streams new weapons).")
    misc_c:newButton("Copy Silent Aim Config", function()
        local parts = {}
        for _, k in ipairs({ "sa_fov", "sa_part", "sa_smooth", "sa_chance", "sa_engine" }) do
            parts[#parts + 1] = k .. "=" .. tostring(state[k])
        end
        local txt = "rain-silent: " .. table.concat(parts, ", ")
        local ok = pcall(function()
            if setclipboard then setclipboard(txt) elseif writefile then
                writefile("rain_silent.txt", txt)
            end
        end)
        notify(ok and "silent aim config copied" or "clipboard unavailable — see console")
    end, false, "Copies current aim settings to the clipboard.")

    -- =====================  VISUALS  =====================
    local visuals = tab_mod.new("Visuals")
    local espbox = visuals:newGroupBox("Player ESP")
    espbox:newToggleWithKeybind("u_esp", "Player ESP", false, "Highlight players.",
        function(v) state.esp = v end, true)
    espbox:newToggle("u_esp_names", "Name Tags + Distance", true, "Billboard nametags.",
        function(v) state.esp_names = v end)
    espbox:newToggle("u_esp_health", "Health Bars", true, "Bar under the nametag.",
        function(v) state.esp_health = v end)
    espbox:newToggle("u_esp_enemies", "Enemies Only", false, "Hide teammates (where Teams exist).",
        function(v) state.esp_enemies = v end)
    espbox:newSlider("u_esp_dist", "ESP Max Distance", 1000, 50, 5000, 0, true, "st",
        function(v) state.esp_dist = v end)
    espbox:newColorPicker("u_esp_color", "ESP Color", state.esp_color,
        function(v) state.esp_color = v end)

    local ex = visuals:newGroupBox("Extras")
    ex:newToggle("u_chams", "Chams (X-Ray)", false, "Second highlight, always on top.",
        function(v) state.chams = v end)
    ex:newSlider("u_chams_fill", "Chams Fill", 35, 0, 100, 0, true, "%",
        function(v) state.chams_fill = v / 100 end)
    ex:newColorPicker("u_chams_color", "Chams Color", state.chams_color,
        function(v) state.chams_color = v end)
    ex:newToggle("u_box", "Box ESP", false, "SelectionBox around the character.",
        function(v) state.box = v end)
    ex:newSlider("u_box_thick", "Box Thickness", 1, 1, 5, 0, true, "px",
        function(v) state.box_thick = v end)
    ex:newToggle("u_tracer", "Tracer", false, "Line from the bottom of the screen.",
        function(v) state.tracer = v end)
    ex:newSlider("u_tracer_thick", "Tracer Thickness", 1, 1, 6, 0, true, "px",
        function(v) state.tracer_thick = v end)
    ex:newColorPicker("u_tracer_color", "Tracer Color", state.tracer_color,
        function(v) state.tracer_color = v end)
    ex:newToggle("u_skeleton", "Skeleton", false, "Bone lines (R6/R15 aware).",
        function(v) state.skeleton = v end)
    ex:newSlider("u_bone_thick", "Skeleton Thickness", 1, 1, 5, 0, true, "px",
        function(v) state.bone_thick = v end)
    ex:newColorPicker("u_bone_color", "Skeleton Color", state.bone_color,
        function(v) state.bone_color = v end)

    local npcs = visuals:newGroupBox("Entity ESP")
    npcs:newToggleWithKeybind("u_npc_esp", "NPC / Mob ESP", false, "Highlights NPCs, mobs and NPCs.",
        function(v)
            state.npc_esp = v
            if v then task.spawn(scan_npcs) end
        end, true)
    npcs:newSlider("u_npc_dist", "Entity Max Distance", 300, 10, 3000, 0, true, "st",
        function(v) state.npc_dist = v end)
    npcs:newColorPicker("u_npc_color", "Entity Color", state.npc_color,
        function(v) state.npc_color = v end)

    local world = visuals:newGroupBox("World")
    world:newToggle("u_fullbright", "FullBright", false, "Force daylight.",
        function(v) state.fullbright = v end)
    world:newToggle("u_no_fog", "Remove Fog / Effects", false, "Huge fog end, disables atmosphere, bloom, clouds.",
        function(v) state.no_fog = v end)
    world:newToggle("u_no_shadows", "Disable Shadows", false, "GlobalShadows off.",
        function(v) state.no_shadows = v end)

    local camera = visuals:newGroupBox("Camera")
    camera:newToggle("u_fov_on", "Custom FOV", false, "Lock field of view.",
        function(v) state.fov_on = v end)
    camera:newSlider("u_fov", "FOV Value", 70, 30, 120, 0, true, "deg",
        function(v) state.fov = v end)
    camera:newToggle("u_zoom", "Infinite Zoom", false, "Zoom out up to 1000.",
        function(v) state.zoom = v end)

    local cross = visuals:newGroupBox("Crosshair")
    cross:newToggle("u_crosshair", "Crosshair", false, "Custom crosshair.",
        function(v) state.crosshair = v end)
    cross:newColorPicker("u_cross_color", "Crosshair Color", state.cross_color,
        function(v) state.cross_color = v end)
    cross:newSlider("u_cross_thick", "Thickness", 2, 1, 8, 0, true, "px",
        function(v) state.cross_thick = v end)
    cross:newSlider("u_cross_gap", "Gap", 4, 0, 30, 0, true, "px",
        function(v) state.cross_gap = v end)
    cross:newToggle("u_cross_dot", "Center Dot", false, "Dot in the middle.",
        function(v) state.cross_dot = v end)
    cross:newToggle("u_hide_default_cross", "Hide Game Crosshair", false,
        "Hides PlayerGui objects named Crosshair/Reticle/MouseIcon.",
        function(v) hide_default_crosshair(v) end)

    -- =====================  UI  =====================
    local uitab = tab_mod.new("UI")
    local ok_t, ThemeManager = pcall(require, "@src/utility/librarys/managers/ThemeManager")
    local ok_s, SaveManager = pcall(require, "@src/utility/librarys/managers/SaveManager")
    if ok_t and ThemeManager and ThemeManager.SetLibrary then
        pcall(function()
            ThemeManager:SetLibrary(Lib)
            ThemeManager:SetFolder("Project Rain/Universal-Config")
            ThemeManager:ApplyToTab(uitab.Tab)
        end)
    end
    if ok_s and SaveManager and SaveManager.BuildConfigSection then
        pcall(function()
            SaveManager:SetLibrary(Lib)
            SaveManager:IgnoreThemeSettings()
            SaveManager:SetFolder("Project Rain/Universal-Config")
            SaveManager:SetIgnoreIndexes({ "u_fly", "u_noclip", "u_speed", "u_infjump", "u_silent", "u_jerk" })
            SaveManager:BuildConfigSection(uitab.Tab)
        end)
    end
    local menubox = uitab:newGroupBox("Menu")
    menubox:newButton("Unload Menu", function()
        unload_all()
    end, false, "Unloads the universal hub (all features off, UI destroyed).")

    local gui_parent = nil
    pcall(function()
        gui_parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
    if not gui_parent then gui_parent = LP:WaitForChild("PlayerGui") end
    esp_gui = Instance.new("ScreenGui")
    esp_gui.Name = "RainUniversalESP"
    esp_gui.ResetOnSpawn = false
    esp_gui.IgnoreGuiInset = true
    esp_gui.DisplayOrder = 100
    esp_gui.Parent = gui_parent
    build_crosshair()

    conns[#conns + 1] = RunService.PreSimulation:Connect(physics_tick)
    -- restore: restore the camera in the same frame, after game logic ran —
    -- PostSimulation is the last hook before the frame renders
    if not pcall(function()
        conns[#conns + 1] = RunService.PostSimulation:Connect(restore_camera_aim)
    end) then
        conns[#conns + 1] = RunService.Heartbeat:Connect(restore_camera_aim)
    end
    conns[#conns + 1] = RunService.Heartbeat:Connect(esp_tick)
    conns[#conns + 1] = RunService.PreSimulation:Connect(aim_tick)
    conns[#conns + 1] = workspace.DescendantAdded:Connect(track_npc)
    conns[#conns + 1] = Players.PlayerRemoving:Connect(function(p)
        local e = vis[p]
        if e then kill_entry(e) end
        vis[p] = nil
        if p.Character then npc_cache[p.Character] = nil end
    end)
    task.spawn(function()
        for i = 1, 40 do
            if not esp_gui then return end
            if i % 15 == 0 then scan_remotes(true) end
            task.wait(5)
        end
    end)

    -- restore: same clickable banner as the Deepwoken menu (src/ui/menu_banner.lua)
    task.spawn(xpcall, function()
        require("@src/ui/menu_banner").initialize()
    end, warn)

    pcall(function()
        if Lib.Toggled ~= true then Lib:Toggle() end
    end)
    print("[restore] universal hub (Main/Combat/Visuals/UI) for place " .. tostring(place_id))
end }
