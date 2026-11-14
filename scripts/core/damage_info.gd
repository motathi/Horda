class_name DamageInfo
extends RefCounted
## Pacote de dano trafegado entre atacante e alvo.

enum Type { PHYSICAL, FIRE, POISON, TRUE }

var amount: float = 0.0
var source: Node = null
var type: Type = Type.PHYSICAL
var is_crit: bool = false
## Multiplicador aplicado contra estruturas (zumbis brutos derrubam muros mais rápido).
var structure_multiplier: float = 1.0

static func make(amt: float, src: Node, crit: bool = false) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amt
	d.source = src
	d.is_crit = crit
	return d
