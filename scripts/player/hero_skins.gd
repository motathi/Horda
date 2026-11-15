class_name HeroSkins
## Aparências jogáveis do herói (escolhidas no menu "Novo jogo"). Só visual: os atributos
## vêm dos pontos de atributo. "hunter" é o modelo original; os demais são do pacote CC0
## KayKit Adventurers (montados por tools/bake_kaykit.gd).

const DEFAULT := "hunter"
const LIST: Array[Dictionary] = [
	{"id": "hunter", "name": "Caçador", "model": "hero", "height": 2.2},
	{"id": "knight", "name": "Cavaleiro", "model": "hero_knight", "height": 2.0},
	{"id": "barbarian", "name": "Bárbaro", "model": "hero_barbarian", "height": 2.0},
	{"id": "mage", "name": "Maga", "model": "hero_mage", "height": 2.0},
	{"id": "ranger", "name": "Patrulheiro", "model": "hero_ranger", "height": 2.0},
	{"id": "rogue", "name": "Ladina", "model": "hero_rogue", "height": 2.0},
	{"id": "rogue_hooded", "name": "Encapuzado", "model": "hero_rogue_hooded", "height": 2.0},
]

static func get_skin(id: String) -> Dictionary:
	for s in LIST:
		if s["id"] == id:
			return s
	return LIST[0]

static func portrait(id: String) -> Texture2D:
	var p := "res://assets/characters/portrait_hero.jpg" if id == DEFAULT else "res://assets/characters/portrait_%s.png" % id
	return load(p) as Texture2D if ResourceLoader.exists(p) else load("res://assets/characters/portrait_hero.jpg") as Texture2D
