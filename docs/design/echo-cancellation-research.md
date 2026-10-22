# Echo cancellation: cleaning our own sounds out of the mic

**PARKED (user, 2026-10-22: "Lets park the audio research for now with those open questions").** Nothing more is built
until the open questions are answered: speakers or headphones (and what players will use); re-running the probe with
Voice Clarity / Audio enhancements off on the QuadCast (and whether NVIDIA Broadcast or similar is in the chain); an
optional startup calibration chirp; downloading speexdsp (BSD-3); "Echo cancel" as a player setting or in Diagnostics.
Ducking stays off meanwhile (`Sfx.ducking`).

*[research] 2026-10-22. Nothing in the game changed. Two lab tools were added: `tools/echo_probe.gd` (plays sweeps,
records the Master bus and the mic at once) and `tools/echo_probe_analyze.py` (delay, level, drift, and how much a
linear canceller removes). The user asked: "knowing what we played, can we identify the feedback delay (if any) and use
that to clean the incoming mic input?" The baseline to beat is **ducking** (user: "Ducking was the alternative"), which
exists (`Sfx.ducking`, `duck_db`) and is off (audio-plan.md, "As built").*

## TL;DR

- **Yes, this is acoustic echo cancellation (AEC) with a known reference**, and Godot gives us the reference: an
  `AudioEffectCapture` on the Master bus hands back exactly what the game mixed, sample-accurate. The probe uses it and
  finds every sweep in the mic.
- **The delay is real and needs measuring; Godot's figure is no use.** On this PC the round trip (mix -> speaker -> air
  -> mic -> our read) is **~115 ms**, but `AudioServer.get_output_latency()` says 10 ms.
- **The delay is steady within a session but not between sessions.** In stream-sample terms it held to ±1.6 samples
  within each run, but it was 2161, 2201 and 2328 samples in three runs (a 3.5 ms spread). It will also move when the
  mic watchdog restarts the device. So a startup chirp alone is not enough: the delay has to be tracked live, from the
  game's own sounds. That is what WebRTC AEC3's delay estimator does.
- **The two clocks drift.** The output is the Realtek onboard device and the mic is a USB HyperX QuadCast S. The delay
  creeps ~0.5 samples/s (~10 ppm) and snaps back ~3 samples every ~6 s. An adaptive canceller copes, but it loses some
  cancellation above 2 kHz after each snap.
- **The echo here is moderate.** Game sound at -15 dBFS RMS comes back at about -54 dBFS RMS (an echo return loss of
  ~38-39 dB). A loud full-scale moment would land near -40 dBFS, about at the gate's -42 dBFS voice threshold. (Speakers
  or headphones on the Realtek output: unknown, open question 1.)
- **On this PC a linear canceller would remove only ~8-10 dB.** A simulated NLMS canceller reached median 7.5 and 9.6 dB
  in two runs; a best-case static fit reached 7.9 and 8.2 dB. The cause is not noise (echo-to-noise is 31-54 dB). The
  echo itself changes from sweep to sweep: the mic stream has **exact digital zeros** between sweeps and a noise floor
  that wanders, and Windows has the "VocaEffectPack" effect (Voice Clarity) registered on the QuadCast. Something in
  Windows is already processing the mic nonlinearly, and that caps what any canceller of ours can do. A re-run with
  Windows' mic processing off would show the raw echo path (open question 2).
- **AEC compared with ducking:** AEC works from the first sample of speech and when the player is silent (the dispatch
  "pod**cast**" leak). The game doesn't go quiet, and it costs under 1% CPU (speexdsp). But it needs native code, and
  here it is capped at ~8-10 dB. Ducking is free and already built, but it arrives ~150-200 ms after the voice starts
  (the "ca-" of "cast" is spoken over full game audio), it pumps the mix every time you talk, and it does nothing about
  leaks while you're silent.
- **Recommendation:**
  1. Measure on a real speaker setup with the probe (and with the OS mic processing off).
  2. Build a real-room leak probe that scores the recognizer.
  3. Add speexdsp's AEC (BSD-3) to the `hero_listen` GDExtension, behind a setting, fed from a Master-bus tap, with our
     own delay estimate.
  4. Decide with the leak probe whether AEC alone is enough or a light duck stays for "Speakers" mode.

  WebRTC AEC3 is the stronger engine (it has its own delay and drift handling) but a much heavier build. It is the
  fallback if speexdsp's numbers are short.

