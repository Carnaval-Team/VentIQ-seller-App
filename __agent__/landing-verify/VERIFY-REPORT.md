# VERIFY-REPORT.md — independent adversarial verification (task-3)

Verifier: `verify` (read-only inside `ventiq_landing/`). All my writes are confined to
`__agent__/landing-verify/`.

## 0. What exactly was verified (hashes — important)

The writers edited the tree *after* the Lead announced completion. My first snapshot
(10:41) was already stale. Everything below is against the **live tree at 10:46**, whose
hash I re-checked against my re-snapshot:

| artifact | git hash-object (verified) |
|---|---|
| `ventiq_landing/r.html` | `a41bd7f05396c79c3b42b6b8a6e5d4f8f2f3b8bc` |
| `ventiq_landing/assets/css/premium-v3.css` | `3a6830b1ca31469be6ff0036d6d0f09477cc738f` |
| `ventiq_landing/assets/js/premium-v3.js` | `bf10914d4101dfee7b103ce3bdbbd00fd253bf8b` |
| baseline = git HEAD `648b35b9` | r.html `8e77aff6…`, css `e02912db…`, js `b733b45c…` |

`r.html` hash matches my 10:41 snapshot, so the whole clipboard verdict below applies to
the live file. `premium-v3.css` (mtime 10:39) and `premium-v3.js` (mtime 10:36) changed
after my first snapshot; I re-snapshotted (`final/`, previous copy kept in
`final/prev-snapshot/`) and re-reviewed the current bytes. **If a writer touches these
files again, this report is invalidated.**

## 1. Verdict summary

| Req | Verdict | One-line reason |
|---|---|---|
| **R1** italic headings not chopped | **PASS** (evidence is the Lead's probes, not mine) | All four `background-clip:text` rules now carry paint-room padding; measured ink envelope is inside the paint box everywhere; raster overlap 0 |
| **R2** stack-card animation must not break | **FAIL (partial)** — stacking PASS, depth animation **inert** | Sticky stacking verified working; `--stack-progress` is *constant* across all 10 scroll stops in the newest artifact, so the recede/scale/dim effect never runs |
| **R3** contrast / attention | **PASS with 1 residual FAIL** | All five baseline failures fixed and independently reproduced (3.90→6.06, 3.20→5.84, 1.81/2.49→5.84/8.24, 4.89→8.57); one hover state is still 4.46:1 |
| **R4** r.html looks like the landing + functional | **PARTIAL** | Palette is exactly the landing's navy+cyan, touch targets ≥44 px, functionality proven; visual resemblance unverified (no post-fix screenshots) and horizontal overflow unknown (the Lead's `hOverflow:true` is a probe artifact) |
| **R5** clipboard always `"CARNAVAL-REF:"+CODE` | **PASS on every route, 1 hard FAIL on code fidelity** | Exact payload via every route I could inject, 0 uncaught errors in 22 scenarios; but the code is silently mutated (`abc-123_xy` → `ABC123XY`) |

Hard failures I am asserting: **2** — (1) R5 code mutation, (2) R2 depth animation not running.

---

## 2. R5 — clipboard. What I ran (my own harness, not the author's)

`__agent__/landing-verify/verify-clipboard/verify-clipboard.js` — a self-contained DOM /
navigator / virtual-clock harness that executes the page's **inline** scripts and never
loads the external `<script src>` (so `window.VentiqTracking` and `supabase` are genuinely
absent). Raw output: `final-clipboard.txt`, machine copy `final-clipboard.json`; the
pre-fix control run is `baseline-clipboard.txt`.

```
C:\Program Files\nodejs\node.exe verify-clipboard.js <r.html> --json <out.json>
```

The harness has a **negative control**: against pre-fix `r.html` it reproduces the real
breakage — with `tracking.js` absent it logs
`Uncaught ReferenceError: VentiqTracking is not defined`, registers **no** click listener,
and copies nothing; with a throwing `navigator.clipboard` getter it dies at init; with
`abc-123_xy` it copies `CARNAVAL-REF:ABC123XY`. A harness that cannot fail proves nothing,
so this control matters.

Final run: **1 hard failure, 22 scenarios, 0 uncaught errors in all 22.**

