# Changelog

## 1.9.2

- Backspacing a step box empty took the step away with it, keyboard and all. The boxes were drawn from the macro text, where an empty step is nothing at all, so the last letter deleted the row. The boxes keep their own shape while one of them has the keyboard: an empty box stays put and goes on taking letters, whether it is the one just added or one in the middle of the list. Only what is actually written reaches the macro, and when the keyboard leaves the empty ones fall away.

## 1.9.1
- The names on offer are a dropdown, so they are drawn over what is under them rather than tangled with it: opaque, bordered, above everything else in the panel, and the width of the box they belong to. Under a step box they had been sharing their place with the Add a step button.

## 1.9.0
- Cast in order and Cast one at random have an editor built for a list: a box per step, numbered, with arrows to move a step up or down and a cross to take it out, and a button to add another. Names finish themselves in every one of those boxes the way they do everywhere else.
- For a sequence the reset is asked for in words rather than written into the same string: tick when you leave combat, when you change target, or give it a number of seconds. Anything else a reset can say is kept as it was.

## 1.8.5
- "As things stand, this line does nothing" read as a verdict on the macro when it is only what the line would do if it were pressed that instant: a mouseover macro says it whenever the mouse is not over anything, which it is not while you are working in this window. It says "If you pressed it this instant" now, and nothing found says why.
- The aimed at block ran off the side of the window: its row was laid out at a width picked in advance, wider than the panel it sits in, which put the box for a name past the edge. The row is the width of the panel now, the units are four across in the room there is, and the name has a line of its own under them. The state block was measured the same way and given a little back.

## 1.8.4
- Finishing a name found Rain of Fire but not Shadow Bolt, Life Tap but not Fear. This client gives up nothing from its spellbook, so the names were coming from your action bars, and a bar slot holding a macro says only that it holds a macro: every spell you keep inside one was invisible. Your own macros are read now, with the addon's own parser, so every spell named in one is a name you can finish. Your bars are read beside them, and a macro changing reads them again.
- When the spellbook answers with a count of nothing but still knows the entries themselves, they are asked for one at a time until they run out.

## 1.8.3
- Both lists could read zero for a whole session. They were read once at login, which is before this client has the spellbook or the bags ready, and an empty answer was kept: nothing clears it but an event saying a spell was learned or a bag changed, and neither of those fires just because they arrived. Nothing found is no longer kept, so it is asked again next time, and the first read is when the world loads rather than at login.

## 1.8.2
- The icon beside the name opens a picker: every icon a macro may wear, sixty at a time, your own spells and items at the front and the game's whole list behind them. The ones with names can be searched. It had only ever toggled between working the icon out and the plain question mark, which is not what clicking an icon looks like it should do. Right-click still goes back to working it out.
- Finishing a spell name found nothing while items worked. Reading the spellbook asked for the banks by name through an Enum this client may not have, and skipped the whole thing when it was missing. They are asked for by number as well now. Failing everything, the spells on your action bars stand in, which are the ones you write macros about anyway.
- "/macrobench debug spells" says which of the spellbook calls this client has, what each one answered, and how many spells came back, so an empty list explains itself.

## 1.8.1
- The tutorials offer themselves the first time the bench is opened with nothing on it and nothing kept, which is what a fresh install looks like. Once only, a moment behind the window so they arrive on top of it. The ? beside the close button, the Tutorial button and a right-click on the minimap button bring them back after that, and "/macrobench tutorials again" makes them offer themselves once more.

## 1.8.0
- The first packaged release. Everything 1.0 through 1.7 built: a macro as a chain of blocks with its text beside it, both live and either one editable; a control for every condition the game has; three checking passes, none of which run the macro; names finished as you type them from your own spellbook and bags; sixty-seven templates and five tutorials; and a library with no limit beside the game's own macro slots.
- Spelled the way this client spells: it says Color, Center and Gray on its own frames, so the addon beside it says the same. Gray, color, center, recognized, localized, channeling. Identifiers are left alone.
- Listing copy for an addon site kept with the addon, in DESCRIPTION.md, so the words on the page and the words in the window cannot drift apart.

## 1.7.5
- The window would not open: "stack overflow". Putting every single-line string through one helper in 1.7.4 rewrote the call inside the helper as well, so it called itself for ever. It sets the line count itself again.

