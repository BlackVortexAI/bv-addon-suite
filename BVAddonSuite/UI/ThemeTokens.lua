local _,ns=...
local T={};ns.ThemeTokens=T
T.order={"clean","bv-tide","bv-graphite","bv-steel","bv-forge","modern","classic"}
T.themes={
 clean={name="BV Dark",bg="171513",panel="201c18",field="100f0d",edge="393027",controlEdge="504636",bg2="11100f",text="e7dfd0",muted="ada397",accent="d9b35c"},
 -- Legacy Moonlit Tide palette on the BV Dark window and control materials.
 ["bv-tide"]={name="BV Moonlit Tide",bg="0d161b",panel="17272f",field="0b1217",edge="354b56",controlEdge="577a8c",bg2="0a1015",text="e7f1f3",muted="a5bcc4",accent="89c9d3"},
 ["bv-graphite"]={name="BV Graphite",bg="222426",panel="25282b",field="191c1f",edge="3b3e42",controlEdge="62666a",bg2="1b1d20",text="e6e5df",muted="a5aaa9",accent="d6b775"},
 ["bv-steel"]={name="BV Steel",bg="24292d",panel="20262b",field="171d22",edge="3d464d",controlEdge="767e82",bg2="181d21",text="e4e8e9",muted="a1aaae",accent="d6b775"},
 ["bv-forge"]={name="BV Forge",bg="28251f",panel="24221d",field="191814",edge="454137",controlEdge="77756c",bg2="1c1b18",text="e7e2d6",muted="aaa492",accent="d6b775"},
 modern={name="WoW Modern",bg="1e2025",panel="24262c",field="111216",edge="2d3036",controlEdge="4b4f57",bg2="17181c",text="e8e9eb",muted="9ba0a8",accent="f2c75c"},
 classic={name="WoW Classic",bg="0c0a08",panel="110e0a",field="0a0806",edge="2a2114",controlEdge="6a4b14",bg2="0f0c09",text="f0e6cf",muted="a69674",accent="a00804"},
}
function T.MaterialFamily(key)
 return key=="bv-tide" and "clean" or key
end
function T.RGB(hex)
 hex=tostring(hex or "ffffff"):gsub("#", "")
 if not hex:match("^%x%x%x%x%x%x$") then hex="ffffff" end
 return {tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,1}
end
local function luminance(c)
 local n={};for i=1,3 do n[i]=c[i]<=.04045 and c[i]/12.92 or ((c[i]+.055)/1.055)^2.4 end
 return n[1]*.2126+n[2]*.7152+n[3]*.0722
end
local function contrast(a,b) local x,y=luminance(a),luminance(b);return (math.max(x,y)+.05)/(math.min(x,y)+.05) end
function T.Resolve(key,accent)
 local self={themes=T.themes,RGB=function(_,value)return T.RGB(value)end}
 self.themeKey=self.themes[key] and key or "clean"
 local t=self.themes[self.themeKey];local c={}
 for role,v in pairs(t) do if role~="name" then c[role]=self:RGB(v) end end
 self.accentHex=accent or t.accent;c.accent=self:RGB(self.accentHex)
 c.onAccent=contrast(c.accent,{1,1,1})>contrast(c.accent,{0,0,0}) and {1,.97,.91,1} or {.07,.05,.03,1}
 c.accentText={c.accent[1],c.accent[2],c.accent[3],1}
 for _=1,40 do if contrast(c.accentText,c.panel)>=4.5 then break end;for i=1,3 do c.accentText[i]=c.accentText[i]+(1-c.accentText[i])*.07 end end
 c.ok=self:RGB("5fcf9a");c.danger=self:RGB("ef8c88");c.warn=self:RGB("e0b669")
 c.pigment={c.accent[1],c.accent[2],c.accent[3],1}
 local soften=self.themeKey=="classic" and .2 or self.themeKey=="modern" and .12 or self.themeKey=="bv-forge" and .14 or self.themeKey=="bv-steel" and .07 or 0
 local grey=c.accent[1]*.2126+c.accent[2]*.7152+c.accent[3]*.0722
 for i=1,3 do c.pigment[i]=c.accent[i]*(1-soften)+grey*soften end
 local darken=self.themeKey=="classic" and .44 or self.themeKey=="modern" and .12 or 0
 c.action={};c.selection={}
 for i=1,3 do c.action[i]=c.pigment[i]*(1-darken)+c.bg[i]*darken;c.selection[i]=c.panel[i]*.86+c.pigment[i]*.14 end
 c.action[4]=1;c.selection[4]=1
 c.selectedFace={};for i=1,3 do c.selectedFace[i]=c.field[i]*.55+c.pigment[i]*.45 end;c.selectedFace[4]=1
 c.selectedText={c.text[1],c.text[2],c.text[3],1};if contrast(c.selectedText,c.selectedFace)<4.5 then c.selectedText=contrast({1,1,1},c.selectedFace)>contrast({0,0,0},c.selectedFace) and {1,1,1,1} or {0,0,0,1} end
 c.onAccent=contrast(c.action,{1,1,1})>contrast(c.action,{0,0,0}) and {1,.97,.91,1} or {.07,.05,.03,1}
 c.bg[4]=T.MaterialFamily(self.themeKey)=="clean" and .9 or .99
 c.panel[4]=.7
 c.success=c.ok;c.warning=c.warn;c.secondary=c.accent;c.raised=c.field;c.ink=c.onAccent;c.conditional=T.RGB("78a6ef")
 return c,self.themeKey
end
