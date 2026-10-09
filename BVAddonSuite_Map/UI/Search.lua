local _,P=...
if not P.ready then return end
-- Map search (none of the leading map addons has one): a magnifier at the
-- map's top left opens a field; results come from the client only: zones of
-- the map tree, points of interest and flight points of the shown map, and
-- quests of your log. Click opens the map there; right-click (or Shift) sets
-- a waypoint where the result has a position.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local S={rows={}}
P.Search=S
local MAX=8

function S:Build()
    local map=P:WorldMap()
    if self.button or not map then return end
    local parent=map.ScrollContainer or map
    UI:WithStyle(P:Style(),function()
        self.button=P:MapButton(parent,"search",function() S:Toggle() end)
        M.Point(self.button,"TOPLEFT",parent,"TOPLEFT",6,-6)
        UI:AttachTooltip(self.button,"Search the map","Zones, points of interest, flight points and your quests.")
        self.box=UI:GamePanel(P.ID,parent,280,36,"bg",4,function() return .92 end)
        self.box:SetFrameLevel(P.BUTTONLEVEL+5);self.box:EnableMouse(true);self.box:Hide()
        M.Point(self.box,"TOPLEFT",self.button,"TOPRIGHT",4,0)
        self.input=UI:Input(self.box,264,function() S:Pick(1,false) end)
        self.input:SetMaxLetters(60)
        M.Point(self.input,"TOPLEFT",self.box,"TOPLEFT",8,-2)
        self.input:HookScript("OnTextChanged",function() S:Update() end)
        self.input:HookScript("OnEscapePressed",function() S:Close() end)
        for i=1,MAX do
            local row=CreateFrame("Button",nil,self.box);row:RegisterForClicks("LeftButtonUp","RightButtonUp")
            M.Size(row,264,20);M.Point(row,"TOPLEFT",self.box,"TOPLEFT",8,-38-(i-1)*20)
            row.text=UI:Label(row,"",12,"text");M.Point(row.text,"LEFT",row,"LEFT",4,0);M.Size(row.text,200,20);row.text:SetWordWrap(false)
            row.kind=UI:Label(row,"",10,"muted");M.Point(row.kind,"RIGHT",row,"RIGHT",-4,0);M.Size(row.kind,60,20)
            row.kind:SetJustifyH("RIGHT")
            row.hover=row:CreateTexture(nil,"BACKGROUND");row.hover:SetAllPoints(row);row.hover:SetTexture("Interface\\Buttons\\WHITE8X8");row.hover:Hide()
            row:SetScript("OnEnter",function() row.hover:Show() end)
            row:SetScript("OnLeave",function() row.hover:Hide() end)
            row:SetScript("OnClick",function(_,button) S:Pick(i,button=="RightButton" or (IsShiftKeyDown and IsShiftKeyDown())) end)
            row:Hide()
            self.rows[i]=row
        end
    end)
end
function S:Toggle()
    if self.box:IsShown() then return self:Close() end
    self.box:Show();self.input:SetText("");self.input:SetFocus();self:Update()
end
function S:Close()
    if self.box then self.box:Hide();self.input:ClearFocus() end
end

-- Results for a text, best first: zones, places on the shown map, quests.
function S:Results(text)
    local out={}
    if type(text)~="string" then text="" end
    text=text:lower():gsub("^%s+",""):gsub("%s+$","")
    if #text<2 then return out end
    for _,zone in ipairs(P.Zones:Search(text,4)) do out[#out+1]={kind="Zone",name=zone.name,mapID=zone.mapID} end
    local map=P:WorldMap()
    local mapID=map and map.GetMapID and map:GetMapID()
    local function place(kind,name,position)
        if type(name)~="string" or P.Secret(name) or not name:lower():find(text,1,true) then return end
        local x,y
        if type(position)=="table" or type(position)=="userdata" then local ok,px,py=pcall(position.GetXY,position);if ok then x,y=px,py end end
        out[#out+1]={kind=kind,name=name,mapID=mapID,x=x,y=y}
    end
    if type(mapID)=="number" then
        local pois=P.Call("C_AreaPoiInfo.GetAreaPOIForMap",mapID)
        if type(pois)=="table" then for _,id in ipairs(pois) do local info=P.Call("C_AreaPoiInfo.GetAreaPOIInfo",mapID,id);if type(info)=="table" then place("Place",info.name,info.position) end end end
        local nodes=P.Call("C_TaxiMap.GetTaxiNodesForMap",mapID)
        if type(nodes)=="table" then
            for _,node in ipairs(nodes) do
                if type(node)=="table" and not (P:Config().ownFlights and P.Flights.Hostile(node)) then place("Flight",node.name,node.position) end
            end
        end
    end
    local count=P.Call("C_QuestLog.GetNumQuestLogEntries")
    for index=1,(type(count)=="number" and count or 0) do
        local info=P.Call("C_QuestLog.GetInfo",index)
        if type(info)=="table" and not info.isHeader and type(info.title)=="string" and not P.Secret(info.title) and info.title:lower():find(text,1,true) then
            local questMap=P.Call("GetQuestUiMapID",info.questID)
            out[#out+1]={kind="Quest",name=info.title,mapID=type(questMap)=="number" and questMap~=0 and questMap or nil,questID=info.questID}
        end
    end
    while #out>MAX do table.remove(out) end
    return out
end
function S:Update()
    if not (self.box and self.box:IsShown()) then return end
    self.results=self:Results(self.input:GetText())
    local s=P:Style()
    local ar,ag,ab=s:Color("accent")
    for i,row in ipairs(self.rows) do
        local result=self.results[i]
        if result then
            row.text:SetText(result.name);row.kind:SetText(result.kind);row.hover:SetVertexColor(ar,ag,ab,.18);row:Show()
        else row:Hide() end
    end
    M.Size(self.box,280,40+#self.results*20)
end
-- Opens the map at the result; waypoint: a position (or the quest's objective).
function S:Pick(index,waypoint)
    local result=self.results and self.results[index]
    if not result then return end
    local map=P:WorldMap()
    if waypoint then
        if result.questID then P.Waypoints:Quest(result.questID,result.name)
        elseif result.x then P.Waypoints:Add({mapID=result.mapID,x=result.x,y=result.y,title=result.name})
        else P:Print("No exact position for "..result.name..".") end
    end
    if result.mapID and map and map.SetMapID then pcall(map.SetMapID,map,result.mapID) end
    self:Close()
end

function S:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() S:Apply() end)
        map:HookScript("OnHide",function() S:Close() end)
    end
    context:Defer(function() S:Close();if S.button then S.button:Hide() end end)
    self:Apply()
end
-- The magnifier follows the switch.
function S:Apply()
    local on=P:Active() and P:Config().search
    if on then self:Build() end
    if self.button then self.button:SetShown(on==true) end
    if not on then self:Close() end
end