## 1.7.4
- Finishing a name offered nothing. Reading the spellbook leaned on one field of one call, and on a client that keeps the name somewhere else the list came back empty without saying so. Every way the name and the icon can be had is tried for every entry now: the info table, the id in it looked up, and the name call of its own. /macrobench debug says how many spells and items it found, so an empty list can be seen rather than guessed at, and both lists are read at login.
- The names being offered had been drawn on top of the line that says what the game made of what you typed. Each has its own band under the box now: what it matched, anything to say about it, then the names.

## 1.7.3
- A macro with a long body drew that body below its own row, over the next macro. Clipping a line of text to one line is not enough on its own: a string anchored on both sides wraps inside its own region, the region stays as tall as the wrapped text, and a font string sits in the middle of its region unless it is told otherwise, so the one line that survived dropped to the middle of three. Every single-line string in the window now goes through one helper that clips it, holds it to the top of its region and stops it wrapping at all.

## 1.7.2
- A macro in the list did not read as one thing. What the slot is, "slot 1" or "yours", sat at the bottom right of its row, level with the next macro name down, so it looked like that one's. It is on the name's line now, the icon lines up with the name rather than floating in the middle of the row, each row has a rule of its own along the bottom instead of leaving a gap to do that work, and rows are six pixels taller.

## 1.7.1
- The minimap button sat inside the ring the others are on. Its reach was a fixed 80 from the center, which is right only for a minimap of the size the game ships; measured from the minimap own width plus six, as Aura Ledger measures it, the two now sit on one ring whatever size the minimap has been made. The icon moved to where the tracking border window is rather than the middle of the button, and it has the same dark backing behind it that the others have.
- Dragging it works on a client without math.atan2, and the angle is kept between 0 and 360.

## 1.7.0

- A part that cannot be used yet is dimmed. Before anything is on the bench that is every condition block, because a condition needs a line to belong to; once there is a line, any block the line does not read conditions on stays dim too. Clicking a dim one says why rather than doing nothing, and its tooltip says it before you click.
- The part you are working on has more room: the panel is 270 tall rather than 212, which is most of the state block without scrolling.

## 1.6.2

- Not a dash of any kind left in the addon: the window, the tutorials, the tooltips, this file and the README. Each one was rewritten to what the sentence wanted, a colon or brackets or a full stop, rather than swapped for a hyphen. The three-way buttons say "-" for a condition that is not asked.

## 1.6.1

- The left panel opens on Parts every time. It had been remembering the last chapter you looked at, so looking at My macros once meant opening there ever after.

## 1.6.0

- Save to a macro slot asks first when something is already there. Updating the macro the bench came from asks "Update Bolt in macro slot 2?", and a name that another macro already has asks "Macro slot 1 already holds Invite. Saving as Invite overwrites it." Either way it shows the first line of what is about to go, so you can see what you would be losing. A slot that is free is written without a word.
- /macrobench confirm stops it asking, and starts it again.

## 1.5.2

- Paste a macro and Macro text were drawn on top of each other, so the header read "PasVteamnaacrto". The new button was hung off the same edge as the one already there; they hang off each other now, right to left: Tutorial, Paste a macro, Macro text, Check.

## 1.5.1

- Registering LEARNED_SPELL_IN_TAB threw: this client has never heard of it, and an unknown event name is an error rather than a quiet no. The name for a spell being learned moves about between clients, so both are asked for, each on its own, and /macrobench debug reports which ones this client took.
- A "Paste a macro" button on the macro header opens the text with everything in it selected, ready for ctrl+V. Pasting already built the chain (anything typed or pasted into that box is read straight into blocks), but nothing said so and the window had to be found first.

## 1.5.0

- A spell or item box finishes what you are typing. Two letters in, the names you actually have start appearing under the box (your spellbook for a cast, your bags and what you are wearing for a use, both for a tooltip line), and clicking one writes the whole name. Tab takes the first. Names that begin with what you typed come first, then names that merely contain it, so "heal" finds Flash Heal and "word" finds Power Word: Shield.
- In a sequence or a random list only the name being typed is searched, and only that one is replaced: "reset=combat Renew, flash" completes to "reset=combat Renew, Flash Heal".
- The lists are read once and kept until the game says a spell was learned or a bag changed.

## 1.4.4

- The ? is built the way Aura Ledger builds its own, which comes out visible on this client: a plain button wearing the client red button art, taking its strata and its level from the close button beside it rather than from the window. Measuring against the window was the mistake: the close button is the thing on that border that is certainly drawn, so one above it is certainly drawn too. It is taken again on every show and every raise, and /macrobench debug says which art it found and where it ended up.

## 1.4.3