## 1. How we capture and play today

**Mic path** (`scripts/voice/voice_caster.gd`, `speech_gate.gd`; `..\Hero-Reader\native\hero_listen\src\word_listener.cpp`):
- The device is Godot's default input. `project.godot` has `audio/driver/enable_input=true`. On this PC it is the
  HyperX QuadCast S (USB), as both the console and the communications default.
- VoiceCaster reads the input device directly, every `_process` frame (`AudioServer.get_input_frames(n)`, the
  experimental 4.5+ API). It does not use `AudioStreamMicrophone`, which replayed its 4 s ring forever when the device
  stalled (the 2026-10-17 playtest). The ring buffer is 192000 frames (4 s at 48 kHz).
- Rates: input mix rate 48 kHz (Godot uses one `mix_rate` for input and output), stereo frames -> mono in
  `SpeechGate.process_frames`.
- **SpeechGate** (GDScript, 10 ms frames at 48 kHz): comfort noise, a learned noise floor, the voice rule (above
  `min_voice_db` -42 dBFS and 7.8 dB over the floor, for at least 50 ms), 80 ms look-ahead, 0.5 s hangover, repeat
  guard, and flush at end of voice. It is also the VAD: `speech_started` and `is_speaking()` come from it.
- **WordListener** (C++, GDExtension): `push_samples(samples, 48000)` -> sherpa-onnx linear resampler to **16 kHz** ->
  a queue -> a worker thread feeds the streaming zipformer in 20 ms steps.
- A watchdog restarts the input device after 1 s without frames, or when the gate sees replayed audio
  (`_restart_mic`).

**Output path** (`default_bus_layout.tres`, `scripts/fx/sfx.gd`, `scripts/ui/dispatch_banner.gd`):
- Buses: Master (HardLimiter -0.5 dB), with SFX (Compressor) -> World and Stings, UI, VoiceFeedback and Music
  (empty) feeding it.
- Cues come from `Sfx` (pools of `AudioStreamPlayer` / `AudioStreamPlayer3D`, pitch jitter, 3D panning). The dispatch
  voice plays on UI. Steam voice chat is not in the game.
