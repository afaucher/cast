# Form rules

Every screen in Cast is a trade form from Cast Budget Sorcery (see `ui-theme-options.md` for the system and
`scripts/ui/forms/` for the parts). These rules keep the forms believable as real paperwork and consistent with
each other. They come from the user's review of the main menu, job board, invoice, notes and join screens
(2026-10-17/18). When a rule and a quick fix disagree, the rule wins; when a new case doesn't fit a rule, ask.

Forms built before these rules may still break some of them (the invoice's large green totals, number keys printed on
the elevator slip and the back rows, the settings and voice setup forms). Bring a form into line when you next
touch it.

## 1. Pick the right form
1. **Start from the paperwork, not the screen.** Ask what a real trade business would hand someone at this moment:
   a work order, a dispatch sheet, a license, an invoice, a requisition, a phone slip. The screen's premise comes from
   that document.
2. **A new situation is a new form, not a relabelled one.** Joining a job in progress is not a fresh license
   requisition (FORM 15): it is FORM 15-S, a supplemental requisition for the ongoing job. Use a variant number (`15-S`, `27-C`,
   `99-B`) for a sibling of an existing form.
3. **Every form has a number and a carbon.** The carbon follows the family (`FormTheme.CARBONS`): white for the office,
   canary for dispatch and the job site, pink for the shop, gold for settings, green for the crew. Add the form to the
   inventory in `ui-theme-options.md`.
4. **The title is the document's name** ("Work order", "Supplemental requisition"), never an instruction.

## 2. Printed, typed, marked
A real form has three layers, made by three different hands. Keep them apart.

| Layer | Who made it | What it is | How it looks |
|---|---|---|---|
| **Printed** | the print shop, before the job | captions, rules, boxes, the company line, anything identical on every copy | teal spot ink, condensed caps (`FormTheme.label`, `small`) |
| **Typed** | the office, for this copy | every value: names, numbers, roles, places, money, times, the client's text | **one typewriter** (`FormTheme.typed`, Courier Prime) |
| **Marked** | the player | ticks, checks, crossings-out, the signature | red grease pencil and the red name stamp |

5. **Anything that varies per copy is typed.** Client, role, company, site, floor, job number, money, story text,
   warnings. That holds inside a printed caption too: "JOB #" is printed, "08137-PR" is typed.
6. **Printed text never contains a value.** "Damages are deducted, up to the contract value", not "up to $49,600".
   If a sentence needs a number, the number goes in a typed field.
7. **One typewriter per form.** Same face, weight, size and ribbon (near-black `FormTheme.TYPED`) for every typed
   value. No bigger type for emphasis, no green money, no red typing. Emphasis comes from position, boxes and rules.
8. **Every player mark is the red grease pencil** (`FormTheme.GREASE`, `draw_tick`, `draw_x`): checkboxes, choices,
   ratings. A rating is printed empty boxes with hand-drawn red checks in them, never filled blocks.
9. **The player signs with a red rubber name stamp** (their name in caps, double border, a slight tilt), not a
   handwriting font.
10. **Warnings: the box and caption are red, the typed text inside stays black.**
11. **Handwriting is only for in-world authors** (the pre-outbreak notes on a site). It is never used for a value the
   game shows the player.

## 3. Say less
12. **Only print what is true for every copy and useful to the reader.** No "3 floors" when every job has three, no
   "PART 2 · CANARY" stub, nothing about a mechanic that is about to change.
13. **Don't explain the game on the paper.** No reassurance or tutorial lines ("Leaving early always works", "Pay never
   goes below $0", "The AI covers your seat until this is approved"). A form records; the game teaches by playing.
14. **A hint must add information.** "Voice setup · "cast" · loose" earns its hint; "Quit · clock out" restates the row.
   When in doubt, leave the hint off.
15. **No key bindings on the paper.** No "[1]", "[E]" or "press Enter" printed or typed on a form. Keys live in the
   paper keycaps (`KeyHints`) outside the sheet. Selecting by mouse, arrows and Enter works everywhere anyway.
16. **Short lines.** A printed line fits on one line at 1280x720. If it wraps, cut words; don't shrink the type or let
   it wrap. Typed running text (a story, a warning) may wrap inside its box; a typed single-line field clips. A typed objective or client line
   is running text too: it wraps onto a second line (the row grows, the second line indents like the first), never clips
   (`tests/test_objective_wrap.gd`).
