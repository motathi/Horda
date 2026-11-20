#!/usr/bin/env python3
"""Converte os sons CC0 baixados do OpenGameArt (tools/oga_fetch.py) para o jogo:
corta silêncio, normaliza loudness e exporta OGG Vorbis (SFX mono, música/ambiente estéreo).
Uso: python3 tools/build_audio.py <pasta_oga>
Saída: assets/sounds/<id>_<n>.ogg, assets/music/<id>.ogg, assets/ambient/<id>.ogg e
assets/sounds/CREDITS.md (autor e página de cada pacote)."""
import glob, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# id -> lista de padrões glob (relativos à pasta baixada). Cada arquivo vira uma variação.
SFX = {
    "swing": ["rpg-sound-pack/**/battle/swing*.wav", "80-cc0-rpg-sfx/**/blade_0[1-3].ogg"],
    "hit": ["37-hitspunches/**/hit0[1-9].mp3.flac", "50-rpg-sound-effects/**/knifeSlice*.ogg"],
    "zombie_hit": ["37-hitspunches/**/hit2[0-6].mp3.flac", "rpg-sound-pack/**/beetle/bite-small*.wav"],
    "hero_hurt": ["37-hitspunches/**/hit1[0-5].mp3.flac"],
    "chop": ["35-wooden-crackshitsdestructions/**/impactwood0[1-8].mp3.flac", "50-rpg-sound-effects/**/chop.ogg"],
    "mine": ["80-cc0-rpg-sfx/**/item_stone_0*.ogg", "80-cc0-rpg-sfx/**/stones_0*.ogg"],
    "break": ["35-wooden-crackshitsdestructions/**/crack0[1-6].mp3.flac"],
    "zombie_death": ["80-cc0-rpg-sfx/**/creature_die_01.ogg", "undead-moans/undead-*.ogg", "rpg-sound-pack/**/gutteral beast/mnstr[1-5].wav"],
    "zombie_attack": ["16-monster-growls/**/monster.[9].ogg", "16-monster-growls/**/monster.1[0-6].ogg", "rpg-sound-pack/**/gutteral beast/mnstr[6-9].wav", "rpg-sound-pack/**/gutteral beast/mnstr1[0-5].wav"],
    "groan": ["undead-moans/undead-*.ogg", "rpg-sound-pack/**/shade/shade[1-8].wav", "16-monster-growls/**/monster.[1-8].ogg", "@split:zombie-moans/*.ogg"],
    "skeleton": ["80-cc0-rpg-sfx/**/wood_0[1-5].ogg", "80-cc0-rpg-sfx/**/chain_0*.ogg"],
    "heal": ["rpg-sound-pack/**/inventory/bubble*.wav", "80-cc0-rpg-sfx/**/spell_02.ogg"],
    "loot": ["100-cc0-sfx/**/wooded_box_open.ogg", "50-rpg-sound-effects/**/doorOpen_*.ogg", "50-rpg-sound-effects/**/creak*.ogg"],
    "pickup": ["80-cc0-rpg-sfx/**/item_coins_0*.ogg", "50-rpg-sound-effects/**/cloth[1-4].ogg", "80-cc0-rpg-sfx/**/item_wood_0*.ogg"],
    "deposit": ["80-cc0-rpg-sfx/**/item_misc_0[1-4].ogg", "50-rpg-sound-effects/**/dropLeather.ogg", "50-rpg-sound-effects/**/beltHandle*.ogg"],
    "ui_click": ["51-ui-sound-effects-buttons-switches-and-clicks/**/click[1-5].wav"],
    "ui_hover": ["51-ui-sound-effects-buttons-switches-and-clicks/**/rollover[1-3].wav"],
    "ui_error": ["rpg-sound-pack/**/interface/interface[4-6].wav"],
    "bell": ["100-cc0-sfx/**/bell_0*.ogg"],
    "gong": ["100-cc0-sfx/**/gong_0*.ogg"],
    "levelup": ["80-cc0-rpg-sfx/**/item_gem_0*.ogg"],
    "objective": ["80-cc0-rpg-sfx/**/item_coins_0[1-2].ogg", "50-rpg-sound-effects/**/handleCoins*.ogg"],
    "step_grass": ["fantozzis-footsteps-grasssand-stone/**/Fantozzi-Sand*.ogg"],
    "step_stone": ["fantozzis-footsteps-grasssand-stone/**/Fantozzi-Stone*.ogg"],
    "ab_whirl": ["20-sword-sound-effects-attacks-and-clashes/**/sword.[1-5].ogg"],
    "ab_dash": ["20-sword-sound-effects-attacks-and-clashes/**/sword.[6-9].ogg", "rpg-sound-pack/**/battle/sword-unsheathe*.wav"],
    "ab_warcry": ["rpg-sound-pack/**/giant/giant[1-3].wav", "80-cc0-rpg-sfx/**/creature_roar_0*.ogg"],
    "ab_nova": ["80-cc0-rpg-sfx/**/spell_fire_0[1-4].ogg", "rpg-sound-pack/**/battle/magic1.wav"],
    "explosion": ["chunky-explosion/*.mp3", "100-cc0-sfx/**/explosion.ogg", "80-cc0-rpg-sfx/**/spell_fire_0[5-7].ogg"],
    "cannon": ["100-cc0-sfx/**/slam_0[1-4].ogg"],
    "bolt": ["100-cc0-sfx/**/spring_0[1-4].ogg"],
    "arrow": ["rpg-sound-pack/**/battle/swing*.wav"],
    "zap": ["80-cc0-rpg-sfx/**/spell_01.ogg", "rpg-sound-pack/**/battle/spell.wav", "100-cc0-sfx/**/weird_0[1-3].ogg"],
    "spit": ["rpg-sound-pack/**/slime/slime[1-5].wav", "80-cc0-rpg-sfx/**/creature_slime_0*.ogg"],
    "acid": ["100-cc0-sfx/**/splash_0*.ogg", "rpg-sound-pack/**/slime/slime[6-9].wav"],
    "leap": ["rpg-sound-pack/**/misc/wolfman.wav", "80-cc0-rpg-sfx/**/creature_misc_0[1-4].ogg"],
    "build": ["100-cc0-sfx/**/tools_0*.ogg", "35-wooden-crackshitsdestructions/**/impactwood1[0-4].mp3.flac"],
    "upgrade": ["80-cc0-rpg-sfx/**/metal_0*.ogg", "100-cc0-sfx/**/metal_0[1-4].ogg"],
    # Atmosfera de terror
    "crow": ["crow/crow_0.ogg", "crow-caw/crow_caw.wav"],
    "scream": ["female-scream-1/*.ogg", "80-cc0-creature-sfx/**/scream_0[1-2].ogg"],
    "ghost": ["ghost-breath/*.flac", "ghost-monster-voice-moaning-growling/**/qubodup-GhostMoan0[1-5].wav"],
    "howl": ["80-cc0-creature-sfx/**/howl.ogg"],
    "heartbeat": ["heartbeat-sounds/heartbeat_slow_0.wav"],
    "heartbeat_fast": ["heartbeat-sounds/heartbeat_fast_0.wav"],
    "fuse": ["rpg-sound-pack/**/slime/slime10.wav", "80-cc0-rpg-sfx/**/creature_monster_0[1-2].ogg"],
}
# Efeitos longos (sem o corte de 4 s): id -> [(padrão, início s, duração s), ...]
LONG_SFX = {
    "thunder": [("rain-long-thunder/rain-thunder.ogg", 21.0, 14.0), ("rain-long-thunder/rain-thunder.ogg", 25.2, 9.0)],
}
# id -> (padrão, início s, duração s ou 0 = inteiro[, canais])  — trilha de terror (CC0)
MUSIC = {
    "menu": ("a-detuned-memory/*.mp3", 0, 0),
    "prep_1": ("horror-atmosphere/*.ogg", 0, 0, 1),
    "prep_2": ("lost-in-a-bad-place-horror-ambience-loop/*.ogg", 0, 0, 1),
    "prep_3": ("a-lurking-evil-horror-ambience/*.ogg", 0, 0, 1),
    "battle_1": ("the-hunt/*.ogg", 0, 0),
    "battle_2": ("chase-in-the-night/*.wav", 0, 0),
    "battle_3": ("menacing-otherworld/*.mp3", 0, 0),
    "boss": ("ancient-grudge/*.mp3", 0, 0),
    "defeat": ("bleeding-out/*.ogg", 0, 0),
}
AMBIENT = {
    "day": ("amb-morning-sounds-perfect-loop/amb_morning_0.ogg", 0, 0),
    "night": ("crickets-ambient-noise-loopable/*.mp3", 0, 0),
    "dark": ("dark-ambiences/**/ambience-3.wav", 0, 0),
    "horror": ("ambient-horror/ambient_horror_0.ogg", 0, 0),
    "storm": ("rain-long-thunder/rain-thunder.ogg", 0, 20.5),
}

