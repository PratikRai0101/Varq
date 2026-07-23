# Keep private content local by default

**Status:** Accepted

## Context

Varq’s private shelf promises stronger protection than an ordinary library filter: a Private Book is encrypted at rest and opened only after system authentication. Planned intelligence, Spotlight, and export features introduce additional copies and destinations for book content. Treating those destinations as implicit would weaken the meaning of the private designation and make the data flow difficult for readers to understand.

## Decision

Private Books are excluded by default from all Search Index content, Spotlight indexing, and Private Cloud Intelligence requests.

A reader may use Local Intelligence with a Private Book only after an explicit, per-book confirmation that says the content remains on the device. That confirmation is not a blanket consent for Private Cloud Intelligence or indexing.

Private Cloud Intelligence is a separately enabled, opt-in feature. Before its first use with any book, Varq must explain that the request is processed by Apple Private Cloud Compute and obtain consent. A Private Book requires an additional per-book confirmation before its content can be sent through that feature.

Vault Export is always user initiated through a system folder chooser. Exporting a Private Book requires a clear confirmation that the resulting selected-folder files are no longer protected by Varq’s private-shelf encryption.

## Consequences

- Privacy scope is enforced at every content-destination seam rather than inferred from UI state.
- Search, intelligence, and export modules need a shared policy decision before accessing Book content.
- Private-book tests must cover denial and consent paths in addition to encryption and authentication paths.
- A reader can make an intentional exception, but Varq never silently broadens the data flow of a Private Book.