| checklist item | verdict | evidence (final r.html) |
|---|---|---|
| C1 `VentiqTracking` unguarded | **PASS** | `track()` wrapper at r.html:664-669 with `try/catch` + `typeof` check; my scenario with tracking absent: `no-errors` PASS, `payload-on-gesture` PASS (`clipboard.writeText "CARNAVAL-REF:ABC123"`). Independently matches the Lead's `clipboard-notrack`: `trackingGlobal:"undefined"`, `errorsCount:0`, exact payload. |
| C2 same on the code-less path | **PASS** | No code + tracking absent: 0 errors, CTA navigates to the APK URL. |
| C3 non-gesture copy on load | **PASS** | `silentCopy()` at load is inside the ladder (`attemptClipboardApi` → `attemptExecCommand` → visible selection); failure never escapes. |
| C4 gesture-less `pageshow` | **PASS** | `pageshow(persisted:true)` scenario: 6 copy attempts, affordance visible, 0 errors. |
| C5 `navigator.clipboard` read can throw | **PASS** | Read moved inside `new Promise(...)` + `try` (r.html:894-905), so a throwing getter becomes a rejection: my hostile-webview scenario copies the exact payload via `execCommand`, 0 errors. |
| C5b clipboard API absent | **PASS** | `execCommand` called with the exact payload. |
| C6 `writeText` rejects → fallback | **PASS** | Log: `writeText(ok:false)` → `document.execCommand("CARNAVAL-REF:ABC123", ok:true)`. Temp `host`/`ta` are removed in a `finally` (r.html:986-989) — statically verified, not runtime-asserted. |
| C7 never-settling `writeText` | **PASS — this was a real bug, now fixed** | `withTimeout(p, 500ms)` (r.html:878-890, 902) races the promise; my `never` scenario still copies via `execCommand` and still navigates. |
| C8 navigation must not depend on the copy | **PASS** | Navigation recorded even when every copy route fails. |
| C11 must never copy `"CARNAVAL-REF:"` bare | **PASS** | `payload=""` and `runCopy()` returns `{ok:false,via:'no-code'}` for no/empty/punctuation-only code; `no-bare-payload` PASS in all three, and clicking the visible copy button adds **no** clipboard write. |
| C12 re-entry after repeated failure | **PASS** | 3 taps with every route dead: 8 copy attempts, affordance stays visible, a navigation fires on each tap, 0 errors. |
| C13 JS-referenced ids | **PASS** | All 12 ids (`ctaBtn ctaText ctaHint refChip refCode chipState toast toastText manualCopy manualCopyText manualHint copyBtn`) exist in the final r.html; no null-deref errors in 22 scenarios. |
| C15 both CDN scripts absent | **PASS** | This is the harness's default condition; also matches the Lead's `clipboard-notrack`/`clipboard-alldead` artifacts. |
| C16 always-available manual affordance | **PASS** | New `#copyBtn` "Copiar código" (r.html:580, 1216-1218) is visible with a code; clicking it produces the exact payload (`copy-button-works` PASS in every code-present scenario). |
| C9 code resolution routes | **PARTIAL → UNVERIFIED in production** | Supported: `?code/ref/referral/codigo/c`, `#code=`, `#?ref=`, bare `#ABC`, and `localStorage/sessionStorage["carnaval_ref_code"]` — all six probes copied the exact payload. **Not** supported: `?invite=` (probe failed). Nothing in this repo links to `r.html` (0 matches), so I cannot confirm which alias production links use. |
| **C10 payload must be exactly `"CARNAVAL-REF:"+CODE`** | **FAIL (hard)** | `normalizeCode` (r.html:713-718) applies `.toUpperCase()` + `.replace(/[^A-Z0-9]/g,"")` + `.slice(0,16)`. Input `?code=abc-123_xy` produced `CARNAVAL-REF:ABC123XY` — a different payload from `"CARNAVAL-REF:" + CODE`. Also truncates any code >16 chars. Harness detail: `payload(s) ["CARNAVAL-REF:ABC123XY","CARNAVAL-REF:ABC123XY",…] -- MUTATED`. Severity depends on the real code alphabet: if Carnaval only ever issues uppercase A–Z0–9 codes ≤16 chars, it is a no-op; I have no evidence of the app's alphabet (the consumer is outside this repo). |
| C17 real iOS Safari | **UNVERIFIED** | My iOS-UA scenario passes, but a stub cannot honour user-activation rules. The iOS load-time attempt is harmless (ladder + timeouts) yet its success cannot be assumed. |

