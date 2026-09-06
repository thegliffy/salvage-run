class_name ShipView
extends Control
## Procedural side-view of the stolen ship.
##
## The chassis is always there. Each installed part bolts on as a module in a
## slot-typed hardpoint (weapons forward/top, hull plating mid-body, utilities
## aft). Calling refresh() with a newly-added part uid plays a short bolt-on
## pop so the reward screen can show the ship growing as you pick hardware.

signal part_clicked(part_uid: int)

const SLOT_COLOUR := {
	&"weapon": UITheme.HOSTILE,
	&"hull": UITheme.ACCENT,
	&"utility": UITheme.GOOD,
}

var _ship: ShipLoadout
var _modules: Array = []          # [{uid, slot, index, def, wrecked, stripped}]
var _animating_uid: int = -1
var _anim_t: float = 0.0
var _pulse: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(360, 160)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _process(delta: float) -> void:
	_pulse += delta
	if _animating_uid >= 0:
		_anim_t = mini(1.0, _anim_t + delta * 2.8)
		if _anim_t >= 1.0:
			_animating_uid = -1
		queue_redraw()
	elif int(_pulse * 8.0) % 2 == 0:
		# Cheap idle shimmer without redrawing every frame aggressively.
		pass

## Rebuild from the current loadout. Pass `animate_uid` to pop that part in.
func refresh(ship: ShipLoadout, animate_uid: int = -1) -> void:
	_ship = ship
	_modules.clear()
	if ship == null:
		queue_redraw()
		return
	var by_slot := {
		ShipLoadout.SLOT_WEAPON: 0,
		ShipLoadout.SLOT_HULL: 0,
		ShipLoadout.SLOT_UTILITY: 0,
	}
	for inst in ship.parts:
		var slot: StringName = inst.def.slot
		var idx: int = int(by_slot.get(slot, 0))
		by_slot[slot] = idx + 1
		_modules.append({
			"uid": inst.uid,
			"slot": slot,
			"index": idx,
			"def": inst.def,
			"wrecked": inst.is_wrecked(),
			"stripped": inst.is_stripped(),
			"name": inst.def.name,
		})
	if animate_uid >= 0:
		_animating_uid = animate_uid
		_anim_t = 0.0
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Soft bay backdrop
	draw_rect(r, Color(0.04, 0.07, 0.1, 1.0))
	_draw_grid(r)

	var hull := _hull_rect(r)
	_draw_chassis(hull)

	# Empty hardpoint ghosts so free slots are readable.
	if _ship != null:
		for slot in ShipLoadout.SLOT_TYPES:
			var cap := _ship.slot_capacity(slot)
			var used := _ship.installed_in(slot).size()
			for i in cap:
				if i >= used:
					_draw_hardpoint_ghost(hull, slot, i)

	for m in _modules:
		_draw_module(hull, m)

	# Nameplate
	if _ship != null:
		var label := _ship.display_name
		var font := UITheme.font("SemiBold")
		draw_string(font, Vector2(12, size.y - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			UITheme.TEXT_DIM)

func _draw_grid(r: Rect2) -> void:
	var c := Color(0.12, 0.18, 0.24, 0.35)
	var step := 18.0
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), c, 1.0)
		x += step
	var y := r.position.y
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), c, 1.0)
		y += step

func _hull_rect(r: Rect2) -> Rect2:
	var margin := 18.0
	var h := mini(72.0, r.size.y * 0.42)
	var w := r.size.x - margin * 2.0
	var y := r.position.y + (r.size.y - h) * 0.42
	return Rect2(r.position.x + margin, y, w, h)

func _draw_chassis(hull: Rect2) -> void:
	# Main body — stretched hex-ish side profile.
	var pts := PackedVector2Array([
		hull.position + Vector2(hull.size.x * 0.08, hull.size.y * 0.25),
		hull.position + Vector2(hull.size.x * 0.72, hull.size.y * 0.05),
		hull.position + Vector2(hull.size.x * 0.96, hull.size.y * 0.45),
		hull.position + Vector2(hull.size.x * 0.78, hull.size.y * 0.92),
		hull.position + Vector2(hull.size.x * 0.18, hull.size.y * 0.88),
		hull.position + Vector2(hull.size.x * 0.02, hull.size.y * 0.55),
	])
	draw_colored_polygon(pts, Color("1a2836"))
	# Cockpit canopy near the nose
	var canopy := PackedVector2Array([
		hull.position + Vector2(hull.size.x * 0.70, hull.size.y * 0.18),
		hull.position + Vector2(hull.size.x * 0.88, hull.size.y * 0.38),
		hull.position + Vector2(hull.size.x * 0.74, hull.size.y * 0.48),
		hull.position + Vector2(hull.size.x * 0.64, hull.size.y * 0.28),
	])
	draw_colored_polygon(canopy, Color("29b6f6").darkened(0.35))
	# Outline
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], UITheme.ACCENT_DIM, 2.0, true)
	# Engine glow stub (always present; thruster parts amplify it)
	var exhaust := hull.position + Vector2(hull.size.x * 0.02, hull.size.y * 0.55)
	var glow := 0.45 + 0.15 * sin(_pulse * 4.0)
	draw_circle(exhaust, 7.0, Color(0.2, 0.7, 1.0, glow * 0.35))
	draw_circle(exhaust, 3.5, Color(0.7, 0.95, 1.0, glow))

