class_name ShipView
extends Control
## Side-view of the stolen ship.
##
## Uses the painted hull art when present, then bolts installed parts onto
## hardpoints (weapons dorsal, hull plating belly, utilities aft). Falls back
## to a procedural chassis if the art file is missing.

signal part_clicked(part_uid: int)

const HULL_ART := "res://assets/ships/salvager-hull.png"

const SLOT_COLOUR := {
	&"weapon": UITheme.HOSTILE,
	&"hull": UITheme.ACCENT,
	&"utility": UITheme.GOOD,
}

var _ship: ShipLoadout
var _hull_tex: Texture2D
var _modules: Array = []
var _animating_uid: int = -1
var _anim_t: float = 0.0
var _pulse: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(360, 180)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hull_tex = UITheme.art(HULL_ART)
	set_process(true)

func _process(delta: float) -> void:
	_pulse += delta
	if _animating_uid >= 0:
		_anim_t = mini(1.0, _anim_t + delta * 2.8)
		if _anim_t >= 1.0:
			_animating_uid = -1
		queue_redraw()

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
	draw_rect(r, Color(0.04, 0.07, 0.1, 1.0))
	_draw_grid(r)

	var hull := _hull_rect(r)
	_draw_chassis(hull)

	if _ship != null:
		for slot in ShipLoadout.SLOT_TYPES:
			var cap := _ship.slot_capacity(slot)
			var used := _ship.installed_in(slot).size()
			for i in cap:
				if i >= used:
					_draw_hardpoint_ghost(hull, slot, i)

	for m in _modules:
		_draw_module(hull, m)

	if _ship != null:
		var font := UITheme.font("SemiBold")
		draw_string(font, Vector2(12, size.y - 10), _ship.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)

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
	var margin_x := 10.0
	var margin_y := 8.0
	var avail := Rect2(
		r.position.x + margin_x,
		r.position.y + margin_y,
		r.size.x - margin_x * 2.0,
		r.size.y - margin_y * 2.0 - 14.0)
	if _hull_tex == null:
		var h := mini(72.0, avail.size.y * 0.7)
		return Rect2(avail.position.x, avail.position.y + (avail.size.y - h) * 0.35,
			avail.size.x, h)
	# Fit the painted hull into the bay, preserving aspect.
	var tex := _hull_tex.get_size()
	var scale := mini(avail.size.x / tex.x, avail.size.y / tex.y)
	var w := tex.x * scale
	var h := tex.y * scale
	return Rect2(
		avail.position.x + (avail.size.x - w) * 0.5,
		avail.position.y + (avail.size.y - h) * 0.5,
		w, h)

func _draw_chassis(hull: Rect2) -> void:
	if _hull_tex != null:
		draw_texture_rect(_hull_tex, hull, false)
		# Soft engine pulse over the rear nozzles (left side of the art).
		var exhaust := hull.position + Vector2(hull.size.x * 0.07, hull.size.y * 0.55)
		var glow := 0.35 + 0.2 * sin(_pulse * 4.0)
		draw_circle(exhaust, hull.size.y * 0.12, Color(0.2, 0.75, 1.0, glow * 0.25))
		return

	# Procedural fallback when art is absent.
	var pts := PackedVector2Array([
		hull.position + Vector2(hull.size.x * 0.08, hull.size.y * 0.25),
		hull.position + Vector2(hull.size.x * 0.72, hull.size.y * 0.05),
		hull.position + Vector2(hull.size.x * 0.96, hull.size.y * 0.45),
		hull.position + Vector2(hull.size.x * 0.78, hull.size.y * 0.92),
		hull.position + Vector2(hull.size.x * 0.18, hull.size.y * 0.88),
		hull.position + Vector2(hull.size.x * 0.02, hull.size.y * 0.55),
	])
	draw_colored_polygon(pts, Color("1a2836"))
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], UITheme.ACCENT_DIM, 2.0, true)

func _hardpoint(hull: Rect2, slot: StringName, index: int) -> Vector2:
	# Tuned to the painted hull: nose right, engines left, dorsal rails on top.
	match slot:
		ShipLoadout.SLOT_WEAPON:
			var t := 0.62 - index * 0.12
			return hull.position + Vector2(hull.size.x * t, hull.size.y * 0.22)
		ShipLoadout.SLOT_HULL:
			var t2 := 0.35 + index * 0.14
			return hull.position + Vector2(hull.size.x * t2, hull.size.y * 0.78)
		_:
			var t3 := 0.18 + index * 0.09
			return hull.position + Vector2(hull.size.x * t3, hull.size.y * (0.28 if index % 2 == 0 else 0.72))

func _draw_hardpoint_ghost(hull: Rect2, slot: StringName, index: int) -> void:
	var p := _hardpoint(hull, slot, index)
	var c: Color = SLOT_COLOUR.get(slot, UITheme.TEXT_FAINT)
	c.a = 0.3
	draw_arc(p, 8.0, 0.0, TAU, 20, c, 1.5, true)

func _draw_module(hull: Rect2, m: Dictionary) -> void:
	var p := _hardpoint(hull, m["slot"], int(m["index"]))
	var scale := 1.0
	var alpha := 1.0
	if int(m["uid"]) == _animating_uid:
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
	draw_rect(Rect2(p - Vector2(w * 0.35, h), Vector2(w * 0.55, h * 1.4)), colour)
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
	var rad := 10.0 * scale
	draw_circle(p, rad, colour.darkened(0.2))
	draw_arc(p, rad, 0.0, TAU, 24, colour.lightened(0.3), 2.0, true)
	draw_line(p + Vector2(0, -rad), p + Vector2(0, -rad * 1.8), colour, 2.0 * scale, true)
	if m["stripped"]:
		draw_line(p + Vector2(-rad, 0), p + Vector2(rad, 0), UITheme.WARN, 2.0)

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