def ff(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)

def find(base, pat):
    return sorted(f for f in glob.glob(os.path.join(base, pat), recursive=True) if not os.path.basename(f).startswith("._"))

def split_on_silence(path, minlen=0.6):
    """Corta um arquivo com vários gemidos em pedaços (detecção de silêncio)."""
    r = subprocess.run(["ffmpeg", "-i", path, "-af", "silencedetect=noise=-38dB:d=0.35", "-f", "null", "-"], capture_output=True, text=True)
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", r.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", r.stderr)]
    segs, cur = [], 0.0
    for s, e in zip(starts, ends):
        if s - cur >= minlen:
            segs.append((cur, s - cur))
        cur = e
    return segs

SFX_FILTER = "silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse,loudnorm=I=-16:TP=-1.5:LRA=11"

def main(base):
    out_s = os.path.join(ROOT, "assets/sounds")
    os.makedirs(out_s, exist_ok=True)
    total = 0
    for sid, pats in SFX.items():
        for old in glob.glob(os.path.join(out_s, sid + "_*.ogg")):
            os.remove(old)
        n = 0
        for pat in pats:
            if pat.startswith("@split:"):
                for f in find(base, pat[7:]):
                    for (st, du) in split_on_silence(f)[:6]:
                        n += 1
                        ff(["-ss", f"{st:.2f}", "-t", f"{min(du, 3.0):.2f}", "-i", f, "-af", SFX_FILTER, "-ac", "1", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "3", os.path.join(out_s, f"{sid}_{n}.ogg")])
                continue
            for f in find(base, pat):
                n += 1
                ff(["-i", f, "-t", "4", "-af", SFX_FILTER, "-ac", "1", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "3", os.path.join(out_s, f"{sid}_{n}.ogg")])
        total += n
        print(f"{sid}: {n} variações", flush=True)
    for sid, parts in LONG_SFX.items():
        for old in glob.glob(os.path.join(out_s, sid + "_*.ogg")):
            os.remove(old)
        for n, (pat, st, du) in enumerate(parts, 1):
            src = find(base, pat)[0]
            ff(["-ss", str(st), "-t", str(du), "-i", src, "-af", f"afade=t=in:d=0.15,afade=t=out:st={du - 3.0}:d=3,loudnorm=I=-16:TP=-1.5",
                "-ac", "1", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "2", os.path.join(out_s, f"{sid}_{n}.ogg")])
        total += len(parts)
        print(f"{sid}: {len(parts)} variações (longas)", flush=True)
    for folder, table, lufs in (("music", MUSIC, -18), ("ambient", AMBIENT, -24)):
        od = os.path.join(ROOT, "assets", folder)
        os.makedirs(od, exist_ok=True)
        for mid, spec in table.items():
            pat, st, du = spec[0], spec[1], spec[2]
            ch = spec[3] if len(spec) > 3 else 2  # ambiências da preparação em mono (menor download)
            src = find(base, pat)[0]
            args = ["-ss", str(st)] + (["-t", str(du)] if du else []) + ["-i", src, "-af", f"loudnorm=I={lufs}:TP=-1.5", "-ac", str(ch), "-ar", "44100" if ch == 2 else "32000", "-c:a", "libvorbis", "-q:a", "0", os.path.join(od, mid + ".ogg")]
            ff(args)
            print(f"{folder}/{mid}.ogg <- {os.path.relpath(src, base)}", flush=True)
    # Créditos (autor e página de cada pacote usado).
    used = set()
    for pats in SFX.values():
        for p in pats:
            used.add(p.replace("@split:", "").split("/")[0])
    for parts in LONG_SFX.values():
        for pat, _, _ in parts:
            used.add(pat.split("/")[0])
    for spec in list(MUSIC.values()) + list(AMBIENT.values()):
        used.add(spec[0].split("/")[0])
    lines = ["# Créditos de áudio", "", "Todos os sons e músicas são **CC0 1.0** (domínio público), do OpenGameArt.org.",
             "Baixados com `tools/oga_fetch.py` (que confere a licença) e convertidos com `tools/build_audio.py`.", ""]
    for slug in sorted(used):
        m = os.path.join(base, slug, "meta.json")
        meta = json.load(open(m)) if os.path.exists(m) else {}
        lines.append(f"- {meta.get('url', slug)} — autor: {meta.get('author', '?')} — {meta.get('license', 'CC0')}")
    open(os.path.join(out_s, "CREDITS.md"), "w").write("\n".join(lines) + "\n")
    print(f"total SFX: {total}")

if __name__ == "__main__":
    main(sys.argv[1])
