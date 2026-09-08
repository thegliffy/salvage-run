class_name StarterShips
extends RefCounted
## Ships the player can begin a run with — hulls worth stealing.
##
## The hull is self-powered so a reactor is an upgrade that buys headroom rather
## than a part you are forced to carry. Each starter begins one part into each
## of its three slot types; the rest of the slots fill from battle rewards.
## Later unlocks can add more ships to steal.

static func brawler() -> ShipLoadout:
	var g := ShipLoadout.new("Brawler")
	g.capacity = {
		ShipLoadout.SLOT_WEAPON: 4,
		ShipLoadout.SLOT_HULL: 3,
		ShipLoadout.SLOT_UTILITY: 4,
	}
	g.base_hull = 30
	g.base_power = 5
	g.base_draw = 5
	g.base_shield = 0
	g.base_shield_regen = 0
	_install(g, &"burst_laser")       # weapon
	_install(g, &"ablative_plating")  # hull — armor, not shields
	_install(g, &"ion_thrusters")     # utility
	return g

## One fewer weapon slot and one fewer energy than the Brawler, with the
## Deflector Mk I as its shield package (10 capacity, +2/turn).
static func tank() -> ShipLoadout:
	var g := ShipLoadout.new("Tank")
	g.capacity = {
		ShipLoadout.SLOT_WEAPON: 3,
		ShipLoadout.SLOT_HULL: 3,
		ShipLoadout.SLOT_UTILITY: 4,
	}
	g.base_hull = 30
	g.base_power = 4
	g.base_draw = 5
	g.base_shield = 0
	g.base_shield_regen = 0
	_install(g, &"burst_laser")
	_install(g, &"deflector_mk1")    # 10 shield / +2 regen
	_install(g, &"ion_thrusters")
	return g

## One weapon, extra utility bays, Deflector shields, and two empty drone bays.
## Launch Attack / Shield drones with cards; they tick at the start of your turn.
static func shepherd() -> ShipLoadout:
	var g := ShipLoadout.new("Shepherd")
	g.capacity = {
		ShipLoadout.SLOT_WEAPON: 1,
		ShipLoadout.SLOT_HULL: 3,
		ShipLoadout.SLOT_UTILITY: 6,
	}
	g.base_hull = 30
	g.base_power = 4
	g.base_draw = 5
	g.base_shield = 0
	g.base_shield_regen = 0
	_install(g, &"burst_laser")
	_install(g, &"deflector_mk1")
	_install(g, &"drone_launcher")
	return g

## Back-compat alias used by older call sites / saves.
static func salvager() -> ShipLoadout:
	return brawler()

static func make(id: StringName) -> ShipLoadout:
	match id:
		&"tank":
			return tank()
		&"shepherd":
			return shepherd()
		_:
			return brawler()

## Title-screen chooser entries: id, label, blurb, unlock_cost (0 = free).
## Tank is the cheapest hull unlock, but costs more than any single part.
static func choices() -> Array:
	return [
		{
			"id": &"brawler",
			"name": "Brawler",
			"blurb": "4 weapons · 5 energy · no shields — bolt them on later",
			"unlock_cost": 0,
		},
		{
			"id": &"tank",
			"name": "Tank",
			"blurb": "3 weapons · 4 energy · Deflector Mk I (10 shield, +2/turn)",
			"unlock_cost": 450,
		},
		{
			"id": &"shepherd",
			"name": "Shepherd",
			"blurb": "1 weapon · 6 utility · Deflector Mk I · two empty drone bays",
			"unlock_cost": 650,
		},
	]

static func choice(ship_id: StringName) -> Dictionary:
	for c in choices():
		if c["id"] == ship_id:
			return c
	return {}

static func unlock_cost(ship_id: StringName) -> int:
	var c := choice(ship_id)
	return int(c.get("unlock_cost", 0)) if not c.is_empty() else 0

static func _install(g: ShipLoadout, part_id: StringName) -> void:
	var p: PartDef = Database.part(part_id)
	if p == null:
		push_error("[StarterShips] missing part '%s'" % part_id)
		return
	if g.install(p) == null:
		push_error("[StarterShips] no free %s slot for '%s'" % [p.slot, part_id])
