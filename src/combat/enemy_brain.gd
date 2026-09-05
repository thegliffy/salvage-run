class_name EnemyBrain
extends RefCounted
## Chooses and telegraphs enemy intents.
##
## The core rule: an intent names the subsystem it fires from. If the player
## destroys or suppresses that subsystem before the enemy turn, the intent
## FIZZLES. Telegraphing one turn ahead is what turns "which system do I shoot"
## into a real decision instead of a coin flip.

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

		# Heavily deprioritise intents whose system is already down; the AI
		# is not stupid, it just cannot always avoid them.
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

## True when the intent's source system is down -- the payoff for targeting.
func intent_fizzles() -> bool:
	if current_intent.is_empty():
		return true
	var req := StringName(current_intent.get("requires_system", ""))
	if req == &"":
		return false
	return not combatant.has_active_system(req)

## Player-facing telegraph text, degraded if the system is damaged.
func telegraph() -> String:
	if current_intent.is_empty():
		return "Idle"
	var base: String = current_intent.get("telegraph", current_intent.get("id", "?"))
	if intent_fizzles():
		return "%s (offline)" % base
	var req := StringName(current_intent.get("requires_system", ""))
	var s: ShipSystem = combatant.system(req)
	if s != null and s.efficiency() < 1.0:
		return "%s (damaged)" % base
	return base

## Damaged weapons hit softer -- partial damage matters, not just kills.
func scaled_effects() -> Array:
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
