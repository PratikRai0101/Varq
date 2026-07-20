# Contributing to Varq

Thanks for considering a contribution. This is an early-stage, personally-directed open-source project, so a few things help keep it coherent as it grows.

## Before you start

- Read `docs/PRD.md` to understand current MVP scope. Features listed under "v1.1+ roadmap" are intentionally deferred — a PR implementing one of these without prior discussion is unlikely to be merged as-is, even if well-built.
- Read `docs/design-system.md` before touching any View code. The visual direction (warm indigo/saffron/terracotta palette, restrained geometric motifs, no literal cultural iconography) is a deliberate creative choice, not a placeholder — PRs that introduce off-palette colors or generic UI patterns will likely need revision.

## Development setup

See `README.md` for build instructions.

## Code style

Follow the conventions in `AGENTS.md` — that file is written for AI agents but applies equally to human contributors: MVVM structure, async/await, no force-unwraps without justification, Services layer stays UI-framework-free and testable.

## Pull requests

- Keep PRs scoped to one logical change
- Include or update unit tests for any new Service or ViewModel logic
- Reference the relevant `docs/BACKLOG.md` item if applicable
- Describe what you manually verified for any UI-facing change

## Issues

Bug reports: include macOS version, Xcode version (if building from source), and reproduction steps.
Feature requests: check `docs/PRD.md` section 8 first in case it's already planned for a later version.

## Code of conduct

Be respectful. Disagreements about design or architecture are fine and expected — keep them constructive.
