class_name HeroSkins
## Aparências do herói (escolhidas no menu "Novo jogo"). Só visual: os atributos vêm dos
## pontos de atributo. Só ficam heróis no estilo do jogo (proporções realistas, pintura escura):
## "hunter" é o modelo original (Tripo) e o Cavaleiro é o modelo enviado pelo jogador, refeito
## leve e com esqueleto pelo Tripo a partir de 4 vistas (tools/render_views.tscn + tripo_pipeline).
## As entradas "hidden" são visuais dos soldados do exército (mesmos modelos, outra cor).

const DEFAULT := "hunter"
const LIST: Array[Dictionary] = [
	{"id": "hunter", "name": "Caçador", "model": "hero", "height": 2.2},
	{"id": "knight", "name": "Cavaleiro", "model": "hero_paladin", "height": 2.25},
	# Soldados (não aparecem na escolha de herói).
	{"id": "ranger", "name": "Arqueiro", "model": "hero", "height": 2.1, "tint": Color(0.7, 1.0, 0.65), "hidden": true},
	{"id": "barbarian", "name": "Bárbaro", "model": "hero_paladin", "height": 2.3, "tint": Color(1.0, 0.5, 0.42), "hidden": true},
	{"id": "mage", "name": "Mago de Batalha", "model": "hero", "height": 2.1, "tint": Color(0.85, 0.7, 1.2), "hidden": true},
]

## Heróis que o jogador pode escolher.
static func playable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in LIST:
		if not s.get("hidden", false):
			out.append(s)
	return out

static func get_skin(id: String) -> Dictionary:
	for s in LIST:
		if s["id"] == id:
			return s
	return LIST[0]

static func portrait(id: String) -> Texture2D:
	var p := "res://assets/characters/portrait_hero.jpg" if id == DEFAULT else "res://assets/characters/portrait_%s.png" % id
	return load(p) as Texture2D if ResourceLoader.exists(p) else load("res://assets/characters/portrait_hero.jpg") as Texture2D
