# Arquitetura — Fase 1

## Princípios

- **Dados separados da lógica**: itens, inimigos, saques, receitas, hordas, ciclo dia/noite e custos
  da base são `Resource`s em `res://data/**.tres`. Balancear = editar dados no inspetor.
- **Comunicação por sinais** (`EventBus`) entre módulos; nada de referências cruzadas entre HUD,
  economia, combate e hordas. Autoloads só expõem estado global, nunca dependem de cenas.
- **Componentes reutilizáveis**: `HealthComponent` (vida/armadura/regeneração/cura ao longo do tempo)
  serve herói, zumbis e construções; `ObjectPool` recicla textos de dano, partículas e itens no chão.
- **Uma cena por entidade** (`scenes/player/hero.tscn`, `scenes/enemies/zombie.tscn`,
  `scenes/buildings/*.tscn`); o visual dos personagens é montado proceduralmente (`CharacterModel`)
  a partir de primitivas + texturas pintadas, com animação procedural (andar, golpe, dano, morte).
- **Preparado para co-op**: o herói é uma entidade comum no grupo `allies`; inimigos escolhem
  alvos por grupo (não por singleton), e todo estado salvo é serializado por sistema — base para
  replicar com `MultiplayerSynchronizer` no futuro.

## Autoloads

| Autoload | Responsabilidade |
|---|---|
| `EventBus` | Sinais globais (dano, abates, coleta, hordas, mensagens/banners) |
| `GameManager` | Estado da partida, dificuldade, troca de cena, fim de jogo, estatísticas |
| `TimeManager` | Rodadas: 2 min de preparação (amanhecer/dia/entardecer) + horda (noite) que termina quando todos morrem; 100 hordas (`TOTAL_WAVES`) |
| `ResourceManager` | Catálogo de itens, mochila do herói (capacidade por peso) e armazém da base |
| `SaveManager` | Salvamento JSON em `user://savegame.json` (cada sistema serializa a si mesmo) |
| `AudioManager` | Pool de players 2D/3D com limitação de repetição |

## Módulos (scripts/)

| Pasta | Conteúdo |
|---|---|
| `core/` | `HealthComponent`, `DamageInfo`, `ObjectPool`, `Layers`, `DayNightConfig` |
| `player/` | `Hero` (movimento WASD/clique, ataque em arco, interação, consumíveis, morte/renascimento), `CameraRig` |
| `enemies/` | `Enemy` (IA em estados: vagar, perseguir, atacar, cerco, voltar), `EnemyDef`, `LootTable` |
| `hordes/` | `HordeConfig` (curva das 100 hordas: quantidade, vida, dano, velocidade, elites a cada 5, chefe a cada 10), `HordeDirector` (levas, direções, fim automático da horda, vitória), `WorldSpawner` (população por região na preparação) |
| `building/` | `Structure` (paliçada, portão só para aliados, núcleo), `BaseZone` (depósito automático) |
| `economy/` `crafting/` | `BaseServices` (reparos, afiar arma, fabricação), `Recipe`, `BaseServicesConfig` |
| `world/` | `World` (orquestra a partida), `WorldBuilder` (mapa determinístico por semente), `PropFactory`, `Harvestable`, `Lootable`, `ResourcePickup`, `DayNightVisuals` |
| `combat/` | `EffectsHub` (efeitos com pool), `FloatingText`, `BurstEffect` |
| `visual/` | `CharacterModel`, `HealthBar3D`, `MaterialLib` (cache de materiais) |
| `ui/` | `HUD`, `TopBar`, `BottomBar`, `SelectionPanel`, `Minimap`, `InventoryPanel`, `BasePanel`, `MainMenu`, `UIStyle` |

## Decisões importantes

- **Zumbis x muros**: a malha de navegação é assada só com a camada `world` (terreno e props);
  muros/portões ficam fora. Assim os zumbis seguem o caminho direto até o Núcleo, esbarram na
  paliçada e passam a atacá-la (`Enemy._check_blockers` / detecção de "preso"). Zumbis resistentes
  têm multiplicador de dano contra estruturas.
- **Portão**: está na camada `gate`, que colide com inimigos mas não com o herói — abre visualmente
  para aliados e continua bloqueando zumbis.
