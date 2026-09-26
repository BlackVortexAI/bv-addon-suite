local _,ns=...
local E,UI,L,D=ns.LayoutEditor,ns.UI,ns.Layout,ns.DesignSystem.Metrics
local function at(w,p,x,y)return UI:Place(w,p,x,y)end
function E:CancelCleanup()
    self.cleanupTarget=nil
    if self.cleanupDialog then self.cleanupDialog:Hide()end
    if self.cleanupShield then self.cleanupShield:Hide()end
end
function E:RequestCleanup()
    if not self.active or self.suspended or not self:CommitAnchorName()then return end
    self:StopDrag();self:CancelAnchorDelete();self.picking=nil;UI:CloseDropdown();self.confirm:Hide()
    self.cleanupTarget={profile=ns.Settings:Profile(),draft=L.draft,selected={}}
    self.cleanupPage=1;self:Refresh();self:RefreshCleanup();self.cleanupShield:Show();self.cleanupDialog:Show()
end
function E:RefreshCleanup()
    local target=self.cleanupTarget
    if not target then return end
    if target.profile~=ns.Settings:Profile() or target.draft~=L.draft then self:CancelCleanup();return end
    local candidates=ns.DisplayAnchors:CleanupCandidates();self.cleanupCandidates=candidates
    local available={};for _,row in ipairs(candidates)do available[row.id]=true end
    for id in pairs(target.selected)do if not available[id]then target.selected[id]=nil end end
    local pages=math.max(1,math.ceil(#candidates/5));self.cleanupPage=math.min(pages,math.max(1,self.cleanupPage or 1))
    for i,row in ipairs(self.cleanupRows)do
        local item=candidates[(self.cleanupPage-1)*5+i];row.id=item and item.id;row:SetShown(item~=nil)
        if item then
            row.check:SetValue(target.selected[item.id]==true)
            row.name:SetText(item.label)
            row.status:SetText(#item.references>0 and "Linked elements: select them too, or unlink first." or "Unused display")
            UI:AttachTooltip(row,item.label,#item.references>0 and table.concat(item.references,"\n") or "No graph or runtime owner. Safe to remove from this draft.")
        end
    end
    self.cleanupInfo:SetText(#candidates==0 and "No unused aura displays found. Disabled graphs and saved layouts are kept."
        or "Select retired displays to remove. Linked retired displays can be selected together. Changes remain in the layout draft until Save & exit.")
    self.cleanupPages:SetText(self.cleanupPage.." / "..pages)
    self.cleanupPrev:SetShown(pages>1);self.cleanupNext:SetShown(pages>1)
    local count=0;for _ in pairs(target.selected)do count=count+1 end
    self.cleanupCount:SetText(count.." selected")
    if count>0 then self.cleanupAccept:Enable()else self.cleanupAccept:Disable()end
    UI:FitWindow(self.cleanupDialog,560,454,ns.Settings:Get("scale"))
end
function E:ConfirmCleanup()
    local target=self.cleanupTarget
    if not target or not self.active or self.suspended then return end
    if target.profile~=ns.Settings:Profile() or target.draft~=L.draft then
        self:CancelCleanup();self:Message("Layout changed. Open Clean up again.");return
    end
    local ids={};for id in pairs(target.selected)do ids[#ids+1]=id end
    local ok,why=ns.DisplayAnchors:DeleteUnusedDisplays(ids)
    if not ok then self:RefreshCleanup();self.cleanupInfo:SetText(why);return end
    self:CancelCleanup();self:Refresh();self:Message("Unused displays removed from draft. Save & exit to keep; Discard to restore.")
end
function E:BuildCleanup()
    if self.cleanupDialog then return end
    local shield=UI:Panel(self.root,1,1,"surface");shield:SetAllPoints(self.root);UI:HideSurface(shield)
    shield:SetFrameLevel(self.root:GetFrameLevel()+69);shield:EnableMouse(true);shield:Hide();self.cleanupShield=shield
    local dialog=UI:Panel(shield,560,454,"raised");dialog:SetPoint("CENTER");dialog:SetFrameLevel(self.root:GetFrameLevel()+70);dialog:EnableMouse(true);dialog:Hide()
    self.cleanupDialog=dialog
    at(UI:Label(dialog,"Clean up unused displays",18,"text",true),dialog,18,16)
    self.cleanupInfo=at(UI:Label(dialog,"",12,"muted"),dialog,18,50);D.Size(self.cleanupInfo,524,56)
    self.cleanupRows={}
    for i=1,5 do
        local row=at(UI:Panel(dialog,524,46,"surface"),dialog,18,110+(i-1)*48)
        row.check=at(UI:Switch(row,false,function(v)
            if self.cleanupTarget and row.id then self.cleanupTarget.selected[row.id]=v or nil;self:RefreshCleanup()end
        end),row,4,10)
        row.name=at(UI:Label(row,"",12,"text",true),row,54,3);D.Size(row.name,458,18)
        row.status=at(UI:Label(row,"",11,"muted"),row,54,24);D.Size(row.status,458,18)
        self.cleanupRows[i]=row
    end
    self.cleanupPrev=at(UI:Button(dialog,"Previous",96,function()self.cleanupPage=self.cleanupPage-1;self:RefreshCleanup()end),dialog,18,356)
    self.cleanupPages=at(UI:Label(dialog,"",12,"muted"),dialog,128,363);D.Size(self.cleanupPages,80,18)
    self.cleanupCount=at(UI:Label(dialog,"",12,"text"),dialog,230,363);D.Size(self.cleanupCount,180,18)
    self.cleanupNext=at(UI:Button(dialog,"Next",96,function()self.cleanupPage=self.cleanupPage+1;self:RefreshCleanup()end),dialog,446,356)
    at(UI:Button(dialog,"Cancel",120,function()self:CancelCleanup()end),dialog,18,406)
    self.cleanupAccept=at(UI:Button(dialog,"Remove selected",166,function()self:ConfirmCleanup()end),dialog,376,406)
end
