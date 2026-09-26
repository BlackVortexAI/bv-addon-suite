-- Shared texture-only gallery. The session owns catalog access and persistence.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
function UI:IconPicker(parent,width)
    local v=UI:Panel(parent,width,470,"surface"); UI:HideSurface(v)
    local function at(widget,x,y) M.Point(widget,"TOPLEFT",v,"TOPLEFT",x,-y); return widget end
    v.input=at(UI:Input(v,width),0,0); v.input:SetMaxLetters(100)
    v.note=at(UI:Label(v,"",11,"muted"),0,41); M.Size(v.note,width,34)
    v.buttons={}; v.page=1
    local columns,rows=8,6
    local stride=width/columns
    for i=1,columns*rows do
        local button=at(UI:Button(v,"",stride-5,function()
            local entry=v.buttons[i].entry
            if v.session and not v.debounce and entry and v.session:Choose(entry) then
                v:RefreshSelection()
                if v.accept then v.accept(entry) end
            end
        end),((i-1)%columns)*stride,80+math.floor((i-1)/columns)*46)
        M.Height(button,42)
        button.preview=button:CreateTexture(nil,"ARTWORK"); M.Size(button.preview,34,34); M.Point(button.preview,"CENTER",button,"CENTER",0,0)
        v.buttons[i]=button
    end
    v.previous=at(UI:Button(v,"Previous",110,function() v.page=v.page-1; v:Refresh() end),0,360)
    v.next=at(UI:Button(v,"Next",110,function() v.page=v.page+1; v:Refresh() end),width-110,360)
    v.pages=at(UI:Label(v,"",12,"muted"),width/2-40,369); M.Size(v.pages,80,20); v.pages:SetJustifyH("CENTER")
    v.preview=v:CreateTexture(nil,"ARTWORK"); M.Size(v.preview,48,48); at(v.preview,0,408)
    v.selection=at(UI:Label(v,"Select an icon",11,"muted"),60,402); M.Size(v.selection,width-60,26)
    v.reference=at(UI:Input(v,width-60),60,429); v.reference:SetMaxLetters(260)
    UI:AttachTooltip(v.reference,"Texture reference","Select text and press Ctrl+C to copy. This is not a spell or item ID.")
    v.reference:SetScript("OnTextChanged",function()
        if v.reference:GetText()~=(v.referenceText or "") then v.reference:SetText(v.referenceText or "") end
    end)
    function v:StopTimer(key) if self[key] then self[key]:Cancel(); self[key]=nil end end
    function v:ClearButtons()
        for _,b in ipairs(self.buttons) do b.entry=nil; b.preview:SetTexture(nil); b:Hide() end
        self.previous:Disable(); self.next:Disable()
    end
    function v:Close()
        self:StopTimer("poll"); self:StopTimer("debounce")
        self.input:ClearFocus(); self.reference:ClearFocus(); UI:HideTooltip()
        if self.session then self.session:Close(); self.session=nil end
        self.matches={}; self.accept=nil; self:ClearButtons()
    end
    function v:RefreshSelection()
        local selected=self.session and self.session:Selected()
        self.preview:SetTexture(selected and selected.texture or nil)
        self.selection:SetText(selected and "Selected texture (Ctrl+C to copy)" or "Select an icon to preview")
        self.referenceText=selected and tostring(selected.texture) or ""; self.reference:SetText(self.referenceText)
        for _,b in ipairs(self.buttons) do b:SetSelected(selected and b.entry and b.entry.key==selected.key or false) end
    end
    function v:Refresh(reset)
        self:StopTimer("debounce"); UI:HideTooltip()
        if not self.session then return end
        local state=self.session:Status()
        if not state.ready then
            self.input:Disable(); self:ClearButtons(); self.pages:SetText(""); self.note:SetText(state.message)
            if state.state=="failed" then self:StopTimer("poll") end
            self:RefreshSelection(); return
        end
        self:StopTimer("poll"); self.input:Enable()
        if reset then self.page=1 end
        self.matches=self.session:Search(self.input:GetText())
        local pages=math.max(1,math.ceil(#self.matches/48)); self.page=math.max(1,math.min(pages,self.page))
        self.pages:SetText(self.page.." / "..pages)
        self.note:SetText(state.message.." | "..#self.matches.." matches\nSearch file IDs or asset names when supplied by the client.")
        for i,b in ipairs(self.buttons) do
            local entry=self.matches[(self.page-1)*48+i]; b.entry=entry; b:SetShown(entry~=nil)
            b.preview:SetTexture(entry and entry.texture or nil)
            if entry then UI:AttachTooltip(b,entry.label,"Texture: "..tostring(entry.texture)..(entry.filename and ("\n"..entry.filename) or "").."\nIndependent icon; no spell or item binding.") end
        end
        if self.page>1 then self.previous:Enable() else self.previous:Disable() end
        if self.page<pages then self.next:Enable() else self.next:Disable() end
        self:RefreshSelection()
    end
    function v:Open(session,dismiss,accept)
        self:Close(); self.session=session; self.dismiss=dismiss; self.accept=accept; self.page=1
        self.input:SetText(""); self:Show(); self:Refresh(true)
        local status=session:Status()
        if not status.ready and status.state~="failed" then self.poll=C_Timer.NewTicker(.1,function() v:Refresh() end) end
    end
    v.input:SetScript("OnTextChanged",function()
        v:StopTimer("debounce"); UI:HideTooltip()
        if v.session and v.session:Status().ready then
            v:ClearButtons(); v.debounce=C_Timer.NewTimer(.15,function() v.debounce=nil; v:Refresh(true) end)
        end
    end)
    v.input:SetScript("OnEnterPressed",function() v:Refresh(true) end)
    for _,input in ipairs({v.input,v.reference}) do
        input:SetScript("OnEscapePressed",function() if v.dismiss then v.dismiss() end end)
    end
    v:HookScript("OnHide",function() v:Close() end)
    v:Hide(); return v
end
