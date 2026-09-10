# ayeaye's API, for a mobile client

Handoff notes for building the mobile app. Everything in the **Auth** and
**The two gates** sections below was **verified with curl against a running
instance** (`ayeaye` @ `81b8817`, 2026-09-08) rather than read off the code or
recalled from SuperTokens' docs — the captured bodies and header names are
real. Anything not verified says so.

Read this once before writing auth. The rest of the API is best learned from
`SITE_URL/api/openapi.json` (151 paths) — generate a typed Dart client from
it rather than hand-writing models.

---

## 1. One base URL is the whole instance

ayeaye is deliberately **single-origin**: the SPA, the JSON API, the auth
routes, `/mcp`, `/media/*` and the WebSocket all share one hostname, set by
one variable (`SITE_URL`) on the server. There is no separate auth host, no
API subdomain, no CDN.

For the app this means **a profile is one URL plus one credential set**.
`https://tasks.example.com` gives you `…/api/*`, `…/api/auth/*`, `…/api/ws`
and `…/media/*` with no further configuration and no discovery call.

Self-hosters run `http://localhost` too, so **don't require https** in
profile validation — warn, don't block.

## 2. Auth — the verified flow

The API's `session.init()` sets **no** `get_token_transfer_method` override,
so SuperTokens honours the client's choice. Send `st-auth-mode: header` and
you get tokens instead of cookies. **No backend change is needed for a mobile
client to register and sign in.**

### Register

```
POST /api/auth/signup
  headers: Content-Type: application/json
           rid: emailpassword
           st-auth-mode: header
  body:    {"formFields":[{"id":"email","value":"…"},
                          {"id":"password","value":"…"}]}
  → 200 {"status":"OK","user":{…}}
```

`signin` is the identical shape at `/api/auth/signin`. A wrong password
returns **200** with `{"status":"WRONG_CREDENTIALS_ERROR"}` — SuperTokens
signals failure in the body, not the status code. A suspended account returns
`{"status":"SIGN_IN_NOT_ALLOWED"}`. Handle `status` before assuming success.

Password policy is server-side (10+ chars, upper, lower, digit) and its
rejection comes back per-field in `formFields`. Mirror it client-side as a
courtesy, but the server decides.

### The three response headers

```
St-Access-Token:  eyJraWQiOi…      (JWT, ~1h)
St-Refresh-Token: 17AC8tLofaPB…    (opaque)
Front-Token:      base64(JSON)     ← read this
```

`Front-Token` is base64-encoded JSON and it is the one worth parsing:

```json
{"ate": 1788913606000,               // access-token expiry, ms
 "uid": "065216ed-…",                // SuperTokens user id
 "up": {"st-ev": {"v": false, …},    // the session's claims
        "sessionHandle": "…", …}}
```

So the client can schedule a refresh and read claim state **without decoding
the JWT itself**. Use `ate` to refresh pre-emptively rather than waiting for
a 401.

### Authenticated requests

```
Authorization: Bearer <st-access-token>
```

Verified: `GET /api/me` → 200. No cookie, no CSRF token, no `rid` header
needed on `/api/*` routes (only on the `/api/auth/*` recipe routes).

### Refresh

```
POST /api/auth/session/refresh
  headers: Authorization: Bearer <st-refresh-token>
  → 200, with NEW St-Access-Token / St-Refresh-Token / Front-Token headers
```

Verified. **Both tokens rotate** — store both from every response.

### Unauthenticated

```
→ 401 {"message":"unauthorised"}
```

Note the key is **`message`**, not `detail`. SuperTokens' own errors use
`message`; the application's own errors use FastAPI's `{"detail": "…"}`.
The client's error parser must handle both or it will show blank messages
on exactly the auth failures you most want explained.

### Do not use `supertokens_flutter` as-is

The SDK is built around **one `apiDomain` per `SuperTokens.init()`**, which
is precisely what multi-profile breaks. Switching instances at runtime is not
a supported flow.

Recommendation: **hand-roll the token lifecycle.** It is a small amount of
code for full control — store `(baseUrl, accessToken, refreshToken, ate)` per
profile in secure storage, add an interceptor that refreshes when `ate` is
near or on a 401, and retry once. This matches ayeaye's own precedent: it
hand-rolled TOTP and its OAuth server rather than accept a constraint.

## 3. The two gates — where an auth-first build gets stuck

