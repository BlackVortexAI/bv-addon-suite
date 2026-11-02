-- Small, opt-in stock reminders. Data provenance and limits:
-- docs/aura-reagent-examples.md. No spellbook scanning or auto-activation.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local G=A.G

local function build(entry)
    local graph=G.New()
    local function add(kind,title,x,y)
        local id=G.Add(graph,kind,A.catalog,x,y)
        graph.nodes[id].title=title
        return id,graph.nodes[id]
    end
    local count,items=add("item_count","1. Carried reagent",0,0)
    items.config.itemID=entry.itemID
    local compare,low=add("compare","2. Minimum stock",280,0)
    low.config.operator="<";low.values.threshold=5
    local resting,state=add("unit_information","3. Rest area",0,250)
    state.config.unit="player";state.config.information="resting"
    local both,conditions=add("logic","4. Both conditions",560,100)
    conditions.config.operation="and";conditions.config.count=2
    local display,output=add("display_visual","5. Stock reminder",840,100)
    output.config.kind="text"
    -- Stable packet identity; the normal importer allocates a fresh display ID.
    local layoutID="bv_aura:"..string.format("%032x",entry.itemID)
    output.config.layoutId=layoutID
    output.values.text="Low stock: "..entry.itemName
    output.values.fontSize=18;output.values.color="E6C777FF"
    -- Beside the execution graph: text/font growth can never overlap its nodes.
    local _,note=add("markdown_note","How this example works",1140,0)
    note.config.width=520
    note.config.text="## "..entry.categoryName..": "..entry.itemName.."\n\n"
        .."Shows **Low stock** only while resting and carrying fewer than **5**.\n"
        .."- Change **Minimum stock > Threshold** to your preferred amount.\n"
        .."- Carried reagent selects item ID **"..entry.itemID.."**; bank stock is excluded.\n"
        .."- To test: rest in an inn/city, then cross the threshold or leave the rest area.\n"
        .."- Move the reminder in Layout Editor. Each reagent has a separate row.\n\n"
        .."Used by: "..entry.spells..".\n\n"
        .."This graph loads only for "..entry.categoryName..". Change this in Graph > Load conditions. "
        .."Import only reagents you actually use: learned spells, ranks and reagent-free effects are not checked. Older ranks may use other items. "
        .."It never buys, casts or consumes anything. Unknown counts stay unknown."
    graph.edges={
        {from=count,output="count",to=compare,input="value"},
        {from=compare,output="result",to=both,input="in1"},
        {from=resting,output="resting",to=both,input="in2"},
        {from=both,output="result",to=display,input="visible"},
    }
    graph.view={x=20,y=220,zoom=.7}
    return {version=1,kind="graph",graphs={{name=entry.name,graph=graph,load={class=entry.category}}},layouts={
        [layoutID]={displayAnchor=1,label=entry.name,width=370,height=28,
            x=0,y=100+(entry.row-1)*32,screen="CENTER"},
    }}
end

-- Build 70532 client tables, seven class spell families; names/IDs are data, not runtime observations.
local classes={
    {token="DRUID",name="Druid",items={
        {id=17021,name="Wild Berries",spells="Gift of the Wild"},
        {id=17026,name="Wild Thornroot",spells="Gift of the Wild"},
        {id=17034,name="Maple Seed",spells="Rebirth"},
        {id=17035,name="Stranglethorn Seed",spells="Rebirth"},
        {id=17036,name="Ashwood Seed",spells="Rebirth"},
        {id=17037,name="Hornbeam Seed",spells="Rebirth"},
        {id=17038,name="Ironwood Seed",spells="Rebirth"},
    }},
    {token="MAGE",name="Mage",items={
        {id=17020,name="Arcane Powder",spells="Arcane Brilliance"},
        {id=17031,name="Rune of Teleportation",spells="Teleport: Dalaran, Teleport: Darnassus, Teleport: Ironforge, Teleport: Orgrimmar, Teleport: Stormwind, Teleport: Thunder Bluff, Teleport: Undercity"},
        {id=17032,name="Rune of Portals",spells="Portal: Darnassus, Portal: Ironforge, Portal: Orgrimmar, Portal: Stormwind, Portal: Thunder Bluff, Portal: Undercity"},
        {id=17056,name="Light Feather",spells="Slow Fall"},
    }},
    {token="PALADIN",name="Paladin",items={
        {id=17033,name="Symbol of Divinity",spells="Divine Intervention"},
        {id=21177,name="Symbol of Kings",spells="Greater Blessing of Kings, Greater Blessing of Light, Greater Blessing of Might, Greater Blessing of Wisdom, Mass Salvation"},
    }},
    {token="PRIEST",name="Priest",items={
        {id=17028,name="Holy Candle",spells="Prayer of Fortitude"},
        {id=17029,name="Sacred Candle",spells="Prayer of Fortitude, Prayer of Shadow Protection, Prayer of Spirit"},
        {id=17056,name="Light Feather",spells="Levitate"},
    }},
    {token="ROGUE",name="Rogue",items={
        {id=5140,name="Flash Powder",spells="Vanish"},
        {id=5530,name="Blinding Powder",spells="Blind"},
    }},
    {token="SHAMAN",name="Shaman",items={
        {id=17030,name="Ankh",spells="Reincarnation"},
        {id=17057,name="Shiny Fish Scales",spells="Water Breathing"},
        {id=17058,name="Fish Oil",spells="Water Walking"},
    }},
    {token="WARLOCK",name="Warlock",items={
        {id=5565,name="Infernal Stone",spells="Inferno"},
        {id=6265,name="Soul Shard",spells="Create Firestone, Create Healthstone, Create Soulstone, Create Spellstone, Portal of Summoning, Ritual of Summoning, Shadowburn, Soul Fire, Subjugate Demon, Summon Felhunter, Summon Incubus, Summon Succubus, Summon Voidwalker"},
        {id=16583,name="Demonic Figurine",spells="Ritual of Doom"},
    }},
}
for _,class in ipairs(classes) do
    for row,item in ipairs(class.items) do
        A.Examples[#A.Examples+1]={id="reagent_"..class.token:lower().."_"..item.id,
            name=class.name..": "..item.name,category=class.token,categoryName=class.name,
            itemID=item.id,itemName=item.name,spells=item.spells,row=row,build=build,
            description="Carried stock below 5 AND resting. Choose only reagents you use; adjust Minimum stock. No spellbook/rank filter."}
    end
end
