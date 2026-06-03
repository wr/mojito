# mojito-stats

Cloudflare Worker + D1 backend for Mojito's anonymous usage statistics. Lives
in this repo but is deployed independently of the macOS app and is **not** part
of the Xcode build.

## What it does

| Route | Who calls it | Notes |
|-------|--------------|-------|
| `POST /ingest` | Mojito.app, once a day | One anonymous aggregate per install. No identifier; the IP is never read or stored. |
| `GET /api/stats.json` | `mojito.wells.ee/stats` | Public marginal aggregates (CORS-allowed for the site). |

Storage is per-UTC-day counters only (see `schema.sql`) — no per-request rows,
no identifiers, no free text. Published output is pure marginals (each dimension
its own table; never cross-tabulated) with a light long-tail trim. The privacy
guarantees are structural, not statistical.

## First-time setup

```bash
cd stats-worker
npm install

# 1. Create the database, paste the printed database_id into wrangler.jsonc
npm run db:create

# 2. Apply the schema (local for `wrangler dev`, remote for production)
npm run db:init:local
npm run db:init:remote

# 3. Run locally
npm run dev
# POST a sample ping:
curl -s -XPOST localhost:8787/ingest -H 'content-type: application/json' -d '{
  "v":1,"app":"1.2.1","os":"26","arch":"arm64","lang":"en","skinTone":"default",
  "features":{"gifSearch":true,"symbols":false},
  "totals":{"emoji":12,"gif":1},"eggs":1,
  "emoji":{"1F600":5,"2764":3}
}'
curl -s localhost:8787/api/stats.json | jq

# 4. Ship it
npm run deploy
```

## Custom domain

The app posts to — and the stats page fetches from — `stats.mojito.wells.ee`.
After the first `wrangler deploy`, add the custom domain (uncomment the `routes`
block in `wrangler.jsonc`, or add it in the dashboard) and redeploy. The host
must match `TelemetryUploader.endpoint` in the app and the fetch URL on the
stats page.

## Schema changes

`schema.sql` is idempotent (`CREATE TABLE IF NOT EXISTS`). Re-run the
`db:init:*` scripts after editing it. For destructive migrations, write an
explicit migration file rather than editing in place.
