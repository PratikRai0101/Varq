# Varq

A native, open-source e-reader for macOS. Built in Swift/SwiftUI with native macOS reader components — no Electron, no web wrappers. Reads EPUB, PDF, CBZ, and CBR. Designed with a warm, distinct visual identity rather than generic minimalism.

## Why

Apple Books is polished but format-locked. Calibre and similar tools support everything but look and feel dated. Varq aims to be the native-feeling, fluid, well-designed option that also handles the formats people actually have.

## Status

Early development — MVP not yet shipped. See `docs/BACKLOG.md` for current task state and `docs/PRD.md` for full scope.

## Documentation

- [`docs/PRD.md`](docs/PRD.md) — product requirements, MVP scope, roadmap
- [`docs/design-system.md`](docs/design-system.md) — color, type, motion, and brand rules
- [`docs/art-prompts.md`](docs/art-prompts.md) — AI image-generation prompts for original brand art, plus asset sourcing/licensing rules
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — technical architecture and implementation notes
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — ordered task list
- [`AGENTS.md`](AGENTS.md) — instructions for AI coding agents working in this repo

## Requirements

- macOS 15+ (Sequoia or later)
- Xcode 16+

## Setup

```bash
git clone https://github.com/PratikRai0101/varq.git
cd varq
open Varq.xcodeproj
```

Resolve Swift Package dependencies via Xcode's File → Packages → Resolve Package Versions, then build and run.

## License

MIT — see `LICENSE`.

## Contributing

See `CONTRIBUTING.md`. This is an early-stage personal project; issues and PRs are welcome but the design direction in `docs/design-system.md` is intentional and should be respected in any UI contribution.
