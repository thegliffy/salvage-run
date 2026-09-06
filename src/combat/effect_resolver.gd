class_name EffectResolver
extends RefCounted
## Executes effect ops against combat state and emits an ordered event stream.
##
## Command pattern on purpose: game logic mutates state synchronously and
## records what happened; the UI replays that record as animation. Nothing in
## here awaits, so a full combat can resolve in microseconds for balance sims.

## Held weakly: CombatController owns the resolver, so a strong reference back
## would form a RefCounted cycle and leak the whole combat at exit.
var _combat_ref: WeakRef

var combat: CombatController:
	get:
		return _combat_ref.get_ref() if _combat_ref != null else null

func _init(controller: CombatController) -> void:
	_combat_ref = weakref(controller)

## ctx keys: source (Combatant), opponent (Combatant), target_system (StringName)
func run(effects: Array, ctx: Dictionary) -> void:
	for op in effects:
		if typeof(op) != TYPE_DICTIONARY:
			push_warning("[EffectResolver] malformed effect op: %s" % [op])
			continue
		_execute(op, ctx)

func _execute(op: Dictionary, ctx: Dictionary) -> void:
	var kind: String = op.get("op", "")
	var source: Combatant = ctx.get("source")
	var opponent: Combatant = ctx.get("opponent")
	var amount := scaled_amount(op, ctx)

	match kind:
		"damage_system":
			var sid: StringName = _resolve_target_system(op, ctx)
			# Hull is a legal target for system-targeted cards: shoot the ship
			# itself without chewing through a subsystem first.
			if sid == &"hull":
				_deal_damage(source, opponent, amount, &"", op)
			else:
				_deal_damage(source, opponent, amount, sid, op)
		"damage_hull":
			_deal_damage(source, opponent, amount, &"", op)
		"damage_self_hull":
			_deal_damage(source, source, amount, &"", {"unavoidable": true})
		"suppress_system":
			var sid2: StringName = _resolve_target_system(op, ctx)
			var s: ShipSystem = opponent.system(sid2)
			if s == null:
				# Nothing left to suppress. Say so: an op that quietly does
				# nothing reads to the player as a bug in their own card.
				_emit({"type": "no_target", "op": kind,
					"target": opponent.display_name})
			else:
				s.suppress(int(op.get("turns", 1)))
				_emit({"type": "suppress", "target": opponent.display_name,
					"system": String(sid2), "turns": int(op.get("turns", 1))})
		"shield":
			var gained := mini(amount, maxi(0, source.max_shield - source.shield))
			# Allow overshield when the op says so; some tech cards want it.
			if bool(op.get("overshield", false)):
				gained = amount
			source.shield += gained
			_emit({"type": "shield", "target": source.display_name, "amount": gained})
		"repair_system":
			var sid3: StringName = _resolve_target_system(op, ctx, true)
			var rs: ShipSystem = source.system(sid3)
			if rs == null:
				_emit({"type": "no_target", "op": kind,
					"target": source.display_name})
			else:
				var healed := rs.repair(amount)
				EventBus.system_repaired.emit(source, sid3)
				_emit({"type": "repair", "target": source.display_name,
					"system": String(sid3), "amount": healed})
		"repair_hull":
			var healed_hull := mini(amount, source.max_hull - source.hull)
			source.hull += healed_hull
			_emit({"type": "repair_hull", "target": source.display_name,
				"amount": healed_hull})
		"draw":
			if source.is_player:
				combat.deck.draw(amount)
				_emit({"type": "draw", "amount": amount})
		"energy":
			source.energy += amount
			EventBus.energy_changed.emit(source.energy, source.max_energy)
			_emit({"type": "energy", "amount": amount})
		"status":
			var who: Combatant = opponent if op.get("to", "enemy") == "enemy" else source
			who.add_status(StringName(op.get("status", "")), amount)
			_emit({"type": "status", "target": who.display_name,
				"status": op.get("status", ""), "stacks": amount})
		"credits":
			combat.pending_credits += amount
			_emit({"type": "credits", "amount": amount})
		_:
			push_warning("[EffectResolver] unknown op '%s'" % kind)

