-- Restored Timing Builder (source was stripped upstream).
-- Minimal but functional: pick a watched animation (Timing Logger click feeds
-- it via load_track), set windup/hitbox/type, Save writes rw_timings/<name>.lua
-- which the Reload Timings button (and hot-reload) picks up into timing_data.
local builder = {};
builder.on_close = nil;

local gui_parent = nil
pcall(function()
    gui_parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)
if not gui_parent then
    local lp = game:GetService("Players").LocalPlayer
    gui_parent = lp and lp:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Name = "RainTimingBuilder"
frame.Size = UDim2.new(0, 300, 0, 300)
frame.Position = UDim2.new(0.5, -150, 0.4, -150)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Active = true

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 26)
title.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
title.BorderSizePixel = 0
title.Text = "Timing Builder"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = frame

-- manual drag (no UI-lib dependency)
do
    local dragging, start_pos, start_input = false, nil, nil
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            start_pos = frame.Position
            start_input = input.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - start_input
            frame.Position = UDim2.new(start_pos.X.Scale, start_pos.X.Offset + d.X, start_pos.Y.Scale, start_pos.Y.Offset + d.Y)
        end
    end)
end

local y = 32
local boxes = {}
local function add_row(label_text, initial)
    local lab = Instance.new("TextLabel")
    lab.Size = UDim2.new(0, 110, 0, 24)
    lab.Position = UDim2.new(0, 8, 0, y)
    lab.BackgroundTransparency = 1
    lab.Text = label_text
    lab.TextColor3 = Color3.fromRGB(200, 200, 200)
    lab.Font = Enum.Font.Gotham
    lab.TextSize = 12
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.Parent = frame
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 170, 0, 24)
    box.Position = UDim2.new(0, 122, 0, y)
    box.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    box.BorderSizePixel = 0
    box.Text = tostring(initial or "")
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.ClearTextOnFocus = false
    box.Parent = frame
    boxes[label_text] = box
    y += 28
    return box
end

add_row("Anim ID", "")
add_row("Name", "CustomM1")
add_row("Windup (s)", "0.35")
add_row("Hitbox XYZ", "14,20,14")
add_row("Action Type", "M1")

local type_btn = Instance.new("TextButton")
type_btn.Size = UDim2.new(0, 170, 0, 24)
type_btn.Position = UDim2.new(0, 122, 0, y)
type_btn.BackgroundColor3 = Color3.fromRGB(50, 90, 50)
type_btn.BorderSizePixel = 0
type_btn.Text = "Parry"
type_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
type_btn.Font = Enum.Font.GothamBold
type_btn.TextSize = 12
type_btn.Parent = frame
do
    local lab = Instance.new("TextLabel")
    lab.Size = UDim2.new(0, 110, 0, 24)
    lab.Position = UDim2.new(0, 8, 0, y)
    lab.BackgroundTransparency = 1
    lab.Text = "Defend Type"
    lab.TextColor3 = Color3.fromRGB(200, 200, 200)
    lab.Font = Enum.Font.Gotham
    lab.TextSize = 12
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.Parent = frame
end
y += 28
type_btn.MouseButton1Click:Connect(function()
    type_btn.Text = (type_btn.Text == "Parry") and "Dodge" or "Parry"
end)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 20)
status.Position = UDim2.new(0, 8, 0, y)
status.BackgroundTransparency = 1
status.Text = ""
status.TextColor3 = Color3.fromRGB(140, 220, 140)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame
y += 24

local save_btn = Instance.new("TextButton")
save_btn.Size = UDim2.new(0, 136, 0, 28)
save_btn.Position = UDim2.new(0, 8, 0, y)
save_btn.BackgroundColor3 = Color3.fromRGB(40, 110, 60)
save_btn.BorderSizePixel = 0
save_btn.Text = "Save Timing"
save_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
save_btn.Font = Enum.Font.GothamBold
save_btn.TextSize = 13
save_btn.Parent = frame

local close_btn = Instance.new("TextButton")
close_btn.Size = UDim2.new(0, 136, 0, 28)
close_btn.Position = UDim2.new(0, 156, 0, y)
close_btn.BackgroundColor3 = Color3.fromRGB(110, 40, 40)
close_btn.BorderSizePixel = 0
close_btn.Text = "Close"
close_btn.TextColor3 = Color3.fromRGB(255, 255, 255)
close_btn.Font = Enum.Font.GothamBold
close_btn.TextSize = 13
close_btn.Parent = frame

frame.Size = UDim2.new(0, 300, 0, y + 36)
pcall(function() frame.Parent = gui_parent end)

local function sanitize(s)
    return tostring(s or ""):gsub("[^%w_%-]", ""):sub(1, 40)
end

save_btn.MouseButton1Click:Connect(function()
    local id = tostring(boxes["Anim ID"].Text or ""):match("%d+")
    local name = sanitize(boxes["Name"].Text)
    if not id or #name == 0 then
        status.Text = "need numeric Anim ID + Name"
        return
    end
    local windup = tonumber(boxes["Windup (s)"].Text) or 0.35
    local hx, hy, hz = tostring(boxes["Hitbox XYZ"].Text or ""):match("([%d%.]+)[,%s]+([%d%.]+)[,%s]+([%d%.]+)")
    hx, hy, hz = tonumber(hx) or 14, tonumber(hy) or 20, tonumber(hz) or 14
    local atype = tostring(boxes["Action Type"].Text or "M1")
    if atype ~= "M1" and atype ~= "Spell" and atype ~= "Critical" then atype = "M1" end
    local dtype = (type_btn.Text == "Dodge") and "Dodge" or "Parry"
    local src = string.format(
        "return {\n    ids = { %q },\n    action_type = %q,\n    name = %q,\n    default_chance = 100,\n    allow_block_input = true,\n    allow_parry_to_roll = true,\n    allow_roll_to_parry = true,\n    allow_parry_to_block = true,\n    run = function(action)\n        action.when = %.3f;\n        action.hitbox = Vector3.new(%.1f, %.1f, %.1f);\n        action.offset = CFrame.new(0, 0, -5);\n        action.type = %q;\n        action:push();\n        return action\n    end\n}\n",
        id, atype, name, windup, hx, hy, hz, dtype)
    local ok, err = pcall(function()
        if not isfolder("rw_timings") then makefolder("rw_timings") end
        writefile("rw_timings/" .. name .. ".lua", src)
        if getgenv().load_timings then getgenv().load_timings() end
    end)
    status.Text = ok and ("saved " .. name .. " (reloaded)") or ("save failed: " .. tostring(err):sub(1, 60))
end)

function builder:set_visible(val)
    frame.Visible = val and true or false
end

close_btn.MouseButton1Click:Connect(function()
    builder:set_visible(false)
    if builder.on_close then pcall(builder.on_close) end
end)

-- Timing Logger entries call this with the live track: prefill id + suggest
-- windup from the track length, then open the window.
function builder:load_track(track, entity)
    pcall(function()
        local aid = track and track.Animation and tostring(track.Animation.AnimationId or ""):match("%d+")
        if aid then boxes["Anim ID"].Text = aid end
        local len = track and track.Length
        if typeof(len) == "number" and len > 0 then
            boxes["Windup (s)"].Text = string.format("%.3f", len * 0.55)
        end
        local en = entity and entity.Name or ""
        if en ~= "" then boxes["Name"].Text = sanitize(en):sub(1, 24) end
        status.Text = "track loaded, adjust + Save"
    end)
    builder:set_visible(true)
end

getgenv().timing_builder = builder
return builder
