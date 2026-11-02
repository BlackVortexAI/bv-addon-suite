local _,Routing=...
if not Routing.ready then return end
-- Routing's scheduler (Claude 2026-10-26, moved out of Grid.lua for the grid's removal; Florian approved the plan):
-- long work runs as a coroutine in slices of a few milliseconds per frame (S.Run), and gives the frame back where
-- it stands when its slice is used up (S.Breathe, S.Pace, S.SearchBreathe). Used by the navmesh planner (Hpa),
-- Navigate, Gather's route plans and the busy sign beside the pointer (UI/Busy.lua).
local S={}
Routing.Scheduler=S
-- Painting a space gives the frame back now and then (Florian 2026-10-14:
-- a generated Undercity of 1000 areas on 34 levels with 2-yard cells, the
-- first way on a level painted it in one piece): after about PAINTSTEP
-- cells, while it runs as a coroutine (S.Run), as the search does.
S.PAINTSTEP=4000
S.painted=0
-- With the game's clock by time (S.Breathe, every PAINTLOOK cells; Claude
-- 2026-10-20: rows of a large polygon cost far more than their cells).
S.PAINTLOOK=300
function S.Pace(cells)
    S.painted=S.painted+cells
    if S.sliceBegan and rawget(_G,"debugprofilestop") then
        if S.painted>=S.PAINTLOOK then S.painted=0;S.Breathe() end
    elseif S.painted>=S.PAINTSTEP then
        S.painted=0
        if coroutine.running() then coroutine.yield() end
    end
end
-- By time, where the work of a step varies (the plan's network search): yields
-- once the slice has run SLICE ms (Claude 2026-10-20: a step count let one
-- slice run 150-180 ms in game). Never inside a metamethod (Lua 5.1 cannot
-- yield there).
S.SLICE=6
function S.Breathe()
    local clock=S.sliceBegan and rawget(_G,"debugprofilestop")
    if clock and clock()-S.sliceBegan>=(S.sliceLimit or S.SLICE) and coroutine.running() then coroutine.yield() end
end
-- Extra search checkpoints are only for walks without a wall-time deadline.
-- More frames can exhaust the same deadline before the same cells are visited.
-- Preserve the old schedule for that exact coroutine, not unrelated work.
-- Navigate.Leg already marks its deadline-controlled coroutine in inner.
function S.SearchBreathe()
    if coroutine.running()~=S.inner then S.Breathe() end
end
-- Runs a function as a coroutine in slices (a few milliseconds per frame).
-- label: what runs, beside the mouse pointer meanwhile (Routing.Busy,
-- Florian 2026-10-14; else S.nextLabel, set just before the call); it goes
-- when the run ends or is cancelled.
S.BUDGET=8
-- Returns its handle: handle:Cancel() stops it. Not the ticker itself:
-- the game's tickers are read-only (Florian 2026-10-14: "Attempted to
-- assign to read-only key Cancel").
-- Where a coroutine stands (file:line, innermost first; Claude 2026-10-20: in
-- game one piece ran 211 ms that never did offline, the log says where).
function S.Where(c)
    if not c then return nil end
    -- The game has no debug.getinfo: its debugstack(thread, start, count1, count2).
    local stack=rawget(_G,"debugstack")
    if stack then
        local ok,text=pcall(stack,c,0,6,0)
        if not ok or type(text)~="string" then return nil end
        local out={}
        for file,line in text:gmatch("([%w_]+)%.lua\"?%]?:(%d+)") do
            if #out<4 then out[#out+1]=file..":"..line end
        end
        return #out>0 and table.concat(out,"<") or nil
    end
    local getinfo=debug and debug.getinfo
    if not getinfo then return nil end
    local out={}
    for level=0,8 do
        local ok,info=pcall(getinfo,c,level,"Sl")
        if not ok or not info then break end
        if info.what~="C" and #out<4 then
            local file=tostring(info.short_src or "?"):match("([%w_]+)%.lua") or "?"
            out[#out+1]=file..":"..tostring(info.currentline or 0)
        end
    end
    return #out>0 and table.concat(out,"<") or nil
end
function S.Run(fn,done,label)
    local co=coroutine.create(fn)
    local ticker
    local handle={}
    local busy=Routing.Busy
    local function stop()
        if ticker then ticker:Cancel() end
        local H=Routing.Hpa
        if H and H.CancelBuild then H:CancelBuild(co) end
        if busy then busy:Stop(handle) end
    end
    function handle:Cancel() stop() end
    -- Several slices per frame while they take less than S.BUDGET ms (the
    -- real ways of a large route are many searches; one slice per frame
    -- made it slow), so the game keeps its frame rate.
    local clock=rawget(_G,"debugprofilestop")
    -- What it cost (Florian 2026-10-14: the log tells it): milliseconds of
    -- its own work, frames it ran in.
    handle.cpu,handle.frames,handle.longest=0,0,0
    -- (the longest time between two of its frames: the game drew none meanwhile - a loading screen; Claude 2026-10-27,
    -- Florian's "first plan 15821 ms" with 958 ms of work in 65 frames)
    handle.longestGap=0
    local function step()
        local now=clock and clock()
        if now and handle.lastStep then handle.longestGap=math.max(handle.longestGap,now-handle.lastStep) end
        handle.lastStep=now
        -- The frame's share (Routing:FrameBudget, the setting); nothing while you fight.
        local budget=Routing.FrameBudget and Routing:FrameBudget(S.BUDGET) or S.BUDGET
        if budget<=0 then handle.paused=(handle.paused or 0)+1;return end
        S.sliceLimit=math.min(S.SLICE,budget)
        local began=clock and clock()
        handle.frames=handle.frames+1
        repeat
            local t=clock and clock()
            S.sliceBegan=t
            local kb=collectgarbage and collectgarbage("count")
            local ok,result=coroutine.resume(co)
            if clock then
                local d=clock()-t;handle.cpu=handle.cpu+d
                local at=S.Where(S.inner or co)
                if d>handle.longest then
                    handle.longest,handle.longestFrom,handle.longestTo=d,handle.at,at
                    handle.longestKB=kb and collectgarbage("count")-kb
                end
                handle.at=at
            end
            if not ok then stop();Routing:Print("Way failed: "..tostring(result));if done then done(nil) end;return end
            if coroutine.status(co)=="dead" then stop();if done then done(result) end;return end
        until not clock or clock()-began>=budget
    end
    -- label false: quiet, nothing beside the pointer (work in the background).
    if busy and label~=false then busy:Start(handle,label or S.nextLabel) end
    S.nextLabel=nil
    ticker=C_Timer.NewTicker(.01,step)
    return handle
end

