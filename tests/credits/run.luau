--!strict

-- The generated credits as the game reads them: three groups in order, every line
-- complete, no asset in two lines, the acknowledgements. The manifest side (every CC BY
-- entry credited exactly once) is tests/credits/run.py. Run from the repository root:
--   luau tests/credits/run.luau

local CreditsConfig = require("../../src/shared/config/CreditsConfig")

local failures = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		return
	end
	failures += 1
	print(string.format("  FAIL %s%s", name, if detail then " (" .. detail .. ")" else ""))
end

local function group(name: string, body: () -> ())
	local before = failures
	body()
	print(string.format("%s %s", if failures == before then "ok  " else "FAIL", name))
end

group("groups", function()
	local names = {}
	for _, g in CreditsConfig.groups do
		table.insert(names, g.name)
	end
	check("models, animations, audio", table.concat(names, ",") == "Models and textures,Animations,Audio", table.concat(names, ","))
	local total = 0
	for _, g in CreditsConfig.groups do
		total += #g.credits
	end
	check("something to credit", total > 0)
end)

group("lines", function()
	local seen: { [string]: boolean } = {}
	for _, g in CreditsConfig.groups do
		for _, credit in g.credits do
			check(credit.title .. " title", #credit.title > 0)
			check(credit.title .. " author", #credit.author > 0)
			check(credit.title .. " licence", string.match(credit.licence, "^CC BY %d") ~= nil, credit.licence)
			check(credit.title .. " url", string.sub(credit.url, 1, 4) == "http", credit.url)
			check(credit.title .. " assets", #credit.assets > 0)
			for _, key in credit.assets do
				check(key .. " once", not seen[key])
				seen[key] = true
				local isAudio = string.sub(key, 1, 6) == "audio/"
				local isAnimation = string.sub(key, 1, 10) == "animation/"
				local expected = if isAudio then "Audio" elseif isAnimation then "Animations" else "Models and textures"
				check(key .. " in its kind's group", g.name == expected, g.name)
			end
		end
	end
	check("the changes note", #CreditsConfig.NOTE > 0)
end)

group("acknowledgements", function()
	check("two lines", #CreditsConfig.acknowledgements == 2)
	for _, ack in CreditsConfig.acknowledgements do
		check(ack.title .. " says it is not required", string.find(ack.licence, "no attribution required", 1, true) ~= nil)
		check(ack.title .. " url", string.sub(ack.url, 1, 4) == "http")
		check(ack.title .. " covers assets", ack.count > 0)
	end
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all credits config tests passed")
