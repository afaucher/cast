# Speech latency: staggered recognizer streams vs. flushing at end of voice

*Research note, 2026-10-17. The prototype bench lived in `tools/stt_stagger/`, and its raw
CSVs and logs in `tools/stt_stagger/results/`; both were removed in 04c4eb4 (docs/history/removed-code.md:
`git checkout 04c4eb4^ -- tools/stt_stagger` brings them back for the commands below). The voice clips are local only.
**Status: the flush is built into the game.** See "8. As built". Sections 1–7 describe the
pre-flush pipeline they measured.*

## TL;DR

- **The idea under test:** run N copies of the streaming recognizer on the same audio, with
  their 320 ms chunk grids staggered by 320/N ms, and act on whichever stream casts first.
- **It works exactly as theory predicts, but it attacks the smaller part of the delay.**
  Measured on the TTS clips at real-time pacing, end of voice to cast:
  - N = 1: mean 771 ms;
  - N = 2: mean 699 ms (−72 ms);
  - N = 3: mean 669 ms (−102 ms).
  - Each extra stream costs about 0.3 CPU cores.
  - Accuracy is unchanged or slightly better (a race across streams also recovers some
    phase-dependent misses).
- **Most of the latency is not the chunk wait.** It is the model's *emission delay*:
  - The zipformer only commits the last word after it has seen roughly 0.35 s (up to
    0.6 s) of audio *after* that word.
  - Per stream, about 360 ms of the ~770 ms is that delay. Then come 148 ms of fixed encoder
    right context, 80 ms of gate lookahead, a 0–320 ms chunk wait (mean 160 ms) and 14 ms
    of compute.
- **"Flush at end of voice" removes nearly all of it, with no second stream and no C++
  change.** When the raw mic has been quiet for 100 ms after a voice run:
  - push the gate's 80 ms delay line plus ~1–1.4 s of comfort noise into the recognizer
    immediately;
  - then drop the same amount of later gate output while the player stays quiet.

  Results:
  - Clean and fast-rate clips: mean **771 → 154 ms**, p50 756 → 154, p90 1030 → 171 ms.
  - Hesitation and sloppy clips: mean 689 → 155 ms.
  - Accuracy is unchanged (94–95% vs 95% at the same phases).
  - CPU is unchanged.
- **Recommendation:** do not build staggered streams. Implement flush-on-voice-end in
  `SpeechGate`/`VoiceCaster` (GDScript only). It cuts perceived latency by about 0.6 s,
  about 6× what N = 3 staggering buys. Then retune the Incantation gap timings, which were
  calibrated on the lagged recognition times, and verify on real mics.
  - Stacking a stagger on top of the flush is worth about 5 ms (simulated). Not worth the
    CPU or the merge logic.

## 1. How the recognizer actually decodes

Sources:
- `../Hero-Reader/native/hero_listen/src/word_listener.cpp`
- the encoder's ONNX metadata, read directly from the model file

**Model metadata:**
- `decode_chunk_len = 32` feature frames. At 10 ms per frame, that is **a 320 ms chunk**
  ("chunk-16" counts 50 Hz frames after the first 2× subsampling).
- `T = 45` frames per encoder call.
- So each call sees **13 frames (130 ms) of right context** beyond its chunk, plus the
  25 ms fbank window.
- `left_context_len = 128,64,32,16,32,64` per stack.

**How WordListener feeds it:**
- A worker thread takes whatever audio is queued.
- It feeds the audio in 20 ms steps and runs `Decode` whenever `IsReady`. That happens
  only when `processed + 45 < frames_ready`, i.e. once per 320 ms of audio.
- After each step it reads the partial result and emits a `hypothesis` event when the
  text changed.
- Endpointing:
  - `rule2_min_trailing_silence = 0.3 s` (sherpa-onnx's default is 1.2 s; Cast already
    uses 0.3).
  - rule1 2.4 s, rule3 20 s.
- An endpoint emits the final and calls `OnlineStreamReset`. That keeps the frame
  counter and encoder state, so **the chunk phase is fixed from stream creation**: at
  `new_stream()` on `reset()` or a hotword change.
- The main thread receives events in `poll()`, once per frame.

