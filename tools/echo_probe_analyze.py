"""Analyse a tools/echo_probe.gd recording: echo delay, level, drift and what a linear canceller could remove.

    python tools/echo_probe_analyze.py <out_dir> [<out_dir> ...]

Lab tool for docs/design/echo-cancellation-research.md (numpy + scipy). Per run it prints:
- the stream offset: how many samples the sweep sits later in the mic stream than in the Master-bus tap (the number an
  AEC's delay line needs), per sweep (GCC-PHAT, 300 Hz-7 kHz, parabolic sub-sample peak), its spread and its drift;
- the round trip in wall-clock ms (each stream's sample index mapped to the time it was read: mix -> speaker -> air ->
  mic -> input buffer -> our read);
- the echo level: the sweep's matched-filter amplitude in the mic relative to the Master tap (dB), and its SNR over the
  mic's own noise;
- ERLE of a least-squares FIR (16 kHz, fitted on the first half, scored on the second): the most a static linear echo
  canceller with that many taps could remove here.
"""
import json
import sys

import numpy as np
from scipy import signal


def sweep(rate, meta):
    m = int(rate * meta["sweep_sec"])
    t = np.arange(m) / rate
    k = np.log(meta["f1"] / meta["f0"])
    ph = 2 * np.pi * meta["f0"] * meta["sweep_sec"] / k * (np.exp(t / meta["sweep_sec"] * k) - 1)
    return np.sin(ph)


def gcc_phat(a, b, rate, max_lag):
    """Lag (samples, float) of b relative to a, and the peak's prominence."""
    n = 1 << int(np.ceil(np.log2(len(a) + len(b))))
    A = np.fft.rfft(a, n)
    B = np.fft.rfft(b, n)
    X = B * np.conj(A)
    f = np.fft.rfftfreq(n, 1 / rate)
    band = (f > 300) & (f < 7000)
    X = np.where(band, X / (np.abs(X) + 1e-12), 0)
    cc = np.fft.irfft(X, n)
    cc = np.concatenate([cc[-max_lag:], cc[: max_lag + 1]])
    i = int(np.argmax(cc))
    frac = 0.0
    if 0 < i < len(cc) - 1:
        y0, y1, y2 = cc[i - 1], cc[i], cc[i + 1]
        d = y0 - 2 * y1 + y2
        frac = 0.5 * (y0 - y2) / d if d != 0 else 0.0
    prominence = cc[i] / (np.median(np.abs(cc)) + 1e-12)
    return i - max_lag + frac, prominence


def read_time(reads, idx, rate):
    """Wall-clock µs at which sample idx became readable (first read whose running count passed it), backed off
    by the samples read after it in that chunk."""
    for t, c in reads:
        if c > idx:
            return t - (c - idx) / rate * 1e6
    return float("nan")


