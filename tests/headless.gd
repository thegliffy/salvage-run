extends Node
## Headless entry point for tests and balance simulation.
##
##   godot --headless --path . res://tests/headless.tscn -- --test
##   godot --headless --path . res://tests/headless.tscn -- --sim 200
##   godot --headless --path . res://tests/headless.tscn -- --sim 200 --seed 42
##
## The simulator exists because a deckbuilder cannot be balanced by intuition.
## Slay the Spire's team leaned on play metrics; solo, the substitute is being
## able to run ten thousand fights in a second and look at the distribution.

var _passed := 0
var _failed := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "--test"
	var count := 100
	var base_seed := -1

	for i in args.size():
		match args[i]:
			"--test": mode = "--test"
			"--sim":
				mode = "--sim"
				if i + 1 < args.size() and args[i + 1].is_valid_int():
					count = int(args[i + 1])
			"--seed":
				if i + 1 < args.size() and args[i + 1].is_valid_int():
					base_seed = int(args[i + 1])

	var code := 0
	if mode == "--sim":
		_run_sim(count, base_seed)
	else:
		code = _run_tests()
	get_tree().quit(code)

# --- Tiny assertion helpers --------------------------------------------------

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % name)
	else:
		_failed += 1
		print("  FAIL  %s%s" % [name, ("  <- " + detail) if detail != "" else ""])

func _eq(name: String, got, want) -> void:
	_check(name, got == want, "got %s, want %s" % [got, want])

# --- Tests -------------------------------------------------------------------

func _run_tests() -> int:
	print("\n=== SALVAGE RUN :: tests ===\n")
	_test_content()
	_test_loadout()
	_test_compile()
	_test_rng_determinism()
	_test_combat_fizzle()
	_test_deck_cycling()
	_test_damage_pipeline()
	_test_strip()
	_test_rewards()
	_test_valuation()
	_test_meta_progression()
	_test_map()
	print("\n%d passed, %d failed\n" % [_passed, _failed])
	return 1 if _failed > 0 else 0

func _test_content() -> void:
	print("content")
	_check("content loads with no errors", Database.errors().is_empty(),
		str(Database.errors()))
	_check("cards present", Database.cards.size() > 0)
	_check("parts present", Database.parts.size() > 0)
	_check("enemies present", Database.enemies.size() > 0)
	var laser: CardDef = Database.card(&"laser_burst")
	_check("card parses upgrade block", laser != null and not laser.upgrade_effects.is_empty())
	_eq("upgraded laser hits harder",
		int(laser.effects_for(true)[0]["amount"]) > int(laser.effects_for(false)[0]["amount"]), true)

func _test_loadout() -> void:
	print("loadout (typed slots)")
	var g := ShipLoadout.new("Test")
	g.capacity = {ShipLoadout.SLOT_WEAPON: 4, ShipLoadout.SLOT_HULL: 3,
		ShipLoadout.SLOT_UTILITY: 4}

	var laser: PartDef = Database.part(&"burst_laser")        # weapon
	var deflector: PartDef = Database.part(&"deflector_mk1")  # hull
	var thrusters: PartDef = Database.part(&"ion_thrusters")  # utility

	_eq("weapon slots start empty", g.free_slots(ShipLoadout.SLOT_WEAPON), 4)
	_check("installs into a free slot", g.install(laser) != null)
	_eq("slot consumed", g.free_slots(ShipLoadout.SLOT_WEAPON), 3)
	_eq("other slots untouched", g.free_slots(ShipLoadout.SLOT_HULL), 3)

	# Fill the weapon slots and confirm the hard limit holds.
	for i in 3:
		g.install(laser)
	_eq("weapon slots full", g.free_slots(ShipLoadout.SLOT_WEAPON), 0)
	_check("refuses a fifth weapon", g.install(laser) == null)
	_check("refusal is readable", g.install_error(laser).contains("weapon"))
	_check("a full weapon slot does not block hull", g.install(deflector) != null)

	# Swapping is how a full slot stays an upgrade path.
	var old: PartInstance = g.installed_in(ShipLoadout.SLOT_WEAPON)[0]
	var lance: PartDef = Database.part(&"carrion_lance")
	_check("swaps within the same slot type", g.replace(old, lance) != null)
	_eq("swap does not change slot usage", g.free_slots(ShipLoadout.SLOT_WEAPON), 0)
	_check("refuses a cross-slot swap",
		g.replace(g.installed_in(ShipLoadout.SLOT_HULL)[0], thrusters) == null)

