-- Profile key assignments for shortcut-enabled Action Displays.
-- Keys are captured only here; ordinary typing never reaches this panel.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local Actions=ns.Actions
local ROW=50 -- compact rows (0.8.73)
function UI:ShortcutOptions(parent,controller,width,height)
    local panel=UI:Panel(parent,width,height,"surface");UI:HideSurface(panel)
    panel.rows={}
    panel.labels=UI:Switch(panel,true,function(value)
        panel:Stop()
        local ok=controller:SetShortcutLabels(value)
        panel.status:SetText(ok and "Key label setting saved" or controller.message or "Setting was not changed")
        panel:Refresh()
    end)
    UI:Place(panel.labels,panel,12,12)
    UI:Place(UI:Label(panel,"Show key labels on displays",12,"text"),panel,62,14)
    panel.note=UI:Label(panel,"Enable Keyboard shortcuts on an Action Display node and save the graph. Keys belong to this profile, work while the display is shown and change only outside combat. A key overrides a WoW binding only while its display is active.",11,"muted")
    UI:Place(panel.note,panel,12,48);M.Size(panel.note,width-24,58)
    panel.form=UI:Place(UI:Form(panel,width-8,height-170),panel,4,112)
    panel.empty=UI:Label(panel.form.content,"No saved graph has an Action Display with Keyboard shortcuts enabled.",12,"muted")
    UI:Place(panel.empty,panel.form.content,8,8);M.Size(panel.empty,width-40,40)
    panel.status=UI:Label(panel,"",11,"text");UI:Place(panel.status,panel,12,height-50);M.Size(panel.status,width-24,40)
    -- Dedicated capture surface: keyboard input is taken only while a row waits.
    panel.capture=CreateFrame("Frame",nil,panel);panel.capture:SetAllPoints(panel);panel.capture:EnableMouse(false)
    panel.capture:EnableKeyboard(false)
    panel.capture:SetScript("OnKeyDown",function(_,key) panel:Key(key) end)
    panel.capture:SetScript("OnHide",function() panel:Stop() end)
    function panel:Stop()
        if self.waiting then self.waiting=nil;self.capture:EnableKeyboard(false);self:Refresh() end
    end
    function panel:Start(row)
        self:Stop()
        if InCombatLockdown() then self.status:SetText("Change keyboard shortcuts after combat");return end
        self.waiting=row.target;self.capture:EnableKeyboard(true)
        if self.capture.SetPropagateKeyboardInput then self.capture:SetPropagateKeyboardInput(false) end
        row.keyButton:SetLabelText("Press a key...")
        self.status:SetText("Press the key combination for "..row.target.binding..". Esc cancels.")
    end
    function panel:Key(key)
        local target=self.waiting;if not target then return end
        if key=="ESCAPE" then self:Stop();self.status:SetText("Assignment cancelled");return end
        local value=Actions.ShortcutFromInput(key,IsAltKeyDown(),IsControlKeyDown(),IsShiftKeyDown())
        -- A lone modifier keeps waiting for the actual key.
        if not value and ({LSHIFT=true,RSHIFT=true,LCTRL=true,RCTRL=true,LALT=true,RALT=true,LMETA=true,RMETA=true})[key] then return end
        self:Stop()
        if not value then self.status:SetText("Choose a keyboard key");return end
        local ok=controller:SetShortcut(target.id,target.key,value)
        self.status:SetText(ok and value.." assigned to "..target.binding or controller.message or "Shortcut was not changed")
        self:Refresh()
    end
    local function row(index)
        local r=panel.rows[index];if r then return r end
        local content=panel.form.content
        r=UI:Panel(content,width-40,ROW-4,"surface");UI:HideSurface(r)
        r.title=UI:Place(UI:Label(r,"",12,"text",true),r,4,2);M.Size(r.title,200,16);r.title:SetWordWrap(false)
        r.binding=UI:Place(UI:Label(r,"",11,"muted"),r,4,18);M.Size(r.binding,200,14);r.binding:SetWordWrap(false)
        r.warning=UI:Place(UI:Label(r,"",10,"accent"),r,4,32);M.Size(r.warning,width-48,14);r.warning:SetWordWrap(false)
        r.keyButton=UI:Place(UI:Button(r,"",120,function() panel:Start(r) end),r,208,4);M.Height(r.keyButton,26)
        r.clear=UI:Place(UI:Button(r,"Clear",64,function()
            panel:Stop()
            local ok=controller:SetShortcut(r.target.id,r.target.key,nil)
            panel.status:SetText(ok and "Shortcut cleared" or controller.message or "Shortcut was not changed")
            panel:Refresh()
        end,"ghost"),r,332,4);M.Height(r.clear,26)
        panel.rows[index]=r;return r
    end
    function panel:Refresh()
        self.labels:SetValue(controller:Store().shortcutLabels~=false)
        local targets=controller:ShortcutTargets()
        for _,r in ipairs(self.rows) do r:Hide() end
        for i,target in ipairs(targets) do
            local r=row(i);r.target=target
            UI:Place(r,self.form.content,4,(i-1)*ROW)
            r.title:SetText(target.graph.." / "..target.node)
            r.binding:SetText(target.binding..(target.enabled and "" or " (graph disabled)"))
            local waiting=self.waiting and self.waiting.id==target.id and self.waiting.key==target.key
            r.keyButton:SetLabelText(waiting and "Press a key..." or target.value or "Not set")
            r.clear:SetShown(target.value~=nil)
            local action=target.value and type(GetBindingAction)=="function" and GetBindingAction(target.value)
            r.warning:SetText(type(action)=="string" and action~="" and "Overrides WoW binding "..action.." while active" or "")
            r:Show()
        end
        self.empty:SetShown(#targets==0)
        self.form:SetContentHeight(math.max(1,#targets*ROW))
    end
    panel:Refresh();return panel
end
