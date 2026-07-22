# Varq — Design System

This is the single source of truth for all visual decisions in the app. Any agent writing View code should reference this before introducing colors, type, spacing, or motion.

## Design philosophy

Elegant restraint with a warm, distinctly Indian visual soul — inspired by two references: Sarvam AI's brand system (deep indigo, warm saffron/terracotta gradients, minimal geometric iconography, generous whitespace) and early-20th-century woodblock/oil paintings of Indian architecture and mythology (warm parchment tones, gold accents, rich but controlled color). The goal is a reading app that feels calm and premium in daily use, with moments of warmth and richness at emotionally appropriate points (splash screen, empty states, about page) — not a generically "clean minimalist" app, and not a maximalist/cluttered one either.

Rule of thumb: the UI chrome (navigation, buttons, controls) should be as restrained as Sarvam's site. The book itself, and a few key brand moments, are where richness lives.

## Color palette

| Token name | Hex (approx) | Usage |
|---|---|---|
| `varqIndigo` | `#241F3D` | Primary dark surface — reader chrome background in dark mode, app icon base |
| `varqIndigoLight` | `#3A3160` | Secondary dark surface, hover/pressed states on indigo |
| `varqParchment` | `#F5EFE3` | Light mode background — never pure white |
| `varqParchmentDeep` | `#EDE4D0` | Card surfaces in light mode |
| `varqSepia` | `#F0E6D2` | Reader page background (both modes) — deliberately warmer than UI chrome |
| `varqSaffron` | `#E6AA5A` | Primary accent — progress indicators, active states, highlights |
| `varqTerracotta` | `#B5502A` | Secondary accent — icons, CTAs, brand mark stroke |
| `varqMaroon` | `#7A2E1D` | Tertiary accent — reserved for a second highlight color option, error states |
| `varqHighlightGreen` | `#92E66B` | Neon text-highlight option — translucent over book text |
| `varqHighlightYellow` | `#F6E65C` | Neon text-highlight option — translucent over book text |
| `varqHighlightRed` | `#FF6B6B` | Neon text-highlight option — translucent over book text |
| `varqHighlightPink` | `#FF7EB6` | Neon text-highlight option — translucent over book text |
| `varqInkLight` | `#2E2717` | Reading text color on sepia page |
| `varqInkDark` | `#EDE4D0` | Reading text color when page is inverted to full dark mode |

Do not introduce new colors outside this table without updating this file first. Text highlights may use the three brand accents or the four dedicated neon highlight tokens above; use a translucent fill so selected text remains readable. If a new state (e.g., a warning banner) needs a color, derive it from the closest existing token rather than picking an arbitrary new hex.

## Typography

- **UI chrome font:** System font (SF Pro) — keep navigation, buttons, and labels in the native system font. This is deliberate: it keeps the app feeling native and fast, and reserves the serif for the reading experience itself.
- **Reading text font:** A warm serif — start with Georgia or New York (system-available) for MVP; consider a licensed literary serif later. Do not use a sans-serif for book body text under any circumstance.
- **Weights:** Regular (400) and Medium (500) only in UI chrome. Avoid heavy/bold weights except for the app's wordmark.
- Sentence case throughout the UI — no Title Case, no ALL CAPS, matching modern Apple HIG conventions.

## Iconography and motifs

- App mark: a minimal geometric compass/star shape (see mockup reference) in `varqTerracotta` or `varqSaffron` on `varqIndigo` — evokes a mandala/lotus without being a literal, potentially cliché rendering of either.
- A thin gold-toned rule (`varqSaffron` at reduced opacity) may be used as a card or section divider accent — sparingly, not on every element.
- Do not use literal cultural iconography (flags, deities, literal lotus flowers, generic "ethnic pattern" borders). The Indian-ness of this design should live in color, warmth, and restraint — not in decorative motifs that read as costume.
- System SF Symbols are fine for standard UI actions (search, settings, bookmark) — tint them with the palette above rather than default system colors.

## Motion and animation

- Page-turn transitions should use a warm-toned shadow (derived from `varqTerracotta` at low opacity), not the default cold gray system shadow.
- Prefer spring animations (`'.spring(response:dampingFraction:)'`) over linear/ease-in-out for anything the user directly triggers (swipes, taps) — this is what makes SwiftUI feel "fluid" versus a web-wrapper.
- Respect `reduceMotion` accessibility setting — provide a cross-fade fallback for the page-turn animation.

## Light / dark / sepia modes

Varq has three reading-relevant states, not just two:
1. **Light (library & UI):** `varqParchment` background, dark text, full color palette visible
2. **Dark (library & UI):** `varqIndigo` background, `varqSaffron`/light text, muted secondary colors
3. **Reading page tone (independent of UI mode):** the actual book page can be set to sepia (`varqSepia` background, `varqInkLight` text) regardless of whether the surrounding UI chrome is in light or dark mode — this mirrors what serious e-reader users expect (e.g., a sepia reading page at night with dark UI chrome around it) and should be a separate user setting, not tied 1:1 to system light/dark mode.

## Reference mockup

See `docs/assets/mockup-reference.png` (or the in-conversation visual reference) for the target look: cream/parchment library grid with indigo-and-saffron reader chrome, sepia page with terracotta highlight color. Any agent generating new screens should visually match this reference's warmth and restraint level before considering a screen "on-brand."

## Brand art assets — sourcing rules (important)

The mood references used to derive this palette (Yoshida Hiroshi woodblock prints of Mughal architecture, Raja Ravi Varma-style Mahabharata oil paintings) are **inspiration for color and composition only** and must never be used directly as shipped assets:

- Yoshida Hiroshi's prints may or may not be public domain depending on jurisdiction and specific print date — do not assume any specific piece is clear to use without per-piece verification.
- The Mahabharata oil paintings referenced were explicitly identified as the work of a named living/recently-working artist (Giampaolo Tomassetti) — these are under copyright and must never be reproduced, cropped, or used as a direct visual reference in any shipped asset, marketing image, or App Store screenshot.
- Do not prompt any AI image generator with a living or named artist's style (e.g. "in the style of [artist name]") for final production assets — use palette/mood/motif language instead (see prompts below), which is both legally cleaner and produces more original, ownable brand material.

All splash screens, app icons, empty-state illustrations, and marketing art must be either (a) originally commissioned/AI-generated art using the prompts in `docs/assets/art-prompts.md`, or (b) built directly from the color tokens and geometric motifs in this file — never derived from or closely resembling the reference paintings/prints themselves.

### Original geometric motifs (safe, on-brand, icon-ready)

Three motifs were developed as legally clean, ownable brand marks — abstracted from architectural/pattern concepts (which are not copyrightable) rather than copying any specific artwork:

1. **Reduced-to-line arch** — a Mughal arch silhouette simplified to two nested outlines in gold/terracotta on indigo. Suitable for section dividers or a loading state.
2. **Jali lattice texture** — repeating circular lattice pattern (inspired by jali screen architecture generally, not any specific historical structure) used as a subtle background texture, never as a foreground decorative element.
3. **Compass mark** — the core app icon seed: an eight-point compass/star form in gold and terracotta outline on indigo, evoking a mandala/lotus form without literally rendering one. This is the primary candidate for the app icon and loading spinner.

See `docs/assets/motif-study.svg` (export the in-conversation SVG reference) for the source shapes. Any agent implementing the app icon or splash screen should start from the compass mark, not invent a new symbol.