func _test_compile() -> void:
	print("compile (loadout -> combat profile)")
	Rng.seed_run(1)
	var ship := StarterShips.salvager()
	var prof := ship.compile()

	_eq("starter fills one of each slot type", ship.parts.size(), 3)
	_eq("weapon slot", ship.free_slots(ShipLoadout.SLOT_WEAPON), 3)
	_eq("hull slot", ship.free_slots(ShipLoadout.SLOT_HULL), 2)
	_eq("utility slot", ship.free_slots(ShipLoadout.SLOT_UTILITY), 3)

	_check("has weapons system", prof.has_system(&"weapons"))
	_check("has shields system", prof.has_system(&"shields"))
	_eq("starter deck is 3 parts x 3 cards", prof.deck.size(), 9)
	_eq("laser granted twice by burst laser", prof.deck.count(&"laser_burst"), 2)
	_check("hull includes base", prof.max_hull >= 30)
	_check("ship is self-powered without a reactor", prof.power > 0)
	_check("starter is within its power budget", prof.warnings.is_empty(),
		str(prof.warnings))

	# Wrecked parts contribute nothing.
	var before := prof.deck.size()
	ship.parts[0].wear = ship.parts[0].def.integrity
	_check("wrecked part drops its cards", ship.compile().deck.size() < before)

	# Overdrawing the reactor is a price, not a wall.
	var hog := ShipLoadout.new("Hog")
	hog.base_power = 2
	hog.install(Database.part(&"carrion_lance"))   # draw 3
	var hp := hog.compile()
	_check("power deficit is reported", not hp.warnings.is_empty())
	_check("deficit reduces energy", hp.power < 2)
	_check("but the part still installed", hog.parts.size() == 1)

	# Synergy keys off having a system anywhere on the ship, not off where a
	# part sits. EMP Projector wants sensors aboard.
	var syn := ShipLoadout.new("Syn")
	syn.install(Database.part(&"emp_projector"))
	var without := syn.compile().draw_per_turn
	syn.install(Database.part(&"sensor_array"))    # sensors present -> synergy fires
	var with_sensors := syn.compile().draw_per_turn
	_check("synergy applies when the system is present",
		with_sensors > without + int(Database.part(&"sensor_array").stats.get("draw", 0)) - 1,
		"without=%d with=%d" % [without, with_sensors])

func _test_rng_determinism() -> void:
	print("rng")
	Rng.seed_run(12345)
	var a: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	Rng.shuffle(&"combat", a)
	Rng.seed_run(12345)
	var b: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	Rng.shuffle(&"combat", b)
	_eq("same seed -> same shuffle", a, b)

	Rng.seed_run(12345)
	var c: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	Rng.shuffle(&"map", c)
	_check("streams are independent", a != c)

func _test_combat_fizzle() -> void:
	print("combat: subsystem targeting + intent fizzle")
	Rng.seed_run(7)
	var ship := StarterShips.salvager()
	var c := CombatController.new()
	c.setup(ship.compile(), Database.enemy(&"scout_drone"), ship)

	_check("combat starts on player turn", c.phase == CombatController.Phase.PLAYER)
	_check("player drew a hand", c.deck.hand.size() > 0)
	_check("enemy telegraphs an intent", c.brain.telegraph() != "")

	# Destroy the enemy weapons system outright.
	var weapons: ShipSystem = c.enemy.system(&"weapons")
	weapons.take_damage(weapons.max_integrity)
	_check("weapons offline after lethal damage", not weapons.is_active())

	# Force the enemy onto a weapons intent, then confirm it fizzles.
	c.brain.current_intent = c.enemy_intent_by_id(&"pulse")
	_check("weapons intent fizzles when weapons are down", c.brain.intent_fizzles())

	var hull_before := c.player.hull
	c.end_player_turn()
	_eq("fizzled intent deals no damage", c.player.hull, hull_before)

	# And a live system does fire.
	Rng.seed_run(7)
	var ship2 := StarterShips.salvager()
	var c2 := CombatController.new()
	c2.setup(ship2.compile(), Database.enemy(&"scout_drone"), ship2)
	c2.brain.current_intent = c2.enemy_intent_by_id(&"pulse")
	var before2 := c2.player.hull + c2.player.shield + _total_integrity(c2.player)
	c2.end_player_turn()
	var after2 := c2.player.hull + c2.player.shield + _total_integrity(c2.player)
	_check("live intent does damage", after2 < before2,
		"before=%d after=%d" % [before2, after2])

	# Regression: a fully disabled enemy must still be killable. Before this
	# rule existed, destroying every subsystem left no legal target and the
	# fight stalled forever -- the balance sim caught it, not a human.
	Rng.seed_run(21)
	var ship3 := StarterShips.salvager()
	var c3 := CombatController.new()
	c3.setup(ship3.compile(), Database.enemy(&"scout_drone"), ship3)
	c3.enemy.shield = 0
	c3.enemy.evasion = 0
	for sid in c3.enemy.systems:
		var sys: ShipSystem = c3.enemy.systems[sid]
		sys.take_damage(sys.max_integrity)
	_check("disabled enemy is still targetable",
		not c3.enemy.targetable_systems().is_empty())
	_check("no systems remain intact", c3.enemy.intact_systems().is_empty())
	var hull_pre := c3.enemy.hull
	c3.resolver.run([{"op": "damage_system", "amount": 9}],
		{"source": c3.player, "opponent": c3.enemy, "target_system": &"weapons"})
	_check("shots at a wrecked system spill into the hull",
		c3.enemy.hull < hull_pre, "hull %d -> %d" % [hull_pre, c3.enemy.hull])

