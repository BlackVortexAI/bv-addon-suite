local _, ns = ...
local M = {}
ns.LayoutModel = M
local points = { CENTER={0,0}, LEFT={-1,0}, RIGHT={1,0}, TOP={0,1}, BOTTOM={0,-1},
    TOPLEFT={-1,1}, TOPRIGHT={1,1}, BOTTOMLEFT={-1,-1}, BOTTOMRIGHT={1,-1} }
function M.Copy(value)
    return ns.GraphValues.Copy(value)
end
function M.Number(v, fallback, low, high)
    if type(v) ~= "number" or v ~= v or math.abs(v) == math.huge then return fallback end
    return math.max(low, math.min(high, v))
end
function M.ZIndex(value)
    if ns.GraphValues.IsSecret(value) then return 0 end
    return math.floor(M.Number(value,0,-1000,1000))
end
-- Stable bands keep every stack template together. Its root controls the group;
-- child indices sort only inside it. Equal values use persistent layout IDs.
function M.DrawOrder(nodes)
    local groups,roots,levels,ranks={}, {}, {}, {}
    for id,n in pairs(nodes) do
        local root=n.templateRoot and nodes[n.templateRoot] and n.templateRoot or id
        if not groups[root] then groups[root]={};roots[#roots+1]=root end
        groups[root][#groups[root]+1]=id
    end
    local function less(a,b,inner,root)
        local za=inner and a==root and 0 or M.ZIndex(nodes[a].zIndex)
        local zb=inner and b==root and 0 or M.ZIndex(nodes[b].zIndex)
        return za<zb or za==zb and a<b
    end
    table.sort(roots,function(a,b)return less(a,b)end)
    local rank=0
    for _,root in ipairs(roots)do
        table.sort(groups[root],function(a,b)return less(a,b,true,root)end)
        for _,id in ipairs(groups[root])do rank=rank+1;ranks[id]=rank;levels[id]=8+rank*8 end
    end
    return levels,ranks,rank
end
function M.NormalizeStack(raw)
    raw=type(raw)=="table" and raw or {}
    return {direction=({UP=true,DOWN=true,LEFT=true,RIGHT=true})[raw.direction] and raw.direction or "DOWN",
        align=({START=true,CENTER=true,END=true})[raw.align] and raw.align or "CENTER",
        gap=M.Number(raw.gap,6,0,1000),maxEntries=math.floor(M.Number(raw.maxEntries,40,1,40)),
        sort=({APPEARANCE=true,NUMERIC=true,ALPHABETICAL=true})[raw.sort] and raw.sort or "APPEARANCE",
        descending=raw.descending==true}
end
function M.Normalize(raw)
    raw = type(raw) == "table" and raw or {}
    local n = M.Copy(raw)
    n.zIndex=M.ZIndex(n.zIndex)
    n.stack=n.anchorPoint==1 and type(n.stack)=="table" and M.NormalizeStack(n.stack) or nil
    local minimum=n.anchorPoint==1 and 0 or 1
    n.width = M.Number(n.width,720,minimum,5000); n.height = M.Number(n.height,22,minimum,2000)
    n.collapseWidth=n.collapseWidth==true; n.collapseHeight=n.collapseHeight==true; n.collapseGap=n.collapseGap==true
    n.x = M.Number(n.x,0,-10000,10000); n.y = M.Number(n.y,0,-10000,10000)
    n.screen = points[n.screen] and n.screen or "CENTER"
    for _, key in ipairs({"widthTarget","heightTarget"}) do
        if type(n[key]) ~= "string" or #n[key] == 0 then n[key] = nil end
    end
    if type(n.link) == "table" and type(n.link.target) == "string" then
        local a = n.link
        a.side = ({TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,CENTER=true})[a.side] and a.side or "BOTTOM"
        a.align = ({START=true,CENTER=true,END=true})[a.align] and a.align or "CENTER"
        a.gap = M.Number(a.gap,6,-10000,10000); a.offset = M.Number(a.offset,0,-10000,10000)
    else n.link = nil end
    if type(n.fallback) == "table" then
        local f = n.fallback
        n.fallback = { x=M.Number(f.x,n.x,-10000,10000), y=M.Number(f.y,n.y,-10000,10000),
            width=M.Number(f.width,n.width,0,5000), height=M.Number(f.height,n.height,0,2000) }
    end
    return n
end
function M.Validate(nodes)
    for id,node in pairs(nodes) do
        if node.zIndex~=nil and (ns.GraphValues.IsSecret(node.zIndex) or type(node.zIndex)~="number"
            or node.zIndex~=M.ZIndex(node.zIndex)) then return false,"Z index must be an integer from -1000 to 1000" end
        if node.widthTarget=="builtin:cursor" or node.heightTarget=="builtin:cursor" or node.widthTarget=="builtin:nameplate" or node.heightTarget=="builtin:nameplate" then
            return false,"Cursor and nameplate targets are position anchors, not size targets"
        end
        if node.link and node.link.target=="builtin:nameplate" and (not node.templateId or node.templateRoot~=id) then
            return false,"Only a Display Stack template root can follow a nameplate"
        end
        if node.templateId then
            local root=nodes[node.templateRoot]
            if type(node.templateId)~="string" or not root or root.templateId~=node.templateId or root.templateRoot~=node.templateRoot then return false,"Template root is unavailable" end
            if id~=node.templateRoot then
                local target=node.link and nodes[node.link.target]
                if not target or target.templateId~=node.templateId then return false,"Template slots must attach within their template" end
                for _,key in ipairs({"widthTarget","heightTarget"})do
                    local sizeTarget=node[key] and nodes[node[key]]
                    if node[key] and (not sizeTarget or sizeTarget.templateId~=node.templateId)then return false,"Template slot sizes must use their own template" end
                end
            end
        end
    end
    for _, axis in ipairs({"widthTarget","heightTarget","position"}) do
        local complete, visiting = {}, {}
        local function visit(id)
            if visiting[id] then return false end
            if complete[id] or not nodes[id] then return true end
            visiting[id] = true
            local node = nodes[id]
            local target = axis == "position" and (node.link and node.link.target) or node[axis]
            if target and not visit(target) then return false end
            visiting[id] = nil; complete[id] = true; return true
        end
        for id in pairs(nodes) do if not visit(id) then return false, "Circular " .. axis .. " relationship" end end
    end
    return true
end
-- Pure resolver. Rectangles are in UIParent units, centered on the screen.
-- External targets are read-only rectangles; an absent target retains its link.
function M.ClampCenter(x,y,width,height,viewportWidth,viewportHeight)
    -- Oversized elements stay centered on that axis without destroying size links.
    local halfX=math.max(0,(viewportWidth-width)/2)
    local halfY=math.max(0,(viewportHeight-height)/2)
    return math.max(-halfX,math.min(halfX,x)),math.max(-halfY,math.min(halfY,y))
end
function M.Resolve(input, external, viewportWidth, viewportHeight, activity, transforms, options)
    local nodes, out, warnings, constrained = {}, {}, {}, {}
    for id, raw in pairs(input) do nodes[id] = M.Normalize(raw) end
    if not M.Validate(nodes) then
        -- Quarantine malformed saved relationships in this resolution only. The
        -- persisted intent remains available for repair, with deterministic output.
        for id,n in pairs(nodes) do
            if n.link or n.widthTarget or n.heightTarget then
                if n.fallback then n.x,n.y,n.width,n.height=n.fallback.x,n.fallback.y,n.fallback.width,n.fallback.height; n.screen="CENTER" end
                n.link,n.widthTarget,n.heightTarget=nil,nil,nil
                warnings[id]="Circular saved relationship; fallback in use"
            end
        end
    end
    local function fallback(id)
        local n = nodes[id]
        local p = points[n.screen]
        return n.fallback or {width=n.width,height=n.height,
            x=n.x+p[1]*(viewportWidth-n.width)/2,y=n.y+p[2]*(viewportHeight-n.height)/2}
    end
    local function warn(id, message) warnings[id] = message end
    local natural,baseSizes={},{}
    for _, dimension in ipairs({"width","height"}) do
        local visiting, done = {}, {}
        local function size(id)
            if not nodes[id] then return external[id] and external[id][dimension] end
            if done[id] then return out[id][dimension] end
            if visiting[id] then warn(id,"Circular saved relationship; fallback in use"); return nil end
            visiting[id] = true
            local n, value = nodes[id], nodes[id][dimension]
            local target = n[dimension .. "Target"]
            if target then
                local matched = size(target)
                if matched then value = matched else value = fallback(id)[dimension]; warn(id,"Target unavailable; fallback in use") end
            end
            natural[id]=natural[id] or {}
            natural[id][dimension]=target and natural[target] and natural[target][dimension] or value
            baseSizes[id]=baseSizes[id] or {}; baseSizes[id][dimension]=value
            if transforms and transforms[id] then
                local transformed=ns.DisplayModel.Transform({x=0,y=0,width=value,height=value},transforms[id],"layout")
                value=transformed[dimension]; natural[id][dimension]=value
            end
            if activity and activity[id]==false and n[dimension=="width" and "collapseWidth" or "collapseHeight"] then value=0 end
            out[id] = out[id] or {}; out[id][dimension] = value
            visiting[id] = nil; done[id] = true; return value
        end
        for id in pairs(nodes) do size(id) end
    end
    local visiting, done, spacingCarry, slots = {}, {}, {}, {}
    local function vertical(side) return side=="TOP" or side=="BOTTOM" end
    local function attach(r,target,a,gap)
        local factor=a.align=="START" and -1 or a.align=="END" and 1 or 0
        if a.side=="CENTER" then r.x=target.x+a.offset; r.y=target.y+gap
        elseif vertical(a.side) then
            r.x=target.x+factor*(target.width-r.width)/2+a.offset
            r.y=target.y+(a.side=="TOP" and 1 or -1)*((target.height+r.height)/2+gap)
        else
            r.x=target.x+(a.side=="RIGHT" and 1 or -1)*((target.width+r.width)/2+gap)
            r.y=target.y-factor*(target.height-r.height)/2+a.offset
        end
    end
    local function position(id)
        if not nodes[id] then return external[id] end
        if done[id] then return out[id] end
        if visiting[id] then warn(id,"Circular saved anchor; fallback in use"); return nil end
        visiting[id] = true
        local n, r = nodes[id], out[id]
        local transform=transforms and transforms[id]
        if transform then r.width,r.height=baseSizes[id].width,baseSizes[id].height end
        local p = points[n.screen]
        r.x, r.y = n.x+p[1]*(viewportWidth-r.width)/2, n.y+p[2]*(viewportHeight-r.height)/2
        local slot={width=natural[id].width,height=natural[id].height}
        slot.x,slot.y=n.x+p[1]*(viewportWidth-slot.width)/2,n.y+p[2]*(viewportHeight-slot.height)/2
        slots[id]=slot
        if n.link then
            local a, target = n.link, position(n.link.target)
            if target then
                local gap=a.gap
                local carry=spacingCarry[a.target]
                if gap>=0 and carry and carry.side==a.side then gap=carry.gap end
                local axis=(a.side=="TOP" or a.side=="BOTTOM") and "collapseHeight" or "collapseWidth"
                local parent=nodes[a.target]; local origin=slots[a.target]
                if a.side~="CENTER" and parent and origin and parent.link and parent.link.side~="CENTER" and vertical(parent.link.side)~=vertical(a.side)
                    and activity and activity[a.target]==false and parent[axis] then
                    -- A turn starts at the hidden parent's former entry edge.
                    -- Project per connection: opposite branches must not mutate
                    -- the parent's rectangle or each other's attachment point.
                    target=M.Copy(target)
                    local dx,dy=(origin.width-target.width)/2,(origin.height-target.height)/2
                    local factor=a.align=="START" and -1 or a.align=="END" and 1 or 0
                    if vertical(a.side) then
                        target.x=origin.x+factor*dx
                        target.y=origin.y+(a.side=="BOTTOM" and 1 or -1)*dy
                    else
                        target.x=origin.x+(a.side=="RIGHT" and -1 or 1)*dx
                        target.y=origin.y-factor*dy
                    end
                    if parent.collapseGap and gap>=0 then gap=0 end
                end
                attach(slot,target,a,gap)
                if a.side~="CENTER" and activity and activity[id]==false and n[axis] and n.collapseGap then
                    -- Splice positive spacing once across consecutive collapsed
                    -- links. Negative overlap offsets remain deliberate geometry.
                    spacingCarry[id]={side=a.side,gap=math.max(0,gap)}
                    if gap>=0 then gap=0 end
                end
                attach(r,target,a,gap)
            else local f=fallback(id); r.x,r.y=f.x,f.y; slot.x,slot.y=f.x,f.y; warn(id,"Anchor unavailable; fallback in use") end
        end
        if transform then
            local changed=ns.DisplayModel.Transform(r,transform,"layout")
            r.x,r.y,r.width,r.height=changed.x,changed.y,changed.width,changed.height
        end
        local unbounded=options and (options.unbounded or options.unboundedNodes and options.unboundedNodes[id])
        if not unbounded then slot.x,slot.y=M.ClampCenter(slot.x,slot.y,slot.width,slot.height,viewportWidth,viewportHeight) end
        local x,y=r.x,r.y
        if not unbounded then x,y=M.ClampCenter(r.x,r.y,r.width,r.height,viewportWidth,viewportHeight) end
        if not unbounded and (x~=r.x or y~=r.y or r.width>viewportWidth or r.height>viewportHeight) then
            -- Retain stored intent. Children anchor to the visible target position.
            constrained[id]={x=r.x,y=r.y,oversized=r.width>viewportWidth or r.height>viewportHeight}
            r.x,r.y=x,y
        end
        visiting[id]=nil; done[id]=true; return r
    end
    for id in pairs(nodes) do position(id) end
    return out, warnings, constrained
end

-- Resolve a complete template once. Missing media never removes a layout slot.
-- An optional rootSize supplies an already resolved external size relationship.
function M.ResolveTemplate(records,rootElement,rootSize)
    if type(records)~="table" or not records[rootElement] then return nil,"Template root is unavailable" end
    local nodes={}
    for id,raw in pairs(records)do
        local n=M.Normalize(raw);n.screen="CENTER";n.collapseWidth,n.collapseHeight,n.collapseGap=false,false,false
        if id==rootElement then
            n.x,n.y,n.link=0,0,nil
            for _,axis in ipairs({"width","height"})do
                if n[axis.."Target"] and not records[n[axis.."Target"]]then
                    local size=rootSize and rootSize[axis]
                    if M.Number(size,nil,1,5000)~=size or size==nil then return nil,"Resolve the root size before repeating the template" end
                    n[axis]=size;n[axis.."Target"]=nil
                end
            end
        elseif not n.link or not records[n.link.target] then return nil,"Template slots must attach within their template" end
        for _,axis in ipairs({"widthTarget","heightTarget"})do if n[axis] and not records[n[axis]]then return nil,"Template size target is unavailable" end end
        nodes[id]=n
    end
    local ok,why=M.Validate(nodes);if not ok then return nil,why end
    -- Every non-root must eventually reach the explicit root (no loose branches).
    for id in pairs(nodes)do
        local cursor=id;local seen={}
        while cursor~=rootElement do
            if seen[cursor] or not nodes[cursor] or not nodes[cursor].link then return nil,"Template slots must reach the root" end
            seen[cursor]=true;cursor=nodes[cursor].link.target
        end
    end
    local rects=M.Resolve(nodes,{},0,0,nil,nil,{unbounded=true})
    local left,right,bottom,top=math.huge,-math.huge,math.huge,-math.huge
    for _,r in pairs(rects)do left=math.min(left,r.x-r.width/2);right=math.max(right,r.x+r.width/2);bottom=math.min(bottom,r.y-r.height/2);top=math.max(top,r.y+r.height/2)end
    return {rootElement=rootElement,root=rects[rootElement],rects=rects,
        bounds={x=(left+right)/2,y=(bottom+top)/2,width=right-left,height=top-bottom,left=left,right=right,bottom=bottom,top=top}}
end

-- Inputs are readable entry identities plus optional runtime sort values. Secret
-- sort values are never compared/stringified; they keep their appearance order.
function M.StackPlacements(template,entries,config)
    local c=M.NormalizeStack(config);local ordered={};local V=ns.GraphValues
    local function number(v)return not V.IsSecret(v) and type(v)=="number" and v==v and math.abs(v)<math.huge end
    for index,entry in ipairs(entries or {})do
        local sortValue=entry.sortValue;local key
        if not V.IsSecret(sortValue)then
            if c.sort=="NUMERIC" and number(sortValue)then key=sortValue
            elseif c.sort=="ALPHABETICAL" and type(sortValue)=="string"then key=sortValue:lower()end
        end
        ordered[#ordered+1]={entry=entry,index=index,appearance=number(entry.appearance) and entry.appearance or index,key=key}
    end
    table.sort(ordered,function(a,b)
        if c.sort~="APPEARANCE" then
            if (a.key==nil)~=(b.key==nil)then return a.key~=nil end
            if a.key~=nil and a.key~=b.key then if c.descending then return a.key>b.key else return a.key<b.key end end
        end
        if a.appearance~=b.appearance then return a.appearance<b.appearance end
        return a.index<b.index
    end)
    local out={};local b=template.bounds
    for index=1,math.min(#ordered,c.maxEntries)do
        local x,y=0,0;local step=index-1
        if c.direction=="UP" or c.direction=="DOWN"then
            y=step*(b.height+c.gap)*(c.direction=="UP" and 1 or -1)
            x=c.align=="START" and -b.left or c.align=="END" and -b.right or -b.x
        else
            x=step*(b.width+c.gap)*(c.direction=="RIGHT" and 1 or -1)
            y=c.align=="START" and -b.top or c.align=="END" and -b.bottom or -b.y
        end
        out[index]={entry=ordered[index].entry,offsetX=x,offsetY=y}
    end
    return out
end
