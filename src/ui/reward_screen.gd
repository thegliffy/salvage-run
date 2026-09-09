extends Control
## Post-victory payout.
##
## A part is the card reward, because the deck is downstream of the ship.
## Improvements come only from mini-bosses and the sector boss. Declining the
## part is a real choice: field-repair the hull (15% of max), or jettison an
## installed part to free its slot. Hover a card chip to see the full card.

var _reward: Dictionary = {}
var _list: VBoxContainer
var _status: Label
var _heading: Label
var _skip_btn: Button
var _ship_view: ShipView
var _power_panel: PanelContainer
var _jettisoning := false
var _preview_layer: Control
var _preview_card: CardView
var _overlay_host: Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	# Fill the viewport; leftover height goes to the ship sketch and the offer
	# row. Tiles themselves stay compact so TAKE / SKIP / JETTISON never clip.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	var chrome := HBoxContainer.new()
	chrome.add_theme_constant_override("separation", 12)
	col.add_child(chrome)
	chrome.add_child(UITheme.chrome_mark())
	chrome.add_child(UITheme.expand())
	var deck_btn := UITheme.ghost_button("  DECK  ")
	UITheme.tip(deck_btn, "Deck\n---\nCards compiled from the ship. Duplicates are counted.")
	deck_btn.pressed.connect(_open_deck)
	chrome.add_child(deck_btn)

	_reward = Game.pending_reward
	_heading = UITheme.label(_reward_heading(), 20, UITheme.GOOD, "Black")
	col.add_child(_heading)
	var hint := "Take a part — skip to field-repair the hull."
	if Game.pending_sector_advance:
		hint = "Then sector %d of %d." % [
			Game.run.sector + 1, MapGenerator.SECTOR_COUNT]
	col.add_child(UITheme.label(hint, 12, UITheme.TEXT_DIM, "SemiBold"))

	# Credits and the improvement are automatic; only the part is a choice.
	var imp: ImprovementDef = _reward.get("improvement")
	if imp != null and Game.run.ship.improvements.find(imp.id) == -1:
		Game.run.ship.add_improvement(imp.id)
		Game.run.recompile()
	col.add_child(_payout_banner(imp))

	_ship_view = ShipView.new()
	_ship_view.custom_minimum_size = Vector2(0, 48)
	_ship_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ship_view.size_flags_stretch_ratio = 0.35
	col.add_child(_ship_view)
	_ship_view.refresh(Game.run.ship)

	_power_panel = ThemedPanel.new()
	col.add_child(_power_panel)

	_status = UITheme.label("", 12, UITheme.TEXT, "SemiBold")
	col.add_child(_status)

	# Expanding HBox rows (not GridContainer): leftover viewport height after
	# chrome / footer is given to the tiles so they grow with the window.
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.size_flags_stretch_ratio = 1.0
	_list.add_theme_constant_override("separation", 10)
	col.add_child(_list)

	_skip_btn = UITheme.outline_button("", UITheme.GOOD)
	_skip_btn.pressed.connect(_skip_for_repair)
	col.add_child(_skip_btn)

	var jettison := UITheme.button("  JETTISON A PART INSTEAD  ", UITheme.HOSTILE)
	UITheme.tip(jettison, "Jettison\n---\nDump an installed part to free its slot and thin the deck.")
	jettison.pressed.connect(_toggle_jettison)
	col.add_child(jettison)

	_overlay_host = Control.new()
	_overlay_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_host.z_index = 10
	add_child(_overlay_host)

	# Floating card preview sits above everything; ignores mouse so hover
	# doesn't flicker when the cursor is over the preview itself.
	_preview_layer = Control.new()
	_preview_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.z_index = 30
	add_child(_preview_layer)

	_refresh()