Residual R5 risk not in the task list: `readStoredCode()` (r.html:768-793) replays a code
from `localStorage` **forever** with no TTL when the URL carries none. My
"localStorage only" probe confirms it copies that stale code. So the clipboard can hold a
code that is not in the current URL — correct format, possibly wrong invitation.

## 3. R2 — stack-card animation (the strongest counterexample I found)

Static re-review of the **current** JS/CSS is clean where it matters: no `gsap`, no
`ScrollTrigger`, no `pinSpacing`, no `pin`; `.v2-tile` no longer receives a JS
`opacity`/`transform` tween (it keeps `v2-reveal` purely CSS, JS only writes
`--mouse-x/--mouse-y`); CSS owns `position:sticky; top:88px` and the JS only writes
`--stack-progress`; the JS media query `(min-width:881px) and (min-height:721px)` is the
exact complement of the CSS un-stick breakpoints (`max-width:880px`, `max-height:720px`);
reduced motion forces `transform:none; opacity:1; --stack-progress:0`.

**Stacking: PASS.** From the newest probe's `walk` scenario (all three cards):
`pos=sticky` at every one of the 10 stops; card1 rect top `889 → 638 → 388 → 137 → 88`
(then sticks); card2 `1724 → … → 220`. Nothing is `fixed`; no ancestor breaks sticky
(this empirically answers the `overflow:hidden` ancestor concern).

**Depth animation: FAIL — it does not run.** `--stack-progress` in the newest artifact
(`final-light-probe.txt`, 10:43) is **constant at every scroll position**:

```
step stop0_want3147 scrollY=3147 | c0 prog=0.042 op=0.98 tf=matrix(0.99748,…,-0.756) | c1 prog=0.000 | c2 prog=0.000
step stop4_want4150 scrollY=4150 | c0 prog=0.042 op=0.98 tf=matrix(0.99748,…,-0.756) | c1 prog=0.000 | c2 prog=0.000
step stop9_want5486 scrollY=5486 | c0 prog=0.042 op=0.98 tf=matrix(0.99748,…,-0.756) | c1 prog=0.000 | c2 prog=0.000
```

c1 never leaves `0.000` even at stops 4-6, where it is stuck (`rect.t=88`) and c2 is
sliding up over it (721 → 471 → 220) — that is exactly when it should recede.

Two extra observations that make this a page bug rather than a probe blind spot:
1. The probe *can* observe changes: `SETY()` uses `window.scrollTo` and the recorded
   `scrollY` does advance 3147→5486, and the same probe caught `0.000` in the 10:39 run and
   `0.042` in the 10:43 run — the value tracks *something*, just not scroll.
2. `0.042` is exactly `(3094 + 88 − 3147) / 835` = `35/835`, i.e. the value a **single**
   `updateStack()` computes at `scrollY≈3094` and never updates. So the formula is right
   but it is being evaluated once (or the `scroll → rAF` path stops re-evaluating).

Root-cause candidates I can name but **could not confirm without a browser** (I am not
allowed to launch Chrome): (a) `updateStack` is not re-invoked on scroll in this build /
rAF not firing under the probe's `--virtual-time-budget`; (b) the
`if (!stackSticky.matches) { …progress 0… }` branch being taken (that branch writes exactly
`0.000`, matching the 10:39 run). The probe does not record `matchMedia(...).matches` or
the JS's internal `stackTops`, which is what would separate these. Both are equally fatal
to the effect, so the verdict holds either way. **The Lead's own message ("depth animation
NOT yet verified") is confirmed and, on the newest evidence, sharpened to "not running".**

Also note the writer *did* fix the original freeze mechanism I flagged in the pre-fix JS
(`getBoundingClientRect()` on a stuck card) and removed the inline
`position:static` thrash — the new `measureStack` is pure `offsetTop/offsetHeight/margin`
arithmetic. That fix is correct as written; the effect still does not animate.

## 4. R1 — chopped italic headings

