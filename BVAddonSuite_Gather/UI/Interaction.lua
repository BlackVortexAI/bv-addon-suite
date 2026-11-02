local _,G=...
if not G.ready then return end
local V={};G.InteractionView=V
local ns=G.ns
local COLORS={ready={.90,.76,.48,1},far={.67,.58,.39,.65},blocked={.63,.66,.69,.85},unknown={.65,.65,.60,.8}}
local MEDIA="Interface\\AddOns\\BVAddonSuite_Gather\\Media\\Interaction\\"
local CELLS={A=0,B=1,C=2}
local LABELS={ready="Interact",far="Out of range",blocked="Cannot gather",unknown="Range unknown"}
function V:Probe()
    if not self.probe then
        self.probe=CreateFrame("Frame",nil,UIParent);self.probe:Hide()
        self.probe.texture=self.probe:CreateTexture(nil,"ARTWORK")
    end
    return self.probe,self.probe.texture
end
function V:RestoreListener(callback)
    if not self.restore then self.restore=CreateFrame("Frame") end
    self.restore:SetScript("OnEvent",callback)
    return self.restore
end
local function symbol(texture,name,size)
    local path,l,r,t,b=ns.Symbols:Coords(name,size)
    if path then texture:SetTexture(path);texture:SetTexCoord(l,r,t,b) end
end
function V:Build()
    if self.mark then return end
    local f=CreateFrame("Frame",nil,UIParent);f:SetFrameStrata("HIGH");f:EnableMouse(false);f:Hide()
    self.mark=f
    f.art=f:CreateTexture(nil,"ARTWORK");f.art:SetAllPoints(f);f.art:SetTexture(MEDIA.."Markers.tga")
    f.iconShade=f:CreateTexture(nil,"BORDER");f.iconShade:SetSize(16,16);f.iconShade:SetVertexColor(.025,.022,.016,.65)
    f.icon=f:CreateTexture(nil,"OVERLAY");f.icon:SetSize(16,16)
    local h=CreateFrame("Frame",nil,UIParent);h:SetSize(1,1);h:SetPoint("CENTER",UIParent,"CENTER",0,-150)
    h:SetFrameStrata("HIGH");h:EnableMouse(false);h:Hide();self.hint=h
    h.ground=h:CreateTexture(nil,"BACKGROUND");h.ground:SetAllPoints(h);h.ground:SetTexture(MEDIA.."Hint.tga")
    local interface=ns.UI:InterfaceStyle()
    if interface and ns.InterfaceSurfaces and ns.InterfaceSurfaces.AttachHUD then ns.InterfaceSurfaces:AttachHUD(interface,h) end
    ns.UI:WithStyle(G:Style(),function()
        h.title=ns.UI:Label(h,"",14,"text",true);h.title:SetPoint("TOP",h,"TOP",0,-8)
        h.action=ns.UI:Label(h,"",12,"text");h.action:SetPoint("TOP",h.title,"BOTTOM",0,-3)
    end)
    for _,label in ipairs({h.title,h.action}) do label:SetWordWrap(false);label:SetShadowOffset(1,-1);label:SetShadowColor(0,0,0,1) end
end
function V:Paint(target)
    if not target then
        if self.mark then self.mark:Hide();self.mark:ClearAllPoints();self.mark:SetParent(UIParent);self.hint:Hide() end
        return
    end
    self:Build()
    local f,c=self.mark,G:Config()
    local color=COLORS[target.state] or COLORS.unknown
    self.hint:SetShown(c.interactHint)
    self.hint.title:SetText(target.name);self.hint.title:SetTextColor(.96,.88,.68,1)
    local key=target.binding and ("["..target.binding.."] ") or ""
    local text=LABELS[target.state] or LABELS.unknown
    if target.state=="ready" and not target.binding then text="Assign Interact Target in Key Bindings" end
    self.hint.action:SetText(key..text)
    self.hint.action:SetTextColor(.90,.91,.90,1)
    local width=math.max(self.hint.title:GetStringWidth(),self.hint.action:GetStringWidth())+24
    local height=self.hint.title:GetStringHeight()+self.hint.action:GetStringHeight()+19
    self.hint:SetSize(width,height)
    local plate=target.plate
    if not plate or type(plate.IsShown)~="function" or not plate:IsShown() or c.objectMark=="off" then f:Hide();return end
    f:SetParent(plate)
    -- Normalize the plate's UI scale, then apply one perspective factor to
    -- both artwork AND offset. Dividing the offset by that factor would
    -- preserve the old fixed-pixel drift. No absolute plate measurement.
    local ok,plateScale=pcall(plate.GetEffectiveScale,plate)
    local uiScale=UIParent:GetEffectiveScale()
    local ratio=ok and not G.Secret(plateScale) and type(plateScale)=="number" and plateScale>0 and uiScale/plateScale or 1
    local perspective=target.markerScale or 1
    f:SetScale(ratio*perspective);f:ClearAllPoints();f:SetPoint("TOP",plate,"BOTTOM",0,c.objectOffset/ratio);f:SetSize(c.objectSize,c.objectSize)
    local iconSize=math.max(16,12/perspective)
    f.icon:SetSize(iconSize,iconSize);f.iconShade:SetSize(iconSize,iconSize)
    if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
    local col=CELLS[c.objectMark] or 0
    local row=(target.state=="blocked" or target.state=="unknown") and 1 or 0
    f.art:SetTexCoord(col/4,(col+1)/4,row/2,(row+1)/2)
    f.art:SetAlpha(target.state=="far" and .85 or target.state=="unknown" and .7 or 1)
    f.icon:ClearAllPoints();f.icon:SetVertexColor(unpack(color))
    local icon=target.kind=="ore" and "pickaxe" or "leaf"
    symbol(f.icon,icon,16);symbol(f.iconShade,icon,16);f.icon:Show();f.iconShade:Show()
    f.iconShade:ClearAllPoints();f.iconShade:SetPoint("CENTER",f.icon,"CENTER",1,-1)
    f.icon:SetPoint("BOTTOM",f,"TOP",0,2)
    f:Show()
end
