# Rianganizze API

A professional, API-only **personal finance** REST API inspired by Organizze.
Ruby 3.3 · Rails 8 · PostgreSQL · JWT · RSpec.

It covers the financial core only: **accounts, credit cards, categories,
income/expense transactions, balances and a dashboard**. No goals, investments,
reports, notifications, bank integrations, sharing or multi-tenant complexity —
by design.

---

## Quick start (Docker)

```bash
cp .env.example .env
docker compose build
docker compose up            # API on http://localhost:3000
docker compose run --rm api bin/rails db:seed   # demo data
docker compose run --rm api bundle exec rspec    # tests + coverage
docker compose run --rm api bundle exec rubocop  # lint
```

Demo login: `demo@rianganizze.com` / `password123`.

## Quick start (local, needs Ruby 3.3 + Postgres)

```bash
bundle install
bin/setup                    # db:prepare + seed
bin/rails server
```

---

## Architecture

```
app/
  controllers/api/v1   thin controllers: parse params, call a service/query, render
  controllers/concerns JWT auth · standardized responses · global error handling
  models               persistence + invariants only (validations, scopes)
  services             one business operation each, return a Result object
  queries              read-side filtering & aggregation (index, dashboard)
  serializers          plain-Ruby JSON shaping (no external dep)
  policies             ownership checks (seam for future sharing/roles)
  jobs                 async work (none required yet)
lib/json_web_token.rb  JWT encode/decode wrapper
```

### Key decisions & trade-offs

- **Service Objects with a `Result`** (`success?/failure?/data/errors`) instead of
  raising for control flow. Controllers stay branch-only and reusable from jobs.
  Trade-off: a little boilerplate vs. predictable, testable flows.
- **Query objects** (`TransactionsQuery`, `DashboardQuery`) own filtering and
  aggregation so controllers never build complex scopes and the logic is reused
  by exports/reports later.
- **PORO serializers** over `jsonapi-serializer`/`blueprinter`. Zero deps, total
  control of the JSON envelope. Trade-off: manual, but trivial here.
- **Soft delete** via `archived_at` + `default_scope { kept }` and an overridden
  `#destroy`. Financial history is never physically lost. Trade-off: must use
  `.unscoped`/`.archived` to reach archived rows (intentional).
- **Money as `decimal(14,2)`** — exact, simple to serialize. (Integer cents is the
  main alternative; decimal is enough at this scope.)
- **Balances are computed, not stored** (`Accounts::BalanceCalculator`). One source
  of truth, no cache invalidation bugs. Trade-off: a few aggregate queries per
  read — fine now; cache later if needed.
- **JWT (HS256), stateless.** No session table. Trade-off: no server-side
  revocation yet (see Future work).
- **Ownership by scoping**: every query goes through `current_user.association`,
  so cross-user access is impossible even before policies are consulted.

### Transaction creation flow

`POST /transactions` → `Transactions::CreateTransaction.call(user:, params:)`
builds the record **through the user association** (guaranteeing ownership),
saves it, and the model enforces invariants: amount > 0, exactly one source
(account XOR credit card), category kind matches the transaction kind, and credit
cards accept expenses only. Failures come back as a `Result` → `422` with
`errors`.

### Dashboard strategy

`DashboardQuery` aggregates a month (paid totals, pending forecast, expense by
category) with grouped SQL sums; `BalanceCalculator` adds consolidated balance,
per-account balances and per-card open invoices. `DashboardSerializer` merges
both into one payload — no N+1 beyond the bounded per-account sums.

---

## Standardized JSON

**Single resource**
```json
{ "data": { "id": 1, "name": "Main Checking", "current_balance": "5420.5" } }
```

**Collection (paginated)**
```json
{
  "data": [ { "id": 12, "description": "Groceries", "amount": "120.5", "kind": "expense" } ],
  "meta": { "pagination": { "page": 1, "items": 25, "count": 1, "pages": 1, "next": null, "prev": null } }
}
```

**Auth**
```json
{ "data": { "token": "eyJhbGci...", "user": { "id": 1, "email": "demo@rianganizze.com" } } }
```

**Error**
```json
{ "message": "Validation failed", "errors": ["Amount must be greater than 0"] }
```

**Dashboard** (`GET /api/v1/dashboard?month=2026-05`)
```json
{
  "data": {
    "period": { "from": "2026-05-01", "to": "2026-05-31" },
    "totals": { "income": "6500.0", "expense": "420.5", "net": "6079.5" },
    "forecast": { "income": "0.0", "expense": "60.0" },
    "by_category": [ { "category_id": 5, "total": "420.5" } ],
    "consolidated_balance": "5879.5",
    "accounts": [ { "id": 1, "name": "Main Checking", "current_balance": "6079.5" } ],
    "credit_cards": [ { "id": 1, "name": "Visa Platinum", "open_invoice": "60.0", "available_limit": "9940.0" } ]
  }
}
```

## Endpoints

| Method | Path | Notes |
|--------|------|-------|
| POST | `/api/v1/auth/register` | returns JWT + seeds default categories |
| POST | `/api/v1/auth/login` | returns JWT |
| GET  | `/api/v1/auth/me` | current user |
| CRUD | `/api/v1/accounts` | soft delete |
| CRUD | `/api/v1/credit_cards` | soft delete |
| CRUD | `/api/v1/categories` | `?kind=income|expense` |
| CRUD | `/api/v1/transactions` | filters: `kind, account_id, credit_card_id, category_id, paid, from, to, search, sort, direction`; paginated |
| GET  | `/api/v1/dashboard` | `?month=YYYY-MM` |
| GET  | `/api/v1/dashboard/balances` | consolidated + per-account/card |

Auth: send `Authorization: Bearer <token>` on every endpoint except register/login.

## Testing & coverage

RSpec + FactoryBot + Shoulda-matchers; SimpleCov (branch coverage) is wired and
grouped by layer. The structure is built for 100% coverage — example model,
service and request specs are included; `minimum_coverage` is `0` so you can fill
the suite in incrementally, then raise the gate.

## Future improvements

- Recurring transactions & credit-card installments (the `CreateTransaction`
  service is the natural seam).
- Cached/materialized balances once data volume grows.
- JWT refresh tokens + a denylist for revocation.
- Real invoice periods using each card's closing/due day.
- Background jobs (Sidekiq) for reports/exports; `ApplicationJob` is ready.
- Reports, budgets/goals, multi-currency, shared accounts via the policy layer.
