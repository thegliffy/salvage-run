extends Control
## Sector map: left-to-right layered DAG, Slay-the-Spire style.
##
## The player stands on the current node and may only enter a node linked from
## it. Visited nodes stay lit so the path taken is readable at a glance.

const COL_W := 116.0
const ROW_H := 92.0
const NODE_R := 24.0
const PAD_X := 48.0
const PAD_Y := 56.0

const TYPE_COLOUR := {
	"start": UITheme.TEXT_DIM,
	"combat": UITheme.HOSTILE,
	"elite": UITheme.WARN,
	"shop": UITheme.ACCENT,
	"chest": UITheme.GOOD,
	"boss": UITheme.HOSTILE,
}

var _scroll: ScrollContainer
var _canvas: Control
var _status: Label
var _positions: Dictionary = {}  # node_id -> Vector2 centre in canvas space
var _overlay_host: Control
var _preview_layer: Control

func _ready() -> void:
	_build()
	_rebuild()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var head := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		head.add_theme_constant_override("margin_" + side, 18 if side != "bottom" else 8)
	root.add_child(head)

	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 6)
	head.add_child(head_col)

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 14)
	head_col.add_child(head_row)
	head_row.add_child(UITheme.chrome_mark())
	head_row.add_child(UITheme.label("SECTOR %d OF %d" % [
		Game.run.sector, MapGenerator.SECTOR_COUNT], 18, UITheme.TEXT, "Bold"))
	_status = UITheme.label("", 13, UITheme.TEXT_DIM, "SemiBold")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(_status)

	var ship_btn := UITheme.ghost_button("  SHIP STATUS  ")
	UITheme.tip(ship_btn, "Ship status\n---\nSlots, power budget, deck, and the painted hull.")
	ship_btn.pressed.connect(_open_ship_status)
	head_row.add_child(ship_btn)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 8)
	head_col.add_child(legend)
	var boss_blurb := "Final boss. Win and sell the ship." \
		if Game.run.is_final_sector() \
		else "Sector boss. Win to enter the next sector."
	for pair in [
		["FIGHT", TYPE_COLOUR["combat"], "Regular combat — credits and a part offer."],
		["MINI-BOSS", TYPE_COLOUR["elite"], "Elite fight — harder, pays an improvement."],
		["STORE", TYPE_COLOUR["shop"], "Buy parts or strip a card (credits, plus a sale penalty)."],
		["CHEST", TYPE_COLOUR["chest"], "Free ship improvement. No slot, no cards."],
		["BOSS" if not Game.run.is_final_sector() else "FINAL", TYPE_COLOUR["boss"], boss_blurb],
	]:
		var badge := UITheme.badge(String(pair[0]), pair[1] as Color)
		UITheme.tip(badge, "%s\n---\n%s" % [pair[0], pair[2]])
		legend.add_child(badge)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_canvas)

	# Full-screen overlays (ship status + card preview) sit above the map.
	_overlay_host = Control.new()
	_overlay_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_host.z_index = 10
	add_child(_overlay_host)

	_preview_layer = Control.new()
	_preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.z_index = 30
	add_child(_preview_layer)

