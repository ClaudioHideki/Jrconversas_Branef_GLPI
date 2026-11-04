# GLPI overview and export contract

The projection is derived from GLPI and never creates an editable native Ticket. List, overview and export use the same account/connection/version, explicitly mapped entities, currently granted units, actor restriction, and validated filters. They expose the latest collection time and scoped coverage. Missing entity labels never identify scope. A changed connection version invalidates its projection and export receipts.

`Overview#list(access:, filters:)` returns `items`, `meta` (page, per_page, total), `coverage`, `observed_at`, and `generated_at`. `Overview#call(access:, filters:)` returns the report metrics, the same coverage, and timestamps. Supported filters: entity_id (including 0), status, priority, search (title), from, to, mine, type, page, per_page. Mine uses the authenticated GLPI mapping and assigned technician actors only; the base restricted read permission accepts requester or technician actors. Missing actor coverage must not broaden the result.

Suggested authenticated endpoints under the existing account GLPI prefix:

- GET overview: standard envelope plus `report`.
- POST exports: 202, envelope plus `export` receipt.
- GET exports/:export_id: envelope plus current receipt.
- POST exports/:export_id/cancel: envelope plus receipt.
- GET exports/:export_id/download: authenticated attachment, or 202 envelope plus receipt while verifying.

Receipt fields: id, state, processed, total, error_code, created_at, finished_at, expires_at, coverage, can_download, verified_from, verified_until, verification_expires_at. States: queued, running, ready, verifying, failed, cancelled, expired. There is no public object URL.

Exports require complete coverage for the requested entity scope. Partial projections remain visible as partial in the list and overview; they cannot become a ready complete export. The background worker streams all matching authorized records to temporary storage and persists progress by batch. It verifies source IDs, actual entity IDs, revisions, duplicate IDs, pagination totals, current permissions and connection version. The artifact becomes ready only after all checks and upload succeed. CSV formulas are neutralized with the existing OperationalCsv rules. An explicit byte quota aborts the whole artifact instead of truncating it. Artifacts expire and are purged 24 hours after generation completes.

Download verification is asynchronous because a complete 10,205-ticket source proof can require over 10,000 detail RPCs. The first download request queues verification and returns 202. Polling reports progress. A successful pass offers a 30-second, one-use delivery proof. The final request atomically consumes that proof and checks fresh JRC account/member/unit/configuration and a bounded source probe before returning the attachment. A source 403, configuration change, or local revocation purges the artifact. Concurrent downloads cannot reuse a proof.

`verified_from` and `verified_until` describe the interval in which all source details were checked. GLPI V1 does not offer a transactional read snapshot across those requests. The final bounded probe does not make all preceding record checks atomic; an external source change between individual reads remains possible. Report this interval and limitation rather than claiming instantaneous source-wide consistency.

Verification uses only synthetic source HTTP responses and disposable CI PostgreSQL/Redis/ActiveStorage. It does not validate the customer's real GLPI rights, nor perform client writes.
