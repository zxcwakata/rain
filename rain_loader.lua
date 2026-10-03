--[[

    Rain OSS FULL RESTORE loader — Project Rain (Deepwoken), community restore.
    Original code: Project Rain OSS (keep credits if you redistribute).

    HOW TO USE:
      1. Upload the whole `project-rain-oss-master` folder to GitHub
         (keep `src/` and `assets/` layout exactly).
      2. Set BASE_URL below to your raw base, e.g.
         "https://raw.githubusercontent.com/YOU/REPO/main/project-rain-oss-master/"
      3. Execute this file in Deepwoken. AutoExecute-ready.

    What was reimplemented (stripped upstream): require/list_modules builder,
    security/user_service, luarmor init, main_menu loader, features/loader,
    timing builder, custom timings, refresh button, spotify widget,
    asset pipeline (inline_asset_b96/decode_asset over HTTP).
    Game/UI/feature files load VERBATIM from your repo.

]]

local BASE_URL = "https://raw.githubusercontent.com/zxcwakata/rain/main/"

-- version stamp: check with print(getgenv().RAIN_LOADER_VERSION).
-- If it prints nil or an older tag, you are executing a STALE copy
-- (old file contents, executor cache, or a duplicate in autoexec folder).
getgenv().RAIN_LOADER_VERSION = "2026-10-03/ports-1"
print("[restore] loader " .. getgenv().RAIN_LOADER_VERSION)

if not game:IsLoaded() then
    repeat task.wait() until game:IsLoaded()
end

-- ==================== URL require shim ====================
local __cache = {}
local function __fetch(url)
    return game:HttpGet(url)
end

local STUBS = {
    ["@src/luarmor_init_script"] = function() return nil end,
    ["@src/security/user_service"] = function() return {} end,
    ["@src/utility/setup_auto_load"] = function() return function() end end,
    ["@src/main_menu/loader"] = function() return true end,
    ["@src/features/auto-parry/builder"] = function()
        return { set_visible = function() end }
    end,
    ["@src/features/auto-parry/data/custom_timings"] = function()
        return {
            sync = function() return function() end end,
            lookup = function() return nil end,
        }
    end,
    ["@src/features/buttons/refresh"] = function()
        return function()
            local ok, fn = pcall(require, "@src/features/buttons/respawn")
            if ok and type(fn) == "function" then fn() end
        end
    end,
    ["@src/features/misc/spotify_widget"] = function() return {} end,
}

-- source patches for build-time assumptions (logged, minimal, compat-only)
-- source patches: fixes now live in the repo files themselves;
-- the mechanism stays for future compat shims. Format:
--   ["path"] = { { "anchor", "replacement" [, "all"] } }
--   ["path"] = { { line = "pattern", after = "code to insert" } }
local SOURCE_PATCHES = {
}

local function apply_patches(rel, src)
    local rules = SOURCE_PATCHES[rel]
    if not rules then return src end
    -- split once, work line-wise (immune to indent/line-ending drift)
    local lines = {}
    for ln in (src .. "\n"):gmatch("(.-)\n") do
        local clean = ln:gsub("\r$", "")
        table.insert(lines, clean)
    end
    for _, r in ipairs(rules) do
        if r.line then
            local at = nil
            for i, ln in ipairs(lines) do
                if ln:match("^%s*" .. r.line .. "%s*$") then at = i break end
            end
            if at then
                table.insert(lines, at + 1, r.after)
                getgenv().RAIN_PATCHED = getgenv().RAIN_PATCHED or {}
                getgenv().RAIN_PATCHED[rel] = (getgenv().RAIN_PATCHED[rel] or 0) + 1
            else
                warn("[restore] patch anchor missing in " .. rel .. " :: " .. r.line)
            end
        else
            local pat = r[1]:gsub("(%W)", "%%%1")
            local joined = table.concat(lines, "\n")
            if joined:find(pat) then
                if r[3] == "all" then
                    joined = joined:gsub(pat, r[2])
                else
                    joined = joined:gsub(pat, r[2], 1)
                end
                lines = {}
                for ln in (joined .. "\n"):gmatch("(.-)\n") do
                    local clean = ln:gsub("\r$", "")
                    table.insert(lines, clean)
                end
                getgenv().RAIN_PATCHED = getgenv().RAIN_PATCHED or {}
                getgenv().RAIN_PATCHED[rel] = (getgenv().RAIN_PATCHED[rel] or 0) + 1
            else
                warn("[restore] patch anchor missing in " .. rel)
            end
        end
    end
    return table.concat(lines, "\n")
end

local function __resolve(path)
    if STUBS[path] then return STUBS[path]() end
    local rel = path:gsub("^@src/", "src/"):gsub("^@assets/", "assets/")
    local candidates = { rel .. ".lua", rel, rel .. ".json" }
    local last_err = nil
    for _, c in ipairs(candidates) do
        local ok, src = pcall(__fetch, BASE_URL .. c)
        if ok and type(src) == "string" and #src > 0 then
            src = apply_patches(c, src)
            local chunk, err = loadstring(src, "=" .. c)
            if chunk then return chunk() end
            if c:sub(-4) ~= ".lua" then return src end -- data (json/text), not code
            last_err = err
        end
    end
    error("rain_loader: cannot load " .. path .. " (" .. tostring(last_err) .. ")")
end

local __real_require = require
function require(path) -- shadows builtin for subsequently loaded chunks (same globals)
    if type(path) ~= "string" or path:sub(1, 1) ~= "@" then
        return __real_require(path)
    end
    if __cache[path] == nil then
        -- retry with backoff: raw.githubusercontent rate-limits burst fetches
        local a, b, c, d, e, f, g, h
        for attempt = 1, 4 do
            a, b, c, d, e, f, g, h = pcall(__resolve, path)
            if a then break end
            task.wait(1 + attempt)
        end
        if a then
            __cache[path] = { ok = a, b, c, d, e, f, g, h }
        end
        -- failures are NOT cached: a later retry may succeed
    end
    local r = __cache[path]
    if not r then
        local a, b, c, d, e, f, g, h = pcall(__resolve, path)
        if not a then error(b) end
        return b, c, d, e, f, g, h
    end
    if not r.ok then error(r[1]) end
    return r[1], r[2], r[3], r[4], r[5], r[6], r[7]
