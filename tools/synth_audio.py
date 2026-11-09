"""Synthesises every sound in the game from noise + oscillators (no recorded samples).
Output: audio/*.ogg (Vorbis) plus WAV previews. Run: python3 tools/synth_audio.py"""
import numpy as np, subprocess, os, json
from scipy import signal
SR = 44100
rng = np.random.default_rng(20261109)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")
PREV = os.path.join(ROOT, "screenshots", "v3", "audio_preview")

def t_axis(dur): return np.arange(int(dur * SR)) / SR
def white(n): return rng.standard_normal(n)
def pink(n):
    X = np.fft.rfft(white(n)); f = np.fft.rfftfreq(n, 1 / SR); f[0] = f[1]
    y = np.fft.irfft(X / np.sqrt(f), n); return y / np.std(y)
def brown(n):
    y = np.cumsum(white(n)); y = signal.sosfilt(signal.butter(1, 20, 'hp', fs=SR, output='sos'), y); return y / np.std(y)
def bp(x, lo, hi, order=2): return signal.sosfilt(signal.butter(order, [lo, hi], 'bp', fs=SR, output='sos'), x)
def lp(x, f, order=2): return signal.sosfilt(signal.butter(order, f, 'lp', fs=SR, output='sos'), x)
def hp(x, f, order=2): return signal.sosfilt(signal.butter(order, f, 'hp', fs=SR, output='sos'), x)
def env_exp(t, tau, t0=0.0, attack=0.002):
    e = np.where(t >= t0, np.exp(-(t - t0) / tau), 0.0)
    a = np.clip((t - t0) / attack, 0, 1); return e * a
def chirp(t, f0, f1, dur, t0=0.0):
    tt = np.clip(t - t0, 0, None)
    f = f0 + (f1 - f0) * np.clip(tt / dur, 0, 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * (t >= t0)
def fades(x, fin=0.002, fout=0.03):
    n_in, n_out = int(fin * SR), int(fout * SR)
    x = x.copy()
    if x.ndim == 1: x = x[:, None]
    x[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    x[-n_out:] *= np.linspace(1, 0, n_out)[:, None] ** 2
    return x.squeeze()
def norm(x, peak_db=-3.0):
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)

def write(name, x, q=4):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1: x = x[:, None]
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    wav = os.path.join(PREV, name + ".wav")
    import wave
    with wave.open(wav, 'wb') as w:
        w.setnchannels(pcm.shape[1]); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q), ogg], check=True)
    subprocess.run(["cp", ogg, os.path.join(PREV, name + ".ogg")], check=True)

# ---------------------------------------------------------------- ambience loop
def ocean_loop(L=24.0, X=3.0):
    n = int((L + X) * SR); t = np.arange(n) / SR
    out = np.zeros((n, 2))
    # 1) continuous distant surf: pink noise, low-passed, slow swell (periodic in L)
    for ch in range(2):
        base = lp(pink(n), 650, 2) * 0.55 + lp(brown(n), 300, 2) * 0.35
        swell = 0.65 + 0.2 * np.sin(2 * np.pi * t / 12 + ch * 0.4) + 0.15 * np.sin(2 * np.pi * t / 8 + 1.3)
        out[:, ch] += base * swell * 0.5
    # 2) individual waves breaking on the beach
    for w0 in [0.6, 6.4, 11.9, 17.3, 21.9, 25.4]:
        pan = rng.uniform(0.3, 0.7)
        size = rng.uniform(0.7, 1.0)
        crash_t = w0 + 1.4
        # swell rises and falls smoothly (no hard edges), crash attack ~0.35 s, wash recedes
        build = np.exp(-((t - (w0 + 1.0)) ** 2) / (2 * 0.55 ** 2))
        att = np.clip((t - crash_t + 0.35) / 0.35, 0, 1) ** 2
        crash = att * np.where(t > crash_t, np.exp(-(t - crash_t) / 0.6), 1.0)
        wash_t = crash_t + 0.4
        watt = np.clip((t - wash_t + 0.6) / 0.6, 0, 1)
        wash = watt * np.where(t > wash_t, np.exp(-(t - wash_t) / 1.05), 1.0)
        fizz = 0.55 + 0.45 * lp(np.abs(white(n)), 14, 1) / 0.8
        for ch in range(2):
            g = (1 - pan) if ch == 0 else pan
            s = lp(pink(n), 450) * build * 0.45
            s += bp(pink(n), 220, 3200) * crash * 0.85
            s += bp(white(n), 1200, 5200) * wash * fizz * 0.22
            out[:, ch] += s * g * size * 1.2
    # 3) water lapping against the dock posts
    tt = 0.3
    while tt < L + X - 0.5:
        a = rng.uniform(0.15, 0.35); f = rng.uniform(380, 900)
        e = env_exp(t, rng.uniform(0.05, 0.09), tt, 0.008)
        s = bp(white(n), f, f * 2.2) * e * a
        pan = rng.uniform(0.2, 0.8)
        out[:, 0] += s * (1 - pan); out[:, 1] += s * pan
        tt += rng.uniform(0.7, 2.2)
    # 4) light wind
    wind = bp(pink(n), 180, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 24 * 2 + 0.7) ** 2) * 0.12
    out += wind[:, None] * np.array([0.9, 1.0])
    # seamless loop: equal-power crossfade of the tail [L, L+X) into the head
    out = hp(out.T, 30, 2).T
    nL, nX = int(L * SR), int(X * SR)
    head = out[:nX].copy(); tail = out[nL:nL + nX]
    k = np.linspace(0, 1, nX)[:, None]
    out[:nX] = head * np.sin(k * np.pi / 2) + tail * np.cos(k * np.pi / 2)
    y = out[:nL]
    return norm(y, -4.0)

