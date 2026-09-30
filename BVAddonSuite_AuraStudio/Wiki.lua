-- Wiki content for the BV wiki window (in-game round 4): general pages written
-- for players plus one page per node type. Node pages combine the plain
-- texts (WikiText.lua), the node's ports and settings from the catalog and
-- the "what works where" table of the node reference (NodeWiki.lua).
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local S,G=ns.AuraStudio,A.G
local Wiki={limit=60000};A.Wiki=Wiki
local general={
{id="start",title="Welcome",text=[[
# Welcome to the Aura Studio wiki
Aura Studio builds displays, sounds and actions from **nodes** that you connect in a **graph**.

- **Sources** read something from the game, for example your health, a buff or your target.
- **Logic, math and time** nodes decide, calculate and wait.
- **Media** nodes turn values into something visible: an icon, text, a bar or a symbol.
- **Outputs** show it on screen, play a sound or run an action.

Connect an output (right side of a node) to an input (left side) of the same type. Changes stay in a **draft** until you press **Save**.

Use the list on the left to read about data types, secret values and every node. The **i** button on a node opens its page directly.
]]},
{id="types",title="Data types",text=[[
# Data types
Every port has a type. You can only connect ports of the same type (a whole number also fits a decimal number port).

| Type | What it holds | Example |
|---|---|---|
| On/off (boolean) | true or false | "Target exists", "In combat" |
| Whole number (integer) | numbers without decimals | stack count, spell ID |
| Number (float) | numbers with decimals | health percent, seconds left |
| Text (string) | words and numbers as text | unit name, formatted message |
| Event | a short signal that something happened | "Aura gained", "Clicked" |
| Media | something that can be shown | icon, text, bar, symbol |
| Font / Style | reusable text and colour settings | outline font, theme colours |
| Symbol | a line symbol plus colour | heart, shield, arrow |
| Dictionary | a list of key/value entries in a fixed order | cooldowns by name |
| Timestamp | a moment in time | when a buff was applied |
| Duration | a native timer for bars and cooldown swipes | aura duration |
| Unit | a unit binding such as a nameplate | for stacks per unit |
| Action | something a button can do | cast a spell, run a macro |

A **Dictionary** keeps entries in the order you added them; you can read an entry by its key or by its position (1, 2, 3 ...). It exists only while the graph runs and is not saved.
]]},
{id="secret",title="Secret values",text=[[
# Secret values
The game hides some information from addons, for example certain health values or unit names in restricted situations. Aura Studio receives such a value as **secret** (also shown as **protected**).

**What still works**
- Showing it: a display, text or bar can show a secret value exactly like a normal one.
- Passing it on through nodes that only transport values.

**What does not work**
- Comparing it, calculating with it or turning it into text you can edit.
- Using it as a condition. A secret value is **never** treated as false, zero or "no target".

When a node needs a readable value but gets a secret one, its output stays empty and its status says **protected**. Nothing breaks; the graph simply waits for readable data again.
]]},
{id="nil",title="Empty, nil and status",text=[[
# Empty values (nil) and status
**Nil** means "no value right now". It is not the same as 0, false or empty text.

| Status | Meaning |
|---|---|
| readable | a normal value that can be used freely |
| protected | the game hides the value (see Secret values) |
| unavailable | the value cannot be read at the moment |
| absent | the thing does not exist, for example no target |
| muted | the node or its section is muted |
| faulted | the node hit an error; it is shown in red |
| inactive | the node is switched off by its Active input |

Nodes treat "unknown" carefully: an unavailable condition is not "false", and a missing number is not "0".
]]},
{id="save",title="Draft, Save and Test",text=[[
# Draft, Save and Test
- **Draft**: every change in the editor. It is not active in the game yet.
- **Save**: checks the whole graph and makes the draft active. If a node has a problem, Save stops, the node turns **red** and the editor jumps to it.
- **Test Mode / Freeze** on source nodes: try values without playing, for example "what does the display do at 20% health".

"Draft / no matching live trace" on a node means your draft differs from what runs in the game. Press **Save** to apply it.
]]},
{id="errors",title="Errors and outdated nodes",text=[[
# Errors and outdated nodes
A node with a problem is shown with a **red top bar, red tint and a warning sign**. The editor status line (bottom) names the node and the problem.

- **Needs update**: the node was saved by an older version and one of its settings no longer fits. Other nodes keep working; fix or replace this node.
- **Made with a newer version**: update the addon.
- New settings that newer versions add are filled in automatically with their defaults.
]]},
{id="share",title="Export and sharing",text=[[
# Export and sharing
- **Export**: copy a graph, a group or a building block as text and paste it anywhere.
- **Share with player**: send a graph or block to your target or a group member. The other player must allow receiving, accept the offer and confirm the import preview. Imported graphs start disabled.
- Communication and macro permissions are always reset on import.
]]},
}
Wiki.general=general
local function cell(v) return (tostring(v or ""):gsub("|","/"):gsub("\n"," ")) end
local function mdTable(columns,rows)
    local out={}
    local head={};for _,c in ipairs(columns) do head[#head+1]=cell(c.label) end
    out[#out+1]="| "..table.concat(head," | ").." |"
    local sep={};for _ in ipairs(columns) do sep[#sep+1]="---" end
    out[#out+1]="|"..table.concat(sep,"|").."|"
    for _,row in ipairs(rows) do
        local r={};for _,c in ipairs(columns) do r[#r+1]=cell(row[c.key]) end
        out[#out+1]="| "..table.concat(r," | ").." |"
    end
    return table.concat(out,"\n")
end
Wiki.Table=mdTable
-- Navigation: general pages, then node pages grouped by palette category.
function Wiki.Entries()
    local out={{group=true,title="General"}}
    for _,p in ipairs(general) do out[#out+1]={id="page:"..p.id,title=p.title} end
    local groups={}
    for kind,def in pairs(A.catalog) do
        local cat=ns.DesignSystem.NodeCategory(kind,def)
        groups[cat]=groups[cat] or {};groups[cat][#groups[cat]+1]={id="node:"..kind,title=def.label or kind}
    end
    for _,cat in ipairs(ns.DesignSystem.categoryOrder) do
        local list=groups[cat]
        if list then
            table.sort(list,function(a,b) return a.title:lower()<b.title:lower() end)
            out[#out+1]={group=true,title=ns.DesignSystem.categories[cat].label}
            for _,e in ipairs(list) do out[#out+1]=e end
        end
    end
    return out
end
local function portRows(ports,output)
    local rows={}
    for _,key in ipairs(G.Ordered(ports)) do
        local p=ports[key];local notes={}
        if not output then notes[#notes+1]=p.required==false and "optional" or (p.wire and "connect a node" or "value or connection") end
        if p.maySecret then notes[#notes+1]="can be secret" end
        rows[#rows+1]={name=p.label or key,type=G.TypeLabel(p.type),notes=table.concat(notes,", ")}
    end
    return rows
end
-- Markdown for one node type; node (optional) is a graph node for its current settings.
function Wiki.NodePage(kind,node)
    local base=A.catalog[kind];if not base then return "# Unknown node\nThis node type is not available in this version." end
    local n=node or {type=kind,config=G.Copy(base.defaults or {}),values={},exposed={}}
    local def=G.Definition(base,n) or base
    local text=A.WikiText and A.WikiText.nodes[kind] or {}
    local out={"# "..(base.label or kind)}
    out[#out+1]="*"..ns.DesignSystem.categories[ns.DesignSystem.NodeCategory(kind,base)].label.."*"
    out[#out+1]=text.summary or (base.help and base.help:match("^(.-%.)%s") or base.help) or ""
    if text.use then out[#out+1]="**When to use it:** "..text.use end
    local cols={{key="name",label="Name"},{key="type",label="Type"},{key="notes",label="Notes"}}
    local inputs=portRows(G.Ports(def),false)
    if #inputs>0 then out[#out+1]="## Inputs";out[#out+1]=mdTable(cols,inputs) end
    local outputs=portRows(base.selectableOutputs or def.outputs or {},true)
    if #outputs>0 then out[#out+1]="## Outputs";out[#out+1]=mdTable(cols,outputs) end
    local fields={}
    for _,f in ipairs(def.fields or base.fields or {}) do
        local choices=""
        if f.choices then local list={};for _,c in ipairs(f.choices) do list[#list+1]=f.choiceLabels and f.choiceLabels[c] or c end;choices=table.concat(list,", ") end
        fields[#fields+1]={name=f.label or f.key,type=f.choices and "choice" or (f.type or "text"),notes=choices}
    end
    if #fields>0 then out[#out+1]="## Settings";out[#out+1]=mdTable({{key="name",label="Setting"},{key="type",label="Kind"},{key="notes",label="Options"}},fields) end
    if A.NodeWiki then
        local ok,page=pcall(A.NodeWiki.Page,n,"overview")
        if ok and page and page.tables and page.tables[1] and #page.tables[1].rows>0 then
            out[#out+1]="## What works where"
            out[#out+1]=mdTable(page.tables[1].columns,page.tables[1].rows)
            if page.notice then out[#out+1]="*"..page.notice.."*" end
        end
    end
    if text.advanced or base.help then
        out[#out+1]="## For experienced users"
        if text.advanced then out[#out+1]=text.advanced end
        if base.help then out[#out+1]="> "..base.help:gsub("\n"," ") end
    end
    return table.concat(out,"\n\n")
end
function Wiki.Page(id,node)
    if type(id)~="string" then id="page:start" end
    local kind=id:match("^node:(.+)$")
    if kind then return Wiki.NodePage(kind,node) end
    local page=id:match("^page:(.+)$")
    for _,p in ipairs(general) do if p.id==page then return p.text end end
    return general[1].text
end
-- Studio entry points: open the wiki window at a page (and node settings).
-- Detailed field reference (per-output availability) for a node page.
function Wiki.Reference(owner,id,node)
    local kind=type(id)=="string" and id:match("^node:(.+)$");local base=kind and A.catalog[kind];if not base then return end
    local n=node or {type=kind,config=G.Copy(base.defaults or {}),values={},exposed={}}
    return ns.UI:NodeWiki(owner,function(topic) return A.NodeWiki.Page(n,topic) end)
end
function S:OpenWiki(id,node)
    self.wikiWindow=self.wikiWindow or ns.UI:WikiWindow({entries=Wiki.Entries,page=Wiki.Page,limit=Wiki.limit,reference=Wiki.Reference})
    self.wikiWindow:Open(id or "page:start",node)
    return self.wikiWindow
end
