#!/usr/bin/env python3
"""Sintetiza efeitos sonoros procedurais (WAV 22kHz mono) para o protótipo."""
import numpy as np, wave, os
SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets/sounds")
rng = np.random.default_rng(7)

def t(d): return np.linspace(0, d, int(SR*d), endpoint=False)
def env(n, a=0.005, r=0.2, d=None):
    x = np.ones(n); A = max(1,int(a*SR)); x[:A] = np.linspace(0,1,A)
    R = min(n, int(r*SR)); x[-R:] *= np.linspace(1,0,R)**2
    return x
def noise(d): return rng.uniform(-1,1,int(SR*d))
def lp(x, k):
    # filtro passa-baixa simples (média móvel exponencial)
    y = np.zeros_like(x); a = k; s = 0.0
    for i,v in enumerate(x): s += a*(v-s); y[i] = s
    return y
def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x))+1e-9) * gain
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name+".wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x*32767).astype(np.int16).tobytes())

# Golpe de arma (whoosh)
d=0.28; n=noise(d); sweep=np.linspace(0.05,0.4,len(n))
save("swing", lp(n,0.25)*np.sin(np.linspace(0,np.pi,len(n)))**2, 0.6)
# Impacto carnudo
d=0.22; x=lp(noise(d),0.15)*env(int(SR*d),0.001,0.2)+0.6*np.sin(2*np.pi*90*t(d))*np.exp(-t(d)*25)
save("zombie_hit", x, 0.7)
save("hit", lp(noise(0.15),0.4)*np.exp(-t(0.15)*30)+0.5*np.sin(2*np.pi*140*t(0.15))*np.exp(-t(0.15)*30), 0.7)
# Herói ferido (grunhido curto)
d=0.3; f=180*np.exp(-t(d)*2); ph=np.cumsum(2*np.pi*f/SR)
save("hero_hurt", (np.sign(np.sin(ph))*0.4+lp(noise(d),0.1))*env(int(SR*d),0.01,0.2), 0.6)
# Morte de zumbi (gemido descendente)
d=0.9; f=160*np.exp(-t(d)*1.2)+20*np.sin(2*np.pi*6*t(d)); ph=np.cumsum(2*np.pi*f/SR)
save("zombie_death", (np.sin(ph)+0.5*np.sin(2*ph)+0.3*lp(noise(d),0.08))*env(int(SR*d),0.02,0.5), 0.7)
# Gemido ambiente noturno
d=1.6; f=110+25*np.sin(2*np.pi*1.3*t(d)); ph=np.cumsum(2*np.pi*f/SR)
save("groan", (np.sin(ph)+0.6*np.sin(3*ph+0.5)+0.4*lp(noise(d),0.05))*env(int(SR*d),0.3,0.7), 0.5)
# Machado na madeira
d=0.25; x=0.8*np.sin(2*np.pi*320*t(d))*np.exp(-t(d)*35)+lp(noise(d),0.5)*np.exp(-t(d)*40)
save("chop", x, 0.7)
# Picareta na pedra
d=0.3; x=sum(np.sin(2*np.pi*f*t(d))*np.exp(-t(d)*k) for f,k in [(1200,30),(1830,40),(2650,50)])+0.5*noise(d)*np.exp(-t(d)*60)
save("mine", x, 0.6)
# Saque (caixa abrindo / tilintar)
d=0.5; x=lp(noise(d),0.3)*np.exp(-t(d)*12)*0.6
for i,f in enumerate([880,1320,1760]):
    s=int(SR*(0.12+i*0.07)); tt=t(d-s/SR); x[s:] += 0.4*np.sin(2*np.pi*f*tt)*np.exp(-tt*10)
save("loot", x, 0.6)
# Coleta de item
d=0.18; f=np.linspace(700,1400,int(SR*d)); ph=np.cumsum(2*np.pi*f/SR)
save("pickup", np.sin(ph)*env(int(SR*d),0.005,0.1), 0.45)
# Depósito no armazém
d=0.6; x=np.zeros(int(SR*d))
for i,f in enumerate([523,659,784]):
    s=int(SR*i*0.1); tt=t(d-s/SR); x[s:] += np.sin(2*np.pi*f*tt)*np.exp(-tt*6)
save("deposit", x, 0.5)
# Cura
d=0.8; x=np.zeros(int(SR*d))
for i,f in enumerate([660,880,990,1320]):
    s=int(SR*i*0.08); tt=t(d-s/SR); x[s:] += np.sin(2*np.pi*f*tt)*np.exp(-tt*5)*(0.5+0.5*np.sin(2*np.pi*12*tt))
save("heal", x, 0.45)
# Trombeta de guerra (aviso de horda)
d=2.6; f=np.where(t(d)<0.5, 110+20*t(d)/0.5, 130); ph=np.cumsum(2*np.pi*f/SR)
x=sum(np.sin(k*ph)/k for k in range(1,9))*env(int(SR*d),0.25,0.8)*(1+0.05*np.sin(2*np.pi*5*t(d)))
save("horn", x, 0.75)
# Aviso do entardecer (sino)
d=2.0; x=sum(np.sin(2*np.pi*f*t(d))*np.exp(-t(d)*k)*a for f,k,a in [(220,1.5,1),(440,2,0.5),(587,2.5,0.4),(880,3,0.2)])
save("bell", x, 0.6)
# Amanhecer (acorde maior suave)
d=2.4; x=sum(np.sin(2*np.pi*f*t(d)) for f in [392,494,587,784])*env(int(SR*d),0.6,1.2)
save("dawn", x, 0.5)
# Estrutura quebrando
d=0.9; x=lp(noise(d),0.2)*np.exp(-t(d)*4)
for k in range(6):
    s=int(SR*rng.uniform(0,0.5)); tt=t(d-s/SR); x[s:] += 0.6*np.sin(2*np.pi*rng.uniform(150,400)*tt)*np.exp(-tt*25)
save("break", x, 0.75)
# Clique de interface
save("ui_click", np.sin(2*np.pi*1100*t(0.06))*np.exp(-t(0.06)*70), 0.4)
save("ui_error", np.sign(np.sin(2*np.pi*180*t(0.18)))*env(int(SR*0.18),0.005,0.05), 0.3)
print("ok")