# ---------------------------------------------------------------- one shots
def skip_sound(seed):
    r = np.random.default_rng(seed); t = t_axis(0.35)
    slap = bp(white(len(t)), 700, 7000) * env_exp(t, r.uniform(0.012, 0.02), 0.0, 0.0015)
    spray = bp(white(len(t)), 2500, 9000) * env_exp(t, r.uniform(0.03, 0.05), 0.004, 0.004) * 0.3
    f0 = r.uniform(650, 1050)
    drop = chirp(t, f0, f0 * r.uniform(1.5, 1.9), 0.035, 0.006) * env_exp(t, 0.03, 0.006, 0.002) * 0.55
    f1 = r.uniform(1100, 1700)
    drop2 = chirp(t, f1, f1 * 1.6, 0.025, r.uniform(0.04, 0.08)) * env_exp(t, 0.02, 0.05, 0.002) * 0.25
    return fades(norm(slap + spray + drop + drop2, -3.0), 0.001, 0.05)

def sink_sound():
    t = t_axis(1.3); n = len(t)
    plunge = lp(white(n), 2200) * env_exp(t, 0.11, 0.0, 0.004)
    spray = bp(white(n), 1200, 6500) * env_exp(t, 0.18, 0.01, 0.01) * 0.35
    gulp = chirp(t, 210, 520, 0.09, 0.02) * env_exp(t, 0.11, 0.02, 0.004) * 0.9
    gulp2 = chirp(t, 340, 690, 0.07, 0.17) * env_exp(t, 0.08, 0.17, 0.004) * 0.45
    bubbles = np.zeros(n)
    for b0 in [0.3, 0.42, 0.55, 0.71, 0.86]:
        f = rng.uniform(800, 1500)
        bubbles += chirp(t, f, f * 1.5, 0.02, b0) * env_exp(t, 0.018, b0, 0.002) * rng.uniform(0.08, 0.18)
    return fades(norm(plunge * 0.8 + spray + gulp + gulp2 + bubbles, -2.5), 0.001, 0.15)

def whoosh():
    dur = 0.5; n = int(dur * SR); x = white(n)
    f, tt, Z = signal.stft(x, SR, nperseg=1024, noverlap=768)
    tn = tt / dur
    fc = 350 + 1700 * np.sin(np.pi * np.clip(tn, 0, 1)) ** 1.5
    mask = np.exp(-((np.log(f[:, None] + 1) - np.log(fc[None, :])) ** 2) / (2 * 0.35 ** 2))
    amp = np.exp(-((tn - 0.42) ** 2) / (2 * 0.16 ** 2))
    _, y = signal.istft(Z * mask * amp[None, :], SR, nperseg=1024, noverlap=768)
    return fades(norm(y[:n], -4.0), 0.01, 0.06)

def modal(freqs, amps, taus, dur, click_band, click_tau, click_amp):
    t = t_axis(dur); y = np.zeros(len(t))
    for f, a, tau in zip(freqs, amps, taus):
        y += a * np.sin(2 * np.pi * f * t * (1 + 0.002 * rng.standard_normal())) * env_exp(t, tau, 0.0, 0.0008)
    y += bp(white(len(t)), *click_band) * env_exp(t, click_tau, 0, 0.0005) * click_amp
    return y

def wood_knock():
    y = modal([185, 470, 830, 1340, 2150], [1, 0.6, 0.45, 0.28, 0.18], [0.085, 0.06, 0.04, 0.028, 0.018], 0.45, (800, 5000), 0.004, 0.8)
    return fades(norm(y, -3.0), 0.0005, 0.08)

def rock_clack():
    y = modal([1180, 2470, 3930, 5210], [1, 0.7, 0.45, 0.3], [0.03, 0.022, 0.016, 0.011], 0.3, (2000, 9000), 0.006, 0.9)
    return fades(norm(y, -3.0), 0.0005, 0.05)

def sand_thud():
    t = t_axis(0.35); n = len(t)
    y = lp(white(n), 420) * env_exp(t, 0.05, 0, 0.002) * 1.0
    y += hp(white(n), 2500) * env_exp(t, 0.035, 0.003, 0.002) * 0.12
    return fades(norm(y, -4.0), 0.001, 0.08)

def chime(notes=(1046.5, 1318.5, 1568.0), gap=0.085):
    t = t_axis(0.9); y = np.zeros(len(t))
    for i, f in enumerate(notes):
        t0 = i * gap
        y += np.sin(2 * np.pi * f * (t - t0)) * env_exp(t, 0.32, t0, 0.003) * 0.6
        y += np.sin(2 * np.pi * 4 * f * (t - t0)) * env_exp(t, 0.04, t0, 0.002) * 0.15
        y += np.sin(2 * np.pi * 2 * f * (t - t0)) * env_exp(t, 0.12, t0, 0.003) * 0.12
    return fades(norm(y, -6.0), 0.001, 0.15)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True); os.makedirs(PREV, exist_ok=True)
    write("ocean_loop", ocean_loop(), q=3)
    for i in range(4):
        write(f"skip_{i}", skip_sound(100 + i))
    write("sink", sink_sound())
    write("whoosh", whoosh())
    write("hit_wood", wood_knock())
    write("hit_rock", rock_clack())
    write("hit_sand", sand_thud())
    write("combo", chime())
    write("record", chime((1046.5, 1318.5, 1568.0, 2093.0), 0.09))
    print("done")
