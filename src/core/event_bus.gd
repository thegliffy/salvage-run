extends Node
## Global signal hub.
##
## Gameplay code emits here; UI listens. Keeping the two decoupled means the
## headless simulator (tests/sim.gd) can run a full combat with no scene tree,
## which is what makes bulk balance passes possible.

# --- Combat ---
signal combat_started(state)
signal turn_began(who: StringName)
signal turn_ended(who: StringName)
signal card_played(card, targets: Array)
signal cards_drawn(cards: Array)
signal deck_reshuffled()
signal energy_changed(current: int, maximum: int)

# --- Resolution ---
## Emitted for every atomic change during effect resolution, in order.
## UI animates from this stream so visuals never drive game logic.
signal effect_resolved(event: Dictionary)
signal system_damaged(combatant, system_id: StringName, amount: int)
signal system_disabled(combatant, system_id: StringName)
signal system_repaired(combatant, system_id: StringName)
signal hull_damaged(combatant, amount: int)
signal intent_fizzled(combatant, intent: Dictionary)
signal combat_ended(victory: bool, rewards: Dictionary)

# --- Run ---
signal run_started(seed_value: int)
signal node_entered(node: Dictionary)
signal credits_changed(amount: int)
signal part_installed(part_id: StringName, cell: Vector2i)
signal part_removed(part_id: StringName, cell: Vector2i)
signal part_stripped(part_id: StringName, grant_index: int)
signal part_jettisoned(part_id: StringName)
signal improvement_installed(improvement_id: StringName)
signal run_ended(outcome: StringName, summary: Dictionary)

# --- Meta ---
signal ship_sold(valuation: Dictionary)
signal salvage_changed(amount: int)
signal part_unlocked(part_id: StringName)
