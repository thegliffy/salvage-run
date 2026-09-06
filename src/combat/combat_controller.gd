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
	events.clear()
	EventBus.combat_started.emit(self)
	brain.choose_intent()
	begin_player_turn()

# --- Turn flow ---------------------------------------------------------------

func begin_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	player.energy = player.max_energy
	player.tick_systems()
	# Shields regenerate at the top of your turn, scaled by shield system health.
	player.shield = mini(player.max_shield, player.shield + player.effective_shield_regen())
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
	if card.def.needs_target() and target_system == &"":
		return "card requires a target system"

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

	_check_end()
	return ""

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
		"discard": deck.discard_pile.size()}
