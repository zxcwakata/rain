-- rain_hooks_new: hooking core transplanted from Ap_central bundle (fixed hooks).
-- Every combat feature defaults OFF, so all handlers are passthrough.
-- Credits to the original authors; do not redistribute without them.
local KeyHandling = (function()
-- KeyHandler related stuff is handled here.
local KeyHandling = {}

-- Key-handler tables.
local remoteTable = nil
local randomTable = nil

---@module Utility.Logger

-- Hash cache.
local hashCache = {}

---Number to string.
---@param num number
---@param iter number
---@return string
local function nts(num, iter)
	local str = ""

	for _ = 1, iter do
		local v78 = num % 256
		str = string.char(v78) .. str
		num = (num - v78) / 256
	end

	return str
end

---String to number.
---@param str string
---@param len number
---@return number
local function stn(str, len)
	local num = 0

	for i = len, len + 3 do
		num = num * 256 + string.byte(str, i)
	end

	return num
end

---SHA-256 preprocess.
---@param msg string
---@param len number
---@return string
local function preprocess(msg, len)
	return msg .. string.char(128) .. string.rep(string.char(0), 64 - (len + 9) % 64) .. nts(8 * len, 8)
end

---Process SHA-256 digest block.
---@param msg string
---@param i number
---@param H table
local function digest(msg, i, H)
	local chunks = {}

	for j = 1, 16 do
		chunks[j] = stn(msg, i + (j - 1) * 4)
	end

	for j = 17, 64 do
		local v103 = chunks[j - 15]
		local v104 = bit32.bxor(bit32.rrotate(v103, 7), bit32.rrotate(v103, 18), bit32.rshift(v103, 3))
		v103 = chunks[j - 2]
		chunks[j] = chunks[j - 16]
			+ v104
			+ chunks[j - 7]
			+ bit32.bxor(bit32.rrotate(v103, 17), bit32.rrotate(v103, 19), bit32.rshift(v103, 10))
	end

	local a = H[1]
	local b = H[2]
	local c = H[3]
	local d = H[4]
	local e = H[5]
	local f = H[6]
	local g = H[7]
	local h = H[8]

	for iter = 1, 64 do
		local v114 = bit32.bxor(bit32.rrotate(a, 2), bit32.rrotate(a, 13), bit32.rrotate(a, 22))
			+ bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
		local v115 = bit32.bxor(bit32.rrotate(e, 6), bit32.rrotate(e, 11), bit32.rrotate(e, 25))
		local v116 = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
		local v117 = h + v115 + v116 + randomTable[iter] + chunks[iter]
		local l_g_0 = g
		local l_f_0 = f
		local l_v109_0 = e
		local v121 = d + v117
		local l_v107_0 = c
		local l_v106_0 = b
		local l_v105_0 = a

		a = v117 + v114
		b = l_v105_0
		c = l_v106_0
		d = l_v107_0
		e = v121
		f = l_v109_0
		g = l_f_0
		h = l_g_0
	end

	H[1] = bit32.band(H[1] + a)
	H[2] = bit32.band(H[2] + b)
	H[3] = bit32.band(H[3] + c)
	H[4] = bit32.band(H[4] + d)
	H[5] = bit32.band(H[5] + e)
	H[6] = bit32.band(H[6] + f)
	H[7] = bit32.band(H[7] + g)
	H[8] = bit32.band(H[8] + h)
end

---Convert remote name to an hashed SHA-256 one.
---@param remoteName string
---@return string
local function hash(remoteName)
	local processed = preprocess(remoteName, #remoteName)

	local ht = {
		1779033703,
		3144134277,
		1013904242,
		2773480762,
		1359893119,
		2600822924,
		528734635,
		1541459225,
	}

	for iter = 1, #remoteName, 64 do
		digest(processed, iter, ht)
	end

	return nts(ht[1], 4)
		.. nts(ht[2], 4)
		.. nts(ht[3], 4)
		.. nts(ht[4], 4)
		.. nts(ht[5], 4)
		.. nts(ht[6], 4)
		.. nts(ht[7], 4)
		.. nts(ht[8], 4)
end

---Find remote table from upvalues.
---@param upvalues table
---@return table?
local function findRemoteTables(upvalues)
	for _, upvalue in next, upvalues do
		if typeof(upvalue) ~= "table" then
			continue
		end

		if getrawmetatable(upvalue) then
			continue
		end

		if #upvalue ~= 0 then
			continue
		end

		if upvalue[10] then
			continue
		end

		return upvalue
	end
end

---Search for remote table.
---@param value any
---@return boolean
local function searchForRemoteTable(value)
	-- Cached.
	if remoteTable then
		return true
	end

	-- Look for the internal upvalues for each function in KeyHandler.
	if typeof(value) ~= "function" then
		return false
	end

	if iscclosure(value) or isexecutorclosure(value) then
		return false
	end

	local isuccess, info = pcall(debug.getinfo, value)
	if not isuccess or not info then
		return false
	end

	if not info.short_src:match("KeyHandler") then
		return false
	end

	local usuccess, vupvalues = pcall(debug.getupvalue, value, 10)
	if not usuccess or typeof(vupvalues) ~= "table" then
		return false
	end

	if getrawmetatable(vupvalues) then
		return false
	end

	-- Mark as found.
	remoteTable = findRemoteTables(vupvalues)

	-- Return true if we found the remote table.
	return remoteTable ~= nil
end

---Search for random table.
---@param value any
---@return boolean
local function searchForRandomTable(value)
	-- Cached.
	if randomTable then
		return true
	end

	-- Check if this is the random table.
	if typeof(value) ~= "table" then
		return false
	end

	if getrawmetatable(value) then
		return false
	end

	local firstIndex, firstValue = next(value)

	if typeof(firstIndex) ~= "number" then
		return false
	end

	if typeof(firstValue) ~= "number" then
		return false
	end

	if firstValue < 100000 or firstValue > 100000000 then
		return false
	end

	if #value ~= 68 then
		return false
	end

	-- Mark as found.
	randomTable = value

	-- Return true.
	return true
end

---Search through 'getgc' for data.
local function searchForKeyHandlerData()
	for _, value in next, getgc(true) do
		if not searchForRandomTable(value) then
			continue
		end

		if not searchForRemoteTable(value) then
			continue
		end

		return true
	end
end

---Initialize the KeyHandler module.
KeyHandling.init = LPH_NO_VIRTUALIZE(function()
	local retries = 0

	while true do
		-- If we're able to find all the data, break.
		if searchForKeyHandlerData() then
			break
		end

		-- Retry if we can't find the data.
		if not LPH_OBFUSCATED or shared.Lycoris.verbose then
			Logger.warn(
				"KeyHandler retry (%i attempts) with results (%s, %s)",
				retries,
				tostring(remoteTable),
				tostring(randomTable)
			)
		end

		retries = retries + 1

		if retries >= 10 then
			-- Warn.
			Logger.warn("KeyHandler failed to initialize after 10 attempts.")

			-- Error.
			return error("Please report this message to the developers.")
		end

		-- Wait.
		task.wait(0.5)
	end
end)

---Get remote from a specific remote name.
---@param remoteName string
---@return Instance|nil
KeyHandling.getRemote = LPH_NO_VIRTUALIZE(function(remoteName)
	if not randomTable and not remoteTable then
		return nil
	end

	local hashedRemoteName = hashCache[remoteName] or hash(remoteName)

	if not hashCache[remoteName] then
		hashCache[remoteName] = hashedRemoteName
	end

	return remoteTable[hashedRemoteName]
end)

---@param remote Instance
KeyHandling.registerRemote = LPH_NO_VIRTUALIZE(function(remote)
	if not remoteTable then
		return
	end

	local remoteName = remote.Name
	local hashedRemoteName = hashCache[remoteName] or hash(remoteName)

	if not hashCache[remoteName] then
		hashCache[remoteName] = hashedRemoteName
	end

	remoteTable[hashedRemoteName] = remote
end)

-- Return KeyHandling module.
return KeyHandling
end)()
local Logger = { warn = function(...) print("[hooks]", ...) end, log_for_devs = function() end }
local Configuration = { expectToggleValue = function() return false end, expectOptionValue = function() return nil end }
-- Rain bridge: bundle toggles driven by live Rain flags (nil-safe, checked per call)
local RAIN_TOGGLE_MAP = { NoFallDamage = "no_fall" }
local _bundle_cfg = Configuration
Configuration = {
    expectToggleValue = function(name)
        local f = RAIN_TOGGLE_MAP[name]
        if f then
            local ok, v = pcall(function() return getgenv().aztup and getgenv().aztup.flags[f] end)
            if ok then return v == true end
        end
        return false
    end,
    expectOptionValue = function(name)
        return _bundle_cfg.expectOptionValue(name)
    end,
}
local InputClient = { sprintFunctionCache = true, rollFunctionCache = true }
local StateListener = {}
local LeaderboardClient = { calling = false }
local Spoofing = { force = false }
local DodgeOptions = { new = function() return {} end }
local TaskSpawner = { spawn = function(_, fn, ...) if type(fn) == "function" then task.spawn(fn, ...) end end }
local Defense = { shouldBlockInput = function() return false end }
getgenv().shared = getgenv().shared or {}
getgenv().shared.Lycoris = getgenv().shared.Lycoris or {}
if typeof(getnilinstances) ~= "function" then getnilinstances = function() return {} end end
local Hooking = {}

---@module Game.KeyHandling

---@module Utility.Logger

---@module Utility.Configuration

---@module Game.InputClient

---@module Features.Combat.StateListener

---@module Game.LeaderboardClient

---@module Features.Game.Spoofing

---@module Game.Objects.DodgeOptions

---@module Utility.TaskSpawner

---@module Features.Combat.Defense

-- Services.
local LogService = game:GetService("LogService")
local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local lighting = game:GetService("Lighting")
local httpService = game:GetService("HttpService")

-- Cached IsA.
local isA = game.IsA

-- Old hooked functions.
local oldFireServer = nil
local oldUnreliableFireServer = nil
local oldNameCall = nil
local oldNewIndex = nil
local oldTick = nil
local oldToString = nil
local oldIndex = nil
local oldPrint = nil
local oldWarn = nil
local oldHasEffect = nil
local oldGetLogHistory = nil
local usingMetaMethodHooks = false

local oldGetKey = nil
local oldCreateKey = nil
local oldKeyHandlerModule = nil
local hookedGetFn = nil
local hookedCreateFn = nil
local hookedKeyHandlerModule = nil

-- EffectReplicator cached reference (FindFirstChild is not free; require() is already memoized).
local cachedEffectReplicator = nil

local function getEffectReplicator()
	if not cachedEffectReplicator then
		cachedEffectReplicator = replicatedStorage:FindFirstChild("EffectReplicator")
	end
	return cachedEffectReplicator
end

-- InputClient caching.
local lastCallingFunction = nil
local lastFunctionCacheAttempt = 0

-- Action rolling.
local lastActionRoll = nil

-- Walkspeed multiplier. The active value is re-rolled on an interval so the speed
-- boost varies over time instead of being a constant, obvious multiplier.
local walkSpeedRandom = Random.new()
local walkSpeedMultiplier = 1.0
local lastWalkSpeedRefresh = 0
local WALK_SPEED_REFRESH = 1.5

-- Ban remotes table.
local banRemotes = {}

-- Input types.
local INPUT_LEFT_CLICK = 1
local INPUT_RIGHT_CLICK = 2
local INPUT_CRITICAL = 3
local INPUT_CAST = 4
local INPUT_BLOCK = 5

local BLOCK_INPUT_MOVE_MAP = {
	[INPUT_LEFT_CLICK] = "M1s",
	[INPUT_CRITICAL] = "Criticals",
	[INPUT_CAST] = "Mantras",
}

-- Input types two.
local INPUT_TYPE_BEFORE = 1
local INPUT_TYPE_AFTER = 2

local ATTACK_EFFECTS = {
	"LightAttack",
	"HeavyAttack",
	"OffhandAttack",
	"UsingAbility",
	"CastingSpell",
}

---Handle flow state.
---@param type number
local handleFlowState = LPH_NO_VIRTUALIZE(function(type)
	local effectReplicator = getEffectReplicator()
	if not effectReplicator then
		return
	end

	local effectReplicatorModule = require(effectReplicator)
	if not effectReplicatorModule then
		return
	end

	local localPlayer = playersService.LocalPlayer
	if not localPlayer then
		return
	end

	local backpack = localPlayer:FindFirstChild("Backpack")
	if not backpack then
		return
	end

	local flowStateTool = backpack:FindFirstChild("Talent:Flow State")
	if not flowStateTool then
		return
	end

	local flowStateRemote = flowStateTool:FindFirstChild("ActivateRt")
	if not flowStateRemote then
		return
	end

	local flowStateCooldown = false
	local shUpperCooldown = false
	local shDashCooldown = false
	local shGapCloserCooldown = false

	for _, effect in next, effectReplicatorModule.Effects do
		local index = rawget(effect, "index")
		if not index then
			continue
		end

		if index.Class == "ToolCD" and index.Value == "Talent: Flow State" then
			flowStateCooldown = true
		end

		if index.Class:match("SHUpper") and index.Class:match("CD") then
			shUpperCooldown = true
		end

		if index.Class:match("SHDash") and index.Class:match("CD") then
			shDashCooldown = true
		end

		if index.Class:match("SHGap") and index.Class:match("CD") then
			shGapCloserCooldown = true
		end
	end

	Logger.warn(
		"(%s, %s, %s, %s, %s) Current cooldown state...",
		shUpperCooldown and "SHUpperCD" or "SHUpperReady",
		shDashCooldown and "SHDashCD" or "SHDashReady",
		shGapCloserCooldown and "SHGapCloserCD" or "SHGapCloserReady",
		effectReplicatorModule:FindEffect("SlideAttackCD") and "SlideAttackCD" or "SlideAttackReady",
		flowStateCooldown and "FlowStateCD" or "FlowStateReady"
	)

	if flowStateCooldown then
		return Logger.warn("Flow state is on cooldown.")
	end

	Logger.warn("(%i) Attempting to detect Silentheart moves for input type.", type)

	if
		effectReplicatorModule:FindEffect("Sliding")
		and not effectReplicatorModule:FindEffect("SlideAttackCD")
		and type == INPUT_LEFT_CLICK
	then
		Logger.warn("Detected 'Ankle Cutter' move.")

		flowStateRemote:FireServer()
	end

	if effectReplicatorModule:FindEffect("SHDash") and not shDashCooldown and type == INPUT_LEFT_CLICK then
		Logger.warn("Detected 'Mayhem' move.")

		flowStateRemote:FireServer()
	end

	-- If we've done an aerial attack -- (aerial cooldown effect)
	-- If we've attacked also -- (light attack effect)
	if
		effectReplicatorModule:FindEffect("AerialCD")
		and effectReplicatorModule:FindEffect("LightAttack")
		and not shGapCloserCooldown
		and type == INPUT_LEFT_CLICK
	then
		Logger.warn("Detected 'Relentless Hunt' move.")

		flowStateRemote:FireServer()
	end

	if
		(
			effectReplicatorModule:FindEffect("Sliding")
			or effectReplicatorModule:FindEffect("ClientCrouch")
			or effectReplicatorModule:FindEffect("Crouching")
		)
		and not shUpperCooldown
		and type == INPUT_RIGHT_CLICK
	then
		Logger.warn("Detected 'Rising Star' move.")

		flowStateRemote:FireServer()
	end
end)

---Handle action rolling.
---@param type number
local handleActionRolling = LPH_NO_VIRTUALIZE(function(type)
	local actionRollTypes = Configuration.expectOptionValue("ActionRollingActions") or {}
	local actionRollInputs = {
		[INPUT_LEFT_CLICK] = actionRollTypes["Roll On M1"],
		[INPUT_CRITICAL] = actionRollTypes["Roll On Critical"],
		[INPUT_CAST] = actionRollTypes["Roll On Cast"],
		[INPUT_BLOCK] = actionRollTypes["Roll On Parry"],
	}

	if not actionRollInputs[type] then
		return
	end

	if type ~= INPUT_CAST then
		local effectReplicator = getEffectReplicator()
		if not effectReplicator then
			return
		end

		local effectReplicatorModule = require(effectReplicator)
		if not effectReplicatorModule then
			return
		end

		if not effectReplicatorModule:HasEffect("Equipped") then
			return
		end
	end

	if type == INPUT_CAST then
		local lMantraActivated = StateListener.lMantraActivated
		if not lMantraActivated then
			return
		end

		if lMantraActivated.Name:match("Wisp") then
			return
		end
	end

	if
		lastActionRoll
		and os.clock() - lastActionRoll < (Configuration.expectOptionValue("ActionRollCooldown") or 2.0)
	then
		return
	end

	-- Timestamp it.
	lastActionRoll = os.clock()

	-- Wait.
	if type ~= INPUT_BLOCK then
		task.wait(0.1)
	end

	-- Perform options.
	local options = DodgeOptions.new()
	options.rollCancel = true
	options.rollCancelDelay = Configuration.expectOptionValue("ActionRollCancelDelay") or 0.1
	options.actionRolling = true

	-- Dodge.
	Logger.warn("(%i) Performing action roll dodge.", type)

	if type == INPUT_CAST then
		TaskSpawner.spawn("ActionRolling_CastDodge", InputClient.dodge, options)
	else
		InputClient.dodge(options)
	end
end)

---Handle delayed feints.
local handleDelayedFeints = LPH_NO_VIRTUALIZE(function()
	local lAnimTrack = StateListener.lAnimationValidTrack
	if not lAnimTrack then
		return Logger.warn("No valid animation track for delayed feint.")
	end

	local lAnimFaction = StateListener.lAnimFaction
	if not lAnimFaction then
		return Logger.warn("No animation faction for delayed feint.")
	end

	if not lAnimTrack.IsPlaying then
		return Logger.warn("Non playing animation track for delayed feint.")
	end

	if not StateListener.cfeint() then
		return Logger.warn("Unable to feint for delayed feint.")
	end

	local laTimestamp = StateListener.lAnimTimestamp
	if not laTimestamp then
		return Logger.warn("No animation timestamp for delayed feint.")
	end

	local laLatency = StateListener.lAnimLatency
	if not laLatency then
		return Logger.warn("No animation latency for delayed feint.")
	end

	local delayed = (lAnimFaction:when() - (os.clock() - laTimestamp)) - laLatency

	Logger.warn("Delaying for %.2f seconds before sending the feint remote.", delayed)

	task.wait(delayed)
end)

---On intercepted input.
---@param type number
---@param state number
local onInterceptedInput = LPH_NO_VIRTUALIZE(function(type, state)
	if Configuration.expectToggleValue("AutoFlowState") and state == INPUT_TYPE_BEFORE and type ~= INPUT_CAST then
		handleFlowState(type)
	end

	if Configuration.expectToggleValue("ActionRolling") and state == INPUT_TYPE_AFTER then
		handleActionRolling(type)
	end

	if
		Configuration.expectToggleValue("DelayedFeints")
		and state == INPUT_TYPE_BEFORE
		and type == INPUT_RIGHT_CLICK
		and StateListener.lAnimationValidTrack
	then
		handleDelayedFeints()
	end
end)

---Recursively find first valid InputClient stack.
---@return table?
local findInputClientStack = LPH_NO_VIRTUALIZE(function()
	for level = 1, math.huge do
		-- Get info.
		local success, info = pcall(debug.getinfo, level)
		if not success or not info then
			break
		end

		-- Check source.
		if not info.source:match("InputClient") then
			continue
		end

		-- Check if CClosure.
		if iscclosure(info.func) then
			continue
		end

		-- Fetch alternative stack - on Wave, this will fail. You cannot wrap debug.getstack(...) in pcall.
		local ssuccess, stack = pcall(debug.getstack, level)

		-- Return stack.
		return ssuccess and stack or debug.getstack(level - 1)
	end
end)

---Find the first call-stack level whose source matches the given pattern.
---@param source string
---@return number?, table?
local findSourceLevel = LPH_NO_VIRTUALIZE(function(source)
	for level = 1, math.huge do
		local success, info = pcall(debug.getinfo, level)
		if not success or not info then
			break
		end
		if info.source:match(source) then
			return level, info
		end
	end
end)

---@return number?, table?
local findClientPhysicsLevel = LPH_NO_VIRTUALIZE(function()
	return findSourceLevel("ClientPhysics")
end)

---@return number?, table?
local findInputClientLevel = LPH_NO_VIRTUALIZE(function()
	return findSourceLevel("InputClient")
end)

---Stop gesture animations.
---@param animator Animator
local stopGestureAnimations = LPH_NO_VIRTUALIZE(function(animator)
	for _, animationTrack in pairs(animator:GetPlayingAnimationTracks()) do
		if not animationTrack.Animation or animationTrack.Animation.Parent.Name ~= "Gestures" then
			continue
		end

		animationTrack:Stop()
	end
end)

---Replicate gesture.
---@param gestureName string
local replicateGesture = LPH_NO_VIRTUALIZE(function(gestureName)
	local assets = replicatedStorage:FindFirstChild("Assets")
	local anims = assets and assets:FindFirstChild("Anims")
	local gestures = anims and anims:FindFirstChild("Gestures")
	local gesture = gestures and gestures:FindFirstChild(gestureName)
	if not gesture then
		return
	end

	local localPlayer = playersService.LocalPlayer
	if not localPlayer then
		return
	end

	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		return
	end

	local effectReplicator = getEffectReplicator()
	local effectReplicatorModule = effectReplicator and require(effectReplicator)
	if not effectReplicatorModule then
		return
	end

	if effectReplicatorModule:FindEffect("Gesturing") then
		return
	end

	-- Create animation objects.
	local actionEffect = effectReplicatorModule:CreateEffect("Action")
	local gesturingEffect = effectReplicatorModule:CreateEffect("Gesturing")
	local mobileActionEffect = effectReplicatorModule:CreateEffect("MobileAction")
	local gestureAnimation = animator:LoadAnimation(gesture)

	-- Play animation.
	stopGestureAnimations(animator)
	gestureAnimation:Play()

	-- Wait for movement to cancel.
	repeat
		task.wait()
	until humanoid.MoveDirection.Magnitude > 0

	-- Wait a bit...
	task.wait(0.5)

	-- Remove effects.
	actionEffect:Remove()
	gesturingEffect:Remove()
	mobileActionEffect:Remove()

	-- Stop animations.
	stopGestureAnimations(animator)
end)

---Modify ambience color.
---@param value Color3
local modifyAmbienceColor = LPH_NO_VIRTUALIZE(function(value)
	local ambienceColor = Configuration.expectOptionValue("AmbienceColor")
	local shouldUseOriginalAmbienceColor = Configuration.expectToggleValue("OriginalAmbienceColor")

	if not shouldUseOriginalAmbienceColor and ambienceColor then
		return ambienceColor
	end

	local brightness = Configuration.expectOptionValue("OriginalAmbienceColorBrightness") or 0.0
	local red, green, blue = value.R, value.G, value.B

	red = math.min(red + brightness, 255)
	green = math.min(green + brightness, 255)
	blue = math.min(blue + brightness, 255)

	return Color3.fromRGB(red, green, blue)
end)

---On print.
---@return any
local onPrint = LPH_NO_VIRTUALIZE(function(...)
	if checkcaller() then
		return oldPrint(...)
	end

	if Configuration.expectToggleValue("StopGameLogging") then
		return
	end

	return oldPrint(...)
end)

---On warn.
---@return any
local onWarn = LPH_NO_VIRTUALIZE(function(...)
	if checkcaller() then
		return oldWarn(...)
	end

	if Configuration.expectToggleValue("StopGameLogging") then
		return
	end

	return oldWarn(...)
end)

---On get log history.
---@return any
local onGetLogHistory = LPH_NO_VIRTUALIZE(function(...)
	local result = oldGetLogHistory(...)

	local blockedPatterns = {
		"Lycoris Recode",       -- Logger.warn prefix
		"debug%.profileEnd%(%)", -- executor profile fingerprint
		"getgc", "hookfunction", "hookmetamethod", -- executor API names
		"checkcaller", "getrawmetatable",
		"LPH_NO_VIRTUALIZE",
	}

	for idx = #result, 1, -1 do
		local msg = result[idx].message
		for _, pat in next, blockedPatterns do
			if msg:find(pat) then
				table.remove(result, idx)
				break
			end
		end
	end

	return result
end)

---On tick.
---@return any
local onTick = LPH_NO_VIRTUALIZE(function(...)
	if checkcaller() then
		return oldTick(...)
	end

	if not Configuration.expectToggleValue("AutoSprint") then
		return oldTick(...)
	end

	local level, info = findInputClientLevel()
	if not level or not info then
		return oldTick(...)
	end

	local stack = findInputClientStack()
	if not stack then
		return error("Stack is nil.")
	end

	local firstConstantSuccess, firstConstant = pcall(debug.getconstant, info.func, 1)
	if not firstConstantSuccess then
		return oldTick(...)
	end

	if firstConstant ~= "UserInputType" then
		return oldTick(...)
	end

	---@note: Filter for any other spots that might be using tick() through the stack.
	if
		not table.find(stack, "W")
		and not table.find(stack, "A")
		and not table.find(stack, "S")
		and not table.find(stack, "D")
	then
		return oldTick(...)
	end

	---@note: We can indeed set a delay in here. The active thread is InputClient.
	if Configuration.expectToggleValue("AutoSprintDelay") then
		task.wait(Configuration.expectOptionValue("AutoSprintDelayTime"))
	end

	local effectReplicator = getEffectReplicator()
	if not effectReplicator then
		return
	end

	local effectReplicatorModule = require(effectReplicator)
	if not effectReplicatorModule then
		return
	end

	if
		not Configuration.expectToggleValue("AutoSprintOnCrouch") and effectReplicatorModule:HasEffect("ClientCrouch")
	then
		return oldTick(...)
	end

	---@note: Set the timestamp set by sprinting to -math.huge so it's always over 0.25s.
	return -math.huge
end)

---On index.
---@return any
local onIndex = LPH_NO_VIRTUALIZE(function(self, index, ...)
	if checkcaller() then
		return oldIndex(self, index, ...)
	end

	---@note: Patch out InputClient detection for __index hooking to prevent annoying errors.
	if typeof(index) == "table" then
		return error("InputClient - Lycoris On Top")
	end

	if Spoofing.force or not Configuration.expectToggleValue("InfoSpoofing") then
		return oldIndex(self, index, ...)
	end

	if typeof(self) == "Instance" and typeof(index) == "string" then
		if index == "Value" then
			if self.Name == "SERVER_NAME" then
				return Configuration.expectOptionValue("SpoofedServerName")
			end

			if self.Name == "SERVER_REGION" then
				return Configuration.expectOptionValue("SpoofedServerRegion")
			end

			if self.Name == "SERVER_AGE" then
				return Configuration.expectOptionValue("SpoofedServerAge")
			end
		end

		if isA(self, "Player") then
			if index == "DisplayName" then
				return "Linoria V2 On Top"
			end

			if index == "Name" then
				return "Linoria V2 On Top"
			end

			if index == "UserId" then
				return 000000000
			end
		end
	end

	return oldIndex(self, index, ...)
end)

---On name call.
---@return any
local onNameCall = LPH_NO_VIRTUALIZE(function(self, ...)
	if not LeaderboardClient.calling and checkcaller() then
		return oldNameCall(self, ...)
	end

	if banRemotes[self] then
		return Logger.warn("(%s) Anticheat is referencing a ban remote.", self.Name)
	end

	if typeof(self) ~= "Instance" then
		return oldNameCall(self, ...)
	end

	local secondArg = ...
	local method = getnamecallmethod()
	local name = self.Name

	if method == "Raycast" then
		local callingScript = getcallingscript()
		local _, info = findClientPhysicsLevel()

		if callingScript and callingScript.Name == "ClientPhysics" and info then
			if info and info.name == "" then
				return false
			end
		end
	end

	if method == "Create" then
		---@note: Fix object if we're using a lighting template.
		local lightingTemplate = select(3, ...)

		if typeof(lightingTemplate) == "table" then
			if
				lightingTemplate["FogStart"]
				and lightingTemplate["FogEnd"]
				and Configuration.expectToggleValue("NoFog")
			then
				lightingTemplate["FogStart"] = 9e9
				lightingTemplate["FogEnd"] = 9e9
			end

			if lightingTemplate["Ambient"] and Configuration.expectToggleValue("ModifyAmbience") then
				lightingTemplate["Ambient"] = modifyAmbienceColor(lightingTemplate["Ambient"])
			end

			if lightingTemplate["Density"] and Configuration.expectToggleValue("NoFog") then
				lightingTemplate["Density"] = 0
			end

			---@note: lightingTemplate is mutated in place (same table reference), so
			return oldNameCall(self, ...)
		end
	end

	if Configuration.expectToggleValue("InfoSpoofing") then
		if typeof(secondArg) == "string" and method == "GetAttribute" and not Spoofing.force then
			local localPlayer = playersService.LocalPlayer
			local character = localPlayer and localPlayer.Character
			local humanoid = game.FindFirstChild(character, "Humanoid")
			local foreign = true

			if character and humanoid and (self.Parent == character or self.Parent == humanoid) then
				foreign = false
			end

			if foreign and not Configuration.expectToggleValue("SpoofOtherPlayers") then
				return oldNameCall(self, ...)
			end

			if secondArg == "FirstName" then
				return foreign and "Linoria V2" or Configuration.expectOptionValue("SpoofedFirstName")
			end

			if secondArg == "LastName" then
				return foreign and "On Top" or Configuration.expectOptionValue("SpoofedLastName")
			end

			if secondArg == "CharacterName" then
				local characterName = Configuration.expectOptionValue("SpoofedFirstName")
					.. " "
					.. Configuration.expectOptionValue("SpoofedLastName")

				return foreign and "Linoria V2 On Top" or characterName
			end

			if secondArg == "Guild" then
				return foreign and "discord.gg/lyc" or Configuration.expectOptionValue("SpoofedGuild")
			end

			if secondArg == "GuildRich" then
				return foreign and "discord.gg/lyc" or Configuration.expectOptionValue("SpoofedGuildName")
			end
		end
	end

	if name == "ActivateMantra" and method == "FireServer" then
		if not checkcaller() and Defense.shouldBlockInput("Mantras") then
			return
		end

		-- State.
		StateListener.lMantraActivated = secondArg

		-- Before.
		onInterceptedInput(INPUT_CAST, INPUT_TYPE_BEFORE)

		-- Now.
		local result = oldNameCall(self, ...)

		-- After.
		onInterceptedInput(INPUT_CAST, INPUT_TYPE_AFTER)

		-- Return.
		return result
	end

	if name == "Gesture" and Configuration.expectToggleValue("EmoteSpoofer") and typeof(secondArg) == "string" then
		return replicateGesture(secondArg)
	end

	if name == "ClientEffectBatch" and method == "FireServer" then
		local payload = secondArg
		if type(payload) == "table" then
			for i, entry in next, payload do
			end
		else
			Logger.warn("ClientEffectBatch payload is not a table.")
		end
		return
	end

	return oldNameCall(self, ...)
end)

---On unreliable fire server.
---@return any
local onUnreliableFireServer = LPH_NO_VIRTUALIZE(function(self, ...)
	if banRemotes[self] then
		return Logger.warn("(%s) Anticheat is calling a unreliable ban remote.", self.Name)
	end

	local leftClickRemote = KeyHandling.getRemote("LeftClick")
	local criticalRemote = KeyHandling.getRemote("CriticalClick")
	local feintClickRemote = KeyHandling.getRemote("FeintClick")
	local offhandAttackRemote = KeyHandling.getRemote("OffhandAttack")

	local inputType = nil

	if criticalRemote and self == criticalRemote then
		inputType = INPUT_CRITICAL
	end

	if leftClickRemote and self == leftClickRemote then
		inputType = INPUT_LEFT_CLICK
	end

	if (feintClickRemote and self == feintClickRemote) or (offhandAttackRemote and self == offhandAttackRemote) then
		inputType = INPUT_RIGHT_CLICK
	end

	if inputType then
		if not checkcaller() and Defense.shouldBlockInput(BLOCK_INPUT_MOVE_MAP[inputType]) then
			return
		end

		-- Before.
		onInterceptedInput(inputType, INPUT_TYPE_BEFORE)

		-- Now.
		local result = oldUnreliableFireServer(self, ...)

		-- After.
		onInterceptedInput(inputType, INPUT_TYPE_AFTER)

		-- Return.
		return result
	end

	if checkcaller() then
		return oldUnreliableFireServer(self, ...)
	end

	return oldUnreliableFireServer(self, ...)
end)

---On fire server.
---@return any
local onFireServer = LPH_NO_VIRTUALIZE(function(self, ...)
	if banRemotes[self] then
		return Logger.warn("(%s) Anticheat is calling a ban remote.", self.Name)
	end

	local blockRemote = KeyHandling.getRemote("Block")

	local inputType = nil

	if blockRemote and self == blockRemote then
		inputType = INPUT_BLOCK
	end

	if inputType then
		-- Before.
		onInterceptedInput(inputType, INPUT_TYPE_BEFORE)

		-- Now.
		local result = oldFireServer(self, ...)

		-- After.
		onInterceptedInput(inputType, INPUT_TYPE_AFTER)

		-- Return.
		return result
	end

	return oldFireServer(self, ...)
end)

---Get the current walkspeed multiplier, re-rolling it once the refresh interval passes.
---@return number
local getWalkSpeedMultiplier = LPH_NO_VIRTUALIZE(function()
	if os.clock() - lastWalkSpeedRefresh > WALK_SPEED_REFRESH then
		local min = Configuration.expectOptionValue("WalkSpeedMultiplierMinimum") or 1.0
		local max = Configuration.expectOptionValue("WalkSpeedMultiplierMaximum") or 1.0

		if min > max then
			min, max = max, min
		end

		walkSpeedMultiplier = walkSpeedRandom:NextNumber(min, max)
		lastWalkSpeedRefresh = os.clock()
	end

	return walkSpeedMultiplier
end)

---On new index.
---@return any
local onNewIndex = LPH_NO_VIRTUALIZE(function(self, index, value, ...)
	if checkcaller() then
		return oldNewIndex(self, index, value, ...)
	end

	if typeof(self) ~= "Instance" then
		return oldNewIndex(self, index, value, ...)
	end

	---@note: Only these keys are ever rewritten below, so bail cheaply on anything
	if
		index ~= "Text"
		and index ~= "ActiveController"
		and index ~= "MouseIconEnabled"
		and index ~= "Ambient"
		and index ~= "WalkSpeed"
	then
		return oldNewIndex(self, index, value, ...)
	end

	---@note: Scale the game's own walkspeed writes for our local humanoid. Because
	-- checkcaller() writes bailed above, only the game's writes reach here, so the
	-- multiplied value replicates naturally instead of us setting WalkSpeed ourselves.
	if index == "WalkSpeed" and Configuration.expectToggleValue("WalkSpeedMultiplier") and typeof(value) == "number" then
		local localPlayer = playersService.LocalPlayer
		local character = localPlayer and localPlayer.Character

		if character and self.Parent == character and isA(self, "Humanoid") then
			return oldNewIndex(self, index, value * getWalkSpeedMultiplier(), ...)
		end
	end

	if Configuration.expectToggleValue("InfoSpoofing") then
		if game.IsA(self, "TextLabel") and index == "Text" and not Spoofing.force then
			if self.Name == "Slot" and self.Parent.Name == "CharacterInfo" then
				return oldNewIndex(self, index, Configuration.expectOptionValue("SpoofedSlotString"))
			end

			if self.Name == "GameVersion" then
				return oldNewIndex(self, index, Configuration.expectOptionValue("SpoofedGameVersion"))
			end

			if self.Name == "Date" then
				return oldNewIndex(self, index, Configuration.expectOptionValue("SpoofedDateString"))
			end
		end
	end

	if Configuration.expectToggleValue("NoClip") and Configuration.expectToggleValue("Fly") then
		if index == "ActiveController" then
			if self.Parent then
				local airController = self:FindFirstChild("AirController")
				return oldNewIndex(self, index, airController or value)
			end
		end
	end

	if index == "MouseIconEnabled" then
		return oldNewIndex(self, index, true)
	end

	if index == "Ambient" then
		if self == lighting and Configuration.expectToggleValue("ModifyAmbience") then
			return oldNewIndex(self, index, modifyAmbienceColor(value))
		end
	end

	return oldNewIndex(self, index, value, ...)
end)

---On to string.
---@return any
local onToString = LPH_NO_VIRTUALIZE(function(str, ...)
	if str == "EEKEWAEJIWAJDOIWAJDIOJAWDIOJAWODJOAIW" then
		Logger.warn("Crash was attempted.")
		return coroutine.yield()
	end

	if InputClient.sprintFunctionCache and InputClient.rollFunctionCache then
		return oldToString(str, ...)
	end

	if os.clock() - lastFunctionCacheAttempt <= 0.5 then
		return oldToString(str, ...)
	end

	local level, info = findInputClientLevel()
	if not level or not info then
		return oldToString(str, ...)
	end

	lastFunctionCacheAttempt = os.clock()

	-- Cache InputClient data.
	local success = InputClient.cache()

	if success then
		lastCallingFunction = info.func
	end

	-- Continue.
	return oldToString(str, ...)
end)

---On has effect.
---@return any
local onHasEffect = LPH_NO_VIRTUALIZE(function(self, class, ...)
	if checkcaller() then
		return oldHasEffect(self, class, ...)
	end

	if Configuration.expectToggleValue("NoAttackingClientChecks") and table.find(ATTACK_EFFECTS, class) then
		return false
	end

	if Configuration.expectToggleValue("NoFallDamage") and class == "NoFall" then
		return true
	end

	return oldHasEffect(self, class, ...)
end)

---@return string
local generateRandomName = LPH_NO_VIRTUALIZE(function()
	local guid = httpService:GenerateGUID(false):lower():gsub("[%-]*", "")
	local length = math.random(8, 16)
	local built = guid:sub(1, length)
	local capitalizedLast = false

	for i = 1, length do
		local prefix = built:sub(1, i - 1)
		local char = built:sub(i, i)
		local suffix = built:sub(i + 1)

		local asNumber = tonumber(char)
		if asNumber then
			char = string.char(103 + asNumber)
		end

		if i == 1 or (math.random(1, 6) == 1 and not capitalizedLast and i < length) then
			char = char:upper()
			capitalizedLast = true
		else
			capitalizedLast = false
		end

		built = prefix .. char .. suffix
	end

	return built:sub(1, length)
end)

---@param remote any
---@return Instance?
local emulatedGetKey = LPH_NO_VIRTUALIZE(function(remote)
	if typeof(remote) ~= "string" then
		return
	end

	return KeyHandling.getRemote(remote)
end)

---@param remote Instance
local emulatedCreateKey = LPH_NO_VIRTUALIZE(function(remote)
	KeyHandling.registerRemote(remote)
	remote.Name = generateRandomName()
end)

---Install the metamethod/function hooks. Doesn't touch LocalPlayer at all, so this can
---(and should) run as early as possible, before LocalPlayer or the character exist.
function Hooking.earlyInit()
	oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, onFireServer)
	oldUnreliableFireServer = hookfunction(Instance.new("UnreliableRemoteEvent").FireServer, onUnreliableFireServer)
	oldToString = hookfunction(tostring, onToString)
	oldIndex = hookfunction(getrawmetatable(game).__index, onIndex)

	if hookmetamethod then
		oldNameCall = hookmetamethod(game, "__namecall", onNameCall)
		oldNewIndex = hookmetamethod(game, "__newindex", onNewIndex)
		usingMetaMethodHooks = true
	else
		oldNameCall = hookfunction(getrawmetatable(game).__namecall, onNameCall)
		oldNewIndex = hookfunction(getrawmetatable(game).__newindex, onNewIndex)
		usingMetaMethodHooks = false
	end
	oldTick = hookfunction(tick, onTick)
	oldWarn = hookfunction(warn, onWarn)
	oldPrint = hookfunction(print, onPrint)
	oldGetLogHistory = hookfunction(LogService.GetLogHistory, onGetLogHistory)
