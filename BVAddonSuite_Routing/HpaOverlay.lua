local _,Routing=...
if not Routing.ready then return end
-- The navmesh planner's run-time overlay (Claude 2026-10-25/26; Florian: the old grid is to go entirely, Gather and
-- Navigate both plan on the navmesh). The navmesh data's classes are made offline from the shipped routing data;
-- what only you have - the areas you painted yourself (BVRoutingDB) and the ways you walked (BV Gather's heat map,
-- given through H.walked) - is laid over it at run time, without building the data again:
--   * every node of a cell under the overlay gets a virtual class: its own class with the paint replaced (no-go,
--     preferred, high risk, water) and/or a walked mark (1 walked, 2 walked WALKED times or more), costed like the
--     stored classes by H.ClassCost and your settings (walked: Routing's walkedPercent; in a city's rectangle a walked
--     cell costs that, else as stored);
--   * the abstract graph's distances inside a cluster touched by painting are measured again on its cells (a copy of
--     H.dm, the data's own rows kept), so the abstract search goes round a painted no-go;
--   * steps between clusters keep their stored costs (an entrance cell painted over is only noticed by the search on
--     the cells: callers refine with a corridor, H.Find(s, g, 0)).
-- The overlay belongs to a continent's state (Hpa.lua, H:Use) and stays while your painting and walked ways stay the
-- same: looked at again once per plan (H:Begin) and by Gather's route plan (H:RefreshOverlay).
local H=Routing.Hpa
if not H then return end
local floor,min,max,huge=math.floor,math.min,math.max,math.huge
local byte,char=string.byte,string.char
local NOGO,PREFER,RISK,ENEMY,WALL,SWIM=1,2,3,4,5,6
-- Painted kinds (Routing's strokes) to the classes' paint codes (Grid.KIND).
H.KIND={nogo=NOGO,prefer=PREFER,risk=RISK,swim=SWIM}
H.WALKED=3          -- times walked from which a cell counts as walked often (Grid.WALKED)
H.overlayRev=0
H.planSerial=0
-- Walked ways, given by BV Gather (Trace.lua): {rev = function() -> a number that changes with them, points =
-- function(cont, add) calling add(x, y, times) for each walked cell (continent map coordinates)}. nil: none.
H.walked=nil
-- "Prefer walked ways" (BV Gather's setting): cells walked WALKED times or more cost like walkedPercent.
H.PreferWalked=nil
function H.WalkedCost() return (Routing:Config().walkedPercent or 60)/100 end
for _,k in ipairs({"overlayChecked","overlayCount"}) do H.STATE[#H.STATE+1]=k end
local function breathe() if H.Breathe then H.Breathe() end end
local baseClassOf=H.BaseClassOf
local function overlayClassOf(n)
    local k=H.vclass[n]
    if k then return k end
    return baseClassOf(n)
end

function H.ClearOverlay()
    if H.baseDm then H.dm=H.baseDm end
    if H.baseClasses then H.classes=H.baseClasses end
    H.baseDm,H.baseClasses=nil,nil
    if H.vclass then
        H.vclass=nil
        H.overlayRev=(H.overlayRev or 0)+1
        H.costKey=nil
    end
    H.ClassOf=baseClassOf
    H.ccAdjusted=nil
    H.overlayStats=nil
end
-- Once per plan: the overlay looked at again (your painting or walked ways may have changed).
local begin=H.Begin
function H:Begin(...)
    begin(self,...)
    H.planSerial=H.planSerial+1
end
-- The class costs, then the walked marks of the virtual classes: walked WALKED times or more at most WalkedCost with
-- "Prefer walked ways"; in a city's rectangle any walked cell costs that.
local costs=H.Costs
function H:Costs()
    if H.cont and H.overlayChecked~=H.planSerial then
        H.overlayChecked=H.planSerial
        H:RefreshOverlay(H.cont)
    end
    costs(self)
    if not H.vclass or H.ccAdjusted==H.cc then return end
    local cfg=H.costCfg or Routing:Config()
    local mode=Routing:RouteMode()
    local walkedCost=H.WalkedCost()
    local prefer=H.PreferWalked and H.PreferWalked()
    local cc,lo=H.cc,H.floor
    for i=(H.NK0 or #H.baseClasses)+1,#H.classes do
        local c=H.classes[i]
        local walked=c[6] or 0
        local paint,flags=c[1],c[2]
        local onway=flags%2==1
        local city=floor(flags/8)%2==1
        if walked>0 and cc[i] and not onway and paint~=PREFER and paint~=SWIM then
            -- the same class on plain ground (no terrain code, not a city): paint and town factors, then the walked way
            local plain={paint,flags-(city and 8 or 0),c[3],255,c[5]}
            local base=H.ClassCost(plain,cfg,mode,nil)
            local w=base and base*walkedCost
            if w then
                if city then cc[i]=w
                elseif walked>=2 and prefer then cc[i]=min(cc[i],w) end
            end
        end
        if cc[i] and cc[i]<lo then lo=cc[i] end
    end
    H.floor=lo
    H.ccAdjusted=cc
end

-- The layers of a cell (nodes), walkable or not by their stored class.
local function cellNodes(cell)
    local out={}
    if baseClassOf(cell)>0 then out[1]=cell end
    local first,count=H.Extras(cell)
    for k=first,first+count-1 do out[#out+1]=H.NC+k end
    return out
end
H.CellNodes=cellNodes

-- cells: {[cell]={paint=code (H.KIND) or nil, walked=0|1|2}}. opts.dirtyWalked: walked ways also make their
-- clusters' abstract distances measured again (dearer to set, the abstract search then prefers them too).
-- Returns stats {cells, nodes, classes, dirty, ms}.
function H:SetOverlay(cells,opts)
    opts=opts or {}
    local clock=rawget(_G,"debugprofilestop")
    local t0=clock and clock() or 0
    H.ClearOverlay()
    local base=H.classes
    H.NK0=#base
    local classes={}
    for i,c in ipairs(base) do classes[i]=c end
    local vclass,keyOf,dirty={},{},{}
    local cellCount,nodeCount=0,0
    for cell,o in pairs(cells) do
        cellCount=cellCount+1
        if cellCount%256==0 then breathe() end
        local paint=o.paint or 0
        local walked=o.walked or 0
        for _,n in ipairs(cellNodes(cell)) do
            local k0=baseClassOf(n)
            if k0>0 then
                local key=k0*64+paint*4+walked
                local v=keyOf[key]
                if not v then
                    local c=base[k0]
                    classes[#classes+1]={paint>0 and paint or c[1],c[2],c[3],c[4],c[5],walked}
                    v=#classes;keyOf[key]=v
                end
                vclass[n]=v
                nodeCount=nodeCount+1
            end
        end
        if paint>0 or opts.dirtyWalked then dirty[H.ClusterOfCell(cell)]=true end
    end
    H.baseClasses=base
    H.classes=classes
    H.vclass=vclass
    H.ClassOf=overlayClassOf
    H.overlayRev=H.overlayRev+1
    H.costKey=nil
    H.ccAdjusted=nil
    H:Costs()
    -- The distances inside the clusters painted over, measured on their cells with the overlay, into a copy of the
    -- data's rows.
    local dm={}
    for cid,row in pairs(H.dm) do dm[cid]=row end
    local dirtyCount=0
    local u24=H.u24
    for cid in pairs(dirty) do
        local f,k=H.afirst[cid],H.acount[cid]
        local row=dm[cid]
        if f and row then
            dirtyCount=dirtyCount+1
            local bytes={}
            for i=1,#row do bytes[i]=byte(row,i) end
            for a=f,f+k-1 do
                local ao=(a-1)*5
                local pos,kc=byte(H.ac,ao+1,ao+2)
                local g0=a-pos
                local rbase=u24(H.ac,ao+3)+pos*kc
                local targets,any={},false
                for b=0,kc-1 do if b~=pos then targets[H.ANode(g0+b)]=true;any=true end end
                if any then
                    local dist=H.Local({[cid]=true},H.ANode(a),{targets=targets})
                    for b=0,kc-1 do
                        if b~=pos then
                            local d=dist[H.ANode(g0+b)]
                            local v=d and H.EncodeDist(floor(d*H.QUANT+.5)) or H.DMNONE
                            local o=(rbase+b)*2+1
                            bytes[o],bytes[o+1]=v%256,floor(v/256)
                        end
                    end
                end
            end
            local parts={}
            for i=1,#bytes,4000 do parts[#parts+1]=char(unpack(bytes,i,min(#bytes,i+3999))) end
            dm[cid]=table.concat(parts)
        end
    end
    H.baseDm=H.dm
    H.dm=dm
    local stats={cells=cellCount,nodes=nodeCount,classes=#classes-#base,dirty=dirtyCount,ms=clock and clock()-t0 or 0}
    H.overlayStats=stats
    return stats
end

---------------------------------------------------------------- your painting and walked ways on a continent
local function inside(poly,x,y)
    local res=false
    local n=#poly/2
    local j=n
    for i=1,n do
        local xi,yi,xj,yj=poly[2*i-1],poly[2*i],poly[2*j-1],poly[2*j]
        if (yi>y)~=(yj>y) and x<(xj-xi)*(y-yi)/(yj-yi)+xi then res=not res end
        j=i
    end
    return res
end
-- Your own strokes of the zones on this continent (level 0: the ground), in continent coordinates; and a key that
-- changes with them.
local function onCont(zone,cont,x,y)
    -- (a stroke on the continent's own map: its coordinates already)
    if zone==cont then return cont,x,y end
    return Routing:OnContinent(zone,x,y)
end
local function strokesOn(cont)
    local list,sum={},0
    local areas=Routing:Store().areas or {}
    for zone,strokes in pairs(areas) do
        if type(strokes)=="table" then
            for _,stroke in ipairs(strokes) do
                local code=H.KIND[stroke.kind]
                if code and (stroke.level or 0)==0 then
                    if stroke.poly then
                        local poly={}
                        for i=1,#stroke.poly-1,2 do
                            local c,x,y=onCont(zone,cont,stroke.poly[i],stroke.poly[i+1])
                            if c==cont then poly[#poly+1]=x;poly[#poly+1]=y end
                        end
                        if #poly>=6 then
                            list[#list+1]={code=code,poly=poly}
                            sum=sum+code*7+#poly+poly[1]*1e4+poly[2]*1e3
                        end
                    elseif stroke.x then
                        local c,x,y=onCont(zone,cont,stroke.x,stroke.y)
                        if c==cont then
                            local r=stroke.r or 20
                            list[#list+1]={code=code,x=x,y=y,r=r}
                            sum=sum+code*7+x*1e4+y*1e3+r
                        end
                    end
                end
            end
        end
    end
    return list,#list..":"..string.format("%.6f",sum)
end
local function cellAt(x,y)
    local g=H.geo
    local cx,cy=floor((x-g.minX)*g.width/H.cell),floor((y-g.minY)*g.height/H.cell)
    if cx<0 or cy<0 or cx>=H.cols or cy>=H.rows then return nil end
    return cy*H.cols+cx,cx,cy
end
-- {[cell]={paint, walked}} of your strokes and walked ways on the continent in use, and counts.
function H.OverlayCells(cont,strokes)
    local cells={}
    local count={strokes=#strokes,painted=0,walked=0}
    local g=H.geo
    local function mark(cell,key,value)
        local o=cells[cell]
        if not o then o={};cells[cell]=o end
        o[key]=value
    end
    for _,st in ipairs(strokes) do
        local test,x0,y0,x1,y1
        if st.poly then
            local p=st.poly
            x0,y0,x1,y1=huge,huge,-huge,-huge
            for i=1,#p-1,2 do x0,y0,x1,y1=min(x0,p[i]),min(y0,p[i+1]),max(x1,p[i]),max(y1,p[i+1]) end
            test=function(px,py) return inside(p,px,py) end
        else
            x0,y0,x1,y1=st.x-st.r/g.width,st.y-st.r/g.height,st.x+st.r/g.width,st.y+st.r/g.height
            local c=cellAt(st.x,st.y)
            if c then mark(c,"paint",st.code) end
            test=function(px,py) local dx,dy=(px-st.x)*g.width,(py-st.y)*g.height;return dx*dx+dy*dy<=st.r*st.r end
        end
        local _,a,b=cellAt(max(g.minX,x0),max(g.minY,y0))
        local _,c,d=cellAt(x1,y1)
        a,b=a or 0,b or 0
        c,d=c or H.cols-1,d or H.rows-1
        for cy=b,d do
            breathe()
            for cx=a,c do
                local px,py=g.minX+(cx+.5)*H.cell/g.width,g.minY+(cy+.5)*H.cell/g.height
                if test(px,py) then mark(cy*H.cols+cx,"paint",st.code);count.painted=count.painted+1 end
            end
        end
    end
    local W=H.walked
    if W and W.points then
        local n=0
        W.points(cont,function(x,y,times)
            local cell=cellAt(x,y)
            if cell and times>0 then
                mark(cell,"walked",times>=H.WALKED and 2 or 1)
                count.walked=count.walked+1
            end
            n=n+1
            if n%256==0 then breathe() end
        end)
    end
    return cells,count
end
-- The overlay of the continent in use made current: built again only when your painting or walked ways changed.
-- Returns its stats (nil: none) and the counts.
function H:RefreshOverlay(cont)
    cont=cont or H.cont
    if not (cont and H:Active(cont)) then return nil end
    local strokes,paintKey=strokesOn(cont)
    local W=H.walked
    local key=paintKey.."|"..tostring(W and W.rev and W.rev() or 0)
    H.overlayChecked=H.planSerial
    if H.overlaySig==key then return H.overlayStats,H.overlayCount end
    local cells,count=H.OverlayCells(cont,strokes)
    if next(cells) then H:SetOverlay(cells) else H.ClearOverlay() end
    H.overlaySig=key
    H.overlayCount=count
    return H.overlayStats,count
end

---------------------------------------------------------------- what Gather's route plan asks the graph
-- The straight line from node a to node b walkable on the graph at any cost (H.Line without its cost limit).
function H.LineAny(a,b)
    if a==b then return true end
    local clear=H.CLEAR
    H.CLEAR=math.huge
    local ok=H.Line(a,b)
    H.CLEAR=clear
    return ok
end

-- Which nodes belong together (one walks to the other and back) inside a set of clusters, on the abstract graph only
-- (intra-cluster groups, steps between clusters, jumps but the drops down a cliff): {[abstract node]=component}.
function H.RegionComponents(region)
    local comp,count={},0
    local u24=H.u24
    local function cluster(a) return H.ClusterOfCell(H.CellOf(H.ANode(a))) end
    for cid in pairs(region) do
        local f,k=H.afirst[cid],H.acount[cid]
        for a0=f or 1,f and f+k-1 or 0 do
            if not comp[a0] then
                count=count+1
                comp[a0]=count
                local queue,head={a0},1
                while head<=#queue do
                    local m=queue[head];head=head+1
                    if head%64==0 then breathe() end
                    local row=H.dm[cluster(m)]
                    local ao=(m-1)*5
                    local pos,kc=byte(H.ac,ao+1,ao+2)
                    local g0=m-pos
                    local rbase=u24(H.ac,ao+3)+pos*kc
                    for b=0,kc-1 do
                        local t=g0+b
                        if b~=pos and not comp[t] then
                            local o=(rbase+b)*2+1
                            local x1,x2=byte(row,o,o+1)
                            if x1+x2*256~=H.DMNONE then comp[t]=count;queue[#queue+1]=t end
                        end
                    end
                    local e0,e1=u24(H.ioff,(m-1)*3+1),u24(H.ioff,m*3+1)
                    for e=e0,e1-1 do
                        local t=u24(H.iedge,e*6+1)
                        if not comp[t] and region[cluster(t)] and H.Cost(H.ANode(t)) then comp[t]=count;queue[#queue+1]=t end
                    end
                    local js=H.jumpFrom[H.ANode(m)]
                    if js then
                        if type(js)=="number" then js={js} end
                        for _,j in ipairs(js) do
                            local t=H.ajump[H.JumpTo(j)]
                            -- (not a drop down a cliff: one way, no way back up)
                            if t and not comp[t] and region[cluster(t)] and not H.JumpDrop(j) then comp[t]=count;queue[#queue+1]=t end
                        end
                    end
                    -- (and the jumps that end here: no direction)
                    local back=H.jumpTo[H.ANode(m)]
                    if back then
                        if type(back)=="number" then back={back} end
                        for _,j in ipairs(back) do
                            local t=H.ajump[H.JumpFrom(j)]
                            if t and not comp[t] and region[cluster(t)] and not H.JumpDrop(j) then comp[t]=count;queue[#queue+1]=t end
                        end
                    end
                end
            end
        end
    end
    return comp,count
end
-- The first abstract node walked to from node n inside the clusters round it (a flood over walkable steps), or nil:
-- n lies on an island of its own there. limit: nodes at most.
function H.Entrance(n,limit)
    local cols,C=H.cols,H.C
    local c=H.CellOf(n)
    local X,Y=floor((c%cols)/C),floor(floor(c/cols)/C)
    local region,ab={},{}
    for dy=-1,1 do for dx=-1,1 do
        local x,y=X+dx,Y+dy
        if x>=0 and y>=0 and x<H.ccols and y<H.crows then
            local cid=x+y*H.ccols
            region[cid]=true
            local f,k=H.afirst[cid],H.acount[cid]
            if f then for a=f,f+k-1 do ab[H.ANode(a)]=a end end
        end
    end end
    if ab[n] then return ab[n] end
    local seen,queue,head={[n]=true},{n},1
    local found
    while head<=#queue and not found do
        local u=queue[head];head=head+1
        if head%64==0 then breathe() end
        if limit and head>limit then return nil end
        H.Each(u,function(v)
            if found or seen[v] then return end
            if not region[H.ClusterOfCell(H.CellOf(v))] or not H.Cost(v) then return end
            seen[v]=true
            if ab[v] then found=ab[v] else queue[#queue+1]=v end
        end)
    end
    -- (none: the nodes of the island too, every one of them reaching none either)
    if not found then return nil,seen end
    return found
end
