# UI theme options: menu style and main-menu backdrop

Status: **options pass, 2026-10-17. Nothing here is committed.** The options below were prototypes; the two
backdrops the user picked (the garage for the main menu, the site diorama for the job board) were built for
real, see "As built" at the end of section 4. Later the same day the user dropped the diorama: the job board uses
the garage too. The storefront stays a prototype in the lab.

What to look at:
- `tools/theme_options/menus.html`: four menu styles, each drawn on five screens. It is self-contained,
  so open it from disk.
- `tools/theme_options/backdrops.html`: three backdrop prototypes captured in engine.
- `scenes/backdrop_lab.tscn` and `scripts/ui/backdrop_options/`: the lab behind those captures (it now shows the
  real garage, plus the storefront prototype; the diorama was deleted).
- `tools/theme_options/shots/`: the raw PNGs.

The question from the user: the concept's clipboard looks great, but will it fit all of our menus,
including future business screens such as shopping between contracts and cosmetics? And what should
the backdrop be?

## 1. Screen inventory

| Screen | Exists | Content | Density | Input needs |
|---|---|---|---|---|
| Main menu | yes (`main_menu.gd`) | 4 buttons (Start, Voice setup, Settings, Quit) | low | list focus |
| Voice setup | yes (`voice_setup_screen.gd`) | live mic meter in dB, min-voice slider, cast-word picker (8 + custom LineEdit), strictness (3) with help text, live "Try it" readout | **high, live** | slider, dropdown, text entry |
| Settings | yes (`settings_screen.gd`) | volume slider, fullscreen toggle, window size, debug-panel toggle | medium | slider, toggle, dropdown |
| Pause | yes (`pause_menu.gd`) | Resume, Abandon contract, Main menu | low | list focus |
| Job board | yes (`job_board.gd`) | 3 offers: client, site, story, objectives with $, floors, danger, property warning, value | **high, comparative** | 1-3, left/right |
| Spell picker | yes (`spell_picker.gd`) | requisition 2 of 9 licenses, a spec sheet for the focused one | medium | multi-select |
| Elevator | yes (`elevator_menu.gd`) | floor N of 3, payout so far, damage so far, Go down or Cash out | low | 2 choices |
| Invoice | yes (`invoice_screen.gd`) | already a real paper invoice: letterhead, line items, deductions, net, stars | high | continue |
| HUD | yes (`hud.gd`, `objective_tracker.gd`, damage ticker) | HP, spell cards, toasts, mic meter, objectives, "-$1,200 wine rack" | in play | none (must not block play) |
| Voice debug panel | yes (dev) | heard text, matches, levels | dev | none |
| Supply-house shop | planned | catalog of licenses, components, rig and van upgrades; qty; total; funds | **high, scrolling** | list, qty, buy |
| Cosmetics | planned | van paint and decals, uniforms, hats, per crew member | medium, visual | swatch grid, preview |
| Crew / locker | planned | per-hero card: kit, uniform, stats, stars | medium | tabs per hero |
| Upgrades / licenses | planned | license register, rig perks | medium | list |
| Contract history | planned | past invoices and receipts | high, scrolling | list, open one |
| Co-op lobby | planned | players, ready state, host, voice check per player | medium, live | ready toggles |

The hard cases are the **dense live screens** (voice setup, settings), the **comparison screen**
(job board), and the **long scrolling lists** (shop, history). A style that only suits a short list,
like the bare clipboard, breaks down on exactly these.

## 2. The four options

Each option maps every screen to one printed object. The mockups show the main menu, job board, shop,
cosmetics and settings, using real Cast copy: clients and stories from `ClientArchetype`, the
$3,000/$10,000/$10 objective pay, Kevin the espresso machine, and corn at $12 with no explanation.

### A. Desk of objects
Each screen gets the object that fits it best:
- the main menu is the clipboard;
- the job board is a corkboard of pinned tickets with sticky notes;
- the shop is a mail-order catalog page with an order blank;
- cosmetics are paint-swatch fans, a uniform catalog and polaroids;
- settings is an equipment checklist;
- the other screens are a torn notepad, ID cards, framed licenses, a shoebox of receipts, and a punch
  clock for the lobby.