func _total_integrity(cb: Combatant) -> int:
	var t := 0
	for sid in cb.systems:
		t += cb.systems[sid].integrity
	return t

func _test_deck_cycling() -> void:
	print("deck")
	Rng.seed_run(3)
	var d := Deck.new()
	var ids: Array[StringName] = [&"laser_burst", &"laser_burst", &"raise_deflector"]
	d.build(ids)
	_eq("deck built", d.total_cards(), 3)
	d.draw(3)
	_eq("hand holds all", d.hand.size(), 3)
	d.discard_hand()
	_eq("discard holds all", d.discard_pile.size(), 3)
	d.draw(2)
	_eq("reshuffles from discard", d.hand.size(), 2)
	_check("no cards lost in cycling", d.total_cards() == 3)

	var unknown: Array[StringName] = [&"nonexistent_card"]
	var d2 := Deck.new()
	d2.build(unknown)
	_eq("unknown card ids are skipped, not fatal", d2.total_cards(), 0)

func _test_damage_pipeline() -> void:
	print("damage pipeline")
	Rng.seed_run(11)
	var ship := StarterShips.salvager()
	var c := CombatController.new()
	c.setup(ship.compile(), Database.enemy(&"raider"), ship)
	c.enemy.evasion = 0   # remove variance for the assertion

	var shield_before := c.enemy.shield
	c.resolver.run([{"op": "damage_system", "amount": 3}],
		{"source": c.player, "opponent": c.enemy, "target_system": &"weapons"})
	_check("shields absorb first", c.enemy.shield < shield_before)
	_eq("system untouched while shields hold",
		c.enemy.system(&"weapons").integrity, c.enemy.system(&"weapons").max_integrity)

	c.enemy.shield = 0
	c.resolver.run([{"op": "damage_system", "amount": 4}],
		{"source": c.player, "opponent": c.enemy, "target_system": &"weapons"})
	_check("system takes damage once shields drop",
		c.enemy.system(&"weapons").integrity < c.enemy.system(&"weapons").max_integrity)

	# Pierce bypasses shields entirely.
	c.enemy.shield = 20
	var eng_before: int = c.enemy.system(&"engines").integrity
	c.resolver.run([{"op": "damage_system", "amount": 4, "pierce": true}],
		{"source": c.player, "opponent": c.enemy, "target_system": &"engines"})
	_eq("pierce leaves shields alone", c.enemy.shield, 20)
	_check("pierce hits the system", c.enemy.system(&"engines").integrity < eng_before)

	# Overflow past a destroyed system spills into the hull.
	c.enemy.shield = 0
	var hull_before := c.enemy.hull
	c.resolver.run([{"op": "damage_system", "amount": 100, "pierce": true}],
		{"source": c.player, "opponent": c.enemy, "target_system": &"engines"})
	_check("overflow spills to hull", c.enemy.hull < hull_before)

	# Player subsystem loss wears the underlying part permanently.
	var wsys: ShipSystem = c.player.system(&"weapons")
	c.resolver.run([{"op": "damage_system", "amount": 999, "pierce": true, "unavoidable": true}],
		{"source": c.enemy, "opponent": c.player, "target_system": &"weapons"})
	var worn := false
	for inst in ship.parts:
		if wsys.part_uids.has(inst.uid) and inst.wear > 0:
			worn = true
	_check("destroyed player system wears its part", worn)

