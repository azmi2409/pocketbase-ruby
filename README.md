# pocketbase (Ruby)

A Ruby port of the official [PocketBase JavaScript SDK](https://github.com/pocketbase/js-sdk) — the full client API for [PocketBase](https://pocketbase.io), written in idiomatic Ruby with **zero runtime dependencies** (stdlib only: `net/http`, `json`, `openssl`…).

```ruby
require "pocketbase"

pb = PocketBase.new("http://127.0.0.1:8090")

# auth
pb.collection("users").auth_with_password("test@example.com", "1234567890")
puts pb.auth_store.token

# crud
post = pb.collection("posts").create("title" => "Hello", "views" => 1)
list = pb.collection("posts").get_list(1, 30, filter: pb.filter("title ~ {:t}", t: "Hello"), sort: "-created")
pb.collection("posts").update(post["id"], "views" => 2)
pb.collection("posts").delete(post["id"])

# realtime
unsub = pb.collection("posts").subscribe("*") { |e| puts "#{e["action"]}: #{e["record"]["id"]}" }
sleep 60
unsub.call
```

## Installation

```ruby
# Gemfile
gem "pocketbase", "~> 0.1"
```

Or install directly:

```
gem install pocketbase
```

Requires Ruby >= 2.7.

## Client basics

```ruby
pb = PocketBase.new("http://127.0.0.1:8090")
# or PocketBase::Client.new(url, auth_store: ..., lang: "en-US")

pb.build_url("/api/health")            # full URL builder
pb.filter("title ~ {:t} && views > {:v}", t: "hi", v: 5)
pb.collection("posts")                 # cached RecordService per collection
pb.create_batch                        # batch request builder
```

Low-level requests (named `send_request` because `send` is taken by `Object#send`):

```ruby
pb.send_request("/api/health", method: "GET", timeout: 10)
```

Options accepted by every service method (all optional):

| Option | Meaning |
|---|---|
| `query:` / `params:` | extra query params (merged) |
| `headers:` | extra headers |
| `timeout:` | seconds |
| `filter:`, `sort:`, `expand:`, `fields:` … | any other top-level key becomes a query param (like the js-sdk) |

Hooks:

```ruby
pb.before_send = ->(url, options) { { url: url, options: options } }
pb.after_send  = ->(response, data, options) { data } # response.status / .headers / .url
```

Errors raise `PocketBase::ClientResponseError` with `#status`, `#url`, `#response` (aliased `#data`), `#original_error`, `#is_abort`.

## Auth store

```ruby
pb.auth_store.token        # raw JWT
pb.auth_store.record       # authed record hash
pb.auth_store.valid?       # token present and unexpired
pb.auth_store.superuser?   # _superusers collection
pb.auth_store.auth_record? # regular auth record
pb.auth_store.save(token, record)
pb.auth_store.clear
pb.auth_store.on_change { |token, record| ... } # returns unsubscribe lambda

# cookie helpers (e.g. for Rails controllers)
cookie = pb.auth_store.export_to_cookie
pb.auth_store.load_from_cookie(request.headers["Cookie"])

# file-persisted store (like the js-sdk LocalAuthStore)
pb2 = PocketBase.new(url, auth_store: PocketBase::FileAuthStore.new("~/.pb_auth.json"))
```

## Records & auth

```ruby
posts = pb.collection("posts")
posts.get_list(1, 30, filter: "...", sort: "-created", expand: "author")
posts.get_full_list(batch: 200, filter: "...")  # or get_full_list(200, filter: "...")
posts.get_first_list_item("title = 'Hello'")    # 404 when missing
posts.get_one("RECORD_ID")
posts.create("title" => "Hi", "image" => File.open("a.png", "rb")) # file upload -> multipart
posts.update("RECORD_ID", "title" => "Hi again")
posts.delete("RECORD_ID")

users = pb.collection("users")
auth = users.auth_with_password("test@example.com", "secret")
users.auth_refresh
users.list_auth_methods
users.request_password_reset("test@example.com")
users.confirm_password_reset("TOKEN", "new-pass", "new-pass")
users.request_verification("test@example.com")
users.confirm_verification("TOKEN")
users.request_email_change("new@example.com")
users.confirm_email_change("TOKEN", "password")
users.request_otp("test@example.com")           # => { "otpId" => ... }
users.auth_with_otp("OTP_ID", "password")

# superuser impersonation -> brand new client with the impersonated session
other = pb.collection("users").impersonate("RECORD_ID")

# superuser token auto-refresh (mirrors js-sdk autoRefreshThreshold, seconds)
pb.collection("_superusers").auth_with_password("admin@example.com", "secret",
                                                auto_refresh_threshold: 1800)
```

### OAuth2

Assisted flow (opens the provider URL via your block, waits on the realtime `@oauth2` channel, exchanges the code):

```ruby
auth = pb.collection("users").auth_with_oauth2(provider: "google") do |url|
  puts "Open: #{url}" # or `system("open", url)`
end
```

Manual flow:

```ruby
info = pb.collection("users").oauth2_login_url("google", scopes: ["email"])
# redirect the user to info["url"], then:
pb.collection("users").auth_with_oauth2_code("google", code, info["code_verifier"], redirect_url)
```

## Files

```ruby
pb.files.get_url(record, "avatar.png")                        # absolute URL
pb.files.get_url(record, "avatar.png", thumb: "100x100")      # thumbnail
pb.files.get_url(record, "avatar.png", download: true)        # force download
pb.files.get_url(record, "avatar.png", token: pb.files.get_token) # protected file
```

## Realtime

The SSE stream runs in a background thread with automatic reconnect (same backoff as the js-sdk).

```ruby
unsub = pb.realtime.subscribe("posts/*") { |e| p e["action"] }
# or via the collection helper:
unsub = pb.collection("posts").subscribe("*") { |e| p e }

unsub.call                        # remove this listener
pb.collection("posts").unsubscribe("*")
pb.realtime.unsubscribe_by_prefix("posts")
pb.realtime.disconnect             # close the stream (auto-closes when no subs remain)
pb.realtime.on_disconnect = ->(subs) { puts "disconnected, active: #{subs}" }
```

## Batch

```ruby
batch = pb.create_batch
batch.collection("posts").create("title" => "a")
batch.collection("posts").update("RECORD_ID", "title" => "b")
batch.collection("posts").upsert("id" => "MAYBE_ID", "title" => "c")
batch.collection("posts").delete("OTHER_ID")
results = batch.send # => [{ "status" => 200, "body" => {...} }, ...]
```

Note: `/api/batch` is **disabled by default** on the server — enable it in *Settings → Batch* (or via `pb.settings.update`).

## Admin services

```ruby
pb.settings.get_all
pb.settings.update(full_settings_hash) # nested structs are replaced wholesale: round-trip get_all
pb.settings.test_s3("storage")
pb.settings.test_email("users", "to@example.com", "verification")

pb.backups.get_full_list
pb.backups.create("backup.zip")   # name must end in .zip
pb.backups.upload("file" => File.open("backup.zip", "rb"))
pb.backups.delete("backup.zip")
pb.backups.restore("backup.zip")
pb.backups.get_download_url(pb.files.get_token, "backup.zip")

pb.logs.get_list(1, 30, filter: "...")
pb.logs.get_one("LOG_ID")
pb.logs.get_stats
pb.logs.truncate

pb.crons.get_full_list
pb.crons.run("job-id")

pb.sql.run("SELECT id FROM posts") # superusers only

pb.collections.get_one("COLLECTION_ID")
pb.collections.create(base_hash)
pb.collections.update("COLLECTION_ID", "listRule" => "")
pb.collections.delete("COLLECTION_ID")
pb.collections.import([col1, col2], delete_missing: false)
pb.collections.truncate("posts")
pb.collections.get_scaffolds
pb.collections.get_all_oauth2_providers
pb.collections.dry_run_view_query("SELECT id FROM posts")

pb.health.check
```

## Notes & differences from the js-sdk

- **Synchronous.** No promises; no auto-cancellation of in-flight requests (`auto_cancellation`/`cancel_request` exist as no-ops for API compatibility).
- **`send_request`** instead of `send` (`Object#send` collision).
- **Options are plain hashes**, e.g. `get_list(1, 30, filter: "...", timeout: 5)`. Pass request bodies as the first positional hash: `create("title" => "Hi")`.
- **Responses are hashes** with string keys (parsed JSON), not model classes.
- **Realtime** uses a background thread + `Queue`-friendly blocks instead of `EventSource`.
- **OAuth2 popup flow** is replaced by a block-based assisted flow (`auth_with_oauth2 { |url| ... }`) plus a manual `oauth2_login_url` helper.
- `settings.update` needs the **full settings object** (PocketBase replaces nested structs wholesale — partial nested hashes don't merge).
- `backups.create` names must end with `.zip`; `/api/batch` must be enabled server-side.

## Development

```bash
# start a local PocketBase for the test suite
./pocketbase serve --http 127.0.0.1:8090
./pocketbase superuser upsert admin@test.com password123

ruby -Ilib -Itest -e 'Dir.glob("test/test_*.rb").each { |f| require_relative f }'
# or: POCKETBASE_URL=http://127.0.0.1:8090 rake test
```

## License

MIT. Port of [pocketbase/js-sdk](https://github.com/pocketbase/js-sdk) (also MIT).