def analyse(d):
    meta = json.load(open(f"{d}/meta.json"))
    rate = int(meta["mix_rate"])
    ref = np.fromfile(f"{d}/ref.f32", dtype=np.float32).astype(np.float64)
    mic = np.fromfile(f"{d}/mic.f32", dtype=np.float32).astype(np.float64)
    tpl = sweep(rate, meta)
    print(f"== {d}")
    print(f"   rate {rate}, Godot output latency {meta['output_latency_s']*1000:.1f} ms, input buffer "
          f"{meta['input_buffer_frames']} frames; ref {len(ref)/rate:.1f} s, mic {len(mic)/rate:.1f} s; "
          f"ref peak {20*np.log10(np.max(np.abs(ref))+1e-12):.1f} dBFS, mic peak {20*np.log10(np.max(np.abs(mic))+1e-12):.1f} dBFS")

    # Sweeps in the reference.
    mf = signal.fftconvolve(ref, tpl[::-1], mode="valid")
    starts = []
    thr = 0.5 * np.max(np.abs(mf))
    i = 0
    while i < len(mf):
        if abs(mf[i]) > thr:
            j = i + int(0.1 * rate)
            k = i + int(np.argmax(np.abs(mf[i:j])))
            starts.append(k)
            i = k + int(0.6 * meta["every_sec"] * rate)
        else:
            i += 1
    # Coarse lag over the whole recording (the two streams start at different times).
    n = min(len(ref), len(mic))
    coarse, prom = gcc_phat(ref[:n], mic[:n], rate, int(1.5 * rate))
    coarse = int(round(coarse))
    print(f"   {len(starts)} sweeps in the reference; whole-recording GCC-PHAT lag {coarse} samples "
          f"({coarse/rate*1000:.1f} ms), prominence {prom:.0f}")

    noise = mic[: int(0.8 * rate)]
    noise_rms = np.sqrt(np.mean(noise ** 2)) + 1e-12
    rows = []
    m = len(tpl)
    for s in starts:
        a0 = s - int(0.02 * rate)
        a = ref[a0 : a0 + m + int(0.04 * rate)]
        b0 = a0 + coarse - int(0.1 * rate)
        b = mic[max(0, b0) : b0 + len(a) + int(0.2 * rate)]
        if len(b) < len(a):
            continue
        lag, pr = gcc_phat(a, b, rate, int(0.15 * rate))
        lag_total = (b0 - a0) + lag
        # Echo level: matched-filter amplitude in mic vs in ref.
        r_amp = np.max(np.abs(np.correlate(ref[s : s + m], tpl, "valid")))
        e0 = s + int(round(lag_total))
        seg = mic[e0 - int(0.01 * rate) : e0 + m + int(0.01 * rate)]
        e_amp = np.max(np.abs(np.correlate(seg, tpl, "valid"))) if len(seg) >= m else np.nan
        echo_db = 20 * np.log10(e_amp / r_amp + 1e-12)
        echo_rms = np.sqrt(np.mean(mic[e0 : e0 + m] ** 2))
        snr = 20 * np.log10(echo_rms / noise_rms)
        rt = (read_time(meta["mic_reads"], e0, rate) - read_time(meta["ref_reads"], s, rate)) / 1000
        rows.append((s / rate, lag_total, pr, echo_db, snr, rt))
    if not rows:
        print("   no sweeps analysed")
        return
    R = np.array(rows)
    good = R[:, 2] > 8
    good &= np.abs(R[:, 1] - np.median(R[good, 1])) < 20   # drop sweeps buried under other sound (talking)
    print("   t(s)   offset(samples)  prom   echo(dB re ref)  SNR(dB)  round trip(ms)")
    for r in R:
        print(f"   {r[0]:5.1f}  {r[1]:12.2f}  {r[2]:6.0f}  {r[3]:10.1f}  {r[4]:8.1f}  {r[5]:9.1f}")
    if good.sum() >= 2:
        G = R[good]
        p = np.polyfit(G[:, 0], G[:, 1], 1)
        print(f"   confident sweeps {good.sum()}/{len(R)}: offset median {np.median(G[:,1]):.2f} samples "
              f"({np.median(G[:,1])/rate*1000:.2f} ms), spread (max-min) {np.ptp(G[:,1]):.2f} samples; drift "
              f"{p[0]:.3f} samples/s = {p[0]/rate*1e6:.1f} ppm; echo {np.median(G[:,3]):.1f} dB re ref; "
              f"SNR {np.median(G[:,4]):.1f} dB; round trip {np.median(G[:,5]):.1f} ms (spread {np.ptp(G[:,5]):.1f})")
        off = int(round(np.median(G[:, 1])))
        lvl(ref, mic, off, rate, starts, m, noise_rms)
        erle(ref, mic, off, rate, starts, m)
        ir_erle(ref, mic, off, rate, starts, meta, G)
        nlms_erle(ref, mic, off, rate, starts, G)
    else:
        print("   no confident echo: the mic did not hear the sweeps (headphones, or a muted/far speaker)")