- **Everything we play passes through Master**, so one `AudioEffectCapture` on Master is the complete reference: post-3D,
  post-jitter, post-compressor and post-limiter, i.e. what the speaker is actually fed. Per-clip bookkeeping ("which clip
  played when") would have to redo all of that, so the Master tap is both simpler and exact.
- The WASAPI driver opens output through `IAudioClient3` with `AudioCategory_GameEffects`. Input uses a plain
  `IAudioClient` in shared mode with no category, so it gets the default processing mode, not the communications
  mode. Godot reads no device timestamps for input (`drivers/wasapi/audio_driver_wasapi.cpp`).

**Clocks.** There are three:
- the output device's sample clock, which drives Godot's mix and therefore the Master tap;
- the input device's clock (here a separate USB device);
- the game's frame clock, which only decides when we read the two buffers.

Pairing the two streams by sample index (each counted from when it started) is exact on each side. The offset between
them is the "delay" an AEC needs. It drifts with the two crystals.

## 2. Measured on this PC (2026-10-22)

`tools/echo_probe.gd` plays exponential sweeps (200 Hz -> 8 kHz) through the normal output at -12 dBFS peak. At the same
time it records the Master bus (an `AudioEffectCapture`, 2 s buffer) and the mic (as VoiceCaster reads it), with each
read's time. `tools/echo_probe_analyze.py` finds each sweep in both streams and computes:
- the offset, with GCC-PHAT (300 Hz-7 kHz) and a sub-sample peak;
- the echo level;
- the echo path's impulse response;
- the cancellation a static linear filter reaches on held-out sweeps;
- the cancellation an NLMS canceller reaches over the whole recording (16 kHz, 1024 taps = 64 ms).

```
godot --path . --display-driver headless --audio-driver WASAPI --script res://tools/echo_probe.gd -- <dir> [sweeps] [amp] [every_s] [sweep_s]
python tools/echo_probe_analyze.py <dir> [<dir> ...]
```

**Devices** (Windows defaults, read with `IMMDeviceEnumerator`): output (console) Speakers (Realtek(R) Audio), an
analog jack, so speakers or headphones; output (communications) the QuadCast's headphone jack; input (both roles)
Microphone (HyperX QuadCast S). Mix rate 48000 in and out.

| | Run 1 (20 sweeps / 1.5 s) | Run 3 (same, new process) | Run 2 (60 short sweeps / 0.5 s) |
|---|---|---|---|
| Stream offset, median | 2161.5 samples (45.0 ms) | 2328.3 samples (48.5 ms) | 2200.7 samples (45.8 ms) |
| Offset spread within the run | 3.2 samples | 3.2 samples | sawtooth, below |
| Round trip, wall clock (±1 frame) | 114 ms | 116 ms | 113 ms |
| Godot `get_output_latency()` | 10 ms | 10 ms | 10 ms |
| Sweep in Master tap / echo in mic (RMS) | -15.2 / -53.4 dBFS | -15.2 / -54.1 dBFS | (room noise in the last 9 s) |
| Echo return loss | 38.2 dB | 39.0 dB | - |
| Mic noise floor (first 0.8 s) | -87.6 dBFS | -66.1 dBFS | -98.3 dBFS |
| Echo IR energy within 8 / 16 / 32 / 64 ms | 64 / 81 / 92 / 99 % | 61 / 80 / 91 / 99 % | - |
| Static LS filter, 64 ms, held-out ERLE | 7.9 dB | 8.2 dB | - |
| NLMS 64 ms, ERLE per sweep after 3 s | median 7.5 (2.2-12.5) dB | median 9.6 (3.9-13.1) dB | median 5.4 dB (with talking) |

- **Drift (run 2, its clean first 23 s).** The offset climbs steadily: 2198.8 -> 2202.0 samples over 7 s, i.e.
  ~0.47 samples/s ≈ 10 ppm. Then it drops ~3 samples, about every 6 s. Something between the two devices (the Windows
  engine or the USB audio driver) is inserting or dropping samples to keep the streams together. The straight-line fit
  over a whole run shows ~0.5 ppm because the drops cancel the climb.
- **Why the cancellation is low.** Band by band, the coherence between what we played and what came back caps a linear
  canceller at:

  | Band | 200-500 Hz | 500 Hz-1 kHz | 1-2 kHz | 2-4 kHz | 4-8 kHz |
  |---|---|---|---|---|---|
  | Cap | 12.7 dB | 14.5 dB | 5.4 dB | 4.2 dB | 3.1 dB |
  | Echo-to-noise | 31 dB | 37 dB | 43 dB | 51 dB | 54 dB |

  So the limit is not noise: the echo is not the same from one sweep to the next. Re-aligning each sweep by its own
  fractional delay lifts 4-8 kHz to 8.9 dB, but 1-4 kHz stays ~5 dB. Meanwhile, 10 of the 20 gaps between sweeps in
  run 1 were **exact digital zeros**, and the noise floor differed by 30 dB between runs. The mic signal is being gated
  or suppressed before Godot sees it. That matches the SpeechGate note ("mics with noise suppression send zeros"). The
  QuadCast endpoint has Windows' `VocaEffectPack` effect registered (the Voice Clarity package). Whether it, or another
  stage, also runs an echo canceller of its own in default mode is unknown. If it does, the 38 dB return loss is
  already after one.
- **Caveats.** It is one machine and one level. The output may have been headphones. The probe's sweeps are not speech.
  Run 2 picked up loud sound in the room after 23 s (mic peak -3.9 dBFS), and 13 of its 60 sweeps were rejected.

**What it means.**
1. Delay, level and drift can be measured from the game's own audio with a few hundred lines; this needs no chirp.
2. On this setup a linear AEC buys roughly what a 10 dB duck buys.
3. The ceiling is set by whatever Windows does to the mic. A machine with raw capture, or one where it is switched off,
   should do much better; that is to be measured.

## 3. Background (research)

**The problem.** The mic hears `y = s + h*x + n`: s is the player, x is what we played, h is the room and speaker path
(delay plus reverb), and n is noise. An AEC estimates `h` from `x` and `y` and subtracts `ĥ*x`. Because `x` is known
exactly, this is far stronger than generic noise suppression, which has to guess.

**Delay estimation.**
- Cross-correlation finds the bulk delay. Weighting it by the phase transform (GCC-PHAT, Knapp & Carter 1976) whitens
  the spectrum, so the peak is sharp even for colored sounds. It gives integer-sample lags, and interpolation gives
  sub-sample ones (MathWorks `gccphat`; Aalto speech processing book).
- WebRTC AEC3 does the same job continuously. It decimates render and capture, runs a bank of matched filters, and
  aggregates their lags. Once the estimate is "refined" it also feeds a clock-drift detector
  (`echo_path_delay_estimator.cc`). Our probe is a one-shot version of that.

**Linear adaptive filters.**
- NLMS is the textbook time-domain filter. It is cheap per tap, but at 16 kHz a 128 ms tail is 2048 taps per sample.
- Frequency-domain block filters (FDAF) do the convolution with FFTs. The *partitioned* or *multidelay* form (MDF, Soo &
  Pang 1990) splits a long filter into blocks so latency stays at one short frame. Speex's echo canceller (`mdf.c`) is an
  MDF, with Valin's adaptive learning rate that slows adaptation during double-talk.
  - API: `speex_echo_state_init(frame_size, filter_length)`, frame 10-20 ms, filter typically 100-500 ms of tail;
    `speex_echo_cancellation(st, rec, play, out)`.
  - The rule: "any echo present in the input must already have been sent to the echo canceller".
- Speex has no delay estimator. The caller aligns the streams, or makes the filter long enough to cover the bulk delay.

**Residual echo suppression and NLP.**
- A linear filter can't remove nonlinear distortion (small speakers driven hard, clipping) or the part of the echo it
  hasn't converged on. Real AECs follow it with a spectral suppressor: Speex's preprocessor, linked by
  `SPEEX_PREPROCESS_SET_ECHO_STATE`, with defaults of -40 dB and -15 dB during near-end speech; AEC3's suppressor.
- Suppression distorts the near-end speech. The literature on ASR (below) favors feeding the recognizer the *linear*
  output and letting the model, or a mild suppressor, handle the rest. AEC3 exposes this as
  `EchoCanceller.export_linear_aec_output`. Espressif's ESP-SR has a linear-only "speech recognition" AEC mode.

**Double talk.**
- While the player speaks over game audio, the adaptive filter must not adapt on the player's voice, or it diverges.
  Classic detectors compare levels (Geigel: near-end peak against half the far-end peak). Modern filters skip the hard
  freeze: they scale the step size down as near-end energy rises (variable step size).
- Speex's MDF and AEC3 both handle this internally. A home-made NLMS would need it.

**Clock drift.**
- With two devices, the echo's position in the capture stream slides. Standard remedies: estimate the drift, then
  resample the reference (or nudge it a sample at a time, in small steps the filter can follow), and keep buffers from
  under- or overflowing.
- AEC3 detects drift. With Speex, a slow slide is tracked by adaptation; jumps and dropped samples are not, per Valin
  on speex-dev.
- We measured ~10 ppm with 3-sample snaps.

**What the platform gives for free.**
- **Windows communications mode.**
  - Opening the mic as a communications stream (`IAudioClient2::SetClientProperties` with `AudioCategory_Communications`,
    or the `eCommunications` role) turns on the endpoint's communications chain: AEC/NS/AGC from the driver's APO or
    Microsoft's. On Windows 11 that includes Voice Clarity, which does AI echo cancellation, noise suppression and
    dereverberation, and is on by default for apps that use the Communications Signal Processing Mode.
  - Its reference is the render endpoint's mix, which includes Discord and every other app. Windows 11 lets an app pick
    the reference endpoint (`IAcousticEchoCancellationControl::SetEchoCancellationRenderEndpoint`, build 22540+).
  - Costs:
    - Godot's driver doesn't do it. We'd open the mic ourselves in the GDExtension, bypassing
      `AudioServer.get_input_frames`, the watchdog's tools and the other platforms.
    - Quality varies by device.
    - The chain also applies NS and AGC that we can't fully control.
    - A communications stream triggers Windows' **default ducking: other sounds -80%** (Communications tab, user
      setting), unless the app opts out.