Two session claims can make **every** `/api/*` route return 403 while the
credentials are perfectly valid. Both are matched by *shape*, never by status
code alone: an unrelated 403 must not be mistaken for one of these.

### `st-mfa-ok` — two-factor required

Captured verbatim:

```json
403 {
  "message": "invalid claim",
  "claimValidationErrors": [
    {"id": "st-mfa-ok",
     "reason": {"message":"wrong value","expectedValue":true,"actualValue":false}}
  ]
}
```

Required when the account has enrolled a TOTP device **or** belongs to an
organisation with `require_mfa` on. Decided **once per session, at first
use** — an organisation turning the requirement on reaches an open session at
its *next sign-in*, not mid-session.

Unblock: `POST /api/me/mfa/totp/challenge` with `{"code":"123456"}` → 204,
or `POST /api/me/mfa/backup-codes/redeem`.

> **The single most expensive gotcha here.** The challenge response carries a
> **new `St-Access-Token`**, and the old token keeps returning 403 forever.
> Verified: post-challenge token → 200, old token → 403. The web app never
> notices because SuperTokens' fetch interceptor absorbs the rotation. **A
> hand-rolled client that ignores response headers on a 204 will complete
> 2FA successfully and stay locked out.** Read `St-*` headers on *every*
> response, including 204s.

Enrolment, if you build it: `POST /api/me/mfa/totp` returns `{secret, …}`
plus a QR as a `data:image/png;base64,…` URI; confirm with
`POST /api/me/mfa/totp/verify` taking **both** `secret` and `code` (the
secret is not stored until confirmed) → 204, which then reveals ten
single-use backup codes. `GET /api/me/mfa/status` reports where the account
stands.

### `st-ev` — email verification

Same shape, `"id": "st-ev"`. Enforcement is the **server's** decision
(`EMAIL_VERIFICATION=auto` — on only where SMTP is configured), so the app
must not assume either way: react to the 403, never pre-empt it. A dev
checkout has it **off**, so you will not see this locally by default —
test it deliberately.

Unblock: the person opens the link in their email, then the app **must
refresh the session** (`POST /api/auth/session/refresh`) before re-checking.
Verification is recorded against the account, but the access token still
carries the stale claim, and the refresh is what picks up the new value.
Without it, "I've confirmed it" re-checks, gets the same answer, and loops
forever.

## 4. `GET /api/me` is not just a fetch

It **creates the local user row on first sight** and **binds pending
invitations**. Everything else keys on the id it returns, so call it first
after auth and gate the UI on it — exactly as the web shell does. Firing
other requests before it means firing them against a user that does not
exist yet.

`PATCH /api/me` sets `display_name`, `status_message`,
`daily_summary_enabled` and `timezone`. **Send the device's IANA timezone
here** — reminders, the deadline sweep and the daily digest all compute
"today" per user zone, and a setting nobody finds stays wrong.

## 5. Realtime, and the personal-access-token story

`WS /api/ws` accepts exactly two credentials:

1. an `sAccessToken` **cookie** (browsers, via single origin), or
2. a **personal access token** in an `Authorization` header, resolved
   through `tokens_service.authenticate`.

A header-mode mobile client has **neither** — its SuperTokens access token is
not a PAT. Verified: a PAT returns **401 on `/api/me`** and **200 on
`/mcp`**; the two credentials are not interchangeable in either direction.

**The clean answer, needing no backend change:** after sign-in, mint a PAT
with the session and keep it in the profile for the socket.

```
POST /api/me/tokens   {"name":"Mobile app","scope":"read"}
  → {"id","name","scope","prefix":"ayc_IUvKSP9r","token":"ayc_…"}   ← plaintext ONCE
```

`scope: "read"` is enough — watching is reading, and the socket carries **no
content**, only `{"type":"task","task_id":…}` style nudges. Store the token in
secure storage; show `prefix` in the UI so a person can tell which token to
revoke (`DELETE /api/me/tokens/{id}`). Revoke and re-mint on profile removal.

Protocol: send `{"watch":{"kind":"task","id":"…"}}` after connect; access is
checked at watch time. Watch `org:<id>` for a board rather than every card,
and coalesce — the web client collects events for 1.5s before refetching.
Events never carry bodies, so **always refetch over HTTP**; a 404 on that
refetch is how you discover access was revoked.

## 6. What a Profile has to store

