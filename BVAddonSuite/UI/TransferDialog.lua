local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local function at(w,p,x,y) M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y); return w end

-- Shared bounded clipboard text surface. Native Ctrl+A/C/V, no OS clipboard API.
-- Built like variant C of the former /bv textdebug, proven natively
-- (in-game finding 50): a skinned frame for the visible area, inside it a
-- plain ScrollFrame with an unskinned multi-line edit box as scroll child,
-- the scroll bar beside it. The border sits on the visible area (a skin on
-- the tall edit box only showed its bottom edge after scrolling), and the
-- edit box height is never set per keystroke (variant D2: resizing on text
-- change broke caret and layout): it keeps the visible height as minimum and
-- grows natively; the scroll range comes from OnScrollRangeChanged.
function UI:TransferText(parent,width,height,maxLetters,changed)
    local style=self:GetStyle()
    local form=CreateFrame("Frame",nil,parent); M.Size(form,width-22,height)
    style:Skin(form,"bg",4,.85); form.surfacePaintOwned=true
    local scroll=CreateFrame("ScrollFrame",nil,form); form.scroll=scroll
    local visible=height-4
    M.Point(scroll,"TOPLEFT",form,"TOPLEFT",2,-2); M.Size(scroll,width-26,visible)
    local input=style:Input(scroll,width-28,true,"",nil,true)
    scroll:SetScrollChild(input); M.Height(input,visible)
    input:SetMaxLetters(maxLetters); form.input=input
    form.slider=style:Slider(form,12,0,0,1,0); local slider=form.slider
    M.Point(slider,"TOPLEFT",form,"TOPRIGHT",6,0); M.Size(slider,12,height)
    slider:SetOrientation("VERTICAL"); slider:SetMinMaxValues(0,0); slider:SetValueStep(1)
    slider.track:ClearAllPoints(); M.Point(slider.track,"TOP"); M.Point(slider.track,"BOTTOM"); M.Width(slider.track,3)
    M.Size(slider:GetThumbTexture(),6,32)
    slider:SetScript("OnValueChanged",function(_,value) scroll:SetVerticalScroll(M.ToNative(value)) end)
    form.maximum=0
    local function range(native)
        form.maximum=math.max(0,M.ToDesign(native or scroll:GetVerticalScrollRange() or 0))
        slider:SetMinMaxValues(0,form.maximum); slider:SetShown(form.maximum>0)
        if slider:GetValue()>form.maximum then slider:SetValue(form.maximum) end
    end
    form.UpdateRange=function() range() end
    scroll:SetScript("OnScrollRangeChanged",function(_,_,y) range(y) end)
    local function scrollTo(v) slider:SetValue(math.max(0,math.min(form.maximum,v))) end
    input:HookScript("OnTextChanged",function(_,user)
        range()
        if user and changed then changed() end
    end)
    -- Keep the native caret in view while typing or moving with the keys.
    input:SetScript("OnCursorChanged",function(_,_,y,_,cursorHeight)
        local top=math.max(0,-M.ToDesign(y)); local bottom=top+M.ToDesign(cursorHeight or 14)
        local offset=slider:GetValue()
        if top<offset then scrollTo(top) elseif bottom>offset+visible then scrollTo(bottom-visible) end
    end)
    -- Border colour follows the edit box focus, painted on the visible area.
    local function paint()
        form:PaintSurface({style:Color("bg")},{style:Color(input.invalid and "danger" or input.focused and "accent" or "edge",.7)},.85)
    end
    style:Bind(paint,form)
    input:HookScript("OnEditFocusGained",paint); input:HookScript("OnEditFocusLost",paint)
    -- Clicks and the wheel go to the edit box; the frames behind it take none.
    input:EnableMouse(true); if input.EnableKeyboard then input:EnableKeyboard(true) end
    input:EnableMouseWheel(true)
    input:SetScript("OnMouseWheel",function(_,delta) scrollTo(slider:GetValue()-delta*42) end)
    UI:TextFieldMenu(input,changed)
    function form:SetText(text) self.input:SetText(text); range(); slider:SetValue(0) end
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
    function dialog:RunPreview()
        invalidate()
        local ok,result=pcall(controller.PreviewTransfer,controller,dialog.text.input:GetText())
        if not ok then dialog:Note("Import rejected: "..ns.GraphValues.UserError(result)); return false,result end
        dialog.token=result; dialog.hasConflicts=#result.conflicts>0; dialog.choice=nil
        dialog:Note(result.summary); dialog.policy:SetShown(dialog.hasConflicts); dialog.policy:SetValue("choose")
        if not dialog.hasConflicts then dialog.confirm:Enable() else dialog.confirm:Disable() end
        return true
    end
    dialog.preview=at(self:Button(p,"Preview",108,function() dialog:RunPreview() end),p,20,376)
    dialog.confirm=at(self:Button(p,"Import disabled",150,function()
        local ok,result=pcall(controller.ImportTransfer,controller,dialog.token,dialog.choice)
        if not ok then dialog:Note("Import rejected: "..ns.GraphValues.UserError(result)); dialog.confirm:Disable(); return end
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
            if ok and packet.kind=="blocks" then
                self.text:SetText(text);self:Note("Block library: "..#packet.blocks.." block(s). Layout positions are not included; displays get new positions when inserted.")
                self.text.input:SetFocus(); self.text.input:HighlightText()
            elseif ok and packet.kind=="block" then
                self.text:SetText(text);self:Note("Building block \""..packet.block.name.."\". Layout positions are not included; displays get new positions when inserted.")
                self.text.input:SetFocus(); self.text.input:HighlightText()
            elseif ok then
                self.text:SetText(text); self:Note(#packet.graphs.." graph(s), including required graph dependencies.\nNo live values, history, index cache or profile settings are exported.\nThis is encoding, not encryption.")
                self.text.input:SetFocus(); self.text.input:HighlightText()
            else self.text:SetText(""); self:Note("Export rejected: "..ns.GraphValues.UserError(text)) end
        else
            self.hint:SetText("Paste a !BVA:1! string with Ctrl+V. Imported graphs are new, disabled copies.")
            self.text:SetText(""); self:Note("Nothing is changed until you review the preview and confirm the import."); self.text.input:SetFocus()
        end
    end
    -- Shared by another player (P4): the received string, previewed; the
    -- import still needs the player's confirmation here.
    function dialog:OpenReceived(text,sender,kind,name)
        self:Open("import")
        self.title:SetText(kind=="block" and "Shared block" or "Shared graph")
        self.hint:SetText("Received from "..tostring(sender):gsub("|","||").." ("..tostring(name):gsub("|","||").."). Review the preview, then import.")
        self.text:SetText(text); self.text.input:ClearFocus()
        local ok,why=self:RunPreview()
        if not ok then self:Hide() end
        return ok,ok and nil or tostring(why)
    end
    return dialog
end
