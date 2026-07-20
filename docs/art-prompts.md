# Varq — Art generation prompts

Reference prompts for producing original brand art via AI image generators (Midjourney, DALL-E 3, or similar). These are written to evoke the mood/palette established in `docs/design-system.md` without copying or closely referencing any specific existing artwork or named artist's style — see the "Brand art assets — sourcing rules" section of `design-system.md` for why this matters legally.

General rules for any prompt used against these tools for this project:
- Never name a specific living or recently-working artist in the prompt
- Never ask for a specific existing monument or building to be rendered recognizably (e.g. "the Taj Mahal") — describe architectural forms generically instead ("a domed archway", "sandstone courtyard")
- Always specify the Varq palette (indigo `#241F3D`, saffron `#E6AA5A`, terracotta `#B5502A`, parchment `#F5EFE3`) so output stays on-brand rather than drifting to whatever the model defaults to
- Treat all output as a draft to art-direct further, not a final asset — review each generation against the sourcing rules before use

## 1. Splash screen / launch art

> Original digital illustration in the style of early 20th-century Japanese woodblock prints, depicting a quiet Mughal-era courtyard at golden hour with a single reader's silhouette seated beneath an arched doorway, warm ochre and terracotta architecture, deep indigo sky transitioning to gold, flat color fields with fine linework in the ukiyo-e tradition, parchment-textured paper background, no text, no recognizable monuments, generous negative space, contemplative and calm mood, muted color palette matching hex E6AA5A gold and 241F3D indigo.

**Use case:** app launch screen, first-run experience
**Negative prompt additions (if supported):** no photorealistic rendering, no 3D render, no literal religious iconography, no recognizable named monuments, no visible text

## 2. App icon exploration

> Minimalist app icon design, a single geometric compass-star motif inspired by Mughal jali lattice patterns and mandala geometry, rendered in flat burnt-orange and gold on a deep indigo circular background, clean vector linework, no text, no literal religious symbols, modern and restrained, centered composition, macOS app icon style with soft rounded square mask, high contrast, suitable for small-size legibility.

**Use case:** primary app icon candidate — cross-reference against the compass mark motif already developed in `design-system.md` before treating a generated result as final
**Negative prompt additions:** no photorealistic elements, no gradients that won't scale down cleanly, no fine detail that disappears at 16px–32px sizes

## 3. About page / empty-state illustration

> Original gouache-style illustration of an open book resting on a windowsill overlooking a warm terracotta rooftop skyline at dusk, inspired by the color palette and composition sensibility of early Indian miniature painting and Japanese travel woodblock prints, deep indigo and saffron-gold color scheme, soft flat shading, no recognizable people or monuments, cozy and literary mood, parchment paper texture visible at the edges.

**Use case:** empty library state, about/credits page, GitHub README hero image
**Negative prompt additions:** no readable text in the illustration, no logos, no recognizable faces

## Tool-specific notes

- **Midjourney:** append `--ar 16:9 --style raw --v 6` (or current version) to reduce default over-stylization and keep color fidelity closer to the specified hex values
- **DALL-E 3:** tends to add text/labels unprompted even when told not to — regenerate if this happens rather than trying to edit it out
- **General:** most image generators are unreliable for pixel-accurate UI mockups — use these prompts for mood/illustration art only, not for generating the actual app interface. Build the interface directly in SwiftUI or Figma using the tokens in `design-system.md`.

## Licensing note for generated output

Confirm the specific AI tool's terms of service regarding commercial usage rights and ownership of generated images before shipping any output as a production asset in an App Store-distributed, open-source app. Terms vary by provider and change over time — verify current terms at the time of use rather than assuming.
