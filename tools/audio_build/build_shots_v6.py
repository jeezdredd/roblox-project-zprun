"""Gunshots v6: natural outdoor shots from the FFSL Prepared SFX Library.

The v5 layered shots measured as 0.7 s of dense noise with nothing above ~6.5 kHz (the
legacy body was low-passed to 3.5 kHz and bus-compressed): the "muffled, like indoors"
report. The Prepared files (Ben Jaszczak's own mix of the range recordings, CC0) have the
natural structure of a shot fired outdoors: the blast and the mechanism in the first
~0.12 s, near silence, then the range's reflection from ~0.14 s and a decay to -60 dB over
~2 s. v6 splits each shot at that gap:

  close_<class>[_02|_03]  blast + mechanism, dry (0 .. 0.13 s, 20 ms crossfade)
  tail_open_<class>       the outdoor reflection and decay, padded with silence so it
                          lines up when both play at once (sum = the original shot)

Channels: the two mics are 1-3 ms apart; the later one is delayed back into line so the
transient stays mono-compatible, and both are matched in RMS over the blast. 96 kHz ->
48 kHz, 30 Hz high-pass, peak -1 dBFS on the close part, the same gain on the tail.
"""
import json, os, subprocess
import numpy as np, soundfile as sf
from scipy.signal import correlate, resample_poly, butter, sosfilt

LIB = '/home/claude/ffsl_prep/Prepared SFX Library'
OUT = '/home/claude/agents/audio/v6'
SR_OUT = 48000
PRE = 0.003            # s kept before the onset
XF_START, XF_END = 0.110, 0.130   # crossfade window after the onset
TAIL_MAX = 2.8
TAIL_FADE = 0.45

# class: [(file, approx onset), ...]; the first entry also gives the class tail
SHOTS = {
    'rifle': [('AK-47/C_28P.wav', 0.610), ('AK-47/C_28P.wav', 3.258), ('AK-47/C_28P.wav', 6.026)],
    'pistol': [('Walther PPQ/X_39P.wav', 1.412), ('Walther PPQ/X_39P.wav', 6.446), ('Walther PPQ/X_39P.wav', 10.664)],
    'shotgun': [('Nova/O_21P.wav', 0.436), ('Nova/O_21P.wav', 3.466), ('Nova/O_17P.wav', 3.718)],
    'smg': [('Carl Gustav M45/G_31P.wav', 0.312), ('Carl Gustav M45/G_31P.wav', 3.506), ('Carl Gustav M45/G_31P.wav', 6.730)],
}
NEXT_ONSETS = {}  # file -> sorted onsets, to stop a tail before the next shot
for cls, items in SHOTS.items():
    for f, t in items:
        NEXT_ONSETS.setdefault(f, set()).add(t)
EXTRA = {'Nova/O_17P.wav': [0.696], 'AK-47/C_28P.wav': [9.162]}
for f, ts in EXTRA.items():
    NEXT_ONSETS.setdefault(f, set()).update(ts)

def write_ogg(path_ogg, x, sr):
    wav = path_ogg[:-4] + '.wav'
    sf.write(wav, x.astype(np.float32), sr, subtype='FLOAT')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'libvorbis', '-q:a', '6', path_ogg], check=True)
    os.remove(wav)

