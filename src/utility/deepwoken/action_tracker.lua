local tracker = {};
tracker.__index = tracker;

-- restore: resolve the LIVE EffectReplicator at call time. The boot stub is
-- replaced by the real game module after replication; chunks may hold a stale
-- global snapshot, so never use the load-time global directly.
local function live_er()
    local gg = (typeof(getgenv) == "function" and getgenv()) or _G
    local er = gg and gg.EffectReplicator or nil
    if type(er) == "table" then return er end
    return EffectReplicator
end

function tracker:can_parry()
	local er = live_er()
	if not er:FindEffect("Equipped") then
		return false
	end

	return not er:FindEffect("ParryCool")
end


function tracker:can_dodge()
	local er = live_er()
	if er:HasAny("NoRoll", "PreventRoll", "Stun") then
		return false
	end

	return true
end

function tracker:activate_request(mantra)
	self.on_mantra_request:Fire(mantra);
end

function tracker.new(player_data)
    local self = setmetatable({}, tracker);
	self.on_mantra_request = Instance.new("BindableEvent");
	self.last_equip_call = false;

	player_data.character_added:connect(function()
		tracker.last_equip_call = false;
	end);

    return self
end

return tracker
