<#
.SYNOPSIS
  Render voice-cast test incantations to 16 kHz / 16-bit / mono WAVs with
  Windows text-to-speech (System.Speech), plus two manifests.
  No microphone needed. Output is generated, so it is git-ignored.

.DESCRIPTION
  Text may contain <b300>-style markers: a silent pause of that many ms.

  tests/voice_clips/manifest.csv   (test_voice_audio.gd)
    file       wav file name
    group      clean | rate | sloppy | hesitate | bare | negative
    strict     expected outcome under strictness "strict" (trigger must start the utterance)
    loose      ... under "loose" (the default: trigger anywhere; "corn" fires on any mention)
    chaos      ... under "chaos" (any spell word anywhere)
               each of those: a spell id that must fire, "none", or "any" (only reported)
    min_power  minimum power when a spell id is expected
    voice, rate, text

  tests/voice_clips/triggers.csv   (test_voice_triggers.gd; wavs in triggers/)
    file,trigger,kind,spell,voice,text    kind = pos | neg | cross

.PARAMETER Triggers
  Trigger words rendered in triggers.csv (VoiceCaster.TRIGGER_OPTIONS).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_voice_clips.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_voice_clips.ps1 -OutDir C:\tmp\clips
#>
param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\tests\voice_clips"),
    [string[]]$Voices = @("Microsoft David Desktop", "Microsoft Zira Desktop"),
    [string[]]$Triggers = @("cast", "magic", "pickle", "conjure", "invoke", "summon", "presto", "abracadabra")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

$installed = (New-Object System.Speech.Synthesis.SpeechSynthesizer).GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }
$Voices = @($Voices | Where-Object { $installed -contains $_ })
if ($Voices.Count -eq 0) { $Voices = @($installed[0]) }
$v1 = $Voices[0]
$v2 = if ($Voices.Count -gt 1) { $Voices[1] } else { $Voices[0] }

$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)

function Render([string]$text, [string]$file, [string]$voice, [int]$rate) {
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $s.SelectVoice($voice)
        $s.Rate = $rate
        $s.SetOutputToWaveFile($file, $fmt)
        $pb = New-Object System.Speech.Synthesis.PromptBuilder
        $pb.Culture = $s.Voice.Culture
        foreach ($part in [regex]::Split($text, '(<b\d+>)')) {
            if ($part -match '^<b(\d+)>$') {
                $pb.AppendBreak([TimeSpan]::FromMilliseconds([int]$Matches[1]))
            } elseif ($part.Trim() -ne "") {
                $pb.AppendText($part.Trim())
            }
        }
        $s.Speak($pb)
    } finally {
        $s.Dispose()
    }
}

function Slug([string]$t) { ($t.ToLower() -replace "<b(\d+)>", 'b$1' -replace "[^a-z0-9]+", "_").Trim("_") }

# group, text, expect(strict), expect(loose), expect(chaos), min_power, voice, rate
$clips = New-Object System.Collections.Generic.List[object]
function Add-Clip([string]$group, [string]$text, [string]$strict, [string]$loose, [string]$chaos, [double]$minPower, [string]$voice, [int]$rate) {
    $clips.Add([PSCustomObject]@{ group = $group; text = $text; strict = $strict; loose = $loose; chaos = $chaos; min_power = $minPower; voice = $voice; rate = $rate })
}
function Same([string]$group, [string]$text, [string]$expect, [double]$minPower, [string]$voice, [int]$rate) {
    Add-Clip $group $text $expect $expect $expect $minPower $voice $rate
}

$spells = [ordered]@{ heal = "heal"; fireball = "fireball"; armor = "armor"; corn = "corn"; tentacles = "tentacles"; teeth = "teeth"; vines = "vines"; damp = "damp"; coffee = "coffee"; chicken = "chicken" }

