extends Control
## Title screen — the job: steal a ship, sell it for salvage, unlock the next score.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT, 1, 6, 28))
	card.custom_minimum_size.x = 680
	centre.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var kicker := HBoxContainer.new()
	kicker.add_theme_constant_override("separation", 10)
	col.add_child(kicker)
	kicker.add_child(UITheme.label("ROGUELIKE DECKBUILDER", 11, UITheme.ACCENT, "Bold"))
	kicker.add_child(UITheme.expand())
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.05"))
	kicker.add_child(UITheme.badge("v%s" % ver, UITheme.ACCENT_DIM))

	var title := UITheme.label("SALVAGE RUN", 52, UITheme.ACCENT, "Black")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := UITheme.label("Steal a ship. Sell it for salvage. Unlock the next one.",
		16, UITheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var pitch := UITheme.label(
		"Bolt on parts as you go — your ship is your deck. What survives the run gets stripped for parts and hulls worth stealing.",
		13, UITheme.TEXT_DIM)
	pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size.x = 540
	col.add_child(pitch)
	col.add_child(UITheme.spacer(4))

	var art := UITheme.art("res://assets/ships/salvager-hull.png")
	if art != null:
		var bay := PanelContainer.new()
		bay.add_theme_stylebox_override("panel",
			UITheme.panel(UITheme.PANEL_DEEP, UITheme.ACCENT_DIM, 1, 4, 8))
		col.add_child(bay)
		var ship := TextureRect.new()
		ship.texture = art
		ship.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ship.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ship.custom_minimum_size = Vector2(420, 180)
		ship.modulate = Color(1, 1, 1, 0.95)
		bay.add_child(ship)
		col.add_child(UITheme.spacer(4))
	else:
		col.add_child(UITheme.spacer(8))

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	col.add_child(stack)

	stack.add_child(UITheme.label("STEAL A SHIP", 14, UITheme.TEXT_DIM, "Bold"))
	var picks := HBoxContainer.new()
	picks.add_theme_constant_override("separation", 10)
	stack.add_child(picks)
	for choice in StarterShips.choices():
		picks.add_child(_ship_pick(choice))

	var yard := UITheme.ghost_button("  SALVAGE YARD  ")
	UITheme.tip(yard, "Salvage Yard\n---\nSpend salvage to unlock hulls and parts. The Tank is the cheapest hull unlock.")
	yard.pressed.connect(func(): Game.goto_unlock_shop())
	stack.add_child(yard)

	var quit := UITheme.button("  QUIT  ", UITheme.PANEL_RAISED)
	quit.add_theme_color_override("font_color", UITheme.TEXT)
	quit.add_theme_color_override("font_hover_color", UITheme.TEXT)
	quit.add_theme_color_override("font_pressed_color", UITheme.TEXT)
	quit.pressed.connect(func(): get_tree().quit())
	stack.add_child(quit)

	col.add_child(UITheme.spacer(8))
	col.add_child(UITheme.hairline())

	var locked_n := Game.meta.unlockable().size() + Game.meta.unlockable_ships().size()
	var meta := UITheme.label(
		"salvage %d  ·  ships stolen %d  ·  best haul %d  ·  %d locked" % [
			Game.meta.salvage, Game.meta.runs_started, Game.meta.best_total, locked_n],
		11, UITheme.TEXT_FAINT)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.tip(meta,
		"Meta\n---\nSalvage is spent at the yard. Unlock parts first; the Tank is the cheapest hull.")
	col.add_child(meta)

func _ship_pick(choice: Dictionary) -> Control:
	var ship_id: StringName = choice["id"]
	var unlocked := Game.meta.is_ship_unlocked(ship_id)
	var cost := int(choice.get("unlock_cost", 0))
	var wrap := UITheme.box(UITheme.PANEL_RAISED, UITheme.ACCENT_DIM, 1, 4, 10)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	wrap.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(UITheme.label(String(choice["name"]).to_upper(), 16, UITheme.ACCENT, "Bold"))
	if not unlocked:
		head.add_child(UITheme.badge("LOCKED", UITheme.WARN))
	var blurb := UITheme.label(String(choice["blurb"]), 12, UITheme.TEXT_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(blurb)
	if unlocked:
		var steal := UITheme.button("  STEAL  ")
		steal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.tip(steal, "Steal the %s\n---\n%s\nBegin a run with this hull." % [
			choice["name"], choice["blurb"]])
		steal.pressed.connect(func(): Game.start_run(-1, ship_id))
		col.add_child(steal)
	else:
		var can := Game.meta.can_afford_ship(ship_id)
		var buy := UITheme.button(
			"  UNLOCK  %d  " % cost if can else "  NEED  %d  " % cost,
			UITheme.GOOD if can else UITheme.PANEL_RAISED)
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy.disabled = not can
		if not can:
			buy.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
			UITheme.tip(buy, "Need %d salvage (have %d).\n---\nSell a ship, then unlock the Tank here or in the Salvage Yard." % [
				cost, Game.meta.salvage])
		else:
			UITheme.tip(buy, "Unlock the %s\n---\n%d salvage. Cheapest hull unlock — costs more than any part." % [
				choice["name"], cost])
		buy.pressed.connect(func():
			if Game.meta.unlock_ship(ship_id):
				SaveSystem.save_meta(Game.meta)
				Game.goto_title())
		col.add_child(buy)
	return wrap
