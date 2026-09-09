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
## Compiled improvement hooks from the ship profile. Data-driven: JSON
## `triggers` land here via ShipLoadout.compile(), combat never reads defs.
var improvement_triggers: Array = []
## True after the hand has been non-empty this player turn. Paradox Engine
## fires once when the hand hits 0, not while it stays empty, and not when
## end-of-turn discard empties it.
var _hand_empty_armed: bool = false
## Probe Tip: first successful virus application this combat is +1.
var _virus_boosted: bool = false
## Signal Noise: enemies with virus lose this much evasion.
const SIGNAL_NOISE_EVASION := 5

# Link back to the run so subsystem destruction can wear down real parts.
var loadout: ShipLoadout = null

func _init() -> void:
	resolver = EffectResolver.new(self)

func setup(profile: ShipProfile, enemy_def: EnemyDef, ship: ShipLoadout = null) -> void:
	player = Combatant.from_profile(profile)
	enemy = Combatant.from_enemy(enemy_def)
	loadout = ship
	deck = Deck.new()
	deck.build(profile.deck, profile.deck_sources)
	brain = EnemyBrain.new(enemy_def, enemy)
	phase = Phase.SETUP
	turn = 0
	pending_credits = int(enemy_def.reward.get("credits", 0))
	drone_slots = profile.drone_slots
	drones.clear()
	events.clear()
	cards_played_this_turn = 0
	improvement_triggers.clear()
	for t in profile.triggers:
		improvement_triggers.append((t as Dictionary).duplicate())
	_hand_empty_armed = false
	_virus_boosted = false
	if profile.has_flag(&"signal_noise"):
		enemy.virus_evasion_mod = SIGNAL_NOISE_EVASION
	EventBus.combat_started.emit(self)
	brain.choose_intent()
	begin_player_turn()

# --- Turn flow ---------------------------------------------------------------

func begin_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	cards_played_this_turn = 0
	player.energy = player.max_energy
	# Virus ticks on the infected combatant's turn start (poison analog).
	# Player virus lives here; enemy virus ticks in _run_enemy_turn. Do not
	# also tick the opponent — that would double-fire.
	_tick_virus(player)
	if phase == Phase.DONE:
		return
	player.tick_systems()
	# Overshield expires at the start of your turn, then regen fills toward cap.
	# Super Capacitor skips the drop for the player only. Regen still fills
	# toward max, but must not clamp a kept overshield back down.
	if not player.keep_overshield:
		player.clear_overshield()
	if player.shield < player.max_shield:
		player.shield = mini(player.max_shield, player.shield + player.effective_shield_regen())
	# Occupied drones tick after shield regen, before the draw.
	_tick_drones()
	deck.draw(player.draw_per_turn)
	# Spare Clip: one extra card on the opening turn of each fight.
	if turn == 1 and player.spare_clip:
		deck.draw(1)
	EventBus.energy_changed.emit(player.energy, player.max_energy)
	EventBus.turn_began.emit(&"player")
	_note_hand_empty()

## Returns "" on success, or a reason the card could not be played.
func play_card(card: CardInstance, target_system: StringName = &"") -> String:
	if phase != Phase.PLAYER:
		return "not your turn"
	if not deck.hand.has(card):
		return "card is not in hand"
	var spent := card_play_cost(card)
	if spent > player.energy:
		return "not enough energy"
	var drone_err := _drone_play_error(card)
	if drone_err != "":
		return drone_err
	if card.def.needs_target() and target_system == &"":
		return "card requires a target system"
	if target_system == &"hull" and not card.def.can_target_hull():
		return "%s needs a subsystem, not the hull" % card.def.name
	if player.damage_as_virus and target_system != &"" and target_system != &"hull" \
			and not card.def.has_suppress(card.upgraded):
		return "%s can only target the hull" % card.def.name
	var exhausts := card.has_keyword(&"exhaust")
	player.energy -= spent
	EventBus.energy_changed.emit(player.energy, player.max_energy)
	EventBus.card_played.emit(card, [target_system])

	resolver.run(card.effects(), {
		"source": player, "opponent": enemy, "target_system": target_system,
		"card": card,
	})

	if exhausts:
		deck.exhaust(card)
	else:
		deck.discard(card)

	cards_played_this_turn += 1
	if phase == Phase.PLAYER:
		if exhausts:
			_fire_improvement_triggers(&"card_exhausted")
		if spent == 0:
			_fire_improvement_triggers(&"zero_cost_played")
		_note_hand_empty()
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
	if player != null:
		amt += player.calibrate_bonus(&"drone")
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
	# End-of-turn discard into an empty hand is not a Paradox empty event.
	_hand_empty_armed = false
	deck.discard_hand()
	EventBus.turn_ended.emit(&"player")
	_run_enemy_turn()