| Field | Notes |
|---|---|
| `label` | user-chosen; several instances may share a hostname pattern |
| `baseUrl` | scheme included; allow `http://` |
| `accessToken`, `refreshToken`, `ate` | secure storage, rotated on every response |
| `patForSocket`, `patId` | minted post-sign-in; optional if realtime is deferred |
| `userId`, `email`, `displayName` | for the switcher, so it renders offline |
| `lastOrgId` | the web app drops you back into the last organisation; match it |

Keep each profile's token set fully independent — no shared "current session"
singleton. Two profiles signed in at once is the normal case for anyone with
a work instance and a personal one.

## 7. Conventions the client must respect

- **No access reads as 404, never 403.** 403 means "you can see this, but not
  at that level". Verified: an organisation you're not in → 404. Don't render
  a "forbidden" screen for a 404; render "not found".
- **`can_*` flags are resolved server-side** (`can_edit`, `can_close`,
  `can_hide`, `can_make_private`, `access`). **Hide controls the flags deny**
  rather than showing a button that 403s — the product's own rule, and it
  saves the app reimplementing the access model.
- **Paged lists return `X-Total-Count`** (verified on `GET …/tasks?limit=1`)
  and take `limit`/`offset`. There is **no default limit** — ask for one.
- **The board has its own endpoint** (`…/tasks/board`) and **cannot be
  paged**: rows come back priority-first, so the first N of a large set are
  all criticals and later columns arrive empty. It bounds each column
  server-side and reports each column's real size.
- **Sorting and filtering are the server's job**, and both belong in app
  state that survives a restart the way the web app puts them in the URL.
- **Status and priority sort by rank, never alphabetically.** Statuses:
  `todo, in_progress, review, on_hold, blocker`. Priorities: `critical,
  urgent, high, normal, low, very_low` (`normal` is the default). There is
  **no `done` status** — open/closed is a separate boolean, and a task can be
  closed at any status.
- **An unknown sort key is ignored, not rejected** — shared links stay valid.
- Errors are `{"detail": "…"}` from the app, `{"message": "…"}` from
  SuperTokens. Show `detail` — it is written to be read by a person.

## 8. Uploads — three steps, and the Content-Type is signed

Bytes go **client → storage directly**, never through the API.

1. `POST …/tasks/{id}/attachments` (or `…/{id}/files`, or the conversation's)
   with the declared filename, content type and size → a `pending` row plus a
   **presigned PUT URL** and the content type to use.
2. `PUT` the bytes to that URL.
3. `POST …/attachments/{id}/confirm` → the server HEADs the object, enforces
   the real size, and flips the row to `ready`.

Three things will bite:

- **The signature covers `Content-Type` byte for byte.** The server
  normalises (`audio/webm;codecs=opus` → `audio/webm`), signs *that*, and
  **returns the value for you to echo**. Send the string the server gave you,
  never the platform's own — a mismatch fails with `SignatureDoesNotMatch`,
  which says nothing about content types.
- **Allowed types** are exactly: `image/jpeg`, `image/png`, `image/gif`,
  `image/webp`, `application/pdf`, `text/plain`, `text/csv`, `video/mp4`,
  `video/webm`, `audio/webm`, `audio/mp4`, `audio/mpeg`. iOS voice notes
  (AAC in MP4) are covered by `audio/mp4`. **`image/heic` is NOT** — and it
  is the iPhone camera's default. Convert to JPEG client-side (better for
  size anyway) or see the gaps section.
- **50MB default** (`attachment_max_bytes`), enforced against the real object
  at step 3, so a too-large file fails *after* uploading. Check size locally
  first; a 413 at confirm is a wasted upload on a phone connection.

Reading: image URLs are **presigned and minted fresh per read**, so they
expire — never cache them, and never persist one.

## 9. Rich text — use the markdown door

Task descriptions and article bodies are **sanitised HTML** on the server
(allow-listed: `h2`/`h3`, lists, `strong`/`em`, links, code blocks with
`language-*` classes, and images carrying `data-attachment-id`). No Flutter
editor emits that shape, and `flutter_quill` is Delta-based.

**But the write endpoints already accept markdown**, built for MCP:

```
POST/PATCH …/tasks        {"description":"**bold**", "description_format":"markdown"}
PATCH …/kb/revisions/{id} {"body":"…",              "body_format":"markdown"}
```

