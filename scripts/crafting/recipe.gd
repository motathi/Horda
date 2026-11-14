class_name Recipe
extends Resource
## Receita de fabricação configurável por dados.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
## item_id -> quantidade
@export var inputs: Dictionary = {}
@export var output_item: StringName
@export var output_amount: int = 1
