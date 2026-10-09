local _,P=...
if not P.ready then return end
-- Unexplored areas on the world map (Florian 2026-10-08, like Leatrix
-- Maps). Blizzard's exploration pin draws the explored overlays; after each
-- of its refreshes ours adds the others (Core's overlay data) on the same
-- pin, in the same pieces and places, with our own textures (Blizzard's
-- pool stays untouched). With Leatrix Maps revealing the map, ours stays
-- out (coexistence guard, "use ours anyway").
local ns=P.ns
local R={textures={},hooked={}}
P.Reveal=R

function R:On()
    return P:Active() and P:Config().unexplored and P.Guard:Owner("reveal")==nil
end
-- Blizzard's exploration pins on the world map.
function R:Pins()
    local map=P:WorldMap()
    local out={}
    if map and map.EnumeratePinsByTemplate then
        local ok,iterator=pcall(map.EnumeratePinsByTemplate,map,"MapExplorationPinTemplate")
        if ok and iterator then for pin in iterator do out[#out+1]=pin end end
    end
    return out
end
function R:Clear(pin)
    for _,texture in ipairs(self.textures[pin] or {}) do texture:Hide() end
end
function R:Paint(pin)
    self:Clear(pin)
    if not self:On() then return end
    local map=pin.GetMap and pin:GetMap()
    local mapID=map and map.GetMapID and map:GetMapID()
    if type(mapID)~="number" or not ns.MapOverlays then return end
    local layers=P.Call("C_Map.GetMapArtLayers",mapID)
    local layer=type(layers)=="table" and (layers[pin.layerIndex or 1] or layers[1])
    if type(layer)~="table" or (layer.tileWidth or 0)<=0 then return end
    local TW,TH=layer.tileWidth,layer.tileHeight
    local pool=self.textures[pin] or {}
    self.textures[pin]=pool
    local used=0
    for _,info in ipairs(ns.MapOverlays:All(mapID)) do
        if not info.explored then
            local wide,tall=math.ceil(info.textureWidth/TW),math.ceil(info.textureHeight/TH)
            for j=1,tall do
                local ph,fh=TH,TH
                if j==tall then ph=info.textureHeight%TH;if ph==0 then ph=TH end;fh=16;while fh<ph do fh=fh*2 end end
                for k=1,wide do
                    local pw,fw=TW,TW
                    if k==wide then pw=info.textureWidth%TW;if pw==0 then pw=TW end;fw=16;while fw<pw do fw=fw*2 end end
                    local file=info.fileDataIDs[(j-1)*wide+k]
                    if file then
                        used=used+1
                        local t=pool[used]
                        if not t then t=pin:CreateTexture(nil,"ARTWORK",nil,0);pool[used]=t end
                        t:SetTexture(file);t:SetTexCoord(0,pw/fw,0,ph/fh);t:SetSize(pw,ph)
                        t:ClearAllPoints();t:SetPoint("TOPLEFT",pin,"TOPLEFT",info.offsetX+TW*(k-1),-(info.offsetY+TH*(j-1)))
                        t:Show()
                    end
                end
            end
        end
    end
end
-- Each pin once: our part follows every refresh of Blizzard's.
function R:Apply()
    for _,pin in ipairs(self:Pins()) do
        if not self.hooked[pin] and type(pin.RefreshOverlays)=="function" then
            self.hooked[pin]=true
            hooksecurefunc(pin,"RefreshOverlays",function(own) R:Paint(own) end)
        end
        self:Paint(pin)
    end
end
function R:Enable(context)
    local map=P:WorldMap()
    if map and not self.hookedMap then
        self.hookedMap=true
        map:HookScript("OnShow",function() R:Apply() end)
        if type(map.OnMapChanged)=="function" then hooksecurefunc(map,"OnMapChanged",function() R:Apply() end) end
    end
    context:Defer(function() for pin in pairs(R.textures) do R:Clear(pin) end end)
    self:Apply()
end
