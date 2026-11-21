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

## Exército

`SoldierDef` (`data/soldiers`), `Soldier` (`scenes/army/soldier.tscn`: IA com alvo por ordem, ataque corpo a
corpo/flecha/magia em área, desvio de obstáculos, modo fantoche no coop) e `Army` (nó do World: quartéis =
`BuildingDef.Category.BARRACKS`, capacidade, fila de treino, ordens DEFEND/FOLLOW/HUNT, postos, formação, save).
Soldados navegam pela `WorldBuilder.ally_nav_region` (camada de navegação 2, recorta paliçada e construções,
rebake em segundo plano quando algo é construído/destruído). `Enemy` alvo em soldados próximos e não "dorme"
perto deles. Coop: `Coop.soldier_spawned/_soldier_snap/_soldier_died/_army_state` e pedidos `recruit`/`army_order`.

## Configurações e tutorial

Autoload `Settings` (`user://settings.cfg`): `quality` (0–2) controla MSAA, atlas de sombras, `scaling_3d_scale`
(resolução 3D), sombra do sol (grupo `quality_sun`), densidade de grama/decoração (na geração do mundo) e luzes;
também `fps_limit` (`Engine.max_fps`), `show_fps`, `damage_numbers` e `tutorial_done`. `SettingsPanel` é usado no
menu principal e na pausa. `Tutorial` (HUD) roda na primeira partida solo, ocupa o lugar dos objetivos, avança por
eventos (`item_picked_up`, `enemy_killed`, `building_placed`, `ability_cast`, `horde_started`) e para o relógio da
preparação até o passo final.

## Coop online

- `Net` (autoload): salas e lobby. No navegador, `WebRTCMultiplayerPeer` com uma `WebRTCPeerConnection` por
  convidado; SDP/ICE trafegam por `PeerJSSignal` (WebSocket no servidor público 0.peerjs.com — o servidor só
  repassa mensagens `CANDIDATE` no formato do PeerJS, então nossos dados vão como JSON em
  `candidate.candidate`). No PC/testes, `ENetMultiplayerPeer`. Lobby por RPC (`_register`, `_lobby`, `_start`).
- `Coop` (autoload): anfitrião autoritativo. Heróis: o dono envia estado a 15 Hz; os outros são
  `Hero.is_puppet` (sem colisão, com nome); dano de zumbi num fantoche é repassado ao dono. Inimigos: o
  anfitrião numera (`net_id`), anuncia e envia instantâneos a 10 Hz; no cliente são `Enemy.puppet` (sem IA),
  golpes e atordoamentos vão ao anfitrião (`_hit_enemy`) e a morte volta com o matador (XP local).
  Saques no chão compartilhados com reivindicação (`claim_pickup`). Coleta/saque de contêineres, construções
  (pedido → anfitrião constrói e replica), vida das estruturas (2 Hz), armazém (debounce), tempo, pesquisas,
  eventos da horda e banners. Ações compartilhadas do cliente usam `Coop.request()`; gastos e depósitos no
  armazém são espelhados por `ResourceManager.spend/store`.
- Teste: `tools/run_coop_test.sh` (dois processos com ENet). Depuração no navegador: `?autocoop=host` e
  `?autocoop=join&sala=CODIGO`.

## Tela inicial

- `main_menu.gd` (cena principal) cria o `TitleBackdrop` (Node3D filho do Control: câmera própria,
  WorldEnvironment, fortaleza/muralha com os modelos do Blender, `Foliage` reaproveitado, zumbis com
  `CharacterModel.build_zombie`, herói `build_hero("knight")`, corvos = `eagle.glb` com material escuro,
  brasas em GPUParticles3D, névoa rasteira num plano com fbm no shader e raio = fita em zigue-zague gerada
  por SurfaceTool) e a interface por cima. `TitleBackdrop.focus(nome)` troca o enquadramento (SHOTS) com
  transição suave; `strike()` dispara um raio.