Static: all four clipped-gradient rules now have paint room plus a cancelling negative
margin — `.v2-hero h1 em` `padding:0.15em 0.2em 0.22em; margin-inline:-0.2em` (css:413-428),
`.v2-h em` `0.08em 0.2em 0.12em/-0.2em` (css:663-670), `.v2-cta h2 em` (css:1385-1391), and
`.v2-tile-stat .v2-num` (css:997-1001). Baseline had `0px`/`0.16em` — the 0.16em version is
what left `IT` clipped.

Measured (the Lead's Canvas `actualBoundingBoxLeft/Right` ink probe — I inspected it, I did
not generate it): every item now has a **negative** deficit (ink inside the paint box):
hero `opera` 86px `deficitL -24.2 / deficitR -10.32`; `.v2-h em` at 52px
`construye -5.44`, `opera -5.4`, **`IT -1.66`**, `piensan -6.29`, `crecen -6.3`;
`herramientas` 72px `-7.68`. The pixel raster probe reports `worstOverlapPx: 0`,
`collidingPairs: []`. The baseline `geometry.json` had `padL/padR: 0px` and the ink test
verdict was CLIPPED (84 device pixels missing); the current `geometry.json` shows
`padL/padR 17.2px` (= 0.2em × 86px) with `marginL/R -17.2px`, i.e. paint room added without
moving the ink.

Two caveats I will not paper over:
* The Lead's message quotes `IT deficitR = +1.26px`; that is the **older** 10:31 run at
  `0.16em`. The newest runs measure `-1.66px` at `0.2em`. The message is stale; the
  artifact is what counts.
* The CSS comment claims `-0.8px` for `IT` while the artifact measures `-1.66px` — a
  documentation nit, same sign, no functional impact.
* **My own evidence here is the Lead's probes.** I could not run Chrome, so I did not
  independently rasterise a glyph. What I *did* verify independently is the code change
  and the internal consistency of those artifacts.

Hero word-reveal clip: the newest `text` probe reports `overflow: visible` on all six
`.v2-hero h1 .word` spans, i.e. the `is-revealed-settled` release (JS:103 after 1400 ms,
CSS:2034) does fire. **Do not misread `clippedH: true` in that artifact as a clip**: those
words also report `transform: translateY(103px)`, i.e. the 800 ms CSS transition has not
advanced under `--virtual-time-budget`; `overflow:visible` is the meaningful field. The
masked state is intentional during the reveal, and reduced motion (`css:2047-2048`) and
JS-off (spans only exist if JS runs) both avoid a permanent clip.

## 5. R3 — contrast (my own math, `verify-tools/contrast.js`)

`node contrast.js spec-final.json` → `final-contrast.txt`. Baseline vs final:

| label | baseline | final | verdict |
|---|---|---|---|
| `--v2-text-mute` 12px on white (`.v2-stack-tag`) | **3.90 FAIL** | 6.06 | PASS |
| `.v2-section-dark` primary (white on `#3A9BB8`) | **3.20 FAIL** | 5.84 (`#08131F` on `#3A9BB8`) | PASS |
| `.v2-flow` primary (white on `#22D3EE`/`#14B8A6`) | **1.81 / 2.49 FAIL** | 8.24 / 5.84 | PASS |
| `.v2-footer-bottom` `rgba(255,255,255,.48)` | 4.89 | 8.57 (`.68`) | PASS |
| `#4E657A` dark-mode mute on `#102033` | — | 5.36 | PASS |
| base navy primary white on `#2A5F8A` | 6.77 | 6.77 | PASS |
| **base navy primary, hover shimmer `rgba(94,184,209,.35)`** | **4.46 FAIL** | **4.46 FAIL** | **residual FAIL** |
| dark-surface hover (`#08131F` + white `.45`) | — | 10.23 | PASS |
| hero `em` gradient / `.v2-h em` / `.v2-cta h2 em` (large text) | 6.96 / 6.45 / 6.96 | unchanged | PASS |

My independent numbers reproduce the authors' claimed 6.06 / 5.84 / 8.24 exactly. The one
residual: the **base** `.v2 .v2-btn-primary` (white on `--v2-grad-accent`, e.g. the drawer
CTA) still uses the unscoped cyan shimmer (css:501-509), so at the lightest gradient stop
on hover it is **4.46:1** where 15 px normal text needs 4.5:1. Baseline had the same value —
this group was not revised. "Grabs attention" is not measurable; I am not certifying it.

