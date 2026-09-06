extends Control
## Title screen.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	centre.add_child(col)

	var title := UITheme.label("SALVAGE RUN", 58, UITheme.ACCENT, "Black")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := UITheme.label("Your ship is your deck.", 17, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UITheme.spacer(26))

	var start := UITheme.button("  NEW RUN  ")
	start.pressed.connect(func(): Game.start_run())
	col.add_child(start)

	var quit := UITheme.button("  QUIT  ", UITheme.PANEL_RAISED)
	quit.add_theme_color_override("font_color", UITheme.TEXT)
	quit.pressed.connect(func(): get_tree().quit())
	col.add_child(quit)

	col.add_child(UITheme.spacer(24))
	var stats := UITheme.label(
		"salvage %d    runs %d    best sale %d" % [
			Game.meta.salvage, Game.meta.runs_started, Game.meta.best_total],
		13, UITheme.TEXT_FAINT)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stats)

	var hint := UITheme.label(
		"Destroy the subsystem behind an enemy's telegraphed shot to cancel it.",
		13, UITheme.TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