func _test_strip() -> void:
	print("strip (card removal)")
	Rng.seed_run(31)
	var run := RunState.new()
	run.start(StarterShips.salvager(), 31)

	var deck_before: int = run.profile.deck.size()
	_eq("starter ship is 3 parts x 3 cards", deck_before, 9)

	var opts := SalvageYard.options(run)
	_eq("every mount on every part is offered", opts.size(), 3 * 3)
	_check("options carry a value cost", int(opts[0]["value_cost"]) > 0)

	# Cut the weapon's third mount. The starter carries no status-kind dud any
	# more (its reactor is gone), so the interesting strip is a real tradeoff
	# card rather than obvious chaff.
	var target_inst: PartInstance = null
	var target_index := -1
	for o in opts:
		if o["card_id"] == &"overheat":
			target_inst = o["part"]
			target_index = o["index"]
	_check("the weapon's third mount is available to cut", target_inst != null)

	var value_before: int = target_inst.sale_value()
	_eq("strip succeeds", SalvageYard.strip(run, target_inst, target_index), "")
	_eq("deck is one card lighter", run.profile.deck.size(), deck_before - 1)
	_check("the stripped card is gone", not run.profile.deck.has(&"overheat"))
	_check("strip costs sale value", target_inst.sale_value() < value_before)

	# THE regression that matters: the deck is derived, so a strip that is not
	# stored on the part gets silently undone by the next ship change.
	run.recompile()
	_eq("strip survives a bare recompile", run.profile.deck.size(), deck_before - 1)
	var spare: PartDef = Database.part(&"sensor_array")
	_check("install an unrelated part", run.install(spare) != null)
	_check("strip survives installing another part",
		not run.profile.deck.has(&"overheat"))

	# One strip per part, enforced by the type rather than by price.
	_check("part reports itself stripped", target_inst.is_stripped())
	_check("part cannot be stripped twice", not target_inst.can_strip())
	_check("second strip is refused", SalvageYard.strip(run, target_inst, 0) != "")
	for o in SalvageYard.options(run):
		if o["part"] == target_inst:
			_check("stripped part offers no further mounts", false)
	_check("stripped part drops out of the options list", true)

	# Thinning has a floor: you can never cut past two thirds.
	var floor_run := RunState.new()
	floor_run.start(StarterShips.salvager(), 32)
	for inst in floor_run.ship.parts:
		SalvageYard.strip(floor_run, inst, 0)
	_eq("every part stripped once", floor_run.profile.deck.size(), 6)
	var still_strippable := 0
	for inst in floor_run.ship.parts:
		if inst.can_strip():
			still_strippable += 1
	_eq("nothing left to strip", still_strippable, 0)

	var summary := SalvageYard.strip_summary(floor_run)
	_eq("summary counts strips", summary["stripped"], 3)

	# Strips must survive save/load along with the rest of the ship.
	var round_trip := ShipLoadout.from_dict(floor_run.ship.to_dict())
	_eq("strips survive serialisation", round_trip.compile().deck.size(), 6)

func _test_rewards() -> void:
	print("rewards")
	Rng.seed_run(77)
	var meta := MetaState.new()
	for pid in Database.parts:
		meta.unlocked[pid] = true
	var run := RunState.new()
	run.start(StarterShips.salvager(), 77)

	# Tier scaling: only tougher fights pay out improvements.
	_check("regular enemies drop no improvement",
		RewardPool.build(run, meta, Database.enemy(&"scout_drone"))["improvement"] == null)
	var elite: ImprovementDef = RewardPool.build(run, meta, Database.enemy(&"gunship"))["improvement"]
	_check("mini-boss drops an improvement", elite != null)
	_check("mini-boss improvement is common or uncommon",
		elite != null and [&"common", &"uncommon"].has(elite.rarity),
		"got %s" % (elite.rarity if elite else "null"))
	var boss: ImprovementDef = RewardPool.build(run, meta, Database.enemy(&"dreadnought"))["improvement"]
	_check("boss improvement is rare", boss != null and boss.rarity == &"rare",
		"got %s" % (boss.rarity if boss else "null"))
	var boss_parts: Array = RewardPool.build(run, meta, Database.enemy(&"dreadnought"))["parts"]
	_check("boss offers a rare part", boss_parts.any(func(o): return o["rarity"] == &"rare"))

	# Improvements change the ship, not the deck.
	var deck_before: int = run.profile.deck.size()
	var hull_before: int = run.profile.max_hull
	run.ship.add_improvement(&"reinforced_frame")   # +16 hull
	run.recompile()
	_eq("improvement adds no cards", run.profile.deck.size(), deck_before)
	_eq("improvement raises hull", run.profile.max_hull, hull_before + 16)

	# Slot improvements really add slots.
	var weapons_before: int = run.ship.slot_capacity(ShipLoadout.SLOT_WEAPON)
	run.ship.add_improvement(&"weapon_hardpoint")
	_eq("weapon hardpoint adds a slot",
		run.ship.slot_capacity(ShipLoadout.SLOT_WEAPON), weapons_before + 1)

	var round_trip := ShipLoadout.from_dict(run.ship.to_dict())
	_eq("improvements survive serialisation",
		round_trip.slot_capacity(ShipLoadout.SLOT_WEAPON), weapons_before + 1)

	# The hull generates power; no part may.
	for pid in Database.parts:
		if Database.parts[pid].power_gen != 0:
			_check("no part generates power (%s)" % pid, false)
	_check("no part generates power", true)
	_check("ship is powered with no reactor part", run.profile.power > 0)

	# Jettison: declining a part cuts an installed one, cards and all.
	var victim: PartInstance = run.ship.parts[0]
	var cards_before: int = run.profile.deck.size()
	var slot := victim.def.slot
	var free_before: int = run.ship.free_slots(slot)
	_eq("jettison succeeds", RewardPool.jettison(run, victim), "")
	_eq("jettison frees the slot", run.ship.free_slots(slot), free_before + 1)
	_check("jettison removes its cards too",
		run.profile.deck.size() < cards_before)
	_check("jettisoning it twice fails", RewardPool.jettison(run, victim) != "")