| Pros | Cons |
|---|---|
| The most charm per screen; the closest to the concept | Every screen is bespoke art and layout, so every new screen costs the most |
| Objects explain themselves: a catalog is a shop | Focus looks different on every object, which is hard on controllers |
| Strong for screenshots and the store page | Rotated, layered pieces fight scrolling and 800p (Steam Deck) readability |
| | Handwriting carrying real values is hard to read and to localize. The corkboard hides the backdrop |

### B. Carbon-copy forms (recommended)
Every screen is a pre-printed trade form:
- a numbered "FORM 27-B" header block;
- a ruled grid of boxed fields in one spot ink (deep teal);
- typed values (Courier Prime);
- red rubber stamps and grease-pencil marks.

Each screen family has a carbon color: white for the office, canary for dispatch, pink for the shop,
goldenrod for settings and green for the crew. The concept's clipboard is kept as the **holder** for
short-list screens (main, pause, elevator), carrying a form with "classified ad" boxes at the bottom.
The job board is a 3-part tear-off set: three offers, the same fields in the same places, so they can
be compared across columns. Focus is always the same yellow highlighter band plus a red tick.

| Screen | Form |
|---|---|
| Main / pause | FORM 27-B Work order, on the clipboard |
| Voice setup | FORM 7 Rig calibration (the live meter sits in a boxed field) |
| Job board | FORM 12 Dispatch offers, a 3-part tear-off set |
| Spell picker | FORM 15 License requisition (15-S Supplemental requisition; 15-A Spec sheet beside it) |
| Elevator | "While you were out" slip |
| Invoice | FORM 99 (the existing invoice, aligned to the grid) |
| Shop | FORM 40 Supply requisition |
| Cosmetics / crew | FORM 9 Vehicle and uniform spec sheet, union ID cards clipped on |
| History | carbon receipt book |
| Co-op lobby | time card, one punch row per player |
| Settings | FORM 3 Equipment settings |
| HUD accents | damage ticker as receipt tape; objective tracker as a work-order slip |

| Pros | Cons |
|---|---|
| Rows, cells, tables and checkboxes map directly onto Containers and StyleBoxes; one `Theme` covers about 90% | Less whimsical; the charm must come from copy, stamps and colors |
| Dense and live screens are what forms are for | Can drift toward "spreadsheet" if the ink and type rules aren't kept strict |
| One focus language for mouse, keyboard and controller | Bright paper over a dark scene: keep it warm off-white, and leave the right side to the backdrop |
| Scrolls cleanly; the invoice is already in this family | |

### C. Dispatch printout
The dispatch rig prints everything on green-bar tractor-feed paper from a dot-matrix printer bezel:
- focus is a yellow highlighter swipe;
- job offers are three torn-off printouts;
- the shop is a parts list;
- cosmetics are a color-code listing with chips stapled on.

| Pros | Cons |
|---|---|
| Lists scroll for free, because the paper just feeds | Cold and "computer"; little trade business, little magic |
| One monospace font and one paper style: the cheapest to build | Pixel fonts at small sizes hurt the Deck, and their CJK/Cyrillic coverage is poor |
| "The platform printed it" suits the gig-app satire | No color, so cosmetics need stapled props. Monospace widths blow up in German |

### D. Mail-order flyer
Two-color newsprint: spot red and black on cream, halftones, starbursts, dashed coupons and slab
headlines.
- The main menu is a yellow-pages ad with the menu items as coupons.
- The job board is the classifieds page.
- The shop is a sale flyer, and cosmetics are a "van wraps, as seen on cable" page.

| Pros | Cons |
|---|---|
| The funniest and most branded; great for the shop and cosmetics | Busy: bursts and halftones compete with content |
| Flat print with no layering is cheap to render | Settings and voice setup have no natural flyer form |
| | Prose ads compare worse than fixed fields; the joke wears thin as an everyday frame |

