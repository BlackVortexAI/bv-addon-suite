-- Reusable selection view. Owns presentation and session cleanup, never client lookups.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
function UI:LookupPicker(parent,width)
    local v=UI:Panel(parent,width,442,"surface")
    local function at(widget,x,y) M.Point(widget,"TOPLEFT",v,"TOPLEFT",x,-y); return widget end
    v.buttons={}; v.matches={}; v.page=1
    v.input=at(UI:Input(v,width),0,0); v.input:SetMaxLetters(100)
    v.note=at(UI:Label(v,"",11,"muted"),0,42); M.Size(v.note,width,32)
    v.metadataStatus=at(UI:Label(v,"Details load automatically for visible results.",10,"muted"),0,84); M.Size(v.metadataStatus,width,26)
    for i=1,8 do
        local button=at(UI:Button(v,"",width,function()
            local entry=v.buttons[i].entry
            if v.session and v.session:Status().ready and entry then v.choose(entry) end
        end),0,116+(i-1)*35)
        button:SetLabelInsets(38,8,"LEFT")
        button.preview=button:CreateTexture(nil,"ARTWORK"); M.Size(button.preview,24,24); M.Point(button.preview,"LEFT",button,"LEFT",6,0)
        button:HookScript("OnEnter",function() v:Hover(button) end)
        button:HookScript("OnLeave",function() if v.hovered==button then v:StopHover() end end)
        button:HookScript("OnHide",function() if v.hovered==button then v:StopHover() end end)
        v.buttons[i]=button
    end
    v.pages=at(UI:Label(v,"",12,"text"),width/2-15,413)
    v.previous=at(UI:Button(v,"Previous",110,function() v.page=v.page-1; v:Refresh() end),0,405)
    v.next=at(UI:Button(v,"Next",110,function() v.page=v.page+1; v:Refresh() end),width-110,405)
    v.blocker=at(UI:Panel(v,width,442,"surface"),0,0)
    v.blocker:SetFrameLevel(v:GetFrameLevel()+10); v.blocker:EnableMouse(true)
    v.blockTitle=UI:Label(v.blocker,"Preparing spell search",15,"text",true); M.Point(v.blockTitle,"TOPLEFT",v.blocker,"TOPLEFT",16,-40)
    v.blockNote=UI:Label(v.blocker,"",12,"muted"); M.Point(v.blockNote,"TOPLEFT",v.blocker,"TOPLEFT",16,-86); M.Size(v.blockNote,width-32,100)
    v.progress=UI:StatusBar(v.blocker,width-32,10); M.Point(v.progress,"TOPLEFT",v.blocker,"TOPLEFT",16,-192)
    v.retry=UI:Button(v.blocker,"Retry",110,function() if v.session then v.session:Retry(); v:Refresh(); v:Poll() end end)
    M.Point(v.retry,"TOPLEFT",v.blocker,"TOPLEFT",16,-232)
    v.cancel=UI:Button(v.blocker,"Cancel",110,function() if v.dismiss then v.dismiss() end end)
    M.Point(v.cancel,"TOPLEFT",v.blocker,"TOPLEFT",width-126,-232)
    function v:StopTimer(key) if self[key] then self[key]:Cancel(); self[key]=nil end end
    function v:StopHover()
        self:StopTimer("hoverTimer"); self.hovered=nil
    end
    function v:Hover(button)
        self:StopHover(); self.hovered=button
        if not self.session or not self.session.Tooltip or not self.session:Status().ready then return end
        local session,id,generation=self.session,button.entry and button.entry.value,self.generation
        if not id then return end
        local retries=0
        local function update()
            self.hoverTimer=nil
            if self.hovered~=button or not self:IsVisible() or self.session~=session or self.generation~=generation
                or not session:Status().ready or not button.entry or button.entry.value~=id then return end
            if session.EnrichmentPaused and session:EnrichmentPaused() then return end
            local row=session:Tooltip(button.entry,true)
            self:Paint(button,row)
            -- Only refresh our current tooltip; never reopen a tooltip after leaving.
            if UI.tooltip and UI.tooltip.owner==button then UI:ShowTooltip(button,row.label,row.origin) end
            retries=retries+1
            if row.textPending and retries<3 then self.hoverTimer=C_Timer.NewTimer(.5,update) end
        end
        self.hoverTimer=C_Timer.NewTimer(.15,update)
    end
    function v:StopEnrichment()
        self.generation=(self.generation or 0)+1; self:StopTimer("enrichment")
    end
    function v:Close()
        self:StopEnrichment(); self:StopHover()
        self:StopTimer("poll"); self:StopTimer("debounce"); self.input:ClearFocus()
        if self.session then self.session:Close(); self.session=nil end
        self.matches={}; for _,b in ipairs(self.buttons) do b.entry=nil end
    end
    function v:Paint(button,row)
        button.entry=row; button:SetShown(row~=nil)
        if row then
            button:SetLabelText(row.label); button.preview:SetTexture(row.icon or 134400)
            UI:AttachTooltip(button,row.label,row.origin)
        end
    end
    function v:EnrichVisible()
        if not self.session.Enrich then return end
        if #self.matches==0 then self.metadataStatus:SetText("No matching results."); return end
        self.metadataStatus:SetText("Loading details for visible results...")
        local generation,session=self.generation,self.session
        local i=0
        local function step()
            self.enrichment=nil
            if self.generation~=generation or self.session~=session or not self:IsVisible() or not session:Status().ready then return end
            if session.EnrichmentPaused and session:EnrichmentPaused() then
                self.metadataStatus:SetText("Details paused during combat")
                self.enrichment=C_Timer.NewTimer(.25,step); return
            end
            i=i+1; local button=self.buttons[i]
            if not button or not button.entry then self.metadataStatus:SetText("Visible results checked. Hover for game text."); return end
            local row=session:Enrich(button.entry,true)
            self.matches[(self.page-1)*8+i]=row; self:Paint(button,row)
            self.metadataStatus:SetText("Loading details: "..i.." / "..math.min(8,#self.matches-(self.page-1)*8))
            self.enrichment=C_Timer.NewTimer(.05,step)
        end
        self.enrichment=C_Timer.NewTimer(.05,step)
    end
    function v:Poll()
        self:StopTimer("poll")
        if self.session and not self.session:Status().ready then
            self.poll=C_Timer.NewTicker(.2,function() self:Refresh() end)
        end
    end
    function v:Refresh(reset)
        self:StopEnrichment(); self:StopHover(); UI:HideTooltip()
        if not self.session then return end
        if reset then self.page=1 end
        local state=self.session:Status()
        self.blocker:SetShown(not state.ready)
        if not state.ready then
            self.input:Disable(); self.input:ClearFocus(); self.matches={}
            self.previous:Disable(); self.next:Disable()
            for _,b in ipairs(self.buttons) do b.entry=nil; b:Hide() end
            self.progress:SetValue(state.progress or 0)
            self.blockNote:SetText(state.message.."\n\nSelection stays locked until the complete index is ready. Closing cancels an unfinished build.")
            self.retry:SetShown(state.state=="failed")
            if state.state=="failed" then self:StopTimer("poll") end
            return
        end
        self:StopTimer("poll"); self.input:Enable()
        local rows,note=self.session:Search(self.input:GetText()); self.matches=rows
        local pages=math.max(1,math.ceil(#rows/8)); self.page=math.max(1,math.min(pages,self.page))
        self.note:SetText(note.."\n"..#rows.." results - choose an ID below.")
        self.pages:SetText(self.page.." / "..pages)
        if self.page>1 then self.previous:Enable() else self.previous:Disable() end
        if self.page<pages then self.next:Enable() else self.next:Disable() end
        for i,b in ipairs(self.buttons) do
            self:Paint(b,rows[(self.page-1)*8+i])
        end
        self:EnrichVisible()
    end
    function v:Open(session,choose,dismiss)
        self:Close(); self.session=session; self.choose=choose; self.dismiss=dismiss; self.page=1
        self.metadataStatus:SetText("Details load automatically for visible results.")
        self.input:SetText(""); self:Show(); self:Refresh(true); self:Poll()
        if session:Status().ready then self.input:SetFocus() end
    end
    v.input:SetScript("OnTextChanged",function()
        v:StopTimer("debounce"); v:StopEnrichment(); v:StopHover(); UI:HideTooltip()
        if v.session and v.session:Status().ready then v.debounce=C_Timer.NewTimer(.15,function() v.debounce=nil; v:Refresh(true) end) end
    end)
    v.input:SetScript("OnEnterPressed",function() v:StopTimer("debounce"); v:Refresh(true) end)
    v:HookScript("OnHide",function() v:Close() end)
    v:Hide(); return v
end