- **The Voice Capture DSP** (`CWMAudioAEC`, a Media Foundation DMO, single-channel AEC mode `SINGLE_CHANNEL_AEC`) is the
  older Windows route. It is documented under "previous versions".
- **Steam voice / Discord.** Each runs AEC for *its own* outgoing voice, and Valve says theirs targets "minimal echo",
  not loud speakers. Neither cleans the stream *we* capture for the recognizer, and their playback is not in our Master
  mix. So a teammate's voice from Discord on speakers can still reach our recognizer. Only an OS-level AEC with the full
  render mix as reference, or headphones, covers that. If Cast ever plays Steam voice chat through a Godot bus, the
  Master tap includes it, and our AEC would also stop teammates' "cast fireball" from casting for us.

**Headphones vs speakers.**
- With closed headphones the echo is tiny, and AEC or ducking hardly matters.
- With desktop speakers the echo is moderate. With laptop speakers and the laptop mic it is large: little distance and
  shared chassis vibration. It is also nonlinear: small drivers distort when driven hard, and that is exactly what a
  linear AEC can't remove.
- `voice-mechanic.md` already recommends headphones, and audio-plan §4 rule 5 proposes a Headphones/Speakers choice.

**AEC and recognition.**
- Studies of keyword spotting and device-directed speech show accuracy drops sharply when user speech overlaps device
  playback, and that echo handling recovers much of it. Cornell et al. (2021): a 56% cut in false rejects with a
  reference-aware model. Panchapagesan et al. (Interspeech 2023): residual echo after a linear AEC "can significantly
  hinder" hotword and speech recognition, and a neural residual suppressor cut WER 38-53% over the linear AEC alone.
