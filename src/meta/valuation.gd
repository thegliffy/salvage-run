class_name Valuation
extends RefCounted
## The end-of-run ship sale.
##
## This is the hinge between the run and the meta-game, so it is built to be
## READ, not just computed: appraise() returns an itemised receipt the sale
## screen renders line by line. Players should be able to look at the breakdown
## and immediately understand what to do differently next run.
##
## Design intent behind the numbers:
##   - Parts are the bulk of the value  -> hoarding good parts is rewarded
##   - Wear cuts value hard             -> taking damage has a lasting cost
##   - Depth multiplies                 -> going further beats playing safe
##   - Dying keeps a real fraction      -> a failed run is never worthless
##
## Tuning constants live here rather than in content JSON because they are
## systemic, not per-item, and changing them re-balances the whole meta curve.

const HULL_CONDITION_BONUS := 60      # max credits from a pristine hull
const ELITE_BONUS := 45
const BOSS_MULTIPLIER := 1.75
const DEATH_RECOVERY := 0.40          # you sell the wreck, not the ship
const SECTOR_MULTIPLIER := 0.25       # +25% of base per sector cleared

static func appraise(run: RunState) -> Dictionary:
	var lines: Array = []
	var base := 0

	# --- Parts, itemised so the player sees which parts carried the run ---
	var part_total := 0
	for inst in run.ship.parts:
		var v: int = inst.sale_value()
		part_total += v
		var condition := "pristine"
		if inst.is_wrecked():
			condition = "wrecked"
		elif inst.wear > 0:
			condition = "worn"
		lines.append({
			"label": "%s (%s)" % [inst.def.name, condition],
			"name": inst.def.name,
			"condition": condition,
			"amount": v,
			"kind": "part",
		})
	base += part_total

	# --- Hull condition ---
	var hull_frac := 0.0
	if run.profile.max_hull > 0:
		hull_frac = clampf(float(run.hull_carryover) / float(run.profile.max_hull), 0.0, 1.0)
	var hull_bonus := int(round(HULL_CONDITION_BONUS * hull_frac))
	if hull_bonus > 0:
		var hull_pct := int(hull_frac * 100.0)
		lines.append({
			"label": "Hull integrity (%d%%)" % hull_pct,
			"name": "Hull integrity",
			"detail": "%d%%" % hull_pct,
			"amount": hull_bonus,
			"kind": "bonus",
		})
	base += hull_bonus

	# --- Combat record ---
	if run.elites_killed > 0:
		var eb := run.elites_killed * ELITE_BONUS
		lines.append({
			"label": "Elite kills x%d" % run.elites_killed,
			"name": "Elite kills",
			"detail": "x%d" % run.elites_killed,
			"amount": eb,
			"kind": "bonus",
		})
		base += eb

	# --- Leftover credits convert 1:1 ---
	if run.credits > 0:
		lines.append({
			"label": "Unspent credits",
			"name": "Unspent credits",
			"detail": "",
			"amount": run.credits,
			"kind": "bonus",
		})
		base += run.credits

	# --- Multipliers ---
	var subtotal := base
	var mult := 1.0 + (maxi(0, run.sector - 1) * SECTOR_MULTIPLIER)
	if run.boss_killed:
		mult *= BOSS_MULTIPLIER
	if not run.alive:
		mult *= DEATH_RECOVERY

	var total := int(round(float(subtotal) * mult))

	var mult_label := "Sector %d" % run.sector
	if run.boss_killed:
		mult_label += " + boss"
	if not run.alive:
		mult_label += " - salvaged wreck"

	return {
		"lines": lines,
		"subtotal": subtotal,
		"multiplier": mult,
		"multiplier_label": mult_label,
		"total": total,
		"survived": run.alive,
		"boss_killed": run.boss_killed,
	}

## Plain-text receipt; used by the headless sim and handy for bug reports.
static func format_receipt(v: Dictionary) -> String:
	var s := "--- SHIP SALE ---\n"
	for l in v["lines"]:
		s += "  %-34s %6d\n" % [l["label"], l["amount"]]
	s += "  %-34s %6d\n" % ["subtotal", v["subtotal"]]
	s += "  %-34s  x%.2f\n" % [v["multiplier_label"], v["multiplier"]]
	s += "  %-34s %6d salvage\n" % ["TOTAL", v["total"]]
	return s