- `TitleStyle`: StyleBoxTexture 9-slice com a arte de `assets/ui/title/` (gerada por `tools/blender_ui.py`;
  os botões têm 400x80 px para os cantos de ~28 px encaixarem em botões de 50–70 px), shader de brilho
  (uniform `hover`) e tweens de hover/clique. `main_menu._restyle` aplica o estilo aos painéis de
  Configurações e Coop, que continuam sendo os mesmos componentes do jogo.
- Captura para revisão: `xvfb-run ... res://tests/menu_probe.tscn -- <pasta>` (entrada, menu e submenus;
  `MENU_FRAMES=1` salva 64 quadros da entrada para montar um GIF).

## Reviver no coop

- `Hero._try_interact` dá prioridade a um aliado caído por perto (`Coop.remote_heroes` com `health.dead`): o
  resgate corre localmente (barra de `interaction_progress`, `REVIVE_TIME`), e no fim
  `Coop.request_revive(pid)` manda `_revive_me` ao dono daquele herói (RPC com relay do servidor quando os dois
  são clientes), que chama `Hero.revive_here` — o resto (posição, vida, "caído") volta pelo estado de rede normal.
- `_update_down_ring` desenha o círculo de resgate (shader aditivo) sob o herói caído, no dono e nos fantoches.
- Teste: `tests/coop_test.gd` derruba o herói do cliente e o anfitrião o revive.

## Versão web no celular

- `export_presets.cfg` → `html/head_include`: trava o zoom (meta viewport com `maximum-scale=1`), fixa
  `html`/`body`/canvas na tela (sem rolagem) e, ao girar o aparelho, desfaz a rolagem e reavisa o tamanho em
  vários instantes até assentar (o Godot mede `innerWidth`/`innerHeight` a cada quadro). Se a tela cheia cair
  junto com a rotação, ela volta no primeiro toque já na horizontal (o navegador só permite pedir tela cheia
  dentro de um toque).
- Trocar de app/aba: `Platform.set_portrait` guarda a pausa de antes do aviso "gire o celular" e volta a ela
  (só continua pausado se o menu de pausa estava aberto — antes a tela inicial e o carregamento ficavam
  pausados para sempre se o celular passasse pela vertical durante a troca de app). `Platform.reset_input()`
  (sinal `input_reset`) solta movimento, ataque, joystick, botões do HUD e toques da câmera; roda ao perder e
  ganhar foco, em `visibilitychange`/`pagehide`/`blur` do navegador e ao voltar para a horizontal. Um toque
  novo num índice que ainda constava como apertado também zera o estado (o "soltou" anterior se perdeu).
- Áudio na web: `project.godot` usa `audio/general/default_playback_type.web=0` (Stream: o Godot mistura o som,
  com volumes, fades da música e o limitador do Master). No padrão do 4.3 para web (Sample) o jogo ficava mudo.
  `driver/output_latency.web=80` dá folga ao mixer no celular (export sem threads). O `head_include` guarda os
  AudioContext criados e chama `resume()` a cada toque/tecla e ao voltar à aba (o celular suspende o áudio da
  página escondida); no Safari pede `navigator.audioSession.type = "playback"` (toca mesmo com o modo silencioso).
- `vercel.json`: `index.pck`/`index.wasm` com `max-age=0, must-revalidate` (sempre confere a versão; sem
  mudança o servidor responde 304). O service worker do PWA não chega a instalar no export sem threads
  (a lista dele inclui `index.worker.js`, que não existe), então não guarda versões antigas.

## Tecnologias

Autoload `Tech` (`autoload/tech_manager.gd`) com `TechDef` (`data/tech`): custo, tempo, pré-requisitos,
horda mínima e `effects` (chaves somadas por `Tech.bonus(key)`). Consumidores: `Structure._max_hp`
(muros/núcleo) e `refresh_stats`, `Building` (dano/velocidade/alcance de torres), `Harvestable` (coleta),
`Lootable` (saque e chance de equipamento), `BaseServices` (afiar e sorte da Forja) e `Hero` (dano, vida,
regeneração, energia, recarga, carga, cura). Efeitos contínuos no próprio `Tech._process`: reparo automático
e produção dos coletores. Estado no save (`tech`); UI na aba Pesquisa do `BasePanel` e pílula no HUD.

