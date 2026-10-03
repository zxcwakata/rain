local latency = {};

-- restore: resolve the stat lazily on every call. The old code cached it at
-- require time (often before Stats replicated) and then returned 0 forever,
-- which shifted every parry timing late by a full RTT.
local function get_ping_stat()
    local ok, stats = pcall(function() return services.Stats end)
    if not ok or not stats then return nil end
    local ok2, item = pcall(function()
        return stats.Network.ServerStatsItem["Data Ping"]
    end)
    if ok2 and item then return item end
    local ok3, found = pcall(function() return stats:FindFirstChild("Data Ping", true) end)
    if ok3 then return found end
    return nil
end

function latency:get_ping()
    local ok, item = pcall(get_ping_stat)
    if ok and item then
        local ok2, val = pcall(function()
            local old = getthreadidentity();
            setthreadidentity(8);
            local v = item:GetValue();
            setthreadidentity(old);
            return v
        end)
        if ok2 and type(val) == "number" then return val / 1000 end
    end
    return 0
end;

function latency:half_ping()
    return latency:get_ping() / 2
end;

-- restore: present so rebinding bare Latency to this module never breaks
-- callers of the old boot stub (fly lag-bypass, currently a no-op).
function latency:force_lag(_) end

return latency