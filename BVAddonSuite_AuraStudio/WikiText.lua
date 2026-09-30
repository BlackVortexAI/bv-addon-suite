-- Plain-language wiki texts per node (English). Written for players; "advanced" is for experienced users.
local _,A=...
if A.blocked then return end
A.WikiText={nodes={
    ["action_display"]={
        summary="Shows a clickable button on screen that performs a prepared action (spell, item, macro, targeting and more) when you click it.",
        use="Connect an Action node and some media (icon, text, button or bar). Example: a big button that casts your defensive cooldown when you left-click it.",
        advanced="You choose which click and modifier combinations are active; you can also assign keyboard shortcuts. Actions, position and visibility are locked in combat; changes apply after combat. Suggest only changes the look. Test never performs the action.",
    },
    ["action_slot"]={
        summary="An action that uses one of your action bar slots (1 to 180), exactly as if you pressed that button.",
        use="Connect it to an Action Display to put a copy of an existing action bar button somewhere else on screen. Example: a large button mirroring slot 1.",
        advanced="Uses the absolute slot number without bar paging. What happens depends on what the game has in that slot. Configure outside combat.",
    },
    ["animation"]={
        summary="Makes media move or change over time: shake, pulse, float, fade, spin or bounce. You pick the animation style in the node.",
        use="Put it between your media and the display to draw attention. Example: make an icon shake while an important buff is missing.",
        advanced="Purely visual; your saved layout is not changed. Spin uses Strength as part of a full turn per cycle, Bounce as height in pixels. Bars and text overlays cannot be rotated.",
    },
    ["animation_bounce"]={
        summary="Makes media bounce up and down.",
        use="Use it on an icon to show that something is ready. Example: a bouncing icon when your proc is up.",
        advanced="Strength is the bounce height in pixels. Visual only; the saved layout does not change. Active off, Mute or Bypass stop the animation.",
    },
    ["animation_fade"]={
        summary="Makes media fade in and out repeatedly.",
        use="Use it for a soft blinking effect. Example: a slowly blinking reminder to eat food before a raid.",
        advanced="Strength is a percentage, speed 0.05 to 2.5 cycles per second. Duration 0 repeats forever; with Repeat off it plays one cycle. Restart is an event that starts it fresh.",
    },
    ["animation_float"]={
        summary="Makes media gently float up and down.",
        use="Use it for a calm, eye-catching motion. Example: a floating icon while a buff is active.",
        advanced="Strength is 0 to 100 pixels, speed 0.05 to 2.5 cycles per second. Duration 0 repeats forever. When the animation ends, the media returns to its normal look.",
    },
    ["animation_pulse"]={
        summary="Makes media grow and shrink in a pulsing rhythm.",
        use="Use it to highlight something urgent. Example: pulse your interrupt icon when the enemy starts casting.",
        advanced="Strength is a percentage, speed 0.05 to 2.5 cycles per second. Duration 0 repeats forever; a positive duration limits playback. Visual only.",
    },
    ["animation_shake"]={
        summary="Makes media shake left and right, up and down, or both.",
        use="Use it for alarm-style warnings. Example: shake a text when your health gets very low.",
        advanced="Strength is 0 to 100 pixels; you can limit the shake to one axis. Visual only; no offsets are saved. Active off, Mute or Bypass stop it.",
    },
    ["animation_spin"]={
        summary="Makes media rotate around its pivot point.",
        use="Use it on a symbol or graphic for a spinning effect. Example: a spinning ring while a cooldown is running.",
        advanced="Strength is the share of a full turn per cycle. Bars and text overlays cannot be rotated and report an error instead.",
    },
    ["array"]={
        summary="A Dictionary: a list of entries where each entry has a name (key) and a value. It keeps the order you added things and lets you look entries up by key or by position.",
        use="Collect several related values and work with them in one place. Example: store names with their cooldown times, then sort them and show the first one.",
        advanced="Operations: create, read, set, add, remove, clear, count, contains and sort (by insertion order, key, value or timestamp). Up to 64 entries, positions start at 1. Each change produces a new Dictionary. A Dictionary cannot be put into Memory.",
    },
    ["aura"]={
        summary="Watches one buff or debuff on yourself and tells you whether it is there, how many stacks it has and how long it lasts.",
        use="Example: show a warning icon when your armor buff is missing, or display the time left on your shield.",
        advanced="Some aura data can be secret in combat. The Estimate outputs keep a best guess from earlier readable data; they are estimates, not recovered secret values. Icon media always shows the spell's artwork, even when the aura is missing.",
    },
    ["bar_duration"]={
        summary="Lets a bar run on the game's own timer, so it fills or empties smoothly by itself.",
        use="Connect a Real Time output (for example from Unit Aura) to make a bar that counts down a buff. Example: a debuff timer bar on your target.",
        advanced="The timer is passed straight to the game's bar; no timing is calculated by the addon. If the game rejects it, the bar is hidden. A missing timer is not treated as zero.",
    },
    ["boolean"]={
        summary="A fixed on/off switch that always outputs true or false.",
        use="Use it to turn parts of your graph on or off by hand, or to feed a fixed true/false into another node. Example: a switch to enable a test display.",
    },
    ["bossmod_event"]={
        summary="Fires when Deadly Boss Mods or BigWigs reports something, such as a timer bar starting, a pull timer, a boss engage, a win or a wipe.",
        use="Example: play a sound when the pull timer starts, or show a message when the boss is engaged.",
        advanced="Needs one of these boss mods installed; otherwise nothing happens. You can filter by boss mod, event type, spell ID and text. Read-only. On WoW Forever few boss modules exist, so mostly pull, break, custom timers and engage/win/wipe arrive.",
    },
    ["bossmod_timer"]={
        summary="Gives you information about a running Deadly Boss Mods or BigWigs timer that matches a spell ID or text, such as a pull or break timer.",
        use="Example: show the remaining pull timer in big letters in the middle of your screen.",
        advanced="Updates only when timers change, so Remaining is not a live countdown. For a smooth countdown feed Expiration into Remaining estimate. Active is off when nothing matches or no boss mod is installed.",
    },
    ["cancel_aura_action"]={
        summary="An action that removes one of your own buffs when you click it.",
        use="Connect it to an Action Display. Example: a button that cancels a speed buff or a shapeshift-like buff with one click.",
        advanced="Only works for buffs you are allowed to cancel; harmful auras cannot be removed. The spell is resolved by name outside combat, so set it up before combat.",
    },
    ["capture_target"]={
        summary="Takes a snapshot of a target (yours, your focus's, a party or raid member's, or mouseover) at the moment something arrives at its Capture input.",
        use="Example: capture your target before and after pressing a targeting macro, then check whether it changed.",
        advanced="Nothing is read between captures. Changed compares with this node's previous capture (by GUID when readable, otherwise by name) and stays empty when either side is unknown or protected.",
    },
    ["chat"]={
        summary="Writes a message into your own chat window. Only you can see it.",
        use="Connect a trigger to it. Example: print \"Interrupt ready!\" when your interrupt comes off cooldown.",
        advanced="Never sends anything to other players. The BV prefix can be turned off. Test messages keep a Test marker.",
    },
    ["chat_direct"]={
        summary="Sends a real chat message (say, party, raid, guild, whisper and so on) directly when triggered, without asking first.",
        use="Example: announce in party chat that you used a cooldown. You must allow sending on the node first.",
        advanced="No retries or fallback channels. Submitted only means the game accepted the request, not that it was delivered. The game may block sends that need a key press. Test never sends. Imports turn the permission off again.",
    },
    ["chat_receive"]={
        summary="Fires when a chat message arrives in the channel you choose, optionally filtered by text and sender.",
        use="Example: react when someone whispers you \"inv\", or when a raid warning contains a certain word.",
        advanced="Filters: exact, contains or glob (* any characters, ? one character). Case-sensitive, not regex. Your own messages are ignored by default. Secret or very long text never matches. Nothing is logged.",
    },
    ["chat_send"]={
        summary="Prepares a chat message and asks you to confirm it with a Send button before anything is posted.",
        use="Example: when the boss dies, offer to post a thank-you in raid chat; you decide with one click whether to send it.",
        advanced="Each request waits 15 seconds for your confirmation; up to eight can be pending. Channel rules (raid warning, officer, whisper target) are checked again when you confirm. Test never creates a request.",
    },
    ["circle"]={
        summary="Turns a radius and an angle into an X/Y position on a circle.",
        use="Use it to place things in a ring. Example: arrange several icons around your character, or move an icon around in a circle by changing the angle.",
        advanced="The angle is in degrees, counter-clockwise.",
    },
    ["click_action"]={
        summary="An action that, when clicked on an Action Display, sends a click event inside your graph instead of casting anything.",
        use="Use it to build your own buttons that change things in the graph. Example: a button that resets a counter or opens a dialog.",
        advanced="Matching Media event nodes (same interaction key) receive the click plus the values you add as payload fields. It never casts spells or runs macros; Test never clicks.",
    },
    ["color_overlay"]={
        summary="Lays a colour over an icon or graphic. You can overlay, darken, brighten, tint or first turn it grey and then tint it.",
        use="Example: tint an icon red when the ability is not usable, or make it grey when it is on cooldown.",
        advanced="Strength 0 to 1 blends from no effect to full. The game only supports these blend modes; modes like Overlay or Screen do not exist in WoW.",
    },
    ["compare"]={
        summary="Compares a number with a threshold (less than, greater than, equal and so on) and outputs true or false.",
        use="Example: become true when your health is below 35 percent.",
        advanced="Secret values cannot be compared; an unknown value gives an unknown result, never false.",
    },
    ["confirm_dialog"]={
        summary="Shows a small dialog with a title, a message and OK / Cancel buttons, and continues your graph once you answer.",
        use="Example: ask \"Write the new macro?\" before something is changed.",
        advanced="Completed fires once; Confirmed is false when you cancel. A payload value is passed through until you answer. Shown in screen center or where you placed it with the Layout Editor. Not shown in combat unless allowed; no combat queue.",
    },
    ["constant_nil"]={
        summary="Outputs \"no value\" on purpose.",
        use="Use it when you want an input to receive nothing instead of its default. Example: one choice of an If / Else that should show nothing.",
        advanced="A connected Nil never falls back to the input's local default. It does not fire events.",
    },
    ["context"]={
        summary="Tells you whether you are in combat right now (true or false).",
        use="Example: only show a display while you are in combat, or only outside combat.",
    },
    ["currency"]={
        summary="Shows information about one currency: its name, how much you have, the maximum and its icon.",
        use="Example: display how many badges or tokens you currently own.",
        advanced="Each value is read separately; missing or secret values stay unavailable and are never shown as zero.",
    },
    ["debounce"]={
        summary="Lets the first event through and then ignores further events until things have been quiet for a set time.",
        use="Stops spam when something fires many times in a row. Example: play a sound only once even if a warning triggers five times quickly.",
        advanced="Events that were held back are not replayed later.",
    },
    ["debug_value"]={
        summary="Shows the current value of a wire right on the graph so you can see what is going on.",
        use="Put it on any connection while building. Example: check what number your health source really outputs.",
        advanced="The value passes through unchanged. Secret values stay hidden. The preview only updates while the editor is open and is never saved. For nameplates you pick a specific plate.",
    },
    ["display"]={
        summary="Puts media (icon, text, bar, graphic) on your screen. This is the end point that makes things visible.",
        use="Connect media and optionally a Visible condition. Example: show a buff icon only while the buff is missing.",
        advanced="Real Time can drive a native icon countdown or bar timing. If Real Time is connected but unavailable, the display hides; if not connected, the media is shown normally.",
    },
    ["display_lifecycle"]={
        summary="Adds show and hide animations to a display: an effect when it appears, a loop while it is shown and an effect when it disappears.",
        use="Example: let an icon fade in, pulse while visible and shrink away when it hides, like in WeakAuras.",
        advanced="The display hides only after the finish effect. Showing it again during finish cancels the finish. Action Display ignores it, because protected buttons cannot delay hiding.",
    },
    ["display_stack"]={
        summary="Combines up to eight media elements into one display per unit, for example icon, name and health bar together.",
        use="Connect the Instance output of a nameplate or group source so each unit gets its own set. Example: a small icon plus timer above every enemy nameplate.",
        advanced="The root element sets the size; others keep their offsets. Sort uses readable values only; secret or missing values keep their normal order.",
    },
    ["encounter_event"]={
        summary="Fires when a boss encounter starts or ends and gives you details such as encounter name, difficulty and whether it was a success.",
        use="Example: reset your timers when a boss fight starts, or play a sound when it was won.",
        advanced="Only new events count; nothing is replayed after a reload. Some details may be missing or secret.",
    },
    ["focus"]={
        summary="Gives you information about your focus target: health, power, class and many more values you choose.",
        use="Example: show your focus target's health or cast bar in a separate spot.",
        advanced="When there is no focus, all other values clear. Secret values can still be shown, but not compared. Values the game does not provide stay unavailable, never zero.",
    },
    ["focus_target"]={
        summary="Gives you information about the target of your focus.",
        use="Example: see whom your focus is attacking.",
        advanced="Clears when your focus has no target. Secret values stay hidden but can be shown in displays.",
    },
    ["format"]={
        summary="Builds a text from a template, putting a number where {value} appears.",
        use="Example: turn 42 into \"HP: 42%\". For new graphs, String Formatter or Format text with several values are more flexible.",
    },
    ["format_values"]={
        summary="Builds a text from up to 16 values using placeholders like {1}, {2} or {value1}, with extras such as percent and time.",
        use="Example: \"{1} / {2} ({percent}%)\" shows current and maximum mana with a percentage.",
        advanced="{time1} to {time16} show seconds as m:ss. Decimal places apply to numbers. It can hide itself when Value 1 is 0 or 1. Missing or secret values leave the text unavailable; use String Formatter for secret values.",
    },
    ["frame_state"]={
        summary="Watches a frame from the frame library and tells you whether it exists and whether it is visible.",
        use="Example: hide your own display while the default map or another addon window is open.",
        advanced="Shown and Hidden only fire on real changes, not on first observation. Read-only; it never changes the frame.",
    },
    ["gate"]={
        summary="Turns a true/false condition into a trigger event, either once when it becomes true or repeatedly with a waiting time.",
        use="Example: send one chat message when your health drops low, or remind you at most every 10 seconds while a buff is missing.",
        advanced="In activation mode it fires once each time the condition switches to true. In timed mode it fires while the condition is true, at most once per the set seconds.",
    },
    ["glow"]={
        summary="Adds a glow effect around an icon or text, like the proc glow on your action bars.",
        use="Example: make an icon glow when your proc is active.",
        advanced="Icons can use the Blizzard button or proc glow, or pixel and autocast styles. Text can use soft, outline, neon, shadow or a frame. Colour, spread, pulse and speed can be set or wired.",
    },
    ["group_action"]={
        summary="An action that starts a ready check or a countdown when you click it.",
        use="Connect it to an Action Display. Example: a button that starts a 10-second pull countdown.",
        advanced="Only outside combat, and you must be group leader or assistant. The countdown can be 1 to 3600 seconds.",
    },
    ["group_aura"]={
        summary="Watches one buff or debuff on every member of your party or raid, each as its own instance.",
        use="Connect Instance to a Display Stack. Example: show which raid members are missing your buff.",
        advanced="Slots are temporary; when the roster changes, the old instance is reset. Secret aura data stays hidden. Estimates are best guesses, not recovered secret data.",
    },
    ["group_cast"]={
        summary="Watches the casts of every member of your party or raid, each as its own instance.",
        use="Example: show a small cast bar for each healer in your group.",
        advanced="Cast succeeded is a real game event, never guessed or replayed. Slots are temporary and reset on roster changes.",
    },
    ["group_units"]={
        summary="Gives you information (health, power, role and more) for every member of your party or raid, each as its own instance.",
        use="Connect Instance to a Display Stack to build a simple group overview. Example: health bars for your party.",
        advanced="Party means the four other members; you are separate. This is read-only and not a replacement for clickable raid frames. Secret values stay hidden, missing values are not zero.",
    },
    ["hp"]={
        summary="Your own current health, maximum health and health percentage.",
        use="Example: show a warning when your health is low. The newer Player node offers the same and much more.",
        advanced="These values can be secret; then they can be shown but not compared or calculated.",
    },
    ["icon"]={
        summary="An older, simple display that shows a chosen icon while its Visible input is true.",
        use="Example: show a buff icon while the buff is missing. For new graphs, use Icon media with a Display.",
    },
    ["icon_appearance"]={
        summary="Changes how an icon looks: original or cropped border, a skin, and a shape such as round or hexagon.",
        use="Example: give your icons a round shape and a matching border skin.",
        advanced="Round and other shapes only change the look; the click area stays rectangular. When the skin is Masque, Masque controls the artwork. Set up action skins outside combat.",
    },
    ["icon_border"]={
        summary="Draws a border around an icon, as a solid line, corners or a double line.",
        use="Example: give an icon a red border while the target is casting.",
        advanced="Colour and width can be wired. Width or alpha 0 hides the border. Only affects icons; other media pass through unchanged.",
    },
    ["icon_cooldown"]={
        summary="Adds the game's cooldown swipe and countdown numbers for a spell on top of an icon.",
        use="Example: show your interrupt icon with its cooldown spiral.",
        advanced="Needs game support; if the cooldown is unavailable the overlay is cleared. Isolated Test does not read live cooldowns.",
    },
    ["icon_duration"]={
        summary="Lets an icon show the game's own countdown spiral from a timer.",
        use="Connect a Real Time output (for example from Unit Aura). Example: a debuff icon with a native countdown on your target.",
        advanced="The timer is passed straight to the game; no timing is calculated by the addon. A missing timer is not treated as zero.",
    },
    ["input_dialog"]={
        summary="Shows a dialog where you can type a value, with OK and Cancel, and continues your graph with what you entered.",
        use="Example: ask for new macro text and then write it with Write Macro.",
        advanced="Completed fires once; Confirmed is false on Cancel. The input never grabs your keyboard automatically in combat. Closing the graph cancels the dialog.",
    },
    ["interval"]={
        summary="Fires a trigger again and again at a fixed interval while it is active.",
        use="Example: remind you every 5 minutes to check your buffs.",
        advanced="The first pulse comes after one interval, or immediately if enabled. Missed pulses are skipped, not fired in a burst. Interval 0.1 to 86400 seconds.",
    },
    ["is_nil"]={
        summary="Tells you whether a connection currently has no value.",
        use="Example: show a fallback text when a source has nothing to report.",
        advanced="0, false and empty text are real values, so they give false. A secret value cannot be tested; the result stays secret. Use Secret to check whether a value is readable.",
    },
    ["item_action"]={
        summary="An action that uses an item, by item ID or by equipment slot, when you click it.",
        use="Connect it to an Action Display. Example: a button for your healing potion or your trinket.",
        advanced="Trinkets are slots 13 and 14. The game may equip an unequipped item instead of using it. Configure outside combat.",
    },
    ["item_cooldown"]={
        summary="Tells you whether an item or equipped slot is on cooldown and when it will be ready again.",
        use="Example: show your trinket icon only when its cooldown is over.",
        advanced="Enabled off means the timer is paused (for example a potion used in combat). Feed Expiration into Remaining estimate for a countdown. Ignore GCD treats very short cooldowns as not active.",
    },
    ["item_count"]={
        summary="How many of a certain item you are carrying.",
        use="Example: warn you when you have fewer than 5 healing potions left.",
        advanced="If the game does not provide the number, it stays unavailable and is not treated as zero.",
    },
    ["item_equipped"]={
        summary="Tells you whether a certain item is currently equipped.",
        use="Example: remind you to swap back to your normal trinket after a fishing session.",
    },
    ["last_unprotected_value"]={
        summary="Remembers the last readable value and keeps showing it while the game hides the current value.",
        use="Example: keep showing your last known stack count when it becomes secret in combat.",
        advanced="Using cached value tells you when the old value is shown. It is an old observation, never recovered secret data. A missing input or Reset clears it.",
    },
    ["location"]={
        summary="Where you are: zone, subzone, map ID and whether you are in an instance.",
        use="Example: only show your raid displays when you are inside a raid instance.",
    },
    ["logic"]={
        summary="Combines several true/false inputs: AND, OR, XOR, NAND, NOR, XNOR or NOT. You pick the operation in the node.",
        use="Example: true only when you are in combat AND your target is casting.",
        advanced="AND and OR can decide even if another input is unknown (one false decides AND, one true decides OR). XOR and XNOR need all inputs. 2 to 16 inputs.",
    },
    ["logic_and"]={
        summary="True only when all inputs are true.",
        use="Example: show a warning only when you are in combat AND your health is low.",
        advanced="One false input decides the result even if others are unknown. Otherwise an unknown input makes the result unknown. 2 to 16 inputs.",
    },
    ["logic_branch"]={
        summary="Sends a value to either the True or the False output, depending on a condition.",
        use="Example: send a trigger to one message when you are in combat and to another when you are not.",
        advanced="The other output gets no value, so connected displays clear. Events are only routed when a new event arrives, not when the condition changes. Nodes before it still run.",
    },
    ["logic_not"]={
        summary="Flips true to false and false to true.",
        use="Example: turn \"buff present\" into \"buff missing\".",
        advanced="An unknown value stays unknown.",
    },
    ["logic_or"]={
        summary="True when at least one input is true.",
        use="Example: show an icon when you have either of two buffs.",
        advanced="One true input decides the result even if others are unknown. 2 to 16 inputs.",
    },
    ["logic_select"]={
        summary="Picks one of two values: If true or If false, depending on a condition.",
        use="Example: show the text \"Ready\" or \"Wait\" depending on whether a spell is usable.",
        advanced="Only the chosen value is used. If the condition is unknown, nothing is chosen. It selects values; it does not stop other parts of the graph from running.",
    },
    ["macro_action"]={
        summary="An action that runs one of your saved game macros when you click it.",
        use="Connect it to an Action Display. Example: a large button for your mount macro.",
        advanced="The macro is identified by name and account or character scope; missing or ambiguous macros stay inactive. Saving in the macro editor changes the game macro outside combat. Imports never write macro text.",
    },
    ["macro_exists"]={
        summary="Checks whether a game macro with a certain name exists.",
        use="Example: if your helper macro is missing, create it automatically with Write Macro.",
        advanced="Without a Check input it refreshes when the game reports macro changes. A read failure never means missing. It never writes or runs macros. Test does not check.",
    },
    ["macro_write"]={
        summary="Saves text into a game macro (update, create or both) when triggered.",
        use="Example: rewrite a macro with a new target name typed into an Input Dialog.",
        advanced="You must allow macro writes on the node; imports turn this off. Only outside combat, no retry. Saved fires only after the game confirms the new text. It never runs the macro.",
    },
    ["markdown_note"]={
        summary="A text note on the canvas to explain your graph. It does nothing else.",
        use="Write down what a part of your graph does or how to use it. Headings, bold, lists and links are supported; line breaks and empty lines show as you type them.",
        advanced="Saved and exported with the graph. Up to 4000 bytes; width can be changed by dragging the corner.",
    },
    ["lua_script"]={
        summary="Runs a small Lua function you write: inputs in1..in4 in, up to four outputs out.",
        use="Example: return in1 * 2, or combine texts. Set the number and types of inputs and outputs in the details; open the code with Edit code.",
        advanced="The code sees only its inputs, math, string, table, a memory table kept between runs and read-only game functions (UnitHealth, UnitName, GetTime ...). No globals, frames or protected actions such as targeting. Errors and runs over 10 ms turn the node red. Imported code is shown but switched off until you enable Allow running code. An endless loop freezes the game, because WoW cannot interrupt Lua.",
    },
    ["marker_action"]={
        summary="An action that sets, clears or toggles a raid target marker (skull, cross and so on) or a world marker when you click it.",
        use="Connect it to an Action Display. Example: a button that puts a skull on your target.",
        advanced="World markers open the placement cursor. Group permissions still apply.",
    },
    ["math"]={
        summary="Calculates with two numbers: add, subtract, multiply, divide, remainder or percent.",
        use="Example: calculate your health percentage from current and maximum health.",
        advanced="Secret values cannot be used. Division by zero or invalid results give no result and Successful off. Bypass passes the first value unchanged.",
    },
    ["media_bar"]={
        summary="A bar that fills according to a value and a maximum, like a health or resource bar.",
        use="Example: a custom health bar for your target, filling from left to right.",
        advanced="Secret values can still fill the bar through the game's own bar. Four fill directions; colours and border can be wired. Bars cannot be rotated.",
    },
    ["media_button"]={
        summary="A labelled button look in several styles (WoW, Modern, Arcane and more) with hover and pressed effects.",
        use="Connect it to an Action Display together with Spell Action to make a castable button. The look alone does nothing.",
        advanced="Font and Style inputs are optional. For ordinary graph clicks on a normal display, use Clickable media.",
    },
    ["media_crop"]={
        summary="Crops part of an icon or graphic away, and can flip it or change its blend mode.",
        use="Example: zoom into the middle of an icon, or mirror a graphic.",
        advanced="Values from 0 to 1 describe the part of the artwork. Replaces the default icon border crop. The size and click area stay the same.",
    },
    ["media_event"]={
        summary="Fires when a clickable element with the same interaction key is clicked, and passes along the values captured at the click.",
        use="Pair it with Click Action or Clickable media. Example: click an icon to reset a timer.",
        advanced="Works for normal displays and single elements of a Display Stack. Payload fields are set on the clickable element. Active off or Mute stops the events.",
    },
    ["media_font"]={
        summary="A reusable font setting (font, size, outline) you can connect to several text nodes.",
        use="Example: give all your texts the same font in one place.",
        advanced="SharedMedia fonts must be installed for anyone you share with; otherwise a fallback font is used and reported.",
    },
    ["media_graphic"]={
        summary="Shows a picture: an addon file, a game texture, a texture ID or a Blizzard atlas image.",
        use="Example: show a custom arrow graphic or a Blizzard artwork element.",
        advanced="Files must exist on your computer; sharing a graph only shares the path. Missing images are cleared. Optional crop settings.",
    },
    ["media_icon"]={
        summary="An icon picture made from a texture ID, ready to show in a display.",
        use="Pick an icon or connect a Texture ID, then connect it to a Display. Example: show the icon of the spell you track.",
        advanced="A secret texture ID can still be shown.",
    },
    ["media_interaction"]={
        summary="Makes media clickable inside your graph, for ordinary (non-combat-action) clicks.",
        use="Pair it with Media event using the same key. Example: click a display to switch between two modes.",
        advanced="Up to eight payload values are captured at each click. Optional mouse feedback shows hover and press. Disabled media lets clicks pass through. No protected game actions.",
    },
    ["media_overlay"]={
        summary="Writes text on top of other media, for example a number on an icon.",
        use="Example: show stack count or item count in the corner of an icon.",
        advanced="Secret numbers or text can still be shown this way. If wired text is missing, that part of the display becomes invalid.",
    },
    ["media_sprite"]={
        summary="Treats a picture as a grid of small frames and shows one frame or plays them as an animation.",
        use="Example: play an animated effect from a sprite sheet, or pick a frame with a counter.",
        advanced="Frames are counted row by row from the top left. Animate plays natively at the chosen frames per second and replaces an earlier crop.",
    },
    ["media_style"]={
        summary="A reusable look (colour, background, border, opacity) you can connect to icons, graphics, text and bars.",
        use="Example: give all bars of a set the same background and border.",
        advanced="A connected style replaces the local style settings; later modifiers still apply. It does not change font, texture or size.",
    },
    ["media_text"]={
        summary="A piece of text ready to show in a display, with font, size, alignment and an optional symbol.",
        use="Example: show \"Interrupt!\" in large letters, or your target's name.",
        advanced="Secret text can still be shown. Font, Style and Symbol can be connected from their definition nodes.",
    },
    ["memory"]={
        summary="Stores or reads a small value in the graph's temporary memory: Get, Set, Delete or Clear. You pick the action in the node.",
        use="Example: remember how often something happened during a fight.",
        advanced="Memory is temporary and only for this graph; it is lost when you apply, disable or stop the graph. Readable values only, up to 64 keys. Chain Done to the next Trigger to control the order.",
    },
    ["memory_clear"]={
        summary="Empties the graph's temporary memory when triggered.",
        use="Example: clear all remembered values when a new boss fight starts.",
        advanced="Only affects this graph (or the current nameplate instance), never other graphs or saved data.",
    },
    ["memory_delete"]={
        summary="Removes one remembered value from the graph's temporary memory when triggered.",
        use="Example: forget a stored player name once it is no longer needed.",
    },
    ["memory_get"]={
        summary="Reads one remembered value from the graph's temporary memory when triggered.",
        use="Example: read back a counter you stored earlier.",
        advanced="It reads at the moment of the trigger, not continuously. Found tells a missing value apart from false, 0 or empty text. A different stored type reports a type mismatch.",
    },
    ["memory_output"]={
        summary="Reads the graph's temporary memory and gives it to you as a Dictionary (key and value pairs) when triggered.",
        use="Example: read all stored values at once and show them in a list.",
        advanced="You can list the keys you want (comma separated) or leave it empty for all, and choose the sort order. Done fires after reading.",
    },
    ["memory_set"]={
        summary="Stores a value under a name in the graph's temporary memory when triggered.",
        use="Example: store the time an ability was last used.",
        advanced="Readable values only; secret values cannot be stored. Text up to 1024 bytes. The memory is not saved between sessions.",
    },
    ["message_receive"]={
        summary="Receives small pieces of data sent by Send Addon Message, from your own graphs or from other players using BV.",
        use="Example: let a raid leader's graph tell your graph that a phase has started.",
        advanced="You can limit senders and accept group members only. No visible chat is involved. Receiving must be allowed on the node.",
    },
    ["message_send"]={
        summary="Sends a small piece of data to your own graphs or to other players using BV, without a visible chat message.",
        use="Example: tell your group's graphs when you used a raid cooldown.",
        advanced="Sending must be allowed on the node; imports turn it off. The routing name is not a password. Test never sends. Small messages only; sharing whole graphs works differently.",
    },
    ["multiply"]={
        summary="Multiplies a number by a factor.",
        use="Example: turn a value from 0-1 into a percentage by multiplying by 100.",
    },
    ["nameplate"]={
        summary="Gives you information about the unit behind one nameplate slot.",
        use="Example: watch one specific visible nameplate. To follow all nameplates, use Nameplates instead.",
        advanced="Nameplate slots are temporary; when a plate is reused, it may show a different unit.",
    },
    ["nameplates"]={
        summary="Watches all visible nameplates (all, friendly or hostile), each as its own instance.",
        use="Connect Instance to a Display Stack. Example: show health text above every enemy nameplate.",
        advanced="Slots are temporary; a reused slot starts a new instance. Friendly and hostile need readable information.",
    },
    ["nameplates_aura"]={
        summary="Watches one buff or debuff on every visible nameplate.",
        use="Example: show your damage-over-time timer above every enemy it is on.",
        advanced="Secret aura data stays hidden; Real Time can still drive a countdown. Estimates are best guesses, not recovered data.",
    },
    ["nameplates_cast"]={
        summary="Watches casts on every visible nameplate.",
        use="Example: show which enemies around you are casting and what they cast.",
        advanced="Cast data comes straight from the game; nothing is guessed or replayed.",
    },
    ["number"]={
        summary="A fixed number you type in.",
        use="Example: a threshold like 35 for a health warning.",
    },
    ["offset"]={
        summary="Moves media by an X and Y amount.",
        use="Example: nudge a text a little up from the icon, or combine with Circle position to move things around.",
        advanced="Affects either only the look or also the layout. Values can be wired.",
    },
    ["ooc_action_stack"]={
        summary="A group of up to eight buttons that cast the same spell on different targets, which you can change outside combat.",
        use="Example: one buff button per party member, each casting your buff on that member.",
        advanced="Only changes outside combat; everything is locked in combat. Spell override and visibility apply out of combat only. Test never casts.",
    },
    ["opacity"]={
        summary="Makes media more or less transparent.",
        use="Example: fade out an icon to 30 percent while the spell is on cooldown.",
        advanced="0 is invisible, 1 is fully visible. Can be wired.",
    },
    ["parse"]={
        summary="Converts a value into another type, for example text to a number or a number to on/off.",
        use="Example: turn a typed number from an input dialog into a real number.",
        advanced="Whole numbers must not have decimals; no rounding happens. On/off accepts true/false and 1/0. Invalid input gives Successful off and no value. Secret input is never looked at.",
    },
    ["party_member"]={
        summary="Gives you information about the player in one party slot (1 to 4).",
        use="Example: show the health of your party's tank.",
        advanced="The slot is a position, not a person; if the group changes, a different player may be shown. Use Group units to follow everyone.",
    },
    ["pet"]={
        summary="Gives you information about your pet: health, power and more.",
        use="Example: warn you when your pet's health is low.",
        advanced="When you have no pet, the other values clear.",
    },
    ["pet_action"]={
        summary="An action that clicks one of your pet bar slots (1 to 10).",
        use="Connect it to an Action Display. Example: a bigger button for your pet's attack command.",
        advanced="The slot content belongs to your current pet.",
    },
    ["play_sound"]={
        summary="Plays a sound when triggered, from the game's sounds or from SharedMedia.",
        use="Example: play a bell when your proc triggers.",
        advanced="Stop wins over Play; a new sound replaces the previous one from this node. Your game sound settings are not changed. Test is silent; use Preview sound in the node details.",
    },
    ["player"]={
        summary="Everything about you: health, power, resources, combat state and many more values you choose.",
        use="Example: build your own health and mana bar, or show your combo points.",
        advanced="Only the values you connect are read. Secret values can be shown but not compared or calculated. Values the game does not support stay unavailable.",
    },
    ["player_cast"]={
        summary="Fires when you successfully cast a spell, either any spell or a specific one.",
        use="Example: start a timer when you cast a certain cooldown.",
        advanced="If the spell ID is secret, a specific spell filter cannot match. It does not guess cooldowns or damage.",
    },
    ["player_durability"]={
        summary="Shows how damaged your equipment is: lowest and total percentage, damaged and broken items, or one slot.",
        use="Example: remind you to repair when an item drops below 20 percent.",
        advanced="Items without durability are skipped. If nothing counts, the values stay unavailable instead of showing 100 percent.",
    },
    ["player_money"]={
        summary="How much money you have, in copper.",
        use="Example: show your gold on screen.",
    },
    ["player_state"]={
        summary="Whether you are mounted, resting or moving.",
        use="Example: hide your combat displays while you are mounted.",
    },
    ["player_swing"]={
        summary="Fires when you swing your weapon, with swing duration and hand information.",
        use="Example: build a simple swing timer.",
        advanced="This is a swing timer event, not proof of a hit or damage. A hand filter needs readable hand information.",
    },
    ["player_talent"]={
        summary="Tells you the rank of one talent in your active talent setup.",
        use="Example: only show a display if you have a certain talent.",
        advanced="Uses the talent node ID, not a spell ID. Unknown nodes stay unavailable, never rank 0. It never changes your talents.",
    },
    ["player_xp"]={
        summary="Your experience: current, required, rested, your level and whether you are at the level cap.",
        use="Example: build your own XP bar.",
    },
    ["raid_member"]={
        summary="Gives you information about the player in one raid slot (1 to 40).",
        use="Example: watch the health of the player in raid slot 1.",
        advanced="The slot is a position, not a person; roster changes can change who is shown. Use Group units to follow everyone.",
    },
    ["ready_check_event"]={
        summary="Fires when a ready check starts or ends, with who started it and the time limit.",
        use="Example: play a loud sound when a ready check begins so you don't miss it.",
        advanced="Only new events count; nothing is replayed. Some details may be missing.",
    },
    ["regex"]={
        summary="Tests, finds or replaces text using search patterns.",
        use="Example: find a number in a chat message, or check whether a name ends with a certain word.",
        advanced="Supports common pattern features but no backreferences or lookaround. Pattern up to 256 bytes, text up to 1024 characters. Limits or protected text give no result, never a false match.",
    },
    ["relay"]={
        summary="Passes its input through unchanged.",
        use="Rename it to label a connection point, for example as a named input or output of a building block.",
    },
    ["remaining_estimate"]={
        summary="Keeps a countdown running from the last readable time when the game hides the remaining time.",
        use="Example: keep a buff timer counting down in combat when the real time becomes secret.",
        advanced="This is an estimate, not recovered secret data. Without a starting value it gives nothing. Hidden refreshes cannot be detected; zero does not prove the aura ended. Estimated tells you when the fallback is used.",
    },
    ["reputation"]={
        summary="Information about a faction: name, standing and progress.",
        use="Example: show your progress with your watched faction. Faction ID 0 uses the watched faction.",
    },
    ["rotate"]={
        summary="Rotates a graphic by a number of degrees.",
        use="Example: turn an arrow graphic to point in a certain direction.",
        advanced="Degrees are counter-clockwise. Bars and text overlays cannot be rotated.",
    },
    ["rotate_offset"]={
        summary="Rotates an X/Y position around the center by a number of degrees.",
        use="Example: turn a whole arrangement of icons by an angle.",
        advanced="Degrees are counter-clockwise.",
    },
    ["round"]={
        summary="Rounds a number to 0 to 6 decimal places, rounding normally, down or up.",
        use="Example: show 12.3 instead of 12.3456.",
        advanced="Gives both a number and a text with exactly the requested decimal places. Secret values are not calculated.",
    },
    ["scale"]={
        summary="Makes media bigger or smaller by a factor.",
        use="Example: make an icon 1.5 times larger while a proc is active.",
        advanced="Factor 0 to 10. Can affect only the look or also the layout.",
    },
    ["secret"]={
        summary="Shows whether a value is hidden by the game (secret) and passes it on unchanged.",
        use="Example: show a hint when a value is currently secret in combat.",
        advanced="Is Secret is true for hidden values; Is Available is only true for readable values. Secret values can still reach String Formatter and displays, but cannot be compared or calculated.",
    },
    ["secure_action_stack"]={
        summary="A group of up to eight buttons that each cast the same spell on a different target, usable in combat.",
        use="Example: one button per party member to cast a heal on them.",
        advanced="Set up and apply outside combat; in combat the buttons, their targets and positions stay fixed. Suggest only changes the look. Test never casts.",
    },
    ["secure_spell"]={
        summary="A simple button that casts one spell on yourself when you click it.",
        use="Example: a button for your self-buff. For more options use Spell Action with Action Display.",
        advanced="Apply outside combat. Graph events never cast; only your click does. Position with the Layout Editor. Changes wait until combat ends. Test is just a preview.",
    },
    ["size"]={
        summary="Changes the width and height of media by a certain amount.",
        use="Example: make a bar wider when you are in combat.",
        advanced="Can affect only the look or also the layout. Values can be wired.",
    },
    ["spell_action"]={
        summary="An action that casts a chosen spell on a chosen target (you, your target, your focus and so on).",
        use="Connect it to an Action Display. Example: a button that casts your heal on your focus.",
        advanced="This node never casts by itself; only your click does. Set it up and apply outside combat.",
    },
    ["spell_charges"]={
        summary="How many charges of a spell you have, the maximum, and whether a charge is recharging.",
        use="Example: show a number with your available charges.",
        advanced="Missing or secret values stay unavailable, never zero.",
    },
    ["spell_cooldown"]={
        summary="Whether a spell is on cooldown, whether it is enabled and whether only the global cooldown is running.",
        use="Example: show an icon when your cooldown is ready.",
    },
    ["spell_known"]={
        summary="Whether you know a certain spell.",
        use="Example: only show a display if you have learned the spell.",
    },
    ["spell_proc"]={
        summary="Whether the game currently shows a proc glow for a spell.",
        use="Example: show a big alert when your proc is active.",
    },
    ["spell_queued"]={
        summary="True while a spell is being cast or waits for your next swing, such as Heroic Strike or Maul. Also shows whether auto-repeat (Auto Shot, Shoot) is running.",
        use="Example: show a small icon while Heroic Strike is queued.",
        advanced="The game cannot tell casting and queued apart; combine with Unit Cast if you need queued only.",
    },
    ["spell_usable"]={
        summary="Whether a spell can be used right now, and whether you lack the resources for it.",
        use="Example: grey out an icon while you don't have enough mana.",
    },
    ["string_formatter"]={
        summary="Builds a text from up to 16 values using placeholders like {1} and {2}.",
        use="Example: \"{1} - {2}\" shows your target's name and health.",
        advanced="Also works with secret numbers or text for displays; the result then stays secret and cannot be compared. No calculations: use Round, Math and Time Format for that.",
    },
    ["symbol"]={
        summary="A simple line symbol (like a star, heart or arrow) you can show or place next to text.",
        use="Example: add a warning symbol next to a text or in a toast note.",
        advanced="Symbols come from the bundled Lucide set, not from WoW icons. The colour input tints them.",
    },
    ["target"]={
        summary="Gives you information about your current target: health, power, class and many more values you choose.",
        use="Example: build your own target health bar.",
        advanced="When you have no target, the values clear. Secret values can still be shown but not compared.",
    },
    ["target_changed"]={
        summary="Fires when your target changes, including when you clear it.",
        use="Example: reset a display or play a sound whenever you switch target.",
        advanced="Has target is only false when the game says you have no target. Protected names stay protected and never count as no target. For a snapshot at a chosen moment, use Capture target.",
    },
    ["target_target"]={
        summary="Gives you information about the target of your target.",
        use="Example: see whether the boss is attacking you or the tank.",
    },
    ["text_compare"]={
        summary="Compares two texts: equals, not equals, contains, starts with or ends with.",
        use="Example: check whether a chat message contains the word \"inv\".",
        advanced="Exact comparison without patterns (use Regex for patterns). Ignore case is available. Protected or missing text gives an unknown result, never false.",
    },
    ["text_outline"]={
        summary="Adds an outline around text.",
        use="Example: make white text readable on bright backgrounds.",
        advanced="Width 0 to 6. Only affects text; other media pass through.",
    },
    ["text_shadow"]={
        summary="Adds a shadow behind text.",
        use="Example: give text a soft drop shadow for better readability.",
        advanced="Offset -64 to 64. Only affects text.",
    },
    ["time_format"]={
        summary="Turns seconds into a clock-style text like 1:05.",
        use="Example: show a timer as minutes and seconds.",
        advanced="Works for 0 to 86400 seconds; fractions round to the nearest second. Secret values produce no text. It only formats; it does not count down.",
    },
    ["timer"]={
        summary="Counts from a start time to a target time, one second per second, up or down.",
        use="Example: a 10-second countdown that sends a message when it finishes.",
        advanced="Active off resets to the start. Reset is an event. Finished fires once. Values 0 to 86400 seconds.",
    },
    ["timestamp"]={
        summary="Notes the time at the moment its input switches from off to on, and keeps it until the next switch.",
        use="Example: remember when a buff was applied, to calculate how long ago it was.",
        advanced="There is no running clock; it only records a moment.",
    },
    ["tint"]={
        summary="Changes the colour of media.",
        use="Example: turn an icon red when you are out of range.",
        advanced="The colour can be picked and further adjusted with red, green and blue inputs.",
    },
    ["toast_note"]={
        summary="Shows a short pop-up note at a screen corner or edge, with optional icon, symbol and sound.",
        use="Example: \"Pull in 5!\" in the top corner with a sound.",
        advanced="Up to five notes stack per position. Notes are click-through unless you allow dismissing them. Closed fires when a note disappears. Notes also show in combat and in Test Mode.",
    },
    ["totem"]={
        summary="Information about one totem slot (1 to 4): whether a totem is there, its name, icon and duration.",
        use="Example: show which totems you have out and how long they last.",
    },
    ["ui_action"]={
        summary="An action that opens or closes the character panel, spellbook, bags or map when you click it.",
        use="Connect it to an Action Display. Example: your own bag button.",
        advanced="Works outside combat.",
    },
    ["unit"]={
        summary="Gives you information about one unit you choose: player, target, focus, pet, party or raid slot, mouseover and more.",
        use="Example: build a mouseover health display.",
        advanced="Party and raid use a slot, not a person. Mouseover clears when you move away. Secret values stay hidden; unavailable values are not zero.",
    },
    ["unit_action"]={
        summary="An action that targets, clears your target, assists or sets focus on a unit when you click it.",
        use="Connect it to an Action Display. Example: a button or key to target your focus. Formerly named Unit Action.",
        advanced="WoW sets target and focus only from your own click or key press on the button, never automatically from a trigger or timer, and the button cannot change in combat. To target by name use a Macro Action with /target Name or /focus Name. Focus needs game support. Target clicks follow the game's cursor spell behaviour.",
    },
    ["unit_aura"]={
        summary="Watches one buff or debuff on a unit you choose (player, target, focus, party or raid slot and more).",
        use="Example: show your debuff on the target with its remaining time.",
        advanced="Real Time drives a native countdown. Estimates are best guesses when data is secret, not recovered values.",
    },
    ["unit_cast"]={
        summary="Watches casting and channelling of a unit you choose.",
        use="Example: show a warning when your target starts casting.",
        advanced="Cast data comes straight from the game; nothing is guessed or replayed.",
    },
    ["unit_menu_action"]={
        summary="An action that opens the right-click menu for a unit.",
        use="Connect it to an Action Display. Example: open your target's menu from a custom frame.",
    },
    ["unit_range"]={
        summary="Estimates how far away a unit is, as a minimum and maximum distance.",
        use="Example: warn you when your healer is out of range.",
        advanced="Exact only for group members in the open world. Unknown or protected never means out of range. Refreshes about four times per second.",
    },
    ["unit_record"]={
        summary="Picks one specific field out of a larger record, for example the name of an aura.",
        use="Example: get just the spell name from an aura record.",
        advanced="Positions 1 to 40. Secret fields stay hidden but can still be shown.",
    },
    ["weapon_enchant"]={
        summary="Information about temporary weapon enchants like poisons, oils, stones or imbues.",
        use="Example: remind you to reapply poison when it runs out.",
        advanced="Time left is read when the enchant changes; feed Expiration into Remaining estimate for a countdown.",
    },
}}
