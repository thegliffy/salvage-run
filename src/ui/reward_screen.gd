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

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_reward = Game.pending_reward
	var tier := int(_reward.get("tier", 1))
	var title := "SALVAGE RECOVERED"
	if tier == 2:
		title = "MINI-BOSS DOWN"
	elif tier >= 3:
		title = "SECTOR BOSS DOWN"
	_heading = UITheme.label(title, 28, UITheme.GOOD, "Black")
	col.add_child(_heading)
	col.add_child(UITheme.label(
		"Take a part — skip to field-repair the hull.",
		13, UITheme.TEXT_DIM))

	# Credits and the improvement are automatic; only the part is a choice.
	var imp: ImprovementDef = _reward.get("improvement")
	if imp != null and Game.run.ship.improvements.find(imp.id) == -1:
		Game.run.ship.add_improvement(imp.id)
		Game.run.recompile()
	col.add_child(_payout_banner(imp))

	_ship_view = ShipView.new()
	_ship_view.custom_minimum_size = Vector2(0, 170)
	_ship_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_ship_view)
	_ship_view.refresh(Game.run.ship)

	_power_panel = ThemedPanel.new()
	col.add_child(_power_panel)

	_status = UITheme.label("", 14, UITheme.TEXT, "SemiBold")
	col.add_child(_status)

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)

	_skip_btn = UITheme.button("", UITheme.GOOD)
	_skip_btn.pressed.connect(_skip_for_repair)
	col.add_child(_skip_btn)

	var jettison := UITheme.ghost_button("  JETTISON A PART INSTEAD  ")
	UITheme.tip(jettison, "Jettison\n---\nDump an installed part to free its slot and thin the deck.")
	jettison.pressed.connect(_toggle_jettison)
	col.add_child(jettison)

	# Floating card preview sits above everything; ignores mouse so hover
	# doesn't flicker when the cursor is over the preview itself.
	_preview_layer = Control.new()
	_preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.z_index = 20
	add_child(_preview_layer)

	_refresh()

func _payout_banner(imp: ImprovementDef) -> Control:
	var wrap := UITheme.callout(
		"+%d CREDITS" % int(_reward.get("credits", 0)),
		"" if imp == null else "SHIP IMPROVEMENT — %s (%s): %s" % [
			imp.name, String(imp.rarity).to_upper(), imp.text],
		&"good")
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
	if _jettisoning:
		_heading.text = "JETTISON A PART"
		_skip_btn.visible = false
		for inst in run.ship.parts:
			_list.add_child(_jettison_row(inst))
	else:
		_skip_btn.visible = true
		_heading.text = "SALVAGE RECOVERED" if int(_reward.get("tier", 1)) == 1 \
			else ("MINI-BOSS DOWN" if int(_reward.get("tier", 1)) == 2 else "SECTOR BOSS DOWN")
		for offer in _reward.get("parts", []):
			_list.add_child(_offer_row(offer))

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
		_power_panel.add_theme_stylebox_override("panel",
			UITheme.panel_stripe(UITheme.INK_WARN, UITheme.WARN, 10))
	else:
		_power_panel.add_theme_stylebox_override("panel",
			UITheme.panel(UITheme.PANEL, UITheme.ACCENT_DIM, 1, 4, 10))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_power_panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UITheme.label(
		"POWER DEFICIT  %d" % deficit if deficit > 0 else "POWER BUDGET",
		13, UITheme.WARN if deficit > 0 else UITheme.TEXT, "Bold"))
	head.add_child(UITheme.expand())
	head.add_child(UITheme.metric("OUTPUT", str(output),
		UITheme.WARN if deficit > 0 else UITheme.TEXT))
	head.add_child(UITheme.metric("DRAW", str(draw),
		UITheme.WARN if deficit > 0 else UITheme.TEXT))
	head.add_child(UITheme.metric("ENERGY", "%d / turn" % energy,
		UITheme.WARN if deficit > 0 else UITheme.ACCENT))

	if deficit > 0:
		col.add_child(UITheme.label(
			"Overdrawn — every point of draw past hull output cuts another energy this run. Jettison a hungry part or find a power improvement.",
			12, UITheme.WARN))
	else:
		col.add_child(UITheme.label(
			"Headroom %d. Parts list their power draw (−N power). Taking more than you generate permanently lowers energy." % (output - draw),
			12, UITheme.TEXT_DIM))
	UITheme.tip(_power_panel, UITheme.power_tip(bud))

