class_name StarterShips
extends RefCounted
## Hull layouts the player can begin a run with.
## Kept in code rather than JSON because a layout is structural, not balance
## data -- adding one is a design act, not a tuning pass.

static func salvager() -> HullGrid:
	var g := HullGrid.new(6, 4)
	g.display_name = "Salvager"
	g.base_hull = 30
	g.base_power = 1
	_install(g, &"reactor_mk1", Vector2i(0, 1))
	_install(g, &"burst_laser", Vector2i(2, 0))
	_install(g, &"deflector_mk1", Vector2i(2, 2))
	_install(g, &"ion_thrusters", Vector2i(4, 1))
	return g

static func _install(g: HullGrid, part_id: StringName, at: Vector2i) -> void:
	var p: PartDef = Database.part(part_id)
	if p == null:
		push_error("[StarterShips] missing part '%s'" % part_id)
		return
	if g.place(p, at) == null:
		push_error("[StarterShips] could not place '%s' at %s" % [part_id, at])
