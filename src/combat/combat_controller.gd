class_name CombatController
extends RefCounted
## Turn loop and combat state.
##
## Deliberately a RefCounted, not a Node: combat can be constructed and run to
## completion with no scene tree, which is what tests/sim.gd relies on for
## balance passes. UI attaches by listening to EventBus.

enum Phase { SETUP, PLAYER, ENEMY, DONE }

var player: Combatant
var enemy: Combatant
var deck: Deck
var brain: EnemyBrain
var resolver: EffectResolver

var phase: Phase = Phase.SETUP
var turn: int = 0
var victory: bool = false
var pending_credits: int = 0
var events: Array[Dictionary] = []
## Successful player plays this turn, not counting a card currently resolving.
## Static Buildup (and the sim preview) add one so the resolving card counts.
var cards_played_this_turn: int = 0

## Drone bays: empty until a launch card fills a slot. Occupied drones tick
## once at the start of the player's turn, after shield regen / overshield
## drop and before the draw. Overcharge activates occupied drones extra times
## immediately (still this turn). Offline `drones` subsystem silences ticks.
const DRONE_ATTACK := 2
const DRONE_SHIELD := 2
var drone_slots: int = 0
## Occupied bays: [{type: attack|shield, amount: int}, ...] — empty at setup.
var drones: Array = []

# Link back to the run so subsystem destruction can wear down real parts.
var loadout: ShipLoadout = null

func _init() -> void:
	resolver = EffectResolver.new(self)

func setup(profile: ShipProfile, enemy_def: EnemyDef, ship: ShipLoadout = null) -> void:
	player = Combatant.from_profile(profile)
	enemy = Combatant.from_enemy(enemy_def)
	loadout = ship
	deck = Deck.new()
	deck.build(profile.deck)
	brain = EnemyBrain.new(enemy_def, enemy)
	phase = Phase.SETUP
	turn = 0
	pending_credits = int(enemy_def.reward.get("credits", 0))
	drone_slots = profile.drone_slots
	drones.clear()
	events.clear()
	cards_played_this_turn = 0
	EventBus.combat_started.emit(self)
	brain.choose_intent()
	begin_player_turn()

# --- Turn flow ---------------------------------------------------------------

func begin_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	cards_played_this_turn = 0
	player.energy = player.max_energy
	player.tick_systems()
	# Overshield expires at the start of your turn, then regen fills toward cap.
	player.clear_overshield()
	player.shield = mini(player.max_shield, player.shield + player.effective_shield_regen())
	# Occupied drones tick after shield regen, before the draw.
	_tick_drones()
	deck.draw(player.draw_per_turn)
	EventBus.energy_changed.emit(player.energy, player.max_energy)
	EventBus.turn_began.emit(&"player")

## Returns "" on success, or a reason the card could not be played.
func play_card(card: CardInstance, target_system: StringName = &"") -> String:
	if phase != Phase.PLAYER:
		return "not your turn"
	if not deck.hand.has(card):
		return "card is not in hand"
	if card.cost() > player.energy:
		return "not enough energy"
	var drone_err := _drone_play_error(card)
	if drone_err != "":
		return drone_err
	if card.def.needs_target() and target_system == &"":
		return "card requires a target system"
	if target_system == &"hull" and not card.def.can_target_hull():
		return "%s needs a subsystem, not the hull" % card.def.name

	player.energy -= card.cost()
	EventBus.energy_changed.emit(player.energy, player.max_energy)
	EventBus.card_played.emit(card, [target_system])

	resolver.run(card.effects(), {
		"source": player, "opponent": enemy, "target_system": target_system,
	})

	if card.has_keyword(&"exhaust"):
		deck.exhaust(card)
	else:
		deck.discard(card)

	cards_played_this_turn += 1
	_check_end()
	return ""

func empty_drone_slots() -> int:
	return maxi(0, drone_slots - drones.size())

## Fill the next empty bay. Returns a reason if the launch is illegal.
func launch_drone(kind: StringName, amount: int) -> String:
	if drone_slots <= 0:
		return "no drone bays"
	if drones.size() >= drone_slots:
		return "drone bays are full"
	if kind != &"attack" and kind != &"shield":
		kind = &"attack"
	drones.append({"type": kind, "amount": maxi(1, amount)})
	return ""

