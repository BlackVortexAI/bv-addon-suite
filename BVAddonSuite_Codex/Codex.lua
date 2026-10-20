local package,C=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.101 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.1.2","0.8.101",1) then return end
-- Codex (Florian 2026-10-11, docs/codex-concept.md): find anything, like
-- Spotlight or EasyFind, and put several places into a tour that BV Routing
-- leads you through the shortest way. Files fill C: Codex (this: the places
-- from Map Data, the search), Tour (stops, the choice of places, leading),
-- UI\Palette (the search field), UI\Tour (the tour window), Commands.
-- Map Data brings the places, Routing the estimates and the way; both are
-- optional (said when missing).
C.ns=ns
ns.Codex=C
C.ready=true
function C:Print(text) ns:Print(text,"Codex") end
local function call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
C.Call=call
function C.Routing() local R=ns.Routing;return R and R.ready and R or nil end

-- Where you are: continent, x, y (continent map), your level; nil without Routing.
function C:Here()
    local R=C.Routing()
    if not R then return nil end
    return R.Navigate:Here()
end
-- Yards between two points of one continent map.
local sizes={}
function C.Yards(cont,x1,y1,x2,y2)
    local s=sizes[cont]
    if not s then
        local w,h=call("C_Map.GetMapWorldSize",cont)
        s={type(w)=="number" and w or 0,type(h)=="number" and h or 0};sizes[cont]=s
    end
    local dx,dy=(x2-x1)*s[1],(y2-y1)*s[2]
    return math.sqrt(dx*dx+dy*dy)
end
-- Your faction: 1 Horde, 2 Alliance, 3 none known.
function C.Faction()
    local group=call("UnitFactionGroup","player")
    return group=="Horde" and 1 or group=="Alliance" and 2 or 3
end

-- The places ------------------------------------------------------------------
-- Every entry: {key, name, detail (what it is), kind ("npc", "category",
-- "flight", "transport", "entrance", "object"), places = {{cont, x, y, z,
-- name, label}}, words (lower case, for the search)}. Built once from Map
-- Data for your faction (friendly NPCs, your flight masters and transports).
local OBJECTS={[1]="Mailbox",[2]="Meeting Stone",[3]="Anvil",[4]="Forge"}
local TRANSPORTS={[1]="Zeppelin",[2]="Ship",[3]="Tram"}
local function field(list,name) for i,f in ipairs(list or {}) do if f==name then return i end end end
local function rows(d,key,cont)
    local f=d.fields and d.fields[key]
    local list=d[key] and d[key][cont]
    local stride=f and #f or 0
    local i=-stride
    return function()
        i=i+stride
        if stride>0 and type(list)=="table" and i+stride<=#list then
            local r={}
            for j=1,stride do r[f[j]]=list[i+j] end
            return r
        end
    end