func _run_enemy_turn() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.ENEMY
	EventBus.turn_began.emit(&"enemy")
	# Enemy virus fires here, before they act, so a lethal tick can win the
	# fight without a shot. Not also ticked at player-turn start.
	_tick_virus(enemy)
	if phase == Phase.DONE:
		return
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

## Damage then decay on `who`. No-ops when they have no virus. Emits
## virus_tick then virus_decay so the combat log can show both steps.
func _tick_virus(who: Combatant) -> void:
	if who == null or phase == Phase.DONE:
		return
	# Persistent Strain is on the player ship: virus they put on the enemy
	# still ticks for hull, but does not decay. Player-side virus still decays.
	var persist := (not who.is_player) and player != null and player.virus_no_decay
	var result := who.tick_virus(persist)
	if result.is_empty():
		return
	var dealt := int(result["damage"])
	EventBus.hull_damaged.emit(who, dealt)
	notify_hull_damaged(who, dealt)
	var tick_ev := {
		"type": "virus_tick",
		"target": who.display_name,
		"amount": dealt,
		"hull_left": int(result["hull_left"]),
		"virus": int(result["virus"]),
	}
	log_event(tick_ev)
	EventBus.effect_resolved.emit(tick_ev)
	var decay_ev := {
		"type": "virus_decay",
		"target": who.display_name,
		"virus": int(result["virus"]),
		"persisted": persist,
	}
	log_event(decay_ev)
	EventBus.effect_resolved.emit(decay_ev)
	_check_end()

## Energy actually spent to play `card` this turn. Hot Swap discounts the
## first play of each player turn by 1 (min 0).
func card_play_cost(card: CardInstance) -> int:
	if card == null:
		return 0
	var n := card.cost()
	if player != null and player.hot_swap and cards_played_this_turn == 0:
		return maxi(0, n - 1)
	return n

## Apply virus stacks, with Probe Tip boosting the first application.
## Returns the stacks actually added.
func grant_virus(target: Combatant, amount: int) -> int:
	if target == null or amount <= 0:
		return 0
	var n := amount
	if player != null and player.probe_tip and target == enemy and not _virus_boosted:
		n += 1
		_virus_boosted = true
	target.add_virus(n)
	return n

func notify_hull_damaged(who: Combatant, amount: int) -> void:
	if who == null or who != player or amount <= 0:
		return
	_fire_improvement_triggers(&"hull_damaged")

func _fire_improvement_triggers(when: StringName) -> void:
	if player == null or phase == Phase.DONE:
		return
	# Exhaust / zero-cost / empty-hand stay player-turn only. Victory payout
	# and Bleed Valve can fire on the enemy turn (or as the fight ends).
	if when != &"combat_won" and when != &"hull_damaged" and phase != Phase.PLAYER:
		return
	for t in improvement_triggers:
		if StringName(t.get("when", "")) != when:
			continue
		var op := String(t.get("op", ""))
		var amount := int(t.get("amount", 1))
		if op == "" or amount <= 0:
			continue
		resolver.run([{"op": op, "amount": amount}], {
			"source": player, "opponent": enemy, "target_system": &"",
		})
		if phase == Phase.DONE:
			return

## Fire `hand_empty` once when the hand hits 0 during the player turn.
## Drawing refills the hand so the same empty event cannot loop; a failed
## draw (empty piles) leaves the trigger disarmed until a card is held again.
func _note_hand_empty() -> void:
	if phase != Phase.PLAYER or deck == null:
		return
	if not deck.hand.is_empty():
		_hand_empty_armed = true
		return
	if not _hand_empty_armed:
		return
	_hand_empty_armed = false
	_fire_improvement_triggers(&"hand_empty")
	if not deck.hand.is_empty():
		_hand_empty_armed = true

func _check_end() -> void:
	if enemy.is_dead():
		_finish(true)
	elif player.is_dead():
		_finish(false)

func _finish(won: bool) -> void:
	if phase == Phase.DONE:
		return
	if won:
		_fire_improvement_triggers(&"combat_won")
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
