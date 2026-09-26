-- Deliberate secure island: graph evaluation updates a cue, never an action.
local _,ns=...
local Q={pending={},pool={}};ns.SecureSpells=Q
function Q:ValidLayout(id)
    local raw=ns.Layout:Nodes()[id]
    -- The first action surface is screen-fixed. Dynamic frame/nameplate/cursor
    -- attachments need a separate secure lifecycle, not ordinary layout polling.
    return raw and not raw.link and not raw.widthTarget and not raw.heightTarget
end
local function create()
    assert(not InCombatLockdown(),"Create secure buttons outside combat")
    local b=CreateFrame("Button",nil,UIParent,"SecureActionButtonTemplate")
    b:Hide();b:SetFrameStrata("MEDIUM");b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown",false)
    b:SetAttribute("unit","player")
    b.image=b:CreateTexture(nil,"ARTWORK");b.image:SetAllPoints(b)
    b.cue=b:CreateTexture(nil,"OVERLAY");b.cue:SetAllPoints(b)
    b.cue:SetColorTexture(1,.78,.15,.35);b.cue:SetAlpha(0)
    b.caption=b:CreateFontString(nil,"OVERLAY")
    b.caption:SetFont("Fonts\\FRIZQT__.TTF",11,"OUTLINE")
    b.caption:SetPoint("TOP",b,"BOTTOM",0,-3)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    -- Keep Blizzard's inherited OnClick. No graph callback or queued cast.
    return b
end
function Q:Cue(rec)
    local b=rec.secureButton;if not b then return end
    local entry=rec.secureEntry
    local same=entry and entry.owner==b.owner and entry.secureSpell==b.spellID
    local hint
    if same then hint=entry.secureHint end
    if same then ns.UI:ApplyIconCrop(b.image,entry.cropBorder) end
    b.cue:SetAlpha(hint==true and 1 or 0)
    local suffix=rec.securePending and " / pending after combat" or hint==true and " / suggested" or hint==nil and " / hint unavailable" or ""
    b.caption:SetText((b.spellName or "Spell "..b.spellID).." / self"..suffix)
end
function Q:Paint(rec,rect,visible)
    local entry=rec.secureEntry
    local wanted=entry and not entry.owner.test and not rec.preview and visible and self:ValidLayout(rec.id) and ns.Layout:IsAvailable(rec.id)
        and rect and rect.width>=8 and rect.height>=8
    if InCombatLockdown() then
        -- Never clear attributes, move, hide, reparent or allocate in lockdown.
        local b=rec.secureButton
        local same=b and wanted and b.owner==entry.owner and b.spellID==entry.secureSpell and b:IsShown()
            and b.rect.x==rect.x and b.rect.y==rect.y and b.rect.width==rect.width and b.rect.height==rect.height
        rec.securePending=not same and (b~=nil or wanted) or nil
        if rec.securePending then self.pending[rec]=true;self:Watch() else self.pending[rec]=nil end
        self:Cue(rec)
        return
    end
    rec.securePending=nil;self.pending[rec]=nil
    local b=rec.secureButton
    if not wanted then
        if b then
            b:Hide();b:SetAttribute("*type1",nil);b:SetAttribute("spell",nil)
            b.owner=nil;b.spellID=nil;rec.secureButton=nil;self.pool[#self.pool+1]=b
        end
        return
    end
    b=b or table.remove(self.pool) or create();rec.secureButton=b
    local spellID=entry.secureSpell
    if b.spellID~=spellID or b.owner~=entry.owner then
        b:Hide();b:SetAttribute("*type1","spell");b:SetAttribute("spell",spellID)
        b.spellID=spellID;b.owner=entry.owner
        b.spellName=nil
        if C_Spell and C_Spell.GetSpellName then
            local ok,name=pcall(C_Spell.GetSpellName,spellID)
            if ok and not ns.GraphValues.IsSecret(name) and type(name)=="string" and #name>0 then b.spellName=name:gsub("|","||") end
        end
        local texture=entry.texture
        if C_Spell and C_Spell.GetSpellTexture then
            local ok,value=pcall(C_Spell.GetSpellTexture,spellID)
            if ok and not ns.GraphValues.IsSecret(value) and type(value)=="number" and value>0 then texture=value end
        end
        b.image:SetTexture(texture or 134400)
    end
    local old=b.rect
    if not old or old.x~=rect.x or old.y~=rect.y or old.width~=rect.width or old.height~=rect.height then
        b:ClearAllPoints();b:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y);b:SetSize(rect.width,rect.height)
        b.rect={x=rect.x,y=rect.y,width=rect.width,height=rect.height}
    end
    local level=ns.Layout:Level(rec.id)+5
    if b:GetFrameLevel()~=level then b:SetFrameLevel(level) end
    self:Cue(rec);if not b:IsShown() then b:Show() end
end
function Q:Watch()
    if self.watching then return end
    self.watching=true
    ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function()
        if InCombatLockdown() then return end
        ns.Events:Release(self);self.watching=nil
        local pending=self.pending;self.pending={}
        for rec in pairs(pending) do
            -- Retired records explicitly queue false; active records resolve
            -- their latest geometry and visibility instead of replaying changes.
            self:Paint(rec,rec.rect,rec.visible)
        end
    end)
end
function Q:Release(rec)
    rec.secureEntry=nil
    self:Paint(rec,nil,false)
end
