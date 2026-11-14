class_name LootEntry
extends Resource

@export var item_id: StringName
@export var min_amount: int = 1
@export var max_amount: int = 1
@export_range(0.0, 1.0) var chance: float = 1.0
