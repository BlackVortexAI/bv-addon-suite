local _,ns=...
-- Notification stage (Core 0.8.95, docs/map-quest-concept.md): cinematic
-- messages in the upper middle of the screen, one after another. Packages
-- register message types (ns.Stage:Register) and send messages
-- (ns.Stage:Show). Without a registered type the stage stays hidden and its
-- settings page does not exist (Florian: active only when a module is there).
-- Look: an in-game style context of its own ("stage"), inheriting the suite.
local UI,M=ns.UI,ns.DesignSystem.Metrics
local Stage={types={},order={},queue={},seq=0,MAX=5,FADE_IN=.3,FADE_OUT=.5}
ns.Stage=Stage
Stage.ID="stage"
local ANIMATIONS={fade=true,slide=true,reveal=true,zoom=true,lowerthird=true,none=true}
local DEFAULTS={styleFamily="inherit",titleSize=30,subtitleSize=15,animation="fade",line=true}

local function num(value,default,low,high)
    if type(value)~="number" or value~=value then value=default end
    return math.max(low,math.min(high,math.floor(value+.5)))
end
function Stage:Config()
    local cfg=ns.Settings:Module(self.ID)
    for key,value in pairs(DEFAULTS) do if cfg[key]==nil then cfg[key]=value end end
    if cfg.styleFamily~="inherit" and not ns.Styles.families[cfg.styleFamily] then cfg.styleFamily="inherit" end
    cfg.titleSize=num(cfg.titleSize,30,16,60);cfg.subtitleSize=num(cfg.subtitleSize,15,10,30)
    if not ANIMATIONS[cfg.animation] then cfg.animation="fade" end
    cfg.line=cfg.line~=false
    if type(cfg.types)~="table" then cfg.types={} end
    return cfg
end
function Stage:TypeConfig(id)
    local types=self:Config().types
    local def=self.types[id]
    local t=types[id]
    if type(t)~="table" then t={};types[id]=t end
    if type(t.enabled)~="boolean" then t.enabled=def.enabled~=false end
    t.hold=num(t.hold,def.hold or 4,1,15)
    return t
end
function Stage:HasTypes() return #self.order>0 end

