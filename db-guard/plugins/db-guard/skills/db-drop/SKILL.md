---
name: db-drop
description: >
  Use this skill whenever the user wants to drop a database table, truncate a table,
  drop a schema, drop a database, or remove a column. Trigger on: /db-drop,
  "drop this table", "truncate the table", "remove that table", "wipe the table",
  "recreate the schema", "apply this destructive migration", or any request to
  execute irreversible SQL that removes data or schema objects.
  This is the ONLY sanctioned path for database destructive operations — it enforces
  the investigation-first workflow and requires explicit per-step confirmation.
version: 1.0.0
---

# db-guard: Safe Database Destructive Operation Workflow

This skill walks through the investigation-first workflow before any DROP or TRUNCATE.
Use `DB_GUARD_SANCTIONED=1` as the bypass sentinel on the final command — the PreToolUse
hook recognises it as the sanctioned path and allows the operation through.

## Step 1 — Identify the target

State the operation to be performed:

- Table name, schema, and database
- Operation: `DROP TABLE`, `TRUNCATE`, `DROP SCHEMA`, `ALTER TABLE … DROP COLUMN`
- Why it is needed

## Step 2 — Count and sample

Run in parallel:

```sql
SELECT COUNT(*) FROM <schema>.<table>;
SELECT * FROM <schema>.<table> LIMIT 5;
```

Show the results. If the table doesn't exist, state that and skip to Step 6.

## Step 3 — Schema and dependency audit

```sql
-- Column schema
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = '<schema>' AND table_name = '<table>'
ORDER BY ordinal_position;

-- Inbound foreign keys
SELECT conname, conrelid::regclass AS referencing_table
FROM pg_constraint
WHERE confrelid = '<schema>.<table>'::regclass AND contype = 'f';

-- Views referencing the table
SELECT viewname FROM pg_views
WHERE definition ILIKE '%<table>%' AND schemaname = '<schema>';

-- Indexes
SELECT indexname FROM pg_indexes
WHERE tablename = '<table>' AND schemaname = '<schema>';
```

For PostGIS tables, also run:

```sql
SELECT f_geometry_column, type, srid
FROM geometry_columns
WHERE f_table_schema = '<schema>' AND f_table_name = '<table>';
```

Show all findings.

## Step 4 — Recovery assessment

State explicitly:

- Is there a backup or snapshot of this data?
- Can the data be rebuilt from another source (shapefile, CSV, scrape)?
- What is **irreversibly lost** if this operation runs?

## Step 5 — Present summary and confirm

Present a single clear summary block to the user:

```
Table:     public.<table>
Rows:      <count>
Columns:   <list>
FKs in:    <list or "none">
Views:     <list or "none">
Recovery:  <yes/no + source>
Lost:      <what cannot be recovered>

Operation: DROP TABLE public.<table>;
```

Ask: **"Proceed with this DROP? (yes / no)"**

Wait for an explicit "yes", "proceed", or "confirmed". Do not infer consent from
prior conversation. If the user says no, stop and report current state.

## Step 6 — Execute with sentinel

Only after explicit confirmation:

```bash
DB_GUARD_SANCTIONED=1 psql "$DSN" -c "DROP TABLE <schema>.<table>;"
```

Or for a migration file:

```bash
DB_GUARD_SANCTIONED=1 python3 -m <project>.db.apply_migration <migration_name>
```

The `DB_GUARD_SANCTIONED=1` prefix is required — the PreToolUse hook blocks the
command without it, even after verbal confirmation.

Show the result (rows affected, confirmation message, or error).

## Step 7 — Post-drop verification

Confirm the operation succeeded:

```sql
SELECT to_regclass('<schema>.<table>');
-- Returns NULL if the table no longer exists
```

Report the result to the user.

## Decision discipline

Never execute a DROP or TRUNCATE without completing Steps 2–4 and receiving
explicit confirmation in Step 5. A prior "just do it" or "proceed" from earlier
in the conversation is not sufficient — ask fresh for destructive DB operations.

If at any step the user says stop, abort cleanly and report the current table state.