### Strain summary

| | A Objects | B Forms | C Printout | D Flyer |
|---|---|---|---|---|
| Scrolling lists | poor (page turns) | good | **best** | fair |
| Dense settings / voice | fair | **best** | good | poor |
| Controller and keyboard focus | poor (per-object) | **best** (one language) | good | good |
| 1080p / Deck readability | fair (rotations, handwriting) | good | fair (pixel font) | fair (busy) |
| Localization | poor (handwriting fonts) | good (with Noto fallbacks) | poor (mono widths, pixel font) | fair |
| Build speed in Godot | slow (bespoke art) | **fast** (Theme + 6 components) | **fast** | medium |
| Charm | **highest** | medium | medium | high |

## 3. Recommendation: B, carbon-copy forms, held on the clipboard

It is the only option that holds up on every screen we have and every screen we plan:
- short lists, dense settings and live voice meters;
- side-by-side job offers;
- long shop tables;
- the existing invoice and a co-op time card.

It does that with one `Theme` and a handful of reusable components, and it keeps the concept's
clipboard and classified ads on the main menu. The other options contribute accents only, never the
frame:
- D's price bursts on shop and cosmetic items;
- A's sticky notes for crew banter;
- C's receipt tape for the in-game damage ticker.

### Build plan
1. **Fonts.** None are downloaded yet. All are free to ship:
   - Barlow Condensed (OFL) for printed labels;
   - Courier Prime (OFL) for typed values;
   - Black Ops One (OFL) for stamps;
   - Permanent Marker (Apache 2.0) or Caveat (OFL) for grease-pencil marks, used for decoration only and
     never for values;
   - Noto Sans and Noto Sans CJK (OFL) as `FontVariation` fallbacks.
2. **`res://ui/theme/forms.tres`**, a `Theme` with:
   - paper `StyleBoxTexture` panels (a 9-slice of one noise and fiber texture, tinted per carbon by
     `modulate` or a type variation);
   - ruled `StyleBoxFlat` cells, with a 1.5 px teal border on one or two sides only;
   - Button `focus` and `hover` as the highlighter band (a semi-transparent yellow StyleBoxFlat with
     skewed ends) plus a tick icon;
   - LineEdit, OptionButton and CheckBox in the boxed-field style;
   - HSlider as a box scale (grabber hidden, `grabber_area` drawn as filled boxes);
   - type variations `FormLabel`, `FormValue`, `FormTitle`, `Stamp`.

   It replaces `MenuStyle`'s per-control overrides.
3. **Components** (`scripts/ui/forms/`, plain Controls that work headless):
   - `FormSheet`: a PanelContainer with the header block (form number, title, company line, corner box)
     and a carbon color;
   - `FormRow`: a numbered row with a checkbox, a typed value and a hint, built on a Button so focus is
     native;
   - `FormField`: a label plus any control, in a ruled row;
   - `FormTable`: an ItemList or Tree styled as ruled columns, for the shop and history;
   - `TearOffSet`: N tickets with perforations, for the job board;
   - `Clipboard`: a frame holding a FormSheet, with a slight tilt only on the frame;
   - `Stamp`: a rotated label using a mask texture.
4. **Migration order:** main menu and pause (clipboard), then settings, job board, voice setup,
   elevator, spell picker, and the invoice re-aligned to the grid. New screens (shop, cosmetics, crew,
   lobby) are built straight on the components.
5. **Rules:**
   - Paper is warm off-white (never pure white) and at most about 40% of the screen on the main menu,
     so the backdrop shows.
   - Minimum 22 px at 1080p, which is about 16 px on the Deck's 800p.
   - Rotation only on frames, never on text-heavy sheets.
   - Every value is typed; handwriting is decoration only.

## 4. Backdrops

