-- Pure editor geometry. Rectangles use TOPLEFT pixels, y grows down.
-- This never moves/resizes actual gameplay movers or writes layout state.
local _, ns = ...
local P = {}
local function clamp(v,lo,hi) return math.max(lo,math.min(math.max(lo,hi),v)) end
local function area(a,b,gap)
    gap=gap or 0
    local w=math.min(a.x+a.w,b.x+b.w+gap)-math.max(a.x,b.x-gap)
    local h=math.min(a.y+a.h,b.y+b.h+gap)-math.max(a.y,b.y-gap)
    return math.max(0,w)*math.max(0,h)
end
P.overlapArea=area
local function center(r) return r.x+r.w/2,r.y+r.h/2 end
local function crossedLength(segments,obstacles)
    local total=0
    for _,s in ipairs(segments) do
        for _,r in ipairs(obstacles or {}) do
            -- Touching an edge is not crossing its interior.
            if s.y1==s.y2 and s.y1>r.y and s.y1<r.y+r.h then
                total=total+math.max(0,math.min(math.max(s.x1,s.x2),r.x+r.w)-math.max(math.min(s.x1,s.x2),r.x))
            elseif s.x1==s.x2 and s.x1>r.x and s.x1<r.x+r.w then
                total=total+math.max(0,math.min(math.max(s.y1,s.y2),r.y+r.h)-math.max(math.min(s.y1,s.y2),r.y))
            end
        end
    end
    return total