- Signal-processing suppressors trade echo removal against near-end distortion (EURASIP 2021).
- For us: our zipformer is not trained on AEC artifacts. Prefer the linear output, and check the speech under it with
  the voice clips before turning on any suppressor.

## 4. Options, against ducking

What each option is meant to fix (audio-plan §4):
- **(i) phantom words or casts while the player is silent**: the dispatch "pod*cast* room" arming the trigger, chimes
  read as "OH";
- **(ii) masking of the player's own words by game sound**: probe C, "cast corn" heard as "GASCORN" under a cue.

| | (a) Duck all game audio while the player speaks | (b) AEC with the Master tap | (c) Light duck + AEC | (d) Gating / known-clip tricks |
|---|---|---|---|---|
| Fixes (i) silent-player leaks | No: nothing ducks until the player speaks. On loud speakers the leak itself can open the gate and duck the game, which pumps | **Yes**, continuously | Yes | Partly: an output-aware gate (raise `min_voice_db` while Master's peak is high) blocks leaks, but also real casts said over loud moments |
| Fixes (ii) masking under speech | Partly: the first ~150-200 ms of every utterance is spoken over full audio (gate onset 50 ms + reads + 30 ms attack + output path, of a ~115 ms round trip). That is the "ca-" of "cast", the C-case risk | **Yes, from the first sample.** The filter must hold during double talk (MDF and AEC3 do) | Yes; the duck covers what AEC misses (after delay snaps, during divergence, speaker distortion) | No |
| Size of the effect | `duck_db` (e.g. -8 to -15 dB) once engaged | Here (OS-processed mic): **~8-10 dB**. Raw capture: to measure; the expectation is well above that | Roughly additive: ERLE + duck | Blocking, not cleaning |
| How the game feels | Goes quiet every time you talk, in a game where you talk constantly; pumps | **Unchanged** | A small dip | Unchanged, but some casts are refused during loud moments |
| Added recognition latency | None | One AEC frame (10-20 ms) plus the alignment buffer: the reference arrives ~115 ms *before* its echo, so nothing waits | 10-20 ms | None |
| CPU | ~0 | speexdsp MDF at 16 kHz, 10 ms frames, 128 ms filter: an estimated ~10 MFLOP/s, well under 1% of a core. AEC3: a few % (unmeasured). A GDScript NLMS is not viable (16M multiply-adds/s) | same as (b) | ~0 |
| Build cost | Built (`Sfx.ducking`, `duck_db`; needs a bus-level gain for "everything") | Native: speexdsp sources compiled into `hero_listen` (Hero-Reader's SConstruct), a Master tap, a delay estimator, a setting, tests. AEC3: meson + abseil, C++17, a bigger binary | (b) + flip ducking on lightly | GDScript only |
| Co-op | Local only; would also duck teammates' voice chat if we ever play it | Cleans anything *we* play, including future in-game voice chat. Not Discord or the Steam overlay (not in our mix) | same | - |
| Risk | Low | Delay jumps (device restart, hot-plug), the OS's own mic processing capping it, speech distortion if a suppressor is added | Low-medium | Refused casts |

"Known-clip subtraction" for our own clips is AEC with the clip as reference. The Master tap is the same idea, minus the
per-clip bookkeeping. **Spectral subtraction** guided by the reference's spectrum is cheaper than a full AEC but leaves
musical noise, which hurts ASR more than it helps. It is only worth it as AEC's residual stage, in a mild setting.

## 5. Could AEC let us skip ducking?

On this PC, as configured, not clearly. ~8-10 dB of AEC is about what a 10 dB duck gives. AEC's advantages are that it
covers the speech onset and silent-player leaks, and that the game doesn't go quiet. On a raw-capture speaker setup the
expectation is yes, if AEC reaches ~20 dB or more there.

**The measurement that decides it** is a *real-room leak probe*: `mic_leak_probe.gd`'s A/B/C/D tests, but with the
acoustic path real instead of a digital mix.
1. On speakers (desktop and a laptop), record with `echo_probe.gd`'s two-stream capture:
   - (a) the cue set and the dispatch lines alone;
   - (b) the voice clips played from a second speaker, or the user reading the 10 spells, with no game sound.

   Air adds linearly, so echo-only and voice-only takes can be mixed afterwards at any ratio, keeping the reference.
2. Feed the recognizer through the real `VoiceCaster`/`SpeechGate`, with:
   - nothing;
   - ducking at -8 and -15 dB, applied with the measured onset lag (~150-200 ms);
   - speexdsp AEC (linear);
   - AEC + a light -6 dB duck.

   Run each with the OS mic processing on and off.
3. Pass criteria:
   - **zero casts and zero armed triggers** from (a) alone;
   - cast recall over cues **within the no-cue control's margin** (e.g. ≥ 95% of control) at the default volume.

   If AEC alone passes on speakers, ducking stays off (or stays as an emergency "Speakers" mode). If only AEC + duck
   passes, ship both with the light duck.

## 6. Feasibility for Cast

**Where it goes.**
- In `VoiceCaster._pump_mic`, before `SpeechGate`, so the gate's floor, voice rule and repeat guard all see the cleaned
  signal.
- The game audio stops opening the gate, which also fixes the fizzle cutting itself on speakers (audio-plan "As built").
- At 16 kHz: downsample both streams in native code (the recognizer resamples to 16 kHz anyway).

**The reference.**
- An `AudioEffectCapture` on Master, added at runtime by VoiceCaster, local only. A 1-2 s buffer.
- Watch `get_discarded_frames()` (a hitch longer than the buffer loses reference and breaks alignment; reset the delay
  estimate when it happens).
- `Sfx` and the buses need no change. Being audio, this has no networking or net-contract impact (AGENTS rules 1-6 don't
  apply: it is not gameplay state, and it touches no `scripts/net/`).

**Alignment.**
- Count samples on both streams. The offset is what the probe measured, and it differs per session and per device
  restart.
- Option 1 is our own estimator in C++ (GCC-PHAT over ~1 s windows of game audio, decimated, run every few seconds and
  re-run after `_restart_mic`), feeding speexdsp a reference delayed to ~4 ms before the echo, with a 128 ms filter for
  the tail and the slack. A startup chirp is optional; it would only seed the estimate before the first loud cue.
- Option 2 is AEC3, which estimates the delay and drift itself and is given only a coarse hint
  (`set_stream_delay_ms`).

**GDScript vs native.**
- GDScript can do the tap, the bookkeeping, the setting and the tests.
- The canceller itself needs FFTs and ~10^7 multiply-adds per second. GDScript has no FFT and would be ~100x too slow,
  so it goes in the GDExtension.
- A new `EchoCanceller` class in `hero_listen`: `configure(rate, frame_ms, tail_ms)`, `push_reference(frames)`,
  `process(mic) -> PackedFloat32Array`, `get_stats()` (delay, ERLE, divergence). Alternatively, an `aec` stage inside
  WordListener's `push_samples`.

**speexdsp.**
- BSD-3 (Xiph.Org, Jean-Marc Valin and others), so it can ship.
- About eight C files: `mdf.c`, `preprocess.c`, `fftwrap.c`, `kiss_fft.c`, `kiss_fftr.c`, `filterbank.c`, plus
  headers; `resample.c` if we want its resampler. They compile into the existing DLL with `FLOATING_POINT` and
  `USE_KISS_FFT`.
- No new runtime DLL and no change to `hero_listen.gdextension`'s dependencies. Linux, macOS and Android build the
  same way.
- The DLLs are built in `..\Hero-Reader\native\hero_listen` (SCons, godot-cpp 4.5). Both template_debug and
  template_release must be rebuilt and copied (README "Not committed").

**WebRTC AEC3.**
- BSD-3 (the WebRTC authors) plus a patent grant. Usable standalone as `webrtc-audio-processing`, freedesktop/PulseAudio's
  meson-built extraction.
- Version 2.x has AEC3. Older distro packages (0.3) have only the previous AEC.
- It needs abseil-cpp and C++17, and it is tested mainly on Linux, so a Windows MSVC build is real work. It is a
  separate static library a few MB in size.
- 10 ms frames: `ProcessReverseStream` for our reference, `ProcessStream` for the mic.
- Better engineered: delay estimator, drift, a suppressor we can bypass via linear output.

**Latency.**
- Recognition gains one AEC frame (10-20 ms), which is negligible against the ~150 ms end-of-voice-to-cast.
- The reference is never late: we have it ~115 ms before its echo arrives. Even a 64 ms frame hitch is fine with a 1 s
  mic ring and a 2 s capture buffer.

**Risks.**
- **The OS processing caps us.** On this PC, ~8-10 dB. If many players' mics are already in a communications or
  enhanced mode, our AEC buys less, and the OS may be doing it anyway.
- **Divergence after a delay snap or device change.** Watch ERLE, and reset when it goes negative (residual louder than
  the mic).
- **Double-talk mistakes** that eat the player's words. The probe's C test and the voice clips catch these.
- **Speakers driven into distortion**, which a linear AEC leaves behind.
- **More moving parts in the mic path**, which is where the playtests found the stall and replay bugs. It needs a
  kill switch, and an "AEC" line on the voice debug panel.

## 7. Recommended path

1. **Measure where it matters** (cheap, no code in the game). Run `tools/echo_probe.gd`:
   - on the user's PC with speakers confirmed, at normal volume, with Windows' mic "Audio enhancements" / Voice Clarity
     **off** and then **on**;
   - on a laptop (built-in speakers and mic);
   - with headphones, as the control.

   This says how big the echo is and how much a linear canceller *could* remove on raw capture. If raw capture still
   gives under ~12 dB, stop here: keep the sound-design rules and turn ducking on.
2. **Build the real-room leak probe** (§5) around the recordings. It is the decision tool for AEC vs ducking vs both,
   and it stays as the regression test.
3. **Prototype speexdsp AEC offline first.** Run speexdsp on the probe recordings, through a Python or a small C harness
   in `tools/`, and score with the leak probe. Only if it beats ducking:
4. **Integrate it in `hero_listen`.**
   - `EchoCanceller`, with our GCC-PHAT delay tracker, a Master tap in VoiceCaster, and re-estimation on `_restart_mic`
     and discarded frames.
   - A setting: "Echo cancel: auto/off". Auto means on unless the player picks "Headphones".
   - A debug panel line (delay, ERLE).
   - A test: a digital echo (a convolved IR + delay + 10 ppm drift + 3-sample snaps) is removed by at least X dB, and
     the voice clips still cast through it.
5. **Revisit AEC3** only if speexdsp misses the bar on the probe (drift snaps, device changes), or when Steam voice chat
   arrives (more echo, and a bigger payoff).
6. **Ducking**, per the probe:
   - if AEC passes alone, ducking stays off, and "Speakers" mode may add a -6 dB duck;
   - if AEC doesn't land, turn ducking on for every cue, as audio-plan already plans.

   Either way, the mic-leak sound-design rules (§4 rules 1-3, 7, 8) stay: AEC is a second line, not a licence for vocal
   cues.

## Open questions for the user

1. **Speakers or headphones?** What was on the Realtek output during the probe, and what do you expect players to use?
   Should "Headphones / Speakers" be a first-run question (audio-plan open question 6)?
2. **May we re-run the probe with Windows' mic processing off?** Settings > System > Sound > QuadCast S > Audio
   enhancements / Voice Clarity. The agent can't change system settings, and the run needs your OK because it makes
   sound. Also: is NVIDIA Broadcast or similar in the chain?
3. **Is an audible calibration chirp at startup acceptable?** It is not required (the delay can be tracked from game
   sounds), but it would seed the estimate. A quiet 0.25 s sweep on the voice setup screen ("Try it") is the natural
   place.
4. **Approve downloading speexdsp?** It's for the offline prototype (step 3) and later the GDExtension.
5. **Should "Echo cancel" be a player setting** (auto/off), or stay hidden in Diagnostics?

## Downloads needed (not done; ask first)

| What | From | Licence | Size |
|---|---|---|---|
| speexdsp source (release 1.2.1) | https://github.com/xiph/speexdsp (or downloads.xiph.org/releases/speex/) | BSD-3 | about 1 MB (not checked) |
| Python bindings for the offline prototype (optional; a 50-line C harness instead avoids it) | PyPI `speexdsp` | to check | small |
| webrtc-audio-processing 2.x (only if step 5) | https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing | BSD-3 | not checked; plus abseil-cpp |

## Sources

- Godot `AudioServer` (`get_output_latency`, `get_input_frames`, `get_input_buffer_length_frames`):
  https://docs.godotengine.org/en/stable/classes/class_audioserver.html
- Godot WASAPI driver (categories, buffer sizes, no input timestamps):
  https://github.com/godotengine/godot/blob/master/drivers/wasapi/audio_driver_wasapi.cpp
- Speex echo canceller API and manual: https://speex.org/docs/api/speex-api-reference/group__SpeexEchoState.html ;
  https://speex.org/docs/manual/speex-manual/node7.html ; header:
  https://github.com/xiph/speexdsp/blob/master/include/speex/speex_echo.h ; MDF source (Soo & Pang 1990, Valin):
  https://android.googlesource.com/platform/external/speex/+/bb67e75/libspeex/mdf.c
- Speex preprocessor and residual echo suppression:
  https://speex.org/docs/api/speex-api-reference/group__SpeexPreprocessState.html ;
  https://lists.xiph.org/pipermail/speex-dev/2007-June/005834.html
- speexdsp licence: https://github.com/xiph/speexdsp/blob/master/COPYING ; WebRTC licence:
  https://webrtc.googlesource.com/src/+/main/LICENSE
- WebRTC AEC3 delay estimator: https://webrtc.googlesource.com/src/+/main/modules/audio_processing/aec3/echo_path_delay_estimator.cc ;
  APM API (`ProcessStream`, `ProcessReverseStream`, `set_stream_delay_ms`, `export_linear_aec_output`):
  https://webrtc.googlesource.com/src/+/main/api/audio/audio_processing.h ; linear AEC output for the NS:
  https://webrtc.googlesource.com/src/+/2e8e1c699ef5af1f8b3e4dd02a50feb015ed3faf
- webrtc-audio-processing (standalone): https://www.freedesktop.org/software/pulseaudio/webrtc-audio-processing/ ;
  AEC2 vs AEC3 packaging notes: https://git.manko.yoga/manawenuz/wz-phone/commits/commit/4ba77c8c0e39d0000290e7b4f453b286a7b79105/crates/wzp-client/Cargo.toml
- GCC-PHAT: https://www.mathworks.com/help/phased/ref/gccphat.html ; https://speechprocessingbook.aalto.fi/Enhancement/tdoa.html
- Clock drift in AEC: https://arxiv.org/html/2507.05399v1 ; https://patents.justia.com/patent/20070165838 ;
  https://lists.xiph.org/pipermail/speex-dev/2011-April/008117.html
- Double talk (Geigel, variable step size): https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/6792106 ;
  https://scholarsmine.mst.edu/ele_comeng_facwork/6170
- Windows AEC (communications streams, reference endpoint):
  https://learn.microsoft.com/en-us/samples/microsoft/windows-classic-samples/acousticechocancellation ;
  https://learn.microsoft.com/en-sg/WINDOWS-HARDWARE/DRIVERS/audio/windows-11-apis-for-audio-processing-objects ;
  Voice Capture DSP: https://learn.microsoft.com/en-us/previous-versions/bb288683(v=vs.85) ;
  default ducking: https://learn.microsoft.com/en-us/windows/win32/coreaudio/stream-attenuation ;
  Voice Clarity: https://www.techradar.com/computing/windows/windows-11s-ai-powered-voice-clarity-feature-improves-your-video-chats-plus-setup-has-a-new-look-finally
- Steam voice: https://partner.steamgames.com/doc/features/voice ; Valve on its AEC:
  https://steamcommunity.com/groups/SteamClientBeta/discussions/3/1694924244567875320
- AEC and recognition: https://arxiv.org/abs/2111.10639 (Cornell et al.);
  https://www.isca-archive.org/interspeech_2023/panchapagesan23_interspeech.pdf ;
  https://asmp-eurasipjournals.springeropen.com/articles/10.1186/s13636-021-00221-8 ;
  ESP-SR AEC modes: https://docs.espressif.com/projects/esp-sr/en/latest/esp32s3/acoustic_echo_cancellation/README.html