17. **No in-jokes as filler.** A joke that doesn't belong to the form's purpose goes (the "Lost: shark" ad). The humour
   lives in the content (the client's warning, the story), in the company's voice.

## 4. The company's voice
18. **Company:** Cast Budget Sorcery. Tagline: "Licensed Budget Sorcery". Motto: "IN. OUT. INVOICED." Phone:
   1-800-LOW-MANA. License: LBS-0427. Use these; don't invent a second company or a new slogan per screen.
19. **The foot of a form is what a business prints there:** its motto plus one sales line or one reminder to staff.
   Not a row of unrelated classified ads.
20. **Dry trade tone.** Plain words a dispatcher would use. Labels are nouns ("Client", "Site", "Danger", "Take").
   Avoid bracketed asides ("(intercepted mail)") and jargon the reader must decode ("per-diem").
21. **Notes found on a site are pre-outbreak documents** written by the client's people for each other. No "Note:"
   prefix, no mention of who found them, nothing about them on the invoice.
22. **Never justify corn.**

## 5. Layout and fit
23. **Parallel copies share one layout.** The three job-board parts have the same fields in the same places, so they
   compare across columns. Do the same for any set of copies.
24. **No scrolling on a document.** It fits 1600x900 canvas units (1280x720) and 1600x1000 (the Steam Deck). A long
   form folds its rows (like FORM 99's `fit_rows`) rather than scroll. Only a catalog (the license grid) may scroll.
25. **Text sizes:** at least 22 px at 1080p (`ui-theme-options.md`, rules). Rotation only on frames, stamps and
   signatures, never on a text-heavy sheet.
26. **Focus is one language:** the yellow highlighter band plus the red tick, the same on every form.

## 6. Back is VOID
27. **Esc voids the form you are on.** A big red VOID stamp lands across the sheet, holds a moment, and the game goes
   back (to the board, out of the crew, out of the menu: whatever "back" means on that screen). The same on every
   form; the main menu has nothing to void.
28. **Open visual item (user, 2026-10-18): the clickable equivalent of VOID** so a mouse or controller player can
   always find it. Options on the table: (A) the Esc keycap in the key strip under every form, labelled VOID and
   clickable, off the paper; (B) a rubber-stamp prop at a fixed screen corner that voids when clicked. Undecided.
   Until then, existing back rows stay and void the form the same way Esc does.

**As built (2026-10-18):** one helper, `FormVoid.void_and(screen, action, over)` (`scripts/ui/forms/form_void.gd`). Every
form screen's `void_back()` calls it, from Esc and from its back row alike: a FormStamp reading VOID (132 px, -9 degrees)
lands on the sheet in 0.1 s (scale 1.3 to 1, fading in), and the screen's back runs once `FormVoid.HOLD_S` (0.3 s) after
the press. While it holds, every key and click on that screen stops at the void. The job board stamps each of its three
parts. Key strips still say where Esc goes ("Esc back", "Esc leave the crew"), not VOID. Screens: job board, license requisition (15 and 15-S), voice setup (7), settings (3), pause
(27-B, back = resume), elevator (E-1, stay), van (E-2, cancel), crew confirm (27-B, stay), invite (27-C, stay), clocking
in (12-C, leave the crew). The invoice has no back. Test: `tests/test_form_void.gd`.

## 7. Submitting and reference pages
As built on the license requisition (FORM 15 / 15-S / 15-A, user, 2026-10-18).

29. **Submitting is signing.** A form the player submits ends in a printed signature line ("Requested by ______", the
   job board's "Take ______"), never a GO / Start / Submit row. It is inert until the form is complete. Enter or a click
   on it stamps the player's name in red (rule 9; one stamp everywhere: `SignLine.draw_stamp`, and `SignRow` for a line
   you can focus), the stamp holds a moment (0.6 s) so it is seen, and then the form goes in. While it holds nothing on
   the form changes and it can't be voided. The name comes from `JobBoard.signer_name()`.
30. **The marks are the record.** Don't echo the player's marks back as state copy: no "Picks 2 / 2" box, no "your
   picks" list, no "Enter to tick" line. A limit the paperwork imposes is one printed rule, once ("Limit 2 licenses
   per crew member, per job.").
31. **A catalog is line items.** One ruled line per item: a printed box for the red tick, the item's name, and only the
   columns a buyer would compare (component, cooldown), all typed. No key numbers on the lines (rule 15).
32. **Reference is a separate page.** What the reader needs about the item in focus (how to say it, what it does) goes
   on its own small sheet lying beside the form: a `SpecSheet` with its own number (`15-A`: the form's number plus a
   letter), header and carbon, a little lower than the form, never a panel inside it. It swaps to the line that has
   focus. Both pages together fit the canvas (rule 24); VOID stamps the form, not the reference page.

## 8. Before shipping a form
- Build it from `FormSheet` / `FormRow` / `FormField` with `theme = FormTheme.theme()`; no one-off colours or fonts.
- Read it as the clerk who typed it: is every variable typed, every caption printed, every player mark red?
- Read it as the player: is there any line you could delete without losing anything? Delete it.
- Add a test that it fits 1280x720 (see `tests/test_license_checkout.gd`, `test_forms.gd`) and take a screenshot at
  1920x1080 for review.