- **Desempenho**: IA "pensa" a 4 Hz com fase aleatória; zumbis diurnos a mais de 75 m do herói
  dormem; separação entre zumbis é um empurrão barato em vez de física/avoidance; sons são
  limitados por tipo; efeitos e itens usam pool; materiais são compartilhados.
- **Malha de navegação** é reassada em segundo plano ao amanhecer quando árvores foram derrubadas.
- **Renderização**: Forward+ (SSAO, glow, sombras). Shaders evitam `instance uniform` para também
  rodar no renderizador Compatibility.

## Arte 3D gerada por IA

Os modelos (herói, 3 zumbis, fortaleza, muralha, portão, torre, pinheiro, rocha, casa em ruínas,
carroça) seguem um pipeline reprodutível:

1. **Conceito** — `tools/gen_image.py tools/model_concepts.json` gera, na BytePlus ARK (Seedream),
   imagens de personagem/objeto isolado em fundo neutro, no estilo Dota 2 / Warcraft III.
2. **Imagem → 3D** — Higgsfield *SAM 3D* (malha texturizada GLB) → `assets/models/raw/` (ignorado
   pelo importador do Godot via `.gdignore`).
3. **Correção** — `tools/fix_glb.py` adiciona normais (os GLBs vêm sem), centraliza e apoia a base em y=0.
4. **Bake** — `tools/bake_models.gd` decima com o meshoptimizer do Godot para um orçamento de
   triângulos por modelo, gera LODs e extrai a textura → `assets/models/<nome>.res` + `textures/`.
   Tudo junto: `tools/build_models.sh`.
5. **Uso** — `ModelLibrary` instancia os modelos já escalados; se um modelo não existir, o jogo usa
   automaticamente o visual procedural antigo (nada quebra).

**Personagens com esqueleto (Tripo API):** `tools/tripo_pipeline.py` envia o conceito do herói e dos
zumbis para a Tripo (imagem → modelo → pré-checagem → rig bípede → 5 animações: idle, walk, run,
slash, hurt) e salva `assets/models/rigged/<nome>.glb` (~105 créditos ≈ US$ 1,05 por personagem).
A chave vai no header `Authorization`; nesta nuvem ela é injetada pelo proxy do ambiente — localmente,
exporte `TRIPO_API_KEY`. `CharacterModel` usa o GLB rigado quando existe (máquina de estados
idle/walk/run/slash; `hurt` vira a queda da morte; animação pausada fora da tela) e cai para a malha
estática animada por código ou para o visual procedural se o arquivo faltar.

## Inimigos especiais

`EnemyDef.Behavior` ganhou `EXPLODER`, `SPITTER` e `LEAPER`, configurados pelos campos `special_*` do
recurso (raio, alcance, tempo, multiplicador e cor). Em `Enemy`: `_start_fuse()`/`_explode()` (explosão
em área contra aliados, estruturas e — se abatido — outros zumbis, com crédito de XP para quem matou),
`AcidProjectile` + `AcidPuddle` (arco balístico, dano a estruturas no impacto e poça que corrói o grupo
`allies`) e `_begin_leap()`/`_process_leap()` (salto parabólico sem colisão com estruturas; no cerco,
`_leap_over_wall()` pula em direção ao núcleo). Entram na horda por `data/config/horde_default.tres`
(estreia nas hordas 4, 7 e 9, anunciada pelo `HordeDirector`) e na Área Contaminada durante o dia.
Modelos riggados gerados pelo `tools/tripo_pipeline.py`.

## Áudio

`AudioManager` (autoload) cria os canais `Music`, `SFX`, `Ambient` e `UI`; `play(id)`/`play_3d(id, pos, vol, pitch,
gap_ms)` sorteiam entre as variações `assets/sounds/<id>_<n>.ogg` (sem repetir a última) e limitam repetições
no mesmo instante. A música é escolhida a cada quadro pelo estado (`GameManager.state`, `horde_started` /
`horde_ended`, `HordeConfig.is_boss_wave`) com crossfade entre dois players; o ambiente mistura três camadas
(dia, noite, área sombria por distância ao cemitério). Todo `BaseButton` criado ganha som de clique/hover via
`SceneTree.node_added`. Os sons vêm de `tools/oga_fetch.py` + `tools/build_audio.py` (manifesto id → arquivos).

## Cenário de terceiros (CC0)