## Inimigos especiais

`EnemyDef.Behavior` ganhou `EXPLODER`, `SPITTER` e `LEAPER`, configurados pelos campos `special_*` do
recurso (raio, alcance, tempo, multiplicador e cor). Em `Enemy`: `_start_fuse()`/`_explode()` (explosão
em área contra aliados, estruturas e — se abatido — outros zumbis, com crédito de XP para quem matou),
`AcidProjectile` + `AcidPuddle` (arco balístico, dano a estruturas no impacto e poça que corrói o grupo
`allies`) e `_begin_leap()`/`_process_leap()` (salto parabólico sem colisão com estruturas; no cerco,
`_leap_over_wall()` pula em direção ao núcleo). Entram na horda por `data/config/horde_default.tres`
(estreia nas hordas 4, 7 e 9, anunciada pelo `HordeDirector`) e na Área Contaminada durante o dia.
Modelos riggados gerados pelo `tools/tripo_pipeline.py`.

### Terror na jogabilidade

- `STALKER` e `SCREAMER` reaproveitam modelos riggados (`EnemyDef.model_id`) com tingimento (`model_tint`;
  materiais tingidos ficam em cache e são compartilhados). Retratos e ícone gerados por `tools/gen_image.py`.
- Olhos: `CharacterModel.add_glow_eyes()` prende um billboard aditivo ao osso da cabeça (`BoneAttachment3D`,
  posição calculada da pose de descanso). O shader puxa o quad 0,35 m para a câmera para a câmera alta ver os
  olhos. Um material por cor; `set_eye_intensity()` (chamado pelo `DayNightVisuals`) acende todos de uma vez.
- Luz: `DayNightVisuals.is_lit(p)` = dia, relâmpago, lanterna de herói (9 m) ou nó no grupo `reveal_lights`
  com o meta `reveal_radius` (tochas 8, torre da paliçada 10, cristal da fortaleza 13, Braseiro = alcance).
  O Espreitador consulta a cada 0,25 s (também no cliente do coop, sem rede); escondido, `is_targetable()` é
  falso e torres, soldados, mira automática e minimapa o ignoram. Dano em área ainda o atinge.
- Gritador: `_begin_scream()` → `_do_scream()` chama `alert(alvo)` nos zumbis do raio (`_frenzy` 6 s: +30%
  velocidade, não desistem do alvo pela distância). O efeito chega ao cliente por `Coop.fx("scream")`.
- Braseiro: `TowerKind.LIGHT` (sem tiro); a cada 0,5 s chama `apply_fear()` (−30% de velocidade, chefes imunes).
- Névoa densa: terceiro clima de `_roll_night()` (nunca junto com tempestade ou lua de sangue);
  `DayNightVisuals.range_mult()` entra em `Building.tower_range()` e `map_reveal_radius()` no minimapa.
- Chefes: `HordeDirector.BOSS_VARIANTS` + `boss_variant()/boss_def()`; `Enemy.make_boss(title)`. Zumbis erguidos
  pela Rainha dos Gritos entram na horda por `HordeDirector.register_extra()`.
- Revisão visual: `ATMO_HORROR=1 ATMO_ONLY=x xvfb-run godot res://tests/atmo_probe.tscn -- <pasta>`.

## Classes do herói

- `HeroSkins.LIST` define por classe `ranged` e `abilities` (ids em `data/skills`); `Hero.skin_id()` resolve a
  classe (a do outro jogador no coop vem de `skin_override`). `Hero.apply_class()` troca em jogo (testes).
