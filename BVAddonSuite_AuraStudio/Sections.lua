-- Canvas sections (roadmap P11): named, coloured frames around nodes. A node
-- belongs to the section that contains its top-left corner; sections never
-- overlap, so membership is unambiguous. Section Mute/Bypass add to a node's
-- own Mute/Bypass and never change node settings.
local _,A=...
if A.blocked then return end
local G=A.G
local Sec={max=32,minWidth=160,minHeight=100,header=30};A.Sections=Sec
Sec.colors={"4A90D9","D9A441","5CB85C","D9534F","9B59B6","7F8C8D"}
local function number(v,lo,hi) return G.Number(v) and v>=lo and v<=hi end
function Sec.Valid(s)
    if type(s)~="table" then return false end
    for k in pairs(s) do if not ({id=true,name=true,color=true,x=true,y=true,width=true,height=true,muted=true,bypassed=true})[k] then return false end end
    return type(s.id)=="string" and #s.id>0 and #s.id<=32 and not s.id:find("[^%w_]")
        and type(s.name)=="string" and #s.name<=40 and not s.name:find("[%c|]")
        and type(s.color)=="string" and #s.color==6 and not s.color:find("[^%x]")
        and number(s.x,-1000000,1000000) and number(s.y,-1000000,1000000)
        and number(s.width,Sec.minWidth,20000) and number(s.height,Sec.minHeight,20000)
        and type(s.muted)=="boolean" and type(s.bypassed)=="boolean"
end
function Sec.Overlap(a,b)
    return a.x<b.x+b.width and b.x<a.x+a.width and a.y<b.y+b.height and b.y<a.y+a.height
end
-- Nil or a message; used by editing and by transfer validation.
function Sec.Check(list)
    if list==nil then return end
    if type(list)~="table" or #list>Sec.max then return "At most "..Sec.max.." sections" end
    for k in pairs(list) do if type(k)~="number" or k<1 or k>#list or k~=math.floor(k) then return "Invalid section list" end end
    local ids={}
    for i,s in ipairs(list) do
        if not Sec.Valid(s) then return "Invalid section" end
        if ids[s.id] then return "Duplicate section" end;ids[s.id]=true
        for j=i+1,#list do if Sec.Valid(list[j]) and Sec.Overlap(s,list[j]) then return "Sections cannot overlap" end end
    end
end
function Sec.Contains(s,n) return n.x>=s.x and n.x<=s.x+s.width and n.y>=s.y and n.y<=s.y+s.height end
function Sec.Members(graph,s)
    local out={}
    for id,n in pairs(graph.nodes or {}) do if Sec.Contains(s,n) then out[#out+1]=id end end
    table.sort(out);return out
end
function Sec.Find(graph,id)
    for i,s in ipairs(graph.sections or {}) do if s.id==id then return s,i end end
end
-- Node ids muted or bypassed by their section.
function Sec.Effects(graph)
    local mute,bypass={},{}
    for _,s in ipairs(graph.sections or {}) do
        if s.muted or s.bypassed then
            for _,id in ipairs(Sec.Members(graph,s)) do
                if s.muted then mute[id]=true end
                if s.bypassed then bypass[id]=true end
            end
        end
    end
    return mute,bypass
end
function Sec.NextId(graph)
    local used={};for _,s in ipairs(graph.sections or {}) do used[s.id]=true end
    local i=1;while used["s"..i] do i=i+1 end
    return "s"..i
end