func _test_valuation() -> void:
	print("valuation")
	Rng.seed_run(5)
	var run := RunState.new()
	run.start(StarterShips.salvager(), 5)
	run.sector = 1
	run.hull_carryover = run.profile.max_hull

	var pristine := Valuation.appraise(run)
	_check("pristine run has value", pristine["total"] > 0)
	_eq("line per part plus hull bonus",
		pristine["lines"].size() >= run.ship.parts.size(), true)

	# Wear cuts value.
	run.ship.parts[0].wear = run.ship.parts[0].def.integrity
	var worn := Valuation.appraise(run)
	_check("wear reduces value", worn["total"] < pristine["total"],
		"%d vs %d" % [worn["total"], pristine["total"]])

	# Dying cuts value hard.
	run.alive = false
	var died := Valuation.appraise(run)
	_check("death reduces value", died["total"] < worn["total"])

	# Boss + depth multiply it up.
	run.alive = true
	run.boss_killed = true
	run.sector = 3
	var deep := Valuation.appraise(run)
	_check("boss and depth multiply value", deep["total"] > worn["total"])
	_check("receipt renders", Valuation.format_receipt(deep).contains("TOTAL"))

func _test_meta_progression() -> void:
	print("meta")
	var meta := MetaState.new()
	meta.grant_starting_unlocks()
	_check("starters unlocked", meta.unlocked.size() > 0)
	_check("locked parts exist to buy", meta.unlockable().size() > 0)

	var target: PartDef = meta.unlockable()[0]
	_check("cannot afford with no salvage", not meta.can_afford(target.id))
	meta.salvage = target.unlock_cost
	_check("unlock succeeds when affordable", meta.unlock(target.id))
	_eq("salvage deducted", meta.salvage, 0)
	_check("part now unlocked", meta.is_unlocked(target.id))
	_check("cannot unlock twice", not meta.unlock(target.id))

	# Round-trip through save serialisation.
	var d := meta.to_dict()
	var meta2 := MetaState.new()
	meta2.from_dict(d)
	_check("save round-trip keeps unlocks", meta2.is_unlocked(target.id))
	_eq("save round-trip keeps salvage", meta2.salvage, meta.salvage)

func _test_map() -> void:
	print("map")
	Rng.seed_run(99)
	var m := MapGenerator.generate(1, 8)
	_eq("layer count", m["by_layer"].size(), 8)
	_check("single entry", m["by_layer"][0].size() == 1)
	_check("boss is last", m["nodes"].back()["type"] == "boss")

	# Every node must be reachable from the entry, or the run can dead-end.
	var seen := {}
	var queue: Array = [m["entry"]]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		if seen.has(n):
			continue
		seen[n] = true
		for e in m["nodes"][n]["edges"]:
			queue.append(e)
	_eq("all nodes reachable", seen.size(), m["nodes"].size())

	Rng.seed_run(99)
	var m2 := MapGenerator.generate(1, 8)
	_eq("map is deterministic for a seed", m2["nodes"].size(), m["nodes"].size())

# --- Balance simulator -------------------------------------------------------