func _drone_play_error(card: CardInstance) -> String:
	for op in card.effects():
		if typeof(op) != TYPE_DICTIONARY:
			continue
		match String(op.get("op", "")):
			"launch_drone":
				if drone_slots <= 0:
					return "no drone bays"
				if drones.size() >= drone_slots:
					return "drone bays are full"
			"overcharge_drones":
				if drones.is_empty():
					return "no drones launched"
				var ds: ShipSystem = player.system(&"drones")
				if ds != null and not ds.is_active():
					return "drone launcher is offline"
	return ""

## Occupied drones fire `times` each. Default once: start-of-turn tick.
## Offline `drones` subsystem silences the wing (soft control).
func _tick_drones(times: int = 1) -> void:
	if drones.is_empty() or phase == Phase.DONE:
		return
	var ds: ShipSystem = player.system(&"drones")
	if ds != null and not ds.is_active():
		log_event({"type": "offline", "target": "Drones"})
		return
	var reps := maxi(1, times)
	for i in reps:
		for d in drones:
			if phase == Phase.DONE:
				return
			_activate_drone(d)
	var ev := {
		"type": "drones",
		"count": drones.size(),
		"times": reps,
	}
	log_event(ev)
	EventBus.effect_resolved.emit(ev)
	_check_end()

func _activate_drone(d: Dictionary) -> void:
	var kind := StringName(d.get("type", &"attack"))
	var amt := int(d.get("amount", DRONE_ATTACK if kind == &"attack" else DRONE_SHIELD))
	var op: Dictionary
	if kind == &"shield":
		op = {"op": "shield", "amount": amt}
	else:
		op = {"op": "damage_system", "amount": amt, "homing": true}
	resolver.run([op], {
		"source": player, "opponent": enemy, "target_system": &"",
	})

func end_player_turn() -> void:
	if phase != Phase.PLAYER:
		return
	deck.discard_hand()
	EventBus.turn_ended.emit(&"player")
	_run_enemy_turn()

func _run_enemy_turn() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.ENEMY
	EventBus.turn_began.emit(&"enemy")
	enemy.tick_systems()
	enemy.clear_overshield()
	enemy.shield = mini(enemy.max_shield, enemy.shield + enemy.effective_shield_regen())

	var effects := brain.scaled_effects()
	if effects.is_empty() and not brain.current_intent.is_empty():
		log_event({"type": "offline", "target": enemy.display_name,
			"intent": brain.current_intent.get("id", "?")})
	else:
		resolver.run(effects, {
			"source": enemy, "opponent": player, "target_system": &"",
		})

	_check_end()
	if phase == Phase.DONE:
		return
	brain.choose_intent()
	EventBus.turn_ended.emit(&"enemy")
	begin_player_turn()

func _check_end() -> void:
	if enemy.is_dead():
		_finish(true)
	elif player.is_dead():
		_finish(false)

func _finish(won: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	victory = won
	var rewards := {"credits": pending_credits if won else 0}
	EventBus.combat_ended.emit(won, rewards)

# --- Persistence of damage ---------------------------------------------------

## When a player subsystem is destroyed, wear the parts behind it so the loss
## follows you out of the fight. This is what gives repair its value and what
## makes a battered ship sell for less at the end of the run.
func mark_parts_wrecked(target: Combatant, s: ShipSystem) -> void:
	if not target.is_player or loadout == null:
		return
	for inst in loadout.parts:
		if s.part_uids.has(inst.uid):
			inst.wear = inst.def.integrity

## Look up one of this enemy's intents by id. Used by tests and by scripted
## boss phases that need to force a specific move.
func enemy_intent_by_id(intent_id: StringName) -> Dictionary:
	for intent in brain.def.intents:
		if StringName(intent.get("id", "")) == intent_id:
			return intent
	return {}

func log_event(e: Dictionary) -> void:
	events.append(e)

func snapshot() -> Dictionary:
	return {"turn": turn, "phase": phase, "player": player.snapshot(),
		"enemy": enemy.snapshot(), "intent": brain.telegraph(),
		"hand": deck.hand.size(), "draw": deck.draw_pile.size(),
		"discard": deck.discard_pile.size(),
		"drone_slots": drone_slots, "drones": drones.size()}
