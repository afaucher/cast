# Cast: the voice mechanic

This doc covers pillar 2, combat through spoken spells: how speaking a spell turns into
power. Pillar 1, exploration, is in `exploration.md`. Voice has only a few light
exploration uses there; spells are mainly for fighting.

The numbers here are grounded in what the speech pipeline can actually do: sherpa-onnx,
the streaming Zipformer, hotword score 2, and the "extra-only" sound-alike matcher. They
come from the speech-to-text evaluation in the Hero-Reader project
(`docs/stt-evaluation.md`), which Cast's speech pipeline was taken from.

## What the recognizer gives us

| Fact (measured) | Design consequence |
|---|---|
| ~95% hits on a clear adult voice through a decent mic; 70–80% in noise or on crowd-sourced audio | Misses are the common error. **A miss must be cheap.** |
| Wrong word ~0.6%, rising to 3–5% when sound-alike words share a vocabulary | Never give one player two confusable spell words |
| Latency from end of voice to event: **~330 ms p50, ~630 ms p90** | Animate from voice *onset*, not from recognition |
| Same-word double fire on 7–10% of utterances | Dedupe the same spell from the same player within 1.5 s |
| Strong hotword boost **invents vocab words** from mumbles ("um" → "OF THE") | Chatter can produce spell words that were never said |
| Signals available: voice onset and offset (`voice_activity`), mic level, streaming partials, the final transcript and its tokens, per-token timestamps, and the exact vs sound-alike match type | These are the inputs for fumble scoring (below) |
| One-syllable and single-letter words are unreliable in isolation | Spell words should be two syllables or more, or a distinctive single syllable |

**Core principle: fumbles degrade, misses are free, and only garbage fizzles.** Players must
be able to tell *their* mistake from the machine's. Penalize the things players can hear
themselves do (pauses, wrong words, "um"). Barely penalize the things they can't (model
confidence).

---

## 1. Incantation grammar

### Options

| Grammar | Example | Pros | Cons |
|---|---|---|---|
| Bare word | "fireball" | Fastest, most magical | Collides with chatter ("use fireball on him") |
| Verb prefix | "cast fireball" | Strong chatter protection | +250 ms of speech and gets repetitive; "cast" vs "past" vs "cash" |
| Multi-word incantation | "great fireball", "ignis magna" | Power scales with effort | Slower; more ways to fumble |
| Modifier words | "big fireball", "twin fireball", "quick heal" | Expressive and learnable | Needs a modifier vocabulary that is robust to ASR |
| Direction by voice | "fireball left" | | **Avoid.** "Left" is ambiguous in isometric view, and the mouse is better at aiming |
| Target by voice | "heal Fox", "armor me" | Great for co-op support | Needs ASR-friendly names (see below) |

### Recommendation

1. **Base form: the bare spell word, as its own short utterance.** "Fireball." Aim always
   comes from the mouse or stick.
2. **The "cast" prefix is always allowed** and overrides chatter filtering. "...so cast
   fireball" works mid-sentence.
3. **Modifiers go before the noun and are unlocked by progression.** "Big" means more
   power, a slower wind-up and a longer cooldown. "Quick" means a smaller effect and an
   instant release. "Twin" splits the spell in two. Order is fixed:
   `[modifier] spell [target]`.
4. **Targets come after the noun, ally spells only:** "heal Fox", "armor me", "heal all".
   - Players pick **callsigns from a curated list** (Fox, Bear, Crow, Moss, Ember, Pike)
     instead of using real names or gamertags. Every name is phonetically distinct from
     every spell word and from the others.
   - With no target, the spell picks the most-hurt ally in range.
5. **Rule: no spell word may be a prefix of another** ("fire" and "fireball" can't both be
   spells). Streaming partials commit the wind-up early (see Latency), so a prefix would
   commit the wrong spell. Compound *halves* are the one deliberate exception, and they are
   cast by two different players.

**Cast time is speaking time.** Longer phrases are stronger and also slower and riskier.
That trade-off is the skill curve, and we get it for free.

