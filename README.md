# Horda: Noites de Sobrevivência

Jogo de sobrevivência cooperativa contra hordas de zumbis (estratégia + RPG + defesa de base),
inspirado em *Night of the Dead: Aftermath* (Warcraft III). Feito em **Godot 4.3+ / GDScript tipado**.

> Estado atual: **Fase 1 — protótipo jogável** concluída.
> Arte gerada por IA no estilo Dota 2 / Warcraft III: texturas, retratos, ícones e conceitos na BytePlus ARK (Seedream);
> **modelos 3D texturizados** (herói, zumbis, fortaleza, muralhas, torres, árvores, casas...) via image-to-3D. Veja o pipeline em docs/ARQUITETURA.md.

## Jogar no navegador / celular

**https://horda-five.vercel.app** — abra no celular na horizontal. No Android (Chrome), use
"Adicionar à tela inicial" para jogar em tela cheia como app.

Celular: joystick à esquerda para andar, botão grande para atacar (mira automática), toque no chão
para ir até lá ou num inimigo para atacá-lo, **E** saqueia, **1/2** curam, **I/B** inventário e base,
pinça para zoom. Parâmetros úteis: `?touch=1` força os controles de toque no PC, `?dbg=1` mostra FPS no console.

Cada push no GitHub recompila automaticamente no Vercel (`tools/vercel_build.sh`, ~1 min).

## Como jogar (PC)

1. Abra a pasta no Godot 4.3 (ou mais novo) e pressione **F5**.
2. *Novo jogo* → escolha dificuldade e duração do ciclo (Normal 22 min / Rápido 11 min).

| Controle | Ação |
|---|---|
| WASD | Mover o herói |
| Clique direito (chão / inimigo) | Mover até o ponto / atacar alvo |
| Clique esquerdo ou Espaço | Golpe em arco na direção do cursor (também corta árvores e quebra pedras) |
| E | Saquear caixas, carros e armários |
| 1 / 2 | Comer carne / usar curativo |
| I ou Tab | Inventário (mochila + armazém) |
| B | Base: reparar muros/núcleo, afiar arma, fabricar curativos |
| Roda / Q, R / C | Zoom / girar câmera / centralizar |
| F5 | Salvar (somente de dia; também salva sozinho a cada amanhecer) |
| F8 | [Depuração] avançar período do dia |
| F1 / Esc | Controles / pausa |

**Ciclo:** de dia explore as regiões (Floresta, Pedreira, Cidade Abandonada, Fazenda, Área Contaminada),
mate zumbis, colete madeira/pedra, saqueie e volte à base — a mochila (60 de peso) é guardada
automaticamente ao entrar. Ao entardecer soa o aviso; à noite a horda vem pelas bordas do mapa,
quebra a paliçada e tenta destruir o **Núcleo**. Sobreviva até o amanhecer: o sol queima os zumbis restantes.
Se o herói cair, renasce na base (e a mochila fica no chão onde morreu). Se o Núcleo cair, fim de jogo.

## Testes

```bash
# Teste automatizado da Fase 1 (gera o mundo, combate, coleta, saque, serviços, noite, amanhecer, save)
godot --headless res://tests/smoke_test.tscn

# Capturas de tela (precisa de display; no Linux sem GPU: xvfb-run + OpenGL)
xvfb-run godot --rendering-driver opengl3 --rendering-method gl_compatibility res://tests/screenshot.tscn -- /tmp/shots
```

## Regenerar arte e sons

```bash
ARK_API_KEY=... python3 tools/gen_image.py tools/art_prompts.json   # só gera o que estiver faltando
python3 tools/gen_sounds.py                                          # efeitos sonoros sintetizados
```

![Horda atacando a base](docs/screenshots/06_night_horde.jpg)

Veja [docs/ARQUITETURA.md](docs/ARQUITETURA.md) para a arquitetura e o roteiro das próximas fases.
