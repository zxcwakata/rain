

local feature = Feature:new("leaderboard_spectate"); 
local camera = workspace.CurrentCamera
local maid = require(("@src/utility/maid"));

local currentSpectatedLabel: TextLabel? = nil
local defaultTextColor = Color3.new(1, 1, 1)
feature.conns = {};
feature.unique_id = services.HttpService:GenerateGUID(); 

-- restore: bundle Player List Spectating port (stream-on-demand, notifies,
-- single streaming task, generation-guarded subject loop).
local function fetch_name(plr: Player): string
    return string.format("(%s) %s", plr:GetAttribute("CharacterName") or "Unknown Character Name", plr.Name)
end

local spectate_gen = 0
local function start_subject_loop(label: TextLabel, get_subject)
    spectate_gen += 1
    local my_gen = spectate_gen
    task.spawn(function()
        while spectate_gen == my_gen and currentSpectatedLabel == label do
            if not local_player.instance:HasTag("ForcedSubject") then
                local_player.instance:AddTag("ForcedSubject")
            end
            local ok, subject = pcall(get_subject)
            if ok and subject then
                camera.CameraSubject = subject
            end
            task.wait();
        end
    end)
end

local stream_last = 0
local function ensure_stream_conn(self)
    if self.stream_conn then return end
    self.stream_conn = services.RunService.RenderStepped:Connect(function()
        if tick() - stream_last < 0.25 or not currentSpectatedLabel then return end
        stream_last = tick();
        local subject = workspace.CurrentCamera.CameraSubject;
        if subject == local_player.humanoid or not subject then return end
        local root = (subject:IsA("BasePart") and subject) or subject:FindFirstChild("HumanoidRootPart")
        if not root then return end
        pcall(function()
            local_player.instance:RequestStreamAroundAsync(root.Position, 0.1);
        end);
    end);
    table.insert(self.conns, self.stream_conn)
end


local function is_player_frame_map(map): boolean
    if type(map) ~= "table" then return false end

    for key, value in pairs(map) do
        if typeof(key) == "Instance" and key:IsA("Player") and typeof(value) == "Instance" then
            return true
        end
    end
    return false
end

local warned_no_map = false


local function get_player_frame_map()
    local ok, result = pcall(function()
        local signal = services.CollectionService:GetInstanceRemovedSignal("ChatBlocked_" .. local_player.instance.UserId)
        local conns = getconnections(signal)
        if not conns or #conns == 0 then
            error("no connections on ChatBlocked_ signal yet");
        end

        local fn = conns[1].Function
        
        for i = 1, 20 do
            local ok_uv, value = pcall(getupvalue, fn, i)
            if not ok_uv or value == nil then break end
            if is_player_frame_map(value) then
                return value
            end
        end

        error("no upvalue on ChatBlocked_ connection matched the player frame map shape");
    end)

    if ok then
        warned_no_map = false;
        return result
    end

    if not warned_no_map then
        
        warned_no_map = true;
    end
    return nil
end

local function get_player_from_frame(frame: Instance): Player?
    local map = get_player_frame_map()
    if not map then return nil end

    for plr, player_frame in pairs(map) do
        if player_frame == frame then
            return plr
        end
    end
    return nil
end

local function get_frame_from_player(plr: Player): Instance?
    local map = get_player_frame_map()
    return map and map[plr]
end


local function wait_for_player_frame_map(): { [Player]: Instance }
    while true do
        local map = get_player_frame_map()
        if map then return map end
        task.wait();
    end
end

