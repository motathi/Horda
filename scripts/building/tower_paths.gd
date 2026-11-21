class_name TowerPaths
extends RefCounted
## Árvore de evolução das torres (estilo Kingdom Rush / Bloons TD): níveis 1-3 em linha; no nível 3 a torre
## escolhe uma de duas especializações, cada uma com dois níveis próprios (4 e 5), com mecânica e visual
## novos (peças "Lv4a", "Lv5a", "Lv4b", "Lv5b" e arma "Turret_a"/"Turret_b" no GLB do Blender).
##
## Modificadores (multiplicam ou somam sobre o nível 3; o nível 5 acumula com o 4):
##   dmg, range, rate, splash  multiplicadores
##   target="strongest"        mira o inimigo com mais vida
##   crit / crit_mult          chance e multiplicador de crítico
##   execute                   chance de matar na hora (não chefes; chefes levam 3x)
##   multi                     flechas em alvos diferentes por disparo
##   burn                      fração do dano por segundo durante 3 s (fogo)
##   width / knockback         largura extra do virote e empurrão (m)
##   harpoon / pull            arpão: prende o alvo (s) e puxa até `pull` inimigos próximos para ele
##   fire_pool                 morteiro deixa chão em chamas (s)
##   cluster                   bala se divide em N bombinhas
##   chain_add / jump          saltos extras do raio e alcance de cada salto
##   storm                     a cada N disparos, raios caem do céu em 5 inimigos
##   pulse / pulse_stun        pulso em área (raio) em vez do raio em cadeia; atordoa (s)
##   slow                      deixa lentos (s)

const TIER4_WAVE := 4
const TIER5_WAVE := 8

const PATHS := {
	&"archer_tower": {
		"a": {"name": "Ninho de Atiradores", "short": "Longo alcance, mira o mais forte, críticos enormes",
			"tiers": [
				{"name": "Ninho de Atiradores", "desc": "Mirante alto com besta de precisão: +60% alcance, dano x3, mira o inimigo mais forte, 30% de crítico x2,5.",
					"mods": {"dmg": 3.0, "range": 1.6, "rate": 0.45, "target": "strongest", "crit": 0.3, "crit_mult": 2.5}},
				{"name": "Olho da Morte", "desc": "Luneta de latão: 12% de chance de abate instantâneo (chefes levam dano triplo).",
					"mods": {"dmg": 1.25, "range": 1.1, "execute": 0.12}}]},
		"b": {"name": "Saraivada", "short": "Várias flechas por disparo em alvos diferentes",
			"tiers": [
				{"name": "Saraivada", "desc": "Mais arqueiros no parapeito: 3 flechas por disparo, cada uma num alvo diferente.",
					"mods": {"dmg": 0.85, "rate": 1.15, "multi": 3}},
				{"name": "Flechas Flamejantes", "desc": "Braseiros acendem as pontas: 5 flechas que incendeiam (35% do dano por segundo, 3 s).",
					"mods": {"dmg": 1.15, "multi": 5, "burn": 0.35}}]},
	},
	&"ballista": {
		"a": {"name": "Perfuradora Pesada", "short": "Virote gigante: dano alto em linha e empurrão",
			"tiers": [
				{"name": "Perfuradora Pesada", "desc": "Arcos de aço e trilho longo: dano x2,2, linha mais larga e +25% de alcance.",
					"mods": {"dmg": 2.2, "range": 1.25, "rate": 0.8, "width": 0.5}},
				{"name": "Aríete de Ferro", "desc": "Ponta de aríete: empurra todos na linha 3 m para trás.",
					"mods": {"dmg": 1.3, "knockback": 3.0}}]},
		"b": {"name": "Arpão de Correntes", "short": "Prende o alvo e puxa os zumbis próximos",
			"tiers": [
				{"name": "Arpão de Correntes", "desc": "Guincho e corrente: o arpão prende o alvo por 1,2 s e o deixa lento.",
					"mods": {"dmg": 1.4, "harpoon": 1.2, "slow": 2.0}},
				{"name": "Rede de Ganchos", "desc": "Arpão duplo: prende e puxa até 4 zumbis próximos para o alvo.",
					"mods": {"dmg": 1.2, "harpoon": 1.6, "pull": 4}}]},
	},
	&"cannon": {
		"a": {"name": "Morteiro", "short": "Artilharia de longe com explosões enormes",
			"tiers": [
				{"name": "Morteiro", "desc": "Cano curto apontado para o céu: +60% alcance, explosão +50%, dano x1,6.",
					"mods": {"dmg": 1.6, "range": 1.6, "rate": 0.7, "splash": 1.5}},
				{"name": "Bombarda Incendiária", "desc": "Barris de óleo: a explosão deixa o chão em chamas por 4 s.",
					"mods": {"dmg": 1.2, "splash": 1.15, "fire_pool": 4.0}}]},
		"b": {"name": "Canhão Duplo", "short": "Disparos rápidos; depois, bombas de fragmentação",
			"tiers": [
				{"name": "Canhão Duplo", "desc": "Dois canos: atira 2,2x mais rápido com explosão menor.",
					"mods": {"dmg": 0.7, "rate": 2.2, "splash": 0.85}},
				{"name": "Metralha", "desc": "Quatro canos giratórios: cada bala se divide em 3 bombinhas.",
					"mods": {"rate": 1.2, "cluster": 3}}]},
	},
	&"tesla": {
		"a": {"name": "Bobina de Tempestade", "short": "Raio salta em muitos alvos; chama tempestades",
			"tiers": [
				{"name": "Bobina de Tempestade", "desc": "Anéis de cobre extras: +3 saltos, saltos mais longos, dano x1,4.",
					"mods": {"dmg": 1.4, "chain_add": 3, "jump": 8.0}},
				{"name": "Senhor dos Raios", "desc": "Cristal flutuante: a cada 4 disparos, raios caem do céu em 5 inimigos.",
					"mods": {"chain_add": 2, "storm": 4}}]},
		"b": {"name": "Pulso Eletromagnético", "short": "Choque em área em volta da torre, deixa lento",
			"tiers": [
				{"name": "Pulso Eletromagnético", "desc": "Antena de disco: pulso que fere todos num raio de 6 m e os deixa lentos.",
					"mods": {"dmg": 0.9, "pulse": 6.0, "slow": 1.5}},
				{"name": "Gerador de Campo", "desc": "Gaiola de energia: pulso de 8,5 m que também atordoa por 0,6 s.",
					"mods": {"dmg": 1.3, "pulse": 8.5, "pulse_stun": 0.6}}]},
	},
}