## Supports "amount_per_active_system" style scaling without bespoke ops.
## Public because anything deciding whether a card is worth playing -- AI,
## the balance sim, a damage-preview tooltip -- needs the real number.
func scaled_amount(op: Dictionary, ctx: Dictionary) -> int:
	var base := int(op.get("amount", 0))
	var scale: String = op.get("scale_by", "")
	if scale == "":
		return base
	var source: Combatant = ctx.get("source")
	var opponent: Combatant = ctx.get("opponent")
	match scale:
		"own_active_systems":
			return base * source.active_systems().size()
		"enemy_disabled_systems":
			var n := 0
			for s in opponent.targetable_systems():
				if not s.is_active():
					n += 1
			# also count fully destroyed ones
			for sid in opponent.systems:
				if opponent.systems[sid].integrity <= 0:
					n += 1
			return base * n
		"missing_hull":
			return base * int(floor(float(source.max_hull - source.hull) / 10.0))
	return base

func _resolve_target_system(op: Dictionary, ctx: Dictionary, own: bool = false) -> StringName:
	# Explicit system on the op wins; otherwise use the player's chosen target.
	if op.has("system"):
		return StringName(op["system"])
	var chosen: StringName = ctx.get("target_system", &"")
	if chosen != &"":
		return chosen
	# Fall back to a random live system so AI ops never no-op silently.
	# Never invent a hull target here — hull is an explicit player choice.
	var pool: Combatant = ctx.get("source") if own else ctx.get("opponent")
	var live := pool.targetable_systems()
	if live.is_empty():
		return &""
	# Its own stream: this fires for player-initiated ops too, so drawing from
	# enemy_ai here would let a player's card choice shift enemy intents.
	return Rng.pick(&"target_fallback", live).id

## The single damage pipeline. Evasion -> shields -> subsystem -> hull spill.
func _deal_damage(source: Combatant, target: Combatant, amount: int,
		system_id: StringName, op: Dictionary) -> void:
	if amount <= 0 or target == null:
		return
	var pierce := bool(op.get("pierce", false))
	var unavoidable := bool(op.get("unavoidable", false))

	# 1. Evasion
	if not unavoidable and not bool(op.get("homing", false)):
		var ev := target.effective_evasion()
		# Dedicated stream: sharing "combat" with deck shuffles meant a single
		# dodge reordered every subsequent draw for the rest of the fight.
		if ev > 0 and Rng.stream(&"evasion").randi_range(1, 100) <= ev:
			_emit({"type": "miss", "target": target.display_name})
			return

	var remaining := amount

	# 2. Shields (pierce bypasses them entirely)
	if not pierce and target.shield > 0:
		var absorbed := mini(target.shield, remaining)
		target.shield -= absorbed
		remaining -= absorbed
		_emit({"type": "shield_absorb", "target": target.display_name,
			"amount": absorbed})
		if remaining <= 0:
			return

	# 3. Subsystem, with overflow continuing into the hull
	if system_id != &"":
		var s: ShipSystem = target.system(system_id)
		if s != null and s.integrity > 0:
			var dealt := s.take_damage(remaining)
			remaining -= dealt
			EventBus.system_damaged.emit(target, system_id, dealt)
			_emit({"type": "system_damage", "target": target.display_name,
				"system": String(system_id), "amount": dealt})
			if s.integrity <= 0:
				EventBus.system_disabled.emit(target, system_id)
				_emit({"type": "system_disabled", "target": target.display_name,
					"system": String(system_id)})
				# Wreck the underlying part so damage persists past this fight.
				combat.mark_parts_wrecked(target, s)

	# 4. Hull
	if remaining > 0:
		target.hull = maxi(0, target.hull - remaining)
		EventBus.hull_damaged.emit(target, remaining)
		_emit({"type": "hull_damage", "target": target.display_name,
			"amount": remaining, "hull_left": target.hull})

func _emit(event: Dictionary) -> void:
	combat.log_event(event)
	EventBus.effect_resolved.emit(event)
