# Results: ink screen of PHerc0257 and PHerc0813 (negative)

Screened from 2026-10-14 to 2026-10-22 with the method in [METHOD.md](METHOD.md). The area is the true 3D mesh area (see
[FAILURE_CASES.md §1](FAILURE_CASES.md#1-spiral-fitting-tifxyz-area-and-scale)).

| scroll | z band | fit: satisfied tracks | windings | area (cm²) | sheet support ≥ 0.85 | screened: windings / cm² | rows of letters |
|---|---|---|---|---|---|---|---|
| PHerc0257 | 9000-10000 | 12.67 % | 120 | 1,052 | 84 | 82 / 547 | none |
| PHerc0257 | 10000-11000 | 15.69 % | 120 | 1,023 | 81 | 82 / 523 | none |
| PHerc0257 | 11000-12000 | 15.49 % | 120 | 1,024 | 64 | 80 / 500 | none |
| PHerc0257 | 12000-13000 | 15.10 % | 120 | 1,095 | 79 | 52 / 259 | none |
| PHerc0813 | 7000-8000 | 12.06 % | 120 | 1,156 | 78 | 78 / 533 | none |
| PHerc0813 | 8000-9000 | 12.18 % | 120 | 1,171 | 71 | 71 / 563 | none |
| PHerc0813 | 9000-10000 | 11.25 % | 120 | 1,244 | 77 | 77 / 734 | none |
| PHerc0813 | 10000-11000 | 11.98 % | 120 | 1,339 | 69 | 35 / 307 | none |
| **total** | | | **960** | **9,103** | **603** | **557 / 3,966** | **none** |

Screened windings: PHerc0257 z9000 and z10000 w010-w090 + w100, z11000 w010-w089, z12000 w010-w061; PHerc0813
z7000 w010-w087, z8000 w020-w090, z9000 w025-w028 + w030-w102, z10000 w029-w063. PHerc0257 was screened by winding
range before the sheet-support rule existed, so 22 of its screened windings are below 0.85 support; PHerc0813 was
screened by the rule. **Not screened yet** (support ≥ 0.85): PHerc0257 z9000 w091-w094,
z10000 w091-w093, z12000 w062-w088, and PHerc0813 z10000 w064-w097, which is 68 windings and 816 cm².

## Review

110 review sheets, each with the PHerc0343 known-text control as its first tile, were viewed at 150-200 µm per pixel
(23 sheets were shrunk by the viewer by up to 11 %). Each sheet is listed in [REVIEW_LOG.md](REVIEW_LOG.md). The control's letter rows were visible on every sheet. No sheet
showed two or more parallel rows of discrete stroke-like marks. All verdicts are from the vision model of the AI agent
that ran the work; a human pass has not been done yet.

**Single-row features, all rejected:**

| where | what | why rejected |
|---|---|---|
| PHerc0257 z10000-11000 w063/w064, reading side | one ~1 cm row of bright marks | only one row; not reproduced by Hecate; the two meshes are ~0.1 mm apart there, so it is one sheet sampled twice ([FAILURE_CASES.md §6](FAILURE_CASES.md#6-one-sheet-sampled-by-two-windings)) |
| PHerc0813 z7000-8000 w056-w058, reading side | one band of bright marks below the upper edge | only one row; at the same place on three consecutive windings, so it is a physical feature seen through several layers |
| PHerc0257 z10000-11000 w037, reading side | a short line of dashes | at 75 µm/px it is blob texture, and the four maps (2 models × 2 depths) do not agree |

**What the maps do show** (so the next search can discount these):

- Cracks, crack loops and damage zones, usually in both the reading-side and blind-side maps, and at the same place
  on consecutive windings. Examples: PHerc0257 z10000 w077-w090 and z11000 w070-w089; PHerc0813 z9000 w049-w059 and
  w072-w076. A large oval that recurs on PHerc0813 z10000 w046-w063 (18 windings) is one of these.
- Fibre-like straight streaks, vertical or diagonal, continuous rather than broken into marks.
- Isolated bright blobs, and bright lines along map borders.
- Blocky rectangular patches where a mesh folds or ends (PHerc0257 z10000 w100, z11000 w085-w089).

## What "negative" means here

These two models (`dnative`, `hybrid_3d2d-seed42`), at depths d = +1 and +3, on these surfaces, show no rows of
letters. Text may still be there if:

- the ink in these scrolls does not look like the ink these models were trained on;
- it sits at another depth, for example because of snap or fit errors (track satisfaction was only 11-16 %);
- the surfaces jump between neighbouring sheets;
- it is in windings or z ranges we did not screen (the table above; both scrolls are much taller than these bands).

The useful parts of this result are the surfaces, which can be re-screened in minutes per winding with better models
or other depths; the per-winding QA, which shows where the fit is weak; and the list of confounders above.