end
local function shares(a,b) return (a%2==1 and b%2==1) or (math.floor(a/2)%2==1 and math.floor(b/2)%2==1) end
C.CONTINENTS={1414,1415}
-- The capitals: Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity.
C.CITY={[1453]=true,[1455]=true,[1457]=true,[1454]=true,[1456]=true,[1458]=true}
-- Whose capital (C.Faction: 1 Horde, 2 Alliance).
C.CAPITAL={[1453]=2,[1455]=2,[1457]=2,[1454]=1,[1456]=1,[1458]=1}
function C:Data() return rawget(_G,"BVMapData") end
-- The zone or city a point lies in (Florian 2026-10-14: "few players know
-- what the NPCs are called"; "Warlock Orgrimmar" finds the trainer there):
-- the smallest of the client's zone rectangles holding it (a city before
-- its zone). Kept per point (to about 30 yards).
function C:ZoneAt(cont,x,y)
    if type(x)~="number" or type(y)~="number" then return nil end
    local rects=self.zoneRects and self.zoneRects[cont]
    if not rects then
        self.zoneRects=self.zoneRects or {}
        rects={}
        for _,info in ipairs(call("C_Map.GetMapChildrenInfo",cont,3,true) or {}) do
            if type(info)=="table" and info.mapType==3 and type(info.name)=="string" then
                local minX,maxX,minY,maxY=call("C_Map.GetMapRectOnMap",info.mapID,cont)
                if type(minX)=="number" and type(maxX)=="number" and maxX>minX and type(minY)=="number" and type(maxY)=="number" and maxY>minY then
                    rects[#rects+1]={info.name,minX,maxX,minY,maxY,(maxX-minX)*(maxY-minY),info.mapID}
                end
            end
        end
        self.zoneRects[cont]=rects
        self.zoneMemo={}
    end
    local key=cont..":"..math.floor(x*1000+.5)..":"..math.floor(y*1000+.5)
    local memo=self.zoneMemo or {};self.zoneMemo=memo
    local known=memo[key]
    if known~=nil then return known or nil end
    local best
    for _,r in ipairs(rects) do
        if x>=r[2] and x<=r[3] and y>=r[4] and y<=r[5] and (not best or r[6]<best[6]) then best=r end
    end
    memo[key]=best and best[1] or false
    self.zoneMapMemo=self.zoneMapMemo or {}
    self.zoneMapMemo[key]=best or false
    return best and best[1] or nil
end
-- In an enemy base (Florian 2026-10-14: shown, marked; leading there turns
-- avoiding them off for that way): its name, else nil. Core's enemy places
-- of the zone (capitals, around enemy flight masters).
function C:Hostile(cont,x,y)
    local O=ns.MapOverlays
    if not (O and O.Hostile) or type(x)~="number" then return nil end
    self:ZoneAt(cont,x,y)
    -- Kept per point (the search's rows ask on every keystroke).
    local key=cont..":"..math.floor(x*1000+.5)..":"..math.floor(y*1000+.5)
    self.hostileMemo=self.hostileMemo or {}
    local known=self.hostileMemo[key]
    if known~=nil then return known or nil end
    local found=false
    -- In a capital of the other side (Florian 2026-10-14: Orgrimmar was not
    -- marked; Core's enemy places are the rectangles of their map labels,
    -- the city's middle lies outside them).
    local mine=C.Faction()
    for _,r in ipairs(self.zoneRects and self.zoneRects[cont] or {}) do
        local side=C.CAPITAL[r[7]]
        if side and mine~=3 and side~=mine and x>=r[2] and x<=r[3] and y>=r[4] and y<=r[5] then found=r[1] end
    end
    -- Every zone map holding it (Florian 2026-10-14: Orgrimmar itself was
    -- not marked; an enemy capital is an area of the zone around it).
    for _,r in ipairs(self.zoneRects and self.zoneRects[cont] or {}) do
        if x>=r[2] and x<=r[3] and y>=r[4] and y<=r[5] then
            local zx,zy=(x-r[2])/(r[3]-r[2]),(y-r[4])/(r[5]-r[4])
            for _,h in ipairs(O:Hostile(r[7]) or {}) do
                if not found and zx>=h.left and zx<=h.right and zy>=h.top and zy<=h.bottom then found=h.name~="" and h.name or r[1] end
            end
        end
    end
    self.hostileMemo[key]=found
    return found or nil
end
function C:Entries()
    local d=self:Data()
    if not (type(d)=="table" and type(d.fields)=="table") then return nil end
    if self.entries and self.entriesData==d then return self.entries end
    local mine=C.Faction()
    local _,_,classID=call("UnitClass","player")
    -- hostile in Map Data: 1 to the Alliance, 2 to the Horde.
    local hostileTo=mine==1 and 2 or mine==2 and 1 or 3
    local byKey,list={},{}
    local function entry(key,name,detail,kind)
        local e=byKey[key]
        if not e then
            e={key=key,name=name,detail=detail,kind=kind,places={},words=(name.." "..(detail or "")):lower()}
            byKey[key]=e;list[#list+1]=e
        end
        return e
    end
    local function place(e,p) e.places[#e.places+1]=p end
    local s=d.strings or {}
    for _,cont in ipairs(C.CONTINENTS) do
        for r in rows(d,"npc",cont) do
            local name,sub=s[r.name],s[r.sub]
            if type(name)=="string" and not shares(r.hostile or 0,hostileTo) then
                local p={cont=cont,x=r.x,y=r.y,z=r.z,name=name,label=sub or "",moves=r.moves==1}
                place(entry("npc:"..name,name,sub~="" and sub or nil,"npc"),p)
                -- Everyone of a title is one category ("Warlock Trainer").
                if type(sub)=="string" and sub~="" then place(entry("title:"..sub:lower(),sub,"everyone of this title","category"),p) end
                -- Your class's trainers (trainer: type * 16 + class, type 0).
                local t=r.trainer or 0
                if t~=0 and math.floor(t/16)==0 and t%16==classID then
                    local e=entry("mine:classtrainer","My Class Trainer","your class's trainers","category")
                    e.words="my class trainer "..e.words
                    place(e,p)
                end
            end
        end
        for r in rows(d,"flights",cont) do
            local name=s[r.name]
            if type(name)=="string" and shares(r.faction or 3,mine) then
                local p={cont=cont,x=r.x,y=r.y,z=r.z,name=name,label="Flight master"}
                place(entry("flight:"..name,name,"Flight master","flight"),p)
                place(entry("title:flight master","Flight Master","every flight master of yours","category"),p)
            end
        end
        for r in rows(d,"entrances",cont) do
            local name=s[r.name]
            if type(name)=="string" then
                local e=entry("entrance:"..name,name,"Instance entrance"..((r.level or 0)>0 and (", level "..r.level) or ""),"entrance")
                -- Its instance map (raids have their own icon).
                e.instance=type(r.instance)=="number" and r.instance or e.instance
                place(e,{cont=cont,x=r.x,y=r.y,z=r.z,name=name,label="Entrance"})
            end
        end
        for r in rows(d,"objects",cont) do
            local kind=OBJECTS[r.kind]
            if kind then place(entry("title:"..kind:lower(),kind,"every "..kind:lower(),"category"),{cont=cont,x=r.x,y=r.y,z=r.z,name=kind,label=kind}) end
        end
    end
    -- Transports: both stops of a connection; a category per kind.
    local f=d.fields.transports
    if f and type(d.transports)=="table" then
        local stride=#f
        for i=0,#d.transports-stride,stride do
            local r={}
            for j=1,stride do r[f[j]]=d.transports[i+j] end
            local name,kind=s[r.name],TRANSPORTS[r.kind]
            if type(name)=="string" and kind and shares(r.faction or 3,mine) then
                local e=entry("transport:"..name,name,kind,"transport")
                local c=entry("title:"..kind:lower(),kind,"every "..kind:lower().." stop of yours","category")
                for _,side in ipairs({{r.mapA,r.xA,r.yA},{r.mapB,r.xB,r.yB}}) do
                    local p={cont=side[1],x=side[2],y=side[3],name=name,label=kind.." stop"}
                    place(e,p);place(c,p)
                end
            end
        end
    end
    -- What vendors sell, which quests NPCs give (Map Data's sells and
    -- quests, by the NPC's name): an item leads to its vendors, a quest to
    -- whoever gives it; only NPCs friendly to you, quests of your side.
    local races=mine==1 and 178 or mine==2 and 77 or 255
    local function any(a,b)
        while a>0 and b>0 do
            if a%2==1 and b%2==1 then return true end
            a,b=math.floor(a/2),math.floor(b/2)
        end
        return false
    end
    local function table_rows(key)
        local f=d.fields[key]
        local list=d[key]
        local stride=f and #f or 0
        local i=-stride
        return function()
            i=i+stride
            if stride>0 and type(list)=="table" and i+stride<=#list then
                local r={}
                for j=1,stride do r[f[j]]=list[i+j] end
                return r
            end
        end
    end
    for r in table_rows("sells") do
        local vendor,item=s[r.npc],s[r.item]
        local who=vendor and byKey["npc:"..vendor]
        if who and type(item)=="string" then
            local e=entry("item:"..item,item,nil,"item")
            e.vendors=(e.vendors or 0)+1
            e.from=vendor
            -- Its ID (Map Data since 2026-10-12): its icon in the client.
            if type(r.id)=="number" and not e.itemID then e.itemID=r.id end
            for _,p in ipairs(who.places) do place(e,p) end
        end
    end
    for r in table_rows("quests") do
        local giver,title=s[r.npc],s[r.title]
        local who=giver and byKey["npc:"..giver]
        if who and type(title)=="string" and ((r.races or 0)==0 or any(r.races,races)) then
            local e=entry("quest:"..title,title,nil,"quest")
            e.level=r.level
            e.from=giver
            for _,p in ipairs(who.places) do place(e,p) end
        end
    end
    -- Where a quest is turned in (Map Data's ends).
    for r in table_rows("ends") do
        local taker,title=s[r.npc],s[r.title]
        local who=taker and byKey["npc:"..taker]
        if who and type(title)=="string" and ((r.races or 0)==0 or any(r.races,races)) then
            local e=entry("turnin:"..title,title,nil,"turnin")
            e.to=taker
            for _,p in ipairs(who.places) do place(e,p) end
        end
    end
    for _,e in ipairs(list) do
        if e.kind=="turnin" then e.detail="turn in at "..e.to;e.words=(e.name.." turn in "..e.to):lower() end
        if e.kind=="item" then e.detail=e.vendors>1 and ("sold by "..e.vendors.." vendors") or ("sold by "..e.from)
        elseif e.kind=="quest" then e.detail=((e.level or 0)>0 and ("level "..e.level..", ") or "").."from "..e.from end
        if e.kind=="item" or e.kind=="quest" then e.words=(e.name.." "..e.detail):lower() end
    end
    -- Zones and cities of both continents (the client's maps): their middle, or the
    -- arrival point Map Data has for your side (Codex 2026-10-20: Winterspring's
    -- middle lay where no way leads; a checked point on a recorded way instead).
    local arrivals=type(d)=="table" and type(d.zoneArrivals)=="table" and d.zoneArrivals or {}
    local side=call("UnitFactionGroup","player")
    for _,cont in ipairs(C.CONTINENTS) do
        for _,info in ipairs(call("C_Map.GetMapChildrenInfo",cont,3,true) or {}) do
            if type(info)=="table" and info.mapType==3 and type(info.name)=="string" then
                local minX,maxX,minY,maxY=call("C_Map.GetMapRectOnMap",info.mapID,cont)
                if type(minX)=="number" and maxX>minX then
                    local e=entry("zone:"..info.mapID,info.name,C.CITY[info.mapID] and "City" or "Zone","zone")
                    e.mapID=info.mapID
                    local a=type(arrivals[info.mapID])=="table" and arrivals[info.mapID][side]
                    if type(a)=="table" and a.cont==cont and type(a.x)=="number" and type(a.y)=="number" then
                        place(e,{cont=cont,x=a.x,y=a.y,name=info.name,label="Zone"})
                    else
                        place(e,{cont=cont,x=(minX+maxX)/2,y=(minY+maxY)/2,name=info.name,label="Zone"})
                    end
                end
            end
        end
    end
    -- Where they are, to search by (not the zones themselves, nor
    -- categories: everyone of a title is everywhere).
    for _,e in ipairs(list) do
        if e.kind~="zone" and e.kind~="category" then
            local seen={}
            for _,p in ipairs(e.places) do
                local zone=self:ZoneAt(p.cont,p.x,p.y)
                if zone and not seen[zone] then seen[zone]=true;e.words=e.words.." "..zone:lower() end
            end
        end
    end
    -- A category of one place is that place.
    local kept={}
    for _,e in ipairs(list) do if not (e.kind=="category" and #e.places<2 and not e.key:find("^mine:")) then kept[#kept+1]=e end end
    self.entries,self.entriesData=kept,d
    return kept
end
-- The nearest place of an entry from a point (cont, x, y): place, yards
-- (nil on another continent or without a position).
function C.Nearest(e,cont,x,y)
    local best,bestD
    for _,p in ipairs(e.places) do
        if cont and p.cont==cont then
            local d=C.Yards(cont,x,y,p.x,p.y)
            if not bestD or d<bestD then best,bestD=p,d end
        end
    end
    return best or e.places[1],bestD
end

-- The search: entries matching every word, best first (the whole name,
-- the name's start, a word's start, anywhere; then the nearer), at most
-- MAX; when none, those a letter or two off (fuzzy). Returns {{entry,
-- place (nearest), yards, fuzzy}} or nil, why.
-- The suite's windows and settings (Florian 2026-10-11: Spotlight also
-- opens things): the minimap launcher's entries, every settings page,
-- Route Studio, the tour, reloading. Asked anew each search (a module's
-- entries come and go with it). Kind "action": run, no places.
function C:Actions()
    local out,seen={},{}
    local function add(key,name,detail,symbol,run,words)
        if type(name)~="string" or seen[name:lower()] or type(run)~="function" then return end
        seen[name:lower()]=true
        out[#out+1]={key="do:"..key,name=name,detail=detail,kind="action",symbol=symbol,run=run,places={},
            words=(name.." "..detail.." "..(words or "")):lower()}
    end
    local L=ns.Launcher
    if L and L.Entries then
        for _,e in ipairs(L:Entries()) do
            add(tostring(e.id),e.label,e.state and "Switch" or "Window",e.id=="settings" and "settings" or "layout-dashboard",e.onClick,"open")
        end
    end
    local cmds=ns.Commands and ns.Commands.aliases or {}
    if cmds.routestudio then add("routestudio","Route Studio","Window","layout-dashboard",function() cmds.routestudio.run("") end,"open routing editor") end
    add("tour","Tour","Window","layout-dashboard",function() C.Tour:Ensure();C.Tour.Window:Open() end,"codex open")
    local Config=ns.Config
    if Config and Config.OpenPage then
        add("page:appearance","Global Settings","Settings","sliders-horizontal",function() Config:OpenPage("appearance") end,"options appearance")
        add("page:profiles","Profiles","Settings","sliders-horizontal",function() Config:OpenPage("profiles") end,"options")
        for _,id in ipairs(Config.moduleOrder or {}) do
            local d=Config.modulePages and Config.modulePages[id]
            if type(d)=="table" and type(d.title)=="string" then
                add("page:"..id,d.title.." settings","Settings","sliders-horizontal",function() Config:OpenPage(id) end,"options "..id)
            end
        end
    end
    add("reload","Reload interface","Command","refresh-cw",function() call("ReloadUI") end,"reloadui rl")
    return out
end
C.MAX=12
function C:Search(text,limit)
    local entries=self:Entries()
    text=type(text)=="string" and text:lower():match("^%s*(.-)%s*$") or ""
    if text=="" then return entries and {} or nil,"The places come from BV Map Data: install or enable it." end
    local words={}
    for w in text:gmatch("%S+") do words[#words+1]=w end
    local cont,x,y=self:Here()
    local found={}
    local function consider(e,fuzzy)
        do
            local name=e.name:lower()
            local score=name==text and 100 or name:sub(1,#text)==text and 80 or (" "..name):find(" "..words[1],1,true) and 60 or 40
            -- A whole title a little before one of its people.
            if e.kind=="category" then score=score+5 end
            -- A window by its name before places that merely contain it.
            if e.kind=="action" and score>=80 then score=score+10 end
            if fuzzy then score=score-30 end
            local p,d=C.Nearest(e,cont,x,y)
            found[#found+1]={entry=e,place=p,yards=d,score=score,fuzzy=fuzzy}
        end
    end
    for _,list in ipairs({entries or {},self:Actions()}) do
        for _,e in ipairs(list) do
            local all=true
            for _,w in ipairs(words) do if not e.words:find(w,1,true) then all=false;break end end
            if all then consider(e) end
        end
    end
    if not entries and #found==0 then return nil,"The places come from BV Map Data: install or enable it." end
    -- Nothing: perhaps mistyped.
    if #found==0 and #text>=4 then
        for _,e in ipairs(self:Fuzzy(words)) do consider(e,true) end
    end
    table.sort(found,function(a,b)
        if a.score~=b.score then return a.score>b.score end
        if (a.yards~=nil)~=(b.yards~=nil) then return a.yards~=nil end
        if a.yards and b.yards and a.yards~=b.yards then return a.yards<b.yards end
        return a.entry.name<b.entry.name
    end)
    local out={}
    for i=1,math.min(#found,limit or C.MAX) do out[i]=found[i] end
    return out
end
-- Typing errors (Florian 2026-10-11: "go wild"): when nothing matches,
-- each word may be one letter off (two in long words) a word of the entry.
local function near(a,b,most)
    local la,lb=#a,#b
    if math.abs(la-lb)>most then return false end
    local prev={}
    for j=0,lb do prev[j]=j end
    for i=1,la do
        local cur={[0]=i}
        local low=i
        for j=1,lb do
            local cost=a:sub(i,i)==b:sub(j,j) and 0 or 1
            cur[j]=math.min(prev[j]+1,cur[j-1]+1,prev[j-1]+cost)
            if cur[j]<low then low=cur[j] end
        end
        if low>most then return false end
        prev=cur
    end
    return prev[lb]<=most
end
C.Near=near
function C:Fuzzy(words)
    local out={}
    for _,e in ipairs(self:Entries() or {}) do
        local all=true
        for _,w in ipairs(words) do
            local most=#w>=7 and 2 or #w>=4 and 1 or 0
            local hit=e.words:find(w,1,true)~=nil
            local first=w:byte(1)
            if not hit and most>0 then
                for word in e.words:gmatch("%S+") do
                    -- The first letter right (typos rarely are there): quick.
                    if word:byte(1)==first and (near(w,word:sub(1,#w+most),most) or near(w,word,most)) then hit=true;break end
                end
            end
            if not hit then all=false;break end
        end
        if all then out[#out+1]=e end
    end
    return out
end
-- Suggestions for an empty field: what you chose lately, then your class
-- trainer and the places everyone needs.
C.COMMON={"mine:classtrainer","title:banker","title:auctioneer","title:flight master","title:innkeeper","title:mailbox"}
C.RECENT=6
function C:Remember(e)
    if type(BVCodexDB)~="table" then BVCodexDB={} end
    local list=type(BVCodexDB.recent)=="table" and BVCodexDB.recent or {}
    for i=#list,1,-1 do if list[i]==e.key then table.remove(list,i) end end
    table.insert(list,1,e.key)
    while #list>C.RECENT do table.remove(list) end
    BVCodexDB.recent=list
end
function C:Suggestions()
    local cont,x,y=self:Here()
    local out,seen={},{}
    local recent=type(BVCodexDB)=="table" and type(BVCodexDB.recent)=="table" and BVCodexDB.recent or {}
    local function add(key,why)
        if seen[key] then return end
        local e=self:Entry(key)
        if not e then return end
        seen[key]=true
        local p,d=C.Nearest(e,cont,x,y)
        out[#out+1]={entry=e,place=p,yards=d,why=why}
    end
    -- Quests of your log that are done: where to turn them in, first; with
    -- two or more, all of them at once as a tour (best order).
    local done={}
    for _,title in ipairs(self:Done()) do
        local e=self:Entry("turnin:"..title)
        if e then done[#done+1]=e end
    end
    if #done>=2 then
        out[#out+1]={entry={key="bundle:done",name="Turn in all done quests",detail=#done.." quests",kind="bundle",
            entries=done,places={},words="turn in all done quests"},why="done"}
    end
    for _,e in ipairs(done) do add(e.key,"done") end
    for _,key in ipairs(recent) do add(key,"recent") end
    for _,key in ipairs(C.COMMON) do add(key,"common") end
    while #out>C.MAX do table.remove(out) end
    return out
end
-- The titles of the quests in your log that are done (ready to turn in).
function C:Done()
    local out={}
    local n=call("GetNumQuestLogEntries")
    for i=1,type(n)=="number" and n or 0 do
        local title,_,_,header,_,complete=call("GetQuestLogTitle",i)
        if type(title)=="string" and not header and complete==1 then out[#out+1]=title end
    end
    return out
end
-- An entry by its key (a tour keeps keys).
function C:Entry(key)
    for _,e in ipairs(self:Entries() or {}) do if e.key==key then return e end end
end