`ThirdParty` (`scripts/world/third_party.gd`) carrega os modelos de `assets/third_party/` (escala por altura,
sombra, `solid()` com colisão em caixa na camada `WORLD`, que entra na malha de navegação).
`DecorScatter` desenha a vegetação sem colisão com um `MultiMeshInstance3D` por modelo e por região
(recorte por câmera; 55% da quantidade em aparelhos fracos). O `WorldBuilder` usa geradores aleatórios
próprios para o cenário (`_srng`, `PropFactory.style_rng`), então a sequência principal do mapa e os IDs
de coletáveis/saqueáveis dos saves não mudam. Os esqueletos KayKit são montados por
`tools/bake_kaykit.gd` em `assets/models/rigged/*.scn` (personagem + armas em `BoneAttachment3D` +
animações renomeadas para idle/walk/run/slash/hurt), carregados por `CharacterModel.rigged_path()`.
Os heróis jogáveis (`HeroSkins`, só visual) usam o mesmo bake; `GameManager.hero_skin` é lembrado em
`user://settings.cfg` e gravado no save. Os sobreviventes (`Survivor`, `tools/bake_npcs.gd`) juntam no mesmo
`Skeleton3D` a cabeça do corpo base (triângulos filtrados pelos ossos da cabeça/pescoço), a roupa e o cabelo
tingido, com animações do Universal Animation Library; papéis WORK/GUARD/TALK/WANDER e fuga para o núcleo
em `horde_started`. As ruínas vêm de `WorldBuilder._build_ruins()` (KayKit Dungeon).

## Roteiro

- **Fase 2 — RPG (em andamento)**: níveis/XP e **habilidades prontas** — `AbilityDef`
  (`scripts/progression/ability_def.gd`, dados em `data/skills/*.tres`: nível de liberação, custo de energia,
  recarga, poder, raio, distância, duração); o `Hero` mantém energia e recargas e expõe
  `cast_ability(i)`/`ability_block_reason(i)`; `Enemy.stun()` (chefes resistem 35%); efeitos
  `EffectsHub.spawn_ring/spawn_explosion`; botões hexagonais em arco no `HudActions` com recarga e cadeado.
  **Atributos prontos**: `AttributeConfig` (`data/config/attributes.tres`) define o bônus por ponto; o `Hero`
  guarda `attributes`/`attr_points` (3 por nível), recalcula vida/energia/regeneração/carga em
  `_recalc_stats()` e chama `refresh_stats` no grupo `buildings` (Engenharia). `CharacterPanel` (P / retrato)
  distribui e redistribui pontos. **Equipamentos prontos**: `EquipmentDef` (item base, `data/equipment`), `GearItem` (raridade, nível,
  bônus sorteados; `stat()`, `to_dict()`), `Gear` (raridades, pesos com sorte, `make_item`, `random_item`,
  `enemy_drop`), `GearPickup` (feixe na cor da raridade). O `Hero` soma `gear(stat)` em dano, velocidade,
  crítico, alcance, armadura, vida, regeneração, energia, poder e recarga; `equip/unequip/salvage`, bolsa de 16.
  Forja em `BaseServices.forge()` (sorte = Engenharia × 4%); abas em `BasePanel` e `CharacterPanel`.
- **Fase 3 — Construção (núcleo pronto)**: `BuildManager` (prévia transparente, grade de 0,5 m, rotação,
  validação por área da base/espaço livre/recursos), `Building` (estende `Structure`: níveis 1–3, torre que
  dispara `Projectile` com pool, armadilha que fere e se desgasta, demolição com reembolso) e dados em
  `data/buildings/*.tres` (`BuildingDef`). Defesas avançadas prontas: `BuildingDef.TowerKind`
  (`ARROW`, `PIERCE`, `SPLASH`, `CHAIN`) com `splash_radius`, `chain_count`, `stun_time` e `unlock_wave`;
  `Building._fire_bolt/_fire_cannon/_fire_chain` e efeitos `EffectsHub.spawn_bolt/spawn_lob/spawn_lightning`;
  modelos estáticos via `tools/tripo_pipeline.py --static` + `tools/build_models.sh`. Falta: portões
  construíveis, fundações e custo de manutenção.
- **Fase 4 — Exército**, **Fase 5 — Conteúdo** (ferro, couro, eletrônicos, pólvora, combustível e cristais
  — ícones já gerados — entram junto com os sistemas que os usam), **Fase 6 — Polimento**.
