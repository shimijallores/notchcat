# NotchCat Sync & Accounts — Future Plan

> Status: **built** for the Mac: invite-only accounts, rate limiting, and sync of tasks, the notepad, focus sessions
> and settings (server in `../notchcat-server`, Mac client in `Sources/NotchCat/Sync`). iOS and Windows are still planned. Where this document
> and the server's README differ, the README describes what exists.

## Goal

One account. The same tasks, reminders, notes, and settings on every device the user
signs into. Works fully offline, then syncs quietly when the connection returns —
the way Apple Notes / Reminders feel, but on our own backend so it works on
Windows too and needs no Apple Developer account for sync.

## Why not iCloud

Ruled out, for two concrete reasons:

1. **CloudKit requires a paid Apple Developer account** ($99/yr), which we don't have.
2. **It's Apple-only.** There is no real native CloudKit client for Windows, and we
   want a Windows version. iCloud also ties data to the signed-in Apple ID per device,
   so a Windows PC can't join.

A self-hosted API on our own VPS keeps every platform on equal footing and removes the
Apple-account dependency from sync entirely. (A paid Apple Developer account is still
required later to *ship the iOS app on the App Store* — that's unavoidable — but not for
sync, and not for the Mac or Windows apps at all.)

## Architecture

```
  macOS (Swift)      iOS (Swift, later)     Windows (later)
        \                  |                    /
         \                 |                   /
          -------- HTTPS (REST + JSON) --------
                           |
                   Caddy (TLS, reverse proxy)   ← Azure VM (student sub)
                           |
                   FastAPI (Python)             ← the API
                           |
                   PostgreSQL                   ← canonical data
```

- **Server language: Python / FastAPI.** Async, typed (Pydantic), auto-generated
  OpenAPI docs that double as the contract future clients code against.
- **Database: PostgreSQL** on the server (real concurrent users). Each **client** keeps
  its existing local **SQLite** as the offline source of truth.
- **TLS: Caddy** for automatic Let's Encrypt HTTPS.
- **Host: Azure "for students" VM.** Fine for building and early users. Caveat: student
  credits can lapse and the VM can be deallocated — revisit hosting before this holds
  paying users' only copy of data. Needs a real **domain name** for TLS.

## Sync model: offline-first, field-level last-write-wins

Clients stay local-first. Each syncable row carries:

- `id` (UUID) — clients already generate these.
- `updated_at` — a **server-assigned logical clock** (a monotonic counter), not wall-clock
  time, to avoid device clock-skew bugs.
- `deleted_at` / `is_deleted` — **soft delete**, so deletions propagate instead of a row
  silently vanishing.
- **per-field timestamps** for the fields that matter (title, done, due date, order…),
  so "checked off on phone" and "renamed on Mac" both land instead of one clobbering
  the other. This is the key to the Notes-like feel without full CRDTs.

Conflict rule: **field-level last-write-wins.** Seamless for tasks / reminders / settings.
The one known limitation is the **notepad body** (free text): whole-field LWW means one
device's version of the paragraph wins. Acceptable for v1; the note body can be upgraded
to a text-merge / CRDT strategy later *without* touching the rest of the model.

### The protocol

Every client keeps an **outbox**: a local queue of changes made while offline.

1. **Push** — client sends its outbox. Server applies field-level LWW, bumps `updated_at`,
   returns the authoritative result for each row.
2. **Pull** — client sends a cursor ("everything changed since N"); server returns changed
   rows plus a new cursor.
3. Client merges results into local SQLite, stores the cursor, clears acked outbox entries.

Sync triggers: on a timer, on app foreground, and immediately when connectivity returns —
so the queue drains automatically and quietly.

## Auth: invite-only, with access keys

Decided after the first draft: nobody can create an account on their own.

- The owner generates **access keys** (`NC-XXXX-XXXX-XXXX-XXXX`) with a command-line tool on the server. There is
  no admin API. Keys are stored hashed and each works for one sign-up.
- A person enters their key once to **choose a username and password**. After that they sign in with the username.
- **Revoking a key** locks that account out (login, refresh and sync return 403) without touching their local data.
- Usernames, not email, so there is no mail service, verification or password-reset flow. The owner resets a
  password from the command line.
- Argon2 password hashes; short-lived access tokens (15 min) plus rotating refresh tokens (60 days) kept in the
  Keychain on macOS.
- Sign in with Apple stays a later option for the iOS app.

## API surface

See the server README for the current list. In short: `/v1/auth/{signup,login,refresh,logout}`, `/v1/me`,
`POST /v1/sync/push` and `GET /v1/sync/pull`.

## Rollout

**Done:**
- FastAPI + SQLAlchemy server (SQLite for tests, Postgres in production), access keys, accounts, rate limits.
- Sync of tasks, the notepad (with conflict handling that keeps both texts), focus sessions and shared settings.
- Mac: a "Cloud sync" section in Settings, Keychain-stored login, a queue of unsent field edits, tombstones for
  deletes, background sync (after edits, every minute, and when the network returns).
- Verified with an end-to-end test of two devices syncing through a live server (`--selftest-sync`).

**Next:**
- Deploy to the Azure VM (Postgres, TLS, a process manager) and make its address the app's default.
- Alembic migrations, backups.
- **iOS client**, then **Windows client** (separate UI apps, same API).

## Open decisions

- Final hosting once there are many users (the Azure student VM is a starting point only).
- Whether to share a portable core across platforms later, or rebuild each client's UI natively against the shared
  API (current lean: native UI per platform, shared API).
- Domain name for the API.