## 6. R4 — r.html restyle

Verified statically (structural, from the live file):
* Palette is the landing's: `--navy-950 #0C1A2A`, `--navy-800 #163353`, `--cyan-400 #5EB8D1`,
  `--cyan-500 #3A9BB8`, `--paper #F7FAFB`, `--ink #102033`, `--ink-soft #3D5366`
  (r.html:37-68); `theme-color` `#F7FAFB`/`#0C1A2A` (16-17); **zero** orange leftovers
  (`#FF8A17/#E5730A/#FFF1E1/#FF6B00/#FFB36A/#FFD8B0/#FFF8F1` all gone). Deliberate Carnaval
  red `#E11D2A` remains as identity, which is defensible.
* `--ink-mute: #6B8498` — the exact token that failed contrast on the landing — is still
  declared (r.html:57) but **never used** (1 grep match = the declaration). No exposure.
* Every small-text colour carries a documented ratio and mine agree (`.benefit .d`/`.foot`
  `#3D5366` on paper 7.62; `h1` white; `.lead #C3D4DF`; `.cta #08131F` on cyan).
* Touch targets: probe `clickables` at 504×716 → CTA 464×52, chip 201×60, copy button
  139×44, footer link 95×46 — all `tooSmall:false`.
* Functionality: proven by the clipboard harness on the live file (copy + navigation).

What I could **not** verify, stated plainly:
* **Visual resemblance.** There is no post-fix screenshot anywhere under
  `__agent__/landing-verify/` (the only screenshots are `before/`, i.e. pre-fix). Palette
  tokens are necessary but not sufficient for "looks like the landing".
* **Horizontal overflow — the Lead's `hOverflow: true` is NOT trustworthy evidence.**
  The probe's `PUB()` appends an **unstyled `<pre id="__probe">`** containing one long JSON
  line to `document.body` (probe.ps1:23). A `<pre>` does not wrap, so it inflates
  `documentElement.scrollWidth`. The reported values confirm it: mobile 504 px viewport →
  `docScrollW: 9842`, desktop 1422 → `1615`. 9842 px is ~20× the viewport and cannot be the
  page's own overflow in a `max-width:480px` layout. So overflow is **UNKNOWN**, not true —
  re-measure with the `<pre>` detached or `pre{max-width:100%;white-space:pre-wrap}`.
* **375 px was never probed**; the narrowest r.html viewport in any artifact is 504×716.
* `.hero-band h1 em` (r.html:229-236) uses `background-clip:text` +
  `-webkit-text-fill-color:transparent` with **no padding**. It is `font-style: normal`, so
  risk is small — but the landing's own ink data shows an *upright* word ("Software", 86 px)
  overhanging its box by ~1 px, so I cannot rule out a sub-pixel trailing clip at 38 px.
  Low severity, same class of bug as R1.

## 7. Checklist items not covered above

* **S3 (`loadScript` can hang)** — still present: the "script already exists" branch
  attaches `load` and returns without ever resolving (js:271-273 area). Severity is now low:
  it is used **only** for optional Lenis, nothing awaits it for correctness. Latent, not a
  functional blocker.
* **S8 (renamed classes/tokens)** — none; `index.html` is untouched and the CSS additions are
  new selectors plus a specificity bump (`.v2 .v2-btn-primary`, 0,2,0) that keeps all class
  names. No section loses its styling.
* **S6/S7/S9** — PASS as described in §3.

## 8. UNVERIFIED (with reasons)

1. Real iOS/Safari behaviour (no Safari, no interactive browser; stubs cannot model
   user-activation rules).
2. R4 visual resemblance and true horizontal overflow (no post-fix screenshots; the
   existing overflow metric is an artefact — see §6).
3. Any viewport below 504 px (375 px never probed).
4. The consumer contract: no file in this repo reads `CARNAVAL-REF`, so the app's code
   alphabet (and therefore the real severity of the C10 mutation) is unknown.
5. Which inbound parameter production links actually use (nothing in this repo links to
   `r.html`).