end

function builder_require(m) return require(m) end
function base_require(m) return require(m) end

-- manifests (was: list_modules builder glob)
local TABS = {
    auto = "@src/ui/tabs/auto",
    combat = "@src/ui/tabs/combat",
    main = "@src/ui/tabs/main",
    ui = "@src/ui/tabs/ui",
    visuals = "@src/ui/tabs/visuals",
}
local TASKS = {
    auto_authority = "@src/automation/persistent_tasks/auto_authority",
    auto_deepdrill = "@src/automation/persistent_tasks/auto_deepdrill",
    auto_duke = "@src/automation/persistent_tasks/auto_duke",
    auto_echo_layer2 = "@src/automation/persistent_tasks/auto_echo_layer2",
    auto_escape_depths = "@src/automation/persistent_tasks/auto_escape_depths",
    auto_ferryman = "@src/automation/persistent_tasks/auto_ferryman",
    auto_layer2 = "@src/automation/persistent_tasks/auto_layer2",
    auto_mooneyrie = "@src/automation/persistent_tasks/auto_mooneyrie",
    auto_progress = "@src/automation/persistent_tasks/auto_progress",
    auto_saramed = "@src/automation/persistent_tasks/auto_saramed",
    auto_voi = "@src/automation/persistent_tasks/auto_voi",
    jetstriker_echofarm = "@src/automation/persistent_tasks/jetstriker_echofarm",
    ministry_notefarm = "@src/automation/persistent_tasks/ministry_notefarm",
    soup_echofarm = "@src/automation/persistent_tasks/soup_echofarm",
    titus_echofarm = "@src/automation/persistent_tasks/titus_echofarm",
    titus_relicfarm = "@src/automation/persistent_tasks/titus_relicfarm",
}
local FALLBACKS = {
    prediction = "@src/features/auto-parry/fallbacks/objects/prediction",
    unbidden = "@src/features/auto-parry/fallbacks/objects/unbidden",
    vent = "@src/features/auto-parry/fallbacks/objects/vent",
}
local FEATS = {
    ["auto-builder/auto_builder"] = "@src/features/auto-builder/auto_builder",
    ["auto-fight/auto-fight"] = "@src/features/auto-fight/auto-fight",
    ["auto-loot/auto-loot"] = "@src/features/auto-loot/auto-loot",
    ["auto-parry/auto-parry"] = "@src/features/auto-parry/auto-parry",
    ["auto-parry/block-input-manager"] = "@src/features/auto-parry/block-input-manager",
    ["auto-parry/defend-action-manager"] = "@src/features/auto-parry/defend-action-manager",
    ["auto-parry/hitbox_simulator"] = "@src/features/auto-parry/hitbox_simulator",
    ["automation/auto_brutus"] = "@src/features/automation/auto_brutus",
    ["automation/auto_chime_requeue"] = "@src/features/automation/auto_chime_requeue",
    ["automation/auto_decline_guild_invites"] = "@src/features/automation/auto_decline_guild_invites",
    ["automation/auto_decline_squad_invites"] = "@src/features/automation/auto_decline_squad_invites",
    ["automation/auto_equip_weapon"] = "@src/features/automation/auto_equip_weapon",
    ["automation/auto_fish"] = "@src/features/automation/auto_fish",
    ["automation/auto_flow_state"] = "@src/features/automation/auto_flow_state",
    ["automation/auto_ragdoll_cancel"] = "@src/features/automation/auto_ragdoll_cancel",
    ["automation/auto_roll_cancel"] = "@src/features/automation/auto_roll_cancel",
    ["automation/auto_sprint"] = "@src/features/automation/auto_sprint",
    ["automation/auto_train_agility"] = "@src/features/automation/auto_train_agility",
    ["automation/auto_uppercut"] = "@src/features/automation/auto_uppercut",
    ["automation/auto_wisp"] = "@src/features/automation/auto_wisp",
    ["automation/backstab_movestacker"] = "@src/features/automation/backstab_movestacker",
    ["automation/charisma_farm"] = "@src/features/automation/charisma_farm",
    ["automation/intelligence_farm"] = "@src/features/automation/intelligence_farm",
    ["buttons/teleports/depths"] = "@src/features/buttons/teleports/depths",
    ["buttons/teleports/eastern"] = "@src/features/buttons/teleports/eastern",
    ["buttons/teleports/etrean"] = "@src/features/buttons/teleports/etrean",
    ["buttons/teleports/trial"] = "@src/features/buttons/teleports/trial",
    ["buttons/auto_trial"] = "@src/features/buttons/auto_trial",
    ["buttons/damage_self"] = "@src/features/buttons/damage_self",
    ["buttons/generic_teleport"] = "@src/features/buttons/generic_teleport",
    ["buttons/knock_self"] = "@src/features/buttons/knock_self",
    ["buttons/respawn"] = "@src/features/buttons/respawn",
    ["buttons/suicide"] = "@src/features/buttons/suicide",
    ["buttons/tp_to_floor"] = "@src/features/buttons/tp_to_floor",
    ["buttons/tp_to_guildbase"] = "@src/features/buttons/tp_to_guildbase",
    ["buttons/tp_to_objectives"] = "@src/features/buttons/tp_to_objectives",
    ["buttons/tp_to_roof"] = "@src/features/buttons/tp_to_roof",
    ["buttons/tp_to_void"] = "@src/features/buttons/tp_to_void",
    ["combat/anim_speed_changer"] = "@src/features/combat/anim_speed_changer",
    ["combat/attach_to_back"] = "@src/features/combat/attach_to_back",
    ["combat/auto_air_counter"] = "@src/features/combat/auto_air_counter",
    ["combat/auto_ardour"] = "@src/features/combat/auto_ardour",
    ["combat/auto_dustlunge"] = "@src/features/combat/auto_dustlunge",
    ["combat/auto_golden_tongue"] = "@src/features/combat/auto_golden_tongue",
    ["combat/auto_reinforce"] = "@src/features/combat/auto_reinforce",
    ["combat/easy_feint"] = "@src/features/combat/easy_feint",
    ["combat/easy_roll_cancel"] = "@src/features/combat/easy_roll_cancel",
    ["combat/fast_swing"] = "@src/features/combat/fast_swing",
    ["combat/m1_hold"] = "@src/features/combat/m1_hold",
    ["combat/mantra_rolling"] = "@src/features/combat/mantra_rolling",
    ["combat/mantra_slidecasting"] = "@src/features/combat/mantra_slidecasting",
    ["combat/safe_input"] = "@src/features/combat/safe_input",
    ["combat/silent_aim"] = "@src/features/combat/silent_aim",
    ["combat/stored_damage_tracker"] = "@src/features/combat/stored_damage_tracker",
    ["combat/vehicle_noclip"] = "@src/features/combat/vehicle_noclip",
    ["combat/vehicle_speed"] = "@src/features/combat/vehicle_speed",
    ["exploits/ap_breaker"] = "@src/features/exploits/ap_breaker",
    ["exploits/boat_teleport"] = "@src/features/exploits/boat_teleport",
    ["exploits/kamui_teleport"] = "@src/features/exploits/kamui_teleport",
    ["exploits/mob_ai_breaker"] = "@src/features/exploits/mob_ai_breaker",
    ["exploits/no_anims"] = "@src/features/exploits/no_anims",
    ["exploits/raknet_fakelag"] = "@src/features/exploits/raknet_fakelag",
    ["exploits/voi_teleport"] = "@src/features/exploits/voi_teleport",
    ["misc/anchor"] = "@src/features/misc/anchor",
    ["misc/apply_fflags"] = "@src/features/misc/apply_fflags",
    ["misc/build_stealer"] = "@src/features/misc/build_stealer",
    ["misc/hair_id_stealer"] = "@src/features/misc/hair_id_stealer",
    ["misc/linoria_watermark"] = "@src/features/misc/linoria_watermark",
    ["misc/opiumware_fix"] = "@src/features/misc/opiumware_fix",
    ["misc/override_deepwoken_cursor"] = "@src/features/misc/override_deepwoken_cursor",
    ["misc/override_roblox_reset"] = "@src/features/misc/override_roblox_reset",
    ["misc/proximity_list"] = "@src/features/misc/proximity_list",
    ["misc/streamer_mode"] = "@src/features/misc/streamer_mode",
    ["misc/talent_highlighter"] = "@src/features/misc/talent_highlighter",
    ["movement/fly"] = "@src/features/movement/fly",
    ["movement/infinite_jump"] = "@src/features/movement/infinite_jump",
    ["movement/knocked_ownership"] = "@src/features/movement/knocked_ownership",
    ["movement/multiply_s"] = "@src/features/movement/multiply_s",
    ["movement/noclip"] = "@src/features/movement/noclip",
    ["movement/speed"] = "@src/features/movement/speed",
    ["movement/tick_rate"] = "@src/features/movement/tick_rate",
    ["qol/aggressive_optimize_game"] = "@src/features/qol/aggressive_optimize_game",
    ["qol/brayden"] = "@src/features/qol/brayden",
    ["qol/bring_mobs"] = "@src/features/qol/bring_mobs",
    ["qol/combosser_detector"] = "@src/features/qol/combosser_detector",
    ["qol/experimental_bug_fixes"] = "@src/features/qol/experimental_bug_fixes",
    ["qol/extend_prompts"] = "@src/features/qol/extend_prompts",
    ["qol/fake_void"] = "@src/features/qol/fake_void",
    ["qol/fall_multiplier"] = "@src/features/qol/fall_multiplier",
    ["qol/fast_mode"] = "@src/features/qol/fast_mode",
    ["qol/fps_booster"] = "@src/features/qol/fps_booster",
    ["qol/girl_detector"] = "@src/features/qol/girl_detector",
    ["qol/give_animation_gamepass"] = "@src/features/qol/give_animation_gamepass",
    ["qol/jesus"] = "@src/features/qol/jesus",
    ["qol/minesweeper"] = "@src/features/qol/minesweeper",
    ["qol/optimize_game"] = "@src/features/qol/optimize_game",
    ["qol/parry_sounds"] = "@src/features/qol/parry_sounds",
    ["qol/restore_old_weapon_behavior"] = "@src/features/qol/restore_old_weapon_behavior",
    ["qol/snake_game"] = "@src/features/qol/snake_game",
    ["qol/tetris"] = "@src/features/qol/tetris",
    ["qol/void_mobs"] = "@src/features/qol/void_mobs",
    ["removals/mantra_revealer/mantra_revealer"] = "@src/features/removals/mantra_revealer/mantra_revealer",
    ["removals/anti_afk"] = "@src/features/removals/anti_afk",
    ["removals/harrow_remover"] = "@src/features/removals/harrow_remover",
    ["removals/no_blind"] = "@src/features/removals/no_blind",
    ["removals/no_blur"] = "@src/features/removals/no_blur",
    ["removals/no_clouds"] = "@src/features/removals/no_clouds",
    ["removals/no_cl_gate"] = "@src/features/removals/no_cl_gate",
    ["removals/no_depths_trial_voices"] = "@src/features/removals/no_depths_trial_voices",
    ["removals/no_echo_screen"] = "@src/features/removals/no_echo_screen",
    ["removals/no_fall"] = "@src/features/removals/no_fall",
    ["removals/no_fire"] = "@src/features/removals/no_fire",
    ["removals/no_flame_blind"] = "@src/features/removals/no_flame_blind",
    ["removals/no_fog"] = "@src/features/removals/no_fog",
    ["removals/no_hive_gate"] = "@src/features/removals/no_hive_gate",
    ["removals/no_kill_bricks"] = "@src/features/removals/no_kill_bricks",
    ["removals/no_mob_encounters"] = "@src/features/removals/no_mob_encounters",
    ["removals/no_one_bit"] = "@src/features/removals/no_one_bit",
    ["removals/no_roll_fatigue"] = "@src/features/removals/no_roll_fatigue",
    ["removals/no_sanity_vfx"] = "@src/features/removals/no_sanity_vfx",
    ["removals/no_sea"] = "@src/features/removals/no_sea",
    ["removals/no_speed_debuff"] = "@src/features/removals/no_speed_debuff",
    ["removals/no_status_effects"] = "@src/features/removals/no_status_effects",
    ["removals/no_stun"] = "@src/features/removals/no_stun",
    ["removals/no_wind"] = "@src/features/removals/no_wind",
    ["removals/no_yun_shul_gate"] = "@src/features/removals/no_yun_shul_gate",
    ["removals/roll2_revealer"] = "@src/features/removals/roll2_revealer",
    ["spoofing/agility_spoof"] = "@src/features/spoofing/agility_spoofer",
    ["spoofing/endurance_runner_spoof"] = "@src/features/spoofing/endurance_runner_spoof",
    ["spoofing/freestylers_band_spoof"] = "@src/features/spoofing/freestylers_band_spoof",
    ["spoofing/kongas_spoof"] = "@src/features/spoofing/kongas_spoof",
    ["spoofing/lightweight_spoof"] = "@src/features/spoofing/lightweight_spoof",
    ["spoofing/momentum_spoof"] = "@src/features/spoofing/momentum_spoof",
    ["visuals/auto_hide_hud"] = "@src/features/visuals/auto_hide_hud",
    ["visuals/base_esp"] = "@src/features/visuals/base_esp",
    ["visuals/chain_counter"] = "@src/features/visuals/chain_counter",
    ["visuals/free_cam"] = "@src/features/visuals/free_cam",
    ["visuals/full_bright"] = "@src/features/visuals/full_bright",
    ["visuals/inf_zoom"] = "@src/features/visuals/inf_zoom",
    ["visuals/leaderboard_spectate"] = "@src/features/visuals/leaderboard_spectate",
    ["visuals/no_shadows"] = "@src/features/visuals/no_shadows",
    ["visuals/player_esp"] = "@src/features/visuals/player_esp",
    ["visuals/race_morph_menu"] = "@src/features/visuals/race_morph_menu",
    ["visuals/sanity_indicator"] = "@src/features/visuals/sanity_indicator",
    ["visuals/show_all_on_map"] = "@src/features/visuals/show_all_on_map",
    ["visuals/show_chat"] = "@src/features/visuals/show_chat",
    ["visuals/stream_proof_esp"] = "@src/features/visuals/stream_proof_esp",
    ["visuals/zoom"] = "@src/features/visuals/zoom",
}