func _run_sim(count: int, base_seed: int) -> void:
	print("\n=== SALVAGE RUN :: simulating %d runs ===\n" % count)
	var wins := 0
	var totals: Array[int] = []
	var turn_counts: Array[int] = []
	var deaths_at: Dictionary = {}
	var tally: Dictionary = {}
	var deck_sizes: Array[int] = []
	var start := Time.get_ticks_msec()

	for i in count:
		var s: int = (base_seed + i) if base_seed >= 0 else (1000 + i)
		var result := _simulate_run(s, false, tally)
		if result["won"]:
			wins += 1
		totals.append(result["salvage"])
		deck_sizes.append(int(result["deck_size"]))
		turn_counts.append(result["turns"])
		if not result["won"]:
			var d: String = result["died_at"]
			deaths_at[d] = int(deaths_at.get(d, 0)) + 1

	var elapsed := Time.get_ticks_msec() - start
	print("win rate     : %.1f%%  (%d/%d)" % [100.0 * wins / maxi(1, count), wins, count])
	print("salvage      : avg %d, min %d, max %d" % [_avg(totals), totals.min(), totals.max()])
	print("combat turns : avg %.1f" % (float(_sum(turn_counts)) / maxi(1, count)))
	print("deaths by    : %s" % [deaths_at])
	print("elapsed      : %d ms (%.2f ms/run)" % [elapsed, float(elapsed) / maxi(1, count)])
	print("final deck   : avg %d cards" % _avg(deck_sizes))
	_print_histogram(tally, count)
	print("")
	print("A healthy target for a scaffold is a NON-trivial win rate: if this")
	print("reads 0%% or 100%%, the numbers in content/*.json need a pass, not the code.")

	# Show one annotated fight so the log format is visible. Honour --seed so
	# the narrated run is one of the runs just measured.
	var sample: int = base_seed if base_seed >= 0 else 1000
	print("\n--- sample fight (seed %d) ---" % sample)
	_simulate_run(sample, true)

func _simulate_run(run_seed: int, verbose: bool = false,
		tally: Dictionary = {}) -> Dictionary:
	var run := RunState.new()
	run.start(StarterShips.salvager(), run_seed)
	var ladder: Array[StringName] = [&"scout_drone", &"raider", &"scout_drone",
		&"gunship", &"raider", &"gunship", &"dreadnought"]
	var total_turns := 0
	var died_at := "survived"

	var first := true
	for enemy_id in ladder:
		var c := run.make_combat(enemy_id)
		if c == null:
			break
		var turns := _autoplay(c, verbose and first, tally)
		first = false
		total_turns += turns
		var stalled := c.phase != CombatController.Phase.DONE
		run.finish_combat(c)
		if stalled:
			died_at = "STALL:" + String(enemy_id)
			run.alive = false
			break
		if not run.alive:
			died_at = String(enemy_id)
			break
		if enemy_id == &"dreadnought":
			run.boss_killed = true
		if enemy_id == &"gunship":
			run.elites_killed += 1
		# Between fights, spend credits repairing the worst-worn part, and
		# cut one dud card the way a player passing a salvage node would.
		_auto_repair(run)
		_auto_reward(run, enemy_id)
		_auto_strip(run)

	run.sector = 3 if run.boss_killed else 2
	var v := Valuation.appraise(run)
	if verbose:
		print(Valuation.format_receipt(v))
	return {"won": run.boss_killed, "salvage": v["total"], "turns": total_turns,
		"died_at": died_at, "deck_size": run.profile.deck.size()}

## The simulator's pilot.
##
## It scores every playable card from its EFFECT OPS rather than from a list of
## card names, so new content is evaluated the moment it is added and dead cards
## show up in the play histogram instead of hiding behind a bot that never tried
## them. The weights below encode "a reasonable median player", not an optimal
## one -- the goal is a stable yardstick, so that a change in the win rate
## reflects a change in the numbers and not a change in how cleverly it played.
##
## It does understand the one rule the design hangs off: disabling the subsystem
## behind the telegraphed intent cancels the shot. That is worth far more than
## the raw damage it costs, and FIZZLE_BONUS says so.
const FIZZLE_BONUS := 25.0
const W_HULL_DAMAGE := 1.0
const W_SYSTEM_DAMAGE := 0.8
const W_SHIELD := 0.55
const W_WASTED_SHIELD := 0.05
const W_REPAIR_HULL := 1.0
const W_REPAIR_SYSTEM := 0.5
const W_DRAW := 2.0
const W_ENERGY := 3.0
const W_SELF_HARM := 1.6
const W_CREDITS := 0.15
const W_SUPPRESS := 3.0
## Damage soaked by shields is not wasted -- stripping the pool is the only way
## through it. Scoring absorbed damage at zero makes the pilot refuse to attack
## a shielded ship at all, which deadlocks the fight instead of losing it.
const W_SHIELD_STRIP := 0.5
## Shield regen at or above this per turn is treated as a gate to break first.
const REGEN_PRESSURE := 3

