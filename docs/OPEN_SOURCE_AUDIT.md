# Source publication hygiene

Original code is MIT-licensed. Data, trademarks and artwork have separate rights described in [third-party notices](../THIRD_PARTY_NOTICES.md).

## Repository boundaries

- Do not commit signing keys, certificates, provisioning profiles, credentials, tokens, local environment files, database backups or compiled packages.
- `backend/.env.example` contains placeholders. Local `.dev.vars*`, `.env*`, `build/` and `tmp/` are ignored.
- Test fixtures are fictional. Exported system symbols and the generated preview embedding them are excluded; regenerate locally when needed.
- Signing team IDs, bundle IDs, App Groups, Worker hostnames and D1 database IDs are configuration identifiers, not credentials. Forks must replace them.
- The public test console uses HTTPS Basic authentication with the test operator secret. Missing configuration disables access.
- Provider credentials stay on the server; installations use random credentials and server-side hashes. Never log full push tokens or journey contents.

## Verification and history

`scripts/audit-publication.py` scans reachable blobs for selected credential patterns and excluded material. It is a limited pattern scan, not proof that every possible secret is absent. Check both the current tree and reachable history before publishing.

Use a GitHub noreply author address where appropriate. Enable repository secret scanning/push protection when available. Rotate any exposed key in every service that shares it.

History rewrites change commit IDs. Preserve private recovery backups outside the repository and reconcile existing clones before pushing again. Do not reintroduce removed objects through old branches. See [history maintenance](PUBLICATION_REVIEW.md).