**Decode grid:**
- Decode n is ready when the stream holds `7480 + 5120·n` samples, i.e. 467.5 ms + 320 ms·n.
- It covers audio up to 320·(n+1) ms. So it lags its own chunk end by 147.5 ms.
- Verified: in every run, 1,500+ hypothesis events arrived 13–21 ms after the stream crossed
  a grid point (p50 14 ms). They arrive at no other time.

**What the grammar waits for (Incantation):**
- An exact match (q ≥ 0.95) fires on the *first partial* that contains it. No endpoint
  wait.
- Only these wait for the final, i.e. the endpoint (+0.3 s of decoded silence):
  - near misses and aliases ("HEADACLES", "CASTOOTH" → "ooth");
  - bare/mention casts;
  - "fire" waiting for "ball".

  In the bench those are the 1.0–1.3 s outliers.

## 2. Latency breakdown (one stream, today's pipeline)

**Setup:**
- 30 clips (clean + rate groups) × 12 chunk phases (0 to 293 ms in 26.7 ms steps) = 360
  plays.
- Real-time mic pacing: each 20 ms buffer is pushed when its last sample would have been
  recorded. Events are polled every ~1 ms.
- Latency = cast wall time − the last sample with |x| > 0.02 (the same voice-end rule as
  `tests/test_voice_audio.gd`).

**Result:** median **756 ms**, p90 **1030 ms**, mean **771 ms**.

| Component | ms | How we know |
|---|---:|---|
| Mic buffer (20 ms buffers) | ~10 | bench pacing. The game pumps the mic once per frame: about +8 ms average at 60 fps |
| Gate lookahead (`SpeechGate.LOOKAHEAD_SEC`) | 80 | fixed: the gate's output is delayed 80 ms |
| Encoder right context (T − chunk = 13 frames + fbank) | 148 | decode grid above (467.5 − 320) |
| **Chunk quantization** (word end → next grid point) | **0–320, mean ~160** | Each clip's latency swings by 300 ms across the 12 phases (e.g. clean heal 616–918 ms, teeth 814–1114 ms). Staggering removes 72/102 ms at N = 2/3; theory says 80/107. |
| **Model emission delay** (how much post-word audio the model needs before emitting the last token) | **~360** (≈ 771 − the rest) | The verbose trace shows the ladder lagging the audio: "CAST" appears 200 ms *after the whole phrase ended*. Pushing 640 ms of padding did not help; 800–1000 ms did. Matches the ~370 ms mean delay that Kang et al. report for transducers trained without a delay penalty. Ours was not trained with one. |
| Decode compute | 14 | grid residual above (2 threads, int8) |
| Main-thread poll | ~1 (bench) / ~8 (60 fps) | |
| Endpoint rules | 0 for exact casts | Finals arrive ~1.1 s after voice end. They gate only alias and near-miss casts. |
| Grammar waits | ~0 | "fire"→"ball" resolves in the same or next chunk. Fireball (693 ms) is not slower than the others. |

**Per spell (p50, ms):**

| | ms |
|---|---:|
| tentacles | 611 |
| fireball | 693 |
| corn | 722 |
| armor | 756 |
| heal | 757 |
| teeth | 903 |

"teeth" ends in a weak fricative, and the model sits on it longest.

**About the 362–479 ms "live" figure:**
- VoiceCaster's logged `latency_ms` is measured from `_last_voice_clock`. That clock keeps
  updating while `WordListener.is_hearing_voice()` is true, which is:
  - 150 ms after the last voiced block,
  - on gate output that is already 80 ms late.
- So **the logged number understates true end-of-voice → cast by roughly 230 ms.** Live
  362–479 ms corresponds to about 0.6–0.7 s real, in line with this bench.
- The test suite's real-time table (`test_logs/test_voice_audio.log`: median 805 ms, each
  clip at one fixed phase) agrees.
- If latency is going to be tuned, the logged metric should be measured from the gate's own
  undelayed end-of-voice instead.

## 3. Staggered streams: results

**How the bench builds each stream:**
- Each stream is a full `VoiceCaster` (`BenchCaster` in `tools/stt_stagger/stagger_bench.gd`)
  fed the same 20 ms buffers.
- Stream k first gets `k·320/N` ms of comfort noise, which shifts its decode grid by that
  much.

**Merge rule simulated:**
- The first cast from any stream wins.
- The same spell from another stream within 1 s is a duplicate.
- A different spell from another stream on the same clip is a conflict.

**Simulation:** the one-stream 12-phase sweep also gives an ideal, contention-free
simulation of N streams: take the earliest correct cast among phases 320/N apart.

