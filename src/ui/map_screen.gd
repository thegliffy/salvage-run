extends Control
## Sector map: left-to-right layered DAG, Slay-the-Spire style.
##
## The player stands on the current node and may only enter a node linked from
## it. Visited nodes stay lit so the path taken is readable at a glance.

const COL_W := 110.0
const ROW_H := 88.0
const NODE_R := 22.0
const PAD_X := 48.0
const PAD_Y := 56.0

const TYPE_COLOUR := {
	"start": UITheme.TEXT_DIM,
	"combat": UITheme.HOSTILE,
	"elite": UITheme.WARN,
	"shop": UITheme.ACCENT,
	"chest": Color("ce93d8"),
	"boss": Color("ff7043"),
}

var _scroll: ScrollContainer
var _canvas: Control
var _status: Label
var _positions: Dictionary = {}  # node_id -> Vector2 centre in canvas space
var _overlay_host: Control
var _preview_layer: Control
var _preview_card: CardView

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

	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 14)
	head.add_child(head_row)
	head_row.add_child(UITheme.label("SECTOR MAP", 28, UITheme.ACCENT, "Black"))
	_status = UITheme.label("", 14, UITheme.TEXT_DIM, "SemiBold")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(_status)

	var ship_btn := UITheme.button("  SHIP STATUS  ", UITheme.ACCENT_DIM)
	ship_btn.add_theme_color_override("font_color", UITheme.TEXT)
	ship_btn.pressed.connect(_open_ship_status)
	head_row.add_child(ship_btn)

	var legend := UITheme.label(
		"FIGHT  ·  MINI-BOSS  ·  STORE  ·  CHEST  ·  BOSS",
		12, UITheme.TEXT_FAINT)
	head_row.add_child(legend)

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
	_status.text = "hull %d/%d   credits %d   deck %d   at %s" % [
		run.hull_carryover, run.profile.max_hull, run.credits,
		run.profile.deck.size(), MapGenerator.label_for(String(cur["type"]))]

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
	wrap.position = pos - Vector2(NODE_R + 8, NODE_R + 18)
	wrap.custom_minimum_size = Vector2((NODE_R + 8) * 2, (NODE_R + 18) * 2 + 10)
	wrap.size = wrap.custom_minimum_size

	var btn := Button.new()
	btn.position = Vector2(8, 18)
	btn.custom_minimum_size = Vector2(NODE_R * 2, NODE_R * 2)
	btn.size = btn.custom_minimum_size
	btn.text = _glyph(ntype)
	btn.tooltip_text = _tooltip(node)
	btn.disabled = not can_enter
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", UITheme.font("Black"))
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", UITheme.BG if can_enter or is_here else UITheme.TEXT_FAINT)
	btn.add_theme_color_override("font_hover_color", UITheme.BG)
	btn.add_theme_color_override("font_disabled_color", UITheme.TEXT_FAINT)

	var fill := colour if (can_enter or is_here or visited) else colour.darkened(0.55)
	var border := Color.WHITE if is_here else (colour.lightened(0.25) if can_enter else Color(0, 0, 0, 0))
	var bw := 3 if is_here else (2 if can_enter else 0)
	btn.add_theme_stylebox_override("normal", UITheme.panel(fill, border, bw, int(NODE_R), 0))
	btn.add_theme_stylebox_override("hover", UITheme.panel(fill.lightened(0.15), Color.WHITE, 3, int(NODE_R), 0))
	btn.add_theme_stylebox_override("pressed", UITheme.panel(fill.darkened(0.2), Color.WHITE, 3, int(NODE_R), 0))
	btn.add_theme_stylebox_override("disabled", UITheme.panel(
		fill.darkened(0.35) if visited else UITheme.PANEL_RAISED,
		Color(0, 0, 0, 0), 0, int(NODE_R), 0))

	if can_enter:
		var nid := int(node["id"])
		btn.pressed.connect(func(): Game.enter_node(nid))

	wrap.add_child(btn)

	var tag := UITheme.label(MapGenerator.label_for(ntype), 10,
		colour if (can_enter or is_here or visited) else UITheme.TEXT_FAINT, "SemiBold")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = Vector2(0, NODE_R * 2 + 20)
	tag.size = Vector2((NODE_R + 8) * 2, 16)
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

