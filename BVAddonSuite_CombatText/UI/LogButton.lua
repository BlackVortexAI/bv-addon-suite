local _,L=...
if not L.ready then return end
-- Start button of the Combat Log signal (Log.lua): a secure macro button.
-- Created out of combat only; Log.lua sets its macro and shows or hides it.
local B={}
L.LogButton=B
B.TITLE="Combat Text: click to start"
B.TEXT="Opens the Combat Log for a moment, so your own hits are recognised. Once per login."
B.HELP="Opens the Combat Log tab for a moment and switches back. Afterwards the game reports your own actions, so Combat Text can tell your hits from your pet's and your group's. Clicking the Combat Log tab yourself works too. Needed once per login."

function B.Create(name)
    assert(not (InCombatLockdown and InCombatLockdown()),"Create the start button outside combat")
    local b=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate")
    b:Hide();b:SetFrameStrata("HIGH");b:SetSize(380,54)
    -- In the middle of the screen, a little above the character (Florian 2026-10-07).
    b:SetPoint("CENTER",UIParent,"CENTER",0,140)
    -- The game runs a macro button on press or release (ActionButtonUseKeyDown).
    b:RegisterForClicks("AnyUp","AnyDown")
    b:SetAttribute("type","macro")
    -- A dark panel with a thin gold frame, the BV logo, a title and one line
    -- that says why (Florian 2026-10-07: clearer and nicer).
    local border=b:CreateTexture(nil,"BACKGROUND")
    border:SetAllPoints();border:SetColorTexture(.9,.74,.35,.9)
    local bg=b:CreateTexture(nil,"BORDER")
    bg:SetPoint("TOPLEFT",1,-1);bg:SetPoint("BOTTOMRIGHT",-1,1);bg:SetColorTexture(.05,.05,.07,.94)
    local glow=b:CreateTexture(nil,"HIGHLIGHT")
    glow:SetPoint("TOPLEFT",1,-1);glow:SetPoint("BOTTOMRIGHT",-1,1);glow:SetColorTexture(1,.85,.4,.12)
    local logo=b:CreateTexture(nil,"ARTWORK")
    logo:SetSize(36,36);logo:SetPoint("LEFT",b,"LEFT",10,0)
    logo:SetTexture("Interface\\AddOns\\BVAddonSuite\\Media\\Brand\\bv-logo-small")
    b.logo=logo
    local title=b:CreateFontString(nil,"OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF",14,"OUTLINE");title:SetTextColor(1,.82,0)
    title:SetPoint("TOPLEFT",logo,"TOPRIGHT",10,-1);title:SetPoint("RIGHT",b,"RIGHT",-10,0)
    title:SetJustifyH("LEFT");title:SetText(B.TITLE)
    local text=b:CreateFontString(nil,"OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF",11,"");text:SetTextColor(.88,.88,.88)
    text:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-4);text:SetPoint("RIGHT",b,"RIGHT",-10,0)
    text:SetJustifyH("LEFT");text:SetText(B.TEXT)
    b.title,b.label=title,text
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