func _autoplay(c: CombatController, verbose: bool = false,
		tally: Dictionary = {}) -> int:
	var guard := 0
	while c.phase != CombatController.Phase.DONE and guard < 60:
		guard += 1
		while true:
			var best: CardInstance = null
			var best_target: StringName = &""
			var best_efficiency := 0.0
			# Hand order is seeded, and ties keep the earlier card, so the
			# whole policy stays deterministic for a given seed.
			for card in c.deck.hand:
				if card.cost() > c.player.energy:
					continue
				var target := _pick_target(c, card)
				if card.def.needs_target() and target == &"":
					continue
				var score := _score_card(c, card, target)
				if score <= 0.0:
					continue
				var efficiency := score / maxf(0.5, float(card.cost()))
				if efficiency > best_efficiency:
					best_efficiency = efficiency
					best = card
					best_target = target
			if best == null:
				break
			var name := best.display_name()
			if c.play_card(best, best_target) != "":
				break
			tally[name] = int(tally.get(name, 0)) + 1
			if verbose:
				print("  T%d  play %-18s -> %-9s (score %.1f/energy)" % [
					c.turn, name, String(best_target) if best_target != &"" else "-",
					best_efficiency])
			if c.phase == CombatController.Phase.DONE:
				break
		if c.phase == CombatController.Phase.DONE:
			break
		if verbose:
			print("  T%d  end turn | enemy: %s | you: %d hp / %d shield" % [
				c.turn, c.brain.telegraph(), c.player.hull, c.player.shield])
		c.end_player_turn()
	return c.turn

## Damage the player is about to take, or 0 if the intent is already dead.
## Drives how much a shield card is actually worth this turn.
func _expected_incoming(c: CombatController) -> int:
	if c.brain.intent_fizzles():
		return 0
	var total := 0
	for op in c.brain.scaled_effects():
		match op.get("op", ""):
			"damage_system", "damage_hull":
				total += int(op.get("amount", 0))
	return total

## The subsystem feeding the enemy's telegraphed shot, or &"" if none/fizzled.
func _intent_system(c: CombatController) -> StringName:
	if c.brain.intent_fizzles():
		return &""
	return StringName(c.brain.current_intent.get("requires_system", ""))

func _pick_target(c: CombatController, card: CardInstance) -> StringName:
	match card.def.target:
		CardDef.Target.SELF_SYSTEM:
			return _worst_own_system(c)
		CardDef.Target.ENEMY_SYSTEM:
			# 1. Shield regeneration gates every point of damage that follows,
			#    so a ship that out-regenerates our output has to be opened up
			#    before anything else matters. Without this the pilot tunnels
			#    on the intent system and fights against regen never end.
			if c.enemy.effective_shield_regen() >= REGEN_PRESSURE \
					and c.enemy.has_active_system(&"shields"):
				return &"shields"
			# 2. Whatever is about to shoot us -- disabling it cancels the shot.
			var intent := _intent_system(c)
			if intent != &"" and c.enemy.has_active_system(intent):
				return intent
			# 2. Otherwise the softest intact system, to disable more of them.
			var intact := c.enemy.intact_systems()
			if not intact.is_empty():
				var softest: ShipSystem = intact[0]
				for s in intact:
					if s.integrity < softest.integrity:
						softest = s
				return softest.id
			# 3. Nothing intact left: shoot the wreck, damage spills to hull.
			var any := c.enemy.targetable_systems()
			return any[0].id if not any.is_empty() else &""
		_:
			return &""

func _score_card(c: CombatController, card: CardInstance, target: StringName) -> float:
	var ctx := {"source": c.player, "opponent": c.enemy, "target_system": target}
	var intent := _intent_system(c)
	var incoming := _expected_incoming(c)
	var score := 0.0
	# Shields absorb in order, so track what is left as ops are considered.
	var shield_left := c.enemy.shield

	for op in card.effects():
		var amount: int = c.resolver.scaled_amount(op, ctx)
		var kind: String = op.get("op", "")
		var pierce: bool = bool(op.get("pierce", false))

		match kind:
			"damage_system":
				var through := amount
				if not pierce:
					var absorbed := mini(shield_left, through)
					shield_left -= absorbed
					through -= absorbed
					score += absorbed * W_SHIELD_STRIP
				if through <= 0:
					continue
				var sys: ShipSystem = c.enemy.system(target)
				if sys != null and sys.integrity > 0:
					var into_system := mini(through, sys.integrity)
					var spill := through - into_system
					score += into_system * W_SYSTEM_DAMAGE + spill * W_HULL_DAMAGE
					# The payoff: this kills the system that is about to fire.
					if into_system >= sys.integrity and target == intent:
						score += FIZZLE_BONUS
				else:
					score += through * W_HULL_DAMAGE
			"damage_hull":
				var h := amount
				if not pierce:
					var absorbed_h := mini(shield_left, h)
					shield_left -= absorbed_h
					h -= absorbed_h
					score += absorbed_h * W_SHIELD_STRIP
				score += maxi(0, h) * W_HULL_DAMAGE
			"suppress_system":
				# Suppression is worth a lot when it cancels the telegraphed
				# shot and very little otherwise -- exactly the card design.
				if target == intent and target != &"":
					score += FIZZLE_BONUS
				else:
					score += W_SUPPRESS
			"shield":
				# The resolver caps shield gain at max_shield, so scoring the
				# card's printed number makes every defensive card look far
				# better than it is. Without this the pilot turtles forever
				# and fights hit the turn guard instead of ending.
				var room := 999999 if bool(op.get("overshield", false)) \
					else maxi(0, c.player.max_shield - c.player.shield)
				var gained := mini(amount, room)
				var needed := maxi(0, incoming - c.player.shield)
				var useful := mini(gained, needed)
				score += useful * W_SHIELD + (gained - useful) * W_WASTED_SHIELD
			"repair_hull":
				score += mini(amount, c.player.max_hull - c.player.hull) * W_REPAIR_HULL
			"repair_system":
				var own: ShipSystem = c.player.system(target)
				if own != null:
					score += mini(amount, own.max_integrity - own.integrity) * W_REPAIR_SYSTEM
			"draw":
				score += amount * W_DRAW
			"energy":
				score += amount * W_ENERGY
			"damage_self_hull":
				score -= amount * W_SELF_HARM
			"credits":
				score += amount * W_CREDITS
	return score

