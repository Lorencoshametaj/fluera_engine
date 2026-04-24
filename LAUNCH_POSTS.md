# Launch posts — Fluera Engine SDK

Draft copy for the first public announcements. Revise tone + stats before
publishing. Every link should be tested; every price/feature claim should
match the actual README + landing page.

---

## 1. Hacker News — "Show HN"

**Title (≤80 chars, no emoji, no marketing):**

```
Show HN: Fluera Engine – Professional 2D canvas SDK for Flutter
```

**Post body (HN hates hype — keep it engineering-first):**

```
Hi HN,

For the last 18 months I've been building a consumer study app
called Fluera — handwritten notes with a pedagogical AI layer.
The hardest part wasn't the pedagogy. It was the canvas engine
underneath: pressure-sensitive brushes that don't tear on pan,
60 FPS with thousands of strokes on a mid-range phone, an infinite
canvas that still feels like paper.

I kept looking at the existing Flutter canvas packages —
flutter_drawing_board, scribble, fldraw — and they all stop way
before what a serious drawing tool needs. No pressure pipeline,
no scene graph, no rendering optimisation beyond naive CustomPaint.

So I extracted the engine and split it into two packages:

  Core (MIT, free):  InfiniteCanvasController, gesture detector
                     with pressure+tilt, scene graph, base nodes,
                     3 brushes, tools, undo/redo, PNG export.

  Pro (commercial):  14 GPU shader renderers, CRDT collaboration,
                     time travel, SQLCipher encrypted storage,
                     PDF/SVG export, tile-cached rendering with
                     LOD + occlusion culling.

The repo: https://github.com/looponia/fluera_engine
The 5-example demo app: https://github.com/looponia/fluera_engine_examples
The landing: https://fluera.dev/sdk
Pricing: €499 one-time + €149/yr updates for Startup, €1,499 + €399/yr
for Pro, custom for Enterprise — with a perpetual-fallback clause
so you keep what you bought even if you stop renewing.

Technical writeups in the repo README cover the scene graph design
and the brush pipeline. Happy to answer questions about anything
under the hood — rendering, input pipeline, Flutter's `dart:ui`
limits, whatever.
```

