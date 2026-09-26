local _, ns = ...
local Model = {}
ns.ProgressModel = Model

function Model.Number(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value)) and value == value and math.abs(value) < math.huge
end

function Model.Duration(seconds)
    if not Model.Number(seconds) or seconds < 0 then return "—" end
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then return "<1m" end
    if minutes < 60 then return minutes .. "m" end
    return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

function Model.NewSession(now)
    return { started = now, gained = 0, gains = 0 }
end

function Model.Observe(session, snapshot, now)
    local old = session.last
    if old then
        local delta
        if snapshot.level == old.level then delta = snapshot.current - old.current
        elseif snapshot.level == old.level + 1 then delta = old.maximum - old.current + snapshot.current end
        if delta and delta >= 0 then
            session.gained = session.gained + delta
            if delta > 0 then session.gains = session.gains + 1 end
        else
            -- Unknown skipped levels / backward snapshots cannot produce an honest rate.
            session.started, session.gained, session.gains = now, 0, 0
        end
        if snapshot.level ~= old.level then session.playedBase, session.playedAt = 0, now end
    end
    session.last = snapshot
end

function Model.Values(snapshot, session, now)
    local current, maximum = snapshot.current, snapshot.maximum
    local remaining = math.max(0, maximum - current)
    local values = {
        level = tostring(snapshot.level or ""), nextLevel = tostring((snapshot.level or 0) + 1),
        current = tostring(math.floor(current)), max = tostring(math.floor(maximum)),
        remaining = tostring(math.floor(remaining)), percent = string.format("%.1f", maximum > 0 and current / maximum * 100 or 100),
        rested = tostring(math.floor(snapshot.rested or 0)),
        faction = snapshot.name or "", standing = snapshot.standing or "", status = snapshot.status or "",
        rate = "—", eta = "—", levelTime = "—", sessionXP = "0",
    }
    if session then
        local elapsed = math.max(0, now - session.started)
        values.sessionXP = tostring(math.floor(session.gained))
        if elapsed >= 60 and session.gains >= 3 and session.gained > 0 then
            local rate = session.gained / elapsed
            values.rate = tostring(math.floor(rate * 3600))
            if not snapshot.capped and not snapshot.disabled then values.eta = Model.Duration(remaining / rate) end
        end
        if session.playedBase then values.levelTime = Model.Duration(session.playedBase + now - session.playedAt) end
    end
    if snapshot.capped then values.eta, values.status = "—", "Maximum reached" end
    if snapshot.disabled then values.eta, values.status = "—", "XP disabled" end
    return values
end

function Model.Format(template, values)
    return (template:gsub("{([%a]+)}", function(key) return values[key] or ("{" .. key .. "}") end))
end
