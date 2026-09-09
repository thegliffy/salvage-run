class_name Combatant
extends RefCounted
## A ship participating in combat -- player or enemy, same class.
##
## Built from a ShipProfile (player) or an EnemyDef (enemy) so both sides obey
## identical rules. If the player can knock out a weapons system, so can the AI.

## Hull-side DoT. Stacks live on the combatant, not a subsystem.
const STATUS_VIRUS := &"virus"

var display_name: String = "Ship"
var is_player: bool = false

var hull: int = 30
var max_hull: int = 30
var shield: int = 0
var max_shield: int = 0
var shield_regen: int = 0
var evasion: int = 0

var energy: int = 0
var max_energy: int = 3
var draw_per_turn: int = 5
## Per-turn subsystem auto-repair. Enemies get this by default; the player
## only gets it from a rare improvement (see system_regen on ShipProfile).
var system_regen: int = 0
## Super Capacitor: excess shield above max stays at the start of your turn.
var keep_overshield: bool = false
## Persistent Strain: virus the player applied to enemies does not decay.
var virus_no_decay: bool = false
## Pure Payload: outgoing damage becomes virus (1:1) instead of HP.
var damage_as_virus: bool = false
## Hot Swap: first card each turn costs 1 less (min 0).
var hot_swap: bool = false
## Spare Clip: draw one extra card on the first turn of combat.
var spare_clip: bool = false
## Probe Tip: first virus application this combat lands +1 stack.
var probe_tip: bool = false
## Signal Noise lives on the player; the enemy copies a evasion penalty.
var signal_noise: bool = false
## Subtracted from effective evasion while this combatant has virus.
var virus_evasion_mod: int = 0
## Fight-long Calibrate bonuses. Per-part stats key on PartInstance.uid;
## evasion and drone tick are ship-wide (see DESIGN.md Calibrate).
var calibrate_by_part: Dictionary = {}  # StringName -> Dictionary[int, int]
var calibrate_evasion: int = 0
var calibrate_drone: int = 0

var systems: Dictionary = {}    # StringName -> ShipSystem
var statuses: Dictionary = {}   # StringName -> int stacks

static func from_profile(prof: ShipProfile) -> Combatant:
	var c := Combatant.new()
	c.is_player = true
	c.display_name = prof.display_name
	c.max_hull = prof.max_hull
	c.hull = prof.max_hull
	c.max_shield = prof.max_shield
	c.shield = prof.max_shield
	c.shield_regen = prof.shield_regen
	c.evasion = prof.evasion
	c.max_energy = prof.power
	c.draw_per_turn = prof.draw_per_turn
	c.system_regen = prof.system_regen
	c.keep_overshield = prof.has_flag(&"keep_overshield")
	c.virus_no_decay = prof.has_flag(&"virus_no_decay")
	c.damage_as_virus = prof.has_flag(&"damage_as_virus")
	c.hot_swap = prof.has_flag(&"hot_swap")
	c.spare_clip = prof.has_flag(&"spare_clip")
	c.probe_tip = prof.has_flag(&"probe_tip")
	c.signal_noise = prof.has_flag(&"signal_noise")
	for sd in prof.systems:
		var s := ShipSystem.from_dict(sd)
		s.auto_repair = c.system_regen
		c.systems[s.id] = s
	return c

static func from_enemy(def: EnemyDef) -> Combatant:
	var c := Combatant.new()
	c.is_player = false
	c.display_name = def.name
	c.max_hull = def.hull
	c.hull = def.hull
	c.max_shield = def.shield
	c.shield = def.shield
	c.shield_regen = def.shield_regen
	c.evasion = def.evasion
	c.system_regen = def.system_regen
	for sd in def.systems:
		var s := ShipSystem.from_dict(sd)
		s.auto_repair = c.system_regen
		c.systems[s.id] = s
	return c

## Shield points above capacity. Still absorb damage; expire at turn start.
func overshield() -> int:
	return maxi(0, shield - max_shield)

func clear_overshield() -> void:
	if shield > max_shield:
		shield = max_shield

func system(sid: StringName) -> ShipSystem:
	return systems.get(sid)

func has_active_system(sid: StringName) -> bool:
	var s: ShipSystem = systems.get(sid)
	return s != null and s.is_active()

