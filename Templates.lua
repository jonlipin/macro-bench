-- Macro Bench blocks and templates.
--
-- The palette is the list of blocks you can drag onto the bench. Templates are whole macros, kept as
-- macro text and nothing else: loading one parses it, so a template can never disagree with what the
-- builder would have produced, and every template is checked by the same pass as your own work.
--
-- Spells are named, not id'd, exactly as a macro names them. A template whose spell you do not have
-- still loads: the check marks the line so you can see what to swap.

local ADDON, ns = ...
local T = {}
ns.Templates = T

-- An icon that is missing draws as a black square, so anything uncertain falls back to the
-- question mark. The client will not always say, in which case it is taken on trust.
local ICON_PATH = "Interface\\Icons\\"
function ns.SafeIcon(name)
	if not name or name == "" then return ns.QUESTION end
	if type(name) == "number" then return name end
	if name:find("\\") then return name end
	local path = ICON_PATH .. name
	if GetFileIDFromPath then
		local ok, id = pcall(GetFileIDFromPath, path)
		if ok and (id == nil or id == 0) then return ns.QUESTION end
	end
	return path
end

local CAST = "Spell_Fire_FlameBolt"
local ITEM = "INV_Potion_54"
local PAPER = "INV_Misc_Note_01"
local BOOK = "INV_Misc_Book_09"
local SWORD = "INV_Sword_04"
local PET = "Ability_Hunter_BeastCall"
local FOOD = "INV_Misc_Food_15"
local RAGE = "Racial_Orc_BerserkerStrength"
local SEQ = "Ability_Marksmanship"