function list_modules(pattern)
    if pattern == "ui/tabs/*" then return TABS end
    if pattern == "automation/persistent_tasks/*" then return TASKS end
    if pattern == "features/auto-parry/fallbacks/objects/*" then return FALLBACKS end
    warn("rain_loader: unknown list_modules pattern " .. tostring(pattern))
    return {}
end

-- asset pipeline over HTTP (build-time base64+zstd replaced by raw + decode w/ passthrough)
function inline_asset_b96(path)
    local rel = path:gsub("^@assets/", "assets/")
    return game:HttpGet(BASE_URL .. rel)
end
function decode_asset(s)
    local ok, res = pcall(function()
        local enc = game:GetService("EncodingService")
        local raw = enc:Base64Decode(buffer.fromstring(s))
        return buffer.tostring(enc:DecompressBuffer(raw, Enum.CompressionAlgorithm.Zstd))
    end)
    if ok and type(res) == "string" then return res end
    return s
end

-- ==================== framework globals (were build-provided) ====================
LPH_OBFUSCATED = false
function LPH_NO_VIRTUALIZE(f) return f end
function LPH_JIT(f) return f end
function LPH_JIT_MAX(f) return f end
function LPH_ENCSTR(f) return f end
function LPH_NO_UPVALUES(f) return f end
function STR_TBL_SF_INVOKE(s) return s end
LRM_ScriptName = "Project Rain"
script_key = nil