func _payout_banner(imp: ImprovementDef) -> Control:
	var wrap := UITheme.box(UITheme.PANEL_RAISED, UITheme.ACCENT_DIM, 1, 4, 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	wrap.add_child(col)
	col.add_child(UITheme.label("+%d CREDITS" % int(_reward.get("credits", 0)),
		18, UITheme.WARN, "Bold"))
	if imp != null:
		var rarity_c := UITheme.rarity_colour(imp.rarity)
		col.add_child(UITheme.label("SHIP IMPROVEMENT — %s  (%s)" % [
			imp.name, String(imp.rarity).to_upper()], 14, rarity_c, "SemiBold"))
		if imp.text != "":
			col.add_child(UITheme.label(imp.text, 13, UITheme.TEXT, "SemiBold"))
	return wrap

func _refresh() -> void:
	var run: RunState = Game.run
	var prof := run.profile
	_status.text = "hull %d/%d    slots  weapon %d/%d    hull %d/%d    utility %d/%d    deck %d" % [
		run.hull_carryover, prof.max_hull,
		run.ship.installed_in(ShipLoadout.SLOT_WEAPON).size(), run.ship.slot_capacity(ShipLoadout.SLOT_WEAPON),
		run.ship.installed_in(ShipLoadout.SLOT_HULL).size(), run.ship.slot_capacity(ShipLoadout.SLOT_HULL),
		run.ship.installed_in(ShipLoadout.SLOT_UTILITY).size(), run.ship.slot_capacity(ShipLoadout.SLOT_UTILITY),
		prof.deck.size()]
	UITheme.tip(_status, "Ship after this fight\nhull %d/%d · deck %d\n---\nSlots are the only hard limit. Power, mass, and deck size are the soft costs." % [
		run.hull_carryover, prof.max_hull, prof.deck.size()])

	_rebuild_power_panel()

	var heal := RewardPool.skip_repair_amount(run)
	if heal > 0:
		_skip_btn.text = "  SKIP PART — REPAIR +%d HULL (15%%)  " % heal
		_skip_btn.disabled = false
		UITheme.tip(_skip_btn, "Skip the part\n---\nField-repair 15%% of max hull (+%d). Leave with no new hardware." % heal)
	else:
		_skip_btn.text = "  SKIP PART — HULL ALREADY FULL  "
		_skip_btn.disabled = false  # still a valid way to leave without a part
		UITheme.tip(_skip_btn, "Skip the part\n---\nHull is already full. Leave with no new hardware.")

	for c in _list.get_children():
		c.queue_free()
	_hide_card_preview()
	if _ship_view != null:
		_ship_view.refresh(run.ship)
	var tiles: Array = []
	if _jettisoning:
		_heading.text = "JETTISON A PART"
		_skip_btn.visible = false
		for inst in run.ship.parts:
			tiles.append(_jettison_row(inst))
	else:
		_skip_btn.visible = true
		_heading.text = _reward_heading()
		for offer in _reward.get("parts", []):
			tiles.append(_offer_row(offer))
	_fill_offer_rows(tiles)

func _reward_heading() -> String:
	if Game.pending_sector_advance:
		return "SECTOR %d CLEAR" % Game.run.sector
	var tier := int(_reward.get("tier", 1))
	if tier == 2:
		return "MINI-BOSS DOWN"
	if tier >= 3:
		return "SECTOR BOSS DOWN"
	return "SALVAGE RECOVERED"

func _rebuild_power_panel() -> void:
	for c in _power_panel.get_children():
		c.queue_free()
	var run: RunState = Game.run
	var bud: Dictionary = run.ship.power_budget()
	var deficit: int = int(bud["deficit"])
	var energy: int = int(bud["energy"])
	var draw: int = int(bud["draw"])
	var output: int = int(bud["output"])

	if deficit > 0:
		_power_panel.add_theme_stylebox_override("panel", UITheme.deficit_style(2))
	else:
		_power_panel.add_theme_stylebox_override("panel",
			UITheme.panel(UITheme.PANEL, UITheme.ACCENT_DIM, 1, 4, 12))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_power_panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UITheme.label(
		"⚡ DEFICIT %d" % deficit if deficit > 0 else "POWER BUDGET",
		14, UITheme.WARN if deficit > 0 else UITheme.TEXT, "SemiBold"))
	head.add_child(UITheme.expand())
	head.add_child(UITheme.metric("OUTPUT", str(output),
		UITheme.WARN if deficit > 0 else UITheme.TEXT))
	head.add_child(UITheme.metric("DRAW", str(draw),
		UITheme.WARN if deficit > 0 else UITheme.TEXT))
	head.add_child(UITheme.metric("ENERGY", "%d / turn" % energy,
		UITheme.WARN if deficit > 0 else UITheme.ACCENT))

	if deficit > 0:
		col.add_child(UITheme.label(
			"Overdraw cuts energy every remaining fight. Jettison a hungry part or find a power improvement.",
			13, UITheme.TEXT, "SemiBold"))
	else:
		col.add_child(UITheme.label(
			"Headroom %d. Taking more draw than output permanently lowers energy." % (output - draw),
			12, UITheme.TEXT_DIM))
	UITheme.tip(_power_panel, UITheme.power_tip(bud))