-- ------------------------------------------------------------------
-- The palette
-- ------------------------------------------------------------------
-- cmd    which command the block writes
-- arg    what it starts out saying
-- cond   a condition it starts with
-- label  overrides the command's own name, when the preset deserves its own
T.PALETTE = {
	{ heading = "Spells and items", items = {
		{ cmd = "cast", arg = "", icon = CAST, tip = "Cast a spell. Drag a spell straight out of your spellbook onto the bench and you get this, filled in." },
		{ cmd = "castsequence", arg = "reset=combat ", icon = SEQ, tip = "Cast the next spell in a list each time you press it. The reset says when it goes back to the start." },
		{ cmd = "use", arg = "", icon = ITEM, tip = "Use an item by name, by bag and slot, or by equipment slot number. Drag an item out of your bags to fill it in." },
		{ cmd = "use", arg = "13", label = "Use trinket", icon = ITEM, tip = "13 is your top trinket, 14 the bottom one." },
		{ cmd = "castrandom", arg = "", icon = SEQ, tip = "Cast one of several at random. Mounts and pets, mostly." },
	} },
	-- These are not commands: they are the parts of one line's conditions, dragged onto a line the
	-- same way an action is dragged onto the chain.
	{ heading = "When does it run", items = {
		-- seed: what the part says the moment it lands, so it is never an empty block you cannot see.
		-- shows: what it says while it is still in the list — the range it covers, not the one value
		-- it happens to arrive with, which would read as the only thing it can say.
		{ part = "mods", seed = "mod:shift", shows = "shift, ctrl, right click…", label = "Modifier", icon = RAGE,
		  tip = "Which modifier keys have to be held down, which must not be, and which mouse button pressed the macro: left, right, middle or the two side buttons. Dropped on a line, it decides when that line runs. It arrives set to shift; click it to change." },
		{ part = "target", seed = "@mouseover", shows = "mouseover, target, focus…", label = "Target filter", icon = SWORD,
		  tip = "What the line is aimed at — mouseover, target, focus, you, your pet, anybody by name — and what has to be true of it: an enemy, friendly, alive, dead, in your party. It arrives aimed at your mouseover; click it to change." },
		{ part = "state", seed = "combat", shows = "in combat, stealthed…", label = "My state", icon = PET,
		  tip = "What has to be true of you: in combat, stealthed, mounted, swimming, indoors, in a form, which pet is out, what you have equipped. It arrives set to in combat; click it to change." },
		{ part = "or", label = "Or these instead", icon = SEQ, shows = "a second set of brackets",
		  tip = "A second set of brackets on the same attempt. The game tries the conditions before it; if they do not apply it tries these, and the first set that does decides what happens. In the macro it is [these][or these] Spell — the mouseover ladder every healer uses." },
		{ part = "otherwise", label = "Otherwise", icon = SEQ, tip = "Another go at the same line, read only when the conditions before it do not apply. The part after the semicolon." },
	} },
	{ heading = "The button itself", items = {
		{ cmd = "#showtooltip", arg = "", icon = BOOK, tip = "Gives the button its icon, its cooldown and its tooltip. With nothing after it the game works out which spell the macro would cast. It has to be the first line." },
		{ cmd = "#", arg = "", label = "Note", icon = PAPER, tip = "A line the game ignores. Its characters still count towards the 255." },
		{ cmd = "raw", arg = "", label = "Free text", icon = PAPER, tip = "Any line at all, written out exactly as you type it. For commands another addon has added." },
	} },
	{ heading = "Targeting", items = {
		{ cmd = "target", arg = "", icon = SWORD, tip = "Target a unit or a name." },
		{ cmd = "targetenemy", arg = "", cond = "noexists", icon = SWORD, tip = "Target the nearest enemy. With [noexists] it only reaches for one when you have nothing." },
		{ cmd = "targetlasttarget", arg = "", icon = SWORD },
		{ cmd = "cleartarget", arg = "", icon = SWORD },
		{ cmd = "focus", arg = "", cond = "@mouseover,exists", icon = SWORD, tip = "Sets your focus, which other macros can then aim at with @focus." },
		{ cmd = "clearfocus", arg = "", icon = SWORD },
		{ cmd = "assist", arg = "", icon = SWORD },
	} },
	{ heading = "In a fight", items = {
		{ cmd = "startattack", arg = "", icon = SWORD, tip = "Starts your auto attack if it is not already going. Put it above the cast." },
		{ cmd = "stopattack", arg = "", icon = SWORD },
		{ cmd = "stopcasting", arg = "", icon = RAGE, tip = "Drops whatever you are casting so the next line can start at once." },
		{ cmd = "stopmacro", arg = "", cond = "channeling", icon = RAGE, tip = "Stops reading the macro here, so the lines below are skipped." },
		{ cmd = "cancelaura", arg = "", icon = RAGE, tip = "Clicks a buff off you, by name." },
		{ cmd = "cancelform", arg = "", icon = RAGE },
		{ cmd = "dismount", arg = "", icon = RAGE },
	} },
	{ heading = "Pet", items = {
		{ cmd = "petattack", arg = "", icon = PET },
		{ cmd = "petfollow", arg = "", icon = PET },
		{ cmd = "petstay", arg = "", icon = PET },
		{ cmd = "petpassive", arg = "", icon = PET },
		{ cmd = "petdefensive", arg = "", icon = PET },
	} },
	{ heading = "Gear", items = {
		{ cmd = "equip", arg = "", icon = SWORD },
		{ cmd = "equipslot", arg = "16 ", icon = SWORD, tip = "16 is your main hand, 17 the off hand, 18 the ranged slot." },
		{ cmd = "equipset", arg = "", icon = SWORD },
	} },
	{ heading = "Talking", items = {
		{ cmd = "say", arg = "", icon = FOOD },
		{ cmd = "yell", arg = "", icon = FOOD },
		{ cmd = "party", arg = "", icon = FOOD },
		{ cmd = "raid", arg = "", icon = FOOD },
		{ cmd = "raidwarning", arg = "", icon = FOOD },
		{ cmd = "emote", arg = "", icon = FOOD },
	} },
	{ heading = "Script", items = {
		{ cmd = "run", arg = "", icon = BOOK, tip = "A line of Lua. Checked for syntax as you type, without being run. It cannot do anything the game protects during combat." },
		{ cmd = "click", arg = "", icon = BOOK, tip = "Clicks a button by its frame name. How macros reach other addons' buttons." },
		{ cmd = "changeactionbar", arg = "", icon = BOOK },
	} },
}

-- ------------------------------------------------------------------
-- Templates
-- ------------------------------------------------------------------
local function Chapter(token, list) T[token] = list end