end
local function leader(box,owner,obstacles)
    local bx,by=center(box);local ox,oy=center(owner)
    local result={fromX=clamp(ox,box.x,box.x+box.w),fromY=clamp(oy,box.y,box.y+box.h),
        toX=clamp(bx,owner.x,owner.x+owner.w),toY=clamp(by,owner.y,owner.y+owner.h)}
    local left,right=math.max(box.x,owner.x),math.min(box.x+box.w,owner.x+owner.w)
    local top,bottom=math.max(box.y,owner.y),math.min(box.y+box.h,owner.y+owner.h)
    if left<=right and top<=bottom then
        -- A caption inside its own mover needs no leader across the label.
        result.fromX=clamp(bx,left,right);result.toX=result.fromX
        result.fromY=clamp(by,top,bottom);result.toY=result.fromY
    elseif left<=right then
        result.fromX=clamp(bx,left,right);result.toX=result.fromX
    elseif top<=bottom then
        result.fromY=clamp(by,top,bottom);result.toY=result.fromY
    end
    local function route(horizontalFirst)
        local x1,y1,x2,y2=result.fromX,result.fromY,result.toX,result.toY
        local cx,cy=horizontalFirst and x2 or x1,horizontalFirst and y1 or y2
        local segments={}
        local function add(ax,ay,bx2,by2)
            if ax~=bx2 or ay~=by2 then segments[#segments+1]={x1=ax,y1=ay,x2=bx2,y2=by2} end
        end
        add(x1,y1,cx,cy);add(cx,cy,x2,y2)
        return segments
    end
    local horizontal,vertical=route(true),route(false)
    local h,v=crossedLength(horizontal,obstacles),crossedLength(vertical,obstacles)
    -- Only two local L paths are considered; this is not an obstacle router.
    result.segments=v<h and vertical or horizontal
    result.crossedLength=math.min(h,v)
    return result
end
P.orthogonalLeader=leader
local function solve(owner,w,h,obstacles,viewport,options)
    options=options or {};local margin=options.margin or 8;local gap=options.gap or 6
    -- Caller enumeration (for example pairs() over panels) must not make an
    -- otherwise identical layout jump. Sort a private list, never the inputs.
    local stable={};for _,obstacle in ipairs(obstacles) do stable[#stable+1]=obstacle end
    table.sort(stable,function(a,b)
        for _,key in ipairs({'x','y','w','h'}) do
            if a[key]~=b[key] then return a[key]<b[key] end
        end
        return false
    end)
    obstacles=stable
    local left,top=(viewport.x or 0)+margin,(viewport.y or 0)+margin
    local right,bottom=(viewport.x or 0)+viewport.w-margin,(viewport.y or 0)+viewport.h-margin
    local limited=w>right-left or h>bottom-top
    w=math.min(w,math.max(1,right-left));h=math.min(h,math.max(1,bottom-top))
    local candidates,seen={},{}
    local function add(x,y)
        x,y=clamp(x,left,right-w),clamp(y,top,bottom-h)
        local key=string.format('%.4f:%.4f',x,y)
        if not seen[key] then seen[key]=true;candidates[#candidates+1]={x=x,y=y,w=w,h=h} end
    end
    if options.preferred then add(options.preferred.x,options.preferred.y) end
    if options.caption then
        add(owner.x,owner.y-h-gap);add(owner.x+owner.w-w,owner.y-h-gap)
        add(owner.x,owner.y+owner.h+gap);add(owner.x+owner.w-w,owner.y+owner.h+gap)
        add(owner.x-w-gap,owner.y);add(owner.x+owner.w+gap,owner.y)
        if owner.w>=w+gap*2 and owner.h>=h+gap*2 then add(owner.x+gap,owner.y+gap) end
    else
        add(owner.x+owner.w+gap,owner.y);add(owner.x-w-gap,owner.y)
        add(owner.x,owner.y+owner.h+gap);add(owner.x,owner.y-h-gap)
    end
    local preferredCount=#candidates
    -- Candidate positions outside obstacles resolve dense clusters without
    -- falsifying mover coordinates. Stable input order gives stable placement.
    for _,r in ipairs(obstacles) do
        add(r.x-w-gap,owner.y);add(r.x+r.w+gap,owner.y)
        add(owner.x,r.y-h-gap);add(owner.x,r.y+r.h+gap)
        add(r.x,r.y-h-gap);add(r.x+r.w-w,r.y+r.h+gap)
    end
    add(left,top);add(right-w,top);add(left,bottom-h);add(right-w,bottom-h)
    add((left+right-w)/2,top);add((left+right-w)/2,bottom-h)
    local best,bestOverlap,bestDistance
    local ox,oy=center(owner)
    for index,candidate in ipairs(candidates) do
        local overlap=0
        for _,obstacle in ipairs(obstacles) do overlap=overlap+area(candidate,obstacle,gap) end
        local cx,cy=center(candidate);local distance=(cx-ox)^2+(cy-oy)^2
        -- Prefer the first unobstructed local position. Otherwise minimize
    -- actual occlusion first; callers can expose unresolved congestion.
        if overlap==0 and index<=preferredCount then
            candidate.clear=true;candidate.limited=limited;candidate.overlap=0
            candidate.leader=leader(candidate,owner,obstacles);return candidate
        end
        if not best or overlap<bestOverlap or overlap==bestOverlap and distance<bestDistance then
            best,bestOverlap,bestDistance=candidate,overlap,distance
        end
    end
    if not options.caption then
        -- A panel can fit at the X edge of one obstacle and the Y edge of
        -- another. Combine the already clamped axes only after local slots
        -- failed; captions retain their existing placement contract.
        local xs,ys,seenX,seenY={},{},{},{}
        for _,candidate in ipairs(candidates) do
            if not seenX[candidate.x] then seenX[candidate.x]=true;xs[#xs+1]=candidate.x end
            if not seenY[candidate.y] then seenY[candidate.y]=true;ys[#ys+1]=candidate.y end
        end
        -- Bound the extra search for crowded editors. All original candidates
        -- remain available; at most 256 nearby combinations can improve them.
        local function nearest(values,target)
            table.sort(values,function(a,b)
                local da,db=math.abs(a-target),math.abs(b-target)
                return da<db or da==db and a<b
            end)
        end
        nearest(xs,ox-w/2);nearest(ys,oy-h/2)
        for xi=1,math.min(16,#xs) do for yi=1,math.min(16,#ys) do
            local x,y=xs[xi],ys[yi]
            local distance=(x+w/2-ox)^2+(y+h/2-oy)^2
            if bestOverlap>0 or distance<bestDistance then
                local candidate={x=x,y=y,w=w,h=h};local overlap=0
                for _,obstacle in ipairs(obstacles) do
                    overlap=overlap+area(candidate,obstacle,gap)
                    if overlap>bestOverlap then break end
                end
                if overlap<bestOverlap or overlap==bestOverlap and distance<bestDistance then
                    best,bestOverlap,bestDistance=candidate,overlap,distance
                end
            end
        end end
    end
    best.clear=bestOverlap==0;best.limited=limited;best.overlap=bestOverlap;best.leader=leader(best,owner,obstacles)
    return best
end

-- items: {id,x,y,w,h,labelW,labelH,selected?}. All must be currently visible.
-- obstacles: visible toolbar/panels, not the items (those are added here).
-- Return positions by id and in priority order; inputs remain untouched.
function P.placeCaptions(items,obstacles,viewport,options)
    local ordered={};for _,item in ipairs(items) do ordered[#ordered+1]=item end
    table.sort(ordered,function(a,b)
        local selectedA,selectedB=not not a.selected,not not b.selected
        if selectedA~=selectedB then return selectedA end
        return tostring(a.id)<tostring(b.id)
    end)
    local result,placed={},{}
    for _,item in ipairs(ordered) do
        assert(result[item.id]==nil,'duplicate mover id')
        local blocked={}
        for _,obstacle in ipairs(obstacles or {}) do blocked[#blocked+1]=obstacle end
        for _,other in ipairs(ordered) do if other~=item then blocked[#blocked+1]=other end end
        for _,previous in ipairs(placed) do blocked[#blocked+1]=previous end
        local opt={caption=true,gap=options and options.gap,margin=options and options.margin}
        local box=solve(item,item.labelW,item.labelH or 23,blocked,viewport,opt)
        box.id=item.id;result[item.id]=box;placed[#placed+1]=box
    end
    return result,placed
end

-- obstacles must include all mover/caption/toolbar rectangles to preserve.
-- A preferred dock can be offered; it is accepted only when unobstructed.
function P.placePanel(owner,w,h,obstacles,viewport,options)
    return solve(owner,w,h,obstacles or {},viewport,options)
end
if ns then ns.LayoutPlacement=P end
return P