def prepare(path, t):
    x, sr = sf.read(os.path.join(LIB, path), always_2d=True)
    # precise onset: first sample above 10 % of the local peak
    a = int((t - 0.05) * sr); b = int((t + 0.02) * sr)
    seg = np.abs(x[a:b]).max(axis=1)
    onset = a + int(np.argmax(seg > 0.1 * seg.max()))
    # channel alignment on the blast
    w0 = onset - int(0.005 * sr); w1 = onset + int(0.04 * sr)
    c = correlate(x[w0:w1, 0], x[w0:w1, 1], mode='full')
    lag = int(np.argmax(np.abs(c)) - (w1 - w0 - 1))  # > 0: ch0 is late
    ch0, ch1 = x[:, 0].copy(), x[:, 1].copy()
    if lag > 0:
        ch1 = np.concatenate([np.zeros(lag), ch1[:-lag]])
    elif lag < 0:
        ch0 = np.concatenate([np.zeros(-lag), ch0[:lag]])
    r0 = np.sqrt((ch0[onset:onset + int(0.1 * sr)] ** 2).mean())
    r1 = np.sqrt((ch1[onset:onset + int(0.1 * sr)] ** 2).mean())
    mean = np.sqrt(r0 * r1)
    y = np.stack([ch0 * mean / r0, ch1 * mean / r1], axis=1)
    later = sorted(o for o in NEXT_ONSETS[path] if o > t + 0.2)
    end_limit = (later[0] - 0.05) if later else len(x) / sr
    start = onset - int(PRE * sr)
    end = min(int((onset / sr + TAIL_MAX) * sr), int(end_limit * sr))
    y = y[start:end]
    y = resample_poly(y, SR_OUT, sr, axis=0)
    # rumble and DC out before the split, so close and tail stay continuous
    y = sosfilt(butter(2, 30, 'highpass', fs=SR_OUT, output='sos'), y, axis=0)
    return y, lag / sr * 1000, 20 * np.log10(r1 / r0)

def split(y):
    n = len(y); sr = SR_OUT
    t = np.arange(n) / sr - PRE
    fade_out = np.clip((XF_END - t) / (XF_END - XF_START), 0, 1)
    fade_out = np.sin(fade_out * np.pi / 2) ** 2
    fade_in = 1 - fade_out
    close = (y * fade_out[:, None])[: int((PRE + XF_END) * sr) + 1]
    tail = y * fade_in[:, None]
    # tail fade-out and rumble high-pass
    nf = int(TAIL_FADE * sr)
    tail[-nf:] *= np.linspace(1, 0, nf)[:, None] ** 2
    return close, tail

def db(v):
    return 20 * np.log10(max(v, 1e-12))

report = {}
for cls, items in SHOTS.items():
    for index, (path, t) in enumerate(items):
        y, lag_ms, bal_db = prepare(path, t)
        close, tail = split(y)
        gain = 10 ** (-1 / 20) / np.abs(close).max()
        close *= gain; tail *= gain
        suffix = '' if index == 0 else f'_0{index + 1}'
        write_ogg(f'{OUT}/close_{cls}{suffix}_v6.ogg', close, SR_OUT)
        entry = {
            'source_file': path, 'onset_s': t, 'channel_lag_ms': round(lag_ms, 2), 'channel_rms_diff_db': round(bal_db, 1),
            'close_ms': round(len(close) / SR_OUT * 1000), 'close_peak_db': round(db(np.abs(close).max()), 1),
            'close_rms_db': round(db(np.sqrt((close ** 2).mean())), 1),
        }
        if index == 0:
            write_ogg(f'{OUT}/tail_open_{cls}_v6.ogg', tail, SR_OUT)
            entry.update({'tail_ms': round(len(tail) / SR_OUT * 1000), 'tail_peak_db': round(db(np.abs(tail).max()), 1)})
            # reconstruction check: close + tail against the prepared original, same gain
            recon = np.zeros_like(tail); recon[: len(close)] += close; recon += tail
            ref = y * gain
            nf = int(TAIL_FADE * SR_OUT); ref[-nf:] *= np.linspace(1, 0, nf)[:, None] ** 2
            err = db(np.sqrt(((recon[:int(0.5*SR_OUT)] - ref[:int(0.5*SR_OUT)]) ** 2).mean())) - db(np.sqrt((ref[:int(0.5*SR_OUT)] ** 2).mean()))
            entry['recon_error_db'] = round(err, 1)
        report[f'close_{cls}{suffix}'] = entry
        print(cls, suffix or '_01', entry)
json.dump(report, open(f'{OUT}/metrics.json', 'w'), indent=1)
