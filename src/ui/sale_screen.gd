extends Control
## End of run: the ship is appraised line by line.
##
## The receipt animates in one line at a time because it is the run's payoff and
## the moment the player learns what to do differently. A single static block of
## numbers reads as a defeat screen; a tallying one reads as a result.

var _lines: VBoxContainer
var _total_host: VBoxContainer

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Receipt can be taller than 720p once a wreck lists every part. Scroll the
	# tally; pin FIND ANOTHER SHIP so it is never clipped off the bottom.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 8)
	margin.add_child(shell)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)

	var wrap := PanelContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT, 1, 6, 18))
	scroll.add_child(wrap)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	wrap.add_child(col)

	col.add_child(UITheme.chrome_mark())

	var v: Dictionary = Game.last_valuation
	var survived := bool(v.get("survived", false))
	var won: bool = survived and bool(v.get("boss_killed", false))
	var title := UITheme.label("DELIVERED TO THE YARD" if won else "WRECK TOWED IN",
		24, UITheme.GOOD if won else UITheme.WARN, "Black")
	col.add_child(title)
	col.add_child(UITheme.label("ITEMISED APPRAISAL", 12, UITheme.ACCENT, "Bold"))
	col.add_child(UITheme.label(
		"You stole her, flew her, and sold her for salvage." if won
		else "Not every theft comes back whole — the yard still pays for scrap.",
		13, UITheme.TEXT_DIM, "SemiBold"))
	col.add_child(UITheme.spacer(4))

	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 3)
	col.add_child(_lines)

	_total_host = VBoxContainer.new()
	_total_host.add_theme_constant_override("separation", 6)
	col.add_child(_total_host)

	var back := UITheme.button("  FIND ANOTHER SHIP  ")
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): Game.goto_title())
	shell.add_child(back)

	_animate(v)

func _section(text: String) -> void:
	_lines.add_child(UITheme.spacer(4))
	_lines.add_child(UITheme.section(text))

func _receipt_row(left: String, mid: String, right: String, colour: Color,
		size: int = 14, weight: String = "Regular", mid_colour: Color = Color(),
		tip_text: String = "") -> void:
	var h := ThemedPanel.new()
	h.add_theme_stylebox_override("panel",
		UITheme.panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(row)
	var l := UITheme.label(left, size, colour, weight)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if mid != "":
		var mc := mid_colour if mid_colour.a > 0.0 else colour
		var m := UITheme.label(mid, 12, mc, "Bold")
		m.custom_minimum_size.x = 88
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(m)
	var r := UITheme.label(right, size, colour, weight)
	r.custom_minimum_size.x = 72
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(r)
	if tip_text != "":
		UITheme.tip(h, tip_text)
	_lines.add_child(h)


func _footer_row(left: String, right: String, colour: Color, size: int,
		weight: String, tip_text: String) -> void:
	var h := ThemedPanel.new()
	h.add_theme_stylebox_override("panel",
		UITheme.panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(row)
	var l := UITheme.label(left, size, colour, weight)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var r := UITheme.label(right, size, colour, weight)
	r.custom_minimum_size.x = 72
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(r)
	if tip_text != "":
		UITheme.tip(h, tip_text)
	_total_host.add_child(h)

func _animate(v: Dictionary) -> void:
	var saw_part := false
	var saw_bonus := false
	for line in v.get("lines", []):
		if not is_inside_tree():
			return
		var kind := String(line.get("kind", ""))
		if kind == "part" and not saw_part:
			_section("PARTS")
			saw_part = true
		elif kind != "part" and not saw_bonus:
			_section("BONUSES")
			saw_bonus = true
		_add_line(line)
		await get_tree().create_timer(0.09).timeout

	if not is_inside_tree():
		return
	_total_host.add_child(UITheme.hairline())
	_footer_row("SUBTOTAL", str(v.get("subtotal", 0)), UITheme.TEXT_DIM, 14, "SemiBold",
		"Subtotal\n%d\n---\nParts plus bonuses, before the sector multiplier." % v.get("subtotal", 0))
	await get_tree().create_timer(0.14).timeout
	if not is_inside_tree():
		return
	_footer_row(String(v.get("multiplier_label", "Sector")),
		"×%.2f" % v.get("multiplier", 1.0), UITheme.WARN, 15, "SemiBold",
		"%s\n×%.2f\n---\nDepth multiplies the haul. Dying keeps 40%%." % [
			v.get("multiplier_label", "Sector"), v.get("multiplier", 1.0)])
	await get_tree().create_timer(0.22).timeout
	if not is_inside_tree():
		return

	# TOTAL owns the eye — itemised lines drop back once the haul lands.
	_lines.modulate = Color(1, 1, 1, 0.62)
	_total_host.add_child(UITheme.spacer(8))
	var total := ThemedPanel.new()
	total.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.INK_GOOD, UITheme.GOOD, 2, 4, 14))
	var trow := HBoxContainer.new()
	total.add_child(trow)
	var tl := UITheme.label("TOTAL", 22, UITheme.GOOD, "Black")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tl)
	trow.add_child(UITheme.label("%d salvage" % v.get("total", 0), 24, UITheme.GOOD, "Black"))
	UITheme.tip(total, "TOTAL\n%d salvage\n---\nSpent at the Salvage Yard to unlock parts for the next theft." % v.get("total", 0))
	_total_host.add_child(total)

func _add_line(line: Dictionary) -> void:
	var kind := String(line.get("kind", ""))
	if kind == "part":
		var cond := String(line.get("condition", ""))
		var name := String(line.get("name", line.get("label", "")))
		var cond_blurb := "Pristine parts sell at full value."
		if cond == "worn":
			cond_blurb = "Wear cuts sale value. Taking hits costs you at the yard."
		elif cond == "wrecked":
			cond_blurb = "Wrecked parts are scrap. Destroyed subsystems zero this line."
		_receipt_row(name, cond.to_upper(), str(line["amount"]),
			UITheme.TEXT, 14, "SemiBold", UITheme.condition_colour(cond),
			"%s\n%s · %d salvage\n---\n%s" % [name, cond, int(line["amount"]), cond_blurb])
		return
	var name2 := String(line.get("name", line.get("label", "")))
	var detail := String(line.get("detail", ""))
	_receipt_row(name2, detail, str(line["amount"]), UITheme.SHIELD, 14, "SemiBold",
		Color(), "%s\n%s%d salvage\n---\nBonus on top of the parts." % [
			name2, (detail + " · ") if detail != "" else "", int(line["amount"])])