def erle(ref, mic, off, rate, starts, m):
    """Least-squares FIR from the aligned reference to the mic at 16 kHz; ERLE on held-out sweeps."""
    q = rate // 16000
    r16 = signal.resample_poly(ref, 1, q)
    m16 = signal.resample_poly(mic, 1, q)
    off16 = off // q
    pre = int(0.004 * 16000)   # taps before the estimated delay (a calibration error margin)
    for taps in (256, 1024):
        idx = []
        for s in starts:
            a = s // q + off16
            idx.extend(range(a - 160, a + m // q + 1600))   # the sweep plus 100 ms of tail
        idx = np.array([i for i in idx if i - off16 - pre - taps > 0 and i < len(m16)])
        half = len(idx) // 2
        def X(rows):
            base = rows - off16 + pre
            return np.stack([r16[base - k] for k in range(taps)], axis=1)
        tr, te = idx[:half], idx[half:]
        w, *_ = np.linalg.lstsq(X(tr), m16[tr], rcond=None)
        res = m16[te] - X(te) @ w
        e = 10 * np.log10(np.mean(m16[te] ** 2) / np.mean(res ** 2))
        print(f"   least-squares FIR {taps} taps ({taps/16:.0f} ms) at 16 kHz: ERLE {e:.1f} dB on held-out sweeps")


def lvl(ref, mic, off, rate, starts, m, noise_rms):
    r = np.sqrt(np.mean(np.concatenate([ref[s : s + m] for s in starts]) ** 2))
    e = np.sqrt(np.mean(np.concatenate([mic[s + off : s + off + m] for s in starts]) ** 2))
    print(f"   levels: sweep in the Master tap {20*np.log10(r):.1f} dBFS RMS, echo in the mic {20*np.log10(e):.1f} dBFS RMS "
          f"(echo return loss {20*np.log10(r/e):.1f} dB), mic noise floor {20*np.log10(noise_rms):.1f} dBFS RMS")


def ir_erle(ref, mic, off, rate, starts, meta, G):
    """Echo path impulse response from the sweeps (cross-spectrum / auto-spectrum, first half of the sweeps), then the
    echo it predicts on the second half, truncated to several lengths. Scored in 200 Hz-8 kHz (where the sweep has
    energy). Also the share of the IR's energy inside each length."""
    L = int(min(1.0, 0.9 * meta["every_sec"]) * rate)
    pre = int(0.02 * rate)
    lead = int(0.002 * rate)   # the IR starts 2 ms before the median offset (sweeps scatter around it)
    wins = [(s - pre, s - pre + off - lead) for s in starts if s - pre + off + L < len(mic) and s - pre > 0]
    half = len(wins) // 2
    n = 1 << int(np.ceil(np.log2(2 * L)))
    f = np.fft.rfftfreq(n, 1 / rate)
    band = (f > 200) & (f < 8000)
    num = np.zeros(n // 2 + 1, complex)
    den = np.zeros(n // 2 + 1)
    for a, b in wins[:half]:
        R = np.fft.rfft(ref[a : a + L], n)
        M = np.fft.rfft(mic[b : b + L], n)
        num += M * np.conj(R)
        den += np.abs(R) ** 2
    H = np.where(band, num / (den + 1e-9 * den.max()), 0)
    h = np.fft.irfft(H, n)
    # The echo sits around lag `pre` relative to window start difference: h is causal from 0.
    energy = np.cumsum(h[: int(0.6 * rate)] ** 2)
    tot = energy[-1]
    shares = {ms: energy[min(len(energy) - 1, int(ms / 1000 * rate))] / tot for ms in (8, 16, 32, 64, 128, 256, 500)}
    peak = int(np.argmax(np.abs(h[: int(0.2 * rate)])))
    print("   echo path IR (from the first half): peak at %.1f ms after the stream offset; energy inside: %s" % (
        (peak - lead) / rate * 1000, ", ".join(f"{k} ms {v*100:.0f}%" for k, v in shares.items())))
    sos = signal.butter(4, [200, 8000], btype="band", fs=rate, output="sos")
    out = []
    for ms in (16, 64, 128, 256, 500):
        if ms / 1000 > 0.9 * meta["every_sec"]:
            continue
        k = int(ms / 1000 * rate)
        hk = h[:k]
        num_e = den_e = 0.0
        for a, b in wins[half:]:
            est = signal.fftconvolve(ref[a - k : a + L], hk)[k : k + L]
            y = signal.sosfilt(sos, mic[b : b + L])
            r = y - signal.sosfilt(sos, est)
            num_e += np.sum(y ** 2)
            den_e += np.sum(r ** 2)
        out.append(f"{ms} ms {10*np.log10(num_e/den_e):.1f} dB")
    print("   ERLE of that IR on the held-out sweeps (fixed delay, no adaptation), by length: " + ", ".join(out))
    # Per band, 64 ms IR: with the median delay (what a fixed calibration gives) and with each sweep's own measured
    # delay (an oracle that tracks the delay jumps), to show whether the delay wander is what limits cancellation.
    k = int(0.064 * rate)
    hk = h[:k]
    lags = dict(zip([int(round(t * rate)) for t in G[:, 0]], G[:, 1]))
    bands = [(200, 1000), (1000, 2000), (2000, 4000), (4000, 8000)]
    for oracle in (False, True):
        res = []
        for lo, hi in bands:
            sb = signal.butter(4, [lo, hi], btype="band", fs=rate, output="sos")
            ne = de = 0.0
            for a, b in wins[half:]:
                s0 = a + pre
                shift = 0
                if oracle:
                    near = min(lags, key=lambda x: abs(x - s0))
                    shift = int(round(lags[near] - off))
                bb = b + shift
                if bb + L > len(mic):
                    continue
                est = signal.fftconvolve(ref[a - k : a + L], hk)[k : k + L]
                y = signal.sosfilt(sb, mic[bb : bb + L])
                r = y - signal.sosfilt(sb, est)
                ne += np.sum(y ** 2)
                de += np.sum(r ** 2)
            res.append(f"{lo}-{hi} Hz {10*np.log10(ne/de):.1f} dB")
        print("   64 ms IR, ERLE per band, %s: %s" % ("each sweep at its own measured delay (oracle)" if oracle else
              "one fixed delay", ", ".join(res)))


def nlms_erle(ref, mic, off, rate, starts, G):
    """A plain adaptive canceller run over the whole recording, the way a game-side AEC would see it: 16 kHz, NLMS,
    1024 taps (64 ms) starting 4 ms before the measured offset, adapting only while the reference has signal. ERLE per
    sweep (after 3 s) shows what adaptation reaches with this machine's drift and capture processing."""
    q = rate // 16000
    r16 = signal.resample_poly(ref, 1, q)
    m16 = signal.resample_poly(mic, 1, q)
    taps, pre, mu, eps = 1024, 64, 0.3, 1e-6
    shift = off // q - pre
    t0 = starts[0] // q - 1000
    t1 = min(len(r16), len(m16) - shift) - 1
    w = np.zeros(taps)
    e = np.zeros(t1)
    p_ref = np.convolve(r16 ** 2, np.ones(taps), "full")[: len(r16)]   # running window energy
    keep = {int(round(t * rate)) for t in G[:, 0]}
    for n in range(t0, t1):
        x = r16[n - taps + 1 : n + 1][::-1]
        y = m16[n + shift]
        err = y - w @ x
        e[n] = err
        px = p_ref[n]
        if px > 1e-4:
            w += (mu / (px + eps)) * err * x
    out = []
    for s in starts:
        if s / rate < starts[0] / rate + 3.0 or not any(abs(s - k) < rate * 0.05 for k in keep):
            continue
        a = s // q + shift
        b = a + int(0.35 * 16000)
        n0, n1 = s // q, s // q + int(0.35 * 16000)
        if n1 >= t1:
            continue
        out.append(10 * np.log10(np.sum(m16[a:b] ** 2) / (np.sum(e[n0:n1] ** 2) + 1e-20)))
    if out:
        o = np.array(out)
        print(f"   NLMS 1024 taps at 16 kHz over the recording: ERLE per sweep after 3 s median {np.median(o):.1f} dB, "
              f"min {o.min():.1f}, max {o.max():.1f} ({len(o)} sweeps)")


if __name__ == "__main__":
    for d in sys.argv[1:]:
        analyse(d)