func _offer_row(offer: Dictionary) -> Control:
	var def: PartDef = offer["def"]
	var rarity: StringName = offer.get("rarity", &"common")
	var rarity_c := UITheme.rarity_colour(rarity)
	# Preview energy first so a new deficit can recolour the card border.
	var replace_target: PartInstance = null if offer["can_install"] else offer.get("replaces")
	var after: Dictionary = Game.run.ship.power_budget(def, replace_target)
	var before: Dictionary = Game.run.ship.power_budget()
	var after_def := int(after["deficit"])
	var shout_deficit := after_def > 0
	var wrap := UITheme.box(UITheme.PANEL,
		UITheme.WARN if shout_deficit else rarity_c,
		2 if shout_deficit else 1, 4, 8)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.custom_minimum_size = Vector2(0, 120)
	UITheme.tip(wrap, UITheme.part_tip(def))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	wrap.add_child(info)

	var name_l := UITheme.label(def.name, 16, UITheme.TEXT, "Bold")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_l)

	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	info.add_child(badges)
	badges.add_child(UITheme.badge(String(rarity).to_upper(), rarity_c))
	badges.add_child(UITheme.badge(String(def.slot).to_upper(), UITheme.ACCENT))

	# Icon beside the card chips so the tile does not stack 80px art on top of
	# three grant rows — that stack was taller than 720p leftover space.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(body)
	var art := UITheme.module_icon(def, UITheme.MODULE_ICON_COMPACT)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(art)
	var grants := VBoxContainer.new()
	grants.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grants.add_theme_constant_override("separation", 3)
	body.add_child(grants)
	grants.add_child(UITheme.label("GRANTS", 10, UITheme.TEXT_FAINT, "Bold"))
	grants.add_child(_card_chips(def.grants))

	var costs := _cost_bits(def)
	if not costs.is_empty():
		var cost_l := UITheme.label("  ·  ".join(costs), 11, UITheme.TEXT_FAINT)
		cost_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(cost_l)

	if shout_deficit:
		info.add_child(UITheme.deficit_panel(after_def,
			"energy %d → %d / turn" % [before["energy"], after["energy"]]))
	elif int(after["energy"]) != int(before["energy"]) or def.power_draw > 0:
		info.add_child(UITheme.energy_note(int(before["energy"]), int(after["energy"])))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)

	var take := UITheme.button("TAKE", UITheme.GOOD)
	take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take.size_flags_vertical = Control.SIZE_SHRINK_END
	if not offer["can_install"]:
		var replaces: PartInstance = offer.get("replaces")
		if replaces != null:
			take = UITheme.button("REPLACE", UITheme.WARN)
			take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			take.size_flags_vertical = Control.SIZE_SHRINK_END
			UITheme.tip(take, "Replace %s\n---\nFrees that slot and its cards, then installs %s." % [
				replaces.def.name, def.name])
		else:
			take.disabled = true
			UITheme.tip(take, "No free %s slot." % String(def.slot))
	else:
		UITheme.tip(take, "Install %s\n---\nAdds its four cards to the deck. Check power draw first." % def.name)
	take.pressed.connect(func():
		var before_uids: Dictionary = {}
		for inst in Game.run.ship.parts:
			before_uids[inst.uid] = true
		var err := RewardPool.claim(Game.run, offer)
		if err == "":
			var new_uid := -1
			for inst2 in Game.run.ship.parts:
				if not before_uids.has(inst2.uid):
					new_uid = inst2.uid
					break
			_ship_view.refresh(Game.run.ship, new_uid)
			_status.text = "Bolted on %s." % def.name
			await get_tree().create_timer(0.55).timeout
			if is_inside_tree():
				_continue()
		else:
			_status.text = err)
	info.add_child(take)
	return wrap