func _rebuild() -> void:
	for c in _canvas.get_children():
		c.queue_free()
	_positions.clear()

	var run: RunState = Game.run
	var map: Dictionary = run.map
	var by_layer: Array = map["by_layer"]
	var layers: int = int(map["layers"])
	var max_slots := 1
	for row in by_layer:
		max_slots = maxi(max_slots, row.size())

	var canvas_w := PAD_X * 2.0 + COL_W * float(layers)
	var canvas_h := PAD_Y * 2.0 + ROW_H * float(max_slots)
	_canvas.custom_minimum_size = Vector2(canvas_w, maxf(canvas_h, size.y - 80.0))

	# Precompute centres so edges can be drawn between them.
	for layer in range(layers):
		var row: Array = by_layer[layer]
		var n := row.size()
		for i in n:
			var nid: int = row[i]
			var x := PAD_X + COL_W * float(layer) + COL_W * 0.5
			var span := ROW_H * float(max_slots)
			var y := PAD_Y + span * (float(i) + 0.5) / float(n)
			_positions[nid] = Vector2(x, y)

	var edges := Control.new()
	edges.set_anchors_preset(Control.PRESET_FULL_RECT)
	edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edges.draw.connect(_draw_edges.bind(edges))
	_canvas.add_child(edges)
	edges.queue_redraw()

	var reachable: Dictionary = {}
	for opt in run.options():
		reachable[int(opt["id"])] = true

	for layer in range(layers):
		for nid in by_layer[layer]:
			_canvas.add_child(_make_node(map["nodes"][nid], reachable.has(int(nid))))

	var cur := MapGenerator.node_at(map, run.current_node)
	_status.text = "HULL %d/%d    CREDITS %d    DECK %d    AT %s" % [
		run.hull_carryover, run.profile.max_hull, run.credits,
		run.profile.deck.size(), MapGenerator.label_for(String(cur["type"]), run.sector)]
	UITheme.tip(_status, "Run status\nhull %d/%d · credits %d · deck %d\n---\nSHIP STATUS opens the full loadout, power budget, and deck." % [
		run.hull_carryover, run.profile.max_hull, run.credits, run.profile.deck.size()])

	# Keep the current column in view.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var cur_pos: Vector2 = _positions.get(run.current_node, Vector2.ZERO)
	_scroll.scroll_horizontal = int(maxi(0, int(cur_pos.x - _scroll.size.x * 0.35)))

func _draw_edges(edges: Control) -> void:
	var run: RunState = Game.run
	var map: Dictionary = run.map
	for node in map["nodes"]:
		var from: Vector2 = _positions.get(int(node["id"]), Vector2.ZERO)
		var from_visited: bool = bool(node["visited"])
		for eid in node["edges"]:
			var to: Vector2 = _positions.get(int(eid), Vector2.ZERO)
			var to_node: Dictionary = map["nodes"][eid]
			var lit := from_visited and (bool(to_node["visited"]) or int(node["id"]) == run.current_node)
			var col := UITheme.ACCENT if lit else UITheme.TEXT_FAINT
			col.a = 0.95 if lit else 0.35
			edges.draw_line(from, to, col, 2.5 if lit else 1.5, true)

