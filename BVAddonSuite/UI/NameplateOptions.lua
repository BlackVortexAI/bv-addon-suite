-- Blizzard nameplate stacking (roadmap P2d). The setting changes only on an
-- explicit click here; the previous value is kept for Restore.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
function UI:NameplateOptions(parent,controller,width)
    local panel=UI:Panel(parent,width,360,"surface");UI:HideSurface(panel)
    panel.state=UI:Label(panel,"",12,"text");UI:Place(panel.state,panel,12,12);M.Size(panel.state,width-24,36)
    local function set()
        local ok=controller:SetNameplateStacking(panel.enemy.value==true,panel.friendly.value==true)
        panel.status:SetText(ok and "Nameplate stacking saved" or controller.message or "Setting was not changed")
        panel:Refresh()
    end
    panel.enemy=UI:Place(UI:Switch(panel,false,set),panel,12,56);UI:Place(UI:Label(panel,"Stack enemy nameplates",12,"text"),panel,62,58)
    panel.friendly=UI:Place(UI:Switch(panel,false,set),panel,12,92);UI:Place(UI:Label(panel,"Stack friendly nameplates",12,"text"),panel,62,94)
    panel.restore=UI:Place(UI:Button(panel,"Restore previous",160,function()
        local ok=controller:RestoreNameplateStacking()
        panel.status:SetText(ok and "Previous nameplate setting restored" or controller.message or "Setting was not changed")
        panel:Refresh()
    end,"ghost"),panel,12,132)
    panel.note=UI:Label(panel,"Stacking moves overlapping nameplates apart (Blizzard setting). Changed only when you click here, outside combat.",11,"muted")
    UI:Place(panel.note,panel,12,176);M.Size(panel.note,width-24,36)
    panel.bounds=UI:Place(UI:Switch(panel,false,function(value) controller:SetNameplateBounds(value);panel:Refresh() end),panel,12,220)
    UI:Place(UI:Label(panel,"Experimental: include BV elements in the stacking size",12,"text"),panel,62,222)
    panel.boundsNote=UI:Label(panel,"Plates with BV elements register a bounds frame covering the plate and those elements. Not yet tested in the game; may conflict with other nameplate addons. Turning it off shrinks the bounds back to the plate.",11,"muted")
    UI:Place(panel.boundsNote,panel,12,254);M.Size(panel.boundsNote,width-24,48)
    panel.status=UI:Label(panel,"",11,"text");UI:Place(panel.status,panel,12,308);M.Size(panel.status,width-24,36)
    function panel:Refresh()
        local cur=controller:NameplateStacking()
        local available=cur~=nil
        for _,w in ipairs({self.enemy,self.friendly}) do if available then w:Enable() else w:Disable() end end
        self.enemy:SetValue(available and cur.enemy);self.friendly:SetValue(available and cur.friendly)
        self.state:SetText(available and ("Current: "..(cur.enemy and cur.friendly and "enemy and friendly" or cur.enemy and "enemy only" or cur.friendly and "friendly only" or "off"))
            or "Nameplate stacking is not available on this client.")
        self.restore:SetShown(controller:Store().nameplateStackingRestore~=nil)
        self.bounds:SetValue(controller:Store().nameplateBoundsExperiment==true)
    end
    panel:Refresh();return panel
end