func _tooltip(node: Dictionary) -> String:
	var ntype := String(node["type"])
	var label := MapGenerator.label_for(ntype)
	var enemy_id := StringName(node.get("enemy", &""))
	if enemy_id != &"":
		var e: EnemyDef = Database.enemy(enemy_id)
		if e != null:
			return "%s — %s" % [label, e.name]
	match ntype:
		"shop": return "Store — buy parts, strip cards"
		"chest": return "Reward chest — ship improvement"
		"start": return "Sector entry"
		_: return label

# --- Ship status overlay -----------------------------------------------------

func _open_ship_status() -> void:
	_close_ship_status()
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_ship_status())
	_overlay_host.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_host.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT_DIM, 1, 6, 18))
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var run: RunState = Game.run
	var prof := run.profile
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UITheme.label(run.ship.display_name.to_upper(), 24, UITheme.ACCENT, "Black"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UITheme.label(
		"hull %d/%d   energy %d/turn   draw %d/%d   evasion %d   deck %d" % [
			run.hull_carryover, prof.max_hull,
			run.ship.power_budget()["energy"],
			run.ship.power_budget()["draw"], run.ship.power_budget()["output"],
			prof.evasion, prof.deck.size()],
		13, UITheme.TEXT_DIM, "SemiBold"))

	var bud: Dictionary = run.ship.power_budget()
	if int(bud["deficit"]) > 0:
		col.add_child(UITheme.label(
			"POWER DEFICIT %d — part draw exceeds hull output, so energy is cut for the whole run." % bud["deficit"],
			12, UITheme.WARN, "SemiBold"))

	for w in prof.warnings:
		col.add_child(UITheme.label("! " + w, 13, UITheme.WARN, "SemiBold"))

	var ship_view := ShipView.new()
	ship_view.custom_minimum_size = Vector2(0, 170)
	ship_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(ship_view)
	ship_view.refresh(run.ship)
	col.add_child(UITheme.label(
		"Red turrets = weapons · cyan plates = hull · green pods = utility · empty rings = free slots",
		11, UITheme.TEXT_FAINT))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)

	var slots_scroll := ScrollContainer.new()
	slots_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_scroll.size_flags_stretch_ratio = 1.1
	slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(slots_scroll)
	var slots_col := VBoxContainer.new()
	slots_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_col.add_theme_constant_override("separation", 10)
	slots_scroll.add_child(slots_col)
	slots_col.add_child(UITheme.label("SLOTS", 15, UITheme.TEXT, "Bold"))
	for slot in ShipLoadout.SLOT_TYPES:
		slots_col.add_child(_slot_block(run, slot))

	if not run.ship.improvements.is_empty():
		slots_col.add_child(UITheme.spacer(4))
		slots_col.add_child(UITheme.label("IMPROVEMENTS", 15, UITheme.TEXT, "Bold"))
		for iid in run.ship.improvements:
			var imp: ImprovementDef = Database.improvement(iid)
			if imp == null:
				continue
			slots_col.add_child(UITheme.label("· %s — %s" % [imp.name, imp.text],
				12, UITheme.TEXT_DIM))

	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(deck_scroll)
	var deck_col := VBoxContainer.new()
	deck_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_col.add_theme_constant_override("separation", 4)
	deck_scroll.add_child(deck_col)
	deck_col.add_child(UITheme.label("DECK  (%d)" % prof.deck.size(), 15, UITheme.TEXT, "Bold"))
	deck_col.add_child(UITheme.label("Hover a card to read it.", 11, UITheme.TEXT_FAINT))

	var counts: Dictionary = {}
	var order: Array[StringName] = []
	for cid in prof.deck:
		if not counts.has(cid):
			counts[cid] = 0
			order.append(cid)
		counts[cid] += 1
	for cid in order:
		deck_col.add_child(_deck_row(cid, int(counts[cid])))

	var close := UITheme.button("  CLOSE  ", UITheme.ACCENT_DIM)
	close.add_theme_color_override("font_color", UITheme.TEXT)
	close.pressed.connect(_close_ship_status)
	col.add_child(close)

