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

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	centre.add_child(col)

	var title := UITheme.label("SALVAGE RUN", 58, UITheme.ACCENT, "Black")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := UITheme.label("Steal a ship. Sell it for salvage. Unlock the next one.",
		17, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var pitch := UITheme.label(
		"Bolt on parts as you go — your ship is your deck. What survives the run gets stripped for parts and hulls worth stealing.",
		13, UITheme.TEXT_FAINT)
	pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.custom_minimum_size.x = 520
	col.add_child(pitch)
	col.add_child(UITheme.spacer(22))

	var start := UITheme.button("  STEAL A SHIP  ")
	start.pressed.connect(func(): Game.start_run())
	col.add_child(start)

	var quit := UITheme.button("  QUIT  ", UITheme.PANEL_RAISED)
	quit.add_theme_color_override("font_color", UITheme.TEXT)
	quit.pressed.connect(func(): get_tree().quit())
	col.add_child(quit)

	col.add_child(UITheme.spacer(24))
	var stats := UITheme.label(
		"salvage %d    ships stolen %d    best haul %d" % [
			Game.meta.salvage, Game.meta.runs_started, Game.meta.best_total],
		13, UITheme.TEXT_FAINT)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stats)

	var hint := UITheme.label(
		"Shoot the hull to finish fights. Soft-disable guns or shields to buy a turn.",
		12, UITheme.TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