static func has_paths(id: StringName) -> bool:
	return PATHS.has(id)

static func branch(id: StringName, br: String) -> Dictionary:
	return PATHS.get(id, {}).get(br, {})

## Dados do nível (4 ou 5) de uma especialização.
static func tier(id: StringName, br: String, lvl: int) -> Dictionary:
	var b := branch(id, br)
	if b.is_empty() or lvl < 4:
		return {}
	var tiers: Array = b["tiers"]
	return tiers[mini(lvl - 4, tiers.size() - 1)]

## Modificadores acumulados até o nível (multiplicadores multiplicam; o resto substitui/soma).
static func mods(id: StringName, br: String, lvl: int) -> Dictionary:
	var out := {}
	if br == "" or lvl < 4:
		return out
	var tiers: Array = branch(id, br).get("tiers", [])
	for i in mini(lvl - 3, tiers.size()):
		var m: Dictionary = tiers[i]["mods"]
		for k: String in m:
			if k in ["dmg", "range", "rate", "splash"]:
				out[k] = float(out.get(k, 1.0)) * float(m[k])
			elif k in ["chain_add"]:
				out[k] = int(out.get(k, 0)) + int(m[k])
			else:
				out[k] = m[k]
	return out

## Custo da especialização: nível 4 = 1,8x e nível 5 = 2,8x o custo da melhoria para o nível 3, mais sucata.
static func cost(d: BuildingDef, lvl: int) -> Dictionary:
	var base := d.upgrade_cost(3)
	var k := 1.8 if lvl == 4 else 2.8
	var c := {}
	for item: StringName in base:
		c[item] = int(ceil(int(base[item]) * k))
	c[&"scrap"] = int(c.get(&"scrap", 0)) + (10 if lvl == 4 else 20)
	return c

static func unlock_wave(lvl: int) -> int:
	return TIER4_WAVE if lvl == 4 else TIER5_WAVE