- Caçador: `_start_attack()` escolhe o alvo com `_bow_target()` (alcance + cone de 40° em volta da mira) e
  solta a flecha em `_fire_arrow()` (Projectile teleguiado do `EffectsHub`); sem alvo e com recurso perto,
  `_melee_swing` usa o golpe de machado de sempre. A pose: `CharacterModel.aim_bow()` + `_after_anim()`
  (sinal `mixer_applied`), que gira L/R_Upperarm/Forearm com `Quaternion(arco_atual, direção)` por cima da
  animação e posiciona o arco (`assets/models/blender/bow.glb`, `top_level`) na mão esquerda.
- Habilidades novas em `AbilityDef.Kind`: `MULTISHOT`, `TRAP` (`BearTrap`), `ARROW_RAIN` (`ArrowRain`) e
  `EAGLE` (`Eagle`, máquina de estados ORBIT → DIVE → CLIMB; grupo `reveal_lights`). Cada uma tem cópia
  só visual no coop via `Coop.fx_all()` (RPC de qualquer jogador para os outros); o dano de quem não é
  anfitrião vai ao anfitrião pelo caminho normal de `Enemy.take_damage` → `Coop.hit_enemy`.
- HUD: os ícones das habilidades vêm da classe e são carregados fora do `_draw` (carregar textura nova
  durante o desenho a deixa branca no renderizador web).
- Modelos do Blender: `tools/blender_hunter_props.py` (cores em sRGB convertidas para linear; animações
  agrupadas por trilhas NLA de mesmo nome → uma animação glTF por trilha).
- Capim: `tools/blender_ground.py` exporta a cor por vértice com `export_vertex_color="NAME"` (camada "Col",
  valores sRGB crus: o importador já converte). No shader a normal é forçada para cima (as folhas têm as duas
  faces e a de trás ficava preta); `Foliage` faz um MultiMesh por variante de touceira com alcance de 48 m.
- Vegetação rasteira (`gc_*.glb`): `Foliage._scatter_cover` sorteia moitas por pedaço (pesos de campo ou de
  floresta em `Foliage.COVER`), usando `WorldBuilder._is_cover_ground` (capim ou terra, fora de estradas) e
  devolve os centros para o capim rarear em volta. Os MultiMesh levam o meta `kind` (o nome do modelo), que o
  `tests/atmo_probe.gd` usa no modo `ATMO_DECOR=<modelo>` para enquadrar a moita mais cheia.
- Árvores: `tools/blender_trees.py` reaproveita as funções de `blender_ground.py` (folha, galho, cor por
  vértice) e acrescenta tubos de casca, cachos de folhas e leques de agulhas. A copa das folhosas é um
  segundo material: cartões com a textura de raminho (renderizada no início do script, alphaMode MASK →
  alpha scissor no Godot) multiplicada pela cor de vértice; o Godot extrai a textura para
  `<árvore>_horda_tree_leaves.png` (importada com compressão com perdas). O modelo de
  cada árvore vem do `PropFactory.style_rng` (não do gerador do mapa) e o das bordas vem da posição, para a
  geração e os saves seguirem iguais.

## Movimento do herói

- `CharacterModel._measure_stride()` mede, uma vez por modelo, quão rápido o pé de apoio (o mais baixo)
  recua nas animações de andar/correr (`_stride_cache`, em m/s por metro de altura). Com
  `ground_speed >= 0` (o herói preenche a velocidade real do quadro), `_animate_stride()` escolhe
  andar/correr e toca no ritmo exato do passo, sem o pé patinar; `backpedal` toca o passo ao contrário
  (arqueiro recuando enquanto mira, 72% da velocidade). Inimigos seguem com a razão de velocidade antiga.
- `Hero`: aceleração/frenagem curtas (`MOVE_ACCEL`/`MOVE_DECEL`) e joystick analógico (`_input_strength()`:
  pouco desvio = andar).
- Cavaleiro: o modelo da Tripo trazia antebraços, lâminas e cabeças soltos flutuando em volta do corpo
  (pedaços de malha sem osso): `tools/clean_floating_parts.py` separa a malha em partes conectadas e apaga as
  que ficam longe do corpo. A espada (`CharacterModel.attach_sword()`) é um `BoneAttachment3D` no osso
  `R_Hand`, encaixada na primeira pose de "parado" (`_fit_sword`), e acompanha o pulso nos golpes.

