"""Idempotent Snowflake loads: stage rows in a temp table, MERGE on the primary key, all inside
one explicit transaction. Any failure rolls the target back and re-raises so Airflow retries.

Re-running with the same input leaves the target unchanged (MERGE upserts on the key), which is
what makes retries and backfills safe.
"""

from __future__ import annotations

import logging

from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

log = logging.getLogger(__name__)


def merge_rows(
    conn_id: str,
    table: str,
    ddl: str,
    columns: list[str],
    key_columns: list[str],
    rows: list[dict],
) -> dict:
    """Upsert `rows` into `table` (created from `ddl` if missing). Returns MERGE counts."""
    if not rows:
        raise ValueError(f"refusing to load 0 rows into {table}")

    tmp = f"{table.rsplit('.', 1)[0]}.TMP_{table.rsplit('.', 1)[1]}"
    col_list = ", ".join(columns)
    placeholders = ", ".join(f"%({c})s" for c in columns)
    on = " AND ".join(f"t.{k} = s.{k}" for k in key_columns)
    non_keys = [c for c in columns if c not in key_columns]
    update_set = ", ".join([f"{c} = s.{c}" for c in non_keys] + ["loaded_at = SYSDATE()"])
    insert_vals = ", ".join([f"s.{c}" for c in columns] + ["SYSDATE()"])

    conn = SnowflakeHook(snowflake_conn_id=conn_id).get_conn()
    cur = conn.cursor()
    try:
        # DDL auto-commits in Snowflake, so it runs before the explicit transaction.
        cur.execute(ddl)
        cur.execute(f"CREATE OR REPLACE TEMPORARY TABLE {tmp} AS SELECT {col_list} FROM {table} WHERE 1 = 0")

        cur.execute("BEGIN")
        cur.executemany(f"INSERT INTO {tmp} ({col_list}) VALUES ({placeholders})", rows)
        cur.execute(f"""
            MERGE INTO {table} t
            USING (
                SELECT * FROM {tmp}
                QUALIFY ROW_NUMBER() OVER (PARTITION BY {", ".join(key_columns)} ORDER BY 1) = 1
            ) s
            ON {on}
            WHEN MATCHED THEN UPDATE SET {update_set}
            WHEN NOT MATCHED THEN INSERT ({col_list}, loaded_at) VALUES ({insert_vals})
        """)
        inserted, updated = cur.fetchone()[:2]
        cur.execute("COMMIT")
        log.info("%s: merged %d rows (%d inserted, %d updated)", table, len(rows), inserted, updated)
        return {"table": table, "rows_in": len(rows), "inserted": inserted, "updated": updated}
    except Exception:
        log.exception("load into %s failed; rolling back", table)
        cur.execute("ROLLBACK")
        raise
    finally:
        cur.close()
        conn.close()


def scalar(conn_id: str, sql: str, params: dict | None = None, setup_sql: str | None = None):
    """Run a single-value query (used for incremental-window checks).

    `setup_sql` (e.g. CREATE TABLE IF NOT EXISTS) runs first so the very first run works too.
    """
    conn = SnowflakeHook(snowflake_conn_id=conn_id).get_conn()
    try:
        cur = conn.cursor()
        if setup_sql:
            cur.execute(setup_sql)
        cur.execute(sql, params or {})
        row = cur.fetchone()
        return row[0] if row else None
    finally:
        conn.close()
