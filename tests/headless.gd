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
	_test_stream_isolation()
	_test_targeting_rules()
	_test_map_navigation()
	_test_combat_fizzle()
	_test_deck_cycling()
	_test_damage_pipeline()
	_test_overshield()
	_test_shield_dump()
	_test_strip()
	_test_rewards()
	_test_valuation()
	_test_ui_copy()
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
	var burst: PartDef = Database.part(&"burst_laser")
	_eq("part icon defaults to <id>.png", burst.icon, "burst_laser.png")
	var blank_icon: PackedStringArray = []
	for pid in Database.parts:
		if Database.parts[pid].icon == "":
			blank_icon.append(String(pid))
	_check("every part has an icon filename", blank_icon.is_empty(), str(blank_icon))
	var ov := PartDef.new()
	_eq("explicit part icon is kept", ov.from_dict(&"test_mod", {
		"name": "Test", "slot": "utility", "icon": "other.png",
	}), "")
	_eq("explicit part icon wins over default", ov.icon, "other.png")
	_check("missing module PNG is null-safe",
		UITheme.art("res://assets/modules/not_a_real_part.png") == null)

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
	_check("has armor system", prof.has_system(&"armor"))
	_check("brawler starts with no shield capacity", prof.max_shield == 0)
	_eq("starter deck is 3 parts x 3 cards", prof.deck.size(), 9)
	_eq("laser granted twice by burst laser", prof.deck.count(&"laser_burst"), 2)
	_eq("starter ship is the Brawler", prof.display_name, "Brawler")
	_check("hull includes base", prof.max_hull >= 30)
	_check("ship is self-powered without a reactor", prof.power > 0)
	_check("starter is within its power budget", prof.warnings.is_empty(),
		str(prof.warnings))

	var tank_ship := StarterShips.tank()
	var tank := tank_ship.compile()
	_eq("tank name", tank.display_name, "Tank")
	_eq("tank has one fewer weapon slot", tank_ship.slot_capacity(ShipLoadout.SLOT_WEAPON), 3)
	_eq("tank has one fewer energy", tank.power, 4)  # base 4, draw 4, no deficit
	_eq("tank deflector is 10 shield", tank.max_shield, 10)
	_eq("tank deflector is +2 regen", tank.shield_regen, 2)
	_check("tank starts with the Deflector Mk I", tank.has_system(&"shields"))
	_eq("tank still starts with three parts", tank_ship.parts.size(), 3)
	_check("tank stays in its power budget", tank.warnings.is_empty(), str(tank.warnings))

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

func _test_stream_isolation() -> void:
	print("rng stream isolation")
	# Consuming one stream must not disturb another, or "same seed replays
	# identically" only holds for an identical sequence of player decisions.
	Rng.seed_run(4242)
	var baseline: Array[int] = []
	for i in 8:
		baseline.append(Rng.stream(&"combat").randi_range(1, 1000))

	Rng.seed_run(4242)
	for i in 20:
		Rng.stream(&"evasion").randi_range(1, 100)       # dodge rolls
		Rng.stream(&"target_fallback").randi_range(1, 5) # auto-target picks
	var after: Array[int] = []
	for i in 8:
		after.append(Rng.stream(&"combat").randi_range(1, 1000))
	_eq("evasion and target picks leave the deck stream untouched", after, baseline)

	# The target fallback fires for player actions too, so it must not share a
	# stream with enemy intent selection.
	Rng.seed_run(99)
	var ai_baseline: Array[int] = []
	for i in 5:
		ai_baseline.append(Rng.stream(&"enemy_ai").randi_range(1, 1000))
	Rng.seed_run(99)
	for i in 15:
		Rng.stream(&"target_fallback").randi_range(1, 5)
	var ai_after: Array[int] = []
	for i in 5:
		ai_after.append(Rng.stream(&"enemy_ai").randi_range(1, 1000))
	_eq("target fallback does not shift enemy intents", ai_after, ai_baseline)

