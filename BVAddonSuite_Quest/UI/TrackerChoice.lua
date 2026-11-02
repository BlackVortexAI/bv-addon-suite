local _,Q=...
if not Q.ready then return end
local ns,Choice=Q.ns,Q.TrackerChoice
local UI,M=ns.UI,ns.DesignSystem.Metrics
local function explanation(s)
    return "Use one quest tracker. This changes Questie's active profile '"..(s.name or "?").."', which may be shared by other characters. "..
        "Questie maps and tracked-quest lists are preserved. Profile changes never silently overwrite another Questie profile."
end
function Choice:ShowDialog(s)
    if self.dialog and self.dialog:IsShown() then return end
    local style=self.dialog and self.dialog.bvStyle or UI:InterfaceStyle()
    if not style then return nil end
    if not self.dialog then
        UI:WithStyle(style,function()
            local d=UI:Dialog("BVQuestTrackerChoice",520,270,nil,{escapeScope=true});self.dialog=d;d.bvStyle=style
            d.title:SetText("Choose your quest tracker")
            -- Own only this dialog's surface painter; never mutate the palette.
            d.surfacePaintOwned=true
            style:Bind(function()d:PaintSurface({style:Color("panel",1)},{style:Color(style.materialProfile=="interface" and "controlEdge" or "edge")},1)end,d)
            d.copy=UI:Label(d.content,"",13,"text");M.Point(d.copy,"TOPLEFT",20,-16);M.Size(d.copy,480,122);d.copy:SetWordWrap(true)
            d.suite=UI:Button(d.content,"Use BV tracker",220,nil,true);M.Point(d.suite,"BOTTOMLEFT",20,20)
            d.questie=UI:Button(d.content,"Use Questie tracker",220);M.Point(d.questie,"BOTTOMRIGHT",-20,20)
            function d:LayoutCopy()
                self.copy:SetHeight(0)
                local height=math.max(122,M.ToDesign(self.copy:GetStringHeight())+4)
                M.Height(self.copy,height)
                self:FitContent(520,math.max(270,36+16+height+24+math.max(M.GetHeight(self.suite),M.GetHeight(self.questie))+20))
            end
            -- Runs after the label's captured font painter on appearance refresh.
            style:Bind(function()d:LayoutCopy()end,d.copy)
            d:HookScript("OnHide",function()if d.profile then self.dismissed[d.profile]=true end end)
        end)
    end
    local d=self.dialog;local token=self:Token(s);d.profile=ns.Settings:Profile()
    d.copy:SetText("Both quest trackers are enabled.\n\n"..explanation(s))
    d.suite:SetScript("OnClick",function()if d:IsShown() then self:Apply("suite",token) end end)
    d.questie:SetScript("OnClick",function()if d:IsShown() then self:Apply("questie",token) end end)
    d:LayoutCopy();d:Show()
end
function Choice:BuildOptions(page,grid)
    local view={page=page};self.views[view]=true;page.trackerChoice=view
    view.select=UI:Dropdown(grid,220,{{value="suite",label="BV tracker"},{value="questie",label="Questie tracker"}},function(value)view.draft=value end)
    grid:Row("Tracker provider",view.select,{help="Review the provider and use Apply. The saved choice belongs to this BV profile; Questie's active profile can affect other characters."})
    view.apply=UI:Button(grid,"Apply tracker choice",220)
    grid:Row("Apply provider",view.apply,{help="Explicitly applies the selected tracker to Questie's current profile. No automatic reload."})
    view.reload=UI:Button(grid,"Reload UI & use Questie",220)
    grid:Row("Pending activation",view.reload,{help="Explicitly reloads the UI to build Questie's tracker. BV remains unchanged until Questie is ready after reload."})
    view.note=UI:Label(grid,"",12,"muted");view.note:SetWordWrap(true);M.Height(view.note,64)
    grid:Block(view.note,64,function(width)
        M.Width(view.note,width);view.note:SetHeight(0)
        local height=math.max(64,M.ToDesign(view.note:GetStringHeight())+4)
        M.Height(view.note,height);return height
    end)
    function view:Refresh()
        local s=Choice:Inspect();local c=Choice:Store();local token=Choice:Token(s)
        if self.profile~=ns.Settings:Profile() then self.profile=ns.Settings:Profile();self.draft=nil end
        local pending=c.trackerProviderPendingReload
        local pendingHere=pending and pending.suiteProfile==token.suiteName and pending.questieProfile==s.name
        self.draft=self.draft or (pendingHere and "questie") or c.trackerProviderChoice or (c.tracker and "suite" or "questie")
        self.select:SetValue(self.draft);self.note:SetText(Choice:Status(s))
        UI:AttachTooltip(self.apply,"Tracker provider",explanation(s))
        local available=Choice.active and s.state=="ready" and not (InCombatLockdown and InCombatLockdown())
        if available then self.select:Enable();self.apply:Enable() else self.select:Disable();self.apply:Disable() end
        if available and pendingHere then self.reload:Enable()else self.reload:Disable()end
        self.apply:SetScript("OnClick",function()if page:IsVisible() then Choice:Apply(self.draft,token) end end)
        self.reload:SetScript("OnClick",function()if page:IsVisible() then Choice:ReloadChoice(token) end end)
        if page.Arrange and page:IsVisible() and ns.Config.window then ns.Config:Layout() end
    end
    page:HookScript("OnHide",function()view.draft=nil end)
    view:Refresh();return view
end
