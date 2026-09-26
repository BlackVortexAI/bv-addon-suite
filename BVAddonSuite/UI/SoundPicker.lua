local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
function UI:SoundPicker(owner,config,choose)
    local w=self:Dialog(nil,560,470,owner);local selected
    local options={};local page,query=1,""
    if config.source=="sharedmedia" then options=ns.Media:SoundOptions()
    else
        for name,id in pairs(SOUNDKIT or {}) do
            if type(name)=="string" and ns.GraphModel.Number(id) and id>0 then options[#options+1]={value=id,label=name:gsub("_"," ").." ["..id.."]"} end
        end
        options[#options+1]={value=config.soundKit,label="Current SoundKit ["..config.soundKit.."]"}
    end
    table.sort(options,function(a,b)return a.label:lower()<b.label:lower()end)
    UI:Place(UI:Label(w,"Choose sound",18,"text",true),w,16,14)
    local hint=UI:Place(UI:Label(w,"Preview a sound before selecting it. Playback uses the node's channel and supported volume.",12,"muted"),w,16,46);D.Size(hint,528,34)
    local rows,filtered={},{}
    local status=UI:Place(UI:Label(w,"",11,"muted"),w,16,388);D.Size(status,528,24)
    local function candidate(entry)
        local c=ns.GraphModel.Copy(config)
        if c.source=="sharedmedia" then c.sound=entry.value else c.soundKit=entry.value end
        return c
    end
    local function refresh()
        filtered={};for _,e in ipairs(options)do if e.label:lower():find(query,1,true)then filtered[#filtered+1]=e end end
        page=math.max(1,math.min(page,math.max(1,math.ceil(#filtered/7))))
        for i,row in ipairs(rows) do
            row.entry=filtered[(page-1)*7+i];row.pick:SetShown(row.entry~=nil);row.play:SetShown(row.entry~=nil)
            if row.entry then row.pick:SetLabelText(row.entry.label);row.pick:SetSelected(selected==row.entry)end
        end
        status:SetText(#filtered.." sounds / page "..page.." of "..math.max(1,math.ceil(#filtered/7)))
    end
    local search=UI:Place(UI:Input(w,528),w,16,84);search:SetAutoFocus(false)
    search:SetScript("OnTextChanged",function()query=search:GetText():lower();page=1;refresh()end)
    for i=1,7 do
        local row={};rows[i]=row
        row.pick=UI:Place(UI:Button(w,"",436,function()selected=row.entry;refresh()end,"nav"),w,16,122+(i-1)*36)
        row.play=UI:Place(UI:Button(w,"Play",80,function()
            if row.entry then local _,message=ns.Sound:Play(w,"preview",candidate(row.entry));status:SetText(message)end
        end,"ghost"),w,464,122+(i-1)*36)
        D.Height(row.pick,32);D.Height(row.play,32)
    end
    UI:Place(UI:Button(w,"Previous",88,function()page=page-1;refresh()end,"ghost"),w,16,422)
    UI:Place(UI:Button(w,"Next",72,function()page=page+1;refresh()end,"ghost"),w,108,422)
    UI:Place(UI:Button(w,"Stop",72,function()ns.Sound:Release(w)end),w,190,422)
    UI:Place(UI:Button(w,"Cancel",104,function()w:Hide()end),w,274,422)
    UI:Place(UI:Button(w,"Select",152,function()if selected then choose(selected.value);w:Hide()end end,true),w,392,422)
    w:HookScript("OnHide",function()ns.Sound:Release(w)end)
    refresh();w:Show();return w
end
