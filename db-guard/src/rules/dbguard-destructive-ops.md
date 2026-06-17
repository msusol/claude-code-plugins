# Database destructive operation guard

Intercepts `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, `DROP SCHEMA`, and
`ALTER TABLE … DROP COLUMN` before they execute. Mirrors the git-guard pattern:
a PreToolUse hook blocks direct Bash calls; the investigation-first workflow
below is the only sanctioned path through.

## What is guarded

Any Bash command or Python call that executes:

- `DROP TABLE` / `DROP TABLE IF EXISTS` (unless immediately followed by `CREATE TABLE` in the same migration block)
- `DROP DATABASE` / `DROP SCHEMA`
- `TRUNCATE TABLE` or bare `TRUNCATE <table>`
- `ALTER TABLE … DROP COLUMN`
- A migration file whose content contains any of the above

This applies regardless of how the SQL is invoked: inline `psql -c`, `psql -f`,
Python + psycopg2, SQLAlchemy `execute()`, or a migration runner.

## The hook

A PreToolUse hook at `~/.claude/scripts/db-guard-hook.zsh` intercepts destructive
SQL patterns in Bash tool calls. It exits 2 (blocking the tool call) and prints
instructions to follow the sanctioned workflow.

**Bypass sentinel:** prepend `DB_GUARD_SANCTIONED=1 ` to the command after the
sanctioned workflow is complete and the user has explicitly confirmed. The sentinel
is intentionally visible in the command shown before execution — that visibility is
the audit signal.

The hook only intercepts patterns visible in the Bash command string (e.g.
`psql -c "DROP TABLE ..."`). For Python-driven drops where the SQL is inside a script,
this rule is the enforcement layer — the hook is a secondary net, not the primary one.

## Sanctioned workflow (investigation-first)

Complete ALL steps before executing any destructive SQL.

### Step 1 — Count and sample the target

```sql
SELECT COUNT(*) FROM <schema>.<table>;
SELECT * FROM <schema>.<table> LIMIT 5;
```

Show the row count and sample rows to the user.

### Step 2 — Schema and dependency audit

```sql
-- Column schema
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = '<schema>' AND table_name = '<table>'
ORDER BY ordinal_position;

-- Geometry columns (PostGIS)
SELECT f_geometry_column, type, srid
FROM geometry_columns
WHERE f_table_schema = '<schema>' AND f_table_name = '<table>';

-- Inbound foreign keys
SELECT conname, conrelid::regclass AS referencing_table
FROM pg_constraint
WHERE confrelid = '<schema>.<table>'::regclass AND contype = 'f';

-- Views referencing the table
SELECT viewname FROM pg_views
WHERE definition ILIKE '%<table>%' AND schemaname = '<schema>';
```

List every FK, view, and index that depends on the table.

### Step 3 — Recovery check

State explicitly:

- Is there a backup or alternative data source?
- Is the data derivable from another table or file in the repo?
- What will be **irreversibly lost** if this proceeds?

### Step 4 — Present findings and confirm

Show the user a summary:

- Row count and what the data represents
- Dependencies (FKs, views) that will break
- What is irreversibly lost
- The exact SQL statement that will run

**Wait for explicit confirmation** — "yes", "proceed", or "confirmed". Silence,
ambiguity, or a prior instruction to "just do it" is not confirmation for a destructive
DB operation. Ask again.

### Step 5 — Execute with sentinel

Once confirmed, prepend `DB_GUARD_SANCTIONED=1` to bypass the hook:

```bash
DB_GUARD_SANCTIONED=1 psql "$DSN" -c "DROP TABLE public.old_parcels;"
```

For Python / migration runners:

```bash
DB_GUARD_SANCTIONED=1 python3 -m clp_parcel_ai.db.apply_migration \
  060_parcels
```

The sentinel is required even after verbal confirmation — it proves this workflow
was followed and makes the bypass visible in the audit trail.

## Narrow exceptions (no sanctioned workflow required)

These may proceed without the full workflow, but still require a one-line explanation:

- `DROP INDEX` / `DROP INDEX IF EXISTS` — reversible; index can be rebuilt.
- `DROP TABLE IF EXISTS <name>` where `<name>` clearly identifies a temp or staging table
  (name contains `_tmp`, `_staging`, `_temp`, or starts with `tmp_`).
- A migration that drops and immediately recreates the same table in a single transaction
  (`DROP TABLE … ; CREATE TABLE …` in one `BEGIN`/`COMMIT` block).

Even for exceptions, state what is being dropped and why before running the command.
