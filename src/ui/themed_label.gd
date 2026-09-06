class_name ThemedLabel
extends Label
## Label that renders UITheme tooltips instead of the engine default.

func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_tooltip(for_text)
