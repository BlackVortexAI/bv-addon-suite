-- Player item sources (roadmap P2a): durability, weapon enchant, item cooldown.
-- Event-driven DataSource kinds; see docs/research/2026-09-26-player-flow-sources.md.
local _,A=...
if A.blocked then return end
local G=A.G
local function port(label,kind,order) return {label=label,type=kind,order=order,optional=true,maySecret=true} end
local function add(kind,d)
    d.source=true;d.dataSource=true;d.inputs={};d.outputs=d.outputs or {};d.fields=d.fields or {}
    A.catalog[kind]=d;A.order[#A.order+1]=kind
end
add("player_durability",{label="Durability",defaults={mode="overall",slot=16},
    help="Equipment durability from the game's durability events. Overall: Lowest % (most damaged item), Total % (sum of current / sum of maximum), lowest slot and counts of damaged and broken items over all equipped items that have durability. Slot: one inventory slot (1 head … 16 main hand, 17 off hand, 18 ranged). Items without durability are skipped; with none counted the totals stay unavailable, never 100 %. Repair disabled reports the game rule where available.",
    resolve=function(c)
        if c.mode~="overall" and c.mode~="slot" then return nil,"Choose Overall or Slot" end
        if c.mode=="slot" and (not G.Number(c.slot) or c.slot<1 or c.slot>19 or c.slot~=math.floor(c.slot)) then return nil,"Slot must be 1..19" end
        local d=G.Copy(A.catalog.player_durability);d.resolve=nil
        d.fields={{key="mode",label="Mode",choices={"overall","slot"},choiceLabels={overall="Overall",slot="One slot"},primary=true}}
        if c.mode=="slot" then
            d.fields[2]={key="slot",label="Inventory slot (1..19)",type="integer"}
            d.outputs={current=port("Current","integer",1),maximum=port("Maximum","integer",2),percent=port("Percent","float",3),broken=port("Broken","boolean",4),hasDurability=port("Has durability","boolean",5)}
        else
            d.outputs={lowestPercent=port("Lowest %","float",1),totalPercent=port("Total %","float",2),lowestSlot=port("Lowest slot","integer",3),
                damagedCount=port("Damaged items","integer",4),brokenCount=port("Broken items","integer",5),countedSlots=port("Counted items","integer",6),repairDisabled=port("Repair disabled","boolean",7)}
        end
        return d
    end})
add("weapon_enchant",{label="Weapon enchant",defaults={slot="mainhand",enchantType="temporary"},
    help="Temporary weapon enchants and imbues (poisons, oils, stones, shaman imbues) from the game's weapon enchant events. Time left is sampled when the enchant changes; feed Expiration into Remaining Estimate for a countdown. Filter Temporary covers temporary enchants and imbues; Any includes permanent enchants. Present=false clears the other outputs.",
    resolve=function(c)
        if not ({mainhand=true,offhand=true,ranged=true})[c.slot] or not ({temporary=true,any=true})[c.enchantType] then return nil,"Choose a weapon slot and filter" end
        local d=G.Copy(A.catalog.weapon_enchant);d.resolve=nil
        d.fields={{key="slot",label="Weapon",choices={"mainhand","offhand","ranged"},choiceLabels={mainhand="Main hand",offhand="Off hand",ranged="Ranged"},primary=true},
            {key="enchantType",label="Enchants",choices={"temporary","any"},choiceLabels={temporary="Temporary and imbues",any="Any, including permanent"}}}
        d.outputs={present=port("Present","boolean",1),enchantID=port("Enchant ID","integer",2),enchantType=port("Enchant type","string",3),charges=port("Charges","integer",4),
            timeLeft=port("Time left (s)","float",5),expiration=port("Expiration","float",6),icon=port("Icon ID","integer",7),count=port("Matching enchants","integer",8)}
        return d
    end})
add("item_cooldown",{label="Item cooldown",defaults={target="item",itemID=5512,slot=13,ignoreGCD=false},
    help="Cooldown of an item by ID or of an equipped slot (13/14 trinkets) from the game's cooldown events. Active means a readable running cooldown; Enabled=false means the timer is paused until a condition ends (e.g. a potion used in combat). Expiration (start + duration) feeds Remaining Estimate. The global cooldown may appear as a short cooldown; enable Ignore GCD to treat cooldowns of 1.5 s or less as not active.",
    resolve=function(c)
        if c.target~="item" and c.target~="slot" then return nil,"Choose Item or Slot" end
        if c.target=="item" and (not G.Number(c.itemID) or c.itemID<1 or c.itemID~=math.floor(c.itemID)) then return nil,"Choose an item ID" end
        if c.target=="slot" and (not G.Number(c.slot) or c.slot<1 or c.slot>19 or c.slot~=math.floor(c.slot)) then return nil,"Slot must be 1..19" end
        local d=G.Copy(A.catalog.item_cooldown);d.resolve=nil
        d.fields={{key="target",label="Target",choices={"item","slot"},choiceLabels={item="Item ID",slot="Equipped slot"},primary=true}}
        d.fields[2]=c.target=="item" and {key="itemID",label="Item ID",type="integer",picker="item"} or {key="slot",label="Inventory slot (1..19)",type="integer"}
        d.fields[3]={key="ignoreGCD",label="Ignore GCD (1.5 s or less)",type="boolean"}
        d.outputs={active=port("Active","boolean",1),startTime=port("Start time (s)","float",2),duration=port("Duration (s)","float",3),enabled=port("Enabled","boolean",4),expiration=port("Expiration","float",5)}
        return d
    end})
-- P2b: "queued action". No API names the spell in the input queue; the
-- honest signal is IsCurrentSpell (casting or queued) for one chosen spell.
add("spell_queued",{label="Spell current / queued",defaults={spellID=78},
    fields={{key="spellID",label="Spell ID",type="integer",picker="aura"}},
    outputs={current=port("Casting or queued","boolean",1),autoRepeat=port("Auto-repeat active","boolean",2)},
    help="True while the chosen spell is being cast or waits in the queue, for example Heroic Strike, Cleave, Raptor Strike or Maul armed for the next swing. The game cannot tell casting and queued apart; combine with Unit Cast (not casting) if you need queued only. Auto-repeat active is true for auto-repeat spells (Auto Shot, Shoot) while they run. Updated by the game's cast and action bar state events, no polling."})
