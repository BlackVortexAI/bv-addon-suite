local _,L=...
if not L.ready then return end
-- Start button of the Combat Log signal (Log.lua): a secure macro button.
-- Created out of combat only; Log.lua sets its macro and shows or hides it.
local B={}
L.LogButton=B
B.TEXT="Combat Text: click once to read your actions"
B.HELP="Opens the Combat Log tab for a moment and switches back. Afterwards the game reports your own actions, so Combat Text can tell your hits from your pet's and your group's. Clicking the Combat Log tab yourself works too. Needed once per login."

function B.Create(name)
    assert(not (InCombatLockdown and InCombatLockdown()),"Create the start button outside combat")
    local b=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate")
    b:Hide();b:SetFrameStrata("MEDIUM");b:SetSize(300,26)
    b:SetPoint("TOP",UIParent,"TOP",0,-120)
    -- The game runs a macro button on press or release (ActionButtonUseKeyDown).
    b:RegisterForClicks("AnyUp","AnyDown")
    b:SetAttribute("type","macro")
    local bg=b:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints();bg:SetColorTexture(.08,.08,.1,.85)
    local text=b:CreateFontString(nil,"OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF",12,"OUTLINE");text:SetTextColor(1,.82,0)
    text:SetPoint("CENTER");text:SetText(B.TEXT)
    b.label=text
    b:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_BOTTOM")
        GameTooltip:SetText("Combat Text")
        GameTooltip:AddLine(B.HELP,1,1,1,true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end