func _make_node(node: Dictionary, can_enter: bool) -> Control:
	var ntype := String(node["type"])
	var colour: Color = TYPE_COLOUR.get(ntype, UITheme.TEXT)
	var pos: Vector2 = _positions[int(node["id"])]
	var visited: bool = bool(node["visited"])
	var is_here: bool = int(node["id"]) == Game.run.current_node

	var wrap := Control.new()
	wrap.position = pos - Vector2(NODE_R + 10, NODE_R + 22)
	wrap.custom_minimum_size = Vector2((NODE_R + 10) * 2, (NODE_R + 22) * 2 + 12)
	wrap.size = wrap.custom_minimum_size

	var btn := ThemedButton.new()
	btn.position = Vector2(10, 22)
	btn.custom_minimum_size = Vector2(NODE_R * 2, NODE_R * 2)
	btn.size = btn.custom_minimum_size
	btn.text = _glyph(ntype)
	UITheme.tip(btn, _tooltip(node, can_enter, is_here, visited))
	btn.disabled = not can_enter
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", UITheme.font("Black"))
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", UITheme.BG if can_enter or is_here else UITheme.TEXT_FAINT)
	btn.add_theme_color_override("font_hover_color", UITheme.BG)
	btn.add_theme_color_override("font_disabled_color", UITheme.TEXT_FAINT)

	var fill := colour if (can_enter or is_here or visited) else UITheme.PANEL_RAISED
	var border := UITheme.ACCENT if is_here else (colour.lightened(0.25) if can_enter else Color(0, 0, 0, 0))
	var bw := 4 if is_here else (2 if can_enter else 0)
	if not can_enter and not is_here and not visited:
		fill = UITheme.PANEL
		btn.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		btn.add_theme_color_override("font_disabled_color", UITheme.TEXT_FAINT)
	btn.add_theme_stylebox_override("normal", UITheme.panel(fill, border, bw, int(NODE_R), 0))
	btn.add_theme_stylebox_override("hover", UITheme.panel(fill.lightened(0.15), UITheme.ACCENT, 3, int(NODE_R), 0))
	btn.add_theme_stylebox_override("pressed", UITheme.panel(fill.darkened(0.2), UITheme.ACCENT, 3, int(NODE_R), 0))
	btn.add_theme_stylebox_override("disabled", UITheme.panel(
		fill if visited else UITheme.PANEL,
		Color(0, 0, 0, 0), 0, int(NODE_R), 0))

	if can_enter:
		var nid := int(node["id"])
		btn.pressed.connect(func(): Game.enter_node(nid))

	wrap.add_child(btn)

	if is_here:
		var here := UITheme.label("YOU", 10, Color.WHITE, "Black")
		here.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		here.position = Vector2(0, 2)
		here.size = Vector2((NODE_R + 10) * 2, 16)
		wrap.add_child(here)

	var tag := UITheme.label(MapGenerator.label_for(ntype, Game.run.sector), 11,
		colour if (can_enter or is_here or visited) else UITheme.TEXT_FAINT,
		"Black" if ntype == "boss" else "Bold")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = Vector2(0, NODE_R * 2 + 24)
	tag.size = Vector2((NODE_R + 10) * 2, 16)
	wrap.add_child(tag)
	return wrap

func _glyph(ntype: String) -> String:
	match ntype:
		"start": return "S"
		"combat": return "F"
		"elite": return "E"
		"shop": return "$"
		"chest": return "C"
		"boss": return "B"
		_: return "?"

func _tooltip(node: Dictionary, can_enter: bool, is_here: bool, visited: bool) -> String:
	var ntype := String(node["type"])
	var title := MapGenerator.label_for(ntype, Game.run.sector)
	var bits: PackedStringArray = [title]
	var enemy_id := StringName(node.get("enemy", &""))
	if enemy_id != &"":
		var e: EnemyDef = Database.enemy(enemy_id)
		if e != null:
			bits.append("%s · hull %d · evasion %d" % [e.name, e.hull, e.evasion])
			if e.shield > 0:
				bits.append("shields %d (+%d/t)" % [e.shield, e.shield_regen])
	bits.append("---")
	match ntype:
		"shop":
			bits.append("Buy parts with credits, or strip a card (credits + sale penalty).")
		"chest":
			bits.append("A ship improvement — no slot, no cards.")
		"start":
			bits.append("Sector %d of %d. Pick a linked node to the right." % [
				Game.run.sector, MapGenerator.SECTOR_COUNT])
		"elite":
			bits.append("Harder fight. Better rewards, including an improvement.")
		"boss":
			if Game.run.is_final_sector():
				bits.append("Final boss. Win and the ship goes to sale.")
			else:
				bits.append("Sector boss. Win to enter sector %d." % (Game.run.sector + 1))
		_:
			bits.append("Combat. Credits and a part offer on a win.")
	if is_here:
		bits.append("You are here.")
	elif can_enter:
		bits.append("Reachable — click to enter.")
	elif visited:
		bits.append("Already visited.")
	else:
		bits.append("Not reachable from here.")
	return "\n".join(bits)

# --- Ship status overlay -----------------------------------------------------

func _open_ship_status() -> void:
	ShipStatusOverlay.open(_overlay_host, _preview_layer, _close_ship_status)

func _close_ship_status() -> void:
	ShipStatusOverlay.close(_overlay_host, _preview_layer)
