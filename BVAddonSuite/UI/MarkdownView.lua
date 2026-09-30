-- Read-only Markdown rendering for graph notes. WoW font strings cannot mix
-- fonts inline, so the supported subset maps to blocks plus colour markup:
-- # ## ### headings, paragraphs, - * + and 1. lists (nested by two spaces),
-- > quotes, ``` code blocks, --- rules; inline **bold**, *italic*, `code`,
-- ~~strike~~ and [links](url) as coloured text. | tables | render as a grid
-- (header row, then rows); images stay text.
local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
local Markdown={maxLength=4000};ns.Markdown=Markdown
local colors={bold="ffffffff",italic="ffc8c8c8",code="ffe6c27a",link="ff6fb7ff",strike="ff8a8a8a"}
local function color(key,text) return "|c"..colors[key]..text.."|r" end
-- Inline markup on already escaped text (| doubled). Code spans are replaced
-- first so their content is never formatted further.
function Markdown.Inline(text)
    text=text:gsub("|","||")
    local codes={}
    text=text:gsub("`([^`]+)`",function(c) codes[#codes+1]=c;return "\0"..#codes.."\0" end)
    text=text:gsub("%[([^%]]+)%]%(([^%)]*)%)",function(label) return color("link",label) end)
    text=text:gsub("%*%*(.-)%*%*",function(t) return color("bold",t) end)
    text=text:gsub("__(.-)__",function(t) return color("bold",t) end)
    text=text:gsub("~~(.-)~~",function(t) return color("strike",t) end)
    -- Like GitHub: no whitespace directly inside the markers ("2 * 3 * 4").
    local function italic(open,t,close)
        if t:match("^%s") or t:match("%s$") then return open..t..close end
        return color("italic",t)
    end
    text=text:gsub("%f[%w%*](%*)([^%*]+)(%*)",italic)
    text=text:gsub("%f[%w_](_)([^_]+)(_)%f[^%w_]",italic)
    text=text:gsub("%z(%d+)%z",function(i) return color("code",codes[tonumber(i)]) end)
    return text
end
-- Markdown text -> list of blocks {kind,text,level,number}.
-- limit: maximum source length (notes 4000; the wiki passes a larger one).
-- breaks (notes, in-game finding 51): text shows as typed - a single line
-- break starts a new line and every blank line is one visible empty line.
-- Without it GitHub rules apply (wiki): breaks join, blank lines only end
-- the paragraph.
local function cells(line)
    local out={};line=line:gsub("^%s*|",""):gsub("|%s*$","")
    for cell in (line.."|"):gmatch("(.-)|") do out[#out+1]=cell:match("^%s*(.-)%s*$") end
    return out
end
function Markdown.Parse(source,limit,breaks)
    local blocks,paragraph,code,tbl={},nil,nil,nil
    local function flush()
        if paragraph then blocks[#blocks+1]={kind="paragraph",text=paragraph};paragraph=nil end
        if tbl then blocks[#blocks+1]=tbl;tbl=nil end
    end
    source=(type(source)=="string" and source or ""):sub(1,limit or Markdown.maxLength):gsub("\r\n","\n")
    for line in (source.."\n"):gmatch("(.-)\n") do
        if not code and line:match("^%s*|.*|%s*$") then
            if paragraph then blocks[#blocks+1]={kind="paragraph",text=paragraph};paragraph=nil end
            local row=cells(line)
            local separator=true;for _,c in ipairs(row) do if not c:match("^:?%-+:?$") then separator=false end end
            if not tbl then tbl={kind="table",rows={}} end
            if not separator then tbl.rows[#tbl.rows+1]=row else tbl.header=true end
        elseif code then
            if line:match("^%s*```") then blocks[#blocks+1]={kind="code",text=table.concat(code,"\n")};code=nil
            else code[#code+1]=line end
        elseif line:match("^%s*```") then flush();code={}
        elseif line:match("^%s*$") then flush();if breaks then blocks[#blocks+1]={kind="blank"} end
        elseif line:match("^%s*([-*_])%s*%1%s*%1[%s%-%*_]*$") then flush();blocks[#blocks+1]={kind="rule"}
        elseif line:match("^#+%s") then
            flush();local marks,text=line:match("^(#+)%s+(.*)$")
            blocks[#blocks+1]={kind="heading",level=math.min(3,#marks),text=text}
        elseif line:match("^%s*>") then flush();blocks[#blocks+1]={kind="quote",text=line:match("^%s*>%s?(.*)$")}
        elseif line:match("^%s*[-*+]%s+") then
            flush();local indent,text=line:match("^(%s*)[-*+]%s+(.*)$")
            blocks[#blocks+1]={kind="bullet",level=math.min(3,math.floor(#indent/2)),text=text}
        elseif line:match("^%s*%d+[.)]%s+") then
            flush();local indent,number,text=line:match("^(%s*)(%d+)[.)]%s+(.*)$")
            blocks[#blocks+1]={kind="number",level=math.min(3,math.floor(#indent/2)),number=number,text=text}
        else paragraph=paragraph and (paragraph..(breaks and "\n" or " ")..line:match("^%s*(.-)%s*$")) or line:match("^%s*(.-)%s*$") end
    end
    if code then blocks[#blocks+1]={kind="code",text=table.concat(code,"\n")} end
    flush()
    return blocks
end
local sizes={17,15,13}
-- options (optional): {body=font size, spacing=extra px between wrapped lines,
-- gap=space after blocks, rowPad=table cell padding, breaks=keep line breaks
-- and blank lines as typed (notes)}. Defaults stay compact for notes on the
-- canvas; the wiki passes roomier values.
function UI:MarkdownView(parent,width,options)
    local view=CreateFrame("Frame",nil,parent);D.Size(view,width,1);view:EnableMouse(false)
    view.width=width;view.labels={};view.textures={}
    local o=options or {}
    view.body,view.spacing,view.gap,view.rowPad,view.breaks=o.body or 12,o.spacing or 0,o.gap or 4,o.rowPad or 4,o.breaks==true
    local function label(i)
        local l=view.labels[i];if not l then l=UI:Label(view,"",12,"text");l:SetJustifyH("LEFT");l:SetJustifyV("TOP");l:SetWordWrap(true);view.labels[i]=l end
        return l
    end
    local function texture(i)
        local t=view.textures[i];if not t then t=view:CreateTexture(nil,"BACKGROUND");view.textures[i]=t end
        return t
    end
    -- Renders the note and returns its height in design units.
    function view:SetMarkdown(source,limit)
        for _,l in ipairs(self.labels) do l:Hide() end
        for _,t in ipairs(self.textures) do t:Hide() end
        local y,li,ti=0,0,0
        local blocks=Markdown.Parse(source,limit,self.breaks)
        -- Blank lines at the very start or end would only add empty space.
        if self.breaks then
            while blocks[1] and blocks[1].kind=="blank" do table.remove(blocks,1) end
            while blocks[#blocks] and blocks[#blocks].kind=="blank" do table.remove(blocks) end
        end
        if #blocks==0 then blocks={{kind="paragraph",text="*Empty note*"}} end
        for _,b in ipairs(blocks) do
            if b.kind=="table" then
                -- Column widths follow the longest cell text (at least 12% each).
                local cols=0;for _,row in ipairs(b.rows) do cols=math.max(cols,#row) end
                local weights,total={},0
                for c=1,cols do
                    local longest=4;for _,row in ipairs(b.rows) do longest=math.max(longest,math.min(60,#(row[c] or ""))) end
                    weights[c]=longest;total=total+longest
                end
                local widths={};for c=1,cols do widths[c]=math.max(self.width*.12,self.width*weights[c]/total) end
                local scale=0;for c=1,cols do scale=scale+widths[c] end
                for c=1,cols do widths[c]=widths[c]*self.width/scale end
                for r,row in ipairs(b.rows) do
                    local header=b.header and r==1
                    local x,rowH=0,0;local rowLabels={}
                    for c=1,cols do
                        li=li+1;local l=label(li)
                        UI:ApplyMediaFont(l,"Fonts\\FRIZQT__.TTF",self.body-1,header and "OUTLINE" or "")
                        if l.SetSpacing then l:SetSpacing(self.spacing) end
                        l:SetTextColor(1,1,1,1);UI:Place(l,self,x+6,y+self.rowPad);D.Width(l,widths[c]-12)
                        l:SetText(Markdown.Inline(row[c] or ""));l:SetHeight(0);l:Show()
                        local h=math.max(13,D.ToDesign(l:GetStringHeight()));D.Height(l,h);rowH=math.max(rowH,h)
                        x=x+widths[c]
                    end
                    ti=ti+1;local t=texture(ti)
                    t:SetColorTexture(1,1,1,header and .12 or (r%2==0 and .04 or .015));UI:Place(t,self,0,y);D.Size(t,self.width,rowH+2*self.rowPad);t:Show()
                    y=y+rowH+2*self.rowPad
                end
                y=y+8
            elseif b.kind=="blank" then
                -- One empty text line; the gap after the previous block stays.
                y=y+self.body+2
            elseif b.kind=="rule" then
                ti=ti+1;local t=texture(ti);t:SetColorTexture(1,1,1,.25);UI:Place(t,self,0,y+6);D.Size(t,self.width,1);t:Show();y=y+14
            else
                li=li+1;local l=label(li);local x,w,size,flags,text=0,self.width,self.body,"",Markdown.Inline(b.text or "")
                if l.SetSpacing then l:SetSpacing(self.spacing) end
                local font="Fonts\\FRIZQT__.TTF"
                if b.kind=="heading" then size=sizes[b.level]+(self.body-12);flags="OUTLINE"
                elseif b.kind=="bullet" then x=10+b.level*12;text="• "..text
                elseif b.kind=="number" then x=10+b.level*12;text=b.number..". "..text
                elseif b.kind=="quote" then x=12
                elseif b.kind=="code" then x=6;size=self.body-1;font="Fonts\\ARIALN.TTF";text=color("code",(b.text:gsub("|","||"))) end
                UI:ApplyMediaFont(l,font,size,flags)
                l:SetTextColor(b.kind=="quote" and .75 or 1,b.kind=="quote" and .75 or 1,b.kind=="quote" and .75 or 1,1)
                UI:Place(l,self,x,y+(b.kind=="code" and 4 or 0));D.Width(l,w-x-(b.kind=="code" and 6 or 0))
                l:SetText(text);l:SetHeight(0);l:Show()
                local h=math.max(size+2,D.ToDesign(l:GetStringHeight()));D.Height(l,h)
                if b.kind=="quote" or b.kind=="code" then
                    ti=ti+1;local t=texture(ti)
                    if b.kind=="quote" then t:SetColorTexture(.55,.7,1,.7);UI:Place(t,self,2,y);D.Size(t,3,h)
                    else t:SetColorTexture(0,0,0,.35);UI:Place(t,self,0,y);D.Size(t,self.width,h+8);h=h+8 end
                    t:Show()
                end
                y=y+h+(b.kind=="heading" and self.gap+2 or self.gap)
            end
        end
        D.Height(self,math.max(1,y));return y
    end
    return view
end
-- Edit window for a Markdown Note node: source on the left, live preview on
-- the right. Save writes the draft through the normal node-value path.
function UI:MarkdownNoteEditor(owner,controller)
    local d=self:Dialog(nil,860,560,owner);local p=d.content
    d.title:SetText("Markdown note")
    UI:Place(self:Label(p,"Markdown: # headings, **bold**, *italic*, `code`, lists, > quotes, ``` code blocks, ---. Line breaks and empty lines show as typed; links show as text.",12,"muted"),p,20,12)
    -- Counter and buttons sit on the bottom edge; the text areas fill the rest.
    d.note=self:Label(p,"",12,"text");D.Point(d.note,"BOTTOMLEFT",p,"BOTTOMLEFT",20,26);D.Size(d.note,540,24)
    local preview=UI:Place(self:Form(p,400,400,p),p,440,44);preview:SetClipsChildren(true)
    d.preview=UI:MarkdownView(preview.content,370,{breaks=true});UI:Place(d.preview,preview.content,0,0)
    local function refresh()
        local text=d.body.input:GetText()
        preview:SetContentHeight(d.preview:SetMarkdown(text))
        d.note:SetText(#text.." / "..Markdown.maxLength.." characters")
    end
    d.body=UI:Place(self:TransferText(p,400,400,Markdown.maxLength,refresh),p,20,44)
    function d:Valid()
        local graph=controller:Graph();local node=graph and graph.draft.nodes[self.nodeID]
        return graph==self.graph and not controller.inspectApplied and node and node.type=="markdown_note"
    end
    function d:Open(nodeID)
        local graph=controller:Graph();local node=graph and graph.draft.nodes[nodeID]
        if not node or node.type~="markdown_note" then return end
        self.nodeID=nodeID;self.graph=graph
        self:FitContent(860,560)
        self.body:SetText(node.config.text or "");refresh();self:Show()
        self.body.input:SetFocus();if self.body.input.SetCursorPosition then self.body.input:SetCursorPosition(0) end
    end
    d.saveButton=self:Button(p,"Save",140,function()
        if not d:Valid() then d.note:SetText("Graph selection changed; reopen this note.");return end
        if #d.body.input:GetText()>Markdown.maxLength then d.note:SetText("Note is longer than "..Markdown.maxLength.." bytes");return end
        if controller:SetValue(d.nodeID,"text",d.body.input:GetText(),true)~=false then d:Hide() else d.note:SetText(controller.message or "Note was not saved") end
    end,true)
    d.cancelButton=self:Button(p,"Cancel",120,function() d:Hide() end,"ghost")
    D.Point(d.cancelButton,"BOTTOMRIGHT",p,"BOTTOMRIGHT",-20,20)
    D.Point(d.saveButton,"RIGHT",d.cancelButton,"LEFT",-10,0)
    d:Hide()
    return d
end