**Comment strategy:** Stay online the first 2 hours. Answer every question.
Don't defend pricing — if someone says "$499 is too much", explain your
unit economics honestly ("I need roughly 20 sales to cover a year of
my own time. I'm happy to discuss freelance rate if you want to compare.").

---

## 2. Reddit — r/FlutterDev

**Title:**

```
I open-sourced the canvas engine behind my drawing app — pressure, infinite, scene graph
```

**Post body (Reddit loves: honesty, concrete code, screenshots):**

```
TL;DR — 280 LoC widget that gives you a working pressure-sensitive
infinite canvas in Flutter. MIT. Runs on every platform Flutter
targets. Advanced stuff (GPU shaders, collaboration, time travel)
lives in a paid companion package, but the core is yours.

**Why another canvas package?**

I'm building a consumer study app (Fluera) where students write
notes by hand. I benchmarked every Flutter canvas package I could
find, and they all fell apart somewhere:

  • flutter_drawing_board → no pressure, no infinite canvas
  • scribble → pressure works but it's a signature pad
  • fldraw → infinite canvas but no pressure, alpha-stage
  • hand-roll your own → 3-6 months to get to "usable"

Mine had to ship into a shippable consumer app, so I built it
properly. Now I'm releasing the engine so you don't have to.

**Repo:** https://github.com/looponia/fluera_engine
**Examples:** https://github.com/looponia/fluera_engine_examples (5 runnable demos)
**Landing:** https://fluera.dev/sdk

**Quick start (literally the whole drawing pipeline):**

```dart
InfiniteCanvasGestureDetector(
  controller: InfiniteCanvasController(),
  onDrawStart: (pos, pressure, tiltX, tiltY) { ... },
  onDrawUpdate: (pos, pressure, tiltX, tiltY) { ... },
  onDrawEnd: (pos) { ... },
  child: CustomPaint(painter: MyScenePainter(), size: Size.infinite),
);
\```

The 5 example demos show: basic drawing, pressure+tilt
visualisation, programmatic stroke push, custom brush renderers,
PNG export. All ≤300 LoC.

AMA in the comments.
```

**Add 2-3 screenshots or a 15s GIF of hello_canvas and pressure_demo.**

---

## 3. dev.to — deep-dive technical post

**Title:**

```
How I built a pressure-sensitive infinite canvas in Flutter (and what I learned about dart:ui)
```

**Structure (5-7 min read):**

```
1. The problem — pressure APIs in Flutter's PointerEvent vs what
   Apple Pencil and S Pen actually emit at 120Hz.

2. The gesture detector — why `GestureDetector` isn't enough, and
   how `Listener` + custom state machine handles palm rejection.

3. The infinite canvas trick — world coordinates + camera transform,
   why `Transform` widget is wrong for this, and what to use instead.

4. Stroke rendering — from `drawLine` segments to tesselated quads,
   and why we eventually pushed it to GPU shaders for the Pro tier.

5. Scene graph design — copied pages from Figma and Excalidraw,
   left out what didn't fit a mobile-first app.

6. Publishing the SDK — monorepo with Melos, two barrels (public
   + internal), one companion package for Pro. Commit history:
   https://github.com/looponia/fluera_engine/commits/main

7. What I still haven't solved — 60Hz predicted touch on Android,
   Impeller edge cases on iOS 18.

If you're building anything canvas-shaped in Flutter, you can
probably skip 3-6 months of this by starting from my repo.

→ https://github.com/looponia/fluera_engine
```

**Call-to-action at bottom:** Pricing link + "hello@fluera.dev if you
want to talk" — no hard sell.

---

## 4. X / Twitter — launch thread

**Tweet 1 (opener):**

```
Two years ago I thought the hard part of my study app
would be the pedagogy.

It was the canvas.

Pressure. Infinite pan. 60 FPS with thousands of strokes.
Today I'm shipping the engine as a Flutter SDK.

🧵
```

**Tweet 2 (what):**

```
Fluera Engine SDK.
• Pressure-sensitive brushes
• Infinite canvas controller
• Scene graph with typed nodes
• Undo/redo with delta tracking
• PNG export

MIT licensed core. Works on iOS, Android, all desktop, web.
```

**Tweet 3 (proof — video/GIF):**

```
Here's the 280-line widget that wraps it up.

5 example apps, ≤300 LoC each:
  ✍️  Hello canvas
  🎨  Pressure + tilt
  🧩  Scene manipulation
  🌈  Custom brush
  💾  Export PNG

[attach 15s screen recording of hello_canvas]
```

**Tweet 4 (why this matters):**

```
I benchmarked every Flutter canvas package and they all stop at
"basic drawing board". None handle pressure + infinite canvas +
scene graph together.

If you're building a whiteboard, note-taking app, sketch tool,
PDF annotator — you've probably been here too.
```

**Tweet 5 (Pro tier pitch):**

```
If you need the hard stuff:
• 14 GPU shader renderers
• CRDT real-time collab
• Time travel playback
• SQLCipher encrypted storage
• PDF + SVG export

That's the Pro tier. €499 Startup, €1,499 Pro, custom Enterprise.
Perpetual fallback — keep what you bought.
```

**Tweet 6 (close):**

```
Repo: github.com/looponia/fluera_engine
Docs: fluera.dev/sdk
Pricing: fluera.dev/sdk#pricing

Questions → hello@fluera.dev or reply here.

(First few customers get a pilot-programme discount. DM.)
```

---

## 5. Direct outreach — 20 Flutter agencies / creators

**Template email** (personalise the first paragraph per recipient — no
cold-mass-mailing):

```
Subject: Flutter canvas engine — 10 min demo worth your time?

Hi [Name],

I read [your recent post / your agency's case study on X]. You
mentioned [specific pain point they wrote about]. That's exactly
what pushed me to build Fluera Engine.

Short version: I spent 18 months building a consumer drawing app
(Fluera). The canvas underneath turned out to be more work than
the pedagogy. I just shipped the engine as a commercial Flutter
SDK — pressure-sensitive brushes, infinite canvas, scene graph,
GPU rendering, real-time collab.

If you're ever handed a "we need a whiteboard in our app" ticket,
this saves you 3-6 months. 5 runnable demos here:
  https://github.com/looponia/fluera_engine_examples

Pricing is consulting-cheap (€499 Startup, €1,499 Pro, perpetual-
fallback licence). If it looks useful for [their agency / project],
I'm happy to do a 10-minute screen share. No pressure.

— Lorenzo
   lorenzo@fluera.dev
   fluera.dev/sdk
```

### Target list brainstorm (20 targets)

Build the real list from these sources — each entry must be a REAL
person you've identified, not a scraped address:

- **Very Good Ventures** — largest Flutter agency, tech leads publish on X
- **Invertase** — Melos / FlutterFire maintainers
- **Serverpod / Drift / Riverpod** core contributors — all Flutter devs
  with audience, some run agencies
- **Independent Flutter creators** with ≥5k X followers writing about
  Flutter tooling
- **Edu-tech founders** on ProductHunt last 6 months with note-taking /
  whiteboard / sketch apps built on Flutter
- **Flutter Favorite authors** (listed at flutter.dev/community/awards)
- **Freelance Flutter devs** on GitHub with ≥50 followers and a
  `canvas`, `drawing`, or `whiteboard` repo in their profile
- **Consulting shops** in EU focused on mobile-first digital products

**DO NOT** use generic "agencies@" or "info@" addresses. DM real humans
only. Aim for 20 personalised emails over 2 weeks, not 100 in one day.

---

## Launch checklist (do these IN ORDER)

- [ ] Landing `fluera.dev/sdk` is live and all links work
- [ ] Repo `fluera_engine` is public on GitHub with README + LICENSE
- [ ] Repo `fluera_engine_examples` is public with all 5 demos
- [ ] Repo `fluera_engine_pro` is private; collaborator invite flow tested
- [ ] Stripe products live; test purchase completed end-to-end
- [ ] Edge Function `grant-sdk-access` deployed and wired to Stripe webhook
- [ ] `sdk_licences` table exists on Supabase
- [ ] Resend (or SMTP) wired for welcome emails
- [ ] `hello@fluera.dev` inbox reachable; 24h response target
- [ ] Draft posts reviewed for tone, stats, and links
- [ ] Schedule: HN Tuesday 08:00 ET · Reddit same day 10:00 ET ·
      dev.to 24h later · X thread concurrent with HN
- [ ] First 20 DMs sent over 14 days (not all at once)
- [ ] Analytics: Plausible or GA4 on landing; track CTA clicks
- [ ] Cost alert still firing to Discord (already in place)

## After first 30 days — what to measure

| Metric | Target (realistic) | How to measure |
|---|---|---|
| Landing unique visitors | 2k-5k | Plausible |
| GitHub stars on core | 100-500 | github.com/looponia/fluera_engine |
| Paid conversions | 2-8 Startup, 0-2 Pro | Stripe dashboard |
| Email volume (hello@) | 15-50 inquiries | inbox count |
| Bug reports filed | 5-20 | GitHub issues |
| Discord cost-alert triggers | 0-3 | cost_alerts table |

Adjust Week 2-4 based on these numbers. If conversion < 0.2%, the
bottleneck is discovery, not pricing. If conversion > 1% but total
visits < 500, the bottleneck is reach — double down on DM outreach.

---

_Written on the launch-prep day. Update this file in place as posts get
published and lessons land._
