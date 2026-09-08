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
	if vp.x < 160.0 or vp.y < 160.0:
		vp = Vector2(1280, 720)
	panel.custom_minimum_size = Vector2(
		minf(760.0, maxf(vp.x - 48.0, 320.0)),
		minf(560.0, maxf(vp.y - 48.0, 280.0)))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT, 1, 6, 18))
	centre.add_child(panel)

	var outer := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(outer)

	# Fill the panel — do not wrap the whole overlay in a ScrollContainer.
	# Nested leftover-height scrolls (parts / deck) need a definite parent
	# height or they collapse and clip, which is how the deck used to vanish.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	outer.add_child(col)

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
	var over_blurb := "Overshield does not expire." if run.ship.has_flag(&"keep_overshield") \
		else "Gain above capacity becomes overshield until your next turn."
	srow.add_child(UITheme.metric("SHIELD", "%d (+%d/t)" % [prof.max_shield, prof.shield_regen], UITheme.SHIELD,
		"Shields\n%d max · +%d / turn\n---\nAbsorbs damage before hull. %s" % [
			prof.max_shield, prof.shield_regen, over_blurb]))
	srow.add_child(UITheme.metric("DECK", str(prof.deck.size()), UITheme.TEXT,
		"Deck %d\n---\nThree cards per installed part. Bigger ships draw worse." % prof.deck.size()))

	for w in prof.warnings:
		if deficit > 0 and String(w).begins_with("Power deficit"):
			continue
		col.add_child(UITheme.label("! " + w, 13, UITheme.WARN, "SemiBold"))

	# Improvements sit under the stats so an empty or installed list is on the
	# first screen — they used to hang off the bottom of a nested slots scroll.
	col.add_child(_improvements_block(run))

	# Two leftover-height columns. Headings stay pinned; only the lists scroll,
	# so a long deck is browseable without clipping parts or improvements.
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.y = 180
	body.add_theme_constant_override("separation", 16)
	col.add_child(body)

	var slots_wrap := VBoxContainer.new()
	slots_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_wrap.size_flags_stretch_ratio = 1.12
	slots_wrap.add_theme_constant_override("separation", 6)
	body.add_child(slots_wrap)
	slots_wrap.add_child(UITheme.label("EQUIPPED PARTS", 15, UITheme.TEXT, "Bold"))
	slots_wrap.add_child(UITheme.label(
		"Grouped by mount. Empty mounts still count against capacity.",
		11, UITheme.TEXT_FAINT))
	var slots_scroll := ScrollContainer.new()
	slots_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slots_wrap.add_child(slots_scroll)
	var slots_col := VBoxContainer.new()
	slots_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_col.add_theme_constant_override("separation", 8)
	slots_scroll.add_child(slots_col)
	for slot in ShipLoadout.SLOT_TYPES:
		slots_col.add_child(_slot_block(run, slot))

	var deck_wrap := VBoxContainer.new()
	deck_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_wrap.add_theme_constant_override("separation", 4)
	body.add_child(deck_wrap)
	deck_wrap.add_child(UITheme.label("DECK  (%d)" % prof.deck.size(), 15, UITheme.TEXT, "Bold"))
	deck_wrap.add_child(UITheme.label(
		"Compiled from installed parts. Duplicates share a count. Hover a row to read the card.",
		11, UITheme.TEXT_FAINT))
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_wrap.add_child(deck_scroll)
	var deck_list := VBoxContainer.new()
	deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_list.add_theme_constant_override("separation", 4)
	deck_scroll.add_child(deck_list)
	_fill_deck_list(deck_list, prof.deck, preview_layer, on_close)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	var scuttle := UITheme.outline_button("  SELF-DESTRUCT  ", UITheme.HOSTILE)
	scuttle.name = "SelfDestruct"
	UITheme.tip(scuttle,
		"Self-destruct\n---\nScuttle the ship and sell the wreck. Asks for confirmation — same as a hull-loss.")
	scuttle.pressed.connect(func():
		_open_self_destruct_confirm(host))
	foot.add_child(scuttle)
	foot.add_child(UITheme.expand())
	var close_foot := UITheme.ghost_button("  CLOSE  ")
	close_foot.pressed.connect(on_close)
	foot.add_child(close_foot)

