class_name RunState
extends RefCounted
## Everything that exists for the duration of one run and dies with it.
##
## The ship (HullGrid) is the run's centre of gravity: the deck is derived from
## it, damage is recorded on it, and at the end it is sold. There is no separate
## "deck" the player edits.

var seed_value: int = 0
var sector: int = 1
var map: Dictionary = {}
var current_node: int = -1
var credits: int = 0
var ship: HullGrid
var profile: ShipProfile
var cleared_nodes: int = 0
var elites_killed: int = 0
var boss_killed: bool = false
var alive: bool = true
var hull_carryover: int = -1   # hull persists between fights; -1 = full

func start(starting_ship: HullGrid, run_seed: int = -1) -> void:
	seed_value = run_seed if run_seed >= 0 else Rng.new_seed()
	Rng.seed_run(seed_value)
	ship = starting_ship
	sector = 1
	credits = 0
	cleared_nodes = 0
	boss_killed = false
	alive = true
	hull_carryover = -1
	map = MapGenerator.generate(sector)
	current_node = map["entry"]
	recompile()
	EventBus.run_started.emit(seed_value)

## Recompute the combat profile from the ship. Call after ANY ship change.
func recompile() -> void:
	profile = ship.compile()
	if hull_carryover < 0:
		hull_carryover = profile.max_hull
	hull_carryover = mini(hull_carryover, profile.max_hull)

func add_credits(amount: int) -> void:
	credits = maxi(0, credits + amount)
	EventBus.credits_changed.emit(credits)

func install(part: PartDef, at: Vector2i) -> bool:
	var inst := ship.place(part, at)
	if inst == null:
		return false
	recompile()
	return true

func uninstall(inst: PartInstance) -> bool:
	if not ship.remove(inst):
		return false
	recompile()
	return true

## Build a combat for the current node's enemy.
func make_combat(enemy_id: StringName) -> CombatController:
	var enemy_def: EnemyDef = Database.enemy(enemy_id)
	if enemy_def == null:
		push_error("[RunState] unknown enemy '%s'" % enemy_id)
		return null
	var c := CombatController.new()
	c.setup(profile, enemy_def, ship)
	# Carry damage forward between fights, FTL-style.
	c.player.hull = clampi(hull_carryover, 1, c.player.max_hull)
	return c

func finish_combat(c: CombatController) -> void:
	hull_carryover = c.player.hull
	if c.victory:
		cleared_nodes += 1
		add_credits(c.pending_credits)
	else:
		alive = false
	recompile()

func advance_to(node_id: int) -> Dictionary:
	current_node = node_id
	var node: Dictionary = MapGenerator.node_at(map, node_id)
	node["visited"] = true
	EventBus.node_entered.emit(node)
	return node

func options() -> Array:
	return MapGenerator.options_from(map, current_node)

func at_boss() -> bool:
	return MapGenerator.node_at(map, current_node)["type"] == "boss"