services = services or setmetatable({}, {
    __index = function(self, index)
        local s = game:GetService(index)
        rawset(self, index, s)
        return s
    end,
})
-- (builder_require defined once near the require shim above)

is_eastern = game.PlaceId == 6473861193
is_depths = game.PlaceId == 5735553160
is_etrean = game.PlaceId == 6032399813
is_chime = game.PlaceId == 6832944305
is_dungeon = game.PlaceId == 8668476218

-- game effect system (real one registers itself in Deepwoken; safe stub elsewhere)
-- every stub also answers unknown methods with a dummy, so half-loaded states degrade instead of erroring
local function dummyfn() return nil end
local function harden(t)
    return setmetatable(t or {}, { __index = function() return dummyfn end })
end
EffectReplicator = EffectReplicator or harden({
    FindEffect = function() return nil end,
    HasEffect = function() return false end,
    CreateEffect = function()
        return harden({ Debris = function() end, Remove = function() end })
    end,
})
Latency = Latency or harden({ force_lag = function() end, get_ping = function() return 0 end, half_ping = function() return 0 end })
KeyHandler = KeyHandler or harden({ get_key = function() return harden({ FireServer = function() end }) end })
general = general or harden({ in_air = function() return true end, is_teammate = function() return false end })
Tween = Tween or harden({ register_lagback = function() end })

-- ==================== boot (adapted init.lua) ====================
-- NOTE: intentionally global (init.lua did `env = getgenv()`); chunks use bare `env`
env = getgenv()

local function brequire(path) -- pcall require with warn, returns nil on failure
    local ok, res = pcall(require, path)
    if not ok then
        warn("[restore] require failed: " .. path .. " :: " .. tostring(res))
        getgenv().RAIN_BOOTLOG = getgenv().RAIN_BOOTLOG or {}
        if #getgenv().RAIN_BOOTLOG < 40 then
            table.insert(getgenv().RAIN_BOOTLOG, path .. " :: " .. tostring(res):sub(1, 220))
        end
        return nil
    end
    return res
