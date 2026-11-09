"""Objective checks on the decoded OGG files: peak/clipping/DC/RMS, loop seam continuity, spectrogram images."""
import numpy as np, subprocess, glob, os, json
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREV = os.path.join(ROOT, "screenshots", "v3", "audio_preview")
def decode(p):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", p, "-f", "f32le", "-ac", "2", "-ar", "44100", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2)
report = {}
fig, axes = plt.subplots(5, 3, figsize=(15, 16)); axes = axes.ravel()
for i, p in enumerate(sorted(glob.glob(os.path.join(ROOT, "audio", "*.ogg")))):
    name = os.path.basename(p)[:-4]; x = decode(p); m = x.mean(1)
    r = {"dur_s": round(len(x) / 44100, 3), "peak_dbfs": round(float(20 * np.log10(np.abs(x).max() + 1e-9)), 2),
         "clipped_samples": int((np.abs(x) >= 0.999).sum()), "dc": round(float(x.mean()), 5),
         "rms_dbfs": round(float(20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9)), 1),
         "start_abs": round(float(np.abs(x[:16]).max()), 4), "end_abs": round(float(np.abs(x[-16:]).max()), 4),
         "kbytes": round(os.path.getsize(p) / 1024, 1)}
    if "loop" in name:
        d = np.abs(np.diff(m)); seam = abs(m[0] - m[-1])
        w = 882; rms = np.sqrt(np.convolve(m ** 2, np.ones(w) / w, "valid"))
        r["seam_jump"] = round(float(seam), 5); r["p999_adjacent_jump"] = round(float(np.percentile(d, 99.9)), 5)
        wrap = np.concatenate([m[-w:], m[:w]]); r["seam_rms_ratio"] = round(float(np.sqrt((wrap ** 2).mean()) / np.median(rms)), 3)
    report[name] = r
    ax = axes[i]; ax.specgram(m, NFFT=1024, Fs=44100, noverlap=768, cmap="magma", vmin=-120); ax.set_title(name); ax.set_ylim(0, 12000)
plt.tight_layout(); plt.savefig(os.path.join(PREV, "spectrograms.png"), dpi=60)
json.dump(report, open(os.path.join(PREV, "audio_check.json"), "w"), indent=1, ensure_ascii=False)
for k, v in report.items(): print(k, v)