| Config | p50 | p90 | mean | correct (per stream → merged) | process CPU (cores, mean) | main-thread probe p50 / p99 | push + poll per 20 ms |
|---|---:|---:|---:|---|---:|---|---:|
| N = 1 (today) | 756 | 1030 | 771 | 95.0% | 0.37 | 1.24 / 1.59 ms | 66 µs |
| N = 2 measured | 673 | 955 | 699 | 94.4% → **96.1%** | 0.69 | 1.25 / 1.60 ms | 100 µs |
| N = 2 simulated | 672 | 953 | 694 | → 96.1% | | | |
| N = 3 measured | 647 | 950 | 669 | 94–95% → **96.7%** | 0.98 | 1.25 / 1.58 ms | 131 µs |
| N = 3 simulated | 645 | 950 | 666 | → 96.7% | | | |
| N = 4 simulated | 630 | 874 | 652 | → 96.7% | | | |
| hesitate + sloppy, N = 1 | 689 | 954 | 689 | 94.4% | 0.38 | | |
| hesitate + sloppy, N = 2 | 636 | 832 | 604 | 94.4% → 96.3% | 0.78 | | |

**What the table shows:**
- **Latency gain:** measured within 5 ms of the simulation, so there was no CPU contention
  on this 32-thread machine. Expected value: the mean chunk wait drops from ~160 ms to
  ~160/N, i.e. **−80 ms at N = 2 and −107 ms at N = 3**. Perceived end-to-end latency:
  ~770 → ~690 → ~665 ms.
- **Accuracy:**
  - Streams at different phases do hear different things on edge clips. Fast "cast
    tentacles" (+3) is "HEADAGLES" (a miss) at 3 of 12 phases. Fast "cast teeth" misses at
    2 of 12. Slow "cast corn" is "CA | CAST COR" at 1 of 12.
  - The race recovers those, because a miss on one stream is usually a hit on another.
  - In 354 merged plays (N = 2 and 3, all four groups) there were **0 wrong-first casts and 0 conflicts**. Every stream that
    cast picked the same spell.
  - Without cross-stream dedupe, *every* cast would fire N times. Each stream cast exactly
    once per clip.
- **Hotwords:** boosting is per stream (same word list, same context graph) and behaved
  identically. No stream produced a spell another did not.
- **CPU:**
  - The worker's own busy time is RTF 0.039 per stream (about 14 ms per 320 ms chunk), yet
    process CPU grows by ~0.31 cores per stream.
  - The likely cause is onnxruntime's intra-op threads spin-waiting between the 2-thread
    decodes. That is not verified with a profiler.
  - The main thread is unaffected: a fixed workload timed per step was 1.24 ms p50 in every
    configuration, including no recognizer. push + poll grows ~33 µs per stream.
  - On a 4-core laptop, 0.3 cores per stream is a real cost. On this machine it is
    invisible.

**What a production stagger would need:**
- **Native change: phase control.** `WordListener` silently recreates its stream when
  hotwords change (`hotwords_stale_` → `new_stream()` at an arbitrary sample). That resets
  the phase, so the streams can drift back into alignment.
  - A real implementation needs WordListener to expose its stream sample count, or accept a
    "pre-pad on new stream" option.
  - This is a Hero-Reader C++ change; it is described here, not made.
- **One gate feeding N listeners** (not N gates):
  - Stream A is authoritative for subtitles (`heard`), finals, fizzles, the voice log and
    alias/near-miss casts.
  - Streams B… may only fire **exact (q ≥ early_min_q) partial casts**.
- **A shared per-utterance lockout:**
  - A cast of spell S from any stream marks S spent until every stream has emitted a final,
    or for `repeat_lockout` (1 s).
  - Late copies from other streams are dropped silently, not reported as `ignored`.
  - Never show B's partials: they flip-flop against A's.
- **"Second stream only while the gate is open":**
  - It is possible. A fresh stream started at gate-open has a random phase relative to the
    word end, so the average gain is the same.
  - It still needs the gate's 80 ms pre-roll and a lead-in, and it adds stream-creation
    cost at every utterance.
  - Moot given the flush result below.

## 4. Flush at end of voice: results

