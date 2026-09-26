local _,ns=...
local Snap={}
ns.SnapModel=Snap
local features={-1,0,1}
local function rank(feature,direction)
    if direction~=0 and feature==direction then return 0 end
    return feature==0 and 1 or 2
end
-- Pure per-axis solver. Distances are UI units; capture/release are physical pixels.
function Snap.Axis(value,extent,axis,targets,options,previous,direction)
    local scale=options.scale or 1
    local dimension=axis=="x" and "width" or "height"
    local function hit(kind,source,targetFeature,target,coordinate)
        local result={kind=kind,source=source,targetFeature=targetFeature,target=target,coordinate=coordinate}
        result.value=coordinate-source*extent/2
        result.distance=math.abs(result.value-value)
        return result
    end
    local function better(candidate,best)
        if not best or candidate.distance<best.distance-.00001 then return true end
        if math.abs(candidate.distance-best.distance)<.00001 then
            local a,b=rank(candidate.source,direction),rank(best.source,direction)
            if a~=b then return a<b end
            -- Prefer like-for-like alignment when the same edge has two equal hits.
            return candidate.targetFeature==candidate.source and best.targetFeature~=best.source
        end
        return false
    end
    if options.elements then
        -- Retain a captured relation until the pointer leaves the wider release range.
        if previous and previous.kind=="element" then
            for _,target in ipairs(targets) do if target.id==previous.target then
                local candidate=hit("element",previous.source,previous.targetFeature,target.id,
                    target[axis]+previous.targetFeature*target[dimension]/2)
                if candidate.distance<=10/scale then return candidate.value,candidate end
            end end
        end
        local best
        for _,target in ipairs(targets) do
            for _,source in ipairs(features) do for _,point in ipairs(features) do
                local candidate=hit("element",source,point,target.id,target[axis]+point*target[dimension]/2)
                if candidate.distance<=6/scale and better(candidate,best) then best=candidate end
            end end
        end
        if best then return best.value,best end
    end
    if options.grid then
        local step,best=options.step
        for _,source in ipairs(features) do
            local coordinate=math.floor((value+source*extent/2)/step+.5)*step
            local candidate=hit("grid",source,nil,nil,coordinate)
            if better(candidate,best) then best=candidate end
        end
        if previous and previous.kind=="grid" then
            local held=hit("grid",previous.source,nil,nil,previous.coordinate)
            if held.distance<=best.distance+step*.20 then best=held end
        end
        return best.value,best
    end
    return value,nil
end

function Snap.Targets(id,nodes,rects,order)
    local out={}
    local function follows(candidate)
        local seen={}
        while nodes[candidate] and nodes[candidate].link do
            if seen[candidate] then return true end
            seen[candidate]=true; candidate=nodes[candidate].link.target
            if candidate==id then return true end
        end
        return false
    end
    for _,key in ipairs(order) do
        if key~=id and rects[key] and not follows(key) then
            local r=rects[key]
            out[#out+1]={id=key,x=r.x,y=r.y,width=r.width,height=r.height}
        end
    end
    return out
end
