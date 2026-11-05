# Isolated GLPI source laboratory

The `glpi-laboratory.yml` workflow installs checksum-pinned GLPI10.0.18 in disposable services and runs the real JRC Client, queries and command executor against synthetic fixtures. It preserves the independently enumerated94-operation matrix in `run.rb`; additional consultation assertions do not replace any required operation.

The laboratory requires `GLPI_LAB_CONFIRM=isolated-synthetic`, Rails test mode and the disposable `branef_glpi_test` database. Its transport accepts only the laboratory HTTPS host/port and generated trusted CA, with no redirects or proxy fallback. Published service ports are verified as loopback-only. These guards prohibit customer/production requests; the evidence records `customer_requests:0`. Do not substitute real customer endpoints, tokens or data.

`test_actual_service_asset_discovery_and_administrative_delete_discover_restore` adds one service-context scenario:

1. Create a fresh synthetic ticket in mapped entity0, search allowlisted Computer candidates by name through `AssetQuery`, and consult the typed asset detail in that ticket's scope.
2. Delete that ticket through the existing durable `Execute` operation.
3. Discover the deleted record by title through the authenticated administrative trash HTTP list, read its detail and assert explicit source `is_deleted` state.
4. Restore through the existing executor with the discovered source revision, then prove that the ticket disappeared from the trash and returned to ordinary source search.

Separate backend/UI regressions verify agent denial, foreign/unmapped asset refusal, explicit source403, association-versus-asset IDs and the human restore-confirmation control. The source laboratory itself exercises backend HTTP/source behavior; it does not claim a live browser or customer homologation.

The workflow prepares fixtures/TLS, verifies service bindings, loads/migrates only the disposable Rails database, runs `bundle exec ruby test/glpi_lab/run.rb` and removes only its isolated Compose project. Results are written to `.runtime/laboratory-results.json`, including exact source SHA, required/recorded operations, checks and transport counters. A green prior SHA is not a substitute for the final exact-SHA gate.