function feature:handle(frame: Frame)
    if frame.Name ~= "PlayerFrame" then return end

    -- restore: bundle ShowHiddenPlayers parity (bundle 86368-86370). Handled
    -- frames are revealed while spectate is on so hidden players stay
    -- clickable; original visibility is restored on disable/cleanup.
    local orig_visible = frame.Visible
    if not orig_visible then
        pcall(function() frame.Visible = true end)
    end
    feature.hidden_restores = feature.hidden_restores or {}

    -- restore: bundle-faithful click path (bundle 85928-85982 has NO hover
    -- precondition and NO transparency gate). The old `inside` flag + the
    -- `Transparency == 0 → return` check ate normal clicks (visible text IS 0)
    -- and could stick: react to MB1 on the frame, nothing else.
    local frame_maid = maid.new();

    local input_began = frame.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        do local gg = getgenv() gg.RAIN_CLICKS = (gg.RAIN_CLICKS or 0) + 1 end

        -- restore: handler may fire before lazy fill registers the module
        do local __f = aztup.features.leaderboard_spectate if __f == nil or __f.unique_id ~= self.unique_id then return end end

        local player_frame = frame:FindFirstChild("PlayerFrame") :: Frame?
        if not player_frame then
            return
        end

        local player_label = player_frame:FindFirstChild("Player") :: TextLabel?
        if not player_label then
            return
        end

        local plr = get_player_from_frame(frame)
        if not plr then
            getgenv().RAIN_LASTCLICK = "map_miss(frame not in player-frame map)"
            return
        end
        if not plr.Character then
            getgenv().RAIN_LASTCLICK = "no_character"
            Logger:notify_sound("Failed to spectate", fetch_name(plr), "their character does not exist.")
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton2 then
			local ray = Ray.new(plr.Character:GetPivot().p, Vector3.new(0,5000,0))
            local marker = services.ReplicatedStorage:FindFirstChild("MarkerWorkspace");
			if marker then
				local found = marker:FindPartOnRayWithWhitelist(ray, {marker:FindFirstChild("AreaMarkers")})
				Logger:notify_sound(plr:GetAttribute("CharacterName") or plr.Name, "is in", found and found.Parent and found.Parent.Name or "Unidentified")
			end
        end

        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        if currentSpectatedLabel == player_label then
            getgenv().RAIN_LASTCLICK = "toggled_off"
            self:stop_spectate();
            return
        end

        -- restore: bundle stream-on-demand (MapPos + missing HRP). WORKS for
        -- streamed-out players: request the area, user clicks again.
        local char = plr.Character
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            local map_pos = char:GetAttribute("MapPos")
            if map_pos then
                pcall(function()
                    local_player.instance:RequestStreamAroundAsync(map_pos, 0.1)
                end)
                getgenv().RAIN_LASTCLICK = "stream_requested"
                Logger:notify_sound("Requesting stream for", fetch_name(plr), "try again later.")
            else
                getgenv().RAIN_LASTCLICK = "not_loaded_in"
                Logger:notify_sound("Failed to spectate", fetch_name(plr), "they are not loaded in.")
            end
            return
        end

        -- restore: bundle subject is the HumanoidRootPart, not the Humanoid
        -- (bundle 85973-85975). Self-click resets via the label toggle above.
        if currentSpectatedLabel then
            currentSpectatedLabel.TextColor3 = defaultTextColor
        end

        local_player.instance:AddTag("ForcedSubject")
        player_label.TextColor3 = Library.AccentColor
        currentSpectatedLabel = player_label
        ensure_stream_conn(self)
        getgenv().RAIN_LASTCLICK = "spectating:" .. tostring(plr.Name)
        Logger:notify_sound("Started spectating", fetch_name(plr))

        start_subject_loop(player_label, function()
            local c = plr.Character
            return c and c:FindFirstChild("HumanoidRootPart")
        end)
    end);

    table.insert(self.conns, input_began)

    frame_maid:give_task(input_began);
    frame_maid:give_task(frame.AncestryChanged:Connect(function()
        if not frame:IsDescendantOf(local_player.instance) then
            frame_maid:do_cleaning();
        end;
    end));
    if not orig_visible then
        local restore_fn = function()
            pcall(function()
                if frame and frame.Parent then frame.Visible = orig_visible end
            end)
        end
        frame_maid:give_task(restore_fn);
        table.insert(feature.hidden_restores, restore_fn)
    end

    aztup.maid:give_task(frame_maid);
