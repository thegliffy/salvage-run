class_name Deck
extends RefCounted
## Draw / hand / discard / exhaust piles.
##
## All shuffles go through the seeded "combat" RNG stream so a run replays
## identically from its seed.

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []

var max_hand_size: int = 10

func build(card_ids: Array[StringName], sources: Array = [],
		upgraded: Array = []) -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	for i in card_ids.size():
		var cid: StringName = card_ids[i]
		var def: CardDef = Database.card(cid)
		if def == null:
			push_warning("[Deck] unknown card id '%s' skipped" % cid)
			continue
		var part_uid := int(sources[i]) if i < sources.size() else 0
		var is_up := bool(upgraded[i]) if i < upgraded.size() else false
		draw_pile.append(CardInstance.create(def, is_up, part_uid))
	Rng.shuffle(&"combat", draw_pile)

func draw(count: int) -> Array[CardInstance]:
	var drawn: Array[CardInstance] = []
	for i in count:
		if hand.size() >= max_hand_size:
			break
		if draw_pile.is_empty():
			_reshuffle()
		if draw_pile.is_empty():
			break  # genuinely out of cards
		var c: CardInstance = draw_pile.pop_back()
		hand.append(c)
		drawn.append(c)
	if not drawn.is_empty():
		EventBus.cards_drawn.emit(drawn)
	return drawn

func _reshuffle() -> void:
	if discard_pile.is_empty():
		return
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	Rng.shuffle(&"combat", draw_pile)
	EventBus.deck_reshuffled.emit()

func discard(card: CardInstance) -> void:
	hand.erase(card)
	card.cost_override = -1
	discard_pile.append(card)

func exhaust(card: CardInstance) -> void:
	hand.erase(card)
	card.cost_override = -1
	exhaust_pile.append(card)

func discard_hand() -> void:
	for c in hand.duplicate():
		if c.has_keyword(&"retain"):
			continue
		discard(c)

func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size() + exhaust_pile.size()
