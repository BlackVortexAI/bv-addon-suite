local _,ns=...
-- In-game style families (Core 0.8.95, docs/style-families-concept.md): BV, WoW
-- and Clean for elements players see while playing (bars, roll bars, toasts).
-- Tool windows keep the BV style (UI:GetStyle). A module asks for its own
-- context with UI:GameStyle(moduleID); it inherits the suite family unless the
-- module's settings name its own (modules[id].styleFamily). Changing a family
-- repaints through the shared paint registry, then ns.Styles:Notify() tells
-- modules to repaint what they draw themselves.
local UI,DS,Theme=ns.UI,ns.DesignSystem,ns.Theme
local M=DS.Metrics
local FLAT="Interface\\Buttons\\WHITE8X8"
local S={contexts={},listeners={}}
ns.Styles=S

S.order={"bv","wow","clean","match"}
-- colors: the factory's color roles; nil = BV palette of the tool windows.
-- fonts: client font paths; nil = the suite font. bar: statusbar texture
-- (path, "flat" or nil = the suite texture). iconEdge: item icon border width.
-- barEdge: frame around timer bars. barFrame: progress bars get the family's
-- border (BV: none, as before). upper: section labels in upper case.
-- level: how an item level reads ("short" iLvl 80, "long" Item Level 80, "bare" 80).
S.families={
    bv={label="BV",border="rounded",barFrame=false,iconEdge=1,barEdge={0,0,0,.85},labelColor={1,1,1},level="short",stripe=true},
    wow={label="WoW",border="gold",barFrame=true,iconEdge=2,barEdge={.54,.43,.18,1},labelColor={1,.82,0},level="long",receive=true,
        colors={bg={.035,.027,.016},panel={.06,.047,.03},raised={.09,.07,.04},accent={1,.82,0},secondary={.8,.62,.25},
            text={.95,.9,.79},muted={.8,.75,.64},edge={.54,.43,.18}},
        fonts={regular="Fonts\\FRIZQT__.TTF",bold="Fonts\\FRIZQT__.TTF",display="Fonts\\MORPHEUS.TTF"},
        bar="Interface\\TargetingFrame\\UI-StatusBar"},
    clean={label="Clean",border="pixel",barFrame=true,iconEdge=1,barEdge={0,0,0,1},labelColor={.72,.72,.72},level="bare",upper=true,
        colors={bg={.07,.07,.07},panel={.07,.07,.07},raised={.11,.11,.11},accent={.37,.71,.85},secondary={.6,.6,.6},
            text={.91,.91,.91},muted={.6,.6,.6},edge={.19,.19,.19}},
        fonts={regular="Fonts\\ARIALN.TTF",bold="Fonts\\ARIALN.TTF",display="Fonts\\ARIALN.TTF"},
        bar="flat"},
}
-- "Clean (match my UI)" (Florian, 2026-10-07, replaces the suite switch of the
-- same name): Clean whose border, background and accent come from a supported
-- interface package; without one it is plain Clean. Choosable per module.
do
    local match={}
    for key,value in pairs(S.families.clean) do match[key]=value end
    match.label,match.matchUI="Clean (match my UI)",true
    S.families.match=match
end
local aliases={canvas="bg",surface="panel",hover="raised",ink="bg"}

-- "Match my UI" (family "match"): border, background and accent colours of a
-- supported interface package, read through that package's own API. The
-- package is never named in user-facing text (settings, tooltips, chat).
local function rgb(t,alpha)
    if type(t)~="table" or type(t[1])~="number" or type(t[2])~="number" or type(t[3])~="number" then return nil end
    return {t[1],t[2],t[3],alpha or (type(t[4])=="number" and t[4]) or 1}
end
-- Providers in order; the first one that answers wins. Each reads the
-- package's own API only (no saved variables of other addons).
local providers={}
providers[1]=function()
    local package=rawget(_G,"ElvUI")
    if type(package)~="table" then return nil end
    local ok,engine=pcall(function() return package[1] end)
    if not ok or type(engine)~="table" or type(engine.media)~="table" then return nil end
    local media=engine.media
    local edge,back=rgb(media.bordercolor),rgb(media.backdropcolor)
    if not (edge and back) then return nil end
    local fade=rgb(media.backdropfadecolor)
    return {edge=edge,panel=back,raised=back,bg=fade or back,accent=rgb(media.rgbvaluecolor)}
