class_name ShipStatusOverlay
extends RefCounted
## Shared ship-status panel used from the map and combat screens.
##
## Builds into a host Control the caller owns. Returns a close Callable so the
## host can dismiss it (and clean up any card preview layer).

static func open(host: Control, preview_layer: Control, on_close: Callable) -> void:
	# Clear any prior overlay content.
	for c in host.get_children():
		c.queue_free()
	host.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			on_close.call())
	host.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(centre)

	var panel := PanelContainer.new()
	# Fit inside the viewport with a margin — never taller/wider than the screen.
	var vp := host.get_viewport_rect().size
	panel.custom_minimum_size = Vector2(
		minf(740.0, vp.x - 48.0),
		minf(540.0, vp.y - 48.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT, 1, 6, 18))
	centre.add_child(panel)

	var outer := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 0)
	panel.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	var run: RunState = Game.run
	var prof := run.profile
	var bud: Dictionary = run.ship.power_budget()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UITheme.label(run.ship.display_name.to_upper(), 24, UITheme.ACCENT, "Black"))
	head.add_child(UITheme.expand())
	var close := UITheme.ghost_button("  CLOSE  ")
	close.pressed.connect(on_close)
	head.add_child(close)

	var deficit: int = int(bud["deficit"])
	if deficit > 0:
		col.add_child(UITheme.deficit_panel(deficit,
			"Part draw %d exceeds hull output %d, so energy is cut to %d every turn. Jettison a hungry part or find a power improvement." % [
				bud["draw"], bud["output"], bud["energy"]]))

	# Explicit stats block so the numbers are impossible to miss.
	var stats := PanelContainer.new()
	stats.add_theme_stylebox_override("panel", UITheme.panel(
		UITheme.INK_WARN if deficit > 0 else UITheme.PANEL_RAISED,
		UITheme.WARN if deficit > 0 else UITheme.ACCENT_DIM, 1, 4, 10))
	col.add_child(stats)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 22)
	stats.add_child(srow)
	srow.add_child(UITheme.metric("HULL", "%d / %d" % [run.hull_carryover, prof.max_hull], UITheme.GOOD,
		"Hull\n%d / %d\n---\nCarry-over between fights. Hit 0 and the wreck is sold." % [
			run.hull_carryover, prof.max_hull]))
	srow.add_child(UITheme.metric("ENERGY", "%d / turn" % bud["energy"],
		UITheme.WARN if deficit > 0 else UITheme.ACCENT,
		UITheme.power_tip(bud)))
	srow.add_child(UITheme.metric("POWER", "draw %d / out %d" % [bud["draw"], bud["output"]],
		UITheme.WARN if deficit > 0 else UITheme.TEXT,
		UITheme.power_tip(bud)))
	srow.add_child(UITheme.metric("EVASION", str(prof.evasion), UITheme.TEXT,
		"Evasion %d\n---\nChance incoming shots miss. Heavier ships dodge worse." % prof.evasion))
	srow.add_child(UITheme.metric("SHIELD", "%d (+%d/t)" % [prof.max_shield, prof.shield_regen], UITheme.SHIELD,
		"Shields\n%d max · +%d / turn\n---\nAbsorbs damage before hull. Gain above capacity becomes overshield until your next turn." % [
			prof.max_shield, prof.shield_regen]))
	srow.add_child(UITheme.metric("DECK", str(prof.deck.size()), UITheme.TEXT,
		"Deck %d\n---\nThree cards per installed part. Bigger ships draw worse." % prof.deck.size()))

	for w in prof.warnings:
		if deficit > 0 and String(w).begins_with("Power deficit"):
			continue
		col.add_child(UITheme.label("! " + w, 13, UITheme.WARN, "SemiBold"))

	var ship_view := ShipView.new()
	ship_view.custom_minimum_size = Vector2(0, 120)
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
		deck_col.add_child(_deck_row(cid, int(counts[cid]), preview_layer, on_close))

	var close_foot := UITheme.ghost_button("  CLOSE  ")
	close_foot.pressed.connect(on_close)
	col.add_child(close_foot)

static func close(host: Control, preview_layer: Control = null) -> void:
	if preview_layer != null:
		for c in preview_layer.get_children():
			c.queue_free()
	for c in host.get_children():
		c.queue_free()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _slot_block(run: RunState, slot: StringName) -> Control:
	var used := run.ship.installed_in(slot)
	var cap := run.ship.slot_capacity(slot)
	var wrap := ThemedPanel.new()
	var full := used.size() >= cap
	wrap.add_theme_stylebox_override("panel", UITheme.panel(
		UITheme.PANEL_RAISED,
		UITheme.WARN if full else UITheme.ACCENT_DIM, 1, 4, 10))
	UITheme.tip(wrap, "%s slots\n%d / %d%s\n---\nTyped mounts. Full means a new part of this type must replace one." % [
		String(slot).to_upper(), used.size(), cap, " · FULL" if full else ""])
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
			var bits: PackedStringArray = []
			if inst.def.power_draw > 0:
				bits.append("-%d power" % inst.def.power_draw)
			bits.append("%d mass" % inst.def.mass)
			var part_l := UITheme.label("· %s  (%s)" % [line, "  ".join(bits)], 12,
				UITheme.HOSTILE if inst.is_wrecked() else UITheme.TEXT)
			var extra := ""
			if inst.is_wrecked():
				extra = "Wrecked — cards gone until repaired."
			elif inst.is_stripped():
				extra = "Stripped — one card already cut from this mount."
			UITheme.tip(part_l, UITheme.part_tip(inst.def, extra))
			col.add_child(part_l)
	return wrap

static func _deck_row(card_id: StringName, count: int, preview_layer: Control,
		_on_close: Callable) -> Control:
	var cd: CardDef = Database.card(card_id)
	if cd == null:
		return UITheme.label("· unknown card", 12, UITheme.TEXT_FAINT)

	var row := ThemedPanel.new()
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

	UITheme.tip(row, UITheme.card_tip(CardInstance.create(cd)))
	row.mouse_entered.connect(func():
		_show_preview(cd, row, preview_layer))
	row.mouse_exited.connect(func():
		_hide_preview(preview_layer))
	return row

static func _show_preview(cd: CardDef, anchor: Control, preview_layer: Control) -> void:
	_hide_preview(preview_layer)
	if preview_layer == null or not is_instance_valid(preview_layer):
		return
	var inst := CardInstance.create(cd)
	var card := CardView.new()
	card.setup(inst)
	card.set_playable(true)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.add_child(card)
	var origin := anchor.get_global_rect().position
	var size := CardView.CARD_SIZE
	var vp := preview_layer.get_viewport_rect().size
	var pos := origin + Vector2(-size.x - 12, 0)
	if pos.x < 12.0:
		pos.x = origin.x + anchor.size.x + 12.0
	pos.y = clampf(pos.y, 12.0, vp.y - size.y - 12.0)
	card.global_position = pos

static func _hide_preview(preview_layer: Control) -> void:
	if preview_layer == null or not is_instance_valid(preview_layer):
		return
	for c in preview_layer.get_children():
		c.queue_free()
