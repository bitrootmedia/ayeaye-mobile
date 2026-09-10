# ayeaye mobile

A Flutter client for [ayeaye](../ayeaye), built against the handoff notes in
[`NOTES-API.md`](NOTES-API.md). Multi-profile by design: an ayeaye instance is
one URL plus one credential set, and self-hosted instances are the normal case.

UI is [shadcn_ui](https://pub.dev/packages/shadcn_ui); state is Riverpod 3;
routing is go_router.

---

## Running it

The machine's default Flutter (`~/development/flutter`) is **3.29**, which is
too old — every published `shadcn_ui` needs 3.35+. Rather than upgrade an SDK
that the other Flutter projects here share, this project pins its own checkout
and `tool/fl` runs it:

```bash
tool/fl analyze
tool/fl test
tool/fl run -d <device>
```

The pinned SDK is a **git worktree** of the existing clone, so it shares the
object store instead of downloading Flutter twice:

```bash
cd ~/development/flutter
git fetch --tags origin stable
git worktree add --detach ~/development/flutter-3.47.2 3.47.2
```

Override the location with `AYEAYE_FLUTTER=/path/to/sdk`.

### Toolchain gaps to close before building for a device

`tool/fl analyze` and `tool/fl test` work today. Building the app does not yet,
and none of it is a code problem:

| Gap | Needed |
|---|---|
| Xcode 13.4.1 | Flutter 3.47 needs **Xcode 15+** (its build passes `-skipPackagePluginValidation`, which 13.x rejects) |
| CocoaPods missing | `brew install cocoapods` — without it no iOS/macOS plugin links |
| Android SDK 35 | Flutter 3.47 wants **SDK 36**; also `tool/fl doctor --android-licenses` |

Once Xcode is current, `tool/fl run -d macos` is the quickest smoke test.

### Pointing it at a local instance

```bash
cd ../ayeaye && ./scripts/setup.sh && docker compose up -d   # http://localhost
```

An emulator cannot reach `localhost` — use `10.0.2.2` (Android) or the host's
LAN IP, and set `SITE_URL` to match, since it configures both Caddy's site
address and the API's own domains.

`http://` is **allowed, not blocked** — the profile form warns instead. Android
sets `usesCleartextTraffic`, iOS sets `NSAllowsArbitraryLoads`, both on purpose.

---

## What is built

**Stage 1 — profiles, auth, tasks, triage, comments, voice notes**

- Profile list and switcher; several instances signed in at once, each with a
  fully independent token set and no shared "current session"
- Register / sign in / sign back in, and both session gates (2FA, email
  verification)
- Task list with server-side filters and sort that survive a restart, paged on
  `X-Total-Count`
- Task detail: description, metadata, checklists, files, quick actions
- Triage — the "nobody action-required" queue, with the three answers to
  "who holds this?" on every row
- Comments, with photo attachments and voice notes (AAC in MP4)
- The running timer, ticking, wherever you might put the phone down

**Stage 2 — notifications, sparks, reminders**

- Inbox: notifications and reminders together, badge polled every 60s
- Quick capture (the web app's ⌘J) and the spark list, with "make a task"
- Reminders, task-scoped and standalone

**Stage 3 — planner, board, calendar, bookmarks, KB**

- Planner: the five buckets, moved by tapping rather than dragging
- Board: horizontally paged columns that report each column's real size
- Calendar: an agenda grouped by day, not a 40px-per-day grid
- Bookmarks, and the knowledge base for reading

Also: search across the organisation, organisation and profile switching,
settings (profile, password, TOTP enrolment, daily summary).

**Deliberately left on the web**, as the notes recommend: sheets, KB authoring,
org settings, the working-hours grid, exports, access panels.

---

## How it is put together

```
lib/
  core/
    api/        ApiClient (the token lifecycle), Repo (every endpoint), errors
    auth/       Profile, keychain store, AuthController, Front-Token parsing
    models/     models.dart — 144 DTOs generated from the OpenAPI document
    realtime/   the WebSocket, authenticated with a personal access token
    upload/     the three-step upload
  features/     one directory per screen area
  ui/           theme, formatting, shared widgets
tool/
  gen_models.py   regenerates lib/core/models/models.dart
  openapi.json    the contract the app was built against
  fl              runs the pinned Flutter
```

### Decisions worth knowing

**The token lifecycle is hand-rolled.** `supertokens_flutter` is built around
one `apiDomain` per `init()`, which is exactly what multi-profile breaks. Each
profile owns an `ApiClient` that stores `(baseUrl, accessToken, refreshToken,
ate)` in the keychain, refreshes pre-emptively from `ate` rather than waiting
for a 401, and retries once.

**`St-*` headers are read on every response, including 204s.** The 2FA
challenge answers 204 with a *new* access token and the old one keeps returning
403 forever — a client that skips header parsing there completes 2FA and stays
locked out. There is a test for it.

**Both session gates are matched by shape, never by status code.** An ordinary
403 must not be mistaken for `st-mfa-ok` or `st-ev`. Clearing the email gate
refreshes the session, because verification is recorded against the account
while the token still carries the stale claim.

**`GET /api/me` gates the whole UI.** It creates the local user row on first
sight and binds pending invitations, so nothing else is fetched until it
answers. It also sends the device's IANA timezone, since reminders, the
deadline sweep and the daily digest all compute "today" per user zone.

**The socket uses a personal access token.** `WS /api/ws` takes a cookie or a
PAT, and a header-mode client has neither — its SuperTokens access token is not
a PAT. Sign-in mints one at `read` scope and stores it in the profile; removing
a profile revokes it. Events carry no bodies, so every nudge means "refetch
over HTTP", coalesced for 1.5s.

**Uploads echo the server's content type.** The signature covers `Content-Type`
byte for byte, so the value the ticket returns is the only one that works.
HEIC is converted to JPEG client-side because it is not on the allow-list and
is the iPhone camera's default. Size is checked locally, since the real check
happens at *confirm* — after the bytes are already up.

**Render HTML, edit markdown.** Bodies are sanitised HTML on a narrow
allow-list that no Flutter editor emits, but the write endpoints accept
`description_format: markdown`. A body with no `<` in it is plain text and is
rendered with its whitespace intact.

**404 means not found, never forbidden.** No access reads as 404 on this API,
so a deleted task and a revoked one are indistinguishable and both say
"not found". Controls that a `can_*` flag denies are hidden rather than shown
to fail.

### Models are generated, not hand-written

`tool/gen_models.py` turns the OpenAPI document into 144 tolerant DTOs:

```bash
python3 tool/gen_models.py tool/openapi.json lib/core/models
```

Tolerant on purpose — every field reads through the helpers in `json.dart`, so
an unexpected null renders a blank field instead of a red screen. Refresh
`tool/openapi.json` from `SITE_URL/api/openapi.json` and re-run after an API
change.

---

## Tests

```bash
tool/fl test
```

84 tests, no device or running instance needed:

- **`api_client_test.dart`** — the token lifecycle over a faked transport:
  bearer auth, `X-Total-Count`, rotation absorbed from a 204, refresh-and-retry
  once, collapsed concurrent refreshes, both gates by shape, 404 vs 403,
  SuperTokens' `message` key, and the presigned PUT
- **`session_tokens_test.dart`** — Front-Token parsing, staleness, gate shapes
- **`upload_test.dart`** — declare → PUT → confirm in order, the content-type
  echo, the local size cap, and that HEIC is never declared
- **`endpoints_test.dart`** — every path `Repo` builds is checked against
  `tool/openapi.json`, so a typo in one of ~90 endpoints fails a test instead
  of a screen
- **`app_flow_test.dart`** — boots the real app over a fake instance: welcome,
  signed-out, dashboard, PAT minting, timezone sync, unreachable instance
- **`screens_test.dart`** — task list, triage's filter and actions, task detail
  with its thread, the More hub, planner buckets, board column sizes, inbox
- **`layout_sweep_test.dart`** — every screen at 320×568 with a 1.3× text
  scale, plus dark mode. Flutter reports an overflow as an error, so this is a
  real assertion; it found six genuine overflow bugs, all in rows of buttons.

One thing worth knowing if you extend the UI: **`ShadButton` sizes itself to
its content and lets `maxWidth` go to infinity**, so it ignores an `Expanded`
or `SizedBox` slot and overflows rather than shrinking. Use `Wrap` with natural
widths, or an `InkWell` when the label must ellipsise.

---

## Not done

- **No push notifications** — the server has no APNs/FCM channel, only webhooks
  and Telegram. The badge polls every 60s, as the web app does.
- **No offline writes.** Every screen is server-resolved and access can be
  revoked between reads; this is cache-and-refetch, never a writable local
  store.
- **No token-only profiles.** A PAT cannot drive `/api/*` (401), and giving the
  REST API a read-only credential is a backend job. Credentials-only for now.
- Not yet run on a real device — see the toolchain gaps above.
