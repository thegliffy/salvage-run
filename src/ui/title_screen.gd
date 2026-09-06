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
	card.custom_minimum_size.x = 640
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

	var start := UITheme.button("  STEAL A SHIP  ")
	UITheme.tip(start, "Steal a ship\n---\nBegin a run. Steal a hull, fight to the boss, sell what you built.")
	start.pressed.connect(func(): Game.start_run())
	stack.add_child(start)

	var yard := UITheme.ghost_button("  SALVAGE YARD  ")
	UITheme.tip(yard, "Salvage Yard\n---\nSpend salvage to unlock parts into the next run's reward pool.")
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

	var locked_n := Game.meta.unlockable().size()
	var meta := UITheme.label(
		"salvage %d  ·  ships stolen %d  ·  best haul %d  ·  %d parts locked" % [
			Game.meta.salvage, Game.meta.runs_started, Game.meta.best_total, locked_n],
		11, UITheme.TEXT_FAINT)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.tip(meta,
		"Meta\n---\nSalvage is spent at the yard. Best haul is the highest single-run sale.")
	col.add_child(meta)
