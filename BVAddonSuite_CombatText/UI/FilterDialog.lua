local _,L=...
if not L.ready then return end
-- Asks before the BV Combat Log filter is set up (LogFilter.lua): it reloads
-- the interface at once. Used by the settings button and the guide.
-- ReloadUI() is protected on Forever, so the accept button is a secure macro
-- button over the styled one: its PreClick writes the filter, then the game
-- runs /reload itself. A failed write empties the macro: no reload. Shown
-- out of combat only (a secure button).
local ns=L.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local D={}
L.FilterDialog=D
D.TITLE="Set up the Combat Log filter"
D.TEXT="Combat Text adds the Combat Log filter \"BV Combat Text\": your actions and your pet's, your pet in its own colour, "
    .."so every Combat Log line tells whether it was you, your pet or someone else. Your other filters stay as they are.\n\n"
    .."The interface reloads right away (like /reload), because the game accepts a new filter only that way. "
    .."Afterwards click the Combat Log tab or the Start button once, as after every login."

function D:Show(accept)
    if InCombatLockdown and InCombatLockdown() then L:Print("Not in combat: set up the Combat Log filter afterwards.");return nil end
    local d=self.dialog
    if not d then
        d=UI:Dialog("BVCombatTextFilterDialog",460,250)
        self.dialog=d
        d.text=UI:Label(d.content,"",12,"text")
        UI:Place(d.text,d.content,20,14);M.Size(d.text,420,150)
        d.text:SetJustifyH("LEFT");d.text:SetJustifyV("TOP")
        if d.text.SetWordWrap then d.text:SetWordWrap(true) end
        d.ok=UI:Button(d.content,"Reload and set up",170,function() end,true)
        M.Point(d.ok,"BOTTOMRIGHT",d.content,"BOTTOMRIGHT",-150,18)
        local s=CreateFrame("Button","BVCombatTextFilterReload",d.ok,"SecureActionButtonTemplate")
        s:SetAllPoints(d.ok);s:SetFrameLevel(d.ok:GetFrameLevel()+5)
        -- The game runs a macro button on press or release (ActionButtonUseKeyDown).
        s:RegisterForClicks("AnyUp","AnyDown")
        s:SetAttribute("type","macro");s:SetAttribute("macrotext","")
        s:SetScript("PreClick",function(self)
            if d.written==nil then
                local run=d.accept
                local ok,result=pcall(function() return run and run() end)
                d.written=ok and result==true
            end
            self:SetAttribute("macrotext",d.written and "/reload" or "")
        end)
        s:SetScript("OnEnter",function() if d.ok:GetScript("OnEnter") then d.ok:GetScript("OnEnter")(d.ok) end end)
        s:SetScript("OnLeave",function() if d.ok:GetScript("OnLeave") then d.ok:GetScript("OnLeave")(d.ok) end end)
        d.secure=s
        d.cancel=UI:Button(d.content,"Cancel",120,function() d:Hide() end,"ghost")
        M.Point(d.cancel,"BOTTOMRIGHT",d.content,"BOTTOMRIGHT",-20,18)
        d:HookScript("OnHide",function() d.accept=nil;d.written=nil end)
        -- Closed as a fight starts (before the lockdown): a secure button
        -- could not be hidden in combat.
        ns.Events:Subscribe(D,"PLAYER_REGEN_DISABLED",function() if d:IsShown() then d:Hide() end end)
    end
    d.title:SetText(self.TITLE)
    d.text:SetText(self.TEXT)
    d.accept=accept
    d.written=nil
    d.secure:SetAttribute("macrotext","")
    d:Show()
    return d
end