Prototypes, built from existing models only, in `scenes/backdrop_lab.tscn`. Run it with
`--option garage|diorama|storefront` (the diorama has since been deleted), plus `--mood`, `--site`, `--van real|stand-in`, `--clean` and
`--shot <png> --shot-after 2`. The van uses the van agent's `VanModel` when its script loads, otherwise
a stand-in block van. All the captures except `garage_realvan_clean.png` use the stand-in.

| Option | What it is | Cost | Changes by context | Verdict |
|---|---|---|---|---|
| **The garage** | The concept, built: stone-block garage over the hex floor, the van on its arrival circle with the side door open, the crew idling, torches, dusty grate shafts, a hellgate glowing through a breach in the back wall, signs ("24/7 EMERGENCY DISPATCH! WE FIX YOUR HEXES OR IT'S FREE!", "DAYS SINCE LAST CORN INCIDENT: 0", neon "CAST / WE FIX HEXES" with a dead H) | Low: everything exists except a wall kit piece, a torch prop, the van (in progress) and some crew lean/sit idles | Time of day (dawn/night prototyped); the last contract's results ("after a bad job": scorch, corn, smoke, prototyped); the real corn counter; live van paint, decals and uniforms; bought items on shelves | **Main menu.** It is the business and a persistent home, and it doubles as the cosmetics preview |
| **Site diorama** | The highlighted offer's site as a miniature on the dispatcher's desk: a cut-out hex chunk on a swaying brass turntable with the client's priced props and tags, the gate, demons, a cowering employee and the tiny crew, under depth of field | Very low: all existing models; the real version can run `SiteBuilder` on a small radius from the offer's seed | Per offer: client, origin theme, pest and props (prepper, villain and founder prototyped); danger; the wreck after a contract | **Job board.** It makes the text concrete. Too crew-less for the main menu |
| **The storefront** | The business at night: a cinder-block unit with the roll-up door half open on a lit shop, rooftop neon CAST, a 1-800-LOW-MANA board, the van in a "RESERVED: VAN" pentagram bay, a sodium lamp, and a manhole leaking red behind cones | Highest new geometry (facade, sign, lamp, skyline), and an outdoor look the game never uses | Weather (rain prototyped); OPEN/CLOSED; window display | Title or attract screen, or the supply-house backdrop |
| Dispatch office (not built) | A corkboard, radio and coffee, with a window onto the garage | High; diegetic UI is hard to read | | Its parts are folded into the garage and the diorama |
| Van interior (not built) | Looking out the back doors at a gate site | Medium (interior to camera quality) | | Loading / drop-in screen between the job board and floor 1 |

**Recommendation:**
- The garage behind the main menu, pause, settings, cosmetics and crew screens. The cosmetics screen
  moves the camera to the van.
- ~~The site diorama behind the job board.~~ Dropped 2026-10-17: the job board uses the garage.
- The storefront saved for the title card or the shop.

Notes from the captures:
- The bright hex seams under a menu are loud, so frame the floor low or dim the near seams.
- The toon shader floors brightness, so night needs a color grade (`adjustment_brightness`), not only
  fewer lights.
- Paper menus sit best on the left third, with the crew and van at screen center-right.

### As built (2026-10-17): the garage (and the diorama, dropped)

2026-10-17: the user dropped the diorama; the job board uses the garage backdrop.

**The garage is the main menu's backdrop** (`scripts/ui/menu_backdrop.gd`, `MenuBackdrop`; main menu, voice setup
and settings share it, as before). Kit pieces (torches, signs, neon, light shafts, motes) live in
`scripts/ui/backdrops/backdrop_kit.gd`.
- **Scene:** Wick, Gasket and Rebar around the real `VanModel` (side door open, violet cargo glow) on a `VanCircle`
  chalk pentagram; torches, a ceiling-grate spot with dusty shafts, the hellgate through the breach with hazard tape,
  the dispatch sign, "DAYS SINCE LAST CORN INCIDENT: 0" and the neon CAST with its dead H. The camera orbits its focus
  by about 3 degrees (a 52 s sway).