end
getgenv().RAIN_BOOTLOG = getgenv().RAIN_BOOTLOG or {}
getgenv().RAIN_BOOTLOG_OUT = function()
    for _, line in ipairs(getgenv().RAIN_BOOTLOG) do
        print("[bootlog] " .. line)
    end
    print("[bootlog] total: " .. #getgenv().RAIN_BOOTLOG)
end

xpcall(function()
    for _, d in ipairs({ "Project Rain", "Project Rain/Assets", "Project Rain/Fonts", "Project Rain/Deepwoken-Config", "Project Rain/Deepwoken-Config/Preferences" }) do
        if not isfolder(d) then makefolder(d) end
    end
    if not isfile("Project Rain/script_state") then
        writefile("Project Rain/script_state", game:GetService("HttpService"):JSONEncode({
            last_executed = tick(), build_id = game:GetService("HttpService"):GenerateGUID(false),
        }))
    end
end, warn)

if env.aztup then
    xpcall(function() env.aztup:detach() end, warn)
    env.aztup = nil
end

env.aztup = {
    detach = function(self)
        if self.maid and self.maid.do_cleaning then pcall(function() self.maid:do_cleaning() end) end
        if self.features then
            for _, feature in pairs(self.features) do
                if type(feature) == "table" and feature._c then
                    pcall(function() feature._c:Disconnect() end)
                    feature._c = nil
                end
                xpcall(function()
                    if type(feature) == "table" and feature.disable then feature:disable() end
                end, warn)
            end
        end
        if self.ui then xpcall(function() self.ui:Unload() end, warn) end
    end,
    features = {}, flags = {}, farms = {}, tabs = {},
}
local aztup = env.aztup

-- fonts: try real Lexend files, fall back to Gotham (UI keeps working).
-- NOTE: TTFs downloaded via HttpGet may arrive corrupted (text transfer);
-- for pixel-perfect Lexend, download the 3 .ttf from the repo in a BROWSER
-- into Project Rain/Fonts/ — existing files are never re-downloaded.
local lexend_ok = false
do
    local finished = false
    task.spawn(function()
        pcall(function()
            for _, f in ipairs({ { "Lexend.ttf", "Fonts/Lexend.ttf" }, { "Lexend-Bold.ttf", "Fonts/Lexend-Bold.ttf" }, { "Lexend-Medium.ttf", "Fonts/Lexend-Medium.ttf" } }) do
                if not isfile("Project Rain/" .. f[2]) then
                    writefile("Project Rain/" .. f[2], game:HttpGet(BASE_URL .. "assets/" .. f[1]))
                end
            end
            local f = require("@src/utility/custom_font")
            local params = Instance.new("GetTextBoundsParams")
            params.Text = "x"
            params.Font = f.regular
            params.Size = 16
            game:GetService("TextService"):GetTextBoundsAsync(params)
            params:Destroy()
            lexend = f
            lexend_ok = true
        end)
        finished = true
    end)
    local t0 = tick()
    while not finished and tick() - t0 < 15 do task.wait(0.25) end
end
if not lexend_ok then
    local g = Font.fromEnum(Enum.Font.Gotham)
    lexend = { regular = g, medium = g, bold = g }
    warn("[restore] Lexend fonts unavailable, using Gotham fallback")
end

local hasnt_accepted_tos = not isfile("Project Rain/tos_accepted_82126_0822UTC0.txt")
env.persistent_data = brequire("@src/utility/persistent_data")
env.Logger = brequire("@src/utility/logger")
aztup.automation = brequire("@src/automation/loader")
env.fflags = brequire("@src/utility/fflags")
if not (env.persistent_data and env.Logger and aztup.automation and env.fflags) then
    return warn("[restore] core modules failed, aborting")
end
local fflags = env.fflags

if game.PlaceId == 4111023553 then
    task.spawn(xpcall, function() brequire("@src/main_menu/loader") end, warn)
    return true
end

env.signal = brequire("@src/utility/signal")
loaded_signal = env.signal and env.signal.new()
env.LOAD_START_TIME = tick()
aztup.silent_mode = isfile("Project Rain/silent_mode_toggle")
do
    local maidlib = brequire("@src/utility/maid")
    aztup.maid = maidlib and maidlib.new() or nil
end
if not aztup.ui then
    aztup.ui = brequire("@src/utility/librarys/ui")
end
env.server_utility = brequire("@src/utility/deepwoken/servers")
env.local_player = brequire("@src/utility/player-data")
if not env.local_player then -- fallback tracker (no action_tracker dep)
    local lp = services.Players.LocalPlayer
    env.local_player = { instance = lp, character = nil, humanoid = nil, root_part = nil }
    local function bind(c)
        env.local_player.character = c
        env.local_player.humanoid = c:FindFirstChildOfClass("Humanoid")
        env.local_player.root_part = c:FindFirstChild("HumanoidRootPart")
        c.DescendantAdded:Connect(function(d)
            if d.Name == "HumanoidRootPart" then env.local_player.root_part = d
            elseif d:IsA("Humanoid") then env.local_player.humanoid = d end
        end)
    end
    lp.CharacterAdded:Connect(bind)
    if lp.Character then bind(lp.Character) end
end
local local_player = env.local_player
env.general = brequire("@src/utility/deepwoken/general_utilitys") or general
env.InstanceWatcher = brequire("@src/utility/instancewatcher")
env.BindableFunction = brequire("@src/utility/bindablefunction")
env.Markers = nil
do
    local mlib = brequire("@src/utility/markers")
    if mlib then
        local ok, inst = pcall(mlib.new)
        if ok then env.Markers = inst end
    end
end
env.MarkedInstanceCreator = brequire("@src/utility/markedinstancecreator")
env.StateMachine = brequire("@src/utility/statemachine")
env.Tween = brequire("@src/utility/deepwoken/safe_tween") or Tween
env.EffectReplicatorHandler = brequire("@src/utility/deepwoken/effect_replicator_handler")
env.LoopUtil = brequire("@src/utility/loop")
env.scheduler = brequire("@src/utility/scheduler")
env.TargetFilter = brequire("@src/features/auto-parry/util/target-filter")
env.ab_builder = brequire("@src/features/auto-builder/auto_builder")

-- hooking (anticheat bypass + KeyHandler). Original kicked on failure;
-- restore warns and continues WITHOUT kick so the hub stays usable.
-- hooking core transplanted from Ap_central bundle (fixed hooks, all passthrough).
-- Upload pr/restore/rain_hooks_new.lua to the repo under restore/ (next to src/).
-- Set getgenv().RAIN_NOHOOKS = true BEFORE executing to skip hooking entirely.
task.spawn(function()
    if getgenv().RAIN_NOHOOKS then
        warn("[restore] hooking skipped (RAIN_NOHOOKS)")
        return
    end
    local ok, mod = pcall(function()
        local src = game:HttpGet(BASE_URL .. "restore/rain_hooks_new.lua")
        local fn = assert(loadstring(src, "=rain_hooks_new"))
        return fn()
    end)
    if not ok then
        warn("[restore] new hooking load failed, continuing without it :: " .. tostring(mod))
        return
    end
    getgenv().RAIN_HOOKS = mod
    local ok2, err = pcall(function()
        mod.earlyInit()
        mod.init()
    end)
    if not ok2 then
        warn("[restore] hooking init failed :: " .. tostring(err))
        return
    end
    warn("[restore] new hooks online")
    -- probe: a broken __newindex hook bricks ALL property sets (incl. movement).
    task.wait(2)
    local probe_ok = pcall(function()
        local p = Instance.new("Part")
        p.Name = "restore_probe"
        p:Destroy()
    end)
    if not probe_ok then
        warn("[restore] metamethod hooks look broken, reverting __newindex")
        pcall(function()
            if typeof(getrawmetatable) == "function" and typeof(isfunctionhooked) == "function" and typeof(restorefunction) == "function" then
                local mt = getrawmetatable(game)
                if mt and isfunctionhooked(mt.__newindex) then
                    restorefunction(mt.__newindex)
                end
            end
        end)
    else
        warn("[restore] hooks probe OK")
    end
end)

-- user_service stub (key system lives server-side in the original)
do
    local us = brequire("@src/security/user_service")
    getgenv().user_service = us
end

if hasnt_accepted_tos then
    xpcall(function() brequire("@src/ui/tos") end, warn)
    task.wait(1.5)
end

-- Feature class (generic_feature) must exist before any feature file loads
Feature = brequire("@src/features/generic_feature")
if not Feature then
    return warn("[restore] generic_feature failed, aborting")
end

-- features/loader: real implementation now lives in source (was stripped).
do
    local fl = brequire("@src/features/loader")
    if fl and fl.initialize then
        xpcall(function() fl.initialize(FEATS) end, warn)
    else
        warn("[restore] features/loader failed")
    end
end

-- escape hatch: releases ToS input capture without accepting.
-- run getgenv().RAIN_FOCUS_FIX() if WASD does nothing while ToS is open.
getgenv().RAIN_FOCUS_FIX = function()
    pcall(function() game:GetService("RunService"):SetRobloxGuiFocused(false) end)
    print("[restore] input focus released")
end

-- on-demand keyhandler/remote diagnostics
getgenv().RAIN_KHDIAG = function()
    local kh = getgenv().KeyHandler
    print("KeyHandler present:", kh ~= nil)
    if not kh then return end
    for _, n in ipairs({ "LeftClick", "CriticalClick", "FeintClick", "OffhandAttack", "Block" }) do
        local ok, r = pcall(function() return kh:get_key(n) end)
        if ok then
            print(n, "=>", (r ~= nil) and (tostring(r.Name or r)) or "nil")
        else
            print(n, "=> ERR", tostring(r))
        end
    end
end

-- on-demand effect/proximity diagnostics
getgenv().RAIN_FXDIAG = function()
    local er = getgenv().EffectReplicator
    print("EffectReplicator type:", type(er), tostring(er):sub(1, 60))
    if type(er) == "table" then
        for _, n in ipairs({ "Equipped", "ParryCool", "Blocking", "NoFall" }) do
            local ok, f = pcall(function() return er:FindEffect(n) end)
            print("FindEffect " .. n .. ":", ok, tostring(f):sub(1, 80))
        end
        local keys, n = {}, 0
        for k, v in pairs(er) do
            n += 1
            if n <= 30 then
                table.insert(keys, tostring(k) .. "=" .. type(v))
            end
        end
        print("module keys (" .. n .. "):", table.concat(keys, ", "))
    end
end
getgenv().RAIN_PROXDIAG = function()
    print("show_list flag:", tostring(aztup.flags.show_list))
    print("range flag:", tostring(aztup.flags.player_proximity_range))
    local lp = env.local_player
    print("root_part:", tostring(lp and lp.root_part))
    local n, d0 = 0, nil
    if lp and lp.root_part then
        for _, p in ipairs(services.Players:GetPlayers()) do
            if p ~= lp.instance and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    n += 1
                    local d = (lp.root_part.Position - hrp.Position).Magnitude
                    if not d0 or d < d0 then d0 = d end
                end
            end
        end
    end
    print("players w/ HRP:", n, "nearest:", tostring(d0))
end

-- on-demand parry pipeline diagnostics
getgenv().RAIN_PARRY = function()
    print("auto_parry flag:", tostring(aztup.flags.auto_parry))
    local D = nil
    for _, f in pairs(aztup.features) do
        if type(f) == "table" and type(f.queue_generic_parry_task) == "function" then
            D = f
            break
        end
    end
    print("defend-action-manager loaded:", D ~= nil)
    if D then
        print("queued actions:", tostring(D.actions_to_play_through and #D.actions_to_play_through or "?"))
        local lq = getgenv().RAIN_LASTQ
        print("last queued:", lq and (tostring(lq.type) .. " " .. string.format("%.1fs ago", tick() - (lq.t or 0))) or "never")
    end
    local lp = env.local_player
    print("tracker present:", lp and lp.tracker ~= nil)
    if lp and lp.tracker then
        local er = getgenv().EffectReplicator
        for i = 1, 4 do
            local ok, r = pcall(function() return lp.tracker:can_parry() end)
            local oe, fe = pcall(function() return er:FindEffect("Equipped") end)
            local op, fp = pcall(function() return er:FindEffect("ParryCool") end)
            print(string.format("try%d can_parry=%s equipped=%s parrycool=%s",
                i, tostring(ok and r),
                tostring(oe and fe and tostring(fe):sub(1, 40)),
                tostring(op and fp and tostring(fp):sub(1, 40))))
        end
        local ok2, r2 = pcall(function() return lp.tracker:can_dodge() end)
        print("can_dodge():", ok2, tostring(r2))
    end
    local kh = getgenv().KeyHandler
    if kh then
        for _, n in ipairs({ "Block", "Unblock", "CriticalClick", "LeftClick" }) do
            local ok, r = pcall(function() return kh:get_key(n) end)
            local where = "nil"
            if ok and r then
                where = tostring(r:GetFullName())
            end
            print("remote " .. n .. ":", ok and where or ("ERR " .. tostring(r)))
        end
    else
        print("KeyHandler: MISSING")
    end
end

-- manual spectate bypass (leaderboard frame wiring is fragile across updates):
-- RAIN_SPEC("name") watches, RAIN_SPEC() resets to self
getgenv().RAIN_SPEC = function(name)
    local cam = workspace.CurrentCamera
    local lp = env.local_player
    if not name or name == "" then
        if lp and lp.humanoid and cam then cam.CameraSubject = lp.humanoid end
        print("[spec] reset to self")
        return
    end
    local q = tostring(name):lower()
    for _, p in ipairs(services.Players:GetPlayers()) do
        local cn = ""
        pcall(function() cn = tostring(p:GetAttribute("CharacterName") or "") end)
        if p.Name:lower():find(q, 1, true) or cn:lower():find(q, 1, true) then
            local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            if h and cam then
                cam.CameraSubject = h
                print("[spec] watching " .. p.Name)
                return
            end
        end
    end
    print("[spec] not found: " .. tostring(name))
end

-- env-scope probe: does tracker's code see getgenv() writes made AFTER its load?
-- If can_parry ignores this proxy, chunks run in isolated envs and every
-- late-bound global must be routed via getgenv() explicitly.
getgenv().RAIN_ENVTEST = function()
    local er = getgenv().EffectReplicator
    if type(er) ~= "table" then
        print("[envtest] no EffectReplicator table")
        return
    end
    local seen = {}
    local proxy = setmetatable({}, { __index = function(_, k)
        local v = er[k]
        if (k == "FindEffect" or k == "HasEffect" or k == "HasAny") and type(v) == "function" then
            return function(_, ...)
                seen[#seen + 1] = tostring(k)
                return v(er, ...)
            end
        end
        return v
    end })
    getgenv().EffectReplicator = proxy
    local lp = getgenv().local_player
    local ok, r = pcall(function() return lp and lp.tracker and lp.tracker:can_parry() end)
    getgenv().EffectReplicator = er
    print("can_parry:", ok, tostring(r))
    print("proxy seen:", (#seen > 0) and table.concat(seen, ",") or "(nothing - isolated env!)")
end

-- spy on EffectReplicator.FindEffect: proves whether tracker sees the same table.
-- RAIN_FXSPY() installs, second call removes. Then fight / run RAIN_PARRY.
getgenv().RAIN_FXSPY = function()
    local er = getgenv().EffectReplicator
    if not er or getgenv().RAIN_FXSPY_ON then
        if er and er.__rain_orig_find then
            er.FindEffect = er.__rain_orig_find
            er.__rain_orig_find = nil
        end
        getgenv().RAIN_FXSPY_ON = nil
        print("[fxspy] removed")
        return
    end
    local orig = er.FindEffect
    er.__rain_orig_find = orig
    er.FindEffect = function(self, name, ...)
        local r = orig(self, name, ...)
        if name == "Equipped" or name == "ParryCool" then
            print(string.format("[fxspy] FindEffect(%s) -> %s", tostring(name), tostring(r):sub(1, 70)))
        end
        return r
    end
    getgenv().RAIN_FXSPY_ON = true
    print("[fxspy] installed")
end

-- animation coverage dump: which enemy swings were seen and which lack data.
-- Fight mobs ~30s, then run RAIN_ANIMDUMP(). "MISS" = no timing data (unparryable
-- by design until data added); "HIT" + no parry = filters/execution, say so.
getgenv().RAIN_ANIMDUMP = function()
    local t = getgenv().RAIN_ANIMS
    if not t or not next(t) then
        print("[animdump] empty — handler saw no swings (auto_parry on? enemies near?)")
        return
    end
    local rows = {}
    for id, e in pairs(t) do
        local who = {}
        for w in pairs(e.who) do table.insert(who, w) end
        table.insert(rows, { n = e.n, line = string.format("%s x%d id=%s name=[%s] from=%s",
            e.has_data and "HIT " or "MISS", e.n, tostring(id), tostring(e.nm or "?"), table.concat(who, ",")) })
    end
    table.sort(rows, function(a, b) return a.n > b.n end)
    for i = 1, math.min(#rows, 30) do print("[animdump] " .. rows[i].line) end
    print(string.format("[animdump] %d distinct anims", #rows))
end
getgenv().RAIN_ANIMCLR = function() getgenv().RAIN_ANIMS = {} print("[animdump] cleared") end

-- on-demand keyhandler/remote diagnostics (parry execution depends on these)
getgenv().RAIN_KHDIAG = function()
    local kh = getgenv().KeyHandler
    print("KeyHandler present:", kh ~= nil)
    if not kh then return end
    for _, n in ipairs({ "LeftClick", "CriticalClick", "FeintClick", "OffhandAttack", "Block" }) do
        local ok, r = pcall(function() return kh:get_key(n) end)
        if ok then
            print(n, "=>", (r ~= nil) and tostring(r.Name or r) or "nil")
        else
            print(n, "=> ERR", tostring(r))
        end
    end
end

-- real game EffectReplicator (many features + parry internals need the live one,
-- not the boot stub). Resolves when the game replicates it.
task.spawn(function()
    for _ = 1, 60 do
        local ok, mod = pcall(function()
            local m = game:GetService("ReplicatedStorage"):FindFirstChild("EffectReplicator")
            if not m then return nil end
            return require(m)
        end)
        if ok and mod then
            -- fxspy proved chunks can hold a STALE global snapshot (tracker saw
            -- the boot stub while getgenv() already had the real module, so
            -- can_parry stayed false with a sword in hand). Upgrade in place:
            -- mutate the stub table so every stale reference delegates live.
            local old = getgenv().EffectReplicator
            getgenv().EffectReplicator = mod
            EffectReplicator = mod
            if type(old) == "table" and old ~= mod then
                pcall(function()
                    for k, v in pairs(mod) do old[k] = v end
                    setmetatable(old, { __index = mod })
                end)
            end
            warn("[restore] real EffectReplicator bound")
            break
        end
        task.wait(1)
    end
end)

-- on-demand diagnostics: run getgenv().RAIN_DIAG() in executor, paste output
getgenv().RAIN_DIAG = function()
    local L = {}
    table.insert(L, "place=" .. tostring(game.PlaceId))
    local fl = {}
    if aztup and aztup.flags then
        for k, v in pairs(aztup.flags) do
            if v == true then table.insert(fl, tostring(k)) end
        end
    end
    table.insert(L, "flags_true=[" .. table.concat(fl, ",") .. "]")
    local con = {}
    if aztup and aztup.features then
        for id, f in pairs(aztup.features) do
            if type(f) == "table" and f._c then
                table.insert(con, tostring(f.id or id))
            end
        end
    end
    table.insert(L, "connected=[" .. table.concat(con, ",") .. "]")
    local lp = env.local_player
    local ch = lp and lp.character
    local rp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if rp then
        table.insert(L, string.format("hrp anchored=%s asmvel=%s pos=%s",
            tostring(rp.Anchored), tostring(rp.AssemblyLinearVelocity), tostring(rp.Position)))
    else
        table.insert(L, "hrp=MISSING")
    end
    if hum then
        table.insert(L, string.format("hum hp=%s/%s state=%s ws=%s md=%s sit=%s ps=%s",
            tostring(hum.Health), tostring(hum.MaxHealth), tostring(hum:GetState()),
            tostring(hum.WalkSpeed), tostring(hum.MoveDirection),
            tostring(hum.Sit), tostring(hum.PlatformStand)))
    else
        table.insert(L, "hum=MISSING")
    end
    table.insert(L, "gravity=" .. tostring(workspace.Gravity))
    local patched = {}
    if getgenv().RAIN_PATCHED then
        for k, v in pairs(getgenv().RAIN_PATCHED) do
            table.insert(patched, k .. "x" .. tostring(v))
        end
    end
    table.insert(L, "patched=[" .. table.concat(patched, ",") .. "]")
    local out = table.concat(L, "\n")
    print(out)
    pcall(function() if setclipboard then setclipboard(out) end end)
    return out
end

if aztup.automation and aztup.automation.initialize then
    xpcall(function() aztup.automation:initialize() end, warn)
end
brequire("@src/features/auto-parry/block-input-manager")
task.spawn(pcall, function()
    brequire("@src/features/auto-parry/handlers/animator-handler")
end)
chance_store = brequire("@src/features/auto-parry/data/chance_store")
getgenv().chance_store = chance_store
do
    local uimod = brequire("@src/ui/ui")
    if uimod and uimod.initialize then
        xpcall(function() uimod.initialize() end, warn)
    else
        warn("[restore] ui module failed, aborting UI-dependent boot")
        return
    end
end
do
    local pe = brequire("@src/features/visuals/player_esp")
    if type(pe) == "function" then xpcall(pe, warn) end
end
do
    local be = brequire("@src/features/visuals/base_esp")
    if type(be) == "function" then xpcall(be, warn) end
end

shared = shared or {}
shared.unloaded = false
local Library = getgenv().Library
if Library and Library.OnUnload then
    Library:OnUnload(function()
        if shared.unloaded then return end
        shared.unloaded = true
        getgenv().RAIN_RESTORED_DEAD = true
        if getgenv().RAIN_HOOKS and getgenv().RAIN_HOOKS.detach then
            pcall(function() getgenv().RAIN_HOOKS.detach() end)
            getgenv().RAIN_HOOKS = nil
        end
        if env.aztup then
            if env.Markers then
                for _, marker in env.Markers:get() do pcall(function() marker:Destroy() end) end
                getgenv().Markers = nil
            end
            env.aztup:detach()
            -- inert stub, NOT nil: lingering loops (base_esp etc.) must no-op instead of erroring
            env.aztup = {
                flags = {}, features = {}, farms = {}, tabs = {},
                automation = { has_any = function() return false end, should_auto_start = function() return false end },
            }
        end
        Library.Unloaded = true
    end)
end

-- post-boot self test: validates the globals tasks depend on
task.delay(10, function()
    local function check(name, fn)
        local ok, res = pcall(fn)
        warn("[selftest] " .. name .. ": " .. (ok and ("OK " .. tostring(res):sub(1, 60)) or ("FAIL " .. tostring(res):sub(1, 160))))
    end
    check("Tween.new->wait", function()
        local t = getgenv().Tween
        assert(type(t) == "table", "Tween not a table")
        assert(type(t.new) == "function", "Tween.new missing")
        -- zero-distance target: waiter exits instantly, no motion
        local ch = game:GetService("Players").LocalPlayer.Character
        local rp = ch and ch:FindFirstChild("HumanoidRootPart")
        assert(rp, "no root_part")
        local tw = t.new(rp.CFrame, true, 170)
        assert(tw ~= nil, "Tween.new returned nil")
        assert(type(tw.wait) == "function", "result.wait missing")
        if tw.stop then pcall(tw.stop) end
        return "full chain OK"
    end)
    check("EffectReplicator", function()
        local er = getgenv().EffectReplicator
        assert(type(er) == "table", "not a table")
        return tostring(er:FindEffect("NoFall"))
    end)
    check("KeyHandler.Block", function()
        local kh = getgenv().KeyHandler
        assert(kh, "no KeyHandler")
        local r = kh:get_key("Block")
        return tostring(r and r:GetFullName() or "nil-remote")
    end)
    check("local_player", function()
        local lp = getgenv().local_player or (env and env.local_player)
        assert(lp and lp.character, "no character")
        return tostring(lp.root_part)
    end)
    check("scheduler", function()
        local s = env and env.scheduler
        assert(s, "no scheduler")
        return "present"
    end)
end)

if env.Logger then
    pcall(function() env.Logger.log("Rain restore loaded.") end)
end
if loaded_signal then
    pcall(function() loaded_signal:fire() end)
end
if aztup.automation and aztup.automation.start then
    xpcall(function() aztup.automation:start() end, warn)
end
if env.Logger and env.LOAD_START_TIME then
    pcall(function()
        env.Logger.log(string.format("Restore boot finished in %.2fs.", tick() - env.LOAD_START_TIME))
    end)
end