func active_systems() -> Array[ShipSystem]:
	var out: Array[ShipSystem] = []
	for sid in systems:
		if systems[sid].is_active():
			out.append(systems[sid])
	return out

## Every system stays targetable, including destroyed ones.
##
## Shooting a wrecked subsystem is shooting the hole where it used to be:
## the damage pipeline finds no integrity to absorb it and spills the full
## amount into the hull. Without this you can disable a ship completely and
## then be unable to finish it, which stalls the fight forever.
func targetable_systems() -> Array[ShipSystem]:
	var out: Array[ShipSystem] = []
	for sid in systems:
		out.append(systems[sid])
	return out

## Systems that still have integrity to chew through -- what an attacker
## actually wants to prioritise.
func intact_systems() -> Array[ShipSystem]:
	var out: Array[ShipSystem] = []
	for sid in systems:
		if systems[sid].integrity > 0:
			out.append(systems[sid])
	return out

func is_dead() -> bool:
	return hull <= 0

## Evasion is reduced when engines are damaged -- partial efficiency matters.
func effective_evasion() -> int:
	var e := evasion
	var engines: ShipSystem = systems.get(&"engines")
	if engines != null:
		e = int(round(float(e) * (0.4 + 0.6 * engines.efficiency())))
	elif not systems.is_empty():
		pass
	if virus() > 0 and virus_evasion_mod != 0:
		e -= virus_evasion_mod
	e += calibrate_evasion
	return maxi(0, e)

func effective_shield_regen() -> int:
	var r := shield_regen
	var sh: ShipSystem = systems.get(&"shields")
	if sh != null:
		r = int(round(float(r) * sh.efficiency()))
	return maxi(0, r)

func add_status(id: StringName, stacks: int) -> void:
	statuses[id] = int(statuses.get(id, 0)) + stacks
	if statuses[id] <= 0:
		statuses.erase(id)

func status(id: StringName) -> int:
	return int(statuses.get(id, 0))

func virus() -> int:
	return status(STATUS_VIRUS)

func add_virus(stacks: int) -> int:
	add_status(STATUS_VIRUS, stacks)
	return virus()

## Record a fight-long Calibrate bonus. `part_uid` is ignored for ship-wide
## stats (evasion, drone tick).
func add_calibrate(stat: StringName, amount: int, part_uid: int = 0) -> void:
	if amount == 0 or stat == &"":
		return
	match stat:
		&"evasion":
			calibrate_evasion += amount
		&"drone":
			calibrate_drone += amount
		_:
			if not calibrate_by_part.has(stat):
				calibrate_by_part[stat] = {}
			var m: Dictionary = calibrate_by_part[stat]
			m[part_uid] = int(m.get(part_uid, 0)) + amount

func calibrate_bonus(stat: StringName, part_uid: int = 0) -> int:
	match stat:
		&"evasion":
			return calibrate_evasion
		&"drone":
			return calibrate_drone
		_:
			var m: Dictionary = calibrate_by_part.get(stat, {})
			return int(m.get(part_uid, 0))

## Infected combatant's turn start: deal 1 hull per counter, then lose 1
## unless `no_decay` (Persistent Strain: player's virus on enemies holds).
## Direct hull — skips evasion and shields. Empty dict if there is nothing to tick.
func tick_virus(no_decay: bool = false) -> Dictionary:
	var stacks := virus()
	if stacks <= 0:
		return {}
	hull = maxi(0, hull - stacks)
	if not no_decay:
		add_status(STATUS_VIRUS, -1)
	return {"damage": stacks, "hull_left": hull, "virus": virus(),
		"persisted": no_decay}

func tick_systems() -> void:
	for sid in systems:
		var s: ShipSystem = systems[sid]
		s.tick_suppression()
		s.tick_auto_repair()

func snapshot() -> Dictionary:
	var sys := {}
	for sid in systems:
		var s: ShipSystem = systems[sid]
		sys[String(sid)] = {"integrity": s.integrity, "max": s.max_integrity,
			"active": s.is_active()}
	return {"name": display_name, "hull": hull, "max_hull": max_hull,
		"shield": shield, "systems": sys, "statuses": statuses.duplicate()}
