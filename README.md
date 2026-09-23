# Macro Bench

A macro builder for the WoW: Forever client (Interface 16001), built from Blizzard's own interface art.

Macro Bench builds a macro out of small blocks you drag about. One line of the macro is one chain, read left to right:

```
[Cast] › [held down: shift] › [aimed at: mouseover, an enemy, alive] › [Polymorph]
```

which is `/cast [mod:shift,@mouseover,harm,nodead] Polymorph`. Every part is its own block: drag it, drop it on another line, throw it away, or click it to open its own options underneath. Under the chain, always visible, is the macro text the chain adds up to. Both are live and both are editable — change a block and the text rewrites itself, type in the text and the chain is read back out of it. Neither one is a copy of the other; they are the same macro, seen twice.

`/macrobench` (or the minimap button) opens it.

## The way through

1. **New macro** at the bottom clears the bench.
2. Drag an **action** in from the left — Cast, Cast in order, Use item, Target — or drop a spell straight out of your spellbook, which arrives as a Cast block already filled in.
3. Drag a **Modifier**, **Target filter** or **My state** block onto that line to say when it runs.
4. **Click any part** to set it up in the panel underneath: the action becomes a list of commands, a target filter becomes units and tick boxes, an argument becomes a text box.
5. Add more lines the same way, and drag them by their action block to reorder.
6. **Name it** at the bottom, then **Save to a macro slot** (a real macro you can put on a bar) or **Keep here** (this addon's own library, which has no limit).

## Templates and parts

The left panel is laid out like the spellbook and borrows its tab art when the client provides it. The chapters are tabs down the left edge, as the spellbook's are, so the page itself stays narrow.

- **My macros** is everything you have kept here, followed by every macro in the game's own macro slots. Click one to put it on the bench. The red X forgets a draft; your macro slots are never touched by it.
- **Parts** is what a macro is built from, drawn as the blocks they become and flowing across the page: the actions (casting, using, targeting, stopping, pet orders, gear, chat, script) and the condition blocks (Modifier, Target filter, My state, Otherwise). Drag one onto the chain, or click it to add it.
- **General** and then a chapter **per class**, your own class first, are whole macros to start from. Each says what it is for, and every one of them passes the check with nothing to report.
- **Search** looks through every chapter and every block at once, by name, by what the macro does, or by the text inside it.

## The bench

Each line is a chain of parts on its own rail, numbered down the left.

- **The line number** down the left has a delete under it: one click takes that whole line out.
- **The action block** is the line's command. Drag it to move the whole line; right-click it to take the line out. Click it and the panel below lists the commands.
- **A condition block** is one kind of question: *pressed with* (shift, ctrl, alt, and which mouse button pressed it), *aimed at* (mouseover, target, focus, you, and whether the unit is an enemy, friendly, alive), *only when* (in combat, stealthed, mounted, in a form). One set of brackets can hold all three; the bench shows them as separate blocks and puts them back together as one condition.
- **The argument block** is the spell, the item, the sequence, whatever the command takes. Typing in it offers what you actually have — the spellbook for a cast, your bags and gear for a use — and clicking one of those finishes the name for you; tab takes the first. Drop a spell or item from the game straight onto it, or use the button beside its box to open the spellbook or your bags.
- **or** means a second set of brackets on the same attempt (`[a][b] Spell`): if the first lot do not apply, the game tries the next.
- **otherwise** is the part after a semicolon: another attempt at the line, read only when nothing above applied.
- **+** at the end of a line adds any of those.
- Drag a condition block **onto another line** to move it there; drag it **off the chain** to take it off.
- The panel says what the selected line resolves to **right now**. Hold shift and watch it change.
- A **macro dragged out of the game's macro window** lands on the bench taken apart into blocks.

## Tutorials

The **?** beside the close button, the **Tutorial** button on the macro header, a right-click on the minimap button, or `/macrobench tutorial` — any of them opens five of them: a mouseover spell, two spells on one key, a trinket and a cast together, a list cast one per press, and a line that only runs sometimes. Each builds a real macro on the bench with your own spells. A step says what to do and a gold frame pulses round the thing it means; when the bench says the step is done it moves on by itself. Stop and carry on whenever you like — starting one halfway through a macro skips whatever is already true.

## The check

Three passes, none of which run the macro.

1. **The grammar and the slots.** Commands the game does not have, conditions that do not exist (with the closest real one suggested), brackets left open, a clause nothing can ever reach, two casts on one press where only the first can fire, `reset=` written wrongly, `#showtooltip` somewhere the game will not read it, a spell named by id instead of by name, spells that are not in your spellbook, and the 255 character wall with how much is over.
2. **Scripts.** A `/run` or `/script` body is handed to `loadstring`, which compiles it and gives back a real syntax error with a position, without executing a single line. The same pass flags calls the game refuses from a script during combat — `CastSpellByName`, `UseAction`, `TargetUnit` and the rest — which is the usual reason a script macro that "works" dies in a raid.
3. **Now.** Conditions are handed to `SecureCmdOptionParse`, the client's own condition parser, so what a line will do is answered by the game rather than guessed at.

Findings are listed worst first under the bench. Click one to jump to the line it is about; a line with something wrong is tinted and carries a mark you can hover.

`/macrobench scan` runs the same check over every macro you already have and lists the ones worth a look.

## Saving

- **Keep in the library** keeps the macro here, inside the addon. There is no limit: build and keep as many as you like, on any character.
- **Save to a macro slot** writes it into one of the game's own macro slots, which is what makes it a real macro. The game will not allow that during a fight, so it is queued and goes in the moment the fight ends.
- **Put on cursor** picks the saved macro up so you can drop it on an action bar. The drop has to be your own click: no addon may place something on a bar for you.
- The **icon** is taken from the first spell or item the macro names, the way the game does it. Click it for the plain question mark instead.
- **this character only** decides which set of slots it goes in: the account shares one set, each character has a few of its own. The counts are on the "In the game" heading under My macros.

## What a macro cannot do

None of this is Macro Bench being careful; it is the game.

- **255 characters**, and not one more. The counter under the text turns amber near it and red past it.
- **A fixed number of slots.** Hence the library, which has none.
- **One cast per press.** Two `/cast` lines with nothing to tell them apart will only ever fire the first, which is what the check says. Two `/use` lines are different and are left alone.
- **No automation.** A macro cannot decide for you, and a script cannot cast for you in combat. Anything built here could have been typed by hand into the game's own macro window; the point is that it is built quickly and checked before it costs you a pull.

## Commands

| Command | What it does |
| --- | --- |
| `/macrobench` | open or close the bench (`/mbench` and `/mb` work too) |
| `/macrobench tutorial` | open the tutorials |
| `/macrobench check` | check what is on the bench and print the findings |
| `/macrobench load <name>` | put one of your game macros on the bench |
| `/macrobench scan` | check every macro you have and list the broken ones |
| `/macrobench confirm` | ask, or stop asking, before a macro slot is replaced |
| `/macrobench minimap` | show or hide the minimap button |
| `/macrobench debug` | what this client allowed |
