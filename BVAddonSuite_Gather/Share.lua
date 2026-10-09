local _,G=...
if not G.ready then return end
-- Live sharing (plan phase 4; defaults until Florian decides: sending off,
-- receiving on, only from your group and guild). A node you record goes out
-- as one small addon message to the channels you chose; nodes others send
-- are added as "shared" (they show, can be hidden and forgotten in one go,
-- and stop being "shared" once you find them yourself). Messages are paced;
-- nothing personal travels, only kind, map, packed position and name.
-- Message: "N" kind mapID coord name (tab separated).
local S={prefix="BVGATHER1",pace=.5,queue={}}
G.Share=S

local function clean(name)
    if type(name)~="string" then return "" end
    return (name:gsub("[%c|\t]"," "):sub(1,48))
end
-- Channels for sending, from the setting ("off", "group", "guild", "both").
function S:Channels()
    local mode=G:Config().shareSend
    local out={}
    if mode=="group" or mode=="both" then
        if G.Call("IsInRaid")==true then out[#out+1]="RAID" elseif G.Call("IsInGroup")==true then out[#out+1]="PARTY" end
    end
    if (mode=="guild" or mode=="both") and G.Call("IsInGuild")==true then out[#out+1]="GUILD" end
    return out
end
-- A node you recorded yourself goes out (new nodes only, not repeats).
function S:Recorded(kind,mapID,node)
    if not G:Active() then return end
    local channels=self:Channels()
    if #channels==0 then return end
    local message=table.concat({"N",kind,tostring(mapID),string.format("%.0f",G.Data.Encode(node.x,node.y)),clean(node.name)},"\t")
    for _,channel in ipairs(channels) do self.queue[#self.queue+1]={message,channel} end
    self:Pump()
end
function S:Pump()
    if self.timer or #self.queue==0 then return end
    local item=table.remove(self.queue,1)
    G.Call("C_ChatInfo.SendAddonMessage",S.prefix,item[1],item[2])
    self.timer=C_Timer.NewTimer(S.pace,function() S.timer=nil;S:Pump() end)
end
local function me(sender)
    local name=G.Call("UnitName","player")
    if type(sender)~="string" or type(name)~="string" then return false end
    return sender==name or sender:match("^[^%-]+")==name
end
function S:Receive(prefix,message,channel,sender)
    if prefix~=S.prefix or type(message)~="string" or G.Secret(message) or G.Secret(sender) then return end
    if not G:Config().shareReceive or me(sender) then return end
    if channel~="PARTY" and channel~="RAID" and channel~="GUILD" then return end
    local fields={}
    for field in (message.."\t"):gmatch("([^\t]*)\t") do fields[#fields+1]=field end
    if fields[1]~="N" or not G.TYPE[fields[2]] then return end
    local mapID,coord=tonumber(fields[3]),tonumber(fields[4])
    local x,y=G.Data.Decode(coord)
    if not (mapID and x and x>=0 and x<=1 and y>=0 and y<=1) then return end
    local name=fields[5]~="" and fields[5] or nil
    local node,new=G.Data:Add(fields[2],mapID,x,y,name,{import=true,source="shared"})
    if node and new then G.Pins:Refresh() end
end
function S:Enable(context)
    G.Call("C_ChatInfo.RegisterAddonMessagePrefix",S.prefix)
    pcall(context.Subscribe,context,"CHAT_MSG_ADDON",function(_,prefix,message,channel,sender) S:Receive(prefix,message,channel,sender) end)
    context:Defer(function() if S.timer then S.timer:Cancel();S.timer=nil end;S.queue={} end)
end
