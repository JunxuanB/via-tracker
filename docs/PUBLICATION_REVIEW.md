# Repository history maintenance

The source repository keeps a single development branch, `main`. Documentation is maintained in English; application localization remains multilingual.

Private distribution material and obsolete documentation snapshots are excluded from the retained code history. Current English engineering documentation is added after that cleanup. Implementation commits remain available, with empty documentation-only commits pruned where appropriate.

Before rewriting history, a complete Git bundle was saved outside the repository. Backups are local recovery material and must not be uploaded. Updates use expected remote commit IDs to avoid overwriting concurrent work.

Existing clones must be re-cloned or deliberately reconciled with the rewritten branch. Never push an old branch back: it can reintroduce removed content. Reachable-ref verification cannot prove that a hosting provider removed every unreachable object, direct commit URL or cached page.

The earlier source cleanup also excluded exported SF Symbols, generated HTML embedding them, a captured operator fixture and personal author email. Original source remains MIT-licensed; [third-party notices](../THIRD_PARTY_NOTICES.md) describe other rights. Repository visibility is controlled separately by its owner.
