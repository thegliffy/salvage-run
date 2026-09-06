class_name UITheme
extends RefCounted
## Central visual language for the demo.
##
## Panels are built as StyleBoxFlat rather than 9-patched from the purchased HUD
## art: those panels are fixed-shape with an asymmetric notch, so stretching
## them to arbitrary sizes distorts the artwork badly. The icons and the Exo
## typeface are where the bought assets genuinely earn their place, so those are
## used directly and the frames are matched to their palette.

const BG            := Color("0a0e14")
const PANEL         := Color("121a24")
const PANEL_RAISED  := Color("18222f")
const PANEL_DEEP    := Color("0d141c")
const ACCENT        := Color("29b6f6")   # cyan: interactive, player
const ACCENT_DIM    := Color("1c6f96")
const HOSTILE       := Color("ef5350")   # red: enemy, damage
const WARN          := Color("ffb74d")   # amber: intent, warnings
const GOOD          := Color("66bb6a")
const SHIELD        := Color("4dd0e1")
const TEXT          := Color("dce6f0")
const TEXT_DIM      := Color("7f8fa3")
const TEXT_FAINT    := Color("4d5a6b")
const RARE          := Color("ce93d8")
const INK_WARN      := Color("2a1d16")
const INK_GOOD      := Color("16241a")
const INK_HOSTILE   := Color("2a1416")

const KIND_COLOUR := {
	&"attack": HOSTILE,
	&"tech": ACCENT,
	&"maneuver": GOOD,
	&"status": Color("ab47bc"),
}

const RARITY_COLOUR := {
	&"starter": TEXT_DIM,
	&"common": TEXT_DIM,
	&"uncommon": ACCENT,
	&"rare": RARE,
}

static func font(weight: String = "Regular") -> FontFile:
	return load("res://assets/fonts/Exo-%s.ttf" % weight)

