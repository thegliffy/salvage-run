class_name EnemyBrain
extends RefCounted
## Chooses and telegraphs enemy intents.
##
## Intents name the subsystem they fire from. An offline system cannot fire
## (damaged weapons hit softer via efficiency). That is a soft control option —
## the player can also just shoot the hull. There is no full "fizzle cancel"
## that makes subsystem hunting mandatory.

var def: EnemyDef
var combatant: Combatant
var current_intent: Dictionary = {}
var _history: Array[StringName] = []

func _init(enemy_def: EnemyDef, c: Combatant) -> void:
	def = enemy_def
	combatant = c

## Pick the next intent, weighted, avoiding immediate repeats where possible.
func choose_intent() -> Dictionary:
	var weights: Dictionary = {}
	for i in range(def.intents.size()):
		var intent: Dictionary = def.intents[i]
		var w := float(intent.get("weight", 1.0))
		var req := StringName(intent.get("requires_system", ""))

		# Softly deprioritise intents whose system is already down.
		if req != &"" and not combatant.has_active_system(req):
			w *= 0.15
		# Soften repeats so fights do not become one move on loop.
		if not _history.is_empty() and _history.back() == StringName(intent.get("id", "")):
			w *= 0.4
		if w > 0.0:
			weights[i] = w

	if weights.is_empty():
		current_intent = {}
		return current_intent

	var idx = Rng.weighted(&"enemy_ai", weights)
	current_intent = def.intents[int(idx)]
	_history.append(StringName(current_intent.get("id", "")))
	return current_intent

## True when the intent's source system is offline — the shot cannot fire.
## Kept for UI/telegraph; combat no longer treats this as a celebrated cancel.
func intent_offline() -> bool:
	if current_intent.is_empty():
		return true
	var req := StringName(current_intent.get("requires_system", ""))
	if req == &"":
		return false
	return not combatant.has_active_system(req)

## Deprecated alias — older call sites / sim. Prefer intent_offline().
func intent_fizzles() -> bool:
	return intent_offline()

## Player-facing telegraph text, degraded if the system is damaged.
func telegraph() -> String:
	if current_intent.is_empty():
		return "Idle"
	var base: String = current_intent.get("telegraph", current_intent.get("id", "?"))
	if intent_offline():
		return "%s (offline)" % base
	var req := StringName(current_intent.get("requires_system", ""))
	var s: ShipSystem = combatant.system(req)
	if s != null and s.efficiency() < 1.0:
		return "%s (damaged)" % base
	return base

## Structured telegraph for the combat banner. `telegraph()` stays the compact
## log/sim string; the UI wants the subsystem, the number, and live/damaged/
## offline as separate fields so they can be sized independently.
func telegraph_info() -> Dictionary:
	var req := StringName(current_intent.get("requires_system", ""))
	var sys: ShipSystem = combatant.system(req) if combatant != null else null
	var sys_name := ""
	if sys != null:
		sys_name = sys.display_name
	elif req != &"":
		sys_name = String(req).capitalize()

	var raw: String = current_intent.get("telegraph", current_intent.get("id", "Idle"))
	var title := raw
	var colon := raw.find(":")
	if colon >= 0:
		title = raw.substr(0, colon).strip_edges()

	var printed := 0
	var op := ""
	for e in current_intent.get("effects", []):
		if e is Dictionary and (e as Dictionary).has("amount"):
			printed = int(e["amount"])
			op = String(e.get("op", ""))
			break

	var scaled := printed
	for e2 in scaled_effects():
		if e2 is Dictionary and (e2 as Dictionary).has("amount"):
			scaled = int(e2["amount"])
			break

	var action := "EFFECT"
	match op:
		"damage_hull":
			action = "HULL"
		"damage_system":
			action = "DAMAGE"
		"shield":
			action = "SHIELD"
		"repair", "repair_hull":
			action = "REPAIR"
		"suppress":
			action = "SUPPRESS"

	var offline := intent_offline()
	var status := "live"
	if current_intent.is_empty():
		status = "idle"
	elif offline:
		status = "offline"
	elif sys != null and sys.efficiency() < 1.0:
		status = "damaged"

	return {
		"title": title,
		"action": action,
		"printed": printed,
		"scaled": scaled,
		"system": req,
		"system_name": sys_name,
		"status": status,
		"offline": offline,
		"text": telegraph(),
	}

## Damaged weapons hit softer. Offline systems produce no effects.
func scaled_effects() -> Array:
	if intent_offline():
		return []
	var req := StringName(current_intent.get("requires_system", ""))
	var eff := 1.0
	var s: ShipSystem = combatant.system(req)
	if s != null:
		eff = 0.5 + 0.5 * s.efficiency()
	var out: Array = []
	for op in current_intent.get("effects", []):
		var copy: Dictionary = (op as Dictionary).duplicate(true)
		if copy.has("amount") and eff < 1.0:
			copy["amount"] = maxi(1, int(round(float(copy["amount"]) * eff)))
		out.append(copy)
	return out