end

---Hooking initialization.
---@note: Hooking.earlyInit() must have already run before this.
function Hooking.init()
	local localPlayer = playersService.LocalPlayer

	---@improvement: Add a listener for this script.
	local playerScripts = localPlayer:WaitForChild("PlayerScripts")
	local clientActor = playerScripts:WaitForChild("ClientActor")
	local clientManager = clientActor:WaitForChild("ClientManager")
	local requests = replicatedStorage:WaitForChild("Requests")

	---@note: Crucial part because of the actor and the error detection.
	clientManager.Enabled = false

	---@note: Dynamically get the ban remotes.
	local banRemoteCount = 0

	for _, request in next, requests:GetChildren() do
		local hasChangedConnection = #getconnections(request.Changed)
		if hasChangedConnection <= 0 then
			continue
		end

		banRemoteCount = banRemoteCount + 1
		banRemotes[request] = true
	end

	-- Did we execute with a standalone AC bypass?
	local nulledBanRemotes = {}

	for _, instance in next, getnilinstances() do
		if instance.Name ~= "NulledBanRemote" then
			continue
		end

		nulledBanRemotes[#nulledBanRemotes + 1] = instance
	end

	if #nulledBanRemotes ~= 2 then
		if banRemoteCount ~= 2 then
			return error("Anticheat has less or more than two ban remotes.")
		end
	end

	local effectReplicator = replicatedStorage:WaitForChild("EffectReplicator")
	local effectReplicatorModule = require(effectReplicator)

	oldHasEffect = effectReplicatorModule.HasEffect

	effectReplicatorModule.HasEffect = onHasEffect

	---@note: KeyHandler is now fully emulated (Project Rain style) instead of being

	local replicatedStorage = game:GetService("ReplicatedStorage")
	local modules = replicatedStorage:WaitForChild("Modules")
	local clientManager = modules:WaitForChild("ClientManager")
	local keyHandler = clientManager:WaitForChild("KeyHandler")
	local keyHandlerModule = require(keyHandler)

	---@note: Future require()s of the module now build our emulated table.
	hookedKeyHandlerModule = keyHandlerModule

	oldKeyHandlerModule = hookfunction(
		keyHandlerModule,
		LPH_NO_VIRTUALIZE(function()
			return { emulatedGetKey, emulatedCreateKey, "Lycoris On Top" }
		end)
	)

	---@note: Replace the already-created get/create pair in memory so existing
	for _, candidate in next, getgc(true) do
		if typeof(candidate) ~= "table" then
			continue
		end

		if getrawmetatable(candidate) then
			continue
		end

		if #candidate ~= 2 then
			continue
		end

		if typeof(candidate[1]) ~= "function" or typeof(candidate[2]) ~= "function" then
			continue
		end

		local getFn = candidate[1]
		local createFn = candidate[2]

		local getOk, getInfo = pcall(debug.getinfo, getFn)
		local createOk, createInfo = pcall(debug.getinfo, createFn)
		if not getOk or not createOk or not getInfo or not createInfo then
			continue
		end

		if not getInfo.source:find("KeyHandler") or not createInfo.source:find("KeyHandler") then
			continue
		end

		hookedGetFn = getFn
		hookedCreateFn = createFn

		oldGetKey = hookfunction(getFn, emulatedGetKey)
		oldCreateKey = hookfunction(createFn, emulatedCreateKey)

		candidate[1] = emulatedGetKey
		candidate[2] = emulatedCreateKey

		break
	end

	if not hookedGetFn then
		Logger.warn("KeyHandler get/create pair not found in getgc; module hook only.")
	end

	-- Okay, we're done.
	if not LPH_OBFUSCATED or shared.Lycoris.verbose then
		Logger.warn("Client-side anticheat has been penetrated.")
	end
end

---Hooking detach.
-- restore: staged, yielding detach. Restoring every hook in one atomic burst
-- while game threads sit inside them is what hard-crashes (esp. Potassium).
-- Order: client AC back on first, cheap function hooks, yield, metamethods,
-- yield, remotes, effect module. Every step isolated via pcall.
function Hooking.detach()
	local localPlayer = playersService.LocalPlayer

	pcall(function()
		local playerScripts = localPlayer and localPlayer:FindFirstChild("PlayerScripts")
		local clientActor = playerScripts and playerScripts:FindFirstChild("ClientActor")
		local clientManager = clientActor and clientActor:FindFirstChild("ClientManager")
		if clientManager then
			clientManager.Enabled = true
		end
	end)
	task.wait(0.2)

	if hookedKeyHandlerModule and oldKeyHandlerModule then
		pcall(hookfunction, hookedKeyHandlerModule, oldKeyHandlerModule)
	end

	if hookedGetFn and oldGetKey then
		pcall(hookfunction, hookedGetFn, oldGetKey)
	end

	if hookedCreateFn and oldCreateKey then
		pcall(hookfunction, hookedCreateFn, oldCreateKey)
	end

	if oldPrint then
		pcall(hookfunction, print, oldPrint)
	end

	if oldWarn then
		pcall(hookfunction, warn, oldWarn)
	end

	if oldGetLogHistory then
		pcall(hookfunction, LogService.GetLogHistory, oldGetLogHistory)
	end

	if oldTick then
		pcall(hookfunction, tick, oldTick)
	end

	if oldToString then
		pcall(hookfunction, tostring, oldToString)
	end
	task.wait(0.2)

	if oldIndex then
		pcall(hookfunction, getrawmetatable(game).__index, oldIndex)
	end

	if oldNameCall then
		if usingMetaMethodHooks and hookmetamethod then
			pcall(hookmetamethod, game, "__namecall", oldNameCall)
		else
			pcall(hookfunction, getrawmetatable(game).__namecall, oldNameCall)
		end
	end

	if oldNewIndex then
		if usingMetaMethodHooks and hookmetamethod then
			pcall(hookmetamethod, game, "__newindex", oldNewIndex)
		else
			pcall(hookfunction, getrawmetatable(game).__newindex, oldNewIndex)
		end
	end
	task.wait(0.2)

	if oldFireServer then
		pcall(hookfunction, Instance.new("RemoteEvent").FireServer, oldFireServer)
	end

	if oldUnreliableFireServer then
		pcall(hookfunction, Instance.new("UnreliableRemoteEvent").FireServer, oldUnreliableFireServer)
	end

	pcall(function()
		local effectReplicator = getEffectReplicator()
		local effectReplicatorModule = effectReplicator and require(effectReplicator)

		if oldHasEffect and effectReplicatorModule then
			effectReplicatorModule.HasEffect = oldHasEffect
			oldHasEffect = nil
		end
	end)

	usingMetaMethodHooks = false

	pcall(Logger.warn, "Pulled out of client-side anticheat.")
end

-- Return Hooking module.

-- auto-init real KeyHandling (remote table scan); game + Rain lookups need it.
-- Retries forever: early boot often precedes game replication.
task.spawn(function()
    while true do
        if getgenv().RAIN_RESTORED_DEAD then break end
        local ok, err = pcall(function() KeyHandling.init() end)
        if ok then
            print("[hooks] KeyHandling ready")
            break
        end
        task.wait(5)
    end
end)
-- Rain restore compat: legacy global KeyHandler API backed by the transplant
getgenv().KeyHandler = {
    get_key = function(_, name) return KeyHandling.getRemote(name) end,
    get_cache = function(_, name) return KeyHandling.getRemote(name) end,
}

return Hooking