# Clean casts, both voices, normal pace: must fire at >= 0.9 in every mode.
foreach ($v in @($v1, $v2)) {
    foreach ($id in $spells.Keys) {
        # David hears "cast coffee" as "COUGHING" (a measured alias, 0.8), so coffee's bar is lower.
        $mp = if ($id -eq "coffee") { 0.75 } else { 0.9 }
        Same "clean" "cast $($spells[$id])" $id $mp $v 0
    }
}
# Pace changes (TTS rate -3 slow .. +3 fast).
foreach ($r in @(-3, 3)) {
    foreach ($id in $spells.Keys) {
        # +3 hears tentacles as "headacles" (a 0.8 alias) and David hears vines as "CASTBINES" (a 0.75 alias)
        $mp = if ($id -eq "tentacles" -or $id -eq "vines") { 0.7 } else { 0.8 }
        Same "rate" "cast $($spells[$id])" $id $mp $v1 $r
    }
}
# tentacles at the pace extremes in the other voice, and the singular at the fast end
# ("headacles"/"headagle" are measured mishearings at rate +3, see Incantation).
foreach ($r in @(-3, 3)) { Same "rate" "cast tentacles" "tentacles" 0.8 $v2 $r }
Same "rate" "cast tentacle" "tentacles" 0.7 $v1 3
# teeth (one syllable, the riskiest word): the pace extremes in the other voice too, and the singular.
foreach ($r in @(-3, 3)) { Same "rate" "cast teeth" "teeth" 0.7 $v2 $r }
Same "rate" "cast tooth" "teeth" 0.7 $v1 3
# vines / damp / coffee: the pace extremes in the other voice too.
foreach ($r in @(-3, 3)) { foreach ($id in @("vines", "damp", "coffee")) { Same "rate" "cast $id" $id 0.7 $v2 $r } }
# chicken: the pace extremes in the other voice too.
foreach ($r in @(-3, 3)) { Same "rate" "cast chicken" "chicken" 0.7 $v2 $r }
# Sloppy but intended: preamble, suffix, mispronunciations, spelling variants.
Same "sloppy" "okay cast heal"            "heal"     0.8 $v1 0
Same "sloppy" "cast fireball now"         "fireball" 0.8 $v2 0
Same "sloppy" "please cast armor"         "armor"    0.8 $v2 0
Same "sloppy" "cast fire ball"            "fireball" 0.9 $v1 0
Same "sloppy" "cast fire bowl"            "any"      0.5 $v1 0
Same "sloppy" "cast fire"                 "any"      0.4 $v1 0
Same "sloppy" "cast armour"               "armor"    0.8 $v1 0
Same "sloppy" "cast heel"                 "any"      0.4 $v1 0
Same "sloppy" "cass heel"                 "any"      0.4 $v1 0
Same "sloppy" "cast he'll"                "any"      0.4 $v2 0
Same "sloppy" "caste corn"                "any"      0.4 $v2 0
Same "sloppy" "cast corn corn"            "corn"     0.8 $v2 0
# tentacles (the longest, rarest spell word): preamble, singular, hesitation, the other voice.
Same "sloppy" "okay cast tentacles"       "tentacles" 0.8 $v1 0
Same "sloppy" "okay cast tentacles"       "tentacles" 0.8 $v2 0
Same "sloppy" "cast tentacle"             "tentacles" 0.8 $v1 0
Same "sloppy" "cast tentacle"             "tentacles" 0.8 $v2 0
Same "sloppy" "please cast tentacles"     "tentacles" 0.8 $v2 0
Same "sloppy" "cast tentacles now"        "tentacles" 0.8 $v1 0
# teeth: preamble, suffix, singular, the other voice.
Same "sloppy" "okay cast teeth"            "teeth" 0.8 $v1 0
Same "sloppy" "okay cast teeth"            "teeth" 0.8 $v2 0
Same "sloppy" "please cast teeth"          "teeth" 0.8 $v2 0
Same "sloppy" "cast teeth now"             "teeth" 0.8 $v1 0
Same "sloppy" "cast tooth"                 "teeth" 0.8 $v1 0
Same "sloppy" "cast tooth"                 "teeth" 0.8 $v2 0
# vines / damp / coffee: preamble, suffix, the singular, the other voice.
Same "sloppy" "okay cast vines"             "vines"  0.8 $v1 0
Same "sloppy" "please cast vines"           "vines"  0.8 $v2 0
Same "sloppy" "cast vines now"              "vines"  0.8 $v1 0
Same "sloppy" "cast vine"                   "vines"  0.8 $v1 0
Same "sloppy" "okay cast damp"              "damp"   0.8 $v1 0
Same "sloppy" "please cast damp"            "damp"   0.8 $v2 0
Same "sloppy" "cast damp now"               "damp"   0.8 $v1 0
Same "sloppy" "okay cast coffee"            "coffee" 0.7 $v1 0   # David: "O K CAST COUGHING" (alias 0.8, less the preamble)
Same "sloppy" "please cast coffee"          "coffee" 0.8 $v2 0
Same "sloppy" "cast coffee now"             "coffee" 0.8 $v1 0
# chicken: preamble, suffix, the plural, the other voice.
Same "sloppy" "okay cast chicken"           "chicken" 0.8 $v1 0
Same "sloppy" "please cast chicken"         "chicken" 0.8 $v2 0
Same "sloppy" "cast chicken now"            "chicken" 0.8 $v1 0
Same "sloppy" "cast chickens"               "chicken" 0.8 $v1 0
Same "sloppy" "cast chickens"               "chicken" 0.8 $v2 0
# Hesitation between the keyword and the spell word.
Same "hesitate" "cast <b300> heal"                    "heal"     0.8 $v1 0
Same "hesitate" "cast <b300> tentacles"               "tentacles" 0.6 $v1 0
Same "hesitate" "cast <b500> tentacles"               "tentacles" 0.8 $v2 0
Same "hesitate" "cast <b800> tentacles"               "tentacles" 0.6 $v1 0
Same "hesitate" "cast <b300> vines"                   "vines" 0.6 $v1 0
Same "hesitate" "cast <b500> damp"                    "damp" 0.6 $v2 0
Same "hesitate" "cast <b300> coffee"                  "coffee" 0.6 $v1 0
Same "hesitate" "cast <b300> teeth"                   "teeth" 0.6 $v1 0
Same "hesitate" "cast <b500> teeth"                   "teeth" 0.6 $v2 0
Same "hesitate" "cast <b800> teeth"                   "teeth" 0.5 $v1 0
Same "hesitate" "cast <b300> chicken"                 "chicken" 0.6 $v1 0
Same "hesitate" "cast <b500> chicken"                 "chicken" 0.6 $v2 0
Same "hesitate" "cast <b700> fireball"                "any"      0.3 $v1 0
Same "hesitate" "cast <b400> uh <b400> heal"          "heal"     0.5 $v2 0
Same "hesitate" "cast <b1200> armor"                  "any"      0.4 $v2 0
Add-Clip "hesitate" "cast <b3000> heal"               "none" "none" "any" 0.0 $v1 0
# Bare spell words: strict/loose do not cast them, except corn (any mention) in loose.
foreach ($v in @($v1, $v2)) {
    foreach ($id in $spells.Keys) {
        $loose = if ($id -eq "corn") { "corn" } else { "none" }
        # David's bare "vines" is heard as "VI NES" (two tokens), so chaos cannot be held to firing it.
        $chaos = if ($id -eq "vines") { "any" } else { $id }
        Add-Clip "bare" $spells[$id] "none" $loose $chaos 0.9 $v 0
    }
}
# Chatter. Accidental invocations are part of the theme in loose/chaos, so the
# expectation depends on the mode.
Add-Clip "negative" "I need a heal over here"        "none" "none" "heal"     0.4 $v1 0
Add-Clip "negative" "nice fireball"                  "none" "none" "fireball" 0.4 $v1 0
Add-Clip "negative" "watch out for the fire ball"    "none" "none" "fireball" 0.4 $v1 0
Add-Clip "negative" "put your armor on"              "none" "none" "armor"    0.4 $v1 0
Add-Clip "negative" "watch out for the tentacles"    "none" "none" "tentacles" 0.4 $v1 0
Add-Clip "negative" "watch out for the tentacles"    "none" "none" "tentacles" 0.4 $v2 0
Add-Clip "negative" "corn on the cob"                "none" "corn" "corn"     0.4 $v1 0
Add-Clip "negative" "corner"                         "none" "corn" "corn"     0.4 $v1 0
Add-Clip "negative" "should I cast heal"             "none" "heal" "heal"     0.4 $v1 0
Add-Clip "negative" "did you cast fireball"          "none" "fireball" "fireball" 0.4 $v2 0
foreach ($t in @("hello", "let's go left", "pop", "of course", "behind you", "castle", "cast away", "the cast of the show", "I cast my vote",
        "attack", "ten tickets", "testicles", "I can't tackle this")) {
    Add-Clip "negative" $t "none" "none" "none" 0.0 $v1 0
}
# Teeth: the words it can be mistaken for, and chatter that really says it. "cast these" / "cast tea" are
# the dangerous ones: the trigger plus a one-syllable "tee" sound. Nothing may cast in any mode, except
# that chaos (any spell word anywhere) fires on the real word in "nice teeth" / "brush your teeth".
foreach ($v in @($v1, $v2)) {
    foreach ($t in @("these", "tea", "teach me", "tease", "cast these", "cast tea", "cast teach me")) {
        Add-Clip "negative" $t "none" "none" "none" 0.0 $v 0
    }
    foreach ($t in @("nice teeth", "brush your teeth")) {
        Add-Clip "negative" $t "none" "none" "teeth" 0.4 $v 0
    }
}
# Vines / damp / coffee: the words they can be mistaken for, and chatter that really says them. "damn" is common
# chatter ("cast damn" would be the trigger plus a one-syllable "dam" sound), "wines"/"vibes"/"fines"/"binds" are the
# vines mishearings, "copy"/"coughing" the coffee ones. Nothing may cast in any mode, except that chaos (any spell
# word anywhere) fires on the real word in "nice vines" / "I need coffee" / "damp towel".
foreach ($v in @($v1, $v2)) {
    foreach ($t in @("wines", "vibes", "damn", "that was damn good", "dump", "camp", "dam", "copy", "coughing", "goddamn it",
            "cast wines", "cast vibes", "cast fines", "cast binds", "cast dump", "cast camp", "cast dam", "cast copy")) {
        Add-Clip "negative" $t "none" "none" "none" 0.0 $v 0
    }
    # The recognizer writes "binds" as VINES (measured, both voices): it fires vines in chaos only, like "nice vines".
    # "fines" is usually "FI NES" / "FINES", but once (2026-10-18, David, a chaos pass) "VI VINES": the same, in chaos only.
    Add-Clip "negative" "binds" "none" "none" "any" 0.0 $v 0
    Add-Clip "negative" "fines" "none" "none" "any" 0.0 $v 0
    foreach ($t in @("nice vines", "damp towel", "I need coffee", "coffee break")) {
        $chaos = if ($t -like "*vines*") { "vines" } elseif ($t -like "*damp*") { "damp" } else { "coffee" }
        Add-Clip "negative" $t "none" "none" $chaos 0.4 $v 0
    }
}
# Chicken: the words it can be mistaken for ("kitchen", "chick", "thicken"; "chicken out" is real chatter), and chatter
# that really says it. Nothing may cast in any mode, except that chaos (any spell word anywhere) fires on the real word.
# "check in" is a true hearing of the spell word for Zira ("CHICK CHICKEN", "CAST CHICKEN": measured 2026-10-18, like
# "binds" for vines): bare it casts in chaos only, after the trigger it is a cast. David hears "CHECK IN" / "CHEQUE IN".
foreach ($v in @($v1, $v2)) {
    foreach ($t in @("kitchen", "chick", "thicken", "cast kitchen", "cast thicken")) {
        Add-Clip "negative" $t "none" "none" "none" 0.0 $v 0
    }
    Add-Clip "negative" "check in" "none" "none" "any" 0.0 $v 0
    Add-Clip "negative" "cast check in" "any" "any" "any" 0.0 $v 0
    foreach ($t in @("don't chicken out", "watch out for the chicken")) {
        Add-Clip "negative" $t "none" "none" "chicken" 0.4 $v 0
    }
}
# Hero names (Rebar, Gasket, Wick) may become voice callsigns, so they must never cast by themselves.
# "gasket" is the worrying one: it starts like the trigger "cast". Nothing may cast in strict or loose
# (loose needs the trigger word); "Gasket heal me" may cast heal in chaos (any spell word anywhere).
foreach ($v in @($v1, $v2)) {
    Add-Clip "negative" "Gasket heal me"  "none" "none" "any"  0.0 $v 0
    Add-Clip "negative" "Rebar watch out" "none" "none" "none" 0.0 $v 0
    Add-Clip "negative" "Wick come here"  "none" "none" "none" 0.0 $v 0
    foreach ($t in @("gasket", "rebar", "wick")) {
        Add-Clip "negative" $t "none" "none" "none" 0.0 $v 0
    }
}
# Tentacle sound-alikes in the other voice too (a different recognizer error profile).
foreach ($t in @("attack", "ten tickets", "testicles", "I can't tackle this")) {
    Add-Clip "negative" $t "none" "none" "none" 0.0 $v2 0
}
Add-Clip "negative" "I need a heal over here"        "none" "none" "heal"     0.4 $v2 0
Add-Clip "negative" "nice fireball"                  "none" "none" "fireball" 0.4 $v2 0
Add-Clip "negative" "corner"                         "none" "corn" "corn"     0.4 $v2 0
Add-Clip "negative" "of course"                      "none" "none" "none"     0.0 $v2 0

