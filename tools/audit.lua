-- Every template: does it round trip, does it fit, and is each script body real Lua?
local G = ns.Grammar
local T = ns.Templates
local bad, n = 0, 0
local bodies = {}

for _, token in ipairs(T.CHAPTERS) do
	for _, e in ipairs(T[token] or {}) do
		n = n + 1
		local blocks = G.Parse(e.text)
		local out = G.Compile(blocks)
		if out ~= e.text then bad = bad + 1; print("NOT A ROUND TRIP  " .. e.name) end
		if #e.text > 255 then bad = bad + 1; print("TOO LONG " .. #e.text .. "  " .. e.name) end
		if not e.why or e.why == "" then bad = bad + 1; print("NO why  " .. e.name) end
		for _, b in ipairs(blocks) do
			if b.kind == "script" then bodies[#bodies + 1] = { e.name, b.body, #e.text } end
		end
	end
end
print("templates: " .. n .. ", script bodies: " .. #bodies)
print(bad == 0 and "ALL CLEAN" or ("PROBLEMS: " .. bad))
print("---- script bodies, longest first ----")
table.sort(bodies, function(a, b) return a[3] > b[3] end)
for _, r in ipairs(bodies) do print(string.format("%3d/255  %s", r[3], r[1])) end
-- Print the bodies for the syntax pass, exactly as a save would hand them to loadstring.
for _, r in ipairs(bodies) do print("@@BODY@@" .. r[2]) end