**Prototype** (`BenchCaster._flush_now`):
- The raw (undelayed) input is watched in 10 ms frames.
  - A voice run uses the gate's own loud rule.
  - The *end* uses a softer rule: a frame still counts as voice if it is within 6 dB
    (`--soft-db`) of the gate's voice level.
- After `Q` ms with no such frame:
  1. hand the recognizer the gate's 80 ms delay line (the real tail);
  2. then F ms of comfort noise;
  3. then drop that many samples of later gate output while the input stays quiet.
- The first loud frame cancels the remaining drop. The real onset is safe in the gate's
  80 ms delay line, so the player's next word is never cut; it just follows an inserted
  pause.

| Config (clean + rate, 4 phases = 120 plays unless noted) | p50 | p90 | mean | correct | CPU cores |
|---|---:|---:|---:|---|---:|
| Baseline at the same 4 phases | 750 | 1030 | 769 | 95.0% | 0.37 |
| F = 640 ms, Q = 100 (first try) | no gain | | | | |
| F = 700 / 800 / 1000 / 1200, clean only, 2 phases | 155 / 146 / 142 / 142 | 896 / 160 / 157 / 155 | 303 / 176 / 137 / 137 | 100% | 0.33–0.41 |
| F = 1000, Q = 100, first prototype (gate's loud rule for the end, delay line discarded) | 142 | 159 | 194 | **90.8%** | 0.35 |
| F = 1000, Q = 100, soft 15 dB | 180 | 267 | 212 | 94.2% | 0.35 |
| F = 1000, Q = 100, soft 6 dB | 158 | 183 | 188 | 95.0% | 0.36 |
| **F = 1400, Q = 100, soft 6 dB** | **154** | **171** | **154** | 94.2% (same misses, ± one flaky clip) | 0.31 |
| Hesitate + sloppy, baseline | 689 | 954 | 689 | 94.4% | 0.38 |
| Hesitate + sloppy, F = 1000, Q = 100, soft 6 | 150 | 175 | 155 | 95.4% | 0.34 |
| Hesitate + sloppy, F = 1000, Q = 60, soft 15 | 128 | 248 | 150 | 95.4% | 0.34 |
| Hesitate + sloppy, F = 1400, Q = 100, soft 15 | 167 | 292 | 191 | 95.4% | 0.36 |
| Stagger N = 2 on top of the flush (simulated) | 175 | 246 | 206 (vs 212) | | +0.3 |

**What it showed:**
- **The pad must cover the emission delay, not just the chunk.** At 640 ms it gave nothing;
  at ≥ 800 ms the last word appears almost at once (three or four chunks decoded in a burst,
  27–40 ms).
- **1.4 s also completes the endpoint.** With it, the *final* arrives about 160–185 ms after
  voice end instead of ~1.1 s. That brings alias and near-miss casts ("HEADACLES") in
  with the rest and removes the p90 tail.
- **Do not replace a quiet word ending with padding.**
  - The first prototype detected the end with the gate's loud rule and threw away the real
    80 ms tail.
  - "cast teeth" at rate +3 became "CAST HE" (6 new misses).
  - Keeping the delay line and using the soft end rule fixed it: the miss set is then
    identical to the baseline.
- **Hesitations still work, and some get better.**
  - "cast … tentacles" with a 300 ms pause went from "CA | STE | ACLES" (weak, 0.75) to
    "CA | CAST | TENTACLES" (0.95). "cast uh … heal" went from a miss to a cast at one phase.
  - Slow speech can be flushed mid-word ("CA" final, then "CAST HEEL"). The pending trigger
    and fragment rejoin absorb it, and every such clip still cast.
- **Power shifts a little on hesitations:** mean +0.02, range −0.15 to +0.32.
  - Incantation's `gap_free` (0.9 s) and `window` (1.7 s) were calibrated on *lagged*
    recognition times ("a 0.3 s pause reads as ~1.0 s").
  - With the flush, the trigger word is recognized ~150 ms after it is said, not ~650 ms.
    The trigger → spell gap then tracks the real pause more closely.
  - Re-measure and retune those two numbers (and the "fresh pause" label threshold) after
    adopting the flush.
- **CPU is unchanged.** Each flush decodes ~1–1.4 s of padding in a burst on the worker
  thread (max decode 70–86 ms, off the main thread). The amount of padding per second of
  speech is what the stream would have decoded anyway.

**Remaining latency with the flush (~150 ms):**

| Part | ms |
|---|---:|
| Q (quiet confirmation) | 100 |
| Soft-tail detection plus 10 ms frame and 20 ms buffer granularity | ~20 |
| Burst decode | ~30 |
| Poll | ~1, or ~8 at 60 fps |

- Q = 60 measured fine on these clips (p50 128 ms). That needs real-mic validation:
  plosive closures and creaky voice make 60 ms gaps inside words.
- **Caveat:** TTS clips have digital silence after the voice. In a real room, the soft end
  rule depends on the learned noise floor (`2 × floor` minimum). In a noisy room the flush
  simply fires later or not at all, which falls back to today's behavior.

## 5. Why chunk-16 (left-128)?

**It was never chosen. It was the only export in the archive we downloaded.**

**What the history shows:**
- **The archive itself:** `sherpa-onnx-streaming-zipformer-en-2023-06-26` ships exactly one
  export, `*-chunk-16-left-128.{onnx,int8.onnx}`, made by its
  `export-onnx-zipformer-online.sh` with `--chunk-size 16 --left-context-frames 128`.
  - Hero-Reader's `third_party/manifest.json` pins that tarball.
  - `stt-eval/engines.py` hard-codes `ZIP_SUFFIX = "epoch-99-avg-1-chunk-16-left-128.int8.onnx"`.
- **What Hero-Reader compared** (`docs/stt-evaluation.md`, `stt-eval/results/*`): *models*,
  not chunk sizes.
  - Zipformer 2023-06-26: 320 ms chunk.
  - Zipformer 20M: zipformer1, also 320 ms; "broken in harness".
  - Kroko 2025-08: its metadata says `decode_chunk_len = 128`, i.e. **1.28 s**; p90
    1.3 s, "disqualifying".
  - NeMo fast-conformer 80 ms: p50/p90 521/840 ms, RTF 0.43, no hotwords. Despite the small
    chunk it was slower than the Zipformer, which is consistent with emission delay
    dominating.
  - The GigaSpeech KWS: also chunk-16 (320 ms); 38.5% hits at default thresholds.
  - Offline models behind a VAD.
- **What was tuned:** hotword score, beam, VAD silence, matcher rules.
- **What decided it:** accuracy. The Zipformer won on the first real adult voice (95.5% vs
  Parakeet's 80–85%) and on the child proxy, and it is 68 MB.
- **Latency was measured** (385/652 ms p50/p90 end of word → zap, Speech Commands words) but
  never broken down.
- Hero-Reader did note that "streaming transducers wait for right-context before committing
  to the last word". That is the emission delay quantified above.
- **Git:** 5 commits, all on 2026-10-16. None mentions the chunk; `git log -S chunk-16` finds
  only the initial import.
- **Cast:** inherited the preset unchanged (`hero_speech.gd`: "zipformer-hot at hotword
  score 2 won on real (adult) voice in Hero-Reader"). `voice-mechanic.md` quotes Hero-Reader's
  latency figures.
- **Was a smaller chunk ever evaluated?** No.
  - For this checkpoint, 16 is the *smallest* chunk it was trained on: icefall Zipformer2
    samples chunks from {16, 32, 64, full}.
  - The published WERs are 3.06/7.79 at 320 ms vs 2.84/7.16 at 640 ms. So chunk-16 is the
    low-latency end of what the model supports, not an arbitrary default.

## 6. Prior art (web research, summarized)

**Staggered or overlapping decoders:**
- No paper or project runs phase-shifted copies of a streaming decoder to cut
  chunk-boundary latency.
- The nearest ideas aim at accuracy at chunk edges, not latency:
  - overlapping-chunk inference, e.g. 640 ms chunks with 50% overlap
    ([arXiv 2104.12631](https://arxiv.org/pdf/2104.12631),
    [arXiv 2304.09325](https://arxiv.org/pdf/2304.09325));
  - a shifted-chunk encoder ([arXiv 2203.15206](https://arxiv.org/pdf/2203.15206));
  - time-shifted contextual attention ([arXiv 2502.15158](https://arxiv.org/pdf/2502.15158));
  - two-pass designs, covered below.

**Chunk size vs. accuracy:**
- [icefall LibriSpeech RESULTS.md](https://github.com/k2-fsa/icefall/blob/master/egs/librispeech/ASR/RESULTS.md),
  for our 2023-05-17 streaming Zipformer:
  - 320 ms: 3.06/7.79 WER (greedy);
  - 640 ms: 2.84/7.16.
- No numbers are published below 320 ms.
- The older stateless7 streaming model: 3.17/8.24 at 320 ms vs 2.98/7.67 at 640 ms.

**Smaller-chunk models in sherpa-onnx**
([release list](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models),
[model docs](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html)):
- No English Zipformer is published below 320 ms (2023-06-26, 2023-06-21, 2023-02-21 and
  20M are all chunk-16).
- [NeMo streaming fast-conformer](https://huggingface.co/nvidia/stt_en_fastconformer_hybrid_large_streaming_multi)
  in 80/480/1040 ms variants:
  - ~105 MB int8;
  - RNNT test-other 6.4/5.7/5.4;
  - greedy only, so no hotwords. Hero-Reader measured it slower than ours.
- [Nemotron streaming 0.6B](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b)
  at 80/160 ms:
  - ~464 MB;
  - 2.80/6.01 at 80 ms.
- Re-exporting our checkpoint at chunk 8 is legal (a multiple of the downsampling), but
  untrained. It would cut the mean chunk wait only from 160 to 80 ms, i.e. the same as
  N = 2, and leaves the emission delay untouched.

**Dynamic chunk training:**
- [WeNet U2/U2++](https://arxiv.org/pdf/2102.01547) and
  [icefall Zipformer2](https://github.com/k2-fsa/icefall/blob/master/egs/librispeech/ASR/zipformer/zipformer.py)
  sample a random chunk per batch, so one model decodes at any *trained* size.
- WeNet's AISHELL CER rises gently as chunks shrink: 6.05/6.28/6.62 at 640/320/160 ms.

**Tail padding and finalization in sherpa-onnx:**
- `InputFinished()` only flushes the fbank extractor
  ([features.cc](https://github.com/k2-fsa/sherpa-onnx/blob/master/sherpa-onnx/csrc/features.cc)).
- The official examples append ~0.66 s of zeros first
  ([online-decode-files.py](https://github.com/k2-fsa/sherpa-onnx/blob/master/python-api-examples/online-decode-files.py)).
  That is the same "flush" measured here, applied at end of file.
- Endpoint defaults are rule1 2.4 s, rule2 1.2 s, rule3 20 s
  ([endpoint.h](https://github.com/k2-fsa/sherpa-onnx/blob/master/sherpa-onnx/csrc/endpoint.h)).
  Ours is already 0.3 s.
- WordListener's own `flush()` pads 0.6 s of *zeros*. That is too short for the emission
  delay, and digital silence is what makes this model invent "HE"/"AND" (see
  `SpeechGate`). Pad with comfort noise instead.

**Keyword spotting:**
- sherpa-onnx's [KeywordSpotter](https://k2-fsa.github.io/sherpa/onnx/kws/index.html) is a
  3.3M-parameter streaming Zipformer. It searches only a keyword graph, with per-keyword
  boost and threshold.
- [icefall's GigaSpeech KWS results](https://github.com/k2-fsa/icefall/blob/master/egs/gigaspeech/KWS/RESULTS.md):
  86% recall at 0.025 false alarms per hour on 20 commands, or 98.7% after fine-tuning.
- The shipped model is also chunk-16. Hero-Reader measured 38.5% hits at default
  thresholds, with p50 331 ms.
- It suits a fixed command set such as "cast heal" and is very cheap. But it has the same
  320 ms chunk, would need threshold tuning against chatter, and loses the open transcript
  Cast uses for fizzles, subtitles and the accidental-cast label.
- The flush works for it too.

**Emission-delay regularization:**
- [FastEmit](https://arxiv.org/pdf/2010.11148) (Google): 150–300 ms lower latency on Voice
  Search, and a better WER on LibriSpeech.
- The [delay-penalized transducer](https://arxiv.org/abs/2211.00490) (k2/icefall):
  - mean delay 373 → 213 → 102 ms at λ = 0.0015/0.003;
  - WER 3.40/8.66 → 3.42/9.01 → 3.70/9.35.
- The icefall recipe behind our model was **not** trained with a delay penalty.
- Fine-tuning with one is the "real" fix for the emission delay, but it is a training job.
  The flush gets the same effect at end of voice for free.

**Commercial systems:**
- Google folds endpointing into the model with an end-of-query token. That more than halved
  latency
  ([Joint endpointing and decoding](https://research.google/pubs/joint-endpointing-and-decoding-with-end-to-end-models/)),
  and penalizing early or late end tokens cut another ~130 ms p90
  ([arXiv 2004.11544](https://arxiv.org/pdf/2004.11544.pdf)).
- Alexa runs a speculative endpointer about 200 ms before the final one so downstream work
  starts early
  ([Amazon Science](https://amazon.science/blog/on-device-speech-processing-makes-alexa-faster-lower-bandwidth)).
- Picovoice Rhino maps speech straight to intents in a fixed grammar
  ([blog](https://picovoice.ai/blog/end-to-end-intent-inference-from-speech/)).
- The common pattern is the one this note lands on:
  - restrict the vocabulary;
  - decide early that speech has ended, speculatively, and confirm later;
  - act on a matching partial.

## 7. Recommendation

1. **Implement flush-on-voice-end** (GDScript only; no WordListener change needed).
   - **`SpeechGate`:**
     - track the raw end of voice with a soft rule (6 dB below the voice level, ≥ 2× the
       floor);
     - after `Q` = 100 ms quiet, return its delay line plus ~1.4 s of comfort noise;
     - drop the matching amount of later output until the first loud frame.
   - **`VoiceCaster`:** pushes that block straight to the listener. Keep `_advance` on raw
     samples, so the audio clock and the Incantation timings stay real time.
   - **Expected:** perceived end-of-voice → cast drops from ~0.75 s (p90 ~1.0 s) to
     **~0.15 s (p90 ~0.17–0.18 s)** on the TTS clips. Finals and alias casts also arrive
     at ~0.17 s instead of ~1.1 s.
   - **Accuracy:** unchanged on 228 clip plays across clean, rate, hesitate and sloppy.
   - **CPU:** unchanged.
2. **Retune Incantation's `gap_free` / `window` / fresh-pause threshold** with the flush on.
   The trigger → spell gaps shrink toward the real pause.
3. **Fix the logged `latency_ms`.** Measure from the gate's undelayed end of voice, not from
   `is_hearing_voice()`, which runs ~230 ms late. Then real-mic logs can confirm the gain.
4. **Validate on real mics before shipping.**
   - Q = 100 vs 60 against plosives and slow speakers.
   - Noisy rooms: the soft rule must still find the end.
   - Speakers who pause mid-incantation: check the inserted pause does not hurt.
5. **Do not build staggered streams.** Alone, they are worth −80 ms (N = 2) or −107 ms
   (N = 3) at ~0.3 cores per stream and need a native phase-control change plus
   cross-stream dedupe. On top of the flush they are worth ~5 ms.
   - If the flush is ever rejected, N = 2 restricted to exact partial casts, with stream A
     authoritative, is a safe second choice.
6. **Longer term**, only if the 150 ms floor matters:
   - a delay-penalty fine-tune of the same checkpoint (helps mid-utterance partials too);
   - or a chunk-8 re-export (untrained size). Each needs icefall/PyTorch tooling, not C++.

## 8. As built (2026-10-17)

Recommendations 1–3 are in the game. No C++ changed.

**`scripts/voice/speech_gate.gd`: flush on voice end.**
- **End of voice:**
  - The gate watches the raw (undelayed) frames.
  - A span starts with the existing voice rule (`MIN_RUN` loud frames).
  - Each frame above max(floor × `FLUSH_FLOOR_RATIO` (3), min voice − `flush_soft_db` (6 dB))
    extends the span and moves `voice_end_sample`.
- **The flush:** after `flush_quiet_sec` (0.1 s) without such a frame, `process()` returns, at
  once:
  - the delay line, through the same `_emit` pass/cut rule as normal output;
  - then `flush_pad_sec` (1.4 s) of cached comfort noise.
- **Paying it back:** the same amount of later output is dropped until the first loud frame.
- **Tunables:** `flush_on_end`, `flush_quiet_sec`, `flush_soft_db`, `flush_pad_sec` are
  per-instance vars. `describe()` (the debug panel's gate line) shows "end flushes N (quiet
  100 ms, pad 1.4 s)".
- **Mic stall:**
  - Repeat-guard frames never count as voice.
  - When `is_stale`, a span is cut without a flush.
  - The padding never passes through the fingerprinting, which only sees input.
  - `test_mic_stall` checks that live speech flushes, that the padding is never taken for a
    repeat, and that a replay starts no new flushes.

**`scripts/voice/voice_caster.gd`: `latency_ms` from the true end of voice.**
- After each `gate.process`, `_note_voice_end` maps `gate.voice_end_sample` onto the audio clock.
- `is_hearing_voice()` is only the fallback when the gate is disabled.

**`scripts/voice/incantation.gd`: `gap_free` 0.9 → 1.0 s, `window` 1.7 → 1.8 s** (see the POWER
comment).
- Fluent trigger → spell gaps fell from 0.3–0.65 s to 0.04–0.54 s.
- A pause now reads as pause + spell word, e.g. 0.8 s → 1.1–1.45 s.
- The new values put every TTS cast back at its old power: the hesitations are within ~0.06,
  except b800 "teeth" (+0.16) and b300 "tentacles". The latter is now heard correctly ("CAST
  TENTACLES" instead of "CA STE ACLES"), so it went 0.75 → 1.00.
- `fresh_pause_s` (0.9) was left alone. Mid-sentence `pause_before` values measured the same
  (0.32–0.34 s) with and without the flush.

**Tests:**
- `test_voice_gate`: new cases 7–10. They cover:
  - the flush and payback;
  - a pause with a second word;
  - a soft ending;
  - flush off.
- `test_mic_stall`: the flush checks above.
- `test_voice_audio`: the real-time table now plays all 12 clean clips and prints both
  measures. It asserts that the median is under 300 ms and that the game metric is within 80 ms
  of the waveform measure.

**Before and after (suite runs; "before" is the 13:45 run on the pre-flush code):**

| `tests/test_voice_audio.gd` | Before | After |
|---|---:|---:|
| Real-time end of voice → cast, clean clips (median) | 805 ms (6 clips) | **166 ms** (p90 178 ms, 12 clips) |
| Game `latency_ms` median, same clips | (~230 ms under the truth) | 150 ms (agrees within 16 ms) |
| Loose table latency at 4× feeding (median, 138 clips) | 846 ms | 265 ms |
| Chaos table latency at 4× (median) | 1142 ms | 309 ms |
| Outcomes (cast / miss / false fire / wrong spell) over 223 clip × mode runs | | **identical**: 0 false fires, 0 confusions, same 2 stress soft misses |
| Accidental labels | | identical |
| Power changes | | 14 runs, all small: fireball 0.96 → 1.00 (gap no longer penalized), hesitations as above |
| `test_voice_triggers` (8 triggers) | cast 8/8 … abracadabra 2/8 | same hit rates; average power ±0.01 |
| `test_voice_noise` | 0 phantoms through the gate | 0 phantoms, 0 flushes on idle noise |

**Full suite:** `.\test_runner.ps1 -TestAll` reports **"All 55 test(s) passed."**

**Still to check on a live mic:**
- **Noisy room:** the end rule needs ~100 ms below max(3 × floor, min voice − 6 dB). Background
  that sits just under that delays or skips the flush. That falls back to the old ~0.8 s; it
  never loses a cast. Look at "end flushes N" on the debug panel's gate line; it should count up
  once per phrase.
- **Slow or plosive speakers:** 100 ms gaps inside a word can flush mid-word. This was absorbed on
  every TTS clip.
- **Players who keep talking right after a cast:** they get an inserted pause, which is
  harmless in tests.
- **Logged latency:** check that the voice log's `lat=` now reads ~150–250 ms.

## Reproduce

```powershell
# one configuration (prints CPU, decode-grid residuals, main-thread probe)
.\tools\stt_stagger\run_bench.ps1 -Streams 2 -Phases 6
.\tools\stt_stagger\run_bench.ps1 -Streams 1 -Phases 4 -Flush 1400 -SoftDb 6
# everything in this note (~2 h of real-time audio; keep the machine otherwise idle)
.\tools\stt_stagger\run_all.ps1
python tools\stt_stagger\analyze.py tools\stt_stagger\results\n1-sweep.csv   # tables + N-stream simulation
```

**Notes on the runs:**
- Some runs overlapped other agents' Godot test runs; `run_bench.ps1` warns when that
  happens.
- Decode compute stayed at 14 ms and the measured N = 2/3 results matched the
  contention-free simulation within 5 ms, so the overlap did not move these numbers.
- The `results/` folder has a `.gdignore`. Without it, Godot's importer turns the CSVs into
  translation resources.