func _hardpoint(hull: Rect2, slot: StringName, index: int) -> Vector2:
	match slot:
		ShipLoadout.SLOT_WEAPON:
			# Along the dorsal ridge, forward-biased.
			var t := 0.55 - index * 0.11
			return hull.position + Vector2(hull.size.x * t, hull.size.y * 0.08)
		ShipLoadout.SLOT_HULL:
			# Belly / mid plating.
			var t2 := 0.28 + index * 0.16
			return hull.position + Vector2(hull.size.x * t2, hull.size.y * 0.78)
		_:
			# Utility: aft cluster and underside pods.
			var t3 := 0.12 + index * 0.10
			return hull.position + Vector2(hull.size.x * t3, hull.size.y * (0.25 if index % 2 == 0 else 0.70))

func _draw_hardpoint_ghost(hull: Rect2, slot: StringName, index: int) -> void:
	var p := _hardpoint(hull, slot, index)
	var c: Color = SLOT_COLOUR.get(slot, UITheme.TEXT_FAINT)
	c.a = 0.25
	draw_arc(p, 9.0, 0.0, TAU, 20, c, 1.5, true)

func _draw_module(hull: Rect2, m: Dictionary) -> void:
	var p := _hardpoint(hull, m["slot"], int(m["index"]))
	var scale := 1.0
	var alpha := 1.0
	if int(m["uid"]) == _animating_uid:
		# Pop in from above with a brief overshoot.
		var t := _anim_t
		var ease := 1.0 - pow(1.0 - t, 3.0)
		scale = lerpf(0.2, 1.0, ease) * lerpf(1.25, 1.0, ease)
		alpha = ease
		p.y -= lerpf(28.0, 0.0, ease)

	var base: Color = SLOT_COLOUR.get(m["slot"], UITheme.ACCENT)
	if m["wrecked"]:
		base = UITheme.TEXT_FAINT
	base.a = alpha

	match String(m["slot"]):
		"weapon":
			_draw_weapon(p, base, scale, m)
		"hull":
			_draw_armor(p, base, scale, m)
		_:
			_draw_utility(p, base, scale, m)

func _draw_weapon(p: Vector2, colour: Color, scale: float, m: Dictionary) -> void:
	var w := 22.0 * scale
	var h := 8.0 * scale
	# Turret body
	draw_rect(Rect2(p - Vector2(w * 0.35, h), Vector2(w * 0.55, h * 1.4)), colour)
	# Barrel pointing forward (right)
	draw_rect(Rect2(p + Vector2(w * 0.15, -h * 0.35), Vector2(w * 0.7, h * 0.55)), colour.lightened(0.2))
	if m["stripped"]:
		draw_line(p + Vector2(-6, -10) * scale, p + Vector2(6, 4) * scale, UITheme.WARN, 2.0)

func _draw_armor(p: Vector2, colour: Color, scale: float, m: Dictionary) -> void:
	var s := 14.0 * scale
	var pts := PackedVector2Array([
		p + Vector2(0, -s * 0.6),
		p + Vector2(s * 0.9, 0),
		p + Vector2(0, s * 0.7),
		p + Vector2(-s * 0.9, 0),
	])
	draw_colored_polygon(pts, colour.darkened(0.15))
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, colour.lightened(0.25), 1.5, true)
	if m["stripped"]:
		draw_circle(p, 3.0 * scale, UITheme.WARN)

func _draw_utility(p: Vector2, colour: Color, scale: float, m: Dictionary) -> void:
	var r := 10.0 * scale
	draw_circle(p, r, colour.darkened(0.2))
	draw_arc(p, r, 0.0, TAU, 24, colour.lightened(0.3), 2.0, true)
	# Tiny antenna / thruster fin
	draw_line(p + Vector2(0, -r), p + Vector2(0, -r * 1.8), colour, 2.0 * scale, true)
	if m["stripped"]:
		draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), UITheme.WARN, 2.0)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _ship == null:
		return
	var hull := _hull_rect(Rect2(Vector2.ZERO, size))
	var local := (event as InputEventMouseButton).position
	for m in _modules:
		var p := _hardpoint(hull, m["slot"], int(m["index"]))
		if local.distance_to(p) <= 16.0:
			part_clicked.emit(int(m["uid"]))
			return
