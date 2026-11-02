# NotchCat Sync & Accounts — Future Plan

> Status: **planned, not started.** This is the agreed design for turning NotchCat
> from a local-only Mac app into an account-based, offline-first product that syncs
> across macOS, a future iOS app, and a future Windows app. Nothing here is built yet.

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

## Auth (real sign-up product)

- Email + password, **Argon2** hashing.
- Short-lived **access token** (JWT, ~15 min) + long-lived **refresh token** in the OS
  secure store (Keychain on macOS/iOS, Credential Manager on Windows).
- **Email verification + password reset** from the start.
- User table designed to allow **multiple auth methods per account** now, so adding
  **Sign in with Apple** for the iOS app later needs no migration.

## API surface (first cut)

```
POST /auth/signup            {email, password} -> tokens
POST /auth/login             {email, password} -> tokens
POST /auth/refresh           {refresh_token}   -> tokens
POST /auth/verify-email      {token}
POST /auth/request-reset     {email}
POST /auth/reset             {token, password}
GET  /me                                         -> user

POST /sync/push              {changes:[...]}    -> applied results
GET  /sync/pull?cursor=N                         -> {changes:[...], cursor:M}
```

## Rollout — tracer bullet first, then widen

**Pass 1 (first slice, prove the whole pipe):**
- FastAPI + Postgres on the Azure VM behind Caddy.
- `signup`, `login`, `refresh`, `me`.
- `push` / `pull` for **tasks only**.
- Mac client: an **Account** section in Settings (sign up / log in / signed-in state),
  Keychain token storage, the outbox + sync loop, tasks syncing end to end.
- Acceptance: edit a task on Mac offline → reconnect → it lands on the server; change it
  on the server → it pulls down.

**Later passes (explicitly not pass 1):**
- Widen sync to notes, reminders, focus sessions, settings.
- Note-body text merge.
- Email verification / reset UX polish; rate limiting, backups, monitoring.
- Sign in with Apple.
- **iOS client**, then **Windows client** (separate UI apps, same API).

## Open decisions (revisit when this work starts)

- Final hosting once there are paying users (Azure student VM is a starting point only).
- Whether to share a portable "core" across platforms later, or rebuild each client's UI
  natively against the shared API (current lean: native UI per platform, shared API).
- Domain name to use for the API.
```