- The ? was there to be hovered but not to be seen, and so was the check line along the bottom whenever the window had been clicked. Both sit on the window border rather than inside it, and the window re-levels itself every time it is shown or brought to the front, which left them stranded under the border art. They are lifted again on every show and every click now, from one place that knows about all of them.
- The book was drawn on the first open only for the My macros chapter, so everything else opened to an empty page with the class icons showing over it, the tab saying Parts and the page said nothing. It is drawn as the window is built.
- The class icons start hidden, and a chapter the addon does not have can no longer throw on its way to being named.

## 1.4.2

- The ? in the title bar was not there to be clicked. The window border is a frame of its own on this client and draws above anything parented to the window at the usual level, so a button tucked into the corner went behind the corner art. It sits above the border now.
- The check line moved to the gray band the window draws along its very bottom, where it has the whole width and no longer reads "nothing on t…" in the gap between the tick box and the buttons. Clicking it still opens the whole list, and hovering it still lists the first few findings.
- Two more ways to the same tutorials, since one that can be hidden is not enough: a Tutorial button on the macro header beside Macro text and Check, and a right-click on the minimap button.

## 1.4.1

- Left click, right click, middle click and the two side buttons are conditions of their own in the Modifier block, three-way like the rest. They were only reachable before through a box labelled "Mouse button" that wanted a number, which is no use unless you already knew [button:2] meant right click. A line now reads "pressed with right click" in the chain and in words.
- The block is called "pressed with" rather than "held down", since a click is not held.

## 1.4.0

- Tutorials, from the |cffffd100?|r beside the close button or /macrobench tutorial. Five of them: a mouseover spell, two spells on one key, a trinket and a cast together, a list cast one per press, and a line that only runs sometimes. Each builds a real macro on the bench with your own spells, one step at a time.
- They watch rather than tell. A step says what to do, a gold frame pulses round the thing it is talking about (the block in the parts list, the box in the panel, the button in the footer), and the moment the bench says the step is done it moves on by itself. Every step reads the macro text, so it passes the same way whether you dragged a block, clicked a button or typed it. Back and Skip are there, starting a tutorial halfway through a macro skips what is already true, and you can stop and carry on whenever.
- The window comes to the front when clicked, as do the text, check and tutorial windows, so another addon in the same layer can no longer interleave with it: its window over our panels, our panels over its window.

## 1.3.0

- The macro text and the check have windows of their own, opened from the buttons on the macro header and movable wherever you like them. The room they used to take goes to the chain, which is now half the window, and to the part panel under it.
- The footer says how the check stands at all times, nothing wrong or what it found, and hovering it lists the first few findings. Clicking it opens the whole list.
- The chapter tabs are back along the top, so the page below them is the full width of its column. The nine classes are one Classes chapter with a row of class icons in it, your own first, which is what lets the tabs fit in one row.
- Parts is the first chapter and the one it opens on, since that is where a macro starts.
- "Or these instead" is a block in the parts list like the others, so a second set of brackets can be dragged onto a line rather than only found in the + panel. An empty set of brackets asks which kind of condition it should hold instead of showing a raw box, and a condition added while one is open lands in that set rather than the first.

## 1.2.1

- A condition block in the parts list said "shift" or "on mouseover" in gold, which read as the only thing that block could ever say. It shows the range it covers instead, in gray, as shift, ctrl, alt…, and its tooltip lists what it can ask and says it arrives set to one of them.

## 1.2.0

- The parts chapter shows the parts as the blocks they will become: the same frame, the same colors, the same two lines of words as on the bench, flowing across the page and wrapping rather than sitting in a list of rows. One function paints a block now, and the chain and the chapter both go through it, so a block in the list cannot drift from the block you drop.
- The chain has its connectors back, and in words: an action is followed by "when" before its first condition, "and" between two conditions of the same set, "then" before what it casts, and a chevron where nothing else fits. They sit above the line plate rather than behind it.

## 1.1.3

- Typing into a box in the part panel let go of the keyboard after every letter. Every keystroke redraws the panel, and the redraw hid all the editors before showing the right one again, and hiding a frame takes the keyboard out of any box inside it. The editor that is already up is left alone now, and the panel only scrolls back to the top when a different part is opened, so it cannot jump about under a box being typed into.
- The line under a spell box says what it needs to in one line.

## 1.1.2

- The tick box beside a condition that takes an answer said "not" but read as "on", so a Pet row with Voidwalker in it looked switched off. It is a button now that says which of the three it is doing (not asked, is, is not), and typing in the box turns the row on by itself. Emptying the box takes the condition off, except where the bare condition means something on its own, as [pet] does.
- The spellbook button loads the spellbook and opens it on one click rather than warning first and wanting a second. Dragging a spell onto the bench is not a protected action, so the taint that loading it causes costs nothing here, and it says once that a /reload clears it.

