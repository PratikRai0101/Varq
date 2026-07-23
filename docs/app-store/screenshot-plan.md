# Varq — App Store screenshot plan

This is the capture-ready plan for the initial macOS product page. Store the final images in `docs/app-store/screenshots/` using the filenames below, then run `scripts/validate-app-store-screenshots.sh` before upload.

## Technical requirements

- Capture six PNG images at **2880 × 1800 px** (16:10). Apple also accepts 1280 × 800, 1440 × 900, and 2560 × 1600 for Mac; use one consistent size for the full set.
- PNGs must be fully opaque—no alpha channel or transparency—and product pages accept one to ten screenshots.
- Capture actual Varq UI from the candidate build. Do not add device frames, fake UI, or capability claims the build cannot perform.
- Use the original **Varq Demo Library** only. It must contain agent-generated/original covers, original public-domain or permissively licensed body text, and original comic panels. Do not use the developer’s personal library, copyrighted covers, book text, or comic panels.
- Include at least one dark-mode capture. Do not show account names, local paths, notifications, the desktop, or another app.

Sources: [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) and [Apple product-page guidance](https://developer.apple.com/app-store/product-page/).

## Capture set

| File | Screen state | Product-page caption | Setup and acceptance criteria |
| --- | --- | --- | --- |
| `01-library.png` | Light-mode library grid | **Your library, in every format** | Show 8–12 original demo books with varied, legible covers. Include EPUB, PDF, and CBZ metadata; do not show CBR. Keep the library toolbar visible. |
| `02-reader.png` | EPUB reader with sepia page | **A calmer place to read** | Show an original demo passage, the page-turn state at rest, and the Appearance menu with typography controls. Ensure no selected text or cursor is visible. |
| `03-highlights-notes.png` | Reader with the Highlights sheet | **Keep the lines that matter** | Show at least two original-text highlights and one attached note. The sheet must have its visible “Back to reader” control. |
| `04-comics.png` | CBZ reader in right-to-left two-page mode | **Comics, your way** | Use two original, text-free geometric demo panels. Show Comic layout controls with right-to-left and two-page spread selected. |
| `05-private-shelf.png` | Library grid with a private demo book | **Private means private** | Show the discrete lock badge on one original cover. Do not attempt to screenshot a system Touch ID prompt. |
| `06-settings.png` | Reading tab in Settings | **Make Varq your own** | Crop to the app window only. Show page tone, font, text size, and line-height defaults; use dark mode for this capture. |

## Capture workflow

1. Build the Release candidate and set the Mac display to a supported 16:10 resolution, preferably 2880 × 1800.
2. Create or import the original Varq Demo Library. Verify every visual asset is cleared for App Store marketing use.
3. Set the required appearance, reader state, and settings for one row above. Hide the desktop and unrelated applications.
4. Capture the app window without transparency. Name the image exactly as specified above.
5. Run:

   ```bash
   scripts/validate-app-store-screenshots.sh
   ```

6. Review captions and images together. The first three screenshots should communicate library, reading, and annotation value without relying on a user reading the description.
7. Upload the validated PNGs and the copy in [`listing-copy.md`](listing-copy.md) to the English (U.S.) product page in App Store Connect.