end
-- Second package (Florian, 2026-10-07): background and border of its Blizzard
-- reskin (GetTooltipBg / GetTooltipBorder) and the accent of its active theme.
providers[2]=function()
    local package=rawget(_G,"EllesmereUI")
    if type(package)~="table" or type(package.GetTooltipBg)~="function" or type(package.GetTooltipBorder)~="function" then return nil end
    local okBack,r,g,b,a=pcall(package.GetTooltipBg)
    local okEdge,er,eg,eb,ea=pcall(package.GetTooltipBorder)
    if not (okBack and okEdge) then return nil end
    local back=rgb({r,g,b},a)
    local edge=rgb({er,eg,eb},ea)
    if not (back and edge) then return nil end
    local accent=package.ELLESMERE_GREEN
    accent=type(accent)=="table" and rgb({accent.r,accent.g,accent.b}) or nil
    local panel={back[1],back[2],back[3],1}
    return {edge=edge,panel=panel,raised=panel,bg=back,accent=accent}
end
function S:External()
    for _,provider in ipairs(providers) do
        local ok,colors=pcall(provider)
        if ok and colors then return colors end
    end
    return nil
end

function S:SuiteFamily()
    -- Until the family existed, "Match my UI" was a suite switch for Clean: move it over once.
    local ui=ns.Settings:Profile().ui
    if ui.gameMatchUI==true then
        if ui.gameFamily=="clean" then ui.gameFamily="match" end
        ui.gameMatchUI=false
    end
    local id=ns.Settings:Get("gameFamily")
    return self.families[id] and id or "bv"
end
-- Family of a module: its own choice, otherwise the suite's.
function S:Family(moduleID)
    local id=self:SuiteFamily()
    if moduleID then
        local own=ns.Settings:Module(moduleID).styleFamily
        if self.families[own] then id=own end
    end
    return id,self.families[id]