## Mapa: densidade, guardiões e baús

- `WorldSpawner` cria os inimigos das regiões em grupos (2–4) até `max` (×0,6 em `Platform.low_end`) e
  repõe 1–3 por vez de dia; a região `Ermos` (`hidden`: o minimapa não escreve o nome) cobre o espaço entre
  as outras. `guardians` vem do `WorldBuilder._place_lair()`: `Enemy.make_guardian()` (×7 vida, ×1,7 dano,
  aura roxa, `is_boss` para o saque) com a vida total escolhida por covil; morto, volta após
  `GUARDIAN_RESPAWN_DAYS` (longe do herói). No coop, o flag 8 e o título vão no `_enemy_spawn`.
- Baús (`PropFactory._setup_chest`, modelos de `tools/blender_chests.py` com a tampa "Lid" separada, com a
  origem na dobradiça): `Lootable.gear_chance/gear_luck/gear_rarity_min` e `guard_radius` (trancado enquanto
  houver guardião vivo por perto, também nos clientes do coop, pois o teste usa `Enemy.all`). Tabelas em
  `data/loot/chest_*.tres`.

## Áudio

`AudioManager` (autoload) cria os canais `Music`, `SFX`, `Ambient` e `UI`; `play(id)`/`play_3d(id, pos, vol, pitch,
gap_ms)` sorteiam entre as variações `assets/sounds/<id>_<n>.ogg` (sem repetir a última) e limitam repetições
no mesmo instante. A música é escolhida a cada quadro pelo estado (`GameManager.state`, `horde_started` /
`horde_ended`, `HordeConfig.is_boss_wave`) com crossfade entre dois players; o ambiente mistura três camadas
(dia, noite, área sombria por distância ao cemitério). Todo `BaseButton` criado ganha som de clique/hover via
`SceneTree.node_added`. Os sons vêm de `tools/oga_fetch.py` + `tools/build_audio.py` (manifesto id → arquivos).

## Atmosfera de terror

- `DayNightVisuals` (no mundo, acesso por `DayNightVisuals.current`) calcula todo quadro sol, céu, neblina e
  ajustes de cor a partir de `TimeManager.daylight()`, mais a lua de sangue (`blood_moon`, rodadas de chefe) e a
  tempestade (`storm`). Os dois são sorteados por `_roll_night()` só a partir do número da rodada, então anfitrião
  e convidados chegam ao mesmo resultado sem RPC.
- Relâmpago: `_flash` (0..1) soma energia ao sol e à luz ambiente; o HUD lê `lightning_flash()` para clarear a tela.
  Trovão com atraso aleatório. Chuva: `GPUParticles3D` que segue o herói (200/450/900 gotas por qualidade; nada na Baixa).
- Lanternas: `OmniLight3D` no grupo `hero_lantern` (criada em `Hero._ready`), energia e tremulação definidas aqui.
- O chão é dividido em `GROUND_CHUNKS`² blocos (`WorldBuilder._build_ground`). O renderizador Compatibility (web)
  aplica no máximo `limits/opengl/max_lights_per_object` (12) luzes por objeto; num chão único, tochas e brilhos de
  saque ocupavam as vagas e a lanterna sumia. O shader do terreno usa coordenadas de mundo, então os blocos não têm emenda.
- Tela (`HUD._update_screen_fx`): um `ColorRect` com shader faz vinheta noturna, granulado, borda vermelha na lua de
  sangue, flash de dano e pulso de vida baixa sincronizado com o som do coração. Não lê a textura da tela (barato no celular).
- Áudio: camadas de ambiente `horror` (noite e área contaminada) e `storm` (chuva) no `AudioManager`; efeitos
  `thunder`, `howl`, `scream`, `ghost`, `crow`, `heartbeat(_fast)` gerados por `tools/build_audio.py`.
- Sangue: `EffectsHub.spawn_blood_pool()` em `enemy_killed`; 48 manchas recicladas que somem em 40 s.

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
