local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local function at(w,p,x,y) M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y); return w end

-- Shared bounded clipboard text surface. Native Ctrl+A/C/V, no OS clipboard API.
function UI:TransferText(parent,width,height,maxLetters,changed)
    local form=self:Form(parent,width,height,parent); form:SetClipsChildren(true)
    local input=self:GetStyle():Input(form.content,width-24,true,"")
    at(input,form.content,0,0); input:SetMaxLetters(maxLetters); form.input=input
    input:HookScript("OnTextChanged",function(_,user)
        local text=input:GetText(); local lines=0
        for line in (text.."\n"):gmatch("(.-)\n") do lines=lines+math.max(1,math.ceil(#line/math.max(1,math.floor((width-44)/9)))) end
        local h=math.max(height,lines*18+20); M.Height(input,h); form:SetContentHeight(h)
        if user and changed then changed() end
    end)
    input:SetScript("OnCursorChanged",function(_,_,y,_,cursorHeight)
        local top=math.max(0,-M.ToDesign(y)); local bottom=top+M.ToDesign(cursorHeight)
        local offset=form.slider:GetValue()
        if top<offset then form.slider:SetValue(top) elseif bottom>offset+height then form.slider:SetValue(math.min(form.maximum or 0,bottom-height)) end
    end)
    function form:SetText(text) self.input:SetText(text); self.slider:SetValue(0) end
    form:SetText(""); return form
end

function UI:TransferDialog(owner,controller)
    local dialog=self:Dialog("BVAddonSuiteTransfer",580,460,owner)
    local p=dialog.content
    dialog.hint=at(self:Label(p,"",12,"muted"),p,20,12); M.Size(dialog.hint,540,42)
    local function invalidate()
        dialog.token=nil; controller:CancelTransfer(); dialog.confirm:Disable(); dialog.policy:Hide()
        dialog.note:SetText("Preview the pasted data before importing.")
    end
    dialog.text=at(self:TransferText(p,540,130,ns.TransferCodec.maxInput,invalidate),p,20,58)
    dialog.previewArea=at(self:Form(p,540,126,p),p,20,204); dialog.previewArea:SetClipsChildren(true)
    dialog.note=at(self:Label(dialog.previewArea.content,"",12,"text"),dialog.previewArea.content,0,0); M.Width(dialog.note,510)
    function dialog:Note(text)
        self.note:SetText(text)
        -- Explicit measured height keeps both native and cold-font fallback safe.
        M.Height(self.note,0); local h=math.max(40,M.ToDesign(self.note:GetStringHeight()))
        M.Height(self.note,h); self.previewArea:SetContentHeight(h); self.previewArea.slider:SetValue(0)
    end
    dialog.policy=at(self:Dropdown(p,350,{{value="choose",label="Resolve anchor conflicts..."},{value="existing",label="Keep existing anchors (positions may differ)"},{value="copy",label="Create separate copies of all anchors"}},function(value)
        dialog.choice=value~="choose" and value or nil
        if dialog.token~=nil and (not dialog.hasConflicts or dialog.choice~=nil) then dialog.confirm:Enable() else dialog.confirm:Disable() end
    end),p,20,338)
    dialog.preview=at(self:Button(p,"Preview",108,function()
        invalidate()
        local ok,result=pcall(controller.PreviewTransfer,controller,dialog.text.input:GetText())
        if not ok then dialog:Note("Import rejected: "..tostring(result)); return end
        dialog.token=result; dialog.hasConflicts=#result.conflicts>0; dialog.choice=nil
        dialog:Note(result.summary); dialog.policy:SetShown(dialog.hasConflicts); dialog.policy:SetValue("choose")
        if not dialog.hasConflicts then dialog.confirm:Enable() else dialog.confirm:Disable() end
    end),p,20,376)
    dialog.confirm=at(self:Button(p,"Import disabled",150,function()
        local ok,result=pcall(controller.ImportTransfer,controller,dialog.token,dialog.choice)
        if not ok then dialog:Note("Import rejected: "..tostring(result)); dialog.confirm:Disable(); return end
        dialog:Hide(); if controller.editor then controller.editor:LoadView() end
    end,"primary"),p,140,376)
    dialog.select=at(self:Button(p,"Select all",108,function() dialog.text.input:SetFocus(); dialog.text.input:HighlightText() end),p,20,376)
    dialog.cancel=at(self:Button(p,"Close",100,function() dialog:Hide() end,"ghost"),p,460,376)
    dialog:HookScript("OnHide",function() dialog.token=nil; controller:CancelTransfer(); dialog.text.input:ClearFocus() end)
    function dialog:Open(mode,kind,id)
        self.token=nil; self.choice=nil; controller:CancelTransfer(); self.confirm:Disable(); self.policy:Hide()
        self.preview:SetShown(mode=="import"); self.confirm:SetShown(mode=="import"); self.select:SetShown(mode=="export")
        self.title:SetText(mode=="import" and "Import graphs" or "Export graphs")
        self:FitContent(580,mode=="import" and 460 or 460)
        self:Show()
        if mode=="export" then
            self.hint:SetText("Current drafts and required layout dependencies. Select all, then Ctrl+C to copy.")
            local ok,text,packet=pcall(controller.ExportTransfer,controller,kind,id)
            if ok then
                self.text:SetText(text); self:Note(#packet.graphs.." graph(s), including required graph dependencies.\nNo live values, history, index cache or profile settings are exported.\nThis is encoding, not encryption.")
                self.text.input:SetFocus(); self.text.input:HighlightText()
            else self.text:SetText(""); self:Note("Export rejected: "..tostring(text)) end
        else
            self.hint:SetText("Paste a !BVA:1! string with Ctrl+V. Imported graphs are new, disabled copies.")
            self.text:SetText(""); self:Note("Nothing is changed until you review the preview and confirm the import."); self.text.input:SetFocus()
        end
    end
    return dialog
end
