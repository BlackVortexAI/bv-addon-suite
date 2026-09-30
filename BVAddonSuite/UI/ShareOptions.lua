-- Graph sharing (roadmap P4): receive switch, send to target, status, and the
-- confirmation dialog shown to the receiver.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
function UI:ShareOptions(parent,controller,width)
    -- Compact spacing (0.8.73): 30-unit switch rows, 26-unit controls.
    local panel=UI:Panel(parent,width,290,"surface");UI:HideSurface(panel)
    panel.receive=UI:Place(UI:Switch(panel,false,function(value)
        controller:SetShareReceive(value);panel:Refresh()
    end),panel,12,12)
    UI:Place(UI:Label(panel,"Allow receiving graphs and blocks",12,"text"),panel,62,14)
    panel.known=UI:Place(UI:Switch(panel,false,function(value)
        controller:SetShareKnownOnly(value);panel:Refresh()
    end),panel,12,42)
    UI:Place(UI:Label(panel,"Only from friends, guild and group",12,"text"),panel,62,44)
    panel.note=UI:Label(panel,"Off by default. Every offer needs Accept; received data opens in the import preview and is imported only when you confirm there, as a disabled draft without communication or macro-write permissions.",11,"muted")
    UI:Place(panel.note,panel,12,72);M.Size(panel.note,width-24,52)
    UI:Place(UI:Label(panel,"Send to",11,"muted"),panel,12,138)
    panel.recipient=UI:Place(UI:Dropdown(panel,250,{{value="target",label="Current target"}},function(value)
        if value=="target" then controller.shareUnit,controller.shareName=nil,nil
        else for _,m in ipairs(controller:ShareRecipients()) do if m.unit==value then controller.shareUnit,controller.shareName=m.unit,m.name end end end
        panel:Refresh()
    end),panel,70,132);M.Height(panel.recipient,26)
    panel.send=UI:Place(UI:Button(panel,"Send current graph",180,function()
        local ok,why=controller:ShareCurrent();if not ok then panel.status:SetText(why or controller.message or "Not sent") end;panel:Refresh()
    end,true),panel,12,166);M.Height(panel.send,26)
    panel.cancel=UI:Place(UI:Button(panel,"Cancel",100,function() controller:CancelShare();panel:Refresh() end,"ghost"),panel,202,166);M.Height(panel.cancel,26)
    panel.status=UI:Label(panel,"",11,"text");UI:Place(panel.status,panel,12,202);M.Size(panel.status,width-24,60)
    function panel:Refresh()
        local data=controller:Store()
        self.receive:SetValue(data.shareReceive==true);self.known:SetValue(data.shareKnownOnly==true)
        if data.shareReceive==true then self.known:Enable() else self.known:Disable() end
        local options={{value="target",label="Current target"}}
        for _,m in ipairs(controller:ShareRecipients()) do options[#options+1]={value=m.unit,label=m.name} end
        self.recipient:SetOptions(options)
        local unit=controller.shareUnit or "target";local present=false
        for _,o in ipairs(options) do if o.value==unit and (unit=="target" or o.label==controller.shareName) then present=true end end
        if not present then controller.shareUnit,controller.shareName=nil,nil;unit="target" end
        self.recipient:SetValue(unit)
        self.status:SetText(controller.shareStatus or "Choose a recipient, then send.")
        self.cancel:SetShown(controller.share~=nil and controller.share:Busy())
    end
    panel:Refresh();return panel
end
-- Receiver prompt: Accept or Decline; closing counts as Decline.
function UI:ShareRequest(sender,kind,name,parts,accept,decline)
    local d=self.shareRequest
    if not d then
        d=self:Dialog(nil,420,230);self.shareRequest=d;d.positionKey="shareRequest"
        d.text=UI:Place(UI:Label(d.content,"",13,"text"),d.content,20,16);M.Size(d.text,380,90)
        -- Buttons on the bottom edge (layout guard).
        d.decline=UI:Button(d.content,"Decline",150,function() local f=d.onDecline;d.onAccept,d.onDecline=nil,nil;d:Hide();if f then f() end end)
        M.Point(d.decline,"BOTTOMRIGHT",d.content,"BOTTOMRIGHT",-20,18)
        d.accept=UI:Button(d.content,"Accept",150,function() local f=d.onAccept;d.onAccept,d.onDecline=nil,nil;d:Hide();if f then f() end end,true)
        M.Point(d.accept,"RIGHT",d.decline,"LEFT",-10,0)
        d:HookScript("OnHide",function() local f=d.onDecline;d.onAccept,d.onDecline=nil,nil;if f then f() end end)
    end
    if d:IsShown() and d.onDecline then local f=d.onDecline;d.onAccept,d.onDecline=nil,nil;f() end
    d.title:SetText("Shared "..(kind=="block" and "block" or "graph"))
    d.text:SetText((sender:gsub("|","||")).." wants to send you the "..(kind=="block" and "block" or "graph").." \""..(name:gsub("|","||")).."\" ("..parts.." parts).\nIt will be imported as a disabled draft copy you can inspect before using.")
    d.onAccept,d.onDecline=accept,decline
    d:Show()
    return d
end