-- def: id (lower case), label, description, priority (1 normal .. 3 urgent,
-- urgent ones go first), hold (seconds), sample={title,subtitle} for tests.
function Stage:Register(def)
    assert(type(def)=="table" and type(def.id)=="string" and def.id:match("^[a-z][a-z0-9_]*$") and type(def.label)=="string","Invalid stage message type")
    assert(not self.types[def.id],"Duplicate stage message type")
    def.priority=num(def.priority,1,1,3)
    self.types[def.id]=def;self.order[#self.order+1]=def.id
    self:Page();self:Element()
    -- Packages register while loading; the layout follows once settings exist.
    if ns.Layout and ns.Settings.db then ns.Layout:Refresh(true) end
    return true
end

-- msg: title, subtitle, color {r,g,b} for the title, key (same key replaces a
-- waiting or showing message of this type, e.g. quest progress 4/12 -> 5/12).
function Stage:Show(id,msg)
    local def=self.types[id]
    if not def or type(msg)~="table" or type(msg.title)~="string" then return false end
    local t=self:TypeConfig(id)
    if not t.enabled then return false end
    self.seq=self.seq+1
    local entry={id=id,title=msg.title,subtitle=msg.subtitle,color=msg.color,priority=def.priority,hold=t.hold,seq=self.seq,
        key=msg.key and (id..":"..tostring(msg.key)) or nil}
    if entry.key and self.current and self.current.key==entry.key then
        self.current=entry;self:Paint(entry);self:Schedule(entry,true);return true
    end
    if entry.key then
        for index,waiting in ipairs(self.queue) do
            if waiting.key==entry.key then entry.seq=waiting.seq;self.queue[index]=entry;return true end
        end
    end
    local at=#self.queue+1
    for index,waiting in ipairs(self.queue) do if entry.priority>waiting.priority then at=index;break end end
    table.insert(self.queue,at,entry)
    while #self.queue>self.MAX do table.remove(self.queue) end
    if not self.current then self:Next() end
    return true
end
function Stage:Clear()
    self.queue={}
    self:Cancel()
    self.current=nil
    if self.frame then self.frame:Hide() end
end

-- Display ---------------------------------------------------------------------------
function Stage:Family() return (ns.Styles:Family(self.ID)) end
function Stage:Frame()
    if self.frame then return self.frame end
    local f=CreateFrame("Frame",nil,UIParent);f:Hide();f:EnableMouse(false);f:SetFrameStrata("HIGH")
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
    M.Size(f,600,90);f:SetPoint("TOP",UIParent,"TOP",0,-M.ToNative(160))
    -- Each part sits in a frame of its own with its own timeline (title,
    -- subtitle, accent line, lower-third band). Frames, because a texture's
    -- alpha is its colour's alpha in the client: animating the line itself
    -- would lose its 0.7.
    local function box() local b=CreateFrame("Frame",nil,f);b:EnableMouse(false);b:SetSize(1,1);return b end
    f.bandBox,f.lineBox,f.titleBox,f.subBox=box(),box(),box(),box()
    f.band=f.bandBox:CreateTexture(nil,"BACKGROUND");f.band:SetTexture("Interface\\Buttons\\WHITE8X8");f.band:SetAllPoints(f.bandBox)
    f.stripe=f.bandBox:CreateTexture(nil,"ARTWORK");f.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.stripe:SetPoint("TOPLEFT",f.bandBox,"TOPLEFT");f.stripe:SetPoint("BOTTOMLEFT",f.bandBox,"BOTTOMLEFT")
    f.line=f.lineBox:CreateTexture(nil,"ARTWORK");f.line:SetTexture("Interface\\Buttons\\WHITE8X8");f.line:SetAllPoints(f.lineBox)
    f.title=f.titleBox:CreateFontString(nil,"OVERLAY");f.title:SetJustifyH("CENTER");f.title:SetWordWrap(false);f.title:SetAllPoints(f.titleBox)
    f.subtitle=f.subBox:CreateFontString(nil,"OVERLAY");f.subtitle:SetJustifyH("CENTER");f.subtitle:SetWordWrap(false);f.subtitle:SetAllPoints(f.subBox)
    f.tracks={}
    for name,key in pairs({title="titleBox",subtitle="subBox",line="lineBox",band="bandBox"}) do
        local region=f[key]
        local g=region:CreateAnimationGroup();g:SetToFinalAlpha(true)
        -- A Translation only acts while it plays; afterwards the part is back at
        -- its anchor. So each entrance starts with an instant step to the start
        -- offset (order 1, 0.01 s) and then moves back by the same amount: net
        -- zero, no jump at the end (Florian, 2026-10-07: the text jumped up when
        -- the fade-in ended). A Scale does not keep an earlier step's size in the
        -- client (Florian, 2026-10-08: the zoom rebounded), so it is one
        -- animation from the start size to 1.
        local tr={group=g,region=region}
        tr.preMove=g:CreateAnimation("Translation");tr.preMove:SetOrder(1);tr.preMove:SetDuration(.01)
        tr.alpha=g:CreateAnimation("Alpha");tr.alpha:SetOrder(2)
        tr.move=g:CreateAnimation("Translation");tr.move:SetOrder(2)
        tr.scale=g:CreateAnimation("Scale");tr.scale:SetOrder(2)
        f.tracks[name]=tr
    end
    self.frame=f
    self:Apply()
    return f
end
-- Fonts, colours and geometry from the settings and the style family.
function Stage:Apply()
    local f=self.frame
    if not f then return end
    local cfg,family=self:Config(),self:Family()
    local style=UI:GameStyle(self.ID)
    ns.Styles:Font(family,f.title,M.ToNative(cfg.titleSize),"display","OUTLINE")
    ns.Styles:Font(family,f.subtitle,M.ToNative(cfg.subtitleSize),"regular","OUTLINE")
    local width=M.GetWidth(f)
    local titleH,subH=cfg.titleSize*1.4,cfg.subtitleSize*1.5
    f.titleBox:ClearAllPoints();M.Point(f.titleBox,"TOP",f,"TOP",0,0);M.Size(f.titleBox,width,titleH)
    f.lineBox:ClearAllPoints();M.Point(f.lineBox,"TOP",f.titleBox,"BOTTOM",0,-2);M.Size(f.lineBox,width*.45,1)
    f.subBox:ClearAllPoints();M.Point(f.subBox,"TOP",f.lineBox,"BOTTOM",0,-6);M.Size(f.subBox,width,subH)
    -- Lower third: a band behind both lines, an accent stripe at its left.
    f.bandBox:ClearAllPoints();M.Point(f.bandBox,"TOP",f.titleBox,"TOP",0,6);M.Size(f.bandBox,width*.7,titleH+subH+21)
    f.stripe:SetWidth(M.ToNative(3))
    local r,g,b=style:Color("accent")
    f.line:SetVertexColor(r,g,b,.7);f.lineBox:SetShown(cfg.line)
    local br,bg,bb,ba=style:Color("bg");f.band:SetVertexColor(br,bg,bb,(ba or 1)*.7);f.stripe:SetVertexColor(r,g,b,1)
    f.bandBox:SetShown(cfg.animation=="lowerthird")
    if self.current then self:Paint(self.current) end
end
function Stage:Paint(entry)
    local f=self:Frame()
    local style=UI:GameStyle(self.ID)
    f.title:SetText(entry.title)
    if entry.color then f.title:SetTextColor(entry.color[1],entry.color[2],entry.color[3],1) else f.title:SetTextColor(style:Color("text")) end
    f.subtitle:SetText(entry.subtitle or "");f.subtitle:SetTextColor(style:Color("muted"))
end
function Stage:Cancel()
    for _,key in ipairs({"holdTimer","doneTimer"}) do if self[key] then self[key]:Cancel();self[key]=nil end end
    if self.frame then for _,tr in pairs(self.frame.tracks) do tr.group:Stop() end end
end

-- Animations (TV lower thirds and Horizon as models, Florian 2026-10-07).
-- Per part: delay, duration, start offset dx/dy and start scale sx/sy for the
-- entrance; end offset and end scale for the exit (design units; +dy is up).
-- inTime/outTime: when the last part has arrived or left.
local function every(step) return {title=step,subtitle=step,line=step,band=step} end
Stage.ANIMATIONS={
    fade={inTime=.3,outTime=.5,enter=every({duration=.3}),exit=every({duration=.5})},
    slide={inTime=.3,outTime=.5,enter=every({duration=.3,dy=-12}),exit=every({duration=.5,dy=12})},
    -- The line grows from the middle, the title rises out of it, the subtitle
    -- drops below it; leaving, the line closes back to the middle.
    reveal={inTime=.65,outTime=.45,
        enter={line={duration=.35,sx=.01},title={delay=.18,duration=.4,dy=-12},subtitle={delay=.28,duration=.35,dy=10},band={duration=.3}},
        exit={title={duration=.3,dy=8},subtitle={duration=.3,dy=-6},line={delay=.1,duration=.35,sx=.01},band={duration=.3}}},
    -- Cinema: the title settles from large, then line and subtitle.
    zoom={inTime=.9,outTime=.6,
        enter={title={duration=.7,sx=1.35,sy=1.35},line={delay=.3,duration=.45,sx=.01},subtitle={delay=.4,duration=.5},band={duration=.3}},
        exit={title={duration=.6,sx=1.08,sy=1.08},line={duration=.4},subtitle={duration=.4},band={duration=.4}}},
    -- TV lower third: the band wipes in from the left, the text follows;
    -- leaving, everything wipes out to the right.
    lowerthird={inTime=.6,outTime=.5,
        enter={band={duration=.35,sx=.01,origin="LEFT"},line={delay=.2,duration=.3,sx=.01,origin="LEFT"},
            title={delay=.15,duration=.35,dx=-30},subtitle={delay=.25,duration=.35,dx=-30}},
        exit={title={duration=.3,dx=30},subtitle={delay=.05,duration=.3,dx=30},line={duration=.3,sx=.01,origin="RIGHT"},
            band={delay=.15,duration=.35,sx=.01,origin="RIGHT"}}},
}
function Stage:Spec() return self.ANIMATIONS[self:Config().animation] or {inTime=0,outTime=0} end
local function scale(anim,fromX,fromY,toX,toY)
    if anim.SetScaleFrom then anim:SetScaleFrom(fromX,fromY);anim:SetScaleTo(toX,toY)
    elseif anim.SetFromScale then anim:SetFromScale(fromX,fromY);anim:SetToScale(toX,toY) end
end
function Stage:Track(tr,step,entering)
    tr.group:Stop()
    local dx,dy=M.ToNative(step.dx or 0),M.ToNative(step.dy or 0)
    local sx,sy=math.max(.01,step.sx or 1),math.max(.01,step.sy or 1)
    local origin=step.origin or "CENTER"
    tr.scale:SetOrigin(origin,0,0)
    if entering then
        tr.preMove:SetOffset(dx,dy);tr.move:SetOffset(-dx,-dy)
        scale(tr.scale,sx,sy,1,1)
    else
        tr.preMove:SetOffset(0,0);tr.move:SetOffset(dx,dy)
        scale(tr.scale,1,1,sx,sy)
    end
    local from,to=entering and 0 or 1,entering and 1 or 0
    tr.alpha:SetFromAlpha(from);tr.alpha:SetToAlpha(to)
    for _,anim in ipairs({tr.alpha,tr.move,tr.scale}) do
        anim:SetDuration(step.duration or .3);anim:SetStartDelay(step.delay or 0);anim:SetSmoothing(entering and "OUT" or "IN")
    end
    tr.region:SetAlpha(from);tr.group:Play()
end
-- Plays the entrance or the exit of every part; "none" just shows or hides.
function Stage:Animate(entering)
    local spec=self.ANIMATIONS[self:Config().animation]
    for name,tr in pairs(self.frame.tracks) do
        tr.group:Stop()
        local step=spec and spec[entering and "enter" or "exit"][name]
        if step then self:Track(tr,step,entering) else tr.region:SetAlpha(entering and 1 or 0) end
    end
end
function Stage:Settle()
    for _,tr in pairs(self.frame.tracks) do tr.group:Stop();tr.region:SetAlpha(1) end
end
-- Enter (or keep shown when only the text changed), hold, leave, next.
function Stage:Schedule(entry,shown)
    self:Cancel()
    local f=self:Frame()
    local spec=self:Spec()
    f:SetAlpha(1)
    if not shown then self:Animate(true) else self:Settle() end
    self.holdTimer=C_Timer.NewTimer((shown and 0 or spec.inTime)+entry.hold,function()
        Stage.holdTimer=nil
        if Stage.current~=entry then return end
        Stage:Animate(false)
        Stage.doneTimer=C_Timer.NewTimer(math.max(.01,spec.outTime),function()
            Stage.doneTimer=nil
            if Stage.current~=entry then return end
            Stage.current=nil;f:Hide();Stage:Next()
        end)
    end)
end
function Stage:Next()
    if self.preview then return end
    local entry=table.remove(self.queue,1)
    self.current=entry
    if not entry then if self.frame then self.frame:Hide() end;return end
    local f=self:Frame()
    self:Paint(entry);f:Show()
    self:Schedule(entry,false)
end
-- One sample with the chosen animation (on picking one in the settings).
function Stage:Preview()
    if self.preview or not self.order[1] then return end
    self.queue={};self:Cancel();self.current=nil
    self:Show(self.order[1],{title="Hillsbrad Foothills",subtitle="Contested territory · 4 quests"})
end
function Stage:Test()
    for _,id in ipairs(self.order) do
        local def=self.types[id]
        local sample=def.sample or {title=def.label,subtitle="Test notification"}
        self:Show(id,{title=sample.title,subtitle=sample.subtitle,color=sample.color})
    end
end

-- Layout Editor element: created with the first registered type.
local function place(rect)
    local f=Stage:Frame()
    f:ClearAllPoints();f:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
    f:SetSize(math.max(1,rect.width),math.max(1,rect.height))
    Stage:Apply()
end
function Stage:Element()
    if self.elementRegistered or not ns.Layout then return end
    self.elementRegistered=true
    ns.Layout:Register("bv:stage",{label="Notifications",
        limits={minWidth=200,maxWidth=1400,minHeight=40,maxHeight=300},
        defaults=function() return {width=M.ToNative(600),height=M.ToNative(90),screen="TOP",x=0,y=-160} end,
        apply=function(rect) place(rect) end,
        enabled=function() return Stage:HasTypes() end,
        preview=function(value)
            Stage.preview=value==true
            local f=Stage:Frame()
            if Stage.preview then
                Stage:Cancel();Stage.current=nil
                Stage:Paint({title="Notification",subtitle="Zone changes, progress and other moments"});f:SetAlpha(1);Stage:Settle();f:Show()
            else f:Hide();Stage:Next() end
        end})
end
-- Style family changes: fonts and the accent line follow.
ns.Styles:OnChanged(Stage,function() Stage:Apply() end)

-- Settings page, created with the first registered type.
local ANIMATION_CHOICES={{value="fade",label="Fade"},{value="slide",label="Fade and slide"},{value="reveal",label="Line reveal"},
    {value="zoom",label="Cinematic zoom"},{value="lowerthird",label="Lower third (TV)"},{value="none",label="None"}}
function Stage:Page()
    if self.pageRegistered or not ns.Config then return end
    self.pageRegistered=true
    local page
    local function build(parent)
        page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
        local g=UI:SettingsGrid(page);page.grid=g
        local controls={}
        local function changed() Stage:Apply();if page then page:Refresh() end end
        local function set(key) return function(value) Stage:Config()[key]=value;changed() end end
        local function row(key,title,control,help) controls[key]=g:Row(title,control,{help=help});return controls[key] end
        g:Section("stage","Notifications")
        row("styleFamily","Style family",UI:Dropdown(g,190,ns.Styles:Choices(true),function(value) Stage:Config().styleFamily=value;ns.Styles:Changed() end),
            "The suite's in-game style or an own one: fonts and the accent line. WoW uses the Morpheus title font.")
        controls.styleFamily:SetOptionsProvider(function() return ns.Styles:Choices(true) end)
        row("titleSize","Title size",UI:InlineSlider(g,190,16,60,1,"%d",set("titleSize")),"Size of the large first line.")
        row("subtitleSize","Subtitle size",UI:InlineSlider(g,190,10,30,1,"%d",set("subtitleSize")),"Size of the second line.")
        row("animation","Animation",UI:Dropdown(g,190,ANIMATION_CHOICES,function(value) Stage:Config().animation=value;changed();Stage:Preview() end),
            "How a notification appears and leaves. Line reveal: the title rises out of the accent line. Cinematic zoom: the title settles from large. Lower third: a band wipes in like a TV caption. Picking one plays a sample.")
        row("line","Accent line",UI:Switch(g,true,set("line")),"A thin line in the accent colour between title and subtitle.")
        g:Row("Position",UI:Button(g,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:stage") end),{help="The notification area is a movable element."})
        g:Row("Test",UI:Button(g,"Test notifications",170,function() Stage:Test() end),{help="One sample of every message type, one after another."})
        g:Section("types","Messages")
        page.types={}
        for _,id in ipairs(Stage.order) do
            local def=Stage.types[id]
            local enabled=g:Row(def.label,UI:Switch(g,true,function(value) Stage:TypeConfig(id).enabled=value end),{help=def.description or "Shows this message."})
            local hold=g:Row("",UI:InlineSlider(g,190,1,15,1,"%d s",function(value) Stage:TypeConfig(id).hold=value end),{help="How long this message stays."})
            page.types[id]={enabled=enabled,hold=hold}
        end
        function page:Arrange(width)
            UI:Place(g,self,0,0)
            local height=g:Arrange(width)+8
            M.Height(self,height);return height
        end
        function page:Refresh()
            local c=Stage:Config()
            for key,control in pairs(controls) do if control.SetValue then control:SetValue(c[key]) end end
            for id,rows in pairs(self.types) do local t=Stage:TypeConfig(id);rows.enabled:SetValue(t.enabled);rows.hold:SetValue(t.hold) end
        end
        page:Arrange(880);page:Refresh()
        return page
    end
    ns.Config:RegisterPage("stage",{title="Notifications",description="Cinematic notifications from your modules: level-ups and more.",
        category="core",build=function(parent) return page or build(parent) end,
        refresh=function() if page then page:Refresh() end end})
end
