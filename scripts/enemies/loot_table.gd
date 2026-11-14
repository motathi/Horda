class_name LootTable
extends Resource
## Tabela de saque: cada entrada é rolada independentemente.

@export var entries: Array[LootEntry] = []

## Retorna Dictionary item_id -> quantidade.
func roll(rng: RandomNumberGenerator, multiplier: float = 1.0) -> Dictionary:
	var out := {}
	for e in entries:
		if rng.randf() <= e.chance:
			var n := int(round(rng.randi_range(e.min_amount, e.max_amount) * multiplier))
			if n > 0:
				out[e.item_id] = int(out.get(e.item_id, 0)) + n
	return out
