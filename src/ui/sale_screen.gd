extends Control
## End of run: the ship is appraised line by line.
##
## The receipt animates in one line at a time because it is the run's payoff and
## the moment the player learns what to do differently. A single static block of
## numbers reads as a defeat screen; a tallying one reads as a result.

var _lines: VBoxContainer

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT_DIM, 1, 4, 26))
	wrap.custom_minimum_size.x = 560
	centre.add_child(wrap)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	wrap.add_child(col)

	var v: Dictionary = Game.last_valuation
	var won: bool = v.get("boss_killed", false)
	var title := UITheme.label("DELIVERED TO THE YARD" if won else "WRECK TOWED IN",
		28, UITheme.GOOD if won else UITheme.WARN, "Black")
	col.add_child(title)
	col.add_child(UITheme.label(
		"You stole her, flew her, and sold her for salvage." if won
		else "Not every theft comes back whole — the yard still pays for scrap.",
		14, UITheme.TEXT_DIM))
	col.add_child(UITheme.label(
		"Salvage unlocks new parts for the next run — and bigger ships to steal.",
		13, UITheme.TEXT_FAINT))
	col.add_child(UITheme.spacer(14))

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 3)
	col.add_child(_lines)

	col.add_child(UITheme.spacer(16))
	var back := UITheme.button("  FIND ANOTHER SHIP  ")
	back.pressed.connect(func(): Game.goto_title())
	col.add_child(back)

	_animate(v)

func _row(left: String, right: String, colour: Color, size: int = 14,
		weight: String = "Regular") -> void:
	var h := HBoxContainer.new()
	var l := UITheme.label(left, size, colour, weight)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UITheme.label(right, size, colour, weight))
	_lines.add_child(h)

func _animate(v: Dictionary) -> void:
	for line in v.get("lines", []):
		if not is_inside_tree():
			return
		_row(line["label"], str(line["amount"]),
			UITheme.TEXT if line["kind"] == "part" else UITheme.SHIELD)
		await get_tree().create_timer(0.09).timeout

	if not is_inside_tree():
		return
	var sep := HSeparator.new()
	_lines.add_child(sep)
	_row("subtotal", str(v.get("subtotal", 0)), UITheme.TEXT_DIM)
	await get_tree().create_timer(0.14).timeout
	if not is_inside_tree():
		return
	_row(v.get("multiplier_label", ""), "x%.2f" % v.get("multiplier", 1.0), UITheme.WARN)
	await get_tree().create_timer(0.22).timeout
	if not is_inside_tree():
		return
	_row("TOTAL", "%d salvage" % v.get("total", 0), UITheme.GOOD, 20, "Black")
