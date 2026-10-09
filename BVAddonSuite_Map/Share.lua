local _,P=...
if not P.ready then return end
-- Sharing a travel path (plan phase 2b) with the group, the guild or one
-- player over addon messages. The path travels as compact text in small,
-- paced chunks; the receiver always sees a preview first and decides
-- (never imported without a click), and receiving can be switched off.
-- Protocol (tab separated): O id count chunks name | C id index data.
-- Payload: "mapID,x,y,title" per waypoint, joined by ";" (titles cleaned).
local S={prefix="BVMAPPATH1",chunk=200,maxPoints=60,maxChunks=40,pace=.15,incoming={}}
P.Share=S

local function clean(text,max)
    if type(text)~="string" then return nil end
    text=text:gsub("[%c|;,\t~]"," "):gsub("^%s+",""):gsub("%s+$","")
    if text=="" then return nil end
    return text:sub(1,max or 40)
end
function S.Encode(points)
    local parts={}
    for i,point in ipairs(points) do
        if i>S.maxPoints then break end
        parts[#parts+1]=string.format("%d,%.4f,%.4f,%s",point.mapID,point.x,point.y,clean(point.title) or "")
    end
    return table.concat(parts,";")
end
function S.Decode(payload)
    local out={}
    if type(payload)~="string" then return out end
    for item in payload:gmatch("[^;]+") do
        local mapID,x,y,title=item:match("^(%d+),([%d%.]+),([%d%.]+),(.*)$")
        mapID,x,y=tonumber(mapID),tonumber(x),tonumber(y)
        if mapID and x and y and x>=0 and x<=1 and y>=0 and y<=1 then
            out[#out+1]={mapID=mapID,x=x,y=y,title=clean(title)}
            if #out>=S.maxPoints then break end
        end
    end
    return out
end

-- Sending: channel "PARTY"/"RAID" (group), "GUILD" or "WHISPER" with a name.
function S:Send(channel,target,name)
    local list={}
    for _,point in ipairs(P.Waypoints:Queue()) do if not point.corpse then list[#list+1]=point end end
    if #list==0 then P:Print("No waypoints to share.");return false end
    if channel=="GROUP" then
        if P.Call("IsInRaid")==true then channel="RAID" elseif P.Call("IsInGroup")==true then channel="PARTY"
        else P:Print("You are not in a group.");return false end
    end
    if channel=="GUILD" and P.Call("IsInGuild")~=true then P:Print("You are not in a guild.");return false end
    if channel=="WHISPER" and (type(target)~="string" or target=="") then P:Print("Who should get it? Enter a name.");return false end
    local payload=S.Encode(list)
    local chunks={}
    for i=1,#payload,S.chunk do chunks[#chunks+1]=payload:sub(i,i+S.chunk-1) end
    if #chunks>S.maxChunks then P:Print("This path is too long to share.");return false end
    self.seq=(self.seq or 0)+1
    local id=tostring(math.floor((GetTime() or 0)*10)%100000).."-"..self.seq
    local messages={table.concat({"O",id,tostring(math.min(#list,S.maxPoints)),tostring(#chunks),clean(name,40) or "Path"},"\t")}
    for index,data in ipairs(chunks) do messages[#messages+1]=table.concat({"C",id,tostring(index),data},"\t") end
    -- Paced: one message after another, so the client never drops them.
    local i=0
    local function step()
        i=i+1
        local message=messages[i]
        if not message then return end
        P.Call("C_ChatInfo.SendAddonMessage",S.prefix,message,channel,channel=="WHISPER" and target or nil)
        if messages[i+1] then S.timer=C_Timer.NewTimer(S.pace,step) else S.timer=nil end
    end
    step()
    P:Print(string.format("Path shared (%d waypoint%s).",#list,#list==1 and "" or "s"))
    return true
end

-- Receiving: offers collect their chunks; complete ones go to the preview.
local function sameAsMe(sender)
    local me=P.Call("UnitName","player")
    if type(sender)~="string" or type(me)~="string" then return false end
    return sender==me or sender:match("^[^%-]+")==me
end
function S:Receive(prefix,message,channel,sender)
    if prefix~=S.prefix or type(message)~="string" or P.Secret(message) or P.Secret(sender) then return end
    if not P:Config().shareReceive or sameAsMe(sender) then return end
    local fields={}
    for field in (message.."\t"):gmatch("([^\t]*)\t") do fields[#fields+1]=field end
    local kind,id=fields[1],fields[2]
    if not id or id=="" then return end
    if kind=="O" then
        local count,chunks=tonumber(fields[3]),tonumber(fields[4])
        if not (count and chunks) or chunks<1 or chunks>S.maxChunks then return end
        self.incoming[sender..id]={sender=sender,id=id,count=count,chunks=chunks,name=clean(fields[5],40) or "Path",parts={},got=0}
    elseif kind=="C" then
        local offer=self.incoming[sender..id]
        local index=tonumber(fields[3])
        if not (offer and index and index>=1 and index<=offer.chunks) or offer.parts[index] then return end
        offer.parts[index]=fields[4] or ""
        offer.got=offer.got+1
        if offer.got==offer.chunks then
            self.incoming[sender..id]=nil
            offer.points=S.Decode(table.concat(offer.parts))
            if #offer.points>0 then self:Offer(offer) end
        end
    end
end
-- One preview at a time; later offers wait.
function S:Offer(offer)
    self.queue=self.queue or {}
    table.insert(self.queue,offer)
    if #self.queue==1 and P.WaypointList then P.WaypointList:ShowOffer(offer) end
end
function S:Answer(accept,mode)
    local offer=self.queue and table.remove(self.queue,1)
    if offer and accept then
        local name="From "..(offer.sender:match("^[^%-]+") or offer.sender)..": "..offer.name
        P:Config().sets[name]=offer.points
        if mode=="replace" then P.Waypoints:LoadSet(name)
        elseif mode=="append" then for _,point in ipairs(offer.points) do P.Waypoints:Add({mapID=point.mapID,x=point.x,y=point.y,title=point.title},true) end end
        P:Print("Saved as set \""..name.."\".")
    end
    local nextOffer=self.queue and self.queue[1]
    if nextOffer and P.WaypointList then P.WaypointList:ShowOffer(nextOffer) end
end

function S:Enable(context)
    P.Call("C_ChatInfo.RegisterAddonMessagePrefix",S.prefix)
    pcall(context.Subscribe,context,"CHAT_MSG_ADDON",function(_,prefix,message,channel,sender) S:Receive(prefix,message,channel,sender) end)
    context:Defer(function() if S.timer then S.timer:Cancel();S.timer=nil end;S.incoming={} end)
end
