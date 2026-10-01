-- Shared adapter for Blizzard-owned buttons (bag bar, micro menu). Buttons are
-- borrowed, never replaced: parent, points, size and scale are recorded once and
-- given back on Release; hidden Blizzard art keeps its alpha for restoration.
-- Arranging happens outside combat only. Nothing is created before Enable.
local _,ns=...
local UI,K,Theme=ns.UI,ns.IconSkins,ns.Theme
local N={records=setmetatable({},{__mode="k"}),masked=setmetatable({},{__mode="k"}),bars={}}
ns.NativeButtons=N

-- Skins offered for borrowed buttons; Masque owns its own groups elsewhere.
function N.SkinChoices()
    local out={}
    for _,id in ipairs(K.styles) do if id~="masque" then out[#out+1]={value=id,label=K.labels[id]} end end
    return out
end
function N.ShapeChoices(skin)
    local out={}
    for _,shape in ipairs(K.Shapes(skin)) do out[#out+1]={value=shape,label=K.shapeLabels[shape]} end
    return out
end
local function clamp(value,fallback,low,high,whole)
    value=tonumber(value);if not value or value~=value then value=fallback end
    if whole then value=math.floor(value+.5) end
    return math.max(low,math.min(high,value))
end
N.Clamp=clamp

function N:Usable(button)
    return type(button)=="table" and type(button.SetParent)=="function" and type(button.ClearAllPoints)=="function"
        and not (button.IsProtected and button:IsProtected())
end
function N:Capture(button)
    local r=self.records[button];if r then return r end
    r={parent=button:GetParent(),width=button:GetWidth(),height=button:GetHeight(),points={},
        scale=button.GetScale and button:GetScale() or 1,alpha=button:GetAlpha(),
        mouse=button.IsMouseEnabled and button:IsMouseEnabled(),level=button.GetFrameLevel and button:GetFrameLevel()}
    for i=1,(button.GetNumPoints and button:GetNumPoints() or 0) do r.points[i]={button:GetPoint(i)} end
    self.records[button]=r;return r
end
function N:Borrowed(button) return self.records[button]~=nil end
function N:Restore(button)
    local r=self.records[button];if not r then return end
    self.records[button]=nil
    if button:GetParent()~=r.parent then button:SetParent(r.parent) end
    if r.level and button.SetFrameLevel then button:SetFrameLevel(r.level) end
    button:ClearAllPoints()
    for _,p in ipairs(r.points) do button:SetPoint(unpack(p)) end
    if r.width>0 and r.height>0 then button:SetSize(r.width,r.height) end
    if button.SetScale then button:SetScale(r.scale) end
    button:SetAlpha(r.alpha or 1)
    if r.mouse~=nil and button.EnableMouse then button:EnableMouse(r.mouse) end
end
-- Alpha masking; a one-time hook keeps Blizzard's later SetAlpha calls at 0
-- while masked and remembers the wanted value for Unmask.
function N:Mask(region)
    if type(region)~="table" or type(region.SetAlpha)~="function" or self.masked[region] then return end
    self.masked[region]={alpha=region:GetAlpha()}
    region:SetAlpha(0)
    if not region.bvNativeMaskHook then
        region.bvNativeMaskHook=true
        hooksecurefunc(region,"SetAlpha",function(r,value)
            local m=N.masked[r];if m and value~=0 then m.alpha=value;r:SetAlpha(0) end
        end)
    end
end
function N:Unmask(region)
    local m=self.masked[region];if not m then return end
    self.masked[region]=nil;region:SetAlpha(m.alpha)
end

-- Texture regions of a Blizzard button, minus the ones named in keep.
function N.Art(button,keep)
    local out={}
    if not button.GetRegions then return out end
    for _,region in ipairs({button:GetRegions()}) do
        if region.GetObjectType and region:GetObjectType()=="Texture" and not region.bvNativeOwned and not (keep and keep[region]) then out[#out+1]=region end
    end
    return out
end
-- Grid geometry. perLine buttons along the main axis; vertical swaps axes.
function N.Grid(count,perLine,vertical)
    count=math.max(1,count);perLine=math.max(1,perLine)
    local along,across=math.min(count,perLine),math.ceil(count/perLine)
    if vertical then return across,along end
    return along,across
end
function N.Extent(count,size,spacing,perLine,vertical)
    local cols,rows=N.Grid(count,perLine,vertical)
    return cols*size+(cols-1)*spacing,rows*size+(rows-1)*spacing
end
function N.SizeForWidth(width,count,spacing,perLine,vertical,low,high)
    local cols=N.Grid(count,perLine,vertical)
    return clamp(math.floor((width-(cols-1)*spacing)/cols),low,low,high,true)
end
function N.Place(buttons,host,size,spacing,perLine,vertical)
    for i,button in ipairs(buttons) do
        local line,pos=math.floor((i-1)/perLine),(i-1)%perLine
        local col,row=pos,line;if vertical then col,row=line,pos end
        local x,y=col*(size+spacing),-row*(size+spacing)
        -- Remembered so an outside move can be undone at once (see bar:Watch).
        button.bvPlaced={host,x,y}
        button:ClearAllPoints();button:SetSize(size,size)
        button:SetPoint("TOPLEFT",host,"TOPLEFT",x,y)
    end
end

-- Skin plate on a borrowed button: background below the button's own art, rim,
-- hover/pressed states and an optional Lucide symbol above it.
function UI:NativePlate(button)
    local plate={button=button}
    plate.fill=button:CreateTexture(nil,"BACKGROUND",nil,-8);plate.fill.bvNativeOwned=true
    plate.frame=CreateFrame("Frame",nil,button);plate.frame:SetAllPoints(button);plate.frame:EnableMouse(false)
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(plate.frame) end
    local f=plate.frame
    plate.symbol=f:CreateTexture(nil,"ARTWORK")
    plate.rim=f:CreateTexture(nil,"OVERLAY",nil,2)
    plate.pushed=f:CreateTexture(nil,"OVERLAY",nil,3)
    plate.hover=f:CreateTexture(nil,"OVERLAY",nil,4)
    for _,t in ipairs({plate.fill,plate.rim,plate.pushed,plate.hover}) do t:SetPoint("CENTER",button,"CENTER",0,0) end
    plate.symbol:SetPoint("CENTER",button,"CENTER",0,0)
    local function states()
        if not plate.painted then return end
        plate.hover:SetAlpha(plate.over and 1 or 0)
        plate.pushed:SetAlpha((plate.down or plate.active) and 1 or 0)
        if plate.symbolName then
            local key=plate.disabled and "muted" or (plate.active or plate.over) and "accent" or "text"
            plate.symbol:SetVertexColor(Theme:Color(key,plate.disabled and .55 or 1))
        end
    end
    plate.states=states
    button:HookScript("OnEnter",function() plate.over=true;states() end)
    button:HookScript("OnLeave",function() plate.over=false;plate.down=false;states() end)
    button:HookScript("OnMouseDown",function() plate.down=true;states() end)
    button:HookScript("OnMouseUp",function() plate.down=false;states() end)
    function plate:SetActive(value) self.active=value==true;states() end
    function plate:SetDisabled(value) self.disabled=value==true;states() end
    -- opts: skin, shape, size, symbol (Lucide name or nil), icon (texture region or nil)
    function plate:Paint(opts)
        local skin=K.Valid(opts.skin) and opts.skin~="masque" and opts.skin or "none"
        local shape=K.Supports(skin,opts.shape) and opts.shape or "square"
        local size=opts.size
        self.painted=true;self.frame:Show()
        -- Background / border switches (0.8.78); hover and pressed stay.
        self.fill:SetShown(opts.background~=false);self.showRim=opts.border~=false
        for _,t in ipairs({self.fill,self.rim,self.pushed,self.hover}) do t:SetSize(size,size) end
        self:Unmask()
        local maskPath=K.Mask(skin,shape)
        if maskPath and button.CreateMaskTexture then
            self.mask=self.mask or button:CreateMaskTexture()
            self.mask:ClearAllPoints();self.mask:SetPoint("CENTER",button,"CENTER",0,0);self.mask:SetSize(size,size)
            self.mask:SetTexture(maskPath,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
            self.fill:AddMaskTexture(self.mask);self.maskedFill=true
        end
        self.fill:SetColorTexture(Theme:Color("canvas",.92))
        if skin=="none" then
            self.rim:SetAlpha(0)
            self.pushed:SetColorTexture(Theme:Color("accent",.22));self.pushed:SetTexCoord(0,1,0,1)
            self.hover:SetColorTexture(1,1,1,.12);self.hover:SetTexCoord(0,1,0,1);self.hover:SetBlendMode("BLEND")
        else
            local path=K.Path(skin,shape)
            self.rim:SetTexture(path);self.rim:SetTexCoord(0,.5,0,.5);self.rim:SetAlpha(self.showRim and 1 or 0)
            self.pushed:SetTexture(path);self.pushed:SetTexCoord(.5,1,0,.5)
            self.hover:SetTexture(path);self.hover:SetTexCoord(0,.5,.5,1);self.hover:SetBlendMode("ADD")
        end
        self.symbolName=opts.symbol
        local pathS,l,r,t,b
        if opts.symbol then pathS,l,r,t,b=ns.Symbols:Coords(opts.symbol,size*.6) end
        if pathS then
            self.symbol:SetTexture(pathS);self.symbol:SetTexCoord(l,r,t,b);self.symbol:SetSize(size*.6,size*.6);self.symbol:Show()
        else self.symbolName=nil;self.symbol:Hide() end
        local icon=opts.icon
        if icon then
            if not self.iconState then
                local points={}
                for i=1,(icon.GetNumPoints and icon:GetNumPoints() or 0) do points[i]={icon:GetPoint(i)} end
                -- Blizzard's own icon masks (round bag slots) are lent to us too.
                local masks={}
                if icon.GetNumMaskTextures then
                    for i=icon:GetNumMaskTextures(),1,-1 do local m=icon:GetMaskTexture(i);masks[#masks+1]=m;icon:RemoveMaskTexture(m) end
                end
                self.iconState={points=points,coords=icon.GetTexCoord and {icon:GetTexCoord()} or nil,icon=icon,masks=masks,
                    width=icon:GetWidth(),height=icon:GetHeight()}
            end
            local scale=skin=="echo" and 1 or skin=="none" and .9 or .75
            icon:ClearAllPoints();icon:SetPoint("CENTER",button,"CENTER",0,0);icon:SetSize(size*scale,size*scale)
            icon:SetTexCoord(.08,.92,.08,.92)
            local iconMask=K.Mask(skin,shape)
            if iconMask and button.CreateMaskTexture and icon.AddMaskTexture then
                self.iconMask=self.iconMask or button:CreateMaskTexture()
                self.iconMask:ClearAllPoints();self.iconMask:SetAllPoints(icon)
                self.iconMask:SetTexture(iconMask,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
                icon:AddMaskTexture(self.iconMask);self.iconMasked=true
            end
        end
        states()
    end
    function plate:Unmask()
        if self.maskedFill then self.fill:RemoveMaskTexture(self.mask);self.maskedFill=nil end
        if self.iconMasked and self.iconState then self.iconState.icon:RemoveMaskTexture(self.iconMask);self.iconMasked=nil end
    end
    function plate:Release()
        self:Unmask();self.painted=nil
        self.frame:Hide();self.fill:Hide()
        local s=self.iconState
        if s then
            self.iconState=nil
            s.icon:ClearAllPoints()
            if #s.points>0 then for _,p in ipairs(s.points) do s.icon:SetPoint(unpack(p)) end else s.icon:SetAllPoints(button) end
            if s.coords and #s.coords>=4 then s.icon:SetTexCoord(unpack(s.coords)) else s.icon:SetTexCoord(0,1,0,1) end
            if s.width>0 and s.height>0 then s.icon:SetSize(s.width,s.height) end
            for _,m in ipairs(s.masks) do s.icon:AddMaskTexture(m) end
        end
    end
    return plate
end

-- A bar of borrowed buttons with its own layout element, option store, optional
-- mouseover fade and an optional collapsed mode (one main button + flyout).
-- def: id (module), layout, label, anchor/x/y, defaults (option table),
-- entries(cfg) -> {{key,button,symbol,icon,art={regions}}}, install(bar) hooks
-- Blizzard relayouts once, restore() lets Blizzard lay out again, main (optional):
-- {symbol,label,click(button),text()} for the collapsed mode.
function N:Bar(def)
    local bar={def=def,plates={},entries={},masks=setmetatable({},{__mode="k"}),parked=setmetatable({},{__mode="k"}),decorMasked={}}
    self.bars[def.id]=bar
    function bar:Config()
        local cfg=ns.Settings:Module(def.id)
        for key,value in pairs(def.defaults) do if cfg[key]==nil then cfg[key]=value end end
        cfg.skin=K.Valid(cfg.skin) and cfg.skin~="masque" and cfg.skin or def.defaults.skin
        cfg.shape=K.Supports(cfg.skin,cfg.shape) and cfg.shape or "square"
        cfg.spacing=clamp(cfg.spacing,def.defaults.spacing,0,24,true)
        cfg.perLine=clamp(cfg.perLine,def.defaults.perLine,1,24,true)
        cfg.size=clamp(cfg.size,def.defaults.size,16,64,true)
        cfg.fadeAlpha=clamp(cfg.fadeAlpha,def.defaults.fadeAlpha,0,1)
        cfg.vertical=cfg.vertical==true;cfg.fade=cfg.fade==true;cfg.collapsed=def.main~=nil and cfg.collapsed==true
        cfg.background=cfg.background~=false;cfg.border=cfg.border~=false;cfg.blizzardFrame=cfg.blizzardFrame==true
        cfg.barBackground=cfg.barBackground==true
        if type(cfg.barColor)~="string" or not cfg.barColor:match("^%x%x%x%x%x%x%x%x$") then cfg.barColor="0D0B10E6" end
        if cfg.flyout~="UP" and cfg.flyout~="DOWN" and cfg.flyout~="LEFT" and cfg.flyout~="RIGHT" then cfg.flyout="UP" end
        return cfg
    end
    function bar:Enabled() return ns.Settings:Module(def.id).enabled==true end
    -- Number of cells on the layout surface (collapsed: only the main button).
    function bar:Count(cfg)
        if cfg.collapsed then return 1 end
        local n=0
        for _,e in ipairs(def.entries(cfg)) do if not e.hidden and e.button:IsShown() then n=n+1 end end
        return math.max(1,n)
    end
    -- Room around the buttons for the solid bar background. The layout element
    -- includes it, so smart alignment and snapping use the visible edge.
    function bar:Pad(cfg)
        return (cfg.barBackground and not cfg.collapsed) and math.max(2,cfg.spacing) or 0
    end
    -- Size of the buttons alone (the host frame).
    function bar:Inner(cfg,size)
        local count=self:Count(cfg)
        return N.Extent(count,size or cfg.size,cfg.spacing,cfg.collapsed and 1 or cfg.perLine,cfg.vertical)
    end
    function bar:Extent(cfg,size)
        local w,h=self:Inner(cfg,size)
        local pad=self:Pad(cfg)
        return w+2*pad,h+2*pad
    end
    -- The size option leads. Only while the Layout Editor runs does the dragged
    -- width set the size; saving the layout writes it back to the option.
    function bar:SizeFromWidth(width,cfg)
        return N.SizeForWidth(width-2*self:Pad(cfg),self:Count(cfg),cfg.spacing,cfg.collapsed and 1 or cfg.perLine,cfg.vertical,16,64)
    end
    function bar:SizeFor(rect,cfg)
        if ns.Layout.draft then return self:SizeFromWidth(rect.width,cfg) end
        return cfg.size
    end
    -- The saved width can be stale (seeded before Blizzard's buttons existed or
    -- while the bag bar was collapsed); bring it in line after arranging.
    function bar:SyncWidth()
        if self.syncTimer then return end
        self.syncTimer=C_Timer.NewTimer(0,function()
            self.syncTimer=nil
            if ns.Layout.draft or not self.active then return end
            local cfg=self:Config()
            ns.Layout:Change(def.layout,{width=(self:Extent(cfg,cfg.size))})
            self.synced=true
        end)
    end
    ns.Layout:AfterSave(bar,function()
        if ns.Layout.draft or not bar.synced then return end
        local stored=ns.Layout:Store()[def.layout];if not stored then return end
        local cfg=bar:Config()
        if math.abs(stored.width-(bar:Extent(cfg,cfg.size)))<=.5 then return end
        cfg.size=bar:SizeFromWidth(stored.width,cfg)
        bar:Arrange();bar:SyncWidth()
        if ns.Config then ns.Config:Refresh() end
    end)
    ns.Layout:Register(def.layout,{label=def.label,autoHeight=true,
        limits={minWidth=16,maxWidth=1600,minHeight=16,maxHeight=1600},
        defaults=function()
            local cfg=bar:Config();local w,h=bar:Extent(cfg)
            return {width=w,height=h,screen=def.anchor,x=def.x,y=def.y}
        end,
        measure=function(rect)
            local cfg=bar:Config();local w,h=bar:Extent(cfg,bar:SizeFor(rect,cfg))
            return h,w
        end,
        apply=function(rect,allowed) bar:Apply(rect,allowed) end,
        enabled=function() return bar:Enabled() end,
        preview=function(value) bar.preview=value==true;bar:Arrange() end})

    function bar:Frames()
        if self.host then return end
        self.host=CreateFrame("Frame",nil,UIParent);self.host:SetFrameStrata("MEDIUM");self.host:Hide()
        self.parking=CreateFrame("Frame",nil,UIParent);self.parking:Hide()
        for _,f in ipairs({self.host,self.parking}) do if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end end
        self.host:HookScript("OnEnter",function() bar:Hover(true) end)
        self.host:HookScript("OnLeave",function() bar:Hover(false) end)
        if def.main then
            local main=CreateFrame("Button",nil,self.host);self.main=main
            main:RegisterForClicks("LeftButtonUp","RightButtonUp")
            main:SetScript("OnClick",function(_,button)
                if button=="RightButton" then bar.pinned=not bar.pinned;bar:ShowFlyout(bar.pinned)
                else ns:Call(def.id.."/main",def.main.click) end
            end)
            main:SetScript("OnEnter",function(button)
                bar:Hover(true);bar:ShowFlyout(true)
                if GameTooltip then
                    GameTooltip:SetOwner(button,"ANCHOR_LEFT");GameTooltip:SetText(def.main.label)
                    GameTooltip:AddLine(def.main.hint,1,1,1,true);GameTooltip:Show()
                end
            end)
            main:SetScript("OnLeave",function() bar:Hover(false);if GameTooltip then GameTooltip:Hide() end end)
            main.bvCount=main:CreateFontString(nil,"OVERLAY");Theme:Font(main.bvCount,11,Theme:BoldFont())
            main.bvCount:SetPoint("BOTTOMRIGHT",main,"BOTTOMRIGHT",-2,2)
            self.mainPlate=UI:NativePlate(main)
            self.flyout=CreateFrame("Frame",nil,self.host);self.flyout:Hide()
            self.flyout:HookScript("OnEnter",function() bar:Hover(true) end)
            self.flyout:HookScript("OnLeave",function() bar:Hover(false) end)
            if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(main);ns.ExternalFrames:MarkOwned(self.flyout) end
        end
    end
    function bar:Editing() return ns.LayoutEditor and ns.LayoutEditor.active==true end
    -- Mouseover: fade the whole bar, and in collapsed mode show the flyout.
    function bar:Hover(over)
        self.over=over
        if self.leaveTimer then self.leaveTimer:Cancel();self.leaveTimer=nil end
        if over then self:FadeTo(1);return end
        self.leaveTimer=C_Timer.NewTimer(.35,function()
            self.leaveTimer=nil
            if self.over then return end
            if self.host and self.host.IsMouseOver and self.host:IsMouseOver() then return end
            if self.flyout and self.flyout:IsShown() and self.flyout.IsMouseOver and self.flyout:IsMouseOver() then return end
            if not self.pinned then self:ShowFlyout(false) end
            self:FadeTo(self:RestingAlpha())
        end)
    end
    function bar:RestingAlpha()
        local cfg=self:Config()
        if not cfg.fade or self:Editing() or self.preview then return 1 end
        return cfg.fadeAlpha
    end
    -- Bar opacity. Buttons that stay with their Blizzard parent (reparent=false)
    -- do not inherit the host alpha and get it directly; parked ones stay at 0.
    function bar:SetBarAlpha(value)
        self.host:SetAlpha(value)
        if self.backdrop and self.backdrop:GetParent()~=self.host then self.backdrop:SetAlpha(value) end
        if def.reparent==false then
            for _,e in ipairs(self.entries) do if not self.parked[e.button] then e.button:SetAlpha(value) end end
        end
    end
    function bar:FadeTo(target)
        if not self.host then return end
        if self.fader then self.fader:Cancel();self.fader=nil end
        local start=self.host:GetAlpha();local steps=6;local step=0
        if math.abs(start-target)<.01 then self:SetBarAlpha(target);return end
        self.fader=C_Timer.NewTicker(.03,function()
            step=step+1;self:SetBarAlpha(start+(target-start)*step/steps)
            if step>=steps and self.fader then self.fader:Cancel();self.fader=nil end
        end)
    end
    function bar:ShowFlyout(show)
        if not self.flyout then return end
        local cfg=self:Config()
        self.flyout:SetShown(cfg.collapsed and (show or self.pinned or self:Editing()) or false)
    end
    function bar:Apply(rect,allowed)
        self.rect=rect;self.allowed=allowed~=false
        self:Arrange()
    end
    function bar:Queue()
        if self.queued or not self.active then return end
        self.queued=C_Timer.NewTimer(0,function() self.queued=nil;self:Arrange() end)
    end
    function bar:Watch(button)
        if button.bvNativeWatch then return end
        button.bvNativeWatch=true
        -- OnShow/OnHide also fire when the flyout or host hides; only Blizzard's
        -- own Show/Hide of the button changes the arrangement.
        local function changed()
            if not bar.active or bar.arranging then return end
            if button:IsShown()~=button.bvNativeShown then bar:Queue() end
        end
        button:HookScript("OnShow",changed)
        button:HookScript("OnHide",changed)
        button:HookScript("OnEnter",function() if bar.active then bar:Hover(true) end end)
        button:HookScript("OnLeave",function() if bar.active then bar:Hover(false) end end)
        -- Blizzard re-anchors its buttons on its own occasions (bag updates while
        -- looting), not only in the hooked Layout. An outside SetPoint is undone
        -- right away, before the frame is drawn (like ElvUI); waiting for the
        -- next frame showed the button jumping. A full arrange follows next frame.
        if hooksecurefunc then
            hooksecurefunc(button,"SetPoint",function(b)
                if not bar.active or bar.arranging or b.bvSnapping then return end
                local placed=b.bvPlaced
                if placed and placed[1] and placed[1]:IsShown() then
                    b.bvSnapping=true
                    b:ClearAllPoints();b:SetPoint("TOPLEFT",placed[1],"TOPLEFT",placed[2],placed[3])
                    b.bvSnapping=nil
                end
                bar:Queue()
            end)
        end
    end
    function bar:Raise(entries)
        local origin
        for _,e in ipairs(entries) do
            if not e.hidden and N:Usable(e.button) then
                local r=N.records[e.button]
                origin=r and r.parent or e.button:GetParent()
                if origin and origin~=self.host and origin~=self.flyout and origin~=self.parking then break end
                origin=nil
            end
        end
        if not origin or not origin.GetFrameLevel then return end
        local strata=origin.GetFrameStrata and origin:GetFrameStrata()
        if strata then self.host:SetFrameStrata(strata) end
        self.host:SetFrameLevel(math.max(self.host:GetFrameLevel(),origin:GetFrameLevel()+10))
        self.raisedAbove=origin
    end
    function bar:Borrow(e,parent)
        local b=e.button
        local record=N:Capture(b);self:Watch(b)
        if def.reparent==false then
            -- Micro menu (0.8.76): changing the parent makes Blizzard lay the menu
            -- out while a button has no position (GetEdgeButton compares nil).
            -- The button stays a MicroMenu child and is only anchored to our host.
            local owner=b:GetParent()
            local scale=self.host:GetEffectiveScale()/math.max(.01,owner and owner:GetEffectiveScale() or 1)
            if b.SetScale then b:SetScale(scale) end
            if e.hidden then
                if not self.parked[b] then self.parked[b]=true;N:Mask(b);b:EnableMouse(false) end
            elseif self.parked[b] then
                self.parked[b]=nil;N:Unmask(b);if record.mouse~=nil then b:EnableMouse(record.mouse) end
            end
        else
            if b:GetParent()~=parent then b:SetParent(parent) end
            if b.SetScale then b:SetScale(1) end
            if b.SetFrameLevel and parent.GetFrameLevel then b:SetFrameLevel(parent:GetFrameLevel()+1) end
        end
        b.bvNativeShown=b:IsShown()
        local wanted={}
        for _,region in ipairs(e.art or {}) do wanted[region]=true;N:Mask(region) end
        for _,region in ipairs(self.masks[b] or {}) do if not wanted[region] then N:Unmask(region) end end
        self.masks[b]=e.art or {}
    end
    function bar:Arrange()
        if not self.active or self.arranging then return end
        if InCombatLockdown() then self.pending=true;return end
        self.pending=nil
        local rect=self.rect
        if not rect or not self.allowed or rect.width<=0 or rect.height<=0 then
            if self.host then self.host:Hide() end;return
        end
        self.arranging=true
        local ok,err=pcall(function()
            self:Frames()
            local cfg=self:Config();local size=self:SizeFor(rect,cfg)
            local w,h=self:Extent(cfg,size)
            if not ns.Layout.draft then
                local stored=ns.Layout:Store()[def.layout]
                if stored and math.abs(stored.width-w)>.5 then self:SyncWidth() else self.synced=true end
            end
            -- The buttons sit centred in the element; the background fills the margin.
            local iw,ih=self:Inner(cfg,size)
            self.host:ClearAllPoints();self.host:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y);self.host:SetSize(iw,ih)
            self.host:EnableMouse(cfg.fade)
            local entries=def.entries(cfg);self.entries=entries
            -- Reparented buttons sit above their old Blizzard bar: it stays where it
            -- was and can take the mouse (bag slots were not clickable there).
            if def.reparent~=false then self:Raise(entries) end
            local visible={}
            local target=cfg.collapsed and self.flyout or self.host
            for _,e in ipairs(entries) do
                if N:Usable(e.button) then
                    self:Borrow(e,e.hidden and self.parking or target)
                    if not e.hidden and e.button:IsShown() then visible[#visible+1]=e.button end
                    local plate=self.plates[e.button]
                    if not plate then plate=UI:NativePlate(e.button);self.plates[e.button]=plate end
                    -- plain: Blizzard art stays, only position and size are ours.
                    if e.plain then plate:Release() else plate:Paint({skin=cfg.skin,shape=cfg.shape,size=size,symbol=e.symbol,icon=e.icon,background=cfg.background,border=cfg.border}) end
                    if e.state and not e.plain then plate:SetActive(e.state.active);plate:SetDisabled(e.state.disabled) end
                end
            end
            if cfg.collapsed then
                local main=self.main;main:Show()
                main:ClearAllPoints();main:SetPoint("TOPLEFT",self.host,"TOPLEFT",0,0);main:SetSize(size,size)
                self.mainPlate:Paint({skin=cfg.skin,shape=cfg.shape,size=size,symbol=def.main.symbol})
                self:Count_(cfg)
                local vertical=cfg.flyout=="UP" or cfg.flyout=="DOWN"
                local fw,fh=N.Extent(#visible,size,cfg.spacing,math.max(1,#visible),vertical)
                self.flyout:ClearAllPoints();self.flyout:SetSize(fw,fh)
                local gap=cfg.spacing+2
                if cfg.flyout=="UP" then self.flyout:SetPoint("BOTTOM",main,"TOP",0,gap)
                elseif cfg.flyout=="DOWN" then self.flyout:SetPoint("TOP",main,"BOTTOM",0,-gap)
                elseif cfg.flyout=="LEFT" then self.flyout:SetPoint("RIGHT",main,"LEFT",-gap,0)
                else self.flyout:SetPoint("LEFT",main,"RIGHT",gap,0) end
                -- The backpack (last) sits next to the main button: reverse when
                -- the flyout grows down or right, where the first cell is nearest.
                local ordered=visible
                if cfg.flyout=="DOWN" or cfg.flyout=="RIGHT" then
                    ordered={};for i=#visible,1,-1 do ordered[#ordered+1]=visible[i] end
                end
                N.Place(ordered,self.flyout,size,cfg.spacing,math.max(1,#ordered),vertical)
                self:ShowFlyout(self.over)
            else
                if self.main then self.main:Hide();self.flyout:Hide() end
                N.Place(visible,self.host,size,cfg.spacing,cfg.perLine,cfg.vertical)
            end
            self:Decor(cfg)
            self:Backdrop(cfg,visible)
            self.host:Show()
            if not self.over then
                if self.fader then self.fader:Cancel();self.fader=nil end
                self:SetBarAlpha(self:RestingAlpha())
            end
        end)
        self.arranging=false
        if not ok then ns:Report(def.id,err) end
    end
    function bar:Count_(cfg)
        if not self.main then return end
        local text=cfg.showCount~=false and def.main.text and def.main.text() or ""
        self.main.bvCount:SetText(text or "")
    end
    function bar:UpdateText() if self.active and self.main then self:Count_(self:Config()) end end
    -- Option changes keep the current button size: the layout width follows.
    function bar:Changed()
        local cfg=self:Config()
        local w=self:Extent(cfg,cfg.size)
        ns.Layout:Change(def.layout,{width=w})
        self:Arrange()
        if ns.Config then ns.Config:Refresh() end
    end
    function bar:Enable(context)
        self.active=true
        if def.install and not self.installed then self.installed=true;def.install(self) end
        context:Subscribe("PLAYER_REGEN_ENABLED",function() if self.pending then self:Arrange() end end)
        context:Subscribe("PLAYER_ENTERING_WORLD",function() self:Queue() end)
        for _,event in ipairs(def.events or {}) do context:Subscribe(event,function(...) def.onEvent(self,...) end) end
        context:Defer(function() self:Disable() end)
        ns.Layout:Refresh(true)
    end
    -- Solid bar background (0.8.79), a replacement for Blizzard's bar art. It must
    -- sit below the buttons: with reparent=false the buttons stay children of
    -- their Blizzard parent, so the backdrop joins that parent one level lower.
    function bar:Backdrop(cfg,visible)
        local owner=self.host
        if def.reparent==false and visible[1] and visible[1]:GetParent() then owner=visible[1]:GetParent() end
        if not self.backdrop or self.backdrop:GetParent()~=owner then
            if self.backdrop then self.backdrop:Hide() end
            self.backdrop=CreateFrame("Frame",nil,owner);self.backdrop:EnableMouse(false)
            -- Blizzard's layout frames (MicroMenu is a GridLayoutFrame) skip such children.
            self.backdrop.ignoreInLayout=true
            self.backdrop.fill=self.backdrop:CreateTexture(nil,"BACKGROUND");self.backdrop.fill:SetAllPoints(self.backdrop)
            if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(self.backdrop) end
        end
        local b=self.backdrop
        b:SetShown(cfg.barBackground and not cfg.collapsed)
        if not b:IsShown() then return end
        local pad=self:Pad(cfg)
        b:ClearAllPoints();b:SetPoint("TOPLEFT",self.host,"TOPLEFT",-pad,pad);b:SetPoint("BOTTOMRIGHT",self.host,"BOTTOMRIGHT",pad,-pad)
        if owner~=self.host then
            local level=visible[1]:GetFrameLevel()
            for _,button in ipairs(visible) do level=math.min(level,button:GetFrameLevel()) end
            b:SetFrameStrata(visible[1]:GetFrameStrata());b:SetFrameLevel(math.max(0,level-1))
            b:SetScale(self.host:GetEffectiveScale()/math.max(.01,owner:GetEffectiveScale()))
        end
        b.fill:SetColorTexture(UI:RGBA(cfg.barColor))
    end
    -- Blizzard's own bar frame and dividers (def.decor): hidden with alpha 0 while
    -- the module runs unless "Show Blizzard bar frame" is on (0.8.78).
    function bar:Decor(cfg)
        local wanted={}
        if def.decor and not cfg.blizzardFrame then
            local ok,list=pcall(def.decor)
            if ok and type(list)=="table" then for _,r in ipairs(list) do wanted[r]=true;N:Mask(r) end end
        end
        for r in pairs(self.decorMasked) do if not wanted[r] then N:Unmask(r) end end
        self.decorMasked=wanted
    end
    function bar:Disable()
        self.active=false;self.pinned=nil
        for r in pairs(self.decorMasked) do N:Unmask(r) end;self.decorMasked={}
        if self.backdrop then self.backdrop:Hide() end
        for _,t in ipairs({"queued","leaveTimer","fader","syncTimer"}) do if self[t] then self[t]:Cancel();self[t]=nil end end
        for button,plate in pairs(self.plates) do plate:Release() end
        for button,regions in pairs(self.masks) do for _,region in ipairs(regions) do N:Unmask(region) end;self.masks[button]=nil end
        for b in pairs(self.parked) do N:Unmask(b);self.parked[b]=nil end
        for _,e in ipairs(self.entries) do N:Restore(e.button) end
        self.entries={}
        if self.host then self.host:Hide() end
        if def.restore then ns:Call(def.id.."/restore",def.restore) end
    end
    return bar
end