end
-- Choices for a module's family dropdown: inherit plus every family.
function S:Choices(inherit)
    local out={}
    if inherit then out[1]={value="inherit",label="Inherit from suite ("..self.families[self:SuiteFamily()].label..")"} end
    for _,id in ipairs(self.order) do
        local label=self.families[id].label
        if self.families[id].matchUI and not self:External() then label=label.." – no interface package found" end
        out[#out+1]={value=id,label=label}
    end
    return out
end
function S:Color(familyID,key,alpha)
    if familyID=="bv" then return Theme:Color(key,alpha) end
    key=aliases[key] or key
    local family=self.families[familyID]
    local external=family.matchUI and self:External()
    if external and external[key] then
        -- The package's own alpha (often a faint border, 0.18) is scaled by the
        -- control's, never replaced: a button's 0.7 edge must not turn it solid
        -- white (Florian's screenshot, 2026-10-07).
        local c=external[key]
        return c[1],c[2],c[3],(c[4] or 1)*(alpha or 1)
    end
    local c=family.colors[key] or DS.shared[key] or Theme.colors[key]
    assert(c,"Unknown style color: "..tostring(key))
    return c[1],c[2],c[3],alpha or c[4] or 1
end
-- flags: font outline ("OUTLINE"...); only for the family fonts and the fallback.
function S:Font(familyID,region,size,weight,flags)
    local path=self:FontPath(familyID,weight)
    if not path then
        Theme:Font(region,size,(weight=="bold" or weight=="display") and Theme:BoldFont() or nil)
        if flags and flags~="" then local current=region:GetFont();if current then region:SetFont(current,size,flags) end end
        return
    end
    local ok,loaded=pcall(region.SetFont,region,path,size,flags or "")
    if not ok or not loaded then region:SetFont("Fonts\\FRIZQT__.TTF",size,flags or "") end
end
-- The family's own font file, nil for BV (the suite font applies).
function S:FontPath(familyID,weight)
    local fonts=self.families[familyID].fonts
    return fonts and (fonts[weight] or fonts.regular) or nil
end
function S:BarTexture(familyID)
    local bar=self.families[familyID].bar
    if bar=="flat" then return ns.Media:StatusBar("flat") end
    return bar or ns.Media:StatusBar(ns.Settings:Get("statusbar"))
end
-- Section labels (Clean: upper case).
function S:Label(familyID,text)
    if type(text)=="string" and self.families[familyID].upper then return text:upper() end
    return text
end
function S:LevelText(familyID,level)
    local kind=self.families[familyID].level
    if kind=="bare" then return tostring(level) end
    if kind=="long" then
        if type(ITEM_LEVEL)=="string" and ITEM_LEVEL:find("%d",1,true) then return (ITEM_LEVEL:gsub("%%d",tostring(level))) end
        return "Item Level "..level
    end
    return (ITEM_LEVEL_ABBR or "iLvl").." "..level
end

-- Modules repaint what they draw themselves (UI:Refresh calls Notify).
function S:OnChanged(owner,callback) self.listeners[owner]=callback end
function S:Off(owner) self.listeners[owner]=nil end
function S:Notify()
    for owner,callback in pairs(self.listeners) do
        local ok,err=pcall(callback,owner)
        if not ok and ns.Print then ns:Print("Style refresh failed: "..tostring(err)) end
    end
end
-- A module changed its own family or style options.
function S:Changed() UI:Refresh() end

-- Surfaces. Each border kind builds its pieces once per frame on first use;
-- a family switch shows that kind's pieces and hides the others.
local function lines(frame,layer,sublevel,thickness,inset)
    local t={}
    for i=1,4 do t[i]=frame:CreateTexture(nil,layer,nil,sublevel);t[i]:SetTexture(FLAT) end
    M.Point(t[1],"TOPLEFT",inset,-inset);M.Point(t[1],"TOPRIGHT",-inset,-inset);M.Height(t[1],thickness)
    M.Point(t[2],"BOTTOMLEFT",inset,inset);M.Point(t[2],"BOTTOMRIGHT",-inset,inset);M.Height(t[2],thickness)
    M.Point(t[3],"TOPLEFT",inset,-inset);M.Point(t[3],"BOTTOMLEFT",inset,inset);M.Width(t[3],thickness)
    M.Point(t[4],"TOPRIGHT",-inset,-inset);M.Point(t[4],"BOTTOMRIGHT",-inset,inset);M.Width(t[4],thickness)
    return t
end
local function build(frame,kind,corner,shadow)
    local p={}
    if kind=="rounded" then
        p.fills=DS.Slice(frame,"Interface\\AddOns\\BVAddonSuite\\Media\\DesignLab\\surface.tga",corner,"BACKGROUND",0)
        p.borders=DS.Slice(frame,"Interface\\AddOns\\BVAddonSuite\\Media\\DesignLab\\border.tga",corner,"BORDER",0)
        p.inner={}
        -- Windows keep their soft shadow in BV, as in the tool style.
        if shadow then for _,t in ipairs(DS.Slice(frame,"Interface\\AddOns\\BVAddonSuite\\Media\\DesignLab\\shadow.tga",20,"BACKGROUND",-2,10)) do p.inner[#p.inner+1]=t end;p.shadow=true end
    else
        local fill=frame:CreateTexture(nil,"BACKGROUND",nil,0);fill:SetTexture(FLAT);fill:SetAllPoints(frame)
        p.fills={fill}
        -- WoW: 2-unit gold frame with a dark inner line; Clean: 1-pixel border with a dark inner line.
        local outer=kind=="gold" and 2 or 1
        p.borders=lines(frame,"BORDER",0,outer,0)
        p.inner=lines(frame,"BORDER",1,1,outer)
    end
    p.all={}
    for _,list in ipairs({p.fills,p.borders,p.inner}) do for _,t in ipairs(list) do p.all[#p.all+1]=t end end
    return p
end
local function familyOf(style)
    if style.fixedFamily then return style.fixedFamily,S.families[style.fixedFamily] end
    return S:Family(style.gameModule)
end
local function refill(list,from) for i=#list,1,-1 do list[i]=nil end;for i,t in ipairs(from) do list[i]=t end end
function S:PaintSkin(style,frame)
    local skin=frame.bvFamilySkin
    local _,family=familyOf(style)
    local kind=family.border
    skin.kinds[kind]=skin.kinds[kind] or build(frame,kind,skin.corner,skin.shadow)
    local pieces=skin.kinds[kind]
    -- A border-only skin (UI:GameBorder) shows no fill, and nothing at all in a
    -- family without bar frames.
    local visible=not frame.surfaceHidden and not (skin.borderOnly and not family.barFrame)
    for k,p in pairs(skin.kinds) do
        local shown=k==kind and visible
        for _,t in ipairs(p.all) do t:SetShown(shown) end
        if shown and skin.borderOnly then for _,t in ipairs(p.fills) do t:Hide() end end
    end
    refill(frame.fills,pieces.fills);refill(frame.borders,pieces.borders)
    -- A control paints its own surface (hover, selection): repeat its last
    -- paint on the pieces of the new kind.
    if frame.bvSurfacePaint then frame:PaintSurface(unpack(frame.bvSurfacePaint));return end
    if frame.surfacePaintOwned then return end
    -- In the client a texture's SetAlpha and the alpha of SetVertexColor are
    -- ONE value: the later call wins. So every alpha goes into the vertex
    -- colour once, combined, and SetAlpha is never used here (a faint 0.18
    -- package border turned solid white, Florian's screenshots 2026-10-07).
    local opacity=type(skin.alpha)=="function" and skin.alpha() or skin.alpha or 1
    local r,g,b,a
    if frame.bvFillOverride then r,g,b,a=frame.bvFillOverride() end
    if not r then r,g,b,a=style:Color(skin.fill) end
    for _,t in ipairs(pieces.fills) do t:SetVertexColor(r,g,b,(a or 1)*opacity) end
    local edgeOpacity=math.max(opacity,.35)
    local er,eg,eb,ea=style:Color("edge",kind=="rounded" and .45 or nil)
    for _,t in ipairs(pieces.borders) do t:SetVertexColor(er,eg,eb,kind=="rounded" and ea or ea*edgeOpacity) end
    if not pieces.shadow then for _,t in ipairs(pieces.inner) do t:SetVertexColor(0,0,0,edgeOpacity) end end
end
function S:Skin(style,frame,fill,corner,alpha,shadow)
    frame.bvFamilySkin={kinds={},fill=fill or "panel",corner=corner or 6,alpha=alpha,shadow=shadow==true,borderOnly=frame.bvFamilySkinBorderOnly==true}
    frame.fills,frame.borders={},{}
    function frame:RepaintSurface() S:PaintSkin(style,self) end
    -- The factory's controls paint their surface themselves (Factory:Button,
    -- Input, Switch...): same contract as the tool skin. Gold and pixel
    -- borders stay crisp, so their alpha does not drop below 0.8.
    function frame:PaintSurface(background,edge,opacity)
        self.bvSurfacePaint={background,edge,opacity}
        local family=select(2,familyOf(style))
        local kind=family.border
        local pieces=self.bvFamilySkin.kinds[kind]
        if not pieces then return end
        for _,t in ipairs(pieces.fills) do t:SetVertexColor(background[1],background[2],background[3],(background[4] or 1)*(opacity or 1)) end
        -- Colours taken from an interface package keep their own (often faint) border alpha.
        local own=kind=="rounded" or (family.matchUI and S:External()~=nil)
        for _,t in ipairs(pieces.borders) do
            t:SetVertexColor(edge[1],edge[2],edge[3],own and (edge[4] or 1) or math.max(edge[4] or 1,.8))
        end
        -- The dark inner line: uncoloured it is plain white (Florian's
        -- screenshot, 2026-10-07: white boxes around every control).
        if not pieces.shadow then for _,t in ipairs(pieces.inner) do t:SetVertexColor(0,0,0,1) end end
    end
    style:Bind(function() S:PaintSkin(style,frame) end,frame)
    return frame
end

-- One style context per module (nil = the suite level).
function UI:GameStyle(moduleID)
    local key=moduleID or "suite"
    local style=S.contexts[key]
    if style then return style end
    local tools=self:ToolStyle()
    style=DS:New(tools.owner)
    style.gameModule=moduleID
    style.colorResolver=function(k,alpha) return S:Color((S:Family(moduleID)),k,alpha) end
    style.fontResolver=function(region,size,weight) S:Font((S:Family(moduleID)),region,size,weight) end
    style.registerPaint=tools.registerPaint
    style.skinner=function(frame,fill,corner,alpha,shadow) return S:Skin(style,frame,fill,corner,alpha,shadow) end
    S.contexts[key]=style
    return style
end
-- The UI facade's signatures (bold as boolean, panel compatibility).
function UI:GameLabel(moduleID,parent,text,size,color,bold)
    return self:GameStyle(moduleID):Label(parent,text,size,color,bold and "bold" or "regular")
end
function UI:GamePanel(moduleID,parent,width,height,fill,corner,alpha)
    return self:Compatible(self:GameStyle(moduleID):Panel(parent,width,height,fill or "panel",corner,alpha))
end
-- Builds a whole window or group in a style: every UI facade call inside fn
-- (UI:Button, UI:Dropdown, UI:Dialog...) uses that style context. The context
-- resolves the family live, so the window follows later style changes.
function UI:WithStyle(style,fn,...)
    local previous=self.styleOverride
    self.styleOverride=style
    local result={pcall(fn,...)}
    self.styleOverride=previous
    if not result[1] then error(result[2],0) end
    return unpack(result,2)
end
-- Only the family's border, drawn inside the parent's rectangle (progress bars).
function S:Border(style,parent)
    local frame=CreateFrame("Frame",nil,parent);frame:SetAllPoints(parent);frame:EnableMouse(false)
    frame.bvFamilySkinBorderOnly=true
    S:Skin(style,frame,"bg",6,1)
    return frame
end
function UI:GameBorder(moduleID,parent) return S:Border(self:GameStyle(moduleID),parent) end
-- A context fixed to one family (design gallery): independent of the saved settings.
function S:Preview(familyID,owner)
    local style=DS:New(owner)
    style.fixedFamily=familyID
    style.colorResolver=function(k,alpha) return S:Color(familyID,k,alpha) end
    style.fontResolver=function(region,size,weight) S:Font(familyID,region,size,weight) end
    style.skinner=function(frame,fill,corner,alpha,shadow) return S:Skin(style,frame,fill,corner,alpha,shadow) end
    return style
end

-- /bv style: what the style families resolve to in the client and how the
-- master loot window's surfaces are really painted (read only). Measures the
-- "Match my UI" borders on Florian's client (2026-10-07).
local function fmt(...)
    local out={}
    for i=1,select("#",...) do local v=select(i,...);out[#out+1]=type(v)=="number" and string.format("%.3f",v) or tostring(v) end
    return table.concat(out," ")
end
local function surface(name,frame,out)
    local skin=type(frame)=="table" and frame.bvFamilySkin
    if not skin then out[#out+1]=name..": no family skin";return end
    local kinds={}
    for kind,p in pairs(skin.kinds) do kinds[#kinds+1]=kind..(p.all[1]:IsShown() and "*" or "") end
    out[#out+1]=name..": kinds "..table.concat(kinds,",").." hidden="..tostring(frame.surfaceHidden==true).." owned="..tostring(frame.bvSurfacePaint~=nil)
    for kind,p in pairs(skin.kinds) do
        if p.all[1]:IsShown() then
            local b,i,f=p.borders[1],p.inner[1],p.fills[1]
            out[#out+1]="  border vertex "..fmt(b:GetVertexColor()).." alpha "..fmt(b:GetAlpha()).." layer "..fmt(b:GetDrawLayer())
            if i then out[#out+1]="  inner vertex "..fmt(i:GetVertexColor()).." alpha "..fmt(i:GetAlpha()).." shown "..tostring(i:IsShown()) end
            out[#out+1]="  fill vertex "..fmt(f:GetVertexColor()).." alpha "..fmt(f:GetAlpha())
        end
    end
    if frame.bvSurfacePaint then
        local e=frame.bvSurfacePaint[2]
        out[#out+1]="  last paint edge "..fmt(e[1],e[2],e[3],e[4])
    end
end
function S:Report()
    local out={"Style families (Core "..ns.version..")","suite family "..self:SuiteFamily()}
    for _,id in ipairs({"loot","combat_text","experience_bar","reputation_bar"}) do out[#out+1]=id..": "..(self:Family(id)) end
    local external=self:External()
    out[#out+1]="external colours: "..(external and "found" or "none")
    if external then for _,key in ipairs({"edge","bg","panel","accent"}) do local c=external[key];out[#out+1]="  "..key.." "..(c and fmt(c[1],c[2],c[3],c[4]) or "nil") end end
    local eui=rawget(_G,"EllesmereUI")
    if type(eui)=="table" then
        if type(eui.GetTooltipBg)=="function" then out[#out+1]="raw bg "..fmt(pcall(eui.GetTooltipBg)) end
        if type(eui.GetTooltipBorder)=="function" then out[#out+1]="raw border "..fmt(pcall(eui.GetTooltipBorder)) end
    end
    local style=UI:GameStyle("loot")
    out[#out+1]="loot style edge(.7) "..fmt(style:Color("edge",.7)).." edge() "..fmt(style:Color("edge"))
    local w=rawget(_G,"BVLootMasterWindow")
    if w then
        surface("window",w,out)
        surface("award button",w.award,out)
        surface("preset dropdown",w.preset,out)
    else out[#out+1]="master loot window not built yet (open it once)" end
    return out
end
ns.Commands:RegisterAction("style",function()
    local ok,lines=pcall(S.Report,S)
    ns.UI:DiagnosticReport("Style families",ok and table.concat(lines,"\n") or ("Report failed: "..tostring(lines)))
end)