$rows = New-Object System.Collections.Generic.List[string]
$rows.Add("file,group,strict,loose,chaos,min_power,voice,rate,text")
$n = 0
foreach ($c in $clips) {
    $vshort = if ($c.voice -eq $v1) { "a" } else { "b" }
    $name = "{0}_{1}_{2}{3}.wav" -f $c.group, (Slug $c.text), $vshort, $c.rate
    Render $c.text (Join-Path $OutDir $name) $c.voice $c.rate
    $rows.Add(("{0},{1},{2},{3},{4},{5},{6},{7},""{8}""" -f $name, $c.group, $c.strict, $c.loose, $c.chaos, $c.min_power, $c.voice, $c.rate, $c.text))
    $n++
}
Set-Content -Path (Join-Path $OutDir "manifest.csv") -Value $rows -Encoding utf8

# --- trigger-word clips (triggers.csv) ---------------------------------------
$tdir = Join-Path $OutDir "triggers"
New-Item -ItemType Directory -Force -Path $tdir | Out-Null
$trows = New-Object System.Collections.Generic.List[string]
$trows.Add("file,trigger,kind,spell,voice,text")
function Add-Trig([string]$trigger, [string]$kind, [string]$spell, [string]$voice, [string]$text) {
    $vs = if ($voice -eq $v1) { "a" } else { "b" }
    $name = "{0}_{1}_{2}_{3}.wav" -f $trigger, $kind, (Slug $text), $vs
    Render $text (Join-Path $tdir $name) $voice 0
    $trows.Add(("{0},{1},{2},{3},{4},""{5}""" -f $name, $trigger, $kind, $spell, $voice, $text))
}
foreach ($t in $Triggers) {
    foreach ($id in $spells.Keys) {
        # "summon teeth" is heard as one word, SEVENTEENTH, every time (measured): a known bad pairing that
        # would eat the trigger's whole miss budget. It is noted in the Incantation header instead.
        if ($t -eq "summon" -and $id -eq "teeth") { continue }
        Add-Trig $t "pos" $id $v1 "$t $($spells[$id])"
    }
    Add-Trig $t "pos" "heal" $v2 "$t heal"
    Add-Trig $t "pos" "fireball" $v2 "$t fireball"
    Add-Trig $t "neg" "none" $v1 $t
    Add-Trig $t "neg" "none" $v1 "I like the $t"
    Add-Trig $t "neg" "none" $v2 "what a $t"
    # Saying the default trigger while another is selected must not cast.
    if ($t -ne "cast") { Add-Trig $t "cross" "none" $v1 "cast heal" }
}
Set-Content -Path (Join-Path $OutDir "triggers.csv") -Value $trows -Encoding utf8

Write-Output "wrote $n clips + manifest.csv, $($trows.Count - 1) trigger clips + triggers.csv to $OutDir (voices: $($Voices -join ', '))"
