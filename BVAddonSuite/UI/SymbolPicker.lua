-- Symbol picker (Lucide set): search field and a scrolling grid. Choosing
-- calls back with the symbol name; nothing is written here.
local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
local CELL,COLUMNS=44,8
function UI:SymbolPicker(parent,width)
    local panel=CreateFrame("Frame",nil,parent);D.Size(panel,width,470)
    panel.search=UI:Input(panel,width-20);UI:Place(panel.search,panel,0,0)
    UI:AttachTooltip(panel.search,"Find symbol","Filter by name, e.g. heart, shield, arrow.")
    panel.form=UI:Form(panel,width,420,panel);UI:Place(panel.form,panel,0,40);panel.form:SetClipsChildren(true)
    panel.buttons={}
    local function button(i)
        local b=panel.buttons[i];if b then return b end
        b=CreateFrame("Button",nil,panel.form.content);D.Size(b,CELL-4,CELL-4)
        b.bg=b:CreateTexture(nil,"BACKGROUND");b.bg:SetAllPoints(b);b.bg:SetColorTexture(1,1,1,.06)
        b.glyph=b:CreateTexture(nil,"ARTWORK");D.Point(b.glyph,"CENTER");D.Size(b.glyph,26,26)
        b:SetScript("OnClick",function(self) if panel.onChoose and self.symbol then panel.onChoose(self.symbol) end end)
        b:SetScript("OnEnter",function(self) self.bg:SetColorTexture(1,1,1,.18);UI:ShowTooltip(self,ns.Symbols:Label(self.symbol),"Click to use this symbol.") end)
        b:SetScript("OnLeave",function(self) self.bg:SetColorTexture(1,1,1,self.symbol==panel.current and .22 or .06);UI:HideTooltip() end)
        panel.buttons[i]=b;return b
    end
    function panel:Refresh()
        local query=(self.search:GetText() or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        local shown=0
        for _,name in ipairs(ns.Symbols:List()) do
            if query=="" or name:find(query,1,true) then
                shown=shown+1;local b=button(shown);b.symbol=name
                local path,l,r,t,bottom=ns.Symbols:Coords(name,26)
                b.glyph:SetTexture(path);b.glyph:SetTexCoord(l,r,t,bottom);b.glyph:SetVertexColor(1,1,1,1)
                b.bg:SetColorTexture(1,1,1,name==self.current and .22 or .06)
                b:ClearAllPoints();UI:Place(b,self.form.content,((shown-1)%COLUMNS)*CELL,math.floor((shown-1)/COLUMNS)*CELL);b:Show()
            end
        end
        for i=shown+1,#self.buttons do self.buttons[i]:Hide() end
        self.form:SetContentHeight(math.max(1,math.ceil(shown/COLUMNS)*CELL))
        self.count=shown
    end
    panel.search:SetScript("OnTextChanged",function() panel:Refresh() end)
    function panel:Open(current,onChoose)
        self.current=current;self.onChoose=onChoose;self.search:SetText("");self:Refresh();self:Show()
    end
    return panel
end
