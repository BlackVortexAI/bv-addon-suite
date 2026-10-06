-- Guide window (Core/Tutorial.lua): the steps of one guide, one after
-- another, each with its live state. A step's secure action is a macro
-- button laid over the action button's face: only a real click may do what
-- it does (e.g. show a Blizzard window). It exists out of combat only.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local W,H,LIST=640,440,170
local OK,OPEN,GREY="|cff40d060","|cffffb040","|cff9a9aa6"
-- Blizzard's ready check marks: present in every client, unlike ✓ in fonts.
local DONE,WAIT,INFO="|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t","|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t","|TInterface\\Common\\Indicator-Gray:14|t"
local function at(w,p,x,y) M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y); return w end
local function locked() return InCombatLockdown and InCombatLockdown() end

local function build()
    local dialog=UI:Dialog("BVAddonSuiteTutorial",W,H)
    local p=dialog.content
    dialog.rows={}
    for i=1,8 do
        local row=at(UI:Label(p,"",13,"text",false),p,18,14+(i-1)*26);M.Size(row,LIST-24,22)
        dialog.rows[i]=row
    end
    local x=LIST+12
    dialog.icon=at(p:CreateTexture(nil,"ARTWORK"),p,x,16);M.Size(dialog.icon,40,40)
    dialog.stepTitle=at(UI:Label(p,"",16,"text",true),p,x+52,16);M.Size(dialog.stepTitle,W-x-70,22)
    dialog.counter=at(UI:Label(p,"",11,"muted",false),p,x+52,38);M.Size(dialog.counter,W-x-70,18)
    dialog.text=at(UI:Label(p,"",13,"text",false),p,x,68);M.Size(dialog.text,W-x-20,190)
    dialog.text:SetJustifyH("LEFT");dialog.text:SetJustifyV("TOP")
    dialog.state=at(UI:Label(p,"",13,"text",true),p,x,268);M.Size(dialog.state,W-x-20,40)
    dialog.state:SetJustifyH("LEFT");dialog.state:SetJustifyV("TOP")
    dialog.action=at(UI:Button(p,"",220,function() dialog:RunAction() end),p,x,314)
    dialog.back=at(UI:Button(p,"Back",100,function() dialog:GoTo(dialog.step-1) end),p,x,360)
    dialog.next=at(UI:Button(p,"Next",100,function() dialog:Next() end,true),p,x+110,360)
    dialog.later=at(UI:Button(p,"Later",100,function() dialog:Hide() end,"ghost"),p,W-120,360)
    UI:AttachTooltip(dialog.later,"Later","Closes the guide. It comes back at the next login until you finish it; /bv guide opens it at any time.")

    -- Secure macro button over the action button (created out of combat).
    function dialog:Secure()
        if self.secure or locked() then return self.secure end
        local b=CreateFrame("Button","BVAddonSuiteTutorialAction",UIParent,"SecureActionButtonTemplate")
        b:Hide();b:SetFrameStrata("FULLSCREEN_DIALOG");b:SetFrameLevel(self:GetFrameLevel()+30)
        b:RegisterForClicks("AnyUp","AnyDown");b:SetAttribute("type","macro")
        b:SetAllPoints(self.action)
        UI:AttachTooltip(b,"Do it now","Clicks for you what the text describes and comes back.")
        self.secure=b
        return b
    end
    function dialog:HideSecure() if self.secure and not locked() then self.secure:Hide() end end

    function dialog:RunAction()
        local step=self.steps[self.step]
        if step and step.action then pcall(step.action.run) end
        self:Render()
    end
    function dialog:Next()
        if self.step<#self.steps then self:GoTo(self.step+1);return end
        self.finished=true
        self:Hide()
        ns.Tutorial:Done(self.guide.id)
    end
    function dialog:GoTo(step)
        self.step=math.max(1,math.min(#self.steps,step or 1))
        self:Render()
    end
    function dialog:Render()
        local guide,T,steps=self.guide,ns.Tutorial,self.steps
        for i,row in ipairs(self.rows) do
            local step=steps[i]
            if step then
                local state=T:Check(step)
                local mark=(state=="done" and DONE or state=="open" and WAIT or INFO).." "
                row:SetText(mark..(i==self.step and step.title or GREY..step.title.."|r"))
                row:Show()
            else row:Hide() end
        end
        local step=steps[self.step]
        self.icon:SetTexture(step.icon or "Interface\\Icons\\INV_Misc_Book_09")
        self.stepTitle:SetText(step.title)
        self.counter:SetText("Step "..self.step.." of "..#steps)
        self.text:SetText(T:Text(step))
        local state,info=T:Check(step)
        self.state:SetText(state=="done" and DONE.." "..OK..(info or "Done").."|r" or state=="open" and WAIT.." "..OPEN..(info or "Not done yet").."|r" or "")
        local action=step.secure or step.action
        -- hideWhenDone: the button only serves to get the step done (Florian
        -- 2026-10-05: opening the Combat Log again changes nothing).
        if action and action.hideWhenDone and state=="done" then action=nil end
        if action then self.action:SetLabelText(action.label or "Do it");self.action:Show() else self.action:Hide() end
        if action and step.secure then
            local b=self:Secure()
            if b and not locked() then
                local ok,macro=pcall(step.secure.macro)
                b:SetAttribute("macrotext",ok and type(macro)=="string" and macro or "")
                b:Show()
            elseif not b then self.action:SetLabelText("After combat") end
        else self:HideSecure() end
        if self.step>1 then self.back:Enable() else self.back:Disable() end
        self.next:SetLabelText(self.step<#steps and "Next" or "Done")
    end
    -- Live: states are checked again every second while the window is open.
    dialog:HookScript("OnShow",function()
        if dialog.ticker then dialog.ticker:Cancel() end
        dialog.ticker=C_Timer.NewTicker(1,function() if dialog:IsShown() then dialog:Render() end end)
    end)
    dialog:HookScript("OnHide",function()
        if dialog.ticker then dialog.ticker:Cancel();dialog.ticker=nil end
        dialog:HideSecure()
    end)
    -- A protected button cannot hide once combat has begun: hide it as combat starts.
    ns.Events:Subscribe(dialog,"PLAYER_REGEN_DISABLED",function() dialog:HideSecure() end)
    ns.Events:Subscribe(dialog,"PLAYER_REGEN_ENABLED",function() if dialog:IsShown() then dialog:Render() end end)
    return dialog
end

function UI:TutorialWindow(guide,steps)
    local dialog=self.tutorialWindow or build()
    self.tutorialWindow=dialog
    dialog.guide,dialog.steps,dialog.finished=guide,steps or guide.steps,nil
    dialog.title:SetText(guide.title.." - Guide")
    dialog:FitContent(W,H)
    dialog:Show()
    dialog:GoTo(1)
    UI:FocusWindow(dialog)
    return dialog
end
