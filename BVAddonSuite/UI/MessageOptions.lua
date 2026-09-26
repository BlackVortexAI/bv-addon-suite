-- Profile emergency pause; node settings own communication permissions.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
function UI:MessageOptions(parent,controller,width)
    local panel=UI:Panel(parent,width,210,"surface");UI:HideSurface(panel)
    panel.toggles={};panel.channels={}
    panel.status=UI:Label(panel,"",11,"text");UI:Place(panel.status,panel,12,166);M.Size(panel.status,width-24,34)
    panel.toggles.paused=UI:Switch(panel,false,function(value)
        local ok=controller:SetCommunication("paused",value)
        panel.status:SetText(ok and "Pause setting saved" or controller.message or "Setting was not changed")
        panel:Refresh()
    end)
    UI:Place(panel.toggles.paused,panel,12,12)
    UI:Place(UI:Label(panel,"Pause external addon communication",12,"text"),panel,62,14)
    panel.note=UI:Label(panel,"Configure Allow sending / Allow receiving and permitted senders on each node. BV Aura Studio messages between your own graphs remain available while external addon communication is paused. Visible chat uses separate Chat Request / Send Chat nodes. Imported communication nodes require local permission.",11,"muted")
    UI:Place(panel.note,panel,12,58);M.Size(panel.note,width-24,98)
    function panel:Refresh()self.toggles.paused:SetValue(controller:Communication().paused==true)end
    panel:Refresh();return panel
end