func _test_targeting_rules() -> void:
	print("targeting rules")
	Rng.seed_run(13)
	var ship := StarterShips.salvager()
	var c := CombatController.new()
	c.setup(ship.compile(), Database.enemy(&"raider"), ship)

	# Hull is a legal target for damage, but not for pure suppression: aiming
	# EMP Pulse at bare hull used to spend the energy and do nothing at all.
	_check("a damage card may target the hull",
		Database.card(&"laser_burst").can_target_hull())
	_check("a suppression card may not", not Database.card(&"emp_pulse").can_target_hull())
	_check("a mixed card may (its damage still lands)",
		Database.card(&"weak_point").can_target_hull())

	var emp := CardInstance.create(Database.card(&"emp_pulse"))
	c.deck.hand.append(emp)
	c.player.energy = 9
	var before: int = c.player.energy
	var err := c.play_card(emp, &"hull")
	_check("playing suppression at the hull is refused", err != "", err)
	_eq("and costs no energy", c.player.energy, before)

	var laser := CardInstance.create(Database.card(&"laser_burst"))
	c.deck.hand.append(laser)
	c.enemy.shield = 0
	c.enemy.evasion = 0
	var hull_before: int = c.enemy.hull
	_eq("damage at the hull is allowed", c.play_card(laser, &"hull"), "")
	_check("and lands on the hull", c.enemy.hull < hull_before)

	# An op with no valid subsystem must say so rather than vanishing.
	var seen := {"hit": false}
	var probe := func(ev: Dictionary):
		if ev.get("type", "") == "no_target":
			seen["hit"] = true
	EventBus.effect_resolved.connect(probe)
	c.resolver.run([{"op": "suppress_system"}],
		{"source": c.player, "opponent": c.enemy, "target_system": &"hull"})
	EventBus.effect_resolved.disconnect(probe)
	_check("an untargetable suppression reports no_target", seen["hit"])

func _test_map_navigation() -> void:
	print("map navigation")
	Rng.seed_run(8)
	var run := RunState.new()
	run.start(StarterShips.salvager(), 8)
	var start: int = run.current_node
	var count: int = run.map["nodes"].size()

	_check("valid node accepted", run.is_valid_node(start))
	_check("negative id rejected", not run.is_valid_node(-1))
	_check("out-of-range id rejected", not run.is_valid_node(count + 50))

	# The sim and the UI share this path; a bad index used to throw.
	_eq("advance_to refuses a bad id", run.advance_to(count + 50), {})
	_eq("and does not move the player", run.current_node, start)
	_eq("advance_to refuses a negative id", run.advance_to(-3), {})
	_eq("still at the start", run.current_node, start)
	_check("at_boss is safe on a bogus position", not _boss_check_safe(run, count + 99))

func _boss_check_safe(run: RunState, bogus: int) -> bool:
	var keep: int = run.current_node
	run.current_node = bogus
	var result: bool = run.at_boss()
	run.current_node = keep
	return result

