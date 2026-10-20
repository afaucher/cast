"""Renders the dispatch headset voice: one Ogg Vorbis clip per banner line (mono, 22050 Hz).

Run through tools/render_dispatch.ps1 (which lists the lines from the game's own constants first), or by hand:

    python -I tools/render_dispatch.py --lines lines.json --out assets/audio/dispatch \
        --tts-exe <sherpa-onnx-offline-tts.exe> --model <kokoro-multi-lang-v1_0 dir> \
        --kenney assets/audio/third_party/kenney_interface-sounds [--force] [--jobs 4]

lines.json is tools/dispatch_lines.tscn's output: [{"key", "text", "spoken", "kind"}]. For each line the "spoken" text
is read by Kokoro-82M v1.0 (sherpa-onnx; voice af_bella = sid 2, speed 1.1) and run through the "walkie" radio chain:
a narrow, clipped, slightly crushed voice over a hiss bed, a key-down click (Kenney CC0 switch_002) and 70 ms of
carrier hiss before it, a key-up click (switch_003) and a squelch tail after it. Needs ffmpeg (with libvorbis) on PATH
(or CAST_FFMPEG). Clips that already exist are skipped unless --force. Lines whose spoken text is the same ("Gary
(Henchman 1)" and "Gary") are read once and copied.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

SID = 2          # af_bella (its slot in our voice table carries Heart's delivery; see voice_table)
PROSODY_SID = 3  # af_heart: the delivery half of the voice (user, 2026-10-20: reel 11 of the delivery study)
SPEED = 1.1
# Keep the model's own pauses: sherpa's default 0.2 squeezes them to a fifth, the rushed feel (delivery study).
SILENCE_SCALE = 1.0
# voices.bin: voices x 510 length rows x 256 floats; [:128] of a row is timbre, [128:] is delivery (prosody).
VOICE_ROWS = 510
VOICE_DIM = 256
RATE = 22050
FMT = f"aformat=sample_rates={RATE}:channel_layouts=mono"

# The user's pick: "walkie" (docs: the dispatch voice audition, round 3).
VOICE = ("highpass=f=450,highpass=f=450,lowpass=f=2800,lowpass=f=2800,equalizer=f=1400:t=o:w=1:g=10,"
         "volume=10,asoftclip=type=hard,acrusher=bits=8:mix=0.25:mode=lin,"
         "acompressor=threshold=0.15:ratio=10:attack=2:release=60:makeup=1.5,aresample=11025,aresample=22050,volume=0.7")
BAND = "highpass=f=500,lowpass=f=3000"
BED = 0.025
TAIL = 0.16

GRAPH = (
    # the read, its leading and trailing silence trimmed (the model's full pauses stay inside it), 50 ms either side
    f"[0:a]aresample={RATE},{FMT},silenceremove=start_periods=1:start_threshold=-48dB,areverse,"
    "silenceremove=start_periods=1:start_threshold=-48dB,areverse,adelay=50:all=1,apad=pad_dur=0.05,"
    f"{VOICE}[v];"
    f"[1:a]{FMT},{BAND},volume={BED}[bed];"
    "[v][bed]amix=inputs=2:duration=first:normalize=0[vn];"
    # key down: a plastic switch, trimmed to its snap, a bit dulled
    f"[2:a]{FMT},silenceremove=start_periods=1:start_threshold=-50dB,atrim=0:0.07,afade=t=out:st=0.03:d=0.04,"
    "highpass=f=200,lowpass=f=6000,volume=0.09[k1];"
    # the carrier opening: 70 ms of the hiss bed before the voice
    f"[3:a]{FMT},{BAND},volume={BED * 1.6},afade=t=in:d=0.02[pre];"
    # key up: the other switch, then the squelch tail (a short bright hiss burst that dies off)
    f"[4:a]{FMT},silenceremove=start_periods=1:start_threshold=-50dB,atrim=0:0.06,afade=t=out:st=0.025:d=0.035,"
    "highpass=f=200,lowpass=f=6000,volume=0.08[k2];"
    f"[5:a]{FMT},highpass=f=900,lowpass=f=5000,afade=t=in:d=0.004,afade=t=out:st=0.01:d=0.2:curve=exp,volume={TAIL}[tail];"
    "[k1][pre][vn][k2][tail]concat=n=5:v=0:a=1,alimiter=limit=0.9"
)


def voice_table(mdir, dst):
    """The model's voices.bin with af_bella's delivery half swapped for af_heart's (pure Python, no numpy)."""
    from array import array
    v = array("f")
    with open(os.path.join(mdir, "voices.bin"), "rb") as fh:
        v.frombytes(fh.read())
    per = VOICE_ROWS * VOICE_DIM
    half = VOICE_DIM // 2
    for r in range(VOICE_ROWS):
        to = SID * per + r * VOICE_DIM + half
        src = PROSODY_SID * per + r * VOICE_DIM + half
        v[to:to + half] = v[src:src + half]
    with open(dst, "wb") as fh:
        v.tofile(fh)
    return dst