## Confirm layer on top of SHIP STATUS. CANCEL / dim click dismisses it and
## leaves the run running; SCUTTLE calls `Game.self_destruct()`.
static func _open_self_destruct_confirm(host: Control) -> void:
	var existing := host.get_node_or_null("SelfDestructConfirm")
	if existing != null and not existing.is_queued_for_deletion():
		return
	if existing != null:
		host.remove_child(existing)
		existing.free()

	var layer := Control.new()
	layer.name = "SelfDestructConfirm"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 20
	host.add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_self_destruct_confirm(host))
	layer.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.HOSTILE, 1, 6, 18))
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	col.add_child(UITheme.label("SELF-DESTRUCT", 20, UITheme.HOSTILE, "Black"))
	col.add_child(UITheme.callout(
		"Scuttle the ship and sell the wreck.",
		"Same as a hull-loss: forty percent recovery, then back to the title. This cannot be undone.",
		&"hostile"))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	col.add_child(actions)
	var cancel := UITheme.ghost_button("  CANCEL  ")
	cancel.name = "CancelSelfDestruct"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func():
		_close_self_destruct_confirm(host))
	actions.add_child(cancel)
	var confirm := UITheme.button("  SCUTTLE  ", UITheme.HOSTILE)
	confirm.name = "ConfirmSelfDestruct"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.tip(confirm,
		"Scuttle\n---\nEnds the run. The yard pays for a salvaged wreck, not a delivered theft.")
	confirm.pressed.connect(func():
		Game.self_destruct())
	actions.add_child(confirm)

static func _close_self_destruct_confirm(host: Control) -> void:
	var layer := host.get_node_or_null("SelfDestructConfirm")
	if layer == null:
		return
	host.remove_child(layer)
	layer.queue_free()

## Compact combat / tooltip strip: slot fill plus improvement count or name.
static func loadout_strip(ship: ShipLoadout) -> String:
	if ship == null:
		return ""
	var bits: PackedStringArray = []
	bits.append("W %d/%d" % [
		ship.installed_in(ShipLoadout.SLOT_WEAPON).size(),
		ship.slot_capacity(ShipLoadout.SLOT_WEAPON)])
	bits.append("H %d/%d" % [
		ship.installed_in(ShipLoadout.SLOT_HULL).size(),
		ship.slot_capacity(ShipLoadout.SLOT_HULL)])
	bits.append("U %d/%d" % [
		ship.installed_in(ShipLoadout.SLOT_UTILITY).size(),
		ship.slot_capacity(ShipLoadout.SLOT_UTILITY)])
	var n := ship.improvements.size()
	if n <= 0:
		bits.append("no improvements")
	elif n == 1:
		var imp: ImprovementDef = Database.improvement(ship.improvements[0])
		bits.append(imp.name if imp != null else "1 improvement")
	else:
		bits.append("%d improvements" % n)
	return "  ·  ".join(bits)

## Visible label copy under `root`. Used by headless overlay coverage.
static func collect_texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	_collect_texts(root, out)
	return out

static func _collect_texts(n: Node, out: PackedStringArray) -> void:
	if n is Label:
		var t := String((n as Label).text).strip_edges()
		if t != "":
			out.append(t)
	for c in n.get_children():
		_collect_texts(c, out)

## First-seen order with duplicate counts. The run deck is derived from the
## ship, so this is the list combat will shuffle.
static func tally_deck(deck: Array) -> Array:
	var counts: Dictionary = {}
	var order: Array[StringName] = []
	for cid in deck:
		var id := cid as StringName
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += 1
	var out: Array = []
	for id in order:
		out.append({"id": id, "count": int(counts[id])})
	return out