func _slot_block(run: RunState, slot: StringName) -> Control:
	var used := run.ship.installed_in(slot)
	var cap := run.ship.slot_capacity(slot)
	var wrap := PanelContainer.new()
	var full := used.size() >= cap
	wrap.add_theme_stylebox_override("panel", UITheme.panel(
		UITheme.PANEL_RAISED,
		UITheme.WARN if full else UITheme.ACCENT_DIM, 1, 4, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	wrap.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UITheme.label(String(slot).to_upper(), 14, UITheme.ACCENT, "Bold"))
	head.add_child(UITheme.label("%d / %d" % [used.size(), cap], 13,
		UITheme.WARN if full else UITheme.TEXT_DIM, "SemiBold"))
	if full:
		head.add_child(UITheme.label("FULL", 11, UITheme.WARN, "Bold"))

	if used.is_empty():
		col.add_child(UITheme.label("empty", 12, UITheme.TEXT_FAINT))
	else:
		for inst in used:
			var line := "%s" % inst.def.name
			if inst.is_wrecked():
				line += "  (wrecked)"
			elif inst.is_stripped():
				line += "  (stripped)"
			col.add_child(UITheme.label("· " + line, 12,
				UITheme.HOSTILE if inst.is_wrecked() else UITheme.TEXT))
	return wrap

func _deck_row(card_id: StringName, count: int) -> Control:
	var cd: CardDef = Database.card(card_id)
	if cd == null:
		return UITheme.label("· unknown card", 12, UITheme.TEXT_FAINT)

	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", UITheme.panel(
		UITheme.PANEL_RAISED, UITheme.KIND_COLOUR.get(cd.kind, UITheme.ACCENT), 1, 3, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	h.add_child(UITheme.label(str(cd.cost), 12, UITheme.KIND_COLOUR.get(cd.kind, UITheme.ACCENT), "Black"))
	var name := UITheme.label(cd.name, 13, UITheme.TEXT, "SemiBold")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(name)
	if count > 1:
		h.add_child(UITheme.label("x%d" % count, 12, UITheme.TEXT_DIM, "Bold"))
	h.add_child(UITheme.label(String(cd.kind), 11, UITheme.TEXT_FAINT))

	row.mouse_entered.connect(_show_card_preview.bind(cd, row))
	row.mouse_exited.connect(_hide_card_preview)
	return row

func _show_card_preview(cd: CardDef, anchor: Control) -> void:
	_hide_card_preview()
	var inst := CardInstance.create(cd)
	_preview_card = CardView.new()
	_preview_card.setup(inst)
	_preview_card.set_playable(true)
	_preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.add_child(_preview_card)

	var origin := anchor.get_global_rect().position
	var size := CardView.CARD_SIZE
	var vp := get_viewport_rect().size
	var pos := origin + Vector2(-size.x - 12, 0)
	if pos.x < 12.0:
		pos.x = origin.x + anchor.size.x + 12.0
	pos.y = clampf(pos.y, 12.0, vp.y - size.y - 12.0)
	_preview_card.global_position = pos

func _hide_card_preview() -> void:
	if _preview_card != null and is_instance_valid(_preview_card):
		_preview_card.queue_free()
	_preview_card = null

func _close_ship_status() -> void:
	_hide_card_preview()
	for c in _overlay_host.get_children():
		c.queue_free()
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