## 1.1.1

- The window would not load at all: building it had grown into one function that reached more than sixty locals of the file around it, which is a hard limit in the game Lua and stops the file compiling. The window is built in a function per band now (the frame, the templates panel, the chain, the part panel, the text and check, the footer), and none of them comes near the limit. Nothing about the window changed.

## 1.1.0

- Every condition the game has now has a control. The blocks that ask only yes or no are three-way buttons (not asked, must be true, must be false, and right-click goes round the other way), and the ones that take an answer have a box beside them: pet (Succubus, Voidwalker, or empty with "not" ticked, which is [nopet]), form or stance, group, channeling, equipped, action bar page, bonus bar, mouse button, spell known.
- Under the controls, every condition block carries the whole of itself written out as the game reads it. A condition with no control of its own, the handful that only exist in later expansions, is shown there and can be edited, rather than being invisible.
- The aimed-at block gives the units their own row, with a box for anybody by name, and asks whether the unit is an enemy, friendly, there at all, dead, in your party, in your raid, or in a vehicle.
- The panel scrolls, because the state block holds more than fits in it.
- A spell or item typed into an argument is matched against the game: its icon, its name and its id sit under the box, and hovering them shows the game own tooltip for it. A name that matches nothing on this character says so, which catches a misspelling before a fight does.
- The spellbook button reports what happened in the panel rather than only in chat, and a second click loads the spellbook addon anyway for anyone who would rather have it than avoid the taint.
- form and stance are read as one condition, and bar as actionbar.

## 1.0.3

- The part panel put its editor where the hint line was, so the two drew on top of each other; the editors sit below both now, with a rule between the header and them.

## 1.0.2

- The spell and item boxes have the window you drag the answer out of beside them: "Open the spellbook" on a spell, "Open your bags" on an item. Neither loads a Blizzard addon to do it, because loading one from addon code taints it and the client then refuses its own protected calls; an unloaded spellbook says to press P once instead.

## 1.0.1

- The part panel's header no longer runs into the editor below it: the hint sat eight pixels inside the first edit box, which clipped it.
- Every line has a delete under its number, so a whole line goes in one click without picking a block first.
- The left panel is called Templates and parts rather than the book, and its middle chapter is Parts.

## 1.0.0

- First version. One line of a macro is one chain of blocks, read left to right (the action, then what has to be held down, then what it is aimed at, then what it casts), and under the chain, always visible, the macro text they add up to. Both are live: a block changed rewrites the text, text typed is read back into blocks. The text is what is real and the blocks are a view of it, so anything the builder does not understand (a command another addon added, a line of Lua, something pasted in) survives being loaded, shown and saved without a character being changed.
- Every part is its own block. Drag the action to move the whole line, drag a condition block onto another line to move it there, drag one off the chain to take it off, right-click any of them to remove it. Clicking one opens it in the panel underneath: the action becomes a list of commands, a target filter becomes units and tick boxes, an argument becomes a text box.
- One set of brackets holds several kinds of question at once, so conditions are sorted into blocks (held down, aimed at, only when) and put back together as one condition. A condition that has only been read is never rewritten, which is what keeps text you typed yourself exactly as you typed it.
- Blocks are dragged in from the left, and so are spells straight out of the spellbook and items out of your bags, which arrive as `/cast` and `/use` lines already filled in. A macro dragged out of the game's own macro window is taken apart into blocks.
- The panel says what the line it is showing resolves to as things stand, answered by the client's own condition parser rather than guessed at, so holding shift changes what it says.
- The check reports, worst first: commands the game does not have, unknown conditions and units with the nearest real one suggested, unclosed brackets, clauses nothing can reach, two casts where one press can only fire the first, malformed `reset=`, `#showtooltip` where the game will not read it, spells named by id, spells not in your spellbook, arguments on commands that read none, and the 255 character limit with the overrun. Scripts are compiled with `loadstring` for a real syntax error without being run, and calls the game refuses from a script in combat are flagged.
- Templates: a General chapter and one per class, your own class first, each with a line on what it is for. All of them pass the check with nothing to report.
- Two places to keep a macro: the library here, which has no limit, and the game's macro slots, which have both a limit and a rule against being written to during a fight: those writes are queued and go in when the fight ends.
- `/macrobench scan` runs the check over every macro you already have and lists the ones worth a look.