So: **render** HTML (`flutter_widget_from_html` or similar), **edit** as
markdown. Two limits carried over — `#` is promoted to `##` (the product only
has h2/h3), and a markdown image reference renders as nothing, because an
image must be an attachment rather than a URL. Attach files separately and
reference them by `data-attachment-id`.

Old descriptions are **plain text** and stay that way: if the body contains
no `<`, render it with preserved whitespace rather than as HTML.

## 10. Endpoint map

Everything below is under `/api`; organisation-scoped routes are prefixed
`/organisations/{org_id}`. Full spec: `SITE_URL/api/openapi.json` — note the
`/api/auth/*` routes are **not** in it, since SuperTokens' middleware serves
them rather than FastAPI; §2 is their documentation.

| Area | Key routes |
|---|---|
| Session | `/auth/signup`, `/auth/signin`, `/auth/signout`, `/auth/session/refresh` |
| You | `/me`, `/me/tokens`, `/me/mfa/*`, `/me/notification-channels/*` |
| Cross-org | `/notifications`, `/reminders`, `/sparks`, `/organisations`, `/invites/{token}` |
| Tasks | `…/tasks` (list, `X-Total-Count`), `…/tasks/board`, `…/tasks/{id}`, `/closed`, `/hidden`, `/pin`, `/note`, `/events`, `/files`, `/checklists`, `/dependencies`, `/reminders`, `/revisions`, `/access`, `/recurrence` |
| Comments | `…/tasks/{id}/comments`, `…/projects/{id}/comments`, `…/comments/{id}` |
| Structure | `…/projects`, `…/project-groups`, `…/teams`, `…/members` |
| Screens | `…/dashboard`, `…/planner`, `…/calendar`, `…/search`, `…/notes`, `…/bookmarks`, `…/tags` |
| Knowledge base | `…/kb/books`, `…/kb/books/{id}/articles`, `…/kb/articles/{id}` (+`/edit-session`, `/private`, `/revisions`), `…/kb/revisions/{id}` (+`/files`) |
| Time | `…/tasks/{id}/time`, `/time/start`, `…/time/entries`, `…/time/summary`, `…/time/{entry_id}`, `/me/timer`, `/me/timer/stop` |
| Realtime | `WS /api/ws` |

Triage is not its own endpoint — it is `…/tasks` with the
"nobody action-required" filter.

## 11. Gaps that need backend work — decide before scoping

| Gap | Cost | Verdict |
|---|---|---|
| A PAT cannot drive `/api/*` (401), so a **token-only profile** can't list tasks | swapping auth in `deps.py` is small; enforcing `read`/`write` **scope** across ~40 routers is not — the REST API has no notion of a read-only credential today (`require_write` lives only in the MCP server) | Ship credentials-only first. Don't start here. |
| The socket needs a cookie or a PAT | none — mint a PAT after sign-in (§5) | Solved client-side. |
| `image/heic` uploads | allow-list entry **plus** HEIF support in the Pillow thumbnail worker | Convert client-side instead. |
| Offline | nothing exists; every screen is server-resolved, and access can be revoked between reads | Treat as cache-and-refetch, never as a writable local store. Don't promise offline editing. |
| Push notifications | none. There is a webhook channel and Telegram, but no APNs/FCM | Poll the inbox (the web app polls the badge every 60s) or add a channel later. |

## 12. Suggested first scope

The web app is ~30 screens at desk density. Porting all of it is how a mobile
app becomes unfriendly. What is genuinely *better* on a phone:

- **Ships first:** profiles + auth, tasks list/detail, triage, comments,
  voice notes, the timer, notifications, sparks, reminders.
- **Later:** planner, board, calendar, bookmarks, KB reading, dashboard.
- **Leave on the web:** sheets, KB authoring, org settings, working-hours
  grid, exports, access panels.

Sparks (⌘J quick capture on the web) and the running timer are the two
features people will open the app for daily. Build them early.

## 13. Dev loop

```bash
cd ../ayeaye && ./scripts/setup.sh && docker compose up -d   # http://localhost
./scripts/diagnose.sh                                        # when something's wrong
```

Mailpit at `http://localhost:8025` catches every outgoing email (verification
links, invites, password resets). Interactive API docs at
`http://localhost/api/docs`.

An emulator cannot reach `localhost` — use `10.0.2.2` (Android) or the host's
LAN IP, and set `SITE_URL` to match, since it configures both Caddy's site
address and the API's own domains and they cannot drift apart.
