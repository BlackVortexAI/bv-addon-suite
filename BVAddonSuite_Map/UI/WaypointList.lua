local _,P=...
if not P.ready then return end
-- Waypoint list window (/way list, the arrow's menu, the settings): the
-- queue with rename, reorder, activate and delete; named sets; import of
-- /way lines (Wowhead lists) and export; sharing the path with the group,
-- the guild or one player, and the preview of a path someone shares with
-- you. With TomTom loaded the queue is TomTom's, so this window only offers
-- the import that hands lines over.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local L={rows={}}
P.WaypointList=L
local ROWS,ROW=12,24

function L:Build()
    if self.dialog then return self.dialog end
    UI:WithStyle(P:Style(),function()
        local d=UI:Dialog("BVMapWaypoints",440,ROWS*ROW+150)
        d.title:SetText("Waypoints")
        local c=d.content
        self.empty=UI:Label(c,"",12,"muted");M.Point(self.empty,"TOPLEFT",c,"TOPLEFT",18,-14);M.Size(self.empty,400,40)
        self.empty:SetWordWrap(true)
        for i=1,ROWS do
            local row=CreateFrame("Button",nil,c);M.Size(row,404,ROW);M.Point(row,"TOPLEFT",c,"TOPLEFT",18,-10-(i-1)*ROW)
            row.index=UI:Label(row,"",11,"muted");M.Point(row.index,"LEFT",row,"LEFT",0,0);M.Size(row.index,22,ROW)
            row.name=UI:Label(row,"",12,"text");M.Point(row.name,"LEFT",row,"LEFT",22,0);M.Size(row.name,190,ROW);row.name:SetWordWrap(false)
            row.where=UI:Label(row,"",11,"muted");M.Point(row.where,"LEFT",row,"LEFT",214,0);M.Size(row.where,100,ROW);row.where:SetWordWrap(false)
            row.edit=UI:Input(row,190,function(text) L:Rename(row,text) end);M.Point(row.edit,"LEFT",row,"LEFT",22,0);row.edit:Hide()
            row.up=UI:Button(row,"Up",40,function() P.Waypoints:Move(row.slot,-1) end,"ghost");M.Point(row.up,"RIGHT",row,"RIGHT",-62,0)
            row.rename=UI:IconButton(row,"edit",function() L:Edit(row) end,"ghost");M.Point(row.rename,"RIGHT",row,"RIGHT",-30,0)
            row.delete=UI:IconButton(row,"close",function() P.Waypoints:Remove(row.slot) end,"ghost");M.Point(row.delete,"RIGHT",row,"RIGHT",-2,0)
            row:SetScript("OnClick",function() P.Waypoints:Choose(row.slot) end)
            UI:AttachTooltip(row,"Waypoint","Click to make it the active waypoint.")
            self.rows[i]=row
        end
        local y=-14-ROWS*ROW
        self.more=UI:Label(c,"",11,"muted");M.Point(self.more,"TOPLEFT",c,"TOPLEFT",18,y);M.Size(self.more,400,16)
        self.import=UI:Button(c,"Import",96,function() L:Transfer("import") end);M.Point(self.import,"TOPLEFT",c,"TOPLEFT",18,y-22)
        self.export=UI:Button(c,"Export",96,function() L:Transfer("export") end);M.Point(self.export,"LEFT",self.import,"RIGHT",8,0)
        self.save=UI:Button(c,"Save as set",110,function() L:Transfer("save") end);M.Point(self.save,"LEFT",self.export,"RIGHT",8,0)
        self.clear=UI:Button(c,"Clear",80,function() P.Waypoints:Clear() end);M.Point(self.clear,"LEFT",self.save,"RIGHT",8,0)
        self.share=UI:Button(c,"Share",80,function() L:ShareMenu(self.share) end);M.Point(self.share,"LEFT",self.clear,"RIGHT",8,0)
        UI:AttachTooltip(self.share,"Share the path","With your group, your guild or one player. They see a preview and decide.")
        self.sets=UI:Dropdown(c,404,{},function(value) L:Set(value) end);M.Point(self.sets,"TOPLEFT",c,"TOPLEFT",18,y-56)
        d:Hide()
        self.dialog=d
    end)
    return self.dialog
end
function L:Toggle()
    local d=self:Build()
    if d:IsShown() then d:Hide() else d:Show();self:Refresh() end
end
function L:Edit(row)
    local point=P.Waypoints:Queue()[row.slot]
    if not point then return end
    row.name:Hide();row.edit:SetText(point.title or "");row.edit:Show();row.edit:SetFocus()
end
function L:Rename(row,text)
    row.edit:Hide();row.name:Show()
    P.Waypoints:Rename(row.slot,text)
end
function L:Refresh()
    local d=self.dialog
    if not (d and d:IsShown()) then return end
    local W=P.Waypoints
    local list,tomtom=W:Queue(),W:TomTom()
    self.empty:SetShown(#list==0 or tomtom~=nil)
    self.empty:SetText(tomtom and "TomTom is loaded: its own list holds the waypoints. Import hands /way lines to TomTom."
        or "No waypoints. /way x y [title], Import (Wowhead lists) or a quest's menu: Waypoint to the objective.")
    for i,row in ipairs(self.rows) do
        local point=not tomtom and list[i]
        row.slot=i
        if point then
            row.index:SetText(tostring(i));row.index:SetTextColor(P:Style():Color(i==1 and "accent" or "muted"))
            row.name:SetText(W:Label(point));row.name:SetTextColor(P:Style():Color(i==1 and "accent" or "text"))
            row.where:SetText(W:MapName(point.mapID).." "..P:Format(point.x,point.y))
            row.up:SetShown(i>1);row.edit:Hide();row.name:Show()
            row:Show()
        else row:Hide() end
    end
    self.more:SetText(not tomtom and #list>ROWS and ("+ "..(#list-ROWS).." more") or "")
    self.export:SetShown(not tomtom);self.save:SetShown(not tomtom);self.clear:SetShown(not tomtom);self.share:SetShown(not tomtom)
    -- Sets: load or delete.
    local options={{value="",label=next(P:Config().sets) and "Load a saved set…" or "No saved sets"}}
    local names={}
    for name in pairs(P:Config().sets) do names[#names+1]=name end
    table.sort(names)
    for _,name in ipairs(names) do
        options[#options+1]={value="load:"..name,label="Load: "..name.." ("..#P:Config().sets[name]..")"}
        options[#options+1]={value="delete:"..name,label="Delete: "..name,danger=true}
    end
    self.sets:SetOptions(options);self.sets:SetValue("")
    self.sets:SetShown(not tomtom)
end
function L:Set(value)
    local kind,name=tostring(value):match("^(%a+):(.+)$")
    if kind=="load" then P.Waypoints:LoadSet(name)
    elseif kind=="delete" then P.Waypoints:DeleteSet(name) end
    self:Refresh()
end
-- Share: group, guild or a player (name asked in the text dialog).
function L:ShareMenu(anchor)
    anchor.bvMenuStyle=P:Style()
    UI:ContextMenu(anchor,{{value="GROUP",label="Share with your group"},{value="GUILD",label="Share with your guild"},{value="WHISPER",label="Share with a player…"}},function(value)
        if value=="WHISPER" then L:Transfer("share") else P.Share:Send(value,nil,L:PathName()) end
    end)
end
function L:PathName()
    local first=P.Waypoints:Queue()[1]
    return first and (first.title or P.Waypoints:MapName(first.mapID)) or "Path"
end
-- A path someone shares: preview, then replace your queue, add to it, keep
-- it only as a set, or decline.
function L:ShowOffer(offer)
    UI:WithStyle(P:Style(),function()
        if not self.offer then
            local d=UI:Dialog("BVMapPathOffer",440,340)
            d.text=UI:Label(d.content,"",12,"text");M.Point(d.text,"TOPLEFT",d.content,"TOPLEFT",18,-14);M.Size(d.text,404,40);d.text:SetWordWrap(true)
            d.list=UI:Label(d.content,"",11,"muted");M.Point(d.list,"TOPLEFT",d.content,"TOPLEFT",18,-60);M.Size(d.list,404,180);d.list:SetWordWrap(true);d.list:SetJustifyV("TOP")
            d.replace=UI:Button(d.content,"Use it",96,function() d:Hide();P.Share:Answer(true,"replace") end,true);M.Point(d.replace,"BOTTOMLEFT",d.content,"BOTTOMLEFT",18,14)
            d.append=UI:Button(d.content,"Add to mine",110,function() d:Hide();P.Share:Answer(true,"append") end);M.Point(d.append,"LEFT",d.replace,"RIGHT",8,0)
            d.keep=UI:Button(d.content,"Save as set",104,function() d:Hide();P.Share:Answer(true,"set") end);M.Point(d.keep,"LEFT",d.append,"RIGHT",8,0)
            d.decline=UI:Button(d.content,"Decline",80,function() d:Hide();P.Share:Answer(false) end);M.Point(d.decline,"LEFT",d.keep,"RIGHT",8,0)
            d:Hide()
            self.offer=d
        end
    end)
    local d=self.offer
    local who=offer.sender:match("^[^%-]+") or offer.sender
    d.title:SetText("Shared path")
    d.text:SetText(string.format("%s shares \"%s\" with you: %d waypoint%s.",who,offer.name,#offer.points,#offer.points==1 and "" or "s"))
    local lines={}
    for i,point in ipairs(offer.points) do
        if i>12 then lines[#lines+1]="… and "..(#offer.points-12).." more";break end
        lines[#lines+1]=i..". "..(point.title or P.Waypoints:MapName(point.mapID)).."  "..P:Format(point.x,point.y)
    end
    d.list:SetText(table.concat(lines,"\n"))
    d:Show()
end
-- Import / export / save-as dialog with one text field.
function L:Transfer(mode)
    UI:WithStyle(P:Style(),function()
        if not self.transfer then
            local t=UI:Dialog("BVMapWaypointText",460,330,self.dialog)
            t.text=UI:TransferText(t.content,430,200,20000)
            M.Point(t.text,"TOPLEFT",t.content,"TOPLEFT",16,-12)
            t.note=UI:Label(t.content,"",11,"muted");M.Point(t.note,"TOPLEFT",t.content,"TOPLEFT",16,-220);M.Size(t.note,420,30);t.note:SetWordWrap(true)
            t.ok=UI:Button(t.content,"OK",110,function() L:Confirm() end);M.Point(t.ok,"BOTTOMRIGHT",t.content,"BOTTOMRIGHT",-16,12)
            self.transfer=t
        end
    end)
    local t=self.transfer
    t.mode=mode
    if mode=="export" then
        t.title:SetText("Export waypoints");t.text:SetText(P.Waypoints:Export())
        t.note:SetText("/way lines: TomTom and BV read them back. Select all with Ctrl+A, copy with Ctrl+C.")
        t.ok:SetText("Close")
    elseif mode=="save" then
        t.title:SetText("Save as set");t.text:SetText("")
        t.note:SetText("A name for the current waypoints.");t.ok:SetText("Save")
    elseif mode=="share" then
        t.title:SetText("Share with a player");t.text:SetText("")
        t.note:SetText("The player's name (Name or Name-Realm). They see a preview and decide.");t.ok:SetText("Share")
    else
        t.title:SetText("Import waypoints");t.text:SetText("")
        t.note:SetText("One waypoint per line: /way 45.2 67.8 Name, /way #1418 45 67, /way Badlands 45 67 (Wowhead lists work as they are).")
        t.ok:SetText("Import")
    end
    t:Show();t.text.input:SetFocus()
end
function L:Confirm()
    local t=self.transfer
    local text=t.text.input:GetText()
    if t.mode=="import" then
        local added,failed=P.Waypoints:Import(text)
        P:Print(added.." waypoint"..(added==1 and "" or "s").." imported"..(#failed>0 and (", "..#failed.." line(s) not understood: "..failed[1]) or "")..".")
    elseif t.mode=="save" then
        if not P.Waypoints:SaveSet(text) then P:Print("A name and at least one waypoint are needed.");return end
    elseif t.mode=="share" then
        local name=text:gsub("^%s+",""):gsub("%s+$","")
        if not P.Share:Send("WHISPER",name,L:PathName()) then return end
    end
    t:Hide();self:Refresh()
end