static func panel(bg: Color = PANEL, border: Color = Color(0, 0, 0, 0),
		width: int = 1, radius: int = 3, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb

static func label(text: String, size: int = 15, colour: Color = TEXT,
		weight: String = "Regular") -> Label:
	var l := ThemedLabel.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

static func button(text: String, colour: Color = ACCENT) -> Button:
	var b := ThemedButton.new()
	b.text = text
	b.add_theme_font_override("font", font("SemiBold"))
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.add_theme_stylebox_override("normal", panel(colour, Color(0,0,0,0), 0, 3, 12))
	b.add_theme_stylebox_override("hover", panel(colour.lightened(0.18), Color(0,0,0,0), 0, 3, 12))
	b.add_theme_stylebox_override("pressed", panel(colour.darkened(0.25), Color(0,0,0,0), 0, 3, 12))
	b.add_theme_stylebox_override("disabled", panel(PANEL_RAISED, Color(0,0,0,0), 0, 3, 12))
	return touch(b)

## Secondary / skip action: coloured outline on a raised panel, light text.
static func outline_button(text: String, colour: Color = GOOD) -> Button:
	var b := ThemedButton.new()
	b.text = text
	b.add_theme_font_override("font", font("SemiBold"))
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", colour)
	b.add_theme_color_override("font_hover_color", colour)
	b.add_theme_color_override("font_pressed_color", colour)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.add_theme_stylebox_override("normal", panel(PANEL_RAISED, colour, 1, 3, 12))
	b.add_theme_stylebox_override("hover", panel(PANEL, colour, 2, 3, 12))
	b.add_theme_stylebox_override("pressed", panel(PANEL_DEEP, colour, 1, 3, 12))
	b.add_theme_stylebox_override("disabled", panel(PANEL_RAISED, TEXT_FAINT, 1, 3, 12))
	return touch(b)

## Android / touch floor. Buttons and hull/system rows should hit this.
static func touch(c: Control, min_h: int = 48) -> Control:
	if c.custom_minimum_size.y < min_h:
		c.custom_minimum_size.y = min_h
	return c

static func chrome_mark() -> Label:
	return label("SALVAGE RUN", 18, ACCENT, "Black")

## Combat intent strip. Live shots are amber; silenced / fizzled shots go dim.
static func intent_style(offline: bool) -> StyleBoxFlat:
	if offline:
		return panel(INK_GOOD, TEXT_DIM, 1, 4, 12)
	return panel(INK_WARN, WARN, 2, 4, 12)

static func deficit_style(width: int = 2) -> StyleBoxFlat:
	return panel(INK_WARN, WARN, width, 4, 12)

## Amber callout used wherever draw exceeds hull output.
static func deficit_panel(n: int, sentence: String = "") -> PanelContainer:
	var wrap := ThemedPanel.new()
	wrap.add_theme_stylebox_override("panel", deficit_style(2))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)
	col.add_child(label("⚡ DEFICIT %d" % n, 14, WARN, "SemiBold"))
	if sentence != "":
		var b := label(sentence, 13, TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(b)
	if sentence != "":
		tip(wrap, "⚡ DEFICIT %d\n---\n%s" % [n, sentence])
	else:
		tip(wrap, "⚡ DEFICIT %d" % n)
	return wrap

static func energy_note(before: int, after: int) -> Label:
	if after < before:
		return label("energy %d → %d / turn" % [before, after], 13, WARN, "SemiBold")
	if after > before:
		return label("energy %d → %d / turn" % [before, after], 13, GOOD, "SemiBold")
	return label("energy stays %d / turn" % after, 12, TEXT_DIM, "SemiBold")

## A labelled bar. Returns the bar; the caller keeps it to update `value`.
static func bar(fill: Color, height: int = 14) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size.y = height
	pb.add_theme_stylebox_override("background", panel(Color("0c1218"), Color("2a3544"), 1, 2, 0))
	pb.add_theme_stylebox_override("fill", panel(fill, Color(0,0,0,0), 0, 2, 0))
	return pb

## Panel with a thicker left stripe — used for intent, deficit, and totals.
static func panel_stripe(bg: Color, stripe: Color, pad: int = 10,
		radius: int = 4) -> StyleBoxFlat:
	var sb := panel(bg, stripe, 1, radius, pad)
	sb.border_width_left = 5
	return sb

static func expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func hairline(colour: Color = TEXT_FAINT) -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = Color(colour.r, colour.g, colour.b, 0.38)
	sb.thickness = 1
	s.add_theme_stylebox_override("separator", sb)
	return s

static func box(bg: Color = PANEL, border: Color = Color(0, 0, 0, 0),
		width: int = 1, radius: int = 4, pad: int = 10) -> ThemedPanel:
	var wrap := ThemedPanel.new()
	wrap.add_theme_stylebox_override("panel", panel(bg, border, width, radius, pad))
	return wrap

static func badge(text: String, colour: Color, filled: bool = false) -> PanelContainer:
	var wrap := box(colour if filled else Color(colour.r, colour.g, colour.b, 0.16),
		colour, 1, 2, 6)
	var fg := BG if filled else colour
	wrap.add_child(label(text, 11, fg, "Bold"))
	return wrap

static func chip(text: String, colour: Color = ACCENT) -> PanelContainer:
	var wrap := box(PANEL_RAISED, colour, 1, 3, 6)
	wrap.add_child(label(text, 12, TEXT))
	return wrap

static func metric(caption: String, value: String, colour: Color = TEXT,
		tip_text: String = "") -> Control:
	var wrap := ThemedPanel.new()
	wrap.add_theme_stylebox_override("panel", panel(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)
	col.add_child(label(caption, 10, TEXT_FAINT, "Bold"))
	col.add_child(label(value, 15, colour, "SemiBold"))
	if tip_text != "":
		tip(wrap, tip_text)
	return wrap

static func ghost_button(text: String) -> Button:
	var b := button(text, ACCENT_DIM)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	return b

static func section(text: String) -> Label:
	return label(text, 18, TEXT, "Bold")

## Amber / green / red callout used for power deficit, payouts, and silenced shots.
static func callout(title: String, body: String = "",
		kind: StringName = &"warn") -> PanelContainer:
	var ink := INK_WARN
	var border := WARN
	var title_c := WARN
	match kind:
		&"good":
			ink = INK_GOOD
			border = GOOD
			title_c = GOOD
		&"hostile":
			ink = INK_HOSTILE
			border = HOSTILE
			title_c = HOSTILE
		&"info":
			ink = PANEL
			border = ACCENT_DIM
			title_c = ACCENT
	var wrap := ThemedPanel.new()
	wrap.add_theme_stylebox_override("panel", panel_stripe(ink, border, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(col)
	col.add_child(label(title, 13, title_c, "Bold"))
	if body != "":
		var b := label(body, 12, TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(b)
	if body != "":
		tip(wrap, "%s\n%s" % [title, body])
	else:
		tip(wrap, title)
	return wrap

static func rarity_colour(rarity: StringName) -> Color:
	return RARITY_COLOUR.get(rarity, TEXT_DIM)

static func condition_colour(condition: String) -> Color:
	match condition:
		"pristine":
			return GOOD
		"worn", "stripped":
			return WARN
		"wrecked":
			return HOSTILE
		_:
			return TEXT_DIM

## Load optional artwork. Returns null instead of erroring when the file is
## absent -- redistributable icons and portraits ship with the repo, but a
## missing file (or a commercial pack that was never added) must still run.
static func art(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res if res is Texture2D else null

static func spacer(h: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

## Attach a themed tooltip. First line is the title; a `---` line becomes a rule.
static func tip(node: Control, text: String) -> void:
	if node == null or text == "":
		return
	node.tooltip_text = text
	if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		node.mouse_filter = Control.MOUSE_FILTER_STOP

static func make_tooltip(for_text: String) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", panel(PANEL, ACCENT, 1, 4, 12))
	wrap.custom_minimum_size.x = 248
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	wrap.add_child(col)
	var lines := for_text.split("\n")
	if lines.is_empty():
		return wrap
	var title := label(lines[0], 14, ACCENT, "Bold")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 224
	col.add_child(title)
	for i in range(1, lines.size()):
		var line := lines[i]
		if line == "":
			continue
		if line == "---":
			col.add_child(hairline(ACCENT_DIM))
			continue
		var body := label(line, 12, TEXT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 224
		col.add_child(body)
	return wrap

static func card_tip(card: CardInstance, energy: int = -1) -> String:
	if card == null or card.def == null:
		return ""
	var bits: PackedStringArray = []
	bits.append(card.display_name())
	var meta := "%s · cost %d" % [String(card.def.kind), card.cost()]
	match card.def.target:
		CardDef.Target.NONE:
			meta += " · plays immediately"
		CardDef.Target.ENEMY_SYSTEM:
			meta += " · enemy system"
			if card.def.can_target_hull():
				meta += " or hull"
		CardDef.Target.ENEMY_SHIP:
			meta += " · enemy ship"
		CardDef.Target.SELF_SYSTEM:
			meta += " · your system"
		CardDef.Target.SELF_SHIP:
			meta += " · your ship"
	bits.append(meta)
	bits.append("---")
	var body := card.text()
	if body != "":
		bits.append(body)
	if not card.def.keywords.is_empty():
		var kw: PackedStringArray = []
		for k in card.def.keywords:
			kw.append(String(k))
		bits.append("keywords: %s" % ", ".join(kw))
	if energy >= 0 and card.cost() > energy:
		bits.append("not enough energy (%d needed)" % card.cost())
	return "\n".join(bits)

static func part_tip(def: PartDef, extra: String = "") -> String:
	if def == null:
		return ""
	var bits: PackedStringArray = []
	bits.append(def.name)
	var meta := "%s slot" % String(def.slot)
	if def.power_draw > 0:
		meta += " · −%d power" % def.power_draw
	meta += " · %d mass" % def.mass
	if def.power_gen > 0:
		meta += " · +%d output" % def.power_gen
	bits.append(meta)
	bits.append("---")
	if def.flavor != "":
		bits.append(def.flavor)
	var grants: PackedStringArray = []
	for cid in def.grants:
		var cd: CardDef = Database.card(cid)
		if cd != null:
			grants.append("%s (%d)" % [cd.name, cd.cost])
	if not grants.is_empty():
		bits.append("grants: %s" % ", ".join(grants))
	if extra != "":
		bits.append(extra)
	return "\n".join(bits)

static func power_tip(bud: Dictionary) -> String:
	var deficit := int(bud.get("deficit", 0))
	var title := "POWER DEFICIT %d" % deficit if deficit > 0 else "Power budget"
	var body := "Hull output %d · part draw %d · energy %d / turn." % [
		bud.get("output", 0), bud.get("draw", 0), bud.get("energy", 0)]
	if deficit > 0:
		body += " Every point of draw past output cuts energy for the rest of the run."
	else:
		body += " Taking more draw than output permanently lowers energy."
	return "%s\n---\n%s" % [title, body]

static func system_tip(s: ShipSystem, intent_source: bool = false) -> String:
	if s == null:
		return ""
	var bits: PackedStringArray = []
	bits.append(s.display_name)
	var job: String = SystemView.BLURB.get(s.id, "")
	bits.append("%s%s" % [String(s.id), (" — " + job) if job != "" else ""])
	bits.append("---")
	bits.append("integrity %d / %d" % [s.integrity, s.max_integrity])
	if s.integrity <= 0:
		bits.append("Destroyed — shots through this spill into hull.")
	elif s.offline_turns > 0:
		bits.append("Suppressed for %d turn(s)." % s.offline_turns)
	elif intent_source:
		bits.append("Firing this turn. Knock it offline to silence the shot.")
	else:
		bits.append("Soft target — chip it to weaken, or shoot the hull instead.")
	return "\n".join(bits)