- **Crew:** the player's hero stands in FRONT, large and three-quarter to the camera, left of the van's open cargo door;
  the other two stand back (one by the cab with a tool, one beyond the nose) in a loose triangle, all right of the
  clipboard. `featured_hero` / `set_featured_hero(id)` (wick, gasket or rebar) re-poses the three in place; the default is
  `MenuBackdrop.PLAYER_HERO` (Wick, because game.gd hard-codes Wick; a character select should call the setter).
  Dev flag `--backdrop-hero wick|gasket|rebar`. The camera sits higher (about 5 units, looking down a little more) and
  drifts by about 3 degrees.
- **Composition:** the picture is slid right with `Camera3D.h_offset` (`FRAME_SHIFT`) so the van and crew sit in the
  right 60% of a 16:9 screen, clear of the clipboard (which is about 40% wide, tabs included).
- **Seams:** `HexMapView` has three new fields, `seam_gain`, `seam_near_gain` and `seam_near_range`. Defaults keep the
  game's look; the garage uses 0.35, 0.2 and 18 so the foreground floor is calm and the far floor keeps a glow.
- **Night is a grade**, not only fewer lights: `Environment` brightness, contrast and saturation, a blue ambient, a
  moonlight key, and an `adjustment_color_correction` 1-D tone curve. After is desaturated and warm.
- **Moods and how one is picked** (`MenuBackdrop.pick_mood(args, hour)`, in this order):
  1. `--backdrop-mood dawn|night|after` (a menu flag, so it does not skip the menu, like `--backdrop-hero`);
  2. `after` when `LastContract.was_bad()`: the last finished contract's invoice had damages of at least 50% of the
     contract value (`LastContract.AFTER_DAMAGE_RATIO`) or the whole crew was incapacitated. `Game._end_contract`
     records it (`LastContract.record(invoice)`); it lives for the process only, nothing is saved;
  3. `night` when the local clock is 20:00 to 04:59;
  4. else `dawn`.
  `set_mood()` switches live. `corn_days` drives the sign; nothing counts corn incidents yet, so it stays 0.