func _test_combat_fizzle() -> void:
	print("combat: hull targeting + soft systems")
	Rng.seed_run(7)
	var ship := StarterShips.salvager()
	var c := CombatController.new()
	c.setup(ship.compile(), Database.enemy(&"scout_drone"), ship)

	_check("combat starts on player turn", c.phase == CombatController.Phase.PLAYER)
	_check("player drew a hand", c.deck.hand.size() > 0)
	_check("enemy telegraphs an intent", c.brain.telegraph() != "")
	var info: Dictionary = c.brain.telegraph_info()
	_check("telegraph info names the shot", String(info.get("title", "")) != "")
	_check("telegraph info reports a status", String(info.get("status", "")) != "")
	_check("telegraph info names a source system", String(info.get("system", "")) != "")
	_eq("enemy systems are soft (5 HP)", c.enemy.system(&"weapons").max_integrity, 5)
	_eq("enemy auto-repairs", c.enemy.system_regen, 2)
	_eq("player has no system regen by default", c.player.system_regen, 0)

	# Destroy the enemy weapons system — the shot cannot fire while offline.
	var weapons: ShipSystem = c.enemy.system(&"weapons")
	weapons.take_damage(weapons.max_integrity)
	_check("weapons offline after lethal damage", not weapons.is_active())

	c.brain.current_intent = c.enemy_intent_by_id(&"pulse")
	_check("weapons intent is offline when weapons are down", c.brain.intent_offline())

	var hull_before := c.player.hull
	c.end_player_turn()
	_eq("offline intent deals no damage", c.player.hull, hull_before)
	# Damaged this cycle, so no auto-repair on that enemy turn.
	_eq("no repair on the turn after being destroyed", weapons.integrity, 0)

	# A live system does fire.
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

	# Hull is a legal target: damage goes through shields straight into hull.
	Rng.seed_run(8)
	var ship_h := StarterShips.salvager()
	var ch := CombatController.new()
	ch.setup(ship_h.compile(), Database.enemy(&"raider"), ship_h)
	ch.enemy.evasion = 0
	ch.enemy.shield = 0
	var w_before: int = ch.enemy.system(&"weapons").integrity
	var h_before := ch.enemy.hull
	ch.resolver.run([{"op": "damage_system", "amount": 9}],
		{"source": ch.player, "opponent": ch.enemy, "target_system": &"hull"})
	_eq("hull target leaves subsystems alone", ch.enemy.system(&"weapons").integrity, w_before)
	_eq("hull target deals full damage to hull", ch.enemy.hull, h_before - 9)

	# Auto-repair: undamaged systems recover 2 HP at the start of their turn.
	Rng.seed_run(9)
	var ship_r := StarterShips.salvager()
	var cr := CombatController.new()
	cr.setup(ship_r.compile(), Database.enemy(&"scout_drone"), ship_r)
	var eng: ShipSystem = cr.enemy.system(&"engines")
	eng.take_damage(3)
	_eq("engines chipped", eng.integrity, 2)
	# Clear the damaged flag as if a full cycle passed without further hits.
	eng.damaged_since_tick = false
	eng.tick_auto_repair()
	_eq("undamaged engines auto-repair 2", eng.integrity, 4)
	eng.damaged_since_tick = true
	eng.tick_auto_repair()
	_eq("damaged engines skip auto-repair", eng.integrity, 4)

	# Rare improvement grants player system regen.
	var ship_n := StarterShips.salvager()
	ship_n.add_improvement(&"damage_control_nanites")
	var prof_n := ship_n.compile()
	_eq("nanites grant system_regen", prof_n.system_regen, 2)
	var cn := CombatController.new()
	cn.setup(prof_n, Database.enemy(&"scout_drone"), ship_n)
	_eq("player systems inherit auto-repair", cn.player.system(&"weapons").auto_repair, 2)

	# Regression: a fully disabled enemy must still be killable.
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
		if inst.def.system == &"weapons" and inst.wear > 0:
			worn = true
	_check("destroying a subsystem wears its part", worn)
	_check("weapons system is offline", not wsys.is_active())

func _test_overshield() -> void:
	print("overshield")
	Rng.seed_run(12)
	var ship := StarterShips.brawler()
	var c := CombatController.new()
	c.setup(ship.compile(), Database.enemy(&"raider"), ship)
	_eq("brawler starts at 0/0 shield", c.player.shield, 0)
	_eq("brawler max shield is 0", c.player.max_shield, 0)

	# Gain with no capacity — the whole pool is overshield.
	c.resolver.run([{"op": "shield", "amount": 8}],
		{"source": c.player, "opponent": c.enemy})
	_eq("shield gain above capacity is kept", c.player.shield, 8)
	_eq("overshield reports the excess", c.player.overshield(), 8)

	# Overshield still absorbs damage.
	c.enemy.evasion = 0
	c.resolver.run([{"op": "damage_hull", "amount": 3, "unavoidable": true}],
		{"source": c.enemy, "opponent": c.player})
	_eq("overshield absorbs damage", c.player.shield, 5)
	_eq("hull untouched while overshield holds", c.player.hull, c.player.max_hull)

	# Bolt on capacity mid-fight and gain past it.
	c.player.max_shield = 4
	c.player.shield = 4
	c.resolver.run([{"op": "shield", "amount": 5}],
		{"source": c.player, "opponent": c.enemy})
	_eq("gain past capacity becomes overshield", c.player.shield, 9)
	_eq("overshield is current - max", c.player.overshield(), 5)

	# Start of player turn clears overshield, then regen fills toward cap.
	c.player.shield_regen = 0
	c.begin_player_turn()
	_eq("overshield cleared at turn start", c.player.shield, 4)
	_eq("no overshield remains", c.player.overshield(), 0)

	c.player.shield = 9
	c.player.shield_regen = 2
	c.begin_player_turn()
	_eq("regen applies after overshield drop", c.player.shield, 4)

