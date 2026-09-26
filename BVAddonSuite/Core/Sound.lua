-- Local audio only. Each owner/node keeps at most one native sound handle.
local _,ns=...
local S={owners={}};ns.Sound=S
local G,V=ns.GraphModel,ns.GraphValues
S.channels={Master=true,SFX=true,Music=true,Ambience=true,Dialog=true}
function S.Valid(c)
    return V.PlainExcept(c,{}) and type(c)=="table" and S.channels[c.channel]==true
        and G.Number(c.volume) and c.volume>=0 and c.volume<=100
        and (c.source=="sharedmedia" and ns.Media:Reference("sound",c.sound)
            or c.source=="soundkit" and G.Number(c.soundKit) and c.soundKit>0 and c.soundKit<=2147483647 and c.soundKit==math.floor(c.soundKit))
end
function S:Stop(owner,id)
    local records=self.owners[owner];local handle=records and records[id]
    if handle then
        local stop=C_Sound and C_Sound.StopSound or StopSound
        if type(stop)=="function" then pcall(stop,handle,0) end
        records[id]=nil;if not next(records) then self.owners[owner]=nil end
    end
    return handle~=nil
end
function S:Release(owner)
    local records=self.owners[owner];if not records then return end
    local ids={};for id in pairs(records) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do self:Stop(owner,id) end
end
function S:Play(owner,id,c)
    if not owner or not id or not self.Valid(c) then return false,"invalid sound settings" end
    self:Stop(owner,id)
    local ok,success,handle
    if c.source=="soundkit" then
        if not C_Sound or type(C_Sound.PlaySound)~="function" then return false,"SoundKit volume API unavailable" end
        ok,success,handle=pcall(C_Sound.PlaySound,c.soundKit,c.channel,false,false,nil,c.volume/100)
    else
        local file,status=ns.Media:Sound(c.sound)
        if not file then return false,status end
        if type(PlaySoundFile)~="function" then return false,"Sound file API unavailable" end
        ok,success,handle=pcall(PlaySoundFile,file,c.channel)
    end
    if not ok or V.IsSecret(success) or success~=true then return false,"sound unavailable or disabled" end
    if not G.Number(handle) or handle<=0 then return true,"played; stop handle unavailable" end
    self.owners[owner]=self.owners[owner] or {};self.owners[owner][id]=handle
    return true,c.source=="sharedmedia" and "played; channel volume" or "played"
end
