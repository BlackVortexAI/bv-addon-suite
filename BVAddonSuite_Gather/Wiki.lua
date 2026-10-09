local _,G=...
if not G.ready then return end
-- Gather wiki (Florian 2026-10-09: the module grew large): what each part
-- and setting does, each with an example; shown in Core's wiki window.
local ns=G.ns
local W={limit=60000}
G.Wiki=W
W.PAGES={
{id="start",title="Welcome",text=[[
# Welcome to Gather
Gather keeps your **herbs, ore, fishing pools and treasure** on the world map and the minimap, plans **routes** through them and helps you farm with a **gather mode**, a **HUD** and a **tracker**.

**Quick start**
1. Turn the module on: `/bv gather on`.
2. Gather as usual. Every node you gather is stored where you stood and shows as a pin.
3. Open the **route editor** (`/bv gather editor`), choose your zones and herbs or ores, press **Calculate**, then **Follow route**.
4. The **gather mode** window (`/bv gather window`) switches the HUD, the route lines and the kinds of nodes.

**Example:** you farm Silverleaf and Peacebloom in Silverpine. Gather for a while, open the editor, choose Silverpine, leave only those two herbs on, Calculate, Follow route. The minimap now leads you from node to node.

Use the list on the left for every part. Settings are under `/bv gather` in the tabs General, Gather mode, Routes and Recording & sharing.
]]},
{id="nodes",title="Your nodes on the maps",text=[[
# Your nodes on the maps
**Recording:** a gathering cast stores the node at your position. Found again close by, it counts up instead of adding a pin.

| Setting | What it does | Example |
|---|---|---|
| Merge distance | The same plant closer than this counts up; the pin moves to the middle of your finds | 15 yd: a few steps aside still count as the same node |
| Spawn distance | Different plants closer than this are one spawn point (they rotate there) | 8 yd: Peacebloom and Silverleaf in the same spot share a pin |
| Merge duplicates | Cleans up nodes a database holds twice | after an import |

**Showing:** each kind has its own switch, colour and a choice **when** it shows:

| Choice | Shows |
|---|---|
| Always | always |
| With the profession | only when you know Herbalism, Mining or Fishing |
| With tracking on | only while Find Herbs, Find Minerals or Find Treasure is active |

The switch is the manual override: **off is always off**.

**Gathered: grey for** keeps a node you just gathered grey until it has likely grown back. **Example:** at 10 minutes, a Briarthorn you picked at 14:00 shows grey until 14:10; its tooltip says "Gathered 4 min ago".

**Far nodes at the edge** keeps nodes beyond the minimap's range at its rim, smaller. Nodes in caves and mines show on a brown ground.
]]},
{id="sources",title="Data sources",text=[[
# Data sources
Gather keeps every source apart and merges them only when it shows nodes. **Your own finds always come first;** the others only fill gaps.

| Source | Where it comes from |
|---|---|
| Own finds | what you gathered yourself |
| Gather Data (known spawns) | BV Addon Suite - Gather Data, the known spawn points; faint until you find them |
| GatherMate2 import | Import from GatherMate2 (Recording & sharing tab) |
| Text imports | a node export someone gave you |
| Group and guild | nodes your group or guild sent (receiving on, sending off by default) |

In **Sources** (General tab) each source has a check, its name and its number of nodes. Unchecked: kept, but not shown and not used for routes.

**Example:** you only want what you have really seen. Uncheck "Gather Data" and the imports; only your own finds remain. **Known spawns in routes** decides separately whether the route editor plans known spawns you never found.
]]},
{id="editor",title="Route editor",text=[[
# Route editor
Its own map window: `/bv gather editor`, the route editor button in the settings or the gather window.

1. **Zones:** up to four zones of one continent ("Add a zone...").
2. **Herbs and ore:** switch the names on that the route should visit; the number is how many nodes are known, the level in brackets is the skill you need. **All** / **None** switch every name.
3. **Area:** limits the route to a search area. Click Area, click the corners on the map (a banner and a frame show the mode), click the first corner or Finish. Right-click takes the last corner back.
4. **Calculate:** a bar shows how far it is. The line under it tells you the stops, the length and the time, and what was left out (no-go areas, enemy bases, not worth the way).
5. **Save** with a name, **Saved routes...** to load, **Export** / **Import** to share, **Follow route** to walk it.

**Example:** a route only through the south of Silverpine: Area, five clicks round the south, Finish, Calculate. Nodes outside are faint and stay out of the route.

Moving the map: right button or the hand tool; mouse wheel zooms. The layers button switches terrain, names, slopes and water, and your walked ways.
]]},
{id="routes",title="Route settings",text=[[
# Route settings
In the editor's side bar and in the **Routes** tab.

| Setting | What it does | Example |
|---|---|---|
| Loop | The route ends where it began | farming the same circuit again and again |
| Pass-by radius | Nodes closer together than this become one stop (default 45 yd) | 45 yd: three herbs on one hill are one stop |
| Goal | Every node, or only **within sight** of the minimap's tracking dots | Within sight: fewer stops, you walk over to what you see |
| Sight radius | How far the tracking dots reach for "within sight" | about 150 yd indoors, 230 zoomed out |
| High risk | How painted high-risk areas count | Avoid where possible |
| Way per node | Groups of stops that cost more extra way per node than this are left out; 0 keeps every node | see below |
| Enemy bases | Avoid, never through or ignore; nodes inside enemy bases stay out | Horde routes skip Southshore |
| Down cliffs | Never, short drops, or always (with Slow Fall) | Short drops: down a small ledge, never down a mountain |

**Way per node, the maths:** for a group of neighbouring stops Gather takes the way through them minus the shortcut without them, and divides it by their nodes (known spawns you never found count half). **Example:** two ores 1,000 yd off the route cost about 1,000 yd extra for 2 nodes, 500 yd each; at a limit of 300 they are left out.

**Terrain:** routes go round steep slopes and through passes, drop down cliffs but never climb them, avoid water you would have to swim (Avoid water), may prefer roads and the ways you walked, and give a node down in a **ravine** its own stop down there, so you are not led along the edge. Smooth curves rounds the ways round obstacles.

**Expert settings** (button in the Routes tab): the fixed values behind all this; see the page "Expert settings".

**Jumps:** pieces of the route that drop down a cliff are drawn **orange**, in the editor and while you follow the route: jump there on purpose, and nowhere else. The status line counts them. Walls come from the terrain's fine heights: the route never climbs one. Stops you cannot walk to and back from (a plateau, a pit; with a start point: that you cannot reach from there) are left out, and the status line says how many. A node at the foot of a rock counts when you can stand beside it. A leg drawn **red** has no way in the terrain data although both ends are reachable (rare): only its straight line is known.

**Difficult spots:** the terrain data cannot know every map. Where the route crosses steep ground, swims, touches magma, passes an enemy base or your high-risk area, takes a long way round between two close stops, has no way, or leaves stops out, a **warning sign** marks the place; its tooltip says why and what may help. You know the place: paint No-go, Preferred or a transition there and Calculate again. **Example:** a sign "Long way round" between two stops on a plateau: paint Preferred up the ramp you know, and the next route takes it.
]]},
{id="paint",title="Painting and editing",text=[[
# Painting and editing
The tools under **Paint and edit**:

| Tool | Use |
|---|---|
| Move | drag the map |
| No-go | the route never goes there |
| Preferred | cheaper ground, for roads and safe paths |
| High risk | dearer or blocked, by the High risk setting (elite camps) |
| Eraser | takes painted strokes and areas away |
| Edit route | drag points, click to add one, right-click to remove one |
| Transition | a bridge, tunnel or cave entrance: click its start, then its end (Shift on the end: one way) |

**Brush** sets the stroke size. **Shift+click** sets the corners of an area, a click without Shift closes it. Undo takes back the last stroke.

**Example:** an elite camp in the middle of your herbs. Pick High risk, Shift+click round the camp, click to close. With "Avoid where possible" the route goes round it if the way is not much longer.

Areas and transitions can be shared as text from the Import menu ("Export areas and transitions").
]]},
{id="follow",title="Following a route",text=[[
# Following a route
**Follow route** (editor or gather window) shows the route on the map and the minimap: small points, lines with arrows, the next point and the line to it in green. Your waypoints stay untouched. `/bv gather stop` ends it.

- You **join** at the leg nearest to you, not at the first point.
- Reaching a point (20 yd) moves on to the next; a loop starts over.
- **Skipping:** walk to another leg on purpose and it becomes the active one, when it is clearly closer (15 yd) than the current one for two seconds in a row.
- **Joining range** limits which legs count: only those within this distance (300 yd).

**Example:** someone farms the hill ahead. Walk past it to the leg behind; after two seconds the route continues from there.

Colours and opacity of lines and points are in the Routes tab; "Route lines" in the gather window hides the lines and keeps the points.
]]},
{id="mode",title="Gather mode and HUD",text=[[
# Gather mode and HUD
The **gather window** (`/bv gather window`): the gather mode switch, the route to follow, the kinds of nodes, route lines and the HUD. Routes and pins of a followed route show only while the gather mode is on.

**HUD:** the real minimap large and see-through in the middle of the screen, with Blizzard's tracking dots. The mouse passes through it; "Close HUD" at the top ends it.

| Setting | What it does |
|---|---|
| HUD size | its size as a share of the screen height |
| HUD map opacity | how visible the map is; route, pins and the sight circle stay at full strength |
| HUD turning | turns with you, north up, or like your minimap |
| Compass at the edge | N, E, S and W at the rim |
| Minimap shape after | square or round again when the HUD closes |

**Sight circle:** a ring of the sight radius around you on the minimap; what lies inside it, your tracking dots can show. Colour, opacity and thickness are settings.

**Example:** HUD at 80 % size and 40 % map opacity, turning with you, compass on: the dots and your route in the middle of the screen without hiding the world.
]]},
{id="tracker",title="Tracker",text=[[
# Tracker
`/bv gather tracker`: what a session brings.

- **Start**, **Pause** and **Stop**; **Sessions** lists the last ones in the chat.
- Nodes, items with their value and **gold per hour**.
- **Prices:** Auto (TradeSkillMaster, then Auctionator, then the vendor price) or one of them.
- **Count all loot:** every item you loot while it runs, not only from gathering.
- **Pause when idle:** after this many minutes without gathering the session pauses, counted up to your last node; the next node resumes it.

**Example:** you stop for ten minutes to talk in town. With "Pause when idle" at 5, the clock stops at your last herb, so gold per hour stays honest.
]]},
{id="commands",title="Commands and keys",text=[[
# Commands and keys
| Command | Does |
|---|---|
| `/bv gather` | the settings |
| `/bv gather on` / `off` | the module |
| `/bv gather mode` | gather mode on or off |
| `/bv gather window` | the gather window |
| `/bv gather hud` | the HUD |
| `/bv gather tracker` | the tracker |
| `/bv gather editor` | the route editor |
| `/bv gather route` | a quick route through your zone as waypoints |
| `/bv gather stop` | stop following |
| `/bv gather wiki` | this wiki |

**Key bindings:** in the game's key bindings under "BV Addon Suite": Gather mode, HUD, window, tracker and route editor.

The minimap button's menu has entries for the gather mode, the gather window, the route editor, the tracker and the HUD.
]]},
{id="faq",title="Questions",text=[[
# Questions
**No pins show.**
GatherMate2 is running: ours waits unless "Show anyway" is on. Or the kind is off or set to "With the profession" / "With tracking on". Or its source is unchecked in Sources.

**Pins are grey.**
You gathered them a short while ago ("Gathered: grey for").

**Pins are small and faint.**
Known spawn points from Gather Data you have not found yourself yet.

**The route leads into an enemy town.**
Set Enemy bases to "Avoid" or "Never through" and calculate again.

**The route walks far for a single node.**
Set "Way per node", for example to 250 yd.

**The route never goes down to a node in a ravine.**
Calculate again: nodes on different levels get their own stops. With "Down cliffs: Never" a steep way down is very dear.

**Calculating takes long.**
Many zones and nodes take a while; the bar shows the progress. Fewer names, a search area or "Within sight" make it faster.
]]},
}
-- The expert values as a table, from the same list as the expert window.
W.EXPERT=[[
# Expert settings
**Routes tab → Open expert settings...**: the fixed values behind route planning and following. Most players never need them; each one shows its default in its tooltip, and **Reset to defaults** brings them all back. Planning values apply to the next **Calculate**, following values at once.

%s

**Examples**
- *A route still goes in and out of a ravine:* raise **Level change** (for example to 20), so changing levels counts even more.
- *Stops on a gentle slope are split although you could walk between them:* raise **Same level** (for example to 10).
- *Too many orange jumps:* raise **Jump marked from**; *jumps you would like to see are missing:* lower it.
- *The route avoids roads too little:* lower **Road and walked way cost** (for example to 0.4).
- *A followed point counts as reached too early or too late:* change **Point reached at**.
- *Known spawns should count like your own finds for "Way per node":* set **Known spawn weight** to 1.
]]
function W.ExpertPage()
    local rows={"| Setting | Default | Range | What it does |","|---|---|---|---|"}
    local section
    for _,def in ipairs(G.Expert and G.Expert.VALUES or {}) do
        if def[11] and def[11]~=section then section=def[11];rows[#rows+1]="| **"..section.."** | | | |" end
        rows[#rows+1]=string.format("| %s | %s | %s to %s | %s |",def[9],string.format(def[8],def[4]),string.format(def[8],def[5]),string.format(def[8],def[6]),(def[10]:gsub("|","/")))
    end
    return W.EXPERT:format(table.concat(rows,string.char(10)))
end
function W.Entries()
    local out={{group=true,title="Gather"}}
    for _,p in ipairs(W.PAGES) do
        out[#out+1]={id="page:"..p.id,title=p.title}
        if p.id=="routes" then out[#out+1]={id="page:expert",title="Expert settings"} end
    end
    return out
end
function W.Page(id)
    local page=type(id)=="string" and id:match("^page:(.+)$")
    if page=="expert" then return W.ExpertPage() end
    for _,p in ipairs(W.PAGES) do if p.id==page then return p.text end end
    return W.PAGES[1].text
end
function W:Open(id)
    self.window=self.window or ns.UI:WikiWindow({entries=W.Entries,page=W.Page,limit=W.limit})
    self.window:Open(id or "page:start")
    return self.window
end
