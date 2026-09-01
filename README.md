# Rialign API

A professional, **API-only personal finance** REST API inspired by Organizze.
Ruby 3.3 · Rails 8 · PostgreSQL · JWT · RSpec.

It covers the financial core only: **bank accounts, credit cards, categories,
income/expense transactions, account balances, consolidated balance and a
dashboard**. By design it does *not* include goals, investments, advanced
reports, notifications, bank integrations, sharing or multi-tenant complexity.

---

## Requirements

- **Ruby 3.3.0** on the host (see `.ruby-version`). Install it with
  [rbenv](https://github.com/rbenv/rbenv), which manages **Ruby only** and does
  not touch an existing `nvm`/Node setup:

  ```bash
  brew install rbenv ruby-build
  echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc && exec zsh
  rbenv install 3.3.0           # picked up automatically via .ruby-version
  ```

- **Docker** (Docker Desktop, or Docker Engine + Compose v2) — used *only* to
  run PostgreSQL locally. The app itself always runs natively, in development
  and in production; there is no application image and no `Dockerfile`.

---

## Getting started

```bash
cd rialign-api
cp .env.example .env          # sane defaults; edit if needed
bundle install
docker compose up -d          # starts PostgreSQL on localhost:5432
bin/rails db:prepare          # create databases, load schema, seed demo data
bin/rails server              # API on http://localhost:3000
```

`db:prepare` creates the databases, loads the schema **and seeds demo data**
(because the DB is brand new). You'll see:

```
Created database 'rialign_development'
Seeding demo data...
  created user demo@rialign.com / password123
  created sample transactions
```

That's it — the API is live with a demo account.

**Demo credentials:** `demo@rialign.com` / `password123`

### Re-seeding manually

Seeds are idempotent, so you can run them any time:

```bash
bin/rails db:seed
```

### Resetting the database

```bash
bin/rails db:reset   # drop, recreate, load schema, seed
```

---

## Try it end to end

With the server running (`bin/rails server`):

```bash
# 1. Health check (no auth) -> empty 200
curl -i localhost:3000/up

# 2. Log in -> returns a JWT
curl -s -X POST localhost:3000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"demo@rialign.com","password":"password123"}'
```

```json
{ "data": { "token": "eyJhbGci...", "user": { "id": 1, "name": "Demo User", "email": "demo@rialign.com" } } }
```

```bash
# 3. Use the token on a protected endpoint
TOKEN=<paste token from step 2>
curl -s localhost:3000/api/v1/dashboard -H "Authorization: Bearer $TOKEN"
```

```json
{
  "data": {
    "period": { "from": "2026-05-01", "to": "2026-05-31" },
    "totals": { "income": "6500.0", "expense": "420.5", "net": "6079.5" },
    "forecast": { "income": "0.0", "expense": "60.0" },
    "by_category": [ { "category_id": 5, "total": "420.5" }, { "category_id": 8, "total": "60.0" } ],
    "consolidated_balance": "11379.5",
    "accounts": [
      { "id": 1, "name": "Main Checking", "current_balance": "11079.5", "initial_balance": "5000.0", "archived": false },
      { "id": 2, "name": "Cash Wallet", "current_balance": "300.0", "initial_balance": "300.0", "archived": false }
    ],
    "credit_cards": [
      { "id": 1, "name": "Visa Platinum", "open_invoice": "60.0", "available_limit": "9940.0", "credit_limit": "10000.0" }
    ]
  }
}
```

How those numbers come together: Main Checking = `5000 + 6500 − 420.50 = 11079.50`;
consolidated = `11079.50 + 300 = 11379.50`. The cinema charge (60, unpaid, on the
credit card) is excluded from balances and instead appears in `forecast.expense`
and the card's `open_invoice`.

---

## Common commands

| Task | Command |
|------|---------|
| Start PostgreSQL | `docker compose up -d` |
| Stop PostgreSQL | `docker compose down` |
| Start the API | `bin/rails server` |
| Run the test suite + coverage | `bundle exec rspec` |
| Lint | `bundle exec rubocop` |
| Rails console | `bin/rails console` |
| Run migrations | `bin/rails db:migrate` |
| Seed demo data | `bin/rails db:seed` |
| Reset the DB | `bin/rails db:reset` |

The `db` service is `restart: unless-stopped`, so once started it comes back on
its own whenever Docker starts — `docker compose up -d` is a one-time step, not
part of the daily loop. Day to day you only run `bin/rails server`.

Postgres data lives in the `pg_data` volume and survives both `docker compose
down` and a container recreation; use `docker compose down -v` to wipe it.

---

## Configuration (environment variables)

Defined in `.env` (copied from `.env.example`) and loaded by `dotenv-rails` in
development and test.

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATABASE_HOST` | `localhost` | Postgres host |
| `DATABASE_PORT` | `5432` | Postgres port |
| `DATABASE_USERNAME` | `postgres` | Postgres user |
| `DATABASE_PASSWORD` | `postgres` | Postgres password |
| `DATABASE_NAME` | `rialign_development` | Dev database name |
| `JWT_SECRET_KEY` | falls back to `secret_key_base` | **Required in production**; signs JWTs |
| `CORS_ORIGINS` | `*` | Comma-separated allowed origins |
| `RAILS_MAX_THREADS` | `5` | Puma / DB pool size |

---

## API surface

All endpoints live under `/api/v1`. Auth is via `Authorization: Bearer <token>`
on every endpoint except `auth/register` and `auth/login`. Resources:
`accounts`, `credit_cards`, `categories`, `transactions` (full CRUD) plus
`dashboard`. The full route list is in `config/routes.rb`.

Standard response envelope: `{ "data": ... }` on success (with a `meta.pagination`
block on collections) and `{ "message": ..., "errors": [...] }` on failure.

---

## Architecture

```
app/
  controllers/api/v1   thin controllers: parse params, call a service/query, render
  controllers/concerns JWT auth · standardized responses · global error handling
  models               persistence + invariants only (validations, scopes)
  services             one business operation each, return a Result object
  queries              read-side filtering & aggregation (index, dashboard)
  serializers          plain-Ruby JSON shaping (no external dependency)
  policies             ownership checks (seam for future sharing/roles)
  jobs                 async work (none required yet)
lib/json_web_token.rb  JWT encode/decode wrapper
```

### Key decisions & trade-offs

- **Service Objects returning a `Result`** (`success?/failure?/data/errors`)
  instead of raising for control flow. Controllers stay branch-only and the
  same operation is reusable from jobs. Trade-off: a little boilerplate.
- **Query objects** (`TransactionsQuery`, `DashboardQuery`) own filtering and
  aggregation, keeping controllers thin and the logic reusable.
- **PORO serializers** over a gem. Zero deps, total control of the JSON shape.
- **Soft delete** via `archived_at` + `default_scope { kept }` and an overridden
  `#destroy`. Financial history is never physically deleted; use
  `.unscoped` / `.archived` to reach archived rows.
- **Money as `decimal(14,2)`** — exact arithmetic. Note it serializes to JSON as
  a **string** (e.g. `"120.5"`) to avoid float precision loss on the client.
- **Balances are computed, not stored** (`Accounts::BalanceCalculator`). One
  source of truth, no cache-invalidation bugs. Cache later if needed.
- **Stateless JWT (HS256)**, 24h expiry, no session table. No server-side
  revocation yet (see Future work).
- **Ownership by scoping**: every query runs through `current_user.association`,
  so cross-user access is impossible even before policies are consulted.

### Transaction creation flow

`POST /transactions` → `Transactions::CreateTransaction.call(user:, params:)`
builds the record **through the user association** (guaranteeing ownership) and
saves it. The model enforces the invariants: `amount > 0`, **exactly one source**
(account XOR credit card), category `kind` must match the transaction `kind`, and
credit cards accept **expenses only**. Failures return a `Result` → `422` with an
`errors` array.

### Dashboard strategy

`DashboardQuery` aggregates a month (paid totals, pending forecast, expense by
category) with grouped SQL sums; `BalanceCalculator` adds the consolidated
balance, per-account balances and per-card open invoices. `DashboardSerializer`
merges both into one payload.

---

## Domain model

| Model | Key fields | Notes |
|-------|-----------|-------|
| `User` | name, email, password_digest | `has_secure_password`; email unique (case-insensitive) |
| `Account` | name, account_type, initial_balance | `checking/savings/cash/other`; soft-deletable |
| `CreditCard` | name, credit_limit, closing_day, due_day | soft-deletable |
| `Category` | name, kind, color | `income` or `expense`; soft-deletable |
| `Transaction` | description, kind, amount, date, paid | references a category and exactly one of account/credit_card; soft-deletable |

`paid: true` counts toward balances; `paid: false` is a scheduled/pending entry
that shows up only in dashboard forecasts and credit-card open invoices.

---

## Testing & coverage

RSpec + FactoryBot + Shoulda-matchers; SimpleCov (branch coverage) is wired and
grouped by layer (Services / Queries / Serializers / Policies).

```bash
bundle exec rspec
```

The suite currently passes (model, service and request examples included). The
project is structured for 100% coverage; `minimum_coverage` in
`spec/spec_helper.rb` is `0` so you can fill the suite in incrementally, then
raise the gate to enforce it.

---

## Things worth knowing

- **Money is JSON-encoded as a string** (`"120.5"`), not a number — parse
  accordingly on the client to keep decimal precision.
- **Soft delete:** `DELETE` sets `archived_at`; the record disappears from normal
  queries but is retained. There is no hard-delete endpoint by design.
- **JWT expiry is 24h.** There's no refresh endpoint yet; clients re-login.
- **Default categories** are created automatically on registration (and in seeds).
- **Test host:** request specs set `host! "example.test"` in `spec/rails_helper.rb`.
  This is required because rspec-rails injects `.localhost`/`.test` host patterns
  into `config.hosts`, and the default integration host `www.example.com` matches
  none of them — without it, Host Authorization returns `403` before the request
  reaches the controller.

---

## Future improvements

- Recurring transactions & credit-card installments (the `CreateTransaction`
  service is the natural seam).
- Cached/materialized balances once data volume grows.
- JWT refresh tokens + a denylist for revocation.
- Real invoice periods using each card's closing/due day.
- Background jobs (Sidekiq) for reports/exports; `ApplicationJob` is ready.
- Reports, budgets/goals, multi-currency, shared accounts via the policy layer.
```