def tts(exe, mdir, text, path, threads, voices):
    cmd = [exe,
           f"--kokoro-model={mdir}/model.onnx", f"--kokoro-voices={voices}",
           f"--kokoro-tokens={mdir}/tokens.txt", f"--kokoro-data-dir={mdir}/espeak-ng-data",
           f"--kokoro-lexicon={mdir}/lexicon-us-en.txt,{mdir}/lexicon-zh.txt",
           f"--sid={SID}", f"--speed={SPEED}", f"--tts-silence-scale={SILENCE_SCALE}", f"--num-threads={threads}",
           f"--output-filename={path}", text]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if not os.path.exists(path):
        raise RuntimeError("tts failed for %r: %s" % (text, r.stderr[-600:]))


def radio(ffmpeg, kenney, src, dst):
    cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", src,
           "-f", "lavfi", "-t", "30", "-i", f"anoisesrc=c=pink:a=1:r={RATE}:seed=1",
           "-i", os.path.join(kenney, "switch_002.ogg"),
           "-f", "lavfi", "-t", "0.07", "-i", f"anoisesrc=c=pink:a=1:r={RATE}:seed=3",
           "-i", os.path.join(kenney, "switch_003.ogg"),
           "-f", "lavfi", "-t", "0.22", "-i", f"anoisesrc=c=white:a=1:r={RATE}:seed=5",
           "-filter_complex", GRAPH, "-ar", str(RATE), "-ac", "1", "-c:a", "libvorbis", "-q:a", "4", "-f", "ogg", dst]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lines", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tts-exe", default=os.environ.get("CAST_KOKORO_EXE", ""))
    ap.add_argument("--model", default=os.environ.get("CAST_KOKORO_MODEL", ""))
    ap.add_argument("--kenney", required=True)
    ap.add_argument("--ffmpeg", default=os.environ.get("CAST_FFMPEG", "") or shutil.which("ffmpeg") or "")
    # Parallel by default: half the logical CPUs as Kokoro processes, each with the CPUs left over as its own threads.
    ap.add_argument("--jobs", type=int, default=int(os.environ.get("CAST_DISPATCH_JOBS", "0")) or max(1, (os.cpu_count() or 4) // 2))
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--prune", action="store_true", help="delete clips (and their .import) for lines the game no longer has")
    a = ap.parse_args()
    for what, val in (("--tts-exe / CAST_KOKORO_EXE", a.tts_exe), ("--model / CAST_KOKORO_MODEL", a.model),
                      ("ffmpeg (PATH or CAST_FFMPEG)", a.ffmpeg)):
        if not val:
            sys.exit("missing " + what)
    for p in (a.tts_exe, a.model, a.kenney, a.lines):
        if not os.path.exists(p):
            sys.exit("not found: " + p)
    for f in ("switch_002.ogg", "switch_003.ogg"):
        if not os.path.exists(os.path.join(a.kenney, f)):
            sys.exit("not found: %s (copy assets/audio/third_party/ from a checkout that has it)" % os.path.join(a.kenney, f))

    with open(a.lines, encoding="utf-8") as fh:
        lines = json.load(fh)
    os.makedirs(a.out, exist_ok=True)
    if a.prune:
        wanted = {ln["key"] + ".ogg" for ln in lines}
        pruned = 0
        for f in os.listdir(a.out):
            if f.endswith(".ogg") and f not in wanted:
                for g in (f, f + ".import"):
                    if os.path.exists(os.path.join(a.out, g)):
                        os.remove(os.path.join(a.out, g))
                pruned += 1
        print("pruned %d clips the game no longer uses" % pruned)
    todo = {}      # spoken text -> [keys still to write]
    skipped = 0
    for ln in lines:
        dst = os.path.join(a.out, ln["key"] + ".ogg")
        if os.path.exists(dst) and not a.force:
            skipped += 1
            continue
        todo.setdefault(ln["spoken"], []).append(ln["key"])
    print("%d lines, %d clips already there, %d to read (%d distinct texts), %d jobs" % (
        len(lines), skipped, sum(len(v) for v in todo.values()), len(todo), a.jobs))
    if not todo:
        return
    started = time.time()
    threads = max(1, (os.cpu_count() or 4) // max(1, a.jobs))
    with tempfile.TemporaryDirectory() as tmp:
        voices = voice_table(a.model, os.path.join(tmp, "voices_cast.bin"))
        def work(item):
            idx, (text, keys) = item
            raw = os.path.join(tmp, "raw_%d.wav" % idx)
            tts(a.tts_exe, a.model, text, raw, threads, voices)
            first = os.path.join(a.out, keys[0] + ".ogg")
            part = first + ".part"
            radio(a.ffmpeg, a.kenney, raw, part)
            os.replace(part, first)
            for k in keys[1:]:
                shutil.copyfile(first, os.path.join(a.out, k + ".ogg"))
            os.remove(raw)
            return len(keys)

        done = 0
        with ThreadPoolExecutor(max_workers=a.jobs) as ex:
            for n in ex.map(work, enumerate(todo.items())):
                done += n
                if done % 20 < n:
                    print("  %d clips (%.0f s)" % (done, time.time() - started), flush=True)
    print("rendered %d clips in %.0f s -> %s" % (done, time.time() - started, a.out))


if __name__ == "__main__":
    main()
