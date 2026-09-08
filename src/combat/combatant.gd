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

## Infected combatant's turn start: deal 1 hull per counter, then lose 1.
## Direct hull — skips evasion and shields. Empty dict if there is nothing to tick.
func tick_virus() -> Dictionary:
	var stacks := virus()
	if stacks <= 0:
		return {}
	hull = maxi(0, hull - stacks)
	add_status(STATUS_VIRUS, -1)
	return {"damage": stacks, "hull_left": hull, "virus": virus()}

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
