-- The invariant the whole addon rests on: Compile(Parse(text)) == text, for every template and for
-- any script body, however many semicolons are in it.
local G = ns.Grammar
local bad = 0

local function trip(label, text)
	local ok, blocks = pcall(G.Parse, text)
	if not ok then print("PARSE FAILED  " .. label .. ": " .. tostring(blocks)); bad = bad + 1; return end
	local ok2, out = pcall(G.Compile, blocks)
	if not ok2 then print("COMPILE FAILED  " .. label .. ": " .. tostring(out)); bad = bad + 1; return end
	if out ~= text then
		bad = bad + 1
		print("NOT A ROUND TRIP  " .. label)
		print("   in:  " .. text)
		print("   out: " .. out)
	end
end

-- Every template already in the book.
local n = 0
for _, token in ipairs((ns.Templates and ns.Templates.CHAPTERS) or {}) do
	for _, entry in ipairs((ns.Templates and ns.Templates[token]) or {}) do
		n = n + 1
		trip(token .. ": " .. entry.name, entry.text)
	end
end
print("templates checked: " .. n)

-- The script bodies being added, semicolons and all.
local candidates = {
	{ "instance exit", '/run local i = InviteUnit or C_PartyInfo.InviteUnit i("aa");C_Timer.After(1,function() LeaveParty() end)' },
	{ "invite mouseover", '/run local u=UnitExists("mouseover") and "mouseover" or "target"; if UnitIsPlayer(u) then local n,r=UnitName(u); local p=(r and r~="") and n.."-"..r or n; C_PartyInfo.InviteUnit(p); C_PartyInfo.RequestInviteFromUnit(p); end' },
}
for _, c in ipairs(candidates) do trip(c[1], c[2]) end

-- And that a script block really is kept verbatim rather than split on its semicolons.
local blocks = G.Parse(candidates[2][2])
print("blocks from the mouseover macro: " .. #blocks .. ", kind=" .. tostring(blocks[1] and blocks[1].kind))
print(bad == 0 and "ALL CLEAN" or ("PROBLEMS: " .. bad))
