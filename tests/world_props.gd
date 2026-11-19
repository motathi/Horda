class_name WorldProps
## Fábrica de objetos de cenário para as capturas de revisão (tests/atmo_probe.gd).

static func make(kind: String, rng: RandomNumberGenerator, i: int) -> Node3D:
	match kind:
		"cart":
			return PropFactory.make_lootable("cart", rng)
		"car":
			var l := PropFactory.make_lootable("car", rng)
			return l
		_:
			var path := "res://assets/models/blender/%s.glb" % kind
			return (load(path) as PackedScene).instantiate() as Node3D