func _test_shield_dump() -> void:
	print("shield dump")
	Rng.seed_run(44)
	var ship := StarterShips.tank()
	var c := CombatController.new()
	c.setup(ship.compile(), Database.enemy(&"raider"), ship)
	c.enemy.evasion = 0
	c.enemy.shield = 0
	var hull_before := c.enemy.hull

	c.player.shield = 14
	c.resolver.run([{
		"op": "damage_system",
		"amount": 0,
		"pierce": true,
		"spend_own_shield": true,
		"unavoidable": true,
	}], {"source": c.player, "opponent": c.enemy, "target_system": &"hull"})
	_eq("dump spends all shield", c.player.shield, 0)
	_eq("dump deals spent shield as damage", c.enemy.hull, hull_before - 14)

	# Flat bonus stacks on top of the dump.
	c.player.shield = 5
	hull_before = c.enemy.hull
	c.resolver.run([{
		"op": "damage_system",
		"amount": 3,
		"pierce": true,
		"spend_own_shield": true,
		"unavoidable": true,
	}], {"source": c.player, "opponent": c.enemy, "target_system": &"hull"})
	_eq("dump plus printed amount", c.enemy.hull, hull_before - 8)
	_eq("shield emptied after bonus dump", c.player.shield, 0)

	# Empty bank is a no-op hit.
	hull_before = c.enemy.hull
	c.resolver.run([{
		"op": "damage_system",
		"amount": 0,
		"pierce": true,
		"spend_own_shield": true,
		"unavoidable": true,
	}], {"source": c.player, "opponent": c.enemy, "target_system": &"hull"})
	_eq("zero-shield dump deals nothing", c.enemy.hull, hull_before)

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
	_eq("first strip credit cost is 40", int(opts[0]["credit_cost"]),
		SalvageYard.STRIP_CREDIT_BASE)
	_eq("cannot afford first strip with 0 credits", opts[0]["can_afford"], false)

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
	_check("strip refused without credits",
		SalvageYard.strip(run, target_inst, target_index) != "")
	_eq("credits unchanged on refuse", run.credits, 0)
	_check("part not stripped on refuse", not target_inst.is_stripped())
	_eq("deck unchanged on refuse", run.profile.deck.size(), deck_before)

	run.add_credits(SalvageYard.STRIP_CREDIT_BASE)
	opts = SalvageYard.options(run)
	_eq("can afford after funding", opts[0]["can_afford"], true)
	var credits_before: int = run.credits
	_eq("strip succeeds", SalvageYard.strip(run, target_inst, target_index), "")
	_eq("deck is one card lighter", run.profile.deck.size(), deck_before - 1)
	_check("the stripped card is gone", not run.profile.deck.has(&"overheat"))
	_eq("strip debit first cost", run.credits,
		credits_before - SalvageYard.STRIP_CREDIT_BASE)
	_check("strip still cuts sale value", target_inst.sale_value() < value_before)
	_eq("sale penalty is 25%", target_inst.sale_value(),
		int(round(float(value_before) * (1.0 - PartInstance.STRIP_VALUE_PENALTY))))

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
	_eq("second strip on same mount names the part, not credits",
		SalvageYard.strip(run, target_inst, 0).contains("stripped"), true)
	for o in SalvageYard.options(run):
		if o["part"] == target_inst:
			_check("stripped part offers no further mounts", false)
	_check("stripped part drops out of the options list", true)

	# Cost scales with installed stripped mounts: 40, then 65.
	_eq("second strip costs 65", SalvageYard.credit_cost(run),
		SalvageYard.STRIP_CREDIT_BASE + SalvageYard.STRIP_CREDIT_STEP)
	var other: PartInstance = null
	for inst in run.ship.parts:
		if inst.can_strip():
			other = inst
			break
	_check("another mount is still strippable", other != null)
	_check("second strip refused until funded",
		SalvageYard.strip(run, other, 0) != "")
	_eq("credits stay 0 after unaffordable second strip", run.credits, 0)
	run.add_credits(SalvageYard.credit_cost(run))
	var second_cost := SalvageYard.credit_cost(run)
	var credits_mid: int = run.credits
	_eq("second strip succeeds", SalvageYard.strip(run, other, 0), "")
	_eq("second strip debit 65", run.credits, credits_mid - second_cost)

	# Thinning has a floor: you can never cut past two thirds.
	var floor_run := RunState.new()
	floor_run.start(StarterShips.salvager(), 32)
	var triple := SalvageYard.STRIP_CREDIT_BASE \
		+ (SalvageYard.STRIP_CREDIT_BASE + SalvageYard.STRIP_CREDIT_STEP) \
		+ (SalvageYard.STRIP_CREDIT_BASE + SalvageYard.STRIP_CREDIT_STEP * 2)
	floor_run.add_credits(triple)
	var floor_credits: int = floor_run.credits
	for inst in floor_run.ship.parts:
		SalvageYard.strip(floor_run, inst, 0)
	_eq("every part stripped once", floor_run.profile.deck.size(), 6)
	_eq("three strips cost 40+65+90", floor_run.credits, floor_credits - triple)
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

	# Skipping a part offer field-repairs 15% of max hull.
	run.hull_carryover = 10
	var max_h := run.profile.max_hull
	var expected := mini(int(ceil(float(max_h) * 0.15)), max_h - 10)
	var healed := RewardPool.skip_for_repair(run)
	_eq("skip repairs 15% of max hull", healed, expected)
	_eq("hull carryover raised", run.hull_carryover, 10 + expected)
	run.hull_carryover = max_h
	_eq("skip heals nothing at full hull", RewardPool.skip_for_repair(run), 0)

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

