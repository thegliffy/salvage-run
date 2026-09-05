extends Node
## Content registry.
##
## All balance-facing content lives in JSON under res://content/ rather than in
## .tres resources. Reasons: it diffs cleanly in git, it can be generated and
## rebalanced by scripts without opening the editor, and a designer can edit a
## hundred card numbers in one pass. The tradeoff is no editor autocomplete on
## content, which is why load() validates hard and fails loudly.

const CONTENT_DIR := "res://content/"

var cards: Dictionary = {}    # StringName -> CardDef
var parts: Dictionary = {}    # StringName -> PartDef
var enemies: Dictionary = {}  # StringName -> EnemyDef

var _errors: Array[String] = []

func _ready() -> void:
	load_all()

func load_all() -> void:
	_errors.clear()
	cards = _load_defs("cards.json", CardDef)
	parts = _load_defs("parts.json", PartDef)
	enemies = _load_defs("enemies.json", EnemyDef)
	_validate_references()
	if not _errors.is_empty():
		for e in _errors:
			push_error("[Database] " + e)

func _load_defs(filename: String, def_class) -> Dictionary:
	var out: Dictionary = {}
	var path := CONTENT_DIR + filename
	if not FileAccess.file_exists(path):
		_errors.append("missing content file: " + path)
		return out
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("malformed JSON (expected object at root): " + path)
		return out
	for id in parsed:
		var def = def_class.new()
		var err: String = def.from_dict(StringName(id), parsed[id])
		if err != "":
			_errors.append("%s[%s]: %s" % [filename, id, err])
			continue
		out[StringName(id)] = def
	return out

## Catch dangling ids at load time rather than mid-combat.
func _validate_references() -> void:
	for pid in parts:
		var p: PartDef = parts[pid]
		for cid in p.grants:
			if not cards.has(cid):
				_errors.append("part '%s' grants unknown card '%s'" % [pid, cid])
	for eid in enemies:
		var e: EnemyDef = enemies[eid]
		for intent in e.intents:
			if not e.has_system(intent.get("requires_system", &"")):
				_errors.append("enemy '%s' intent '%s' requires system '%s' it does not have"
					% [eid, intent.get("id", "?"), intent.get("requires_system", "?")])

func errors() -> Array[String]:
	return _errors

func card(id: StringName) -> CardDef:
	return cards.get(id)

func part(id: StringName) -> PartDef:
	return parts.get(id)

func enemy(id: StringName) -> EnemyDef:
	return enemies.get(id)

func parts_matching(filter: Callable) -> Array:
	var out: Array = []
	for pid in parts:
		if filter.call(parts[pid]):
			out.append(parts[pid])
	return out
