# For Consideration

Deferred ideas that aren't scoped or committed to yet — revisit if they keep coming up in real use,
rather than building speculatively now. Items already tracked inline in BUILD_LOG.md's "Deliberately
deferred" notes (per-scene cascade gaps, etc.) aren't duplicated here; this file is for open design
questions, not known implementation gaps.

- **Annotations panel position (bottom vs. right-docked).** Currently always bottom-docked under
  the scene editor (Phase 4). A right-docked option would need to coexist with the Reference
  Panel, which already owns the right-hand slot with its own resize handle — stacking or tabbing
  the two would add real layout complexity. Hold off until the bottom panel actually feels cramped
  in day-to-day use.

- **Per-project vault passwords.** Current design is one password for the whole library
  (`VaultService`). Explicitly deferred when the vault/backup system was built — see BUILD_LOG.md.

- **Emailing/sharing exported review files directly from the app.** Currently the export/import
  and reviewer-session screens (Phase 4) just write files to a user-chosen path, plus a "Copy Path"
  snackbar action on the reviewer's comments export. Actual email sending would need its own
  SMTP/credential setup — a meaningfully bigger, separate feature with real security surface, not a
  bolt-on. A lighter middle step worth considering first: a "Reveal in Explorer" action next to the
  existing save dialogs.