6. Whether the depth animation's root cause is the `matchMedia` branch or the
   scroll→rAF path — the probe does not capture `stackSticky.matches` or the JS's internal
   `stackTops`.
7. "Colours grab attention" (subjective).
8. My R1 pixel-level conclusion rests on the Lead's probes; I verified the code and the
   arithmetic, not a rasterisation.

## 9. Exact commands (all run from `__agent__/landing-verify/`)

```
git hash-object ventiq_landing/r.html ventiq_landing/assets/css/premium-v3.css ventiq_landing/assets/js/premium-v3.js
git diff --no-index -U2 final/prev-snapshot/premium-v3.js final/premium-v3.js
"C:\Program Files\nodejs\node.exe" verify-clipboard\verify-clipboard.js <r.html> --debug-display --json verify-clipboard\final-clipboard.json
"C:\Program Files\nodejs\node.exe" verify-clipboard\verify-clipboard.js ..\baseline\r.html --json verify-clipboard\baseline-clipboard.json
"C:\Program Files\nodejs\node.exe" verify-tools\contrast.js verify-tools\spec-baseline.json
"C:\Program Files\nodejs\node.exe" verify-tools\contrast.js verify-tools\spec-final.json
"C:\Program Files\nodejs\node.exe" verify-tools\mine-probe.js ..\final-light-probe.txt
```

## 10. Bottom line for the Lead

Ship-blocking: **the R2 depth animation does not run** in the newest artifact, and
**R5's code normalisation changes the payload** for any code containing lowercase,
`-`/`_`, or more than 16 characters. Both are small, well-scoped fixes. Everything else is
either verified or explicitly unverified above — nothing in this report is a restatement of
an author's claim.

---

# 11. CORRECTION (appended after the Lead's re-measure — supersedes §1's R2 row and §3; settles two UNVERIFIED items)

The original text above is kept unedited as the audit trail. This section **supersedes**
exactly three things: the **R2 verdict**, the **R4 "horizontal overflow"** entry, and the
**R1 `IT` figure** note. **R5 (including the hard C10 code-mutation FAIL) is unaffected**,
as is everything else.

## 11.1 R2 — my FAIL is retracted; R2 is now PASS

**Root cause of the bad measurement (the Lead's harness, confirmed by inspection of
`probe.ps1`):** under `--headless=new --virtual-time-budget=N` Chrome renders almost no
frames and emits **no `scroll` events at all**, so the page's
`scroll → queueStackUpdate → requestAnimationFrame → updateStack` chain could never run.
Instrumented: ~6 rAF ticks per run, 0 scroll events, even though `window.scrollTo()` did
move the page. A constant `--stack-progress` therefore proved nothing — and it also explains
the two values I reported disagreeing (0.000 at 10:39 vs 0.042 at 10:43): each run froze
whichever single value the page happened to compute once. My §3 inference that "the scroll
listener stops re-evaluating" was drawn from a harness that never fired a scroll event; that
inference is withdrawn.

**I did not take the retraction on trust — I re-derived it.** I read
`stackforce.txt` and the `stackforce` scenario in `probe.ps1` (it shims `requestAnimationFrame`
onto `setTimeout`, dispatches a real `scroll` event after each `scrollTo`, and leaves the page
code unmodified), then checked the numbers against the page's own formula and the CSS mapping:

| observation | check |
|---|---|
| card0 series `(3147, 0.042) (3481, 0.442) (3815, 0.842) (4150, 1.000)` | slope `0.400/334` → **1/835 = 1/(807 card height + 28 margin)**, i.e. exactly the intended span |
| intercept back-solved from card0 | `stackTops[0] ≈ 3200`; predicted at 3815 `(3815+88−3200)/835 = 0.842` ✓ matches |
| card1 series `(4150, 0.243) (4484, 0.643) (4818, 1.000)` | same 1/835 slope; back-solved `stackTops[1] ≈ 4035 = 3200 + 835` ✓ exactly one span apart |
| opacity in every row | matches CSS `1 − prog × 0.45` to 4 dp: 0.042→0.9811, 0.442→**0.8011**, 0.842→0.6211, 1.000→0.55 ✓ |
| transform at prog 1 | card top 88 → 70 = CSS `translateY(prog × −18px)` ✓ |
| card2 | stays 0.000 with opacity 1 — **correct by design** (js:216 keeps the last card fully visible) |
| scroll events counted per stop | 2, 4, 6, … 14 — the listener genuinely fires |

