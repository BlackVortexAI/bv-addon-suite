local _,ns=...
local K={styles={"none","obsidian","precision","aether","gilded","runebound","fel","signature","minimal","echo","masque"},labels={none="None",obsidian="Obsidian",precision="Precision",aether="Aether",gilded="Gilded",runebound="Runebound",fel="Fel",signature="BV Signature",minimal="Minimal",echo="Icon Echo",masque="Masque"},shapes={"square","circle","hexagon","octagon"},shapeLabels={square="Square",circle="Round",hexagon="Hexagon",octagon="Octagon"}}
ns.IconSkins=K
function K.Valid(id) return type(id)=="string" and K.labels[id]~=nil end
local root="Interface\\AddOns\\BVAddonSuite\\Media\\IconSkins\\"
function K.Supports(id,shape)
    if not K.Valid(id) then return false end
    if shape=="square" then return true end
    if id=="none" or id=="masque" then return false end
    if shape=="circle" then return id~="precision" and id~="aether" and id~="fel" end
    if shape=="hexagon" then return id~="gilded" end
    return shape=="octagon"
end
function K.Shapes(id)
    local out={};for _,shape in ipairs(K.shapes) do if K.Supports(id,shape) then out[#out+1]=shape end end;return out
end
function K.Path(id,shape) return root..id..(shape and shape~="square" and "-"..shape or "")..".tga" end
function K.Mask(id,shape,swipe)
    shape=shape or "square"
    if id=="echo" then return root.."mask-echo-"..shape..".tga" end
    if shape~="square" then return root.."mask-"..(swipe and "swipe" or "icon").."-"..shape..".tga" end
end
function K:Masque()
    local api=LibStub and LibStub("Masque",true)
    if not api or type(api.AddSkin)~="function" or type(api.Group)~="function" then return end
    if self.registered~=api then
        for _,id in ipairs(self.styles) do if id~="none" and id~="masque" then
          for _,shape in ipairs(self.Shapes(id)) do
            local path=self.Path(id,shape);local size=id=="echo" and 32 or 24
            local name=id=="signature" and "BV Signature" or "BV "..self.labels[id]
            if shape~="square" then name=name.." - "..self.shapeLabels[shape] end
            local ok=pcall(api.AddSkin,api,name,{Author="BV",Version="2",Shape=shape=="circle" and "Circle" or "Square",
                Icon={Width=size,Height=size,TexCoords={.08,.92,.08,.92},Mask=self.Mask(id,shape)},
                Normal={Width=32,Height=32,Texture=path,TexCoords={0,.5,0,.5},Color={1,1,1,1}},
                Pushed={Width=32,Height=32,Texture=path,TexCoords={.5,1,0,.5}},
                Highlight={Width=32,Height=32,Texture=path,TexCoords={0,.5,.5,1},BlendMode="ADD"},
                Disabled={Width=32,Height=32,Texture=path,TexCoords={.5,1,.5,1}},
                Backdrop={Hide=true},Shadow={Hide=true},Gloss={Hide=true}})
            if not ok then return end
          end
        end end
        self.registered=api
    end
    return api
end