---

## 2. Fumble scoring

The contract is `spell_spoken(spell_id, power, heard)` with power in (0, 1]. The formula:

```
power = clamp(M × F × C, 0, 1)
```

**M (match quality)**, per spell word, from the matcher:

| Match | M |
|---|---|
| Exact or homophone | 1.00 |
| Sound-alike, "extra-only" (one extra sound: "corns", "healed") | 0.80 |
| Sound-alike, "any" (the friendly-mode accessibility option) | 0.70 |

**F (fluency)**, from per-token timestamps (multi-word incantations only):
- A gap between words of **≤ 0.25 s** gives 1.0. From **0.25 to 0.70 s** it falls linearly
  to 0.75. A gap **> 0.70 s** **breaks** the incantation: the parts are scored as separate
  utterances.
- Each filler or unknown token *inside* the incantation ("big, uh, fireball") multiplies
  by 0.85.
- A restart ("fi– fireball", seen as a junk token right before the spell word) multiplies
  by 0.90.
- Single-word spells have F = 1.

**C (clarity)**, from mean per-token probability if the sherpa build exposes it:
- `C = 0.85 + 0.15 × smoothstep(0.4, 0.9, p)`.
- Capped so that invisible model noise moves power by at most 15%.
- If token probabilities aren't exposed, C = 1. *Check the sherpa-onnx result JSON first;
  it reports tokens and timestamps.*

**Missing words degrade instead of failing:**
- If a modifier isn't recognized, the base spell still casts at full M. "Big fireball"
  heard as "fireball" gives a plain fireball.
- If the target isn't recognized, the spell falls back to auto-targeting.

### Tiers

| Power | Tier | What happens |
|---|---|---|
| ≥ 0.95 | **Perfect** | Full effect plus a bonus rider (fireball leaves a burn patch, heal overheals into a small shield), and a gold glyph flourish |
| 0.75–0.95 | **Clean** | Full effect |
| 0.50–0.75 | **Shaky** | The effect is `base × lerp(0.6, 1.0, power)`, and the glyph sputters |
| < 0.50, or spell-ish with no match | **Fizzle** | No effect, 25% of the cooldown spent, and a comic puff of smoke |
| Nothing recognized | **Miss** | Nothing happens and **no cooldown is spent**. A grey "?" glyph shows the heard text |

Worked examples:
- "fireball" clean: M=1, Perfect.
- "fireballs": M=0.8, Clean.
- "big... uh... fireball" with a 0.5 s gap: 1 × (0.86 × 0.85) ≈ 0.73, Shaky.
- "corns, um" heard as "CORNS OF THE": the "of the" junk sits *after* the spell, so it
  doesn't count. M=0.8, Clean.

**Mic volume (an optional signal):** loudness relative to the player's calibrated normal
level. It should *not* be a general power input, because shouting all session causes voice
fatigue and annoyed housemates. Reserve it for specific spells and enemies (see
content-ideas.md).

---

## 3. Voice chat vs casting

### The problem

- Players talk constantly. Conversation runs at roughly 15 utterances a minute.
- Hotword biasing pulls mumbles toward spell words.
- If even 0.5% of chatter utterances become a spell, that is one accidental cast every
  ~13 minutes. That's tolerable for corn and terrible for a 30-second-cooldown meteor.
  **The POC must measure this rate.**

### Rule 1: spoken, not mentioned

