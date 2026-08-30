# Frontend design quality — anti-AI-slop reference

Load this only when a story creates or materially redesigns visual surface (new page,
component, theme, or layout) — not for pure logic/state changes to existing UI, and not
for backend/API-only stories. Condensed from [Impeccable](https://github.com/pbakaus/impeccable)
(Apache 2.0), which itself extends Anthropic's `frontend-design` skill.

## Absolute bans (match-and-refuse — rewrite on sight)

- **Side-stripe borders**: `border-left`/`border-right` > 1px as a colored accent on cards/alerts. Use full borders, background tints, or icons instead.
- **Gradient text**: `background-clip: text` + gradient. Use a solid color; emphasize via weight/size.
- **Glassmorphism as default**: decorative blur/glass cards used everywhere. Rare and purposeful, or nothing.
- **Hero-metric template**: big number + small label + gradient accent. SaaS cliché.
- **Identical card grids**: same-sized icon+heading+text cards repeated endlessly. Nested cards are always wrong.
- **Eyebrow-on-every-section**: small all-caps tracked label above every heading ("ABOUT", "PROCESS"). One deliberate brand kicker is voice; one per section is AI grammar.
- **Numbered section markers as default scaffolding** (01/02/03 above every section) unless the section is a genuine ordered sequence.
- **Text overflowing its container**: test heading copy at every breakpoint; reduce clamp max or rewrite copy if it overflows.
- **Pure black/gray**: always tint neutrals toward the brand hue, even slightly.

## Color

- Body text contrast ≥4.5:1 against background (≥3:1 for large/bold text). Placeholder text needs the same 4.5:1 — light gray "for elegance" is the most common AI-slop tell.
- Gray text on a colored background reads washed out — darken toward the background's own hue instead.
- New project, no existing tokens: use OKLCH; pick a deliberate color strategy (Restrained / Committed / Full palette / Drenched) before picking colors — don't default to warm-neutral cream/sand/beige body backgrounds, that's the current saturated AI default.

## Typography

- Cap body line length at 65–75ch.
- Pair fonts on a contrast axis (serif+sans, geometric+humanist) — never two similar-but-not-identical sans-serifs.
- Hero/display heading ceiling: `clamp()` max ≤ 6rem.
- Display letter-spacing floor: ≥ -0.04em (tighter reads cramped, not designed).
- `text-wrap: balance` on h1–h3; `text-wrap: pretty` on long prose.

## Layout

- Vary spacing for rhythm — don't apply one spacing scale uniformly everywhere.
- Cards are the lazy answer — use only when truly the best affordance.
- Flexbox for 1D, Grid for 2D — don't default to Grid when `flex-wrap` suffices.
- Responsive grid without breakpoints: `repeat(auto-fit, minmax(280px, 1fr))`.
- Semantic z-index scale (dropdown → sticky → modal-backdrop → modal → toast → tooltip) — never arbitrary values like 999/9999.

## Motion

- Motion is part of the build, not an afterthought — plan it, don't bolt it on.
- Don't animate CSS layout properties unless truly needed; ease out with exponential curves (`ease-out-quart`/`quint`/`expo`) — no bounce, no elastic.
- Every animation needs a `@media (prefers-reduced-motion: reduce)` alternative (crossfade or instant).
- Staggered list-item entrances are fine; a uniform identical fade applied to every section is the tell.
- A reveal animation must enhance an already-visible default — never gate content visibility behind a class-triggered transition (breaks on hidden tabs / headless renders / screenshot tests).

## The AI-slop test

If someone could look at the interface and say "AI made that" without doubt, it failed.
Two checks:
- **First-order**: could someone guess the theme/palette from the category alone (e.g. every fintech is navy-and-gold)? If yes, rework the color/theme decision.
- **Second-order**: could someone guess the aesthetic family from category-plus-anti-references (e.g. "workflow tool that's not SaaS-cream" → still lands on editorial-typographic by reflex)? If yes, the first reflex was avoided but not the second — rework again.