func _offer_row(offer: Dictionary) -> Control:
	var def: PartDef = offer["def"]
	var rarity: StringName = offer.get("rarity", &"common")
	var rarity_c := UITheme.rarity_colour(rarity)
	var wrap := UITheme.box(UITheme.PANEL, rarity_c, 1, 4, 12)
	UITheme.tip(wrap, UITheme.part_tip(def))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	wrap.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	row.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	head.add_child(UITheme.label(def.name, 20, UITheme.TEXT, "Black"))
	head.add_child(UITheme.badge(String(rarity).to_upper(), rarity_c))
	head.add_child(UITheme.badge(String(def.slot).to_upper(), UITheme.ACCENT))
	head.add_child(UITheme.expand())
	for bit in _cost_bits(def):
		head.add_child(UITheme.chip(bit, UITheme.TEXT_FAINT))

	if def.flavor != "":
		info.add_child(UITheme.label(def.flavor, 12, UITheme.TEXT_FAINT))

	# Preview what this part does to combat energy if taken / swapped in.
	var replace_target: PartInstance = null if offer["can_install"] else offer.get("replaces")
	var after: Dictionary = Game.run.ship.power_budget(def, replace_target)
	var before: Dictionary = Game.run.ship.power_budget()
	var energy_drop := int(after["energy"]) < int(before["energy"])
	var after_def := int(after["deficit"])
	if energy_drop or after_def > 0:
		var title := "POWER OVERDRAW"
		if after_def > 0:
			title = "POWER DEFICIT  %d" % after_def
		info.add_child(UITheme.callout(title,
			"energy %d → %d / turn. Taking this cuts energy every remaining fight." % [
				before["energy"], after["energy"]],
			&"warn"))
	elif int(after["energy"]) > int(before["energy"]):
		info.add_child(UITheme.label(
			"energy %d → %d / turn" % [before["energy"], after["energy"]],
			12, UITheme.GOOD, "SemiBold"))
	elif def.power_draw > 0:
		info.add_child(UITheme.label(
			"uses %d power  ·  energy stays %d" % [def.power_draw, after["energy"]],
			12, UITheme.TEXT_DIM, "SemiBold"))

	info.add_child(UITheme.label("GRANTS — hover a card", 11, UITheme.TEXT_FAINT, "Bold"))
	info.add_child(_card_chips(def.grants))

	var take := UITheme.button("  TAKE  ", UITheme.GOOD)
	if not offer["can_install"]:
		var replaces: PartInstance = offer.get("replaces")
		if replaces != null:
			take.text = "  REPLACE %s  " % replaces.def.name
			take.add_theme_stylebox_override("normal",
				UITheme.panel(UITheme.WARN, Color(0,0,0,0), 0, 3, 12))
			UITheme.tip(take, "Replace %s\n---\nFrees that slot and its cards, then installs %s." % [
				replaces.def.name, def.name])
		else:
			take.disabled = true
			UITheme.tip(take, "No free %s slot." % String(def.slot))
	else:
		UITheme.tip(take, "Install %s\n---\nAdds its three cards to the deck. Check power draw first." % def.name)
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
	row.add_child(take)
	return wrap

func _jettison_row(inst: PartInstance) -> Control:
	var wrap := UITheme.box(UITheme.PANEL, UITheme.HOSTILE, 1, 4, 12)
	UITheme.tip(wrap, UITheme.part_tip(inst.def, "Jettison frees the slot and removes these cards."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	wrap.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	head.add_child(UITheme.label(inst.def.name, 17, UITheme.TEXT, "Bold"))
	head.add_child(UITheme.label("[%s]" % String(inst.def.slot).to_upper(), 12,
		UITheme.ACCENT, "SemiBold"))
	head.add_child(UITheme.label("frees the slot and these cards", 12, UITheme.TEXT_FAINT))
	info.add_child(_card_chips(inst.granted_cards()))

	var cut := UITheme.button("  JETTISON  ", UITheme.HOSTILE)
	UITheme.tip(cut, "Jettison %s\n---\nSlot opens. Its cards leave the deck for the rest of the run." % inst.def.name)
	cut.pressed.connect(func():
		var err := RewardPool.jettison(Game.run, inst)
		if err == "":
			_jettisoning = false
			_ship_view.refresh(Game.run.ship)
			_continue()
		else:
			_status.text = err)
	row.add_child(cut)
	return wrap

func _card_chips(card_ids) -> Control:
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	for cid in card_ids:
		var cd: CardDef = Database.card(cid)
		if cd == null:
			continue
		var chip := UITheme.chip(cd.name, UITheme.KIND_COLOUR.get(cd.kind, UITheme.ACCENT))
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
	Game.after_reward()
