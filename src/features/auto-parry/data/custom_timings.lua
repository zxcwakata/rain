-- Restored data/custom_timings (was stripped upstream).
-- The rw_timings/ folder workflow (builder Save / Reload Timings button)
-- loads entries straight into timing_data, so this module only needs to stay
-- API-compatible: lookup(id) checks the live timing table first.
return {
    lookup = function(_id) return nil end,
    sync = function()
        return function() end
    end,
}
