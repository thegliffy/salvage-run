extends Control
## Between fights: repair worn parts, strip a card, or forge a mount.
##
## This is the salvage-node screen in miniature. It is here in the demo because
## stripping is the only way the player has any say over their deck, and a demo
## that never shows it hides half the design.

const REPAIR_COST := 40

var _credits: Label
var _list: VBoxContainer
var _deck: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(UITheme.label("SALVAGE YARD", 30, UITheme.ACCENT, "Black"))
	col.add_child(UITheme.label(
		"Cut a card from a mount, or forge one so remaining cards play upgraded. Both cost credits.",
		14, UITheme.TEXT_DIM))
	col.add_child(UITheme.spacer(6))

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 24)
	col.add_child(status)
	_credits = UITheme.label("", 15, UITheme.WARN, "SemiBold")
	status.add_child(_credits)
	_deck = UITheme.label("", 15, UITheme.TEXT, "SemiBold")
	status.add_child(_deck)
	col.add_child(UITheme.spacer(8))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	col.add_child(scroll)

	var go := UITheme.button("  BACK TO MAP  ")
	go.pressed.connect(func(): Game.goto_map())
	col.add_child(go)
	_refresh()

func _refresh() -> void:
	var run: RunState = Game.run
	var strip_cost := SalvageYard.credit_cost(run)
	var can_afford_strip := run.credits >= strip_cost
	var forge_cost := SalvageYard.forge_cost(run)
	var can_afford_forge := run.credits >= forge_cost
	_credits.text = "credits %d" % run.credits
	_deck.text = "deck %d   hull %d/%d   power %d/%d   weapon %d/%d  hull-slot %d/%d  utility %d/%d" % [
		run.profile.deck.size(), run.hull_carryover, run.profile.max_hull,
		run.profile.power_draw, run.profile.power,
		run.ship.installed_in(ShipLoadout.SLOT_WEAPON).size(), run.ship.slot_capacity(ShipLoadout.SLOT_WEAPON),
		run.ship.installed_in(ShipLoadout.SLOT_HULL).size(), run.ship.slot_capacity(ShipLoadout.SLOT_HULL),
		run.ship.installed_in(ShipLoadout.SLOT_UTILITY).size(), run.ship.slot_capacity(ShipLoadout.SLOT_UTILITY)]
	for c in _list.get_children():
		c.queue_free()

	for inst in run.ship.parts:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel",
			UITheme.panel(UITheme.PANEL, Color(0,0,0,0), 0, 3, 10))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)

		var status := "ok"
		if inst.is_wrecked():
			status = "wrecked"
		elif inst.upgraded and inst.is_stripped():
			status = "forged, stripped"
		elif inst.upgraded:
			status = "forged"
		elif inst.is_stripped():
			status = "stripped"
		var label := "%s  [%s]  (%s)" % [inst.def.name, String(inst.def.slot).left(3).to_upper(),
			status]
		var nm := UITheme.label(label, 15, 
			UITheme.HOSTILE if inst.is_wrecked() else (UITheme.GOOD if inst.upgraded else UITheme.TEXT), "SemiBold")
		nm.custom_minimum_size.x = 210
		h.add_child(nm)

		if inst.is_wrecked():
			var fix := UITheme.button("REPAIR (%d)" % REPAIR_COST, UITheme.GOOD)
			fix.disabled = run.credits < REPAIR_COST
			fix.pressed.connect(func():
				run.add_credits(-REPAIR_COST)
				inst.wear = 0
				run.recompile()
				_refresh())
			h.add_child(fix)

		for i in inst.def.grants.size():
			var cd: CardDef = Database.card(inst.def.grants[i])
			if cd == null:
				continue
			var stripped_this: bool = inst.stripped_index == i
			var preview := CardInstance.create(cd, inst.upgraded)
			var b := UITheme.button(preview.display_name(),
				UITheme.PANEL_RAISED if stripped_this else UITheme.ACCENT_DIM)
			b.add_theme_color_override("font_color",
				UITheme.TEXT_FAINT if stripped_this else UITheme.card_name_colour(inst.upgraded))
			b.disabled = stripped_this or not inst.can_strip() or not can_afford_strip
			if stripped_this:
				b.text = "✖ " + preview.display_name()
				UITheme.tip(b, UITheme.card_tip(preview) + "\n---\nAlready stripped.")
			elif not inst.can_strip():
				UITheme.tip(b, UITheme.card_tip(preview) + "\n---\nThis mount is already stripped.")
			elif not can_afford_strip:
				UITheme.tip(b, UITheme.card_tip(preview)
					+ "\n---\nNeed %d credits (have %d)." % [strip_cost, run.credits])
			else:
				UITheme.tip(b, UITheme.card_tip(preview)
					+ "\n---\nStrip this card for %d credits. Also cuts sale value by 25%%." % strip_cost)
			var idx := i
			b.pressed.connect(func():
				SalvageYard.strip(run, inst, idx)
				_refresh())
			h.add_child(b)
		var forge := UITheme.button("FORGE (%d)" % forge_cost, UITheme.GOOD)
		forge.disabled = inst.upgraded or not can_afford_forge
		if inst.upgraded:
			forge.text = "FORGED"
			UITheme.tip(forge, "Already forged. Remaining cards play upgraded.")
		elif not can_afford_forge:
			UITheme.tip(forge, "Need %d credits (have %d)." % [forge_cost, run.credits])
		else:
			UITheme.tip(forge, "Forge this mount for %d credits. Remaining cards play upgraded." % forge_cost)
		forge.pressed.connect(func():
			SalvageYard.forge(run, inst)
			_refresh())
		h.add_child(forge)
		_list.add_child(row)