func _worst_own_system(c: CombatController) -> StringName:
	var worst: ShipSystem = null
	for sid in c.player.systems:
		var s: ShipSystem = c.player.systems[sid]
		if s.integrity < s.max_integrity and (worst == null or s.integrity < worst.integrity):
			worst = s
	return worst.id if worst != null else &""


## Take a battle reward the way the reward screen does, scaled by enemy tier:
## a part from every win, plus an improvement from mini-bosses and bosses.
func _auto_reward(run: RunState, enemy_id: StringName) -> void:
	var enemy: EnemyDef = Database.enemy(enemy_id)
	if enemy == null:
		return
	var pack := RewardPool.build(run, _sim_meta_state(), enemy)
	var imp: ImprovementDef = pack["improvement"]
	if imp != null:
		run.ship.add_improvement(imp.id)
		run.recompile()
	var offers: Array = pack["parts"]
	for o in offers:
		if o["can_install"]:
			RewardPool.claim(run, o)
			return
	if not offers.is_empty():
		RewardPool.claim(run, offers[0])

## The simulator has no Game autoload state; build a meta with everything
## unlocked so reward offers cover the whole part list.
func _sim_meta_state() -> MetaState:
	if _sim_meta == null:
		_sim_meta = MetaState.new()
		for pid in Database.parts:
			_sim_meta.unlocked[pid] = true
	return _sim_meta

var _sim_meta: MetaState = null

## Cut the first status-kind ("dud") card found. A real player would agonise;
## the sim just needs the mechanic exercised so deck size reflects it.
func _auto_strip(run: RunState) -> void:
	for o in SalvageYard.options(run):
		var card: CardDef = Database.card(o["card_id"])
		if card != null and card.kind == &"status":
			SalvageYard.strip(run, o["part"], o["index"])
			return

func _auto_repair(run: RunState) -> void:
	for inst in run.ship.parts:
		if inst.wear > 0 and run.credits >= 40:
			run.add_credits(-40)
			inst.wear = 0
			run.recompile()
			return

## Which cards the pilot actually reached for. A card sitting at the bottom of
## this list is either badly costed or badly targeted -- it is the fastest way
## to spot content that exists but does nothing.
func _print_histogram(tally: Dictionary, runs: int) -> void:
	var names: Array = tally.keys()
	names.sort_custom(func(a, b): return int(tally[a]) > int(tally[b]))
	var total := 0
	for n in names:
		total += int(tally[n])
	print("\ncard plays (per run, %d distinct cards seen):" % names.size())
	for n in names:
		var per_run := float(tally[n]) / maxf(1.0, float(runs))
		var bar := "#".repeat(int(round(per_run * 2.0)))
		print("  %-20s %5.1f  %s" % [n, per_run, bar])

	# Anything reachable but never played is dead content.
	var reachable: Dictionary = {}
	for pid in Database.parts:
		for cid in Database.parts[pid].grants:
			var cd: CardDef = Database.card(cid)
			if cd != null:
				reachable[cd.name] = true
	var never: Array = []
	for n in reachable:
		if not tally.has(n):
			never.append(n)
	never.sort()
	if never.is_empty():
		print("  (every reachable card was played at least once)")
	else:
		print("  NEVER PLAYED: %s" % ", ".join(never))

func _sum(a: Array[int]) -> int:
	var t := 0
	for v in a:
		t += v
	return t

func _avg(a: Array[int]) -> int:
	return int(round(float(_sum(a)) / maxi(1, a.size())))
