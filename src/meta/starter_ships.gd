class_name StarterShips
extends RefCounted
## Ships the player can begin a run with.
##
## The hull is self-powered (base_power 5) so a reactor is an upgrade that buys
## headroom rather than a part you are forced to carry. The Salvager starts one
## part into each of its three slot types, leaving eight slots to fill from
## battle rewards.

static func salvager() -> ShipLoadout:
	var g := ShipLoadout.new("Salvager")
	g.capacity = {
		ShipLoadout.SLOT_WEAPON: 4,
		ShipLoadout.SLOT_HULL: 3,
		ShipLoadout.SLOT_UTILITY: 4,
	}
	g.base_hull = 30
	g.base_power = 5
	g.base_draw = 5
	_install(g, &"burst_laser")      # weapon
	_install(g, &"deflector_mk1")    # hull
	_install(g, &"ion_thrusters")    # utility
	return g

static func _install(g: ShipLoadout, part_id: StringName) -> void:
	var p: PartDef = Database.part(part_id)
	if p == null:
		push_error("[StarterShips] missing part '%s'" % part_id)
		return
	if g.install(p) == null:
		push_error("[StarterShips] no free %s slot for '%s'" % [p.slot, part_id])
