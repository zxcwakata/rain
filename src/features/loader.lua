-- Restored features/loader (was stripped upstream).
-- Lazy-loads feature files on first enable (boot stays side-effect free),
-- then supervises flags -> enable/update/disable.
-- Toggle flag ids map 1:1 to feature .id in most cases; exceptions below.
local FLAGMAP = {
    ["movement/tick_rate"] = "tickrate",
    ["misc/proximity_list"] = "show_list",
}

return { initialize = function(FEATS)
    FEATS = FEATS or {}
    -- background eager fill for cross-module refs (aztup.features.X),
    -- batched to dodge raw rate-limits
    task.spawn(function()
        local batch = 0
        for id, path in pairs(FEATS) do
            if aztup.features[id] == nil then
                task.spawn(function()
                    local ok, mod = pcall(require, path)
                    if ok and type(mod) == "table" then
                        aztup.features[id] = mod
                        if type(mod.id) == "string" then
                            aztup.features[mod.id] = mod
                        end
                    end
                end)
                batch += 1
                if batch % 8 == 0 then task.wait(0.3) end
            end
        end
    end)
    -- supervisor + physics wedge watchdog (tick_rate does Pause/Step/Run per frame)
    task.spawn(function()
        local last_watchdog = 0
        while true do
            task.wait(0.15)
            if getgenv().RAIN_RESTORED_DEAD then break end
            local now = tick()
            if now - last_watchdog > 1 then
                last_watchdog = now
                local paused_ok, paused = pcall(function() return services.RunService.Paused end)
                if paused_ok and paused then
                    pcall(function() services.RunService:Run() end)
                    warn("[restore] physics was left paused, resumed (tick_rate wedge?)")
                end
            end
            for id, path in pairs(FEATS) do
                local wantflag = FLAGMAP[id] or id:match("([^/]+)$")
                if aztup.flags[wantflag] == true then
                    local f = aztup.features[id]
                    if f == nil then
                        local ok, mod = pcall(require, path)
                        if not ok then
                            warn("[restore] feature load failed: " .. id .. " :: " .. tostring(mod))
                        elseif type(mod) == "table" then
                            f = mod
                            aztup.features[id] = mod
                            if type(mod.id) == "string" then
                                aztup.features[mod.id] = mod
                            end
                        end
                    end
                    if type(f) == "table" then
                        if type(f.update) == "function" and f.conn then
                            if not f._c then
                                warn("[restore] +connected " .. id)
                                pcall(function() f:enable() end)
                                local ok, c = pcall(function()
                                    return f.conn:Connect(function(...) pcall(f.update, ...) end)
                                end)
                                if ok then f._c = c end
                            end
                        elseif not f._on then
                            warn("[restore] +enabled " .. id)
                            f._on = true
                            pcall(function() f:enable() end)
                        end
                    end
                else
                    local f = aztup.features[id]
                    if type(f) == "table" and (f._c or f._on) then
                        warn("[restore] -disabled " .. id)
                        if f._c then pcall(function() f._c:Disconnect() end) f._c = nil end
                        f._on = nil
                        pcall(function() f:disable() end)
                    end
                end
            end
        end
    end)
end }
