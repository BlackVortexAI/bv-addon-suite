local _,Routing=...
if not Routing.ready then return end
-- On which level you are (docs/module-structure-routing.md, "Ebenen und
-- Uebergaenge"). The client gives no height (z is 0; level probe 2026-10-10),
-- so the level comes from what happened: a transition you took sets it
-- (Navigate, Route Studio's recording), the subzone checks it. A level is
-- Route Studio's own element: levels[mapID] = {id, name, subzones = {...}}
-- (Routing.lua, Store); nil is the ground. Its subzones are cues: in one
-- of them, on that map, you are on that level when no other level of the
-- map names the same subzone.
local L={}
Routing.Level=L

-- The map and its parents (a level of Undercity's map also counts while the
-- client names a part of it).
function L.Chain(mapID)
    local out,guard={},0
    while type(mapID)=="number" and mapID>0 and guard<6 do
        out[#out+1]=mapID
        local info=Routing.Call("C_Map.GetMapInfo",mapID)
        mapID=type(info)=="table" and info.parentMapID or nil
        guard=guard+1
    end
    return out
end
-- A level by its id, and the map it belongs to.
function L:Find(id)
    if id==nil then return nil end
    for mapID,list in pairs(Routing:Data().levels) do
        if type(list)=="table" then
            for _,level in ipairs(list) do if level.id==id then return level,mapID end end
        end
    end
    return nil
end
-- Districts (Florian 2026-10-10: riding the lift down, the game names
-- "Trade Quarter"): what the game says where you are, the subzone and the
-- minimap's zone text, both but the zone's own name (it is everywhere).
-- A level's districts are kept in level.subzones.
function L.Here()
    local out,seen={},{}
    local zone=Routing.Call("GetZoneText")
    for _,path in ipairs({"GetSubZoneText","GetMinimapZoneText"}) do
        local text=Routing.Call(path)
        if type(text)=="string" and text~="" and not Routing.Secret(text) and text~=zone and not seen[text] then
            seen[text]=true;out[#out+1]=text
        end
    end
    return out
end
local function names(level,texts)
    if type(level.subzones)~="table" then return false end
    for _,name in ipairs(level.subzones) do
        for _,text in ipairs(texts) do if name==text then return true end end
    end
    return false
end
-- The level you are on now (its id), or nil for the ground.
function L:Current()
    local mapID=Routing:Position()
    if not mapID then return self.id end
    local chain=L.Chain(mapID)
    local here=L.Here()
    local cue
    for _,map in ipairs(chain) do
        for _,level in ipairs(Routing:ReadLevels(map)) do
            if names(level,here) then cue=(cue==nil) and level or false end
        end
    end
    -- A transition just taken (or /bv route level) counts until you are in
    -- another district (Florian's probe 2026-10-11: just through the
    -- passage into the city, still in "Ruins of Lordaeron", the entrance's
    -- district put the level back).
    local where=table.concat(here,"|")
    if self.setWhere and self.setWhere~=where then self.setWhere=nil end
    if cue and not (self.setWhere and cue.id~=self.id) then
        if self.id~=cue.id then self.id=cue.id;self:Remember() end
        self.sure=true
        return self.id
    end
    -- Sure: a district or a transition just taken told it (the height is
    -- learned only then).
    self.sure=self.setWhere~=nil
    -- The level kept does not fit your height, another near one alone does
    -- (Florian's probe 2026-10-11): that one (not sure). A level's height is
    -- a hint, not a fact (Florian 2026-10-11: one per level; where it does
    -- not hold, the level is split): only after HEIGHTVOTES measurements in
    -- a row say so.
    -- Florian 2026-10-11 (on Bank Level, kept on Entrance 110 yd above):
    -- two near levels both fitting (Bank Level and First Level, 12 yd
    -- apart) let the wrong one stay. Now the nearest fitting level by
    -- height, else none (unknown is better than a level the height denies).
    local H=Routing.Height
    local voted=false
    if self.id~=nil and H and H:FitsLevel(self.id)==false then
        local pick=self:ByHeight(mapID) or self:ByHeight(mapID,true)
        if pick~=self.id then
            voted=true
            if H.nowAt~=self.voteAt then self.voteAt=H.nowAt;self.votes=(self.votes or 0)+1 end
            if self.votes>=L.HEIGHTVOTES then
                self.id,self.setWhere,self.sure,self.votes=pick,nil,false,0
                if pick then self:Remember() end
                local probe=Routing.Probe
                if probe and probe.on then probe:Note("level by your height: "..(pick and self:Name(pick) or "unknown (none fits)")) end
                return pick
            end
        end
    end
    if not voted then self.votes=0 end
    -- Once a session: the level kept from before (a reload, a login).
    if self.id==nil and not self.recalled then self.recalled=true;self:Recall() end
    if self.id then
        local level,map=self:Find(self.id)
        local here=false
        for _,m in ipairs(chain) do if m==map then here=true end end
        -- Kept while you are on its map and not in a subzone it does not
        -- name (no subzone at all tells nothing).
        local listed=type(level and level.subzones)=="table" and #level.subzones>0
        -- (named: "here" is whether you are on its map, the districts are names)
        if level and here and (not listed or #L.Here()==0 or names(level,L.Here()) or self.setWhere) then return self.id end
        -- In a district it does not name, but your height fits it (NPCs near).
        if level and here and Routing.Height and Routing.Height:FitsLevel(self.id)==true then return self.id end
    end
    self.id=nil
    -- None known: the one level near whose height fits yours (Florian's
    -- probe 2026-10-11: in the Trade Quarter only First Level fitted, the
    -- level stayed unknown). Not sure: nothing is learned from it.
    local pick=self:ByHeight(mapID)
    if pick then self.id=pick;return pick end
    return nil
end
-- The only level with a street near you whose height fits yours (NPCs
-- near, Height); nil when none or several fit, or the ground does too.
-- nearest: of those that fit (the ground too), the one whose height lies
-- nearest the band's middle (nil when the ground or none).
function L:ByHeight(mapID,nearest)
    local H,N=Routing.Height,Routing.Navigate
    if not (H and N and N.Candidates) then return nil end
    local m=H:Now()
    local span=H.Span(m.set)
    if not span or span>H.SPAN then return nil end
    local _,x,y=Routing:Position()
    local cont,cx,cy=Routing:OnContinent(mapID,x,y)
    if not cont then return nil end
    local fits,ground={},false
    local _,low,high=H.Span(m.set)
    local mid=(low+high)/2
    local best,bestOff
    for _,cand in ipairs(N:Candidates(cont,cx,cy)) do
        if H:FitsLevel(cand.level or nil,cont,cx,cy)==true then
            if cand.level then fits[cand.level]=true else ground=true end
            -- A level without a height known counts with the ground's (as before).
            local off=cand.level and self:Off(cand.level,mid,cont,cx,cy)
            if off==nil then
                local z=N.GroundHeight(cont,cx,cy)
                off=type(z)=="number" and math.abs(z-mid) or nil
            end
            if off and (not bestOff or off<bestOff) then best,bestOff=cand.level or false,off end
        end
    end
    if nearest then return best or nil end
    local only,count=nil,0
    for id in pairs(fits) do only,count=id,count+1 end
    return (count==1 and not ground) and only or nil
end
-- What the subzone alone says: the level it names (unique on your map),
-- or nil when it names none (no cue).
function L:Cue()
    local levels=self:CueLevels()
    local only,count=nil,0
    for id in pairs(levels) do only,count=id,count+1 end
    return count==1 and only or nil
end
-- Every level of your map whose districts name where you are: {[id]=true}
-- (several: they narrow it down; Navigate picks among them by the street).
function L:CueLevels()
    local out={}
    local mapID=Routing:Position()
    if not mapID then return out end
    local here=L.Here()
    if #here==0 then return out end
    for _,map in ipairs(L.Chain(mapID)) do
        for _,level in ipairs(Routing:ReadLevels(map)) do
            if names(level,here) then out[level.id]=true end
        end
    end
    return out
end
-- A transition took you to a level (nil: the ground); kept for the next
-- session too.
function L:Set(id)
    self.id=id
    -- Where it was set: the districts there do not overrule it.
    self.setWhere=table.concat(L.Here(),"|")
    self:Remember()
end
-- Your level kept per character with where you stood (Florian 2026-10-10:
-- inside Undercity after a reload nobody can tell the level): after a
-- reload or a login it counts again while you stand within RECALL yards.
L.RECALL=40
L.HEIGHTVOTES=3   -- measurements in a row against your level before the height changes it
function L:Remember()
    self:WatchLogout()
    local mapID,x,y=Routing:Position()
    if not mapID then return end
    local db=Routing:Store()
    db.where=type(db.where)=="table" and db.where or {}
    db.where[Routing:Author()]={level=self.id or false,map=mapID,x=x,y=y,at=time()}
end
-- At a reload or logout: your level kept where you stand now (Florian
-- 2026-10-13: after a reload in Undercity's canals Routing did not know the
-- level; it was kept only where it had last changed, 40 yards and more
-- away). Nothing kept while it is unknown.
-- (Watched from the first level known on: nothing runs for players who
-- never have one.)
function L:WatchLogout()
    if self.watchingLogout or not (Routing.ns and Routing.ns.Events) then return end
    self.watchingLogout=true
    Routing.ns.Events:Subscribe(L,"PLAYER_LOGOUT",function() if L.id~=nil then L:Remember() end end)
end
function L:Recall()
    local db=Routing:Store()
    local kept=type(db.where)=="table" and db.where[Routing:Author()]
    if type(kept)~="table" or not kept.level then return nil end
    local mapID,x,y=Routing:Position()
    if not mapID or not self:Find(kept.level) then return nil end
    local kx,ky=kept.x,kept.y
    if kept.map~=mapID then kx,ky=Routing.Grid.Convert(kept.map,mapID,kept.x,kept.y) end
    if not kx then return nil end
    local w,h=Routing.Call("C_Map.GetMapWorldSize",mapID)
    if type(w)~="number" or w<=0 then w,h=1000,1000 end
    local dx,dy=(x-kx)*w,(y-ky)*h
    if math.sqrt(dx*dx+dy*dy)>L.RECALL then return nil end
    self.id=kept.level
    return self.id
end
-- A level of your map by its name (case does not matter; the start of it
-- will do when only one level starts so); "ground" is the ground. Returns
-- the id (nil: the ground) and whether one was found.
function L:Named(text)
    text=type(text)=="string" and text:lower():match("^%s*(.-)%s*$") or ""
    if text=="ground" then return nil,true end
    local mapID=Routing:Position()
    if not mapID then return nil,false end
    local exact,starts,count
    count=0
    for _,map in ipairs(L.Chain(mapID)) do
        for _,level in ipairs(Routing:ReadLevels(map)) do
            local name=type(level.name)=="string" and level.name:lower() or ""
            if name==text then exact=level.id end
            if name:sub(1,#text)==text then starts=level.id;count=count+1 end
        end
    end
    if exact then return exact,true end
    if count==1 then return starts,true end
    return nil,false
end
-- A level's height (Florian 2026-10-11: Map Data knows how high every NPC
-- stands): set by hand (level.z), else learned on the way (Height:Learn,
-- once enough), else the middle height of the Map Data NPCs standing still
-- on its streets and given ways (its posts; older data: its NPC groups).
-- Returns the height (world yards), "set", "learned" or "npcs", and how
-- many told it; nil without any.
-- Kept per level until its strokes or ways change.
L.heights={}
L.NEAR=6          -- yards beyond a stroke's edge, or from a way, an NPC still stands on it
local function field(list,name) for i,f in ipairs(list or {}) do if f==name then return i end end end
-- A level's heights from its lowest to its highest street (level.lo and
-- level.hi, Claude 2026-10-12: generated levels on a slope, a valley rising
-- 20 yards); without them its one height (Height). nil: none known.
function L:Span(id)
    local level=self:Find(id)
    if level and type(level.lo)=="number" and type(level.hi)=="number" and level.hi>=level.lo then return level.lo,level.hi end
    local z=self:Height(id)
    if type(z)~="number" then return nil end
    return z,z
end
-- A level's heights where you are (Claude 2026-10-12: a generated level
-- runs from a valley floor up a hill): its height samples (level.heights:
-- x, y, lo, hi per sample on its map) within SAMPLE yards; without any near,
-- its span (Span).
L.SAMPLE=14
function L:SpanAt(id,cont,cx,cy)
    local level,mapID=self:Find(id)
    local list=level and level.heights
    if type(list)=="table" and #list>=4 and cont and mapID and type(cx)=="number" then
        local mx,my=Routing.Grid.Convert(cont,mapID,cx,cy)
        if mx then
            local w,h=Routing.Call("C_Map.GetMapWorldSize",mapID)
            if type(w)~="number" or w<=0 then w,h=1000,1000 end
            local lo,hi
            local r2=L.SAMPLE*L.SAMPLE
            for i=1,#list-3,4 do
                local dx,dy=(list[i]-mx)*w,(list[i+1]-my)*h
                if dx*dx+dy*dy<=r2 then
                    local a,b=list[i+2],list[i+3]
                    if type(a)=="number" and type(b)=="number" then lo=math.min(lo or a,a);hi=math.max(hi or b,b) end
                end
            end
            if lo then return lo,hi end
        end
    end
    return self:Span(id)
end
-- Yards from a height to a level's (0 within its span); nil: none known.
-- With a place (cont, cx, cy): its heights there (SpanAt).
function L:Off(id,z,cont,cx,cy)
    local lo,hi
    if cont then lo,hi=self:SpanAt(id,cont,cx,cy) else lo,hi=self:Span(id) end
    if not lo or type(z)~="number" then return nil end
    if z<lo then return lo-z end
    if z>hi then return z-hi end
    return 0
end
function L:Height(id)
    local level,mapID=self:Find(id)
    if not level then return nil end
    if type(level.z)=="number" then return level.z,"set",0 end
    if Routing.Height then
        local learned,count=Routing.Height:Learned(id)
        if learned then return learned,"learned",count end
    end
    local d=rawget(_G,"BVMapData")
    local zi=d and d.fields and field(d.fields.npc,"z")
    if not (zi and type(d.npc)=="table") then return nil end
    local strokes,ways,areas={},{},{}
    for _,st in ipairs(Routing:ReadStrokes(mapID)) do
        if st.level==id and st.kind=="prefer" and not st.poly and type(st.x)=="number" then strokes[#strokes+1]=st end
        if st.level==id and st.kind=="prefer" and type(st.poly)=="table" and #st.poly>=6 then areas[#areas+1]=st end
    end
    for _,way in ipairs(Routing:ReadWays(mapID)) do if way.level==id and type(way.points)=="table" then ways[#ways+1]=way end end
    local key=#strokes..":"..#ways..":"..#areas..":"..tostring(d)
    local kept=self.heights[id]
    if kept and kept.key==key then return kept.z,kept.z and "npcs" or nil,kept.n end
    -- The streets' box on the map first: only NPCs in it are looked at.
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local function grow(x,y) minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y) end
    for _,st in ipairs(strokes) do grow(st.x,st.y) end
    for _,way in ipairs(ways) do for i=1,#way.points-1,2 do grow(way.points[i],way.points[i+1]) end end
    for _,area in ipairs(areas) do for i=1,#area.poly-1,2 do grow(area.poly[i],area.poly[i+1]) end end
    local zs={}
    if minX<=maxX then
        local w,h=Routing.Call("C_Map.GetMapWorldSize",mapID)
        if type(w)~="number" or w<=0 then w,h=1000,1000 end
        local pad=40/w
        -- NPCs standing still (Map Data's posts; older data: its NPC groups).
        local pts={}
        for cont,list in pairs(d.npc) do
            local posts=d.posts and Routing.Height and Routing.Height:Posts(cont)
            if posts then
                for _,group in pairs(posts) do for _,e in ipairs(group) do pts[#pts+1]={cont,e.x,e.y,e.z} end end
            elseif type(list)=="table" then
                local stride=#d.fields.npc
                for i=0,#list-stride,stride do pts[#pts+1]={cont,list[i+1],list[i+2],list[i+zi]} end
            end
        end
        do
            do
                for _,pt in ipairs(pts) do
                    local mx,my=Routing.Grid.Convert(pt[1],mapID,pt[2],pt[3])
                    if mx and mx>=minX-pad and mx<=maxX+pad and my>=minY-pad and my<=maxY+pad then
                        local on=false
                        for _,area in ipairs(areas) do if Routing.Grid.Inside(area.poly,mx,my) then on=true;break end end
                        for _,st in ipairs(strokes) do
                            local dx,dy=(mx-st.x)*w,(my-st.y)*h
                            if dx*dx+dy*dy<=((st.r or 0)+L.NEAR)^2 then on=true;break end
                        end
                        if not on then
                            for _,way in ipairs(ways) do
                                local q=way.points
                                for k=1,#q-3,2 do
                                    local ax,ay,bx,by=q[k]*w,q[k+1]*h,q[k+2]*w,q[k+3]*h
                                    local px,py=mx*w,my*h
                                    local vx,vy=bx-ax,by-ay
                                    local len=vx*vx+vy*vy
                                    local t=len>0 and math.max(0,math.min(1,((px-ax)*vx+(py-ay)*vy)/len)) or 0
                                    local ex,ey=ax+vx*t-px,ay+vy*t-py
                                    if ex*ex+ey*ey<=L.NEAR*L.NEAR then on=true;break end
                                end
                                if on then break end
                            end
                        end
                        local z=pt[4]
                        if on and type(z)=="number" then zs[#zs+1]=z end
                    end
                end
            end
        end
    end
    table.sort(zs)
    local z=#zs>0 and zs[math.floor((#zs+1)/2)] or nil
    self.heights[id]={key=key,z=z,n=#zs}
    return z,z and "npcs" or nil,#zs
end
-- A level's name for the player ("Ground" for nil).
function L:Name(id)
    if id==nil then return "Ground" end
    local level=self:Find(id)
    return level and level.name or "?"
end
-- A level as the player is told it (Florian 2026-10-12: "go through to
-- Mage Down" says little in the game; the short names stay for Route
-- Studio's narrow lists): the name given for that (level.shown), else its
-- one district ("the Magic Quarter"), else its name; the ground "outside".
function L:Shown(id)
    if id==nil then return "outside" end
    local level=self:Find(id)
    if not level then return "?" end
    if type(level.shown)=="string" and level.shown:match("%S") then return level.shown end
    local subs=type(level.subzones)=="table" and level.subzones or {}
    if #subs==1 and type(subs[1])=="string" then
        local name=subs[1]
        return name:match("^[Tt]he ") and name or "the "..name
    end
    return level.name or "?"
end
-- Up or down from one level to another, by their heights (the ground: the
-- terrain where the transition is); nil when they lie about as high or a
-- height is unknown.
L.STEP=4
function L:Way(from,to,cont,x,y)
    local function z(id)
        if id==nil then
            local N=Routing.Navigate
            return cont and N.GroundHeight and N.GroundHeight(cont,x,y) or nil
        end
        return (self:Height(id))
    end
    local a,b=z(from),z(to)
    if type(a)~="number" or type(b)~="number" or math.abs(b-a)<L.STEP then return nil end
    return b>a and "up" or "down"
end
