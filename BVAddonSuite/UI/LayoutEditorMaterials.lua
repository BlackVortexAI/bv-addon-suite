local _,ns=...
-- Approved C2 chrome. These cached regions only decorate the editor; they do
-- not change mover hit rectangles, layout coordinates or saved element data.
local A={}
ns.LayoutEditorMaterials=A
local WHITE="Interface\\Buttons\\WHITE8X8"
local function flat(t)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)end
    return t
end
function A.Rect(parent,key,x,y,w,h,color,layer)
    parent.layoutParts=parent.layoutParts or {}
    local t=parent.layoutParts[key]
    if not t then t=flat(parent:CreateTexture(nil,layer or "ARTWORK"));parent.layoutParts[key]=t end
    t:ClearAllPoints();t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    t:SetSize(math.max(.1,w),math.max(.1,h));t:SetTexture(WHITE);t:SetVertexColor(unpack(color));t:Show()
    return t
end
local function slice(parent,key,path,w,h,cap,sourceCap,pad,color,layer)
    local xs={-pad,cap-pad,w-cap+pad,w+pad};local ys={-pad,cap-pad,h-cap+pad,h+pad}
    local uv={0,sourceCap/128,1-sourceCap/128,1}
    for y=1,3 do for x=1,3 do
        local t=A.Rect(parent,key..y..x,xs[x],ys[y],xs[x+1]-xs[x],ys[y+1]-ys[y],color,layer)
        t:SetTexture(path);t:SetTexCoord(uv[x],uv[x+1],uv[y],uv[y+1])
    end end
end
-- C2 luminance is calibrated to the approved BV Dark/gold reference. Hue and
-- family neutrals come from existing roles, so other families/custom accents
-- do not inherit a fixed brown/gold plate. No new palette or saved setting.
function A.Tint(style,role,reference,alpha)
    local color={style:Color(role)}
    local base=ns.ThemeTokens.RGB(ns.ThemeTokens.themes.clean[role])
    for i=1,3 do color[i]=math.max(0,math.min(1,color[i]*reference[i]/base[i]))end
    color[4]=alpha;return color
end
function A.Accent(style,reference,alpha)
    local color={style:Color("accentText")};local base=ns.ThemeTokens.RGB(ns.ThemeTokens.themes.clean.accent)
    for i=1,3 do color[i]=math.max(0,math.min(1,color[i]*reference[i]/base[i]))end
    color[4]=alpha;return color
end
function A.Surface(parent,style)
    local w,h=parent:GetWidth(),parent:GetHeight()
    local media=style.materialMediaRoot.."LayoutEditor\\"
    slice(parent,"shadow",media.."panel-shadow.tga",w,h,24,48,12,{1,1,1,.72},"BACKGROUND")
    slice(parent,"fill",media.."panel-fill.tga",w,h,12,24,0,A.Tint(style,"bg",{.068,.063,.052},.99),"BACKGROUND")
    local art=A.Rect(parent,"motif",5,5,w-10,h-10,A.Accent(style,{.86,.77,.56},h<=60 and .27 or .18),"BORDER")
    art:SetTexture(style.materialMediaRoot.."Backgrounds\\Relief")
    local _,_,u1,u2,v1,v2=ns.InterfaceSurfaces.MenuCrop(w-10,h-10)
    art:SetTexCoord(u1,u2,v1,v2)
    slice(parent,"rim",media.."panel-rim.tga",w,h,12,24,0,A.Accent(style,{.72,.61,.39},.95),"OVERLAY")
    A.Rect(parent,"innerTop",12,3,w-24,1,A.Accent(style,{.91,.79,.49},.20))
    A.Rect(parent,"innerBottom",12,h-4,w-24,1,{0,0,0,.48})
end
function A.Mover(editor,mover,id)
    local selected=id==editor.selected
    local gold={editor.style:Color("accentText")}
    local color=selected and gold or A.Tint(editor.style,"muted",{.62,.58,.47},.72)
    local w,h=mover:GetWidth(),mover:GetHeight()
    mover:PaintSurface(A.Tint(editor.style,"bg",{.035,.032,.026},selected and .72 or .44),color,1)
    for i,v in ipairs({{0,0,1,1},{w,0,-1,1},{0,h,1,-1},{w,h,-1,-1}})do
        local x,y,sx,sy=unpack(v);local length=selected and 11 or 7
        A.Rect(mover,"cornerH"..i,x+(sx<0 and -length or 0),y+(sy<0 and -2 or 0),length,2,color,"OVERLAY"):SetShown(editor.overlays)
        A.Rect(mover,"cornerV"..i,x+(sx<0 and -2 or 0),y+(sy<0 and -length or 0),2,length,color,"OVERLAY"):SetShown(editor.overlays)
    end
    for i,v in ipairs({{w/2,0},{w/2,h},{0,h/2},{w,h/2}})do
        A.Rect(mover,"handle"..i,v[1]-2,v[2]-2,4,4,gold,"OVERLAY"):SetShown(editor.overlays and selected)
    end
    mover.fill:SetShown(editor.overlays)
    mover:SetAlpha(editor.focus and not selected and .35 or 1)
end
function A.Grid(editor)
    for _,line in ipairs(editor.grid)do
        local _,_,_,x,y=line:GetPoint(1);local value=math.abs(x~=0 and x or y or 0)
        local major=math.abs(value/64-math.floor(value/64+.5))<.001
        line:SetColorTexture(unpack(A.Tint(editor.style,"muted",{.73,.68,.54},value==0 and .15 or major and .055 or .018)))
    end
end
