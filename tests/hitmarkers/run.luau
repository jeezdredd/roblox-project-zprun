--!strict

-- Pure tests for the hit and kill markers: the variant, the timing, the damage
-- scaling, restarting without stacking, a kill not cut short, the per-pellet sum.
-- Run from the repository root with the standalone Luau CLI:
--   luau tests/hitmarkers/run.luau
-- One line per group; the run exits non-zero when any check failed.

local HitMarkerConfig = require("../../src/shared/config/HitMarkerConfig")
local HitMarkerMath = require("../../src/shared/util/HitMarkerMath")
local WeaponsConfig = require("../../src/shared/config/WeaponsConfig")

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

local C = HitMarkerConfig :: any
local M = HitMarkerMath

local function hit(damage: number, headshot: boolean?, killed: boolean?): HitMarkerMath.Confirm
	return { damage = damage, headshot = headshot == true, killed = killed == true }
end

group("variant", function()
	check("a body hit", M.variantFor(hit(30)) == "Hit")
	check("a headshot", M.variantFor(hit(60, true)) == "Headshot")
	check("a kill", M.variantFor(hit(30, false, true)) == "Kill")
	check("a headshot kill is a kill", M.variantFor(hit(60, true, true)) == "Kill")
	check("no damage, no marker", M.variantFor(hit(0)) == nil)
	check("a kill with no damage left still marks", M.variantFor(hit(0, false, true)) == "Kill")
	for _, variant in { "Hit", "Headshot", "Kill" } do
		check(variant .. " has a colour", HitMarkerConfig.colors[variant] ~= nil and #HitMarkerConfig.colors[variant] == 3)
	end
	check("the kill is red", HitMarkerConfig.colors.Kill[1] > 200 and HitMarkerConfig.colors.Kill[2] < 100)
	check("the headshot tint differs from the hit", HitMarkerConfig.colors.Headshot[3] ~= HitMarkerConfig.colors.Hit[3])
end)

group("timing", function()
	check("hit about 0.12 s", math.abs(M.durationFor(C, "Hit") - 0.12) < 1e-9)
	check("headshot as a hit", M.durationFor(C, "Headshot") == M.durationFor(C, "Hit"))
	check("kill about 0.25 s", math.abs(M.durationFor(C, "Kill") - 0.25) < 1e-9)
	local state = M.start(C, M.idle(), 10, hit(30))
	check("shows at the start", M.frame(C, state, 10).visible)
	check("shows just before the end", M.frame(C, state, 10.119).visible)
	check("gone at the end", not M.frame(C, state, 10.1201).visible)
	check("idle shows nothing", not M.frame(C, M.idle(), 0).visible)
	local start = M.frame(C, state, 10)
	check("pops in larger", math.abs(start.scale - state.scale * HitMarkerConfig.POP) < 1e-9)
	local settled = M.frame(C, state, 10 + 0.12 * HitMarkerConfig.POP_SHARE + 1e-4)
	check("settles to its scale", math.abs(settled.scale - state.scale) < 1e-9)
	check("opaque before the fade", M.frame(C, state, 10 + 0.12 * 0.5).alpha == 1)
	local late = M.frame(C, state, 10 + 0.12 * 0.9)
	check("fading near the end", late.alpha > 0 and late.alpha < 1, tostring(late.alpha))
	local a = M.frame(C, state, 10 + 0.12 * 0.7).alpha
	local b = M.frame(C, state, 10 + 0.12 * 0.8).alpha
	check("the fade only goes down", b < a)
end)

group("damage scaling", function()
	check("reference damage is scale 1", M.scaleFor(C, "Hit", HitMarkerConfig.DAMAGE_REFERENCE) == 1)
	check("more damage, bigger", M.scaleFor(C, "Hit", 45) > M.scaleFor(C, "Hit", 30))
	check("less damage, smaller", M.scaleFor(C, "Hit", 16) < 1)
	check("clamped high", M.scaleFor(C, "Hit", 100000) == HitMarkerConfig.SCALE_MAX)
	check("clamped low", M.scaleFor(C, "Hit", 0) == HitMarkerConfig.SCALE_MIN)
	check("negative is the floor", M.scaleFor(C, "Hit", -50) == HitMarkerConfig.SCALE_MIN)
	check("a kill is its own size", M.scaleFor(C, "Kill", 1) == HitMarkerConfig.KILL_SCALE and M.scaleFor(C, "Kill", 999) == HitMarkerConfig.KILL_SCALE)
	check("a kill is larger than any hit", HitMarkerConfig.KILL_SCALE > HitMarkerConfig.SCALE_MAX)
	check("only slightly", HitMarkerConfig.SCALE_MAX <= 1.3 and HitMarkerConfig.SCALE_MIN >= 0.8)
	for _, id in WeaponsConfig.order do
		local weapon = WeaponsConfig.get(id) :: WeaponsConfig.WeaponConfig
		local body = M.scaleFor(C, "Hit", weapon.damage * weapon.pellets)
		check(id .. " body shot within range", body >= HitMarkerConfig.SCALE_MIN and body <= HitMarkerConfig.SCALE_MAX)
	end
end)

group("restart, no stacking", function()
	local first = M.start(C, M.idle(), 10, hit(30))
	local second = M.start(C, first, 10.05, hit(30))
	check("a new hit restarts the one marker", second.startedAt == 10.05 and second.variant == "Hit")
	check("full again", M.frame(C, second, 10.1).visible and M.frame(C, second, 10.16).visible)
	check("nothing confirmed keeps the state", M.start(C, second, 10.1, hit(0)) == second)
	local kill = M.start(C, second, 10.1, hit(30, false, true))
	check("a kill takes over a hit", kill.variant == "Kill" and kill.startedAt == 10.1)
	local hitDuringKill = M.start(C, kill, 10.2, hit(30))
	check("a hit does not cut a kill short", hitDuringKill == kill)
	local headDuringKill = M.start(C, kill, 10.2, hit(60, true))
	check("nor does a headshot", headDuringKill == kill)
	local afterKill = M.start(C, kill, 10.36, hit(30))
	check("after the kill ends a hit shows again", afterKill.variant == "Hit" and afterKill.startedAt == 10.36)
	local killAgain = M.start(C, kill, 10.2, hit(30, false, true))
	check("a second kill restarts the kill", killAgain.startedAt == 10.2)
	local head = M.start(C, first, 10.05, hit(60, true))
	check("a headshot takes over a hit", head.variant == "Headshot")
	local bodyAfterHead = M.start(C, head, 10.1, hit(30))
	check("a body hit does not cut a headshot short", bodyAfterHead == head)
end)

group("per-pellet sum", function()
	local sum = M.combine({ hit(12), hit(12), hit(0), hit(12, true) }) :: HitMarkerMath.Confirm
	check("damage summed", sum.damage == 36)
	check("any headshot counts", sum.headshot)
	check("no kill", not sum.killed)
	local kill = M.combine({ hit(12), hit(12, false, true) }) :: HitMarkerMath.Confirm
	check("any kill counts", kill.killed and kill.damage == 24)
	check("nothing hurt, nil", M.combine({ hit(0), hit(0) }) == nil)
	check("no pellets, nil", M.combine({}) == nil)
end)

if failures > 0 then
	error(string.format("%d assertion(s) failed", failures))
end
print("all hit marker tests passed")