end

function feature:stop_spectate()
    spectate_gen += 1
    if currentSpectatedLabel then
        currentSpectatedLabel.TextColor3 = defaultTextColor
    end;
    currentSpectatedLabel = nil

    local_player.instance:RemoveTag("ForcedSubject")
    camera.CameraSubject = local_player.humanoid;
    Logger:notify_sound("Reset spectating camera subject.")
end;

function feature:force_spectate(query: string | Player)
    local target_player: Player?

    if typeof(query) == "Instance" and query:IsA("Player") then
        target_player = query
    elseif type(query) == "string" and query ~= "" then
        for _, player in services.Players:GetPlayers() do
            if player:GetAttribute("CharacterName") == query or player.Name == query then
                target_player = player;
                break            
end;
        end;
    end

    if not target_player or not target_player.Character then return end

    local target_frame = get_frame_from_player(target_player)
    if not target_frame then return end

    local target_player_frame = target_frame:FindFirstChild("PlayerFrame") :: Frame?
    local target_label = target_player_frame and target_player_frame:FindFirstChild("Player") :: TextLabel?
    if not target_label then return end

    local target_hrp = target_player.Character:FindFirstChild("HumanoidRootPart")
    if not target_hrp then return end

    if currentSpectatedLabel == target_label then
        self:stop_spectate();
        return
    end

    if currentSpectatedLabel then
        currentSpectatedLabel.TextColor3 = defaultTextColor
    end

    local_player.instance:AddTag("ForcedSubject")
    target_label.TextColor3 = Library.AccentColor
    currentSpectatedLabel = target_label
    ensure_stream_conn(self)
    Logger:notify_sound("Started spectating", fetch_name(target_player))

    start_subject_loop(target_label, function()
        local c = target_player.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end)
end;

function feature:disable()
    if not self.was_on then return end
    self.was_on = false;

    for _, conn in self.conns do
        conn:Disconnect();
    end;
    table.clear(self.conns);
    self.stream_conn = nil;

    -- restore: undo the ShowHiddenPlayers-style reveal on disable
    if self.hidden_restores then
        for _, fn in self.hidden_restores do pcall(fn) end
        table.clear(self.hidden_restores);
    end

    if self.last_conn then
        self.last_conn:Disconnect();
        self.last_conn = nil;
    end;

    if self.gui_added_conn then
        self.gui_added_conn:Disconnect();
        self.gui_added_conn = nil;
    end;

    self:stop_spectate();
end;

function feature:connect()
    if self.last_conn then
        self.last_conn:Disconnect();
    end;

    local player_gui = local_player.instance:WaitForChild("PlayerGui");
    player_gui:WaitForChild("LeaderboardGui", 9e9):WaitForChild("MainFrame", 9e9):WaitForChild("ScrollingFrame", 9e9);

    wait_for_player_frame_map();

    for _, frame in player_gui.LeaderboardGui.MainFrame.ScrollingFrame:GetChildren() do
        self:handle(frame)
    end

    self.last_conn = player_gui.LeaderboardGui.MainFrame.ScrollingFrame.ChildAdded:Connect(function(frame)
        self:handle(frame)
    end)
    aztup.maid:give_task(self.last_conn)
end;

function feature:enable()
    self.was_on = true;

    task.spawn(xpcall, function()
        local player_gui = local_player.instance:WaitForChild("PlayerGui");

        if self.gui_added_conn then
            self.gui_added_conn:Disconnect();
        end;

        self.gui_added_conn = player_gui.ChildAdded:Connect(function(child)
            if child.Name ~= "LeaderboardGui" then
                return
            end;
            self:connect();
        end);

        self:connect();
    end, warn);
end; 

return feature