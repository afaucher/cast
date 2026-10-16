# Cast (POC)

A co-op exploration game where you fight with spoken spells, aiming for "Overcooked with magic".
You explore a procedural hex dungeon with heights and say spells out loud to fight.
Speech recognition runs on-device (the sherpa-onnx `WordListener` extension from Hero-Reader).

## Play

- **Exe:** `build\windows\Cast.exe` (made by `.\build.ps1`). Keep the DLLs and `Cast.pck` beside it.
- **From source:** `.\run.ps1`, which accepts `-- --seed 42 --spells heal,corn --no-mic`.

| Input | Action |
|---|---|
| WASD | Move. You can step up 1 level and climb 2 (slowly); 3 is a wall. Stairs bridge big gaps |
| Mouse | Aim. Spells and the bolt land at the white ring; it turns green when it locks onto a teammate |
| LMB / RMB | Sword / bolt (the bolt is weaker) |
| **Say "cast heal"** etc. | Cast a spell in your slots. Fumbles weaken it or fizzle it |
| 1 / 2 | Keyboard fallback for spell slots |
| Enter | Type an incantation instead of speaking |
| F1 | Toggle the debug side panel (what the mic hears and what the game did) |
| F5 | New dungeon |

**Spells** (pick 2 at the start): heal, fireball, armor, and corn, which hits everyone, you included.
All of them land where you aim, so to heal a friend you point at them, and you don't want to say "corn" while doing it.

**Voice settings** are in the debug panel. The trigger word is "cast" by default; the other
choices are magic, pickle, conjure, invoke, summon, presto, or a custom word. Strictness is
strict, loose (the default) or chaos. Accidental casts are a feature. Every utterance is
logged to `%APPDATA%\Godot\app_userdata\Cast\voice_log.csv`.

## Develop

```powershell
.\test_runner.ps1 -TestAll     # all headless tests (the voice audio tests take ~2.5 min)
.\build.ps1                    # tests, then export build\windows\Cast.exe
```

- **Docs:** contracts are in `docs/ARCHITECTURE.md`, design is in `docs/design/` (start with `north-star.md`).
- **Not committed:** the speech DLLs, the model and the pronunciation dictionary. Copy them from
  `..\Hero-Reader` (see `.gitignore`), together with the Godot 4.7 export templates in `build\deps`.