A spell fires only when it is *used*, not *talked about*:
- the utterance starts with "cast", **or**
- the spell phrase *is* the utterance, allowing at most one extra word ("heal!", "heal
  me", "fireball now").

"I'll save my fireball for the brute" is a long utterance with the spell word buried in it,
so nothing fires. "He'll be fine" has "he'll", a homophone of "heal", as one of three
words, so nothing fires. This uses the endpointed final result, which we wait for anyway.

### Rule 2: hair-trigger spells (deliberate accidents)

Some spells ignore Rule 1 and fire on *any* mention:
- **Corn.** If you say "corn" anywhere, in any sentence, it drops, aimed at *the speaker*.
  Talking about the corn spell is how you learn this.
- Others: "duck" (everyone ducks *and* a rubber duck appears), "over here" (a taunt), and
  "hurry" (a haste speed boost).

Accidents are fun when the spell is cheap and funny or does what you probably meant
anyway. They're miserable when they burn a big cooldown. **Never hair-trigger anything
with a cooldown over ~10 s.**

Note "corner": under extra-only it's corn plus one extra sound, so "he's in the corner!"
drops corn. Keep it. That's a feature.

### Rule 3: push-to-talk modes

| Mode | How it works | Who it's for |
|---|---|---|
| **Open mic** (default) | Rules 1–2 apply | Most groups |
| **Push-to-cast** | Hold a key or mouse thumb button. Only speech while held can cast, and Rule 1 is off (everything said is an attempt) | Noisy rooms, streamers, high-difficulty runs |
| **Push-to-chat** | Hold a key to talk without casting | Players who chat a lot and cast a lot |


### Crosstalk: shared rooms and shared mics

- **Two PCs in one room:** each player's mic hears the other.
  - **Per-player level gate:** at calibration, record each player's own speaking level.
    Reject utterances more than ~12 dB below it, since a voice from across the room is
    much quieter.
  - **Host attribution:** if two players cast the same spell with voice onsets within
    300 ms, credit only the louder one, unless both were loud. Then it's a *unison* cast
    (see below), and that's a feature.
- **Speakers instead of headphones:** teammates' voice chat leaks back into your mic.
  - Recommend headphones in the first-run screen.
  - Do voice chat **in-game** (Steam voice) rather than through Discord. Then we have the
    playback signal for echo cancellation and can drop casts that match a word we just
    played out of the speakers.
- **One mic shared by two players (couch):** speaker attribution is hard. Use **disjoint
  spell sets** instead: each player's words are unique, so the word identifies the
  caster. Speaker embeddings (sherpa-onnx has speaker-ID models) are a later upgrade.
- **Same-word dedupe:** ignore the same spell from the same player within 1.5 s (this
  covers the Zipformer double fires).

---

## 4. Co-op voice ideas

- **Unison (chorus).** Two or more players say the same spell with **voice onsets within
  400 ms** of each other. It becomes one Chorus cast: radius ×1.5 per extra voice, and
  power uses the best player's score.
  - Compare *local onset timestamps* (with synced clocks), not arrival times, so network
    jitter doesn't matter.
  - Sealed shrine doors open only to a chorus (see `exploration.md`).
- **Call and response.** One player calls "Brace!" Everyone who answers "Brace!" within
  2 s gets armor, and the caller gets armor too if at least two answer. It's a short,
  learnable ritual that makes voice chat sound like a team.
- **Split words.** A compound spell is cast by two players, each saying one half within
  1.5 s, in order. Fire + storm, earth + quake, **pop + corn** (a cluster of exploding
  kernels), and corn + field (a carpet-bomb line). Each half is also a valid noise on its
  own, so a solo player saying "storm" gets a fizzle with a hint.
- **Silence.**
  - *Vow of quiet:* a player who has been silent for 8 s glows, and their next spell is
    automatically Perfect. This rewards the quiet player in a loud group.
  - *Hush zones:* areas where speaking wakes sleeping enemies, used for stealth rooms.
  - *Silencer enemies:* see content-ideas.md.
- **Voice-commanding AI allies (POC-friendly).** "Fox, heal me" makes the AI ally cast.
  This tests targeting grammar today, with no networking.

---

## 5. Latency budget and hiding it

**Budget for a voice cast (single word, measured on the current pipeline):**

| Stage | Time |
|---|---|
| Speaking the word | 300–600 ms |
| Endpoint silence + decode (end of voice → event) | ~330 ms p50 / ~630 ms p90 |
| **Onset → effect** | **~0.7–1.2 s** |
| Human reaction + speaking + ASR, for reactive casts | **~1.0 s p50, ~1.5 s p90** |

**How to hide it:**
1. **Voice onset (~0 ms):** the hero instantly starts a generic "gathering" pose, their
   hands glow and a faint rune ring appears on the ground. This tells players they've been heard.
2. **Partial hypothesis exactly matches a spell (mid-word):** commit the wind-up to that
   spell's color and glyph. If the final result disagrees, play a cheap fizzle with *no
   cooldown*.
3. **Final result:** release. Every spell gets a **0.3–0.5 s release animation** whose hit
   frame comes at the end, and projectiles travel, so the last 300 ms reads as
   choreography.
4. **Optional quick-draw for later testing:** fire immediately on an exact partial for
   single-word spells tagged `quick` (heal, corn). This is faster but more chatter-prone.

**Tuning rules this forces:**
- Enemy telegraphs that a *voice* spell should answer, such as the brute slam vs armor,
  need **≥ 1.5 s** of warning.
- Spell cooldowns should be long (6–30 s), with big effects. Voice is not for spam.
  Ordinary attacks fill the gaps.
- Keep total voice casts to **~6–10 a minute** at peak to avoid vocal fatigue.

---

## 6. Accessibility

- **Keyboard and controller fallback (keys 1/2 already exist):**
  - **Default parity:** a keyboard cast has a 0.5 s channel and fixed power 0.8 (Clean,
    never Perfect), so voice stays the best option without being mandatory.
  - **Accessibility mode:** keyboard casts at 1.0, with no channel.
- **Fluency scoring toggle:** "Pauses and fillers reduce power." It is on by default and
  explained during first-run calibration. The gap penalty *is* a stutter penalty, so it
  must be one click away and never shamed.
- **Friendly matching:** the "any" sound-alike rule, for accents and articulation
  differences. It accepts more near-misses at a small wrong-spell cost.
- **Rebindable spell words:** the player picks from 3–4 alternates per spell, all
  pre-vetted for ASR ("fireball", "inferno", "blaze"). Free-text custom words come later,
  because they need pronunciations generated for the matcher.
- **Non-native speakers:** the English model is the limit for now. Prefer plain, common,
  multi-syllable words over fantasy jargon. Localizing means a model per language and
  word lists per language.
- **Calibration ("Attunement," 60–90 s):**
  - Say each spell word 3 times and measure the hit rate, level and noise floor.
  - Flag any word below 80% and offer an alternate.
  - Set the personal level gate for crosstalk.
  - Optionally record a speaker embedding.
  - Re-runnable from the pause menu.

---

## 7. What the POC playtest must measure

**Logged automatically for every utterance:**
- heard text, partial vs final, match type, M/F/C, power, tier;
- onset → event and end → event latency;
- whether the hero knew the spell, and the cooldown state.

**Session data:**
- Record mic audio with consent so matcher rules can be replayed offline, like
  Hero-Reader's `replay_matcher.py`.
- A **"that was wrong" key (F2)**: the tester taps it after a miss or a false cast. This
  provides ground truth cheaply.

| Question | Metric | Go threshold |
|---|---|---|
| Does it understand me? | Intended casts recognized (from F2 + audio review) | ≥ 90% |
| Does chatter misfire? | Accidental non-hair-trigger casts per 10 min of talking (tester thinks aloud, or a second person in the room) | ≤ 1 |
| Does it feel fast? | "Felt laggy" rating; onset → effect p90 | ≤ 1.2 s; rating ≥ 5/7 |
| Is fumbling legible? | After a Shaky cast, can the tester say why? | ≥ 70% correct |
| **Is voice actually fun?** | Share of casts by voice when keys 1/2 are equally available, after 20 minutes | **≥ 60%** |
| Does corn land? | Laughs or unprompted "corn" casts per session (observer tally) | Any. If nobody laughs, the timing or FX is wrong |
| Is it sustainable? | Voice fatigue rating after 30 minutes; casts per minute | No hoarseness; ≤ 10/min |

The most important number is **voice share when keys are available.** If players drift to
the keyboard, the mechanic isn't earning its friction, no matter how accurate the
recognizer is.