The forced-invocation series is internally consistent to three decimals with the JS
arithmetic *and* the CSS mapping, for both receding cards, and clamps correctly. **R2 = PASS:
sticky stacking correct, depth animation correct and scroll-driven, CDN-independent (no
gsap/ScrollTrigger/pin; `.v2-tile` no longer receives a JS opacity/transform write).**

Two caveats I will not drop, both recorded as residual rather than failure:
1. This validates the **arithmetic and the listener wiring via forced invocation** (rAF
   shimmed to `setTimeout` + synthetic `scroll`), **not the natural browser frame loop**,
   which is unobservable in this sandbox. Someone should confirm it on a real browser.
2. The page's internal `stackTops[0] ≈ 3200` differs by ~53 px from the probe's
   `probeTops[0] = 3147` (the probe measures `rect.top + scrollY − 88`; the JS builds the
   chain from the intro's `offsetTop`/`offsetHeight`/margin). Both cards share the identical
   835 span, so the behaviour and shape are right and every prediction above still holds; it
   just means the first stop reads 0.042 rather than 0.105. Benign, but if exact parity with
   the visual stick point ever matters, that offset is where to look.

## 11.2 R4 — horizontal overflow: now settled as PASS (my §6 "UNKNOWN" is resolved)

My §6 diagnosis was right and is now confirmed from both directions. After the Lead moved
`PUB()`'s `<pre>` off-flow (`position:fixed;left:-99999px`), the overflow vanished at every
size I inspected in `rlayout.txt`: 732 px viewport → `docScrollW 732, hOverflow false`; 1422 px
→ `docScrollW 1422, hOverflow false`. That is the same artifact behaving as predicted.

The true-375 px gap is closed by `iframe375.txt`, which measures inside an iframe because
Chrome clamps `--window-size` to ~504 px: `iframeCss 375x812`, `innerViewport 375x812`,
**`docScrollW 375`, `hOverflow false`, `overflowingElements []`**, clickables 335×52 /
190×60 / 132×44 / 89×46 (all above the 44 px minimum). **R4 horizontal overflow at 375 px =
PASS.** The one R4 item I still cannot certify is *visual resemblance* — post-fix frames now
exist (`probe-rlayout/frame-rlayout.png`, `frame-rlayout-desktop.png`), but this model
declares no image input, so I cannot view them; resemblance remains **UNVERIFIED**, now for
that reason rather than for absence of evidence.

## 11.3 R1 — settlement accepted, with one clarification

Accepted: the newest inkmetrics (`final-light-probe.txt`) measures `IT` at 52 px,
`deficitR = **−1.66**` (negative = ink inside the paint box), and all four clipped-gradient
elements are negative (`opera` 86 px −10.28; `construye` −5.42; `opera` 52 px −5.37;
`piensan` −6.29; `crecen` −6.29; `herramientas` 72 px −7.71). R1 stays **PASS**. The CSS
comment's "−0.8px" versus the measured −1.66 remains a documentation nit, same sign, no
functional impact.

Clarification worth keeping: in that same run the upright `.word` spans still show small
**positive** deficits (`Software +1.02`, `que +0.49`). Those are not clipped, because they
are not `background-clip:text` elements and their `overflow` is `visible` once
`is-revealed-settled` lands (§4). The acceptance rule applies to the clipped-gradient rules
only, and those are all negative.

## 11.4 Verdict table as corrected

| Req | §1 (original) | corrected |
|---|---|---|
| R1 | PASS | **PASS** |
| R2 | FAIL (partial) | **PASS** (forced-invocation caveat in §11.1) |
| R3 | PASS + 1 hover residual | **PASS + 1 hover residual** (unchanged) |
| R4 | PARTIAL | **PARTIAL** — overflow now PASS/verified at 375 px; visual resemblance still UNVERIFIED (no image input) |
| R5 | PASS on all routes + hard FAIL on code fidelity | **unchanged** — `?code=abc-123_xy` still writes `CARNAVAL-REF:ABC123XY` |

Net: the only remaining ship-blocking item is the R5 code-mutation FAIL (§2, C10).