func _jettison_row(inst: PartInstance) -> Control:
	var wrap := UITheme.box(UITheme.PANEL, UITheme.HOSTILE, 1, 4, 8)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.custom_minimum_size = Vector2(0, 110)
	UITheme.tip(wrap, UITheme.part_tip(inst.def, "Jettison frees the slot and removes these cards."))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	wrap.add_child(info)

	var name_l := UITheme.label(inst.def.name, 15, UITheme.TEXT, "Bold")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_l)
	info.add_child(UITheme.badge(String(inst.def.slot).to_upper(), UITheme.ACCENT))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(body)
	var art := UITheme.module_icon(inst.def, UITheme.MODULE_ICON_COMPACT)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(art)
	var grants := VBoxContainer.new()
	grants.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grants.add_theme_constant_override("separation", 3)
	body.add_child(grants)
	grants.add_child(UITheme.label("frees slot + cards", 11, UITheme.TEXT_FAINT))
	grants.add_child(_card_chips(inst.granted_cards()))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)

	var cut := UITheme.button("JETTISON", UITheme.HOSTILE)
	cut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cut.size_flags_vertical = Control.SIZE_SHRINK_END
	UITheme.tip(cut, "Jettison %s\n---\nSlot opens. Its cards leave the deck for the rest of the run." % inst.def.name)
	cut.pressed.connect(func():
		var err := RewardPool.jettison(Game.run, inst)
		if err == "":
			_jettisoning = false
			_ship_view.refresh(Game.run.ship)
			_continue()
		else:
			_status.text = err)
	info.add_child(cut)
	return wrap

func _card_chips(card_ids) -> Control:
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 4)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for cid in card_ids:
		var cd: CardDef = Database.card(cid)
		if cd == null:
			continue
		var chip := UITheme.chip(cd.name, UITheme.KIND_COLOUR.get(cd.kind, UITheme.ACCENT))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		UITheme.tip(chip, UITheme.card_tip(CardInstance.create(cd)))
		chip.mouse_entered.connect(_show_card_preview.bind(cd, chip))
		chip.mouse_exited.connect(_hide_card_preview)
		cards.add_child(chip)
	return cards

func _show_card_preview(cd: CardDef, anchor: Control) -> void:
	_hide_card_preview()
	var inst := CardInstance.create(cd)
	_preview_card = CardView.new()
	_preview_card.setup(inst)
	_preview_card.set_playable(true)
	_preview_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.add_child(_preview_card)

	# Place to the right of the chip, clamped inside the viewport.
	var origin := anchor.get_global_rect().position
	var size := CardView.CARD_SIZE
	var vp := get_viewport_rect().size
	var pos := origin + Vector2(anchor.size.x + 12, -20)
	pos.x = clampf(pos.x, 12.0, vp.x - size.x - 12.0)
	pos.y = clampf(pos.y, 12.0, vp.y - size.y - 12.0)
	_preview_card.global_position = pos

func _hide_card_preview() -> void:
	if _preview_card != null and is_instance_valid(_preview_card):
		_preview_card.queue_free()
	_preview_card = null

## A reactor showing "power 0" would hide the only reason to take it, so
## generation reads as a gain and draw as a cost. Stat bonuses matter too --
## they are half of what a hull part is for.
func _cost_bits(def: PartDef) -> PackedStringArray:
	var bits: PackedStringArray = []
	if def.power_draw > 0:
		bits.append("−%d power" % def.power_draw)
	bits.append("%d mass" % def.mass)
	for key in ["hull", "shield", "shield_regen", "evasion", "draw"]:
		var v := int(def.stats.get(key, 0))
		if v != 0:
			bits.append("+%d %s" % [v, key.replace("_", " ")])
	return bits

## Three expanding tiles per row so leftover viewport space stretches the
## cards instead of pooling as empty GridContainer slack.
func _fill_offer_rows(tiles: Array) -> void:
	var row: HBoxContainer = null
	var in_row := 0
	for tile in tiles:
		if row == null or in_row == 3:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_list.add_child(row)
			in_row = 0
		row.add_child(tile)
		in_row += 1
	if row != null:
		while in_row < 3:
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
			row.add_child(pad)
			in_row += 1

func _open_deck() -> void:
	_hide_card_preview()
	ShipStatusOverlay.open_deck(_overlay_host, _preview_layer, _close_deck)

func _close_deck() -> void:
	_preview_card = null
	if _overlay_host == null:
		return
	ShipStatusOverlay.close(_overlay_host, _preview_layer)

func _skip_for_repair() -> void:
	var healed := RewardPool.skip_for_repair(Game.run)
	if healed > 0:
		_status.text = "Field repair restored %d hull." % healed
	_continue()

func _toggle_jettison() -> void:
	if _jettisoning:
		_jettisoning = false
		_refresh()
		return
	if not bool(_reward.get("allow_jettison", false)):
		_status.text = "Nothing installed to jettison."
		return
	_jettisoning = true
	_refresh()

func _continue() -> void:
	_hide_card_preview()
	_close_deck()
	Game.after_reward()