## Focused deck list for the reward and map screens. Same rows and card
## preview as the ship-status panel; dismiss with CLOSE or a click on the dim.
static func open_deck(host: Control, preview_layer: Control, on_close: Callable) -> void:
	for c in host.get_children():
		c.queue_free()
	host.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			on_close.call())
	host.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(centre)

	var panel := PanelContainer.new()
	var vp := host.get_viewport_rect().size
	panel.custom_minimum_size = Vector2(
		minf(560.0, vp.x - 48.0),
		minf(640.0, vp.y - 48.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT, 1, 6, 18))
	centre.add_child(panel)

	var outer := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(outer)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	outer.add_child(col)

	var run: RunState = Game.run
	var deck: Array = run.profile.deck

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UITheme.label("DECK  (%d)" % deck.size(), 24, UITheme.ACCENT, "Black"))
	head.add_child(UITheme.expand())
	var close := UITheme.ghost_button("  CLOSE  ")
	close.pressed.connect(on_close)
	head.add_child(close)

	col.add_child(UITheme.label(
		"Cards compiled from installed parts. Duplicates share a count. Hover a row to read the card.",
		13, UITheme.TEXT_DIM, "SemiBold"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	_fill_deck_list(list, deck, preview_layer, on_close)

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

static func _fill_deck_list(list: VBoxContainer, deck: Array, preview_layer: Control,
		on_close: Callable) -> void:
	if deck.is_empty():
		list.add_child(UITheme.label("No cards — the ship is empty.", 13, UITheme.TEXT_FAINT))
		return
	for entry in tally_deck(deck):
		list.add_child(_deck_row(entry["id"], int(entry["count"]), preview_layer, on_close))

static func _slot_block(run: RunState, slot: StringName) -> Control:
	var used := run.ship.installed_in(slot)
	var cap := run.ship.slot_capacity(slot)
	var wrap := ThemedPanel.new()
	var full := used.size() >= cap
	wrap.add_theme_stylebox_override("panel", UITheme.panel(
		UITheme.PANEL_RAISED,
		UITheme.WARN if full else UITheme.ACCENT_DIM, 1, 4, 8))
	UITheme.tip(wrap, "%s slots\n%d / %d%s\n---\nTyped mounts. Full means a new part of this type must replace one." % [
		String(slot).to_upper(), used.size(), cap, " · FULL" if full else ""])
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	wrap.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UITheme.label(String(slot).to_upper(), 14, UITheme.ACCENT, "Bold"))
	head.add_child(UITheme.label("%d / %d" % [used.size(), cap], 13,
		UITheme.WARN if full else UITheme.TEXT_DIM, "SemiBold"))
	if full:
		head.add_child(UITheme.label("FULL", 11, UITheme.WARN, "Bold"))
	else:
		var empty := cap - used.size()
		head.add_child(UITheme.label(
			"1 empty mount" if empty == 1 else "%d empty mounts" % empty,
			11, UITheme.TEXT_FAINT))

	if used.is_empty():
		col.add_child(UITheme.label("nothing equipped", 12, UITheme.TEXT_FAINT))
	else:
		for inst in used:
			col.add_child(_part_row(inst))
	return wrap

static func _part_row(inst: PartInstance) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var art := UITheme.module_icon(inst.def, UITheme.MODULE_ICON_LIST)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name := inst.def.name
	if inst.is_wrecked():
		name += "  (wrecked)"
	elif inst.is_stripped():
		name += "  (stripped)"
	info.add_child(UITheme.label(name, 13,
		UITheme.HOSTILE if inst.is_wrecked() else UITheme.TEXT, "SemiBold"))
	var bits: PackedStringArray = []
	if inst.def.power_draw > 0:
		bits.append("−%d power" % inst.def.power_draw)
	bits.append("%d mass" % inst.def.mass)
	info.add_child(UITheme.label("  ·  ".join(bits), 11, UITheme.TEXT_FAINT))

	var extra := ""
	if inst.is_wrecked():
		extra = "Wrecked — cards gone until repaired."
	elif inst.is_stripped():
		extra = "Stripped — one card already cut from this mount."
	UITheme.tip(row, UITheme.part_tip(inst.def, extra))
	return row

static func _improvements_block(run: RunState) -> Control:
	var wrap := ThemedPanel.new()
	wrap.add_theme_stylebox_override("panel", UITheme.panel(
		UITheme.PANEL_RAISED, UITheme.ACCENT_DIM, 1, 4, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	wrap.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UITheme.label("IMPROVEMENTS", 14, UITheme.ACCENT, "Bold"))
	head.add_child(UITheme.label(str(run.ship.improvements.size()), 13,
		UITheme.TEXT_DIM, "SemiBold"))

	if run.ship.improvements.is_empty():
		head.add_child(UITheme.label("No improvements yet", 13, UITheme.TEXT_FAINT, "SemiBold"))
		UITheme.tip(wrap,
			"Improvements\nNone installed\n---\nMini-bosses and chests install these. They fill no slot and add no cards.")
		return wrap

	for iid in run.ship.improvements:
		var imp: ImprovementDef = Database.improvement(iid)
		if imp == null:
			continue
		col.add_child(_improvement_row(imp))
	return wrap

static func _improvement_row(imp: ImprovementDef) -> Control:
	var colour: Color = UITheme.rarity_colour(imp.rarity)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(UITheme.label(imp.name, 13, UITheme.TEXT, "SemiBold"))
	if imp.text != "":
		var effect := UITheme.label("—  %s" % imp.text, 12, UITheme.TEXT)
		effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(effect)
	row.add_child(UITheme.label(String(imp.rarity).to_upper(), 10, colour, "Bold"))
	UITheme.tip(row, "%s\n%s\n---\nInstalled ship improvement. Fills no slot and grants no cards." % [
		imp.name, imp.text if imp.text != "" else String(imp.rarity).capitalize()])
	return row

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
