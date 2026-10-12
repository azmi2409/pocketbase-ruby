# Changelog

## 0.1.1 (2026-10-12)

- Prevent forwarding authorization and cookies across redirect origins; preserve HTTP redirect method/body semantics.
- Honor string-keyed hook results and preserve request options when `before_send` returns nil.
- Normalize realtime subscription query options; roll back failed listeners and retry failed subscription updates.
- Terminate idle SSE readers on disconnect and notify `on_disconnect` on stream interruption before reconnecting.
- Deliver auth changes reliably when callbacks unsubscribe themselves.
- Expand home-relative auth file paths and raise persistence errors instead of silently dropping writes.
- Add offline HTTP/SSE regression checks using local TCP servers.

## 0.1.0 (2026-10-12)

Initial release — full Ruby port of [pocketbase/js-sdk](https://github.com/pocketbase/js-sdk):

- `PocketBase::Client` with `send_request`, `before_send`/`after_send` hooks, `filter` builder, `build_url`
- `PocketBase::AuthStore` (in-memory) and `PocketBase::FileAuthStore` (persisted), cookie import/export, `valid?`/`superuser?`/`auth_record?`, `on_change`
- `PocketBase::ClientResponseError` (`status`, `url`, `response`/`data`, `original_error`)
- Services: records (CRUD + password/OAuth2/OTP auth, password reset, verification, email change, impersonate, superuser auto-refresh), collections, files, logs, settings, backups, health, crons, SQL, batch
- Realtime SSE subscriptions with background thread + auto-reconnect
- Zero runtime dependencies (stdlib only)
- 65 integration tests against a live PocketBase server
