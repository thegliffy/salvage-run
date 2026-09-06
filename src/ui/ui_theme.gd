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
const ACCENT        := Color("29b6f6")   # cyan: interactive, player
const ACCENT_DIM    := Color("1c6f96")
const HOSTILE       := Color("ef5350")   # red: enemy, damage
const WARN          := Color("ffb74d")   # amber: intent, warnings
const GOOD          := Color("66bb6a")
const SHIELD        := Color("4dd0e1")
const TEXT          := Color("dce6f0")
const TEXT_DIM      := Color("7f8fa3")
const TEXT_FAINT    := Color("4d5a6b")

const KIND_COLOUR := {
	&"attack": HOSTILE,
	&"tech": ACCENT,
	&"maneuver": GOOD,
	&"status": Color("ab47bc"),
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
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l

static func button(text: String, colour: Color = ACCENT) -> Button:
	var b := Button.new()
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
	return b

## A labelled bar. Returns the bar; the caller keeps it to update `value`.
static func bar(fill: Color, height: int = 14) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size.y = height
	pb.add_theme_stylebox_override("background", panel(Color("0c1218"), TEXT_FAINT, 1, 2, 0))
	pb.add_theme_stylebox_override("fill", panel(fill, Color(0,0,0,0), 0, 2, 0))
	return pb

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
