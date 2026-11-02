local _,ns=...
-- Design units only. Existing window/controller semantics remain authoritative.
local S={}
ns.ShellMetrics=S
local defaults={titlebarHeight=44,contentLeft=0,contentTop=44,contentRight=0,contentBottom=0,
    collapsedHeight=44,collapsedMinWidth=280,collapsedMaxWidth=360}
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
function S.Window(overrides)
    assert(overrides==nil or type(overrides)=="table","Shell metrics must be a table")
    local out={}
    for key,value in pairs(defaults)do out[key]=value end
    for key,value in pairs(overrides or {})do
        assert(defaults[key]~=nil,"Unknown shell metric: "..tostring(key))
        assert(finite(value),"Shell metric must be finite: "..key)
        local inset=key:sub(1,7)=="content"
        assert(inset and value>=0 or not inset and value>0,"Invalid shell metric: "..key)
        out[key]=value
    end
    assert(out.collapsedHeight>=out.titlebarHeight,"Collapsed window must contain its titlebar")
    assert(out.collapsedMaxWidth>=out.collapsedMinWidth,"Collapsed width range is reversed")
    return out
end
function S.ContentSize(width,height,metrics)
    assert(finite(width) and finite(height),"Window dimensions must be finite")
    local w=width-metrics.contentLeft-metrics.contentRight
    local h=height-metrics.contentTop-metrics.contentBottom
    assert(w>0 and h>0,"Shell insets leave no content area")
    return w,h
end

-- BV Dark presentation is explicit and session-local; generic window defaults above do not change.
function S.BVDarkWindow(theme)
 local inset=(theme=="bv-steel" or theme=="bv-forge") and 3 or 1
 return S.Window({contentLeft=inset,contentTop=inset,contentRight=inset,contentBottom=inset})
end
function S.BVDarkLayout(width,height,tabs,theme)
 local w,h=S.ContentSize(width,height,S.BVDarkWindow(theme))
 local compact=width<860;local side=compact and 56 or 216
 local head=width<900 and 94 or 77.546875
 local tabHeight=tabs and 42 or 0
 local top=head+tabHeight+12;local footer,cue=49,24
 return {width=w,height=h,compact=compact,side=side,header=head,brand=76.625,footer=footer,cue=cue,
  inner=w-side-44,top=top,viewHeight=math.max(40,h-top-footer-cue),tabHeight=tabHeight}
end

-- R9 native-shell coordinates are outer-window design units.
function S.IsWoW(theme)return theme=='modern' or theme=='classic'end
function S.WoWWindow()return S.Window({contentLeft=0,contentTop=0,contentRight=0,contentBottom=0,titlebarHeight=54,collapsedHeight=64,collapsedMinWidth=360,collapsedMaxWidth=480})end
function S.WoWLayout(width,height,tabs)
 return {native=true,width=width,height=height,compact=false,side=206,header=50,brand=0,footer=42,cue=24,inner=math.max(1,width-300),top=132,viewHeight=math.max(40,height-249),tabHeight=tabs and 33 or 0}
end