- **Cost:** 7 positional lights (grate spot, work light, two torches, breach, the van's cargo glow, the gate) and no
  shadows; about 236 draw calls and 58k primitives in the lab at 1600x900, against about 311 draw calls and 242k
  primitives on a game floor. Nothing allocates per frame (tested).

**The job board uses the garage too.** The diorama was built, then dropped by the user the same day and its code
deleted (`JobBoardDiorama`: a miniature of the highlighted offer's site on a turntable; the FORM 12 board covered most
of the screen, so it was nearly hidden).
- `Game._show_board` adds a `MenuBackdrop` named "Backdrop" and frees it when a job is picked. The main menu's own
  backdrop is not reused: Start changes scene, which frees the menu scene and its backdrop before the game scene
  builds the board, so the board gets a fresh one. It picks the same mood and hero as the menu on its own
  (`pick_mood`, `hero_from_args`; `LastContract` and the local clock are process-wide, so they agree).
- `JobBoard.backdrop_behind` (set by the game) turns the opaque dark shade into a light dim (alpha 0.22); with it
  false, the board is a plain dark screen as before.

Lab: `godot --path . -- --scene res://scenes/backdrop_lab.tscn --option garage|storefront --mood ... --hero ...
--board [--board-seed n] --clean --shot <png>` (`--board` lays the real job board over the garage). Screenshots from this pass are not committed.

### As built (2026-10-17): the carbon-copy forms
Option B is in the game. Every screen in `scripts/ui/` is a form; `MenuStyle` is gone.

**Components** (`scripts/ui/forms/`, plain Controls, all drawn in code so they work headless; sizes are in the
1600x900 canvas units, so 20 is 16 px at 1280x720):
- `FormTheme`: the one place for colours (teal ink `#1f5c63`, typed `#1d1a26`, red `#b3261e`, the six carbons),
  fonts, the shared `Theme` (`FormTheme.theme()`: Label, Button, OptionButton, LineEdit, PopupMenu, scrollbars),
  the generated paper grain, the highlighter band, the grease-pencil tick and X, and small helpers (`label`, `typed`,
  `boxed`, `ad`, `chain` for wrapped Up/Down focus).
- `PaperPanel`: grain tinted by the carbon, drop shadow, optional yellow outline and tear-off perforation.
  `FormSheet` = `PaperPanel` + `FormHeader` (form number, company line and title, copy box, 3 unit rules) + a body.
  `FormSection` = a ruled, captioned section.
- `FormRow` (a real `Button`: number cell, box, typed label, optional description and spell colour bar, printed hint),
  `FormField` (label + any controls, drawing the band when one has focus), `FormCheck` (typed X), `BoxScale`
  (a `Range`: 10 boxes, Left/Right one box, Shift one step, mouse click/drag), `FormStamp`, `FormClipboard` (wood
  board, metal clip, index tabs, 1 degree tilt), `KeyHints` (paper keycaps).
- Signing and reference pages (`form-rules.md` §7): `SignLine` (the ruled line and the red name stamp, shared by the job
  board's Take line and the requisition), `SignRow` (a focusable "Requested by" SignLine: Enter / click signs, inert
  while disabled), `RequisitionLine` (a requisition line item: printed box with the red tick, typed name with its colour
  tag, typed columns; `RequisitionLine.Captions` prints the column heads) and `SpecSheet` (a separate small FormSheet of
  caption-over-typed-value cells that lies beside a form and follows its focus).
- Focus is one language: the mouse grabs focus on hover, so only one thing is ever highlighted, and the focused
  row gets the yellow band plus a red tick (or, on a toggle row, the band alone, with a red X in the box once ticked).
- Back is one language too (`form-rules.md` §6): `FormVoid` (2026-10-18). Esc or a form's back row stamps a red VOID on
  the sheet (each part of the job board's set), holds 0.3 s (`FormVoid.HOLD_S`) with the screen's input blocked, then runs
  that screen's back. Each screen exposes `void_back()`; game.gd and the main menu call it on Esc. The key strips still say
  where Esc goes ("Esc back", "Esc leave the crew"), not VOID. Test seam: `FormVoid.hold_s`; tests wait it out with `TestCase.after_void()`.
- `forms_lab.gd` / `scenes/forms_lab.tscn`: the screenshot lab (see Screenshots below).

**Fonts:** the real OFL files in `assets/fonts/` (Barlow Condensed, Courier Prime, Black Ops One, Caveat variable
at weight 700), each wrapped in a `FontVariation` whose fallback is the Windows `SystemFont` (Bahnschrift, Courier New,
Impact, Segoe Print). Swap fonts in `FormTheme._font()` callers only.

**Screens**
| Screen | Form |
|---|---|
| `MainMenu` | FORM 27-B Work order on a tilted clipboard, left third. Rows Start / Voice setup / Settings / Quit; the office-use box shows the saved cast word, strictness, min voice and the build (`BuildVersion.text()`); three classified ads; a stamp; index tabs (decoration) |
| `VoiceSetupScreen` | FORM 7 Rig calibration: cast word and strictness pickers, the live meter (restyled `MicMeter`), min voice as a `BoxScale`, "Try it" with the HEARD box, spell chips and the type-it field. The mic status sits in the header's copy box |
| `SettingsScreen` | FORM 3 Options (goldenrod): box scale, boxed checks, boxed picker |
| `PauseMenu` | FORM 27-B "On hold" on a clipboard, with the build |
| `JobBoard` | FORM 12 header strip + a 3-part set (white, canary, pink), same fields in the same places. Left/Right (or hover) highlights, Enter or 1-3 takes. No full-screen paper: the garage (`MenuBackdrop`) shows between and around the cards. `backdrop_behind` (set by the game) swaps the opaque dark shade for a light dim |
| `SpellPicker` | FORM 15 License requisition (white) and, for a player joining a job in progress, FORM 15-S Supplemental requisition (canary): one component, two variants. Job # in the copy box; typed Client / Issued to (15-S adds Floor); a line item per spell (box, license, component, cooldown; scrolls past 9); "Limit 2 licenses per crew member, per job."; "Requested by", signed with the red name stamp, then `picked`; the back row. Beside it, FORM 15-A Spec sheet (blue): Say, Component, Cooldown, What it does, for the focused line |
| `ElevatorMenu` | FORM E-1 canary "while you were out" slip with three rows (the old keys 1, 2, Esc work as before) |
| `InvoiceScreen` | FORM 99, same content and logic; the crew debrief is a canary slip (FORM 99-B) with a "Next contract" row |
| `ObjectiveTracker` (HUD) | a small canary work-order slip; the only HUD change |

**Left out:** the shop, crew and cosmetics forms and the clipboard's matching rows (those screens do not exist yet:
the main menu has no dead items); the damage ticker as receipt tape; paper that is rotated other than the clipboard.
A stamp is plain alpha, not multiply: Godot's canvas multiply blend turns every glyph quad into a solid block.

**Notes for the next form:** follow `form-rules.md` (what is printed, typed and marked; what to leave off). Build it with `FormSheet` (pick the carbon), put `FormRow`s or `FormSection`s in `body`,
set `theme = FormTheme.theme()` on the screen root (popups inherit it), call `FormTheme.chain(...)` for focus order and
grab focus on the first control. Keep long text in the typed font only for values; printed descriptions use the
condensed label font. A Button subclass must set `custom_minimum_size`, not override `_get_minimum_size` (the native
Button ignores the script's).

**Screenshots:** the menu screens use the menu's own flags (`--menu-screen main|voice|settings --menu-shot`); the
rest use the lab: `godot --path . --resolution 1280x720 -- --scene res://scenes/forms_lab.tscn --screen
board|picker|picker_s|pause|elevator|elevator_last|invoice|tracker --shot x --lab-shot <abs.png> [--lab-focus n]`
(the requisition: `--lab-picks n` ticks the first n lines, `--lab-sign` stamps "Requested by" and holds, `--lab-card i`
focuses line i, `--lab-fake n` offers n made-up spells). The `--shot x`
only stops `Boot` from changing the window size. Add `--lab-void` (lab) or `--menu-void` (menu sub-screens) to void the
screen just before the shot and hold the VOID stamp. Tests: `tests/test_forms.gd`, `tests/test_form_void.gd`.

## 5. Files
- `tools/theme_options/menus.html`, `tools/theme_options/backdrops.html`: self-contained mockups.
  `embed_images.py` re-embeds the PNGs after re-rendering.
- `tools/theme_options/shots/*.png`:
  - `garage_*`, `diorama_*` (the dropped diorama), `storefront_*`: lab captures; `_clean` versions have no overlay;
  - `crop_*`: crew crops used in the mockups.
- The real backdrop: `scripts/ui/menu_backdrop.gd` (`MenuBackdrop`, behind the menu and the job board), `scripts/ui/backdrops/last_contract.gd` (`LastContract`) and
  `scripts/ui/backdrops/backdrop_kit.gd` (torches, paper signs, neon, light shafts, motes). Test:
  `tests/test_menu_backdrops.gd`.
- The forms: `scripts/ui/forms/` and `scenes/forms_lab.tscn` (see "As built: the carbon-copy forms").
- `scenes/backdrop_lab.tscn`, `scripts/ui/backdrop_options/` (the lab, kept working):
  - `backdrop_lab.gd`, the lab: the garage is the real class above (`--board` adds the real job board);
  - `storefront_backdrop.gd`, the title-screen prototype (not used by the game yet);
  - `van_stand_in.gd`: the stand-in van (only the storefront uses it now).
  The garage prototype that lived here was replaced by the real class and deleted (the diorama too). The `garage_*` and
  `diorama_*` PNGs under `tools/theme_options/shots/` are still the prototype captures.

  All of it passes `test_net_contract`: no global random, no networking, no actors.
