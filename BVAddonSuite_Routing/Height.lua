local _,Routing=...
if not Routing.ready then return end
-- Your height from the NPCs standing near (Florian 2026-10-11: "we know the
-- NPCs' heights; we can work out ours"). The game gives an addon neither
-- your height nor an exact distance, only in range or not for fixed steps:
-- the range of items (5, 10, 15, 20, 30, 35 yards) and of inspecting (28),
-- which count in space as far as the Undercity probe of 2026-10-11 shows
-- (duel and trade ranges contradicted them for NPCs and are left out).
-- Each NPC with a name plate (or your target, the mouseover) found among
-- Map Data's posts bounds your height: height difference^2 = distance^2 -
-- horizontal distance^2, above or below. The bounds of all of them laid
-- over each other narrow it (Measure). Only NPCs standing still count
-- (Florian: patrols must not): Map Data's posts are spawns without
-- movement; one whose range changes while you stand still is left out too.
-- Used by the level (Level:Current keeps a level the height confirms), the
-- start of a way (levels whose height does not fit are no start) and the
-- probe. Level heights are learned on the way: while your level is sure and
-- the band narrow, its middle is kept per level (Learn; Level:Height).
local H={}
Routing.Height=H
-- Range steps (Florian 2026-10-11: "Aura Studio measured with more items"):
-- the friend item lists of LibRangeCheck-3.0 (037851f8, Era branch, MIT; as
-- in Aura Studio's RangeCheck, docs/research/2026-09-26-unit-range-sources.md),
-- one item per step that the client has cached; and its interact distances
-- by your race (3: duel 8 yd, 4: follow 28 yd; Tauren 6/25, Undead 7/27).
H.ITEMS={
    [5]={1970,8149,15826,16308,16991,17117,20403,22259},
    [10]={17626,17689,21267,23164},
    [15]={1251,2581,3530,3531,6450,6451,8544,8545,14529,14530,19066,19067,19068,19307},
    [20]={12450,12451,12455,12457,12458,12460,17757,21519},
    [25]={13289},
    [30]={954,955,1180,1181,1477,1478,1711,1712,1851,1912,2289,2290,2948,3012,3013},
    [35]={18904},
    [40]={1713,5205,5323,8346,11562,18640,18662},
}
H.INTERACT={[3]=8,[4]=28}
H.RACEINTERACT={Tauren={[3]=6,[4]=25},Scourge={[3]=7,[4]=27}}
-- The steps, smallest first: {r, check} or {r, items}; made once.
function H:Steps()
    if self.steps then return self.steps end
    local out={}
    local _,race=Routing.Call("UnitRace","player")
    for index,yards in pairs(H.RACEINTERACT[race] or H.INTERACT) do out[#out+1]={r=yards,check=index} end
    for yards,items in pairs(H.ITEMS) do out[#out+1]={r=yards,items=items} end
    table.sort(out,function(a,b) if a.r~=b.r then return a.r<b.r end return (a.check or 0)<(b.check or 0) end)
    self.steps=out
    return out
end
-- The item of a step the client has cached (looked for again every 5 s
-- while none is).
function H:Item(step)
    local now=GetTime()
    if step.item then return step.item end
    if step.lookedAt and now-step.lookedAt<5 then return nil end
    step.lookedAt=now
    for _,id in ipairs(step.items) do
        local cached=Routing.Call("C_Item.IsItemDataCachedByID",id)
        if cached==nil then cached=Routing.Call("GetItemInfo",id)~=nil end
        if cached==true and not Routing.Secret(cached) then step.item=id;return id end
    end
    return nil
end
H.NEAR=60       -- yards: posts of the name farther away are someone else
H.TOL=3         -- yards added to every bound (combat reach, Map Data's rounding)
H.STILL=1       -- yards: you count as standing still
H.EVERY=1       -- seconds a measurement is kept (Now)
H.FIT=5         -- yards a level's height may lie off the band and still fit
H.LEARN=8       -- a band at most this wide teaches the level's height
H.KEEP=40       -- learned heights kept per level
H.LEARNED=5     -- learned heights needed before they count
H.SPAN=40       -- a band (all its parts) wider than this tells nothing
H.STEADY=8      -- yards about one spot the measurements are laid over each other

local function field(list,name) for i,f in ipairs(list or {}) do if f==name then return i end end end
-- Map Data's posts of a continent by name: {x, y, z}. Older Map Data
-- without posts: its single NPCs with a service that do not walk about.
function H:Posts(cont)
    local d=rawget(_G,"BVMapData")
    if not (d and type(d.fields)=="table") then return nil end
    self.posts=self.posts or {}
    if self.posts[cont] and self.posts.data==d then return self.posts[cont] end
    if self.posts.data~=d then self.posts={data=d} end
    local out={}
    local function add(name,x,y,z)
        if type(name)~="string" or type(z)~="number" then return end
        out[name]=out[name] or {}
        local list=out[name]
        list[#list+1]={x=x,y=y,z=z}
    end
    local f=d.fields.posts
    if type(f)=="table" and type(d.posts)=="table" then
        local stride=#f
        local xi,yi,zi,ni=field(f,"x"),field(f,"y"),field(f,"z"),field(f,"name")
        local list=d.posts[cont]
        if type(list)=="table" and xi and ni and zi then
            for i=0,#list-stride,stride do add(d.strings[list[i+ni]],list[i+xi],list[i+yi],list[i+zi]) end
        end
    else
        f=d.fields.npc
        local stride=#(f or {})
        local xi,yi,ni,fi,ci,zi,mi=field(f,"x"),field(f,"y"),field(f,"name"),field(f,"flags"),field(f,"count"),field(f,"z"),field(f,"moves")
        local list=type(d.npc)=="table" and d.npc[cont]
        if type(list)=="table" and xi and ni and zi then
            for i=0,#list-stride,stride do
                local single=(not ci or list[i+ci]==1) and (fi and list[i+fi]~=0) and (not mi or list[i+mi]==0)
                if single then add(d.strings[list[i+ni]],list[i+xi],list[i+yi],list[i+zi]) end
            end
        end
    end
    self.posts[cont]=out
    return out
end
-- The units to look at: name plates, target, mouseover (no players).
function H:Units()
    local out,seen={},{}
    local function add(unit)
        if not Routing.Call("UnitExists",unit) or Routing.Call("UnitIsPlayer",unit) then return end
        local guid=Routing.Call("UnitGUID",unit)
        if type(guid)~="string" or Routing.Secret(guid) or seen[guid] then return end
        seen[guid]=true
        out[#out+1]={unit=unit,guid=guid}
    end
    local plates=Routing.Call("C_NamePlate.GetNamePlates")
    for _,plate in ipairs(type(plates)=="table" and plates or {}) do
        local unit=type(plate)=="table" and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
        if type(unit)=="string" then add(unit) end
    end
    add("target");add("mouseover")
    return out,type(plates)=="table" and #plates or 0
end
-- In range of each step: true, false or nil (unknown).
function H:Ranges(unit)
    local out={}
    for i,step in ipairs(self:Steps()) do
        local v
        if step.check then v=Routing.Call("CheckInteractDistance",unit,step.check)
        else
            local item=self:Item(step)
            if item then
                v=Routing.Call("C_Item.IsItemInRange",item,unit)
                if v==nil then v=Routing.Call("IsItemInRange",item,unit) end
            end
        end
        if Routing.Secret(v) then v=nil end
        if v==1 then v=true elseif v==0 then v=false end
        if v==true or v==false then out[i]=v end
    end
    return out
end
-- The range items' data (their range needs it in the client).
function H:Prepare()
    if self.prepared then return end
    self.prepared=true
    for _,step in ipairs(self:Steps()) do
        for i,id in ipairs(step.items or {}) do if i<=3 then Routing.Call("C_Item.RequestLoadItemDataByID",id) end end
    end
end
-- Interval lists {{a, b}, ...} intersected.
function H.Intersect(set,with)
    local out={}
    for _,p in ipairs(set) do
        for _,q in ipairs(with) do
            local a,b=math.max(p[1],q[1]),math.min(p[2],q[2])
            if a<=b then out[#out+1]={a,b} end
        end
    end
    return out
end
-- One measurement where you stand (cont, x, y on the continent):
-- {set = {{low, high}, ...}, used, units, plates, npcs = {{name, unit, guid,
-- post (the nearest of its name), h (its horizontal yards), sig, lo, hi, a,
-- b, posts (how many of the name count), why}}}.
-- Several posts of one name near (Florian's probe 2026-10-11: the guards at
-- the top and at the foot of Undercity's lift, the same name 100 yards
-- apart in height): each is possible; their bands together, the other
-- NPCs decide. A walking NPC: its range changed while you stood (at least
-- STILLFOR seconds apart, moved at most STILL yards) twice.
H.STILLFOR=.4
H.MOVED=2         -- times its range changed while you stood before it counts as walking
H.CHOICES=6       -- posts of one name at most looked at (the nearest)
-- Limits (Florian 2026-10-12: the game froze in Orgrimmar's throne hall,
-- many name plates; the bands of all of them were intersected unjoined,
-- their parts multiplying from NPC to NPC): the band joined after every NPC,
-- range asked only of NPCs with a post of their name near, at most UNITS of
-- them a measurement; the memory of NPCs seen kept small.
H.UNITS=12
H.REMEMBER=300
function H:Measure(cont,cx,cy)
    self:Prepare()
    local N=Routing.Navigate
    local posts=self:Posts(cont)
    local units,plates=self:Units()
    local now=GetTime()
    self.moving=self.moving or {}
    self.seen=self.seen or {}
    local out={set={{-1e9,1e9}},used=0,units=#units,plates=plates,npcs={}}
    -- Forget the NPCs seen when too many (a capital's crowd).
    self.seenCount=(self.seenCount or 0)
    if self.seenCount>H.REMEMBER then self.seen,self.moving,self.seenCount={},{},0 end
    local asked=0
    for _,u in ipairs(units) do
        local name=Routing.Call("UnitName",u.unit)
        if Routing.Secret(name) then name=nil end
        -- Only NPCs Map Data knows near here are asked (the cheap test first).
        local known=false
        if posts and name and posts[name] then
            for _,e in ipairs(posts[name]) do
                if N.Yards(cont,cx,cy,e.x,e.y)<=H.NEAR then known=true;break end
            end
        end
        if known and asked>=H.UNITS then known=nil end
        if known then asked=asked+1 end
        local ranges=known and self:Ranges(u.unit) or {}
        local sig={}
        local steps=self:Steps()
        for i=1,#steps do sig[i]=ranges[i]==true and "y" or ranges[i]==false and "n" or "?" end
        sig=table.concat(sig)
        -- Its range changed while you stood still: it may walk.
        local last=self.seen[u.guid]
        if known and last and last.sig~=sig and last.cont==cont and now-last.t>=H.STILLFOR and N.Yards(cont,cx,cy,last.x,last.y)<=H.STILL then
            self.moving[u.guid]=(self.moving[u.guid] or 0)+1
        end
        if known and (not last or last.sig~=sig or N.Yards(cont,cx,cy,last.x,last.y)>H.STILL) then
            if not last then self.seenCount=self.seenCount+1 end
            self.seen[u.guid]={sig=sig,cont=cont,x=cx,y=cy,t=now}
        end
        -- The posts of its name near, nearest first.
        local near={}
        for _,e in ipairs(posts and name and posts[name] or {}) do
            local d=N.Yards(cont,cx,cy,e.x,e.y)
            if d<=H.NEAR then near[#near+1]={e,d} end
        end
        table.sort(near,function(a,b) return a[2]<b[2] end)
        while #near>H.CHOICES do table.remove(near) end
        -- The bounds of its distance: out of range of lo, in range of hi.
        local lo,hi=0,nil
        for i,step in ipairs(steps) do
            if ranges[i]==true and (not hi or step.r<hi) then hi=step.r end
            if ranges[i]==false and step.r>lo then lo=step.r end
        end
        -- Each post it may be: above or below it.
        local band,first={},nil
        for _,c in ipairs(near) do
            local e,d=c[1],c[2]
            if not hi or hi+H.TOL>=d then
                local a=math.sqrt(math.max(0,math.max(0,lo-H.TOL)^2-d^2))
                local b=hi and math.sqrt(math.max(0,(hi+H.TOL)^2-d^2)) or 1e9
                band[#band+1]={e.z-b,e.z-a};band[#band+1]={e.z+a,e.z+b}
                first=first or {a=a,b=b}
            end
        end
        local why
        if not name then why="no name"
        elseif name=="Unknown" or name==(rawget(_G,"UNKNOWNOBJECT") or "Unknown") then why="name not loaded yet"
        elseif not posts then why="no Map Data"
        elseif #near==0 then why="not in Map Data nearby"
        elseif known==nil then why="not asked (enough NPCs measured)"
        elseif (self.moving[u.guid] or 0)>=H.MOVED then why="moved while you stood"
        elseif hi and lo>hi then why="its ranges contradict"
        elseif not hi and lo<=0 then why="no range answered"
        elseif #band==0 then why="in range closer than its spot (Map Data off?)" end
        local entry={name=name,unit=u.unit,guid=u.guid,post=near[1] and near[1][1],h=near[1] and near[1][2],sig=sig,lo=lo,hi=hi,why=why,posts=#band/2}
        if not why then
            entry.a,entry.b=first.a,first.b
            out.set=H.Join(H.Intersect(out.set,H.Join(band)))
            out.used=out.used+1
        end
        out.npcs[#out.npcs+1]=entry
    end
    -- Touching parts as one.
    if out.used==0 then out.set=nil else out.set=H.Join(out.set) end
    return out
end
-- Interval parts sorted and touching ones joined.
function H.Join(set)
    table.sort(set,function(a,b) return a[1]<b[1] end)
    local out={}
    for _,p in ipairs(set) do
        local last=out[#out]
        if last and p[1]<=last[2]+.5 then last[2]=math.max(last[2],p[2]) else out[#out+1]={p[1],p[2]} end
    end
    return out
end
-- The band's whole width (lowest to highest), nil without one.
function H.Span(set)
    if not set or #set==0 then return nil end
    local low,high=math.huge,-math.huge
    for _,p in ipairs(set) do low,high=math.min(low,p[1]),math.max(high,p[2]) end
    return high-low,low,high
end
-- Does a height lie in the band (FIT yards either side)? nil: the band
-- tells nothing (none, or wider than SPAN).
function H.Fits(set,z,top)
    local span=H.Span(set)
    if not span or span>H.SPAN or type(z)~="number" then return nil end
    top=type(top)=="number" and top or z
    -- A span of heights (a level on a slope): any of it.
    for _,p in ipairs(set) do if top>=p[1]-H.FIT and z<=p[2]+H.FIT then return true end end
    return false
end
-- The measurement where you are now, kept EVERY seconds.
function H:Now()
    local t=GetTime()
    if self.now and self.nowAt and t-self.nowAt<H.EVERY then return self.now end
    local mapID,x,y=Routing:Position()
    local cont,cx,cy
    if mapID then cont,cx,cy=Routing:OnContinent(mapID,x,y) end
    local m=cont and self:Measure(cont,cx,cy) or {used=0,npcs={},units=0,plates=0}
    -- Near one spot (STEADY yards) the measurements are laid over each other
    -- (Florian 2026-10-11: at the top of the lift, between two guards, the
    -- band stayed 15 yards wide and Use flickered): a few steps about
    -- change the distances and narrow it; walking off starts anew.
    local steady=self.steady
    if m.set and steady and cont and steady.cont==cont and Routing.Navigate.Yards(cont,cx,cy,steady.x,steady.y)<=H.STEADY then
        local both=H.Intersect(steady.set,m.set)
        if #both>0 then
            m.raw=m.set;m.set=H.Join(both);steady.n=steady.n+1
        else steady.n=1 end
        steady.set=m.set
        m.still=steady.n
    elseif m.set and cont then
        self.steady={cont=cont,x=cx,y=cy,set=m.set,n=1}
        m.still=1
    elseif cont and steady and Routing.Navigate.Yards(cont,cx,cy,steady.x,steady.y)>H.STEADY then
        self.steady=nil
    end
    self.now=m
    self.nowAt=t
    return self.now
end
-- Does your height fit a level (its height: Level:Height; nil the ground,
-- its height from the terrain where you are)? nil: nothing to tell.
function H:FitsLevel(id,cont,cx,cy)
    local m=self:Now()
    if not m.set then return nil end
    if id==nil then return H.Fits(m.set,cont and Routing.Navigate.GroundHeight(cont,cx,cy)) end
    local lo,hi
    if cont then lo,hi=Routing.Level:SpanAt(id,cont,cx,cy) else lo,hi=Routing.Level:Span(id) end
    return H.Fits(m.set,lo,hi)
end
-- While your level is sure and the band narrow: its middle kept for the level.
function H:Learn(id)
    if id==nil then return false end
    local m=self:Now()
    local span,low,high=H.Span(m.set)
    if not span or span>H.LEARN or #m.set==0 then return false end
    local db=Routing:Store()
    db.heights=type(db.heights)=="table" and db.heights or {}
    local list=type(db.heights[id])=="table" and db.heights[id] or {}
    db.heights[id]=list
    -- Once per measurement.
    if self.learnedAt==self.nowAt then return false end
    self.learnedAt=self.nowAt
    list[#list+1]=math.floor((low+high)/2+.5)
    while #list>H.KEEP do table.remove(list,1) end
    return true
end
-- A level's learned height (the middle of what was learned) and how many.
function H:Learned(id)
    local db=Routing:Store()
    local list=type(db.heights)=="table" and db.heights[id]
    if type(list)~="table" or #list<H.LEARNED then return nil,type(list)=="table" and #list or 0 end
    local sorted={}
    for i,v in ipairs(list) do sorted[i]=v end
    table.sort(sorted)
    return sorted[math.floor((#sorted+1)/2)],#sorted
end
-- A measurement in words (Florian 2026-10-11: "how can I sound out the
-- height in the game myself?"): the band ("-44..-42"), its middle and
-- width; nil, why when it tells nothing.
H.USE=16          -- a band at most this wide may be taken as a level's height
function H.Text(m)
    if not m or (m.used or 0)==0 then return nil,"no NPC near tells it (friendly NPC name plates on?)" end
    if not m.set or #m.set==0 then return nil,"the NPCs near contradict each other" end
    local span,low,high=H.Span(m.set)
    if low<-1e8 or high>1e8 then return nil,"only far NPCs: not bounded yet" end
    local parts={}
    for _,p in ipairs(m.set) do parts[#parts+1]=string.format("%.0f..%.0f",p[1],p[2]) end
    return table.concat(parts," or "),(low+high)/2,span
end
-- Measured now (not the kept one).
function H:Fresh()
    self.nowAt=nil
    return self:Now()
end