T.CHAPTERS = { "GENERAL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

Chapter("GENERAL", {
	{ name = "Heal whatever you point at", why = "Heals your mouseover if it is friendly and alive, otherwise your target, otherwise you. The one macro most healers build first.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash Heal" },
	{ name = "Hit whatever you point at", why = "Casts at your mouseover when it is an enemy, otherwise at your target, so you never have to change target.",
	  text = "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Shadow Bolt" },
	{ name = "Two spells on one key", why = "The plain spell on its own, the other one while you hold shift. Swap the modifier for ctrl or alt, or add more clauses.",
	  text = "#showtooltip\n/cast [mod:shift] Fire Blast; Frostbolt" },
	{ name = "Both trinkets", why = "13 is the top trinket slot and 14 the bottom one, so this works on every character without naming anything.",
	  text = "#showtooltip 13\n/use 13\n/use 14" },
	{ name = "Healthstone, potion on shift", why = "One key for the panic button, with the potion behind shift so you cannot waste it by accident.",
	  text = "#showtooltip [mod:shift] Healing Potion; Healthstone\n/use [mod:shift] Healing Potion; Healthstone" },
	{ name = "Bandage yourself", why = "Drops whatever you are casting first, then bandages you rather than your target.",
	  text = "#showtooltip\n/stopcasting\n/use [@player] Heavy Bandage" },
	{ name = "Swing while you cast", why = "Starts your auto attack if it is not going yet, then casts. Melee want this on nearly everything.",
	  text = "#showtooltip\n/startattack\n/cast Sinister Strike" },
	{ name = "Set focus, then aim at it", why = "Points your focus at whatever the mouse is over, and casts at the focus if you have one. Two presses, one key.",
	  text = "#showtooltip\n/focus [@mouseover,exists]\n/cast [@focus,harm,nodead][harm,nodead] Polymorph" },
	{ name = "Find something to hit", why = "Only reaches for a new target when you have none or yours is dead, so it never pulls you off the kill target.",
	  text = "#showtooltip\n/targetenemy [noexists][dead]\n/cast Shoot" },
	{ name = "Click a buff off", why = "Removes a buff by name. The usual ones are the ones that stop you moving or drinking.",
	  text = "#showtooltip\n/cancelaura Blessing of Protection" },
	{ name = "Say something as you cast", why = "The chat line is not read for conditions, so it always goes out. Keep it for taunts and warnings, not for spam.",
	  text = "#showtooltip\n/cast Taunt\n/say Taunting %t!" },
	{ name = "Skull on your target", why = "A script line, checked for syntax before you save it. Marks need you to be leader or an assistant.",
	  text = "#showtooltip\n/run SetRaidTarget(\"target\", 8)" },
	{ name = "Enemy nameplates on or off", why = "Shows what a script block is for: one line of Lua, no spell involved, and it works out of combat where scripts are allowed to.",
	  text = "/run local n=\"nameplateShowEnemies\" local g=C_CVar and C_CVar.GetCVar or GetCVar local s=C_CVar and C_CVar.SetCVar or SetCVar s(n,g(n)==\"1\" and 0 or 1)" },
})

Chapter("WARRIOR", {
	{ name = "Charge from any stance", why = "One press puts you in Battle Stance, the next charges. Stances are form: to a macro, in the order the game lists them.",
	  text = "#showtooltip Charge\n/cast [nostance:1] Battle Stance\n/cast [stance:1] Charge" },
	{ name = "Battle or Commanding Shout", why = "The shout you use most on the key, the raid one behind shift.",
	  text = "#showtooltip\n/cast [mod:shift] Commanding Shout; Battle Shout" },
	{ name = "Sunder and keep swinging", why = "Starts the auto attack first so a missed swing never costs you rage.",
	  text = "#showtooltip\n/startattack\n/cast Sunder Armor" },
	{ name = "Defensive stance, then Shield Wall", why = "Presses into Defensive Stance when you are not in it, and uses the button properly once you are.",
	  text = "#showtooltip Shield Wall\n/cast [nostance:2] Defensive Stance\n/cast [stance:2] Shield Wall" },
	{ name = "Intervene whoever you point at", why = "Runs to the friendly unit under the mouse without changing your target.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead] Intervene" },
	{ name = "Berserker Stance, then Whirlwind", why = "Same shape as the charge macro: get into the stance, then use the ability that needs it.",
	  text = "#showtooltip Whirlwind\n/cast [nostance:3] Berserker Stance\n/cast [stance:3] Whirlwind" },
})

Chapter("PALADIN", {
	{ name = "Cleanse whoever you point at", why = "Mouseover, then target, then you. Works while you are staring at a boss.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Cleanse" },
	{ name = "Blessing, protection on shift", why = "Your everyday blessing on the key, the emergency one behind a modifier so it cannot go out by mistake.",
	  text = "#showtooltip\n/cast [mod:shift,@mouseover,help][mod:shift] Blessing of Protection; Blessing of Might" },
	{ name = "Seal then judge", why = "A sequence: the first press seals, the second judges, and it goes back to the start when you change target.",
	  text = "#showtooltip\n/castsequence reset=target Seal of the Crusader, Judgement" },
	{ name = "Lay on Hands, pointed", why = "The one spell you cannot afford to send to the wrong unit, so the mouseover comes first and you are the fallback.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Lay on Hands" },
	{ name = "Bubble yourself, protect a friend", why = "Shift for your own shield, otherwise the friendly unit under the mouse.",
	  text = "#showtooltip\n/cast [mod:shift,@player] Divine Shield; [@mouseover,help,nodead] Blessing of Protection" },
	{ name = "Stun and swing", why = "Auto attack first, stun second.",
	  text = "#showtooltip\n/startattack\n/cast Hammer of Justice" },
})

Chapter("HUNTER", {
	{ name = "Send the pet in and start shooting", why = "One key to open: the pet goes, you start your auto shot.",
	  text = "#showtooltip\n/petattack [@target,harm]\n/startattack [@target,harm]" },
	{ name = "Trap without losing your swing", why = "Stops the attack so you do not break the trap the moment it lands, and sits the pet down.",
	  text = "#showtooltip Freezing Trap\n/stopattack\n/petpassive\n/cast Freezing Trap" },
	{ name = "Feign death properly", why = "A feign with the pet still attacking does not drop you out of the fight, so the pet is called off in the same press.",
	  text = "#showtooltip Feign Death\n/petpassive\n/petfollow\n/cast Feign Death" },
	{ name = "Mend pet without targeting it", why = "Aims at the pet whatever you have targeted, and does nothing when there is no pet.",
	  text = "#showtooltip\n/cast [@pet,exists,nodead] Mend Pet" },
	{ name = "Misdirect to the pet", why = "The usual solo version: no target change, no fumbling.",
	  text = "#showtooltip\n/cast [@pet,exists] Misdirection" },
	{ name = "Pet control on one key", why = "Modifiers instead of three buttons: shift sends it in, ctrl calls it back, otherwise it sits.",
	  text = "#showtooltip\n/petattack [mod:shift]\n/petfollow [mod:ctrl]\n/petstay [nomod]" },
})

Chapter("ROGUE", {
	{ name = "Opener from stealth", why = "Ambush while you are stealthed, your normal builder when you are not. The same shape covers every stealth pair.",
	  text = "#showtooltip\n/cast [stealth] Ambush; Sinister Strike" },
	{ name = "Kick, Blind on shift", why = "Two interrupts on one key, with the one you want less often behind a modifier.",
	  text = "#showtooltip\n/cast [mod:shift] Blind; Kick" },
	{ name = "Cheap Shot or Kidney Shot", why = "The stun you can actually use, depending on whether you are stealthed.",
	  text = "#showtooltip\n/cast [stealth] Cheap Shot; Kidney Shot" },
	{ name = "Poison the main hand", why = "Uses the poison and then the weapon slot, which is what the game expects: 16 is the main hand, 17 the off hand.",
	  text = "#showtooltip Instant Poison\n/use Instant Poison\n/use 16" },
	{ name = "Vanish, sprint otherwise", why = "Holding any modifier at all is what [mod] means, which is handy when you do not care which one.",
	  text = "#showtooltip\n/cast [mod] Vanish; Sprint" },
	{ name = "Pick pocket while you are at it", why = "Stealthed, it lifts a pocket; out of stealth it just attacks.",
	  text = "#showtooltip\n/cast [stealth] Pick Pocket; Sinister Strike" },
})

Chapter("PRIEST", {
	{ name = "Shield whoever you point at", why = "Mouseover, then shift for yourself, then your target, then you. The full ladder, in one line.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][mod:shift,@player][help,nodead][@player] Power Word: Shield" },
	{ name = "Get into Shadowform, then cast", why = "Shadowform counts as form 1. Out of it the press puts you in, in it the press casts.",
	  text = "#showtooltip Mind Flay\n/cast [noform:1] Shadowform\n/cast [form:1] Mind Flay" },
	{ name = "Dispel a mouseover", why = "Cleansing without changing target, which is the whole point of mouseover macros.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Dispel Magic" },
	{ name = "Resurrect the dead one under the mouse", why = "Only fires on a friendly, dead unit, so it cannot go off on a living raid member by accident.",
	  text = "#showtooltip\n/cast [@mouseover,help,dead][help,dead] Resurrection" },
	{ name = "Fade on a modifier", why = "Keeps a rarely used panic button on a key you already press.",
	  text = "#showtooltip\n/cast [mod:shift] Fade; Renew" },
	{ name = "Psychic Scream, then heal yourself", why = "Two lines, one of them a cast: the scream costs no cast time, so both can happen on one press.",
	  text = "#showtooltip\n/cast Psychic Scream\n/cast [@player] Renew" },
})

Chapter("SHAMAN", {
	{ name = "Totems in order", why = "One key drops the whole set, one totem per press, starting over when you leave combat.",
	  text = "#showtooltip\n/castsequence reset=combat Strength of Earth Totem, Searing Totem, Mana Spring Totem" },
	{ name = "Earth Shield whoever you point at", why = "The tank under your mouse, then your target, then you.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Earth Shield" },
	{ name = "All three shocks on one key", why = "Three clauses with different modifiers, read left to right. This is the pattern for any three-way key.",
	  text = "#showtooltip\n/cast [mod:shift] Flame Shock; [mod:ctrl] Frost Shock; Earth Shock" },
	{ name = "Purge a mouseover", why = "Dispelling the enemy the mouse is on without leaving your kill target.",
	  text = "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Purge" },
	{ name = "Ghost Wolf in and out", why = "The cancel only fires when you are already in the form, so one key does both ways.",
	  text = "#showtooltip Ghost Wolf\n/cancelform [form:1]\n/cast [noform:1] Ghost Wolf" },
	{ name = "Heal yourself or the target", why = "Shift aims at you; otherwise it heals whatever friendly thing you have.",
	  text = "#showtooltip\n/cast [mod:shift,@player][help,nodead][@player] Healing Wave" },
})

Chapter("MAGE", {
	{ name = "Blink, Ice Block on shift", why = "Both escapes on one key, with the one that ends your damage behind a modifier.",
	  text = "#showtooltip\n/cast [mod:shift] Ice Block; Blink" },
	{ name = "Sheep a mouseover", why = "Polymorph the thing under the mouse and keep hitting your target. The single most useful mage macro.",
	  text = "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Polymorph" },
	{ name = "Counterspell a mouseover", why = "Same shape as the sheep, for the interrupt that has to land on the healer and not the boss.",
	  text = "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Counterspell" },
	{ name = "Stop casting, then Evocate", why = "Without the stop, the press is eaten by the spell you are already casting.",
	  text = "#showtooltip Evocation\n/stopcasting\n/cast Evocation" },
	{ name = "Wards on one key", why = "Fire ward on shift, frost otherwise, so one slot covers both schools.",
	  text = "#showtooltip\n/cast [mod:shift] Fire Ward; Frost Ward" },
	{ name = "Make food and water", why = "A sequence for the two conjures, back to the start when you leave combat.",
	  text = "#showtooltip\n/castsequence reset=combat Conjure Water, Conjure Food" },
})

Chapter("WARLOCK", {
	{ name = "Summon, or sacrifice what you have", why = "Summons a Voidwalker when you have no pet, and eats the one you have when you do.",
	  text = "#showtooltip Summon Voidwalker\n/cast [nopet] Summon Voidwalker; Sacrifice" },
	{ name = "Life Tap on a modifier", why = "Tapping on a key you already hit means never hunting for the button at 10% mana.",
	  text = "#showtooltip\n/cast [mod:shift] Life Tap; Shadow Bolt" },
	{ name = "Fear a mouseover", why = "Crowd control on the thing under the mouse, target untouched.",
	  text = "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Fear" },
	{ name = "Soulstone a friend or yourself", why = "The friendly unit under the mouse, otherwise you. Items take conditions the same way spells do.",
	  text = "#showtooltip\n/use [@mouseover,help,nodead][@player] Soulstone" },
	{ name = "Healthstone", why = "Named rather than numbered, so it keeps working when the rank changes.",
	  text = "#showtooltip Healthstone\n/use Healthstone" },
	{ name = "Banish, Enslave on shift", why = "Two spells that only ever go on a demon, sharing one key.",
	  text = "#showtooltip\n/cast [mod:shift] Enslave Demon; Banish" },
})

Chapter("DRUID", {
	{ name = "Cat, Bear on shift", why = "Both forms on one key. Pressing it in the form you are in leaves it, because the game treats the form spell as a toggle.",
	  text = "#showtooltip\n/cast [mod:shift] Dire Bear Form; Cat Form" },
	{ name = "Heal out of form", why = "The first press drops your form, the second heals: a macro cannot do both in one press, and any that claims to is lying.",
	  text = "#showtooltip Healing Touch\n/cancelform [form:1/2/3]\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Touch" },
	{ name = "Innervate whoever you point at", why = "Mouseover first, then your target, then you.",
	  text = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead][@player] Innervate" },
	{ name = "Powershift into cat", why = "Cancels the form and casts it again, which is the shift rogues of the druid world live on.",
	  text = "#showtooltip Cat Form\n/cancelform [form:3]\n/cast [noform:3] Cat Form" },
	{ name = "Travel or swim", why = "Aquatic in the water, travel on land, one key.",
	  text = "#showtooltip\n/cast [swimming] Aquatic Form; Travel Form" },
	{ name = "Rebirth the dead one under the mouse", why = "Friendly and dead, both checked, so it cannot be spent on someone standing up.",
	  text = "#showtooltip\n/cast [@mouseover,help,dead][help,dead] Rebirth" },
})

-- The chapters, along the top. The parts come first because that is where a macro starts, and the
-- nine classes are one chapter with a row of class icons in it rather than nine tabs, which is what
-- lets the tabs sit in a single row and the page underneath be as wide as it is.
function T.Order()
	return { "BLOCKS", "MINE", "GENERAL", "CLASSES" }
end

-- Your own class first, then the rest, for the row of icons inside the Classes chapter.
function T.ClassOrder()
	local mine = select(2, UnitClass("player"))
	local order = {}
	if mine and T[mine] then order[#order + 1] = mine end
	for _, token in ipairs(T.CHAPTERS) do
		if token ~= "GENERAL" and token ~= mine then order[#order + 1] = token end
	end
	return order
end

function T.Label(token)
	if type(token) ~= "string" or token == "" then return "?" end
	if token == "MINE" then return "My macros" end
	if token == "BLOCKS" then return "Parts" end
	if token == "GENERAL" then return "General" end
	if token == "CLASSES" then return "Classes" end
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end

-- The icon a template wears: the first spell or item it names.
function T.Icon(entry)
	if entry.icon then return ns.SafeIcon(entry.icon) end
	local blocks = ns.Grammar.Parse(entry.text or "")
	for _, b in ipairs(blocks) do
		local subject, kind = ns.Grammar.BlockSubject(b)
		if subject then
			local icon = ns.IconFor(subject, kind)
			if icon then return icon end
		end
	end
	return ns.QUESTION
end

-- Every template that mentions the search words, across every chapter.
function T.Search(query)
	query = string.lower(ns.Grammar.Trim(query or ""))
	if query == "" then return nil end
	local out = {}
	for _, token in ipairs(T.CHAPTERS) do
		for _, entry in ipairs(T[token] or {}) do
			local hay = string.lower((entry.name or "") .. " " .. (entry.why or "") .. " " .. (entry.text or "") .. " " .. T.Label(token))
			if hay:find(query, 1, true) then
				out[#out + 1] = { entry = entry, token = token }
			end
		end
	end
	return out
end