func _test_ui_copy() -> void:
	print("ui copy")
	var ship := StarterShips.salvager()
	var prof := ship.compile()
	_check("starter deck is non-empty", prof.deck.size() > 0)
	var card := CardInstance.create(Database.card(prof.deck[0]))
	var tip := UITheme.card_tip(card, 0)
	_check("card tip names the card", tip.contains(card.display_name()))
	_check("card tip has a COST section", tip.contains("COST"))
	_check("card tip has a RULES section", tip.contains("RULES"))
	var pierce := CardInstance.create(Database.card(&"breach_missile"))
	_check("card tip defines pierce", UITheme.card_tip(pierce).contains("Ignores shields"))
	var bud := ship.power_budget()
	_check("power tip mentions energy", UITheme.power_tip(bud).contains("energy"))
	var part: PartDef = ship.parts[0].def
	_check("part tip names the part", UITheme.part_tip(part).contains(part.name))
	var mod_icon := UITheme.module_icon(part, 80)
	_check("module icon is a TextureRect", mod_icon is TextureRect)
	_eq("module icon keep-aspect", mod_icon.stretch_mode,
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	if mod_icon.texture != null:
		_eq("module icon class size at 720p", int(mod_icon.custom_minimum_size.x), 80)
	else:
		_check("module icon hides when PNG is missing", not mod_icon.visible)
	mod_icon.free()
	var popup := UITheme.make_tooltip("Title\n---\nBody line")
	_check("themed tooltip builds a control", popup is Control)
	popup.free()
	var warn_tip := UITheme.make_tooltip("@warn\n⚡ DEFICIT 2\n---\ncuts energy every turn.")
	_check("deficit tooltip uses warn border",
		(warn_tip.get_theme_stylebox("panel") as StyleBoxFlat).border_color == UITheme.WARN)
	warn_tip.free()
	var live := UITheme.intent_style(false)
	_check("live intent uses warn border", live.border_color == UITheme.WARN)
	_eq("live intent border width", live.border_width_top, 2)
	var silenced := UITheme.intent_style(true)
	_check("offline intent uses dim border", silenced.border_color == UITheme.TEXT_DIM)
	_eq("offline intent border width", silenced.border_width_top, 1)
	var def_panel := UITheme.deficit_panel(2, "cuts energy every fight.")
	_check("deficit panel builds", def_panel is PanelContainer)
	def_panel.free()
	var note := UITheme.energy_note(4, 3)
	_check("energy drop note is warn", note.get_theme_color("font_color") == UITheme.WARN)
	note.free()
	var btn := UITheme.button("GO")
	_check("buttons meet touch floor", btn.custom_minimum_size.y >= 48)
	UITheme.row_cta(btn)
	_check("row CTA does not stretch vertically", btn.size_flags_vertical == Control.SIZE_SHRINK_BEGIN)
	btn.free()

func _test_meta_progression() -> void:
	print("meta")
	var meta := MetaState.new()
	meta.grant_starting_unlocks()
	_check("starters unlocked", meta.unlocked.size() > 0)
	_check("brawler starts unlocked", meta.is_ship_unlocked(&"brawler"))
	_check("tank starts locked", not meta.is_ship_unlocked(&"tank"))
	_check("tank is the cheapest ship unlock", meta.unlockable_ships().size() >= 1
		and meta.unlockable_ships()[0]["id"] == &"tank")
	_eq("tank unlock cost", StarterShips.unlock_cost(&"tank"), 450)
	var dearest_part := 0
	for p in meta.unlockable():
		dearest_part = maxi(dearest_part, p.unlock_cost)
	_check("tank costs more than every locked part",
		StarterShips.unlock_cost(&"tank") > dearest_part)

	_check("cannot afford tank with no salvage", not meta.can_afford_ship(&"tank"))
	meta.salvage = StarterShips.unlock_cost(&"tank")
	_check("tank unlock succeeds when affordable", meta.unlock_ship(&"tank"))
	_eq("tank unlock spends salvage", meta.salvage, 0)
	_check("tank now unlocked", meta.is_ship_unlocked(&"tank"))
	_check("cannot unlock tank twice", not meta.unlock_ship(&"tank"))

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
	_check("save round-trip keeps ship unlocks", meta2.is_ship_unlocked(&"tank"))
	_eq("save round-trip keeps salvage", meta2.salvage, meta.salvage)

	# Old saves without unlocked_ships still get free starters.
	var meta3 := MetaState.new()
	meta3.from_dict({"salvage": 0, "unlocked": []})
	_check("legacy save still unlocks brawler", meta3.is_ship_unlocked(&"brawler"))
	_check("legacy save keeps tank locked", not meta3.is_ship_unlocked(&"tank"))

func _test_map() -> void:
	print("map")
	Rng.seed_run(99)
	var m := MapGenerator.generate(1)
	_eq("layer count (start + 15 stops + boss)", m["by_layer"].size(),
		MapGenerator.STOPS_BEFORE_BOSS + 2)
	_eq("stops field", m["stops"], MapGenerator.STOPS_BEFORE_BOSS)
	_check("single entry", m["by_layer"][0].size() == 1)
	_check("entry is start", m["nodes"][m["entry"]]["type"] == "start")
	_check("boss is last", m["nodes"].back()["type"] == "boss")
	_check("entry marked visited", m["nodes"][m["entry"]]["visited"] == true)

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

	# Combat-bearing nodes carry an enemy id assigned at generation.
	for node in m["nodes"]:
		var t: String = node["type"]
		if t == "combat" or t == "elite" or t == "boss":
			_check("enemy set on %s" % t, StringName(node["enemy"]) != &"")
			_check("enemy exists for %s" % t, Database.enemy(node["enemy"]) != null)

	# Across many seeds the stop-layer mix should land near the design weights.
	var counts := {"combat": 0, "shop": 0, "elite": 0, "chest": 0}
	var total_stops := 0
	for s in 40:
		Rng.seed_run(1000 + s)
		var sample := MapGenerator.generate(1)
		for node2 in sample["nodes"]:
			var t2: String = node2["type"]
			if counts.has(t2):
				counts[t2] += 1
				total_stops += 1
	_check("stop nodes rolled", total_stops > 0)
	if total_stops > 0:
		var combat_share := float(counts["combat"]) / float(total_stops)
		_check("combat near 70%% (got %.0f%%)" % (combat_share * 100.0),
			combat_share > 0.55 and combat_share < 0.85)

	Rng.seed_run(99)
	var m2 := MapGenerator.generate(1)
	_eq("map is deterministic for a seed", m2["nodes"].size(), m["nodes"].size())

	# Chest reward returns an improvement the ship does not already have.
	var run := RunState.new()
	run.start(StarterShips.salvager(), 42)
	var before := run.ship.improvements.duplicate()
	var chest_imp: ImprovementDef = RewardPool.chest_improvement(run)
	_check("chest yields an improvement", chest_imp != null)
	if chest_imp != null:
		_check("chest improvement not already installed", before.find(chest_imp.id) == -1)

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
## Soft-disabling the firing subsystem is still valuable (silence for a turn
## before auto-repair), but hull damage is the primary win condition.
const OFFLINE_BONUS := 12.0
const W_HULL_DAMAGE := 1.35
const W_SYSTEM_DAMAGE := 0.55
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

## Damage the player is about to take, or 0 if the intent is already offline.
## Drives how much a shield card is actually worth this turn.
func _expected_incoming(c: CombatController) -> int:
	if c.brain.intent_offline():
		return 0
	var total := 0
	for op in c.brain.scaled_effects():
		match op.get("op", ""):
			"damage_system", "damage_hull":
				total += int(op.get("amount", 0))
	return total

## The subsystem feeding the enemy's telegraphed shot, or &"" if none/offline.
func _intent_system(c: CombatController) -> StringName:
	if c.brain.intent_offline():
		return &""
	return StringName(c.brain.current_intent.get("requires_system", ""))

func _pick_target(c: CombatController, card: CardInstance) -> StringName:
	match card.def.target:
		CardDef.Target.SELF_SYSTEM:
			return _worst_own_system(c)
		CardDef.Target.ENEMY_SYSTEM:
			# 1. High shield regen gates everything — soft-disable shields first.
			if c.enemy.effective_shield_regen() >= REGEN_PRESSURE \
					and c.enemy.has_active_system(&"shields"):
				return &"shields"
			# 2. Incoming threat this turn: soft-disable the firing system.
			var intent := _intent_system(c)
			if intent != &"" and c.enemy.has_active_system(intent) \
					and c.enemy.system(intent).integrity <= 5:
				return intent
			# 3. Default: shoot the hull. Soft systems are optional control.
			return &"hull"
		_:
			return &""

func _score_card(c: CombatController, card: CardInstance, target: StringName) -> float:
	var ctx := {"source": c.player, "opponent": c.enemy, "target_system": target}
	var intent := _intent_system(c)
	var incoming := _expected_incoming(c)
	var score := 0.0
	# Shields absorb in order, so track what is left as ops are considered.
	var shield_left := c.enemy.shield
	var own_shield := c.player.shield

	for op in card.effects():
		var amount: int = c.resolver.scaled_amount(op, ctx)
		var kind: String = op.get("op", "")
		var pierce: bool = bool(op.get("pierce", false))
		if bool(op.get("spend_own_shield", false)):
			# Dump current shield into the hit; penalize cover we still needed.
			var dumped := own_shield
			var needed_cover := maxi(0, incoming - 0)
			score -= mini(dumped, needed_cover) * W_SHIELD
			amount += dumped
			own_shield = 0

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
				if target == &"hull":
					score += through * W_HULL_DAMAGE
					continue
				var sys: ShipSystem = c.enemy.system(target)
				if sys != null and sys.integrity > 0:
					var into_system := mini(through, sys.integrity)
					var spill := through - into_system
					score += into_system * W_SYSTEM_DAMAGE + spill * W_HULL_DAMAGE
					# Soft-disable the system that is about to fire.
					if into_system >= sys.integrity and target == intent:
						score += OFFLINE_BONUS
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
				if target == intent and target != &"":
					score += OFFLINE_BONUS
				else:
					score += W_SUPPRESS
			"shield":
				# Excess above max_shield is overshield until next turn, so the
				# printed amount is always reachable. Score only what covers
				# incoming damage this turn as fully useful.
				var gained := amount
				var needed := maxi(0, incoming - own_shield)
				var useful := mini(gained, needed)
				score += useful * W_SHIELD + (gained - useful) * W_WASTED_SHIELD
				own_shield += gained
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
		if not bool(o.get("can_afford", false)):
			continue
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
