# Performance Optimization Reference

Complete guide to PostgreSQL query tuning and performance optimization with Bun.sql.

## EXPLAIN ANALYZE

### Basic Usage

```typescript
const plan = await sql`
  EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
  SELECT * FROM orders o
  JOIN customers c ON c.id = o.customer_id
  WHERE o.created_at > NOW() - INTERVAL '30 days'
`;
```

### EXPLAIN Options

| Option | Description |
|--------|-------------|
| `ANALYZE` | Execute query and show actual times |
| `BUFFERS` | Show buffer usage (hits, reads, writes) |
| `COSTS` | Show estimated costs (default: on) |
| `TIMING` | Show actual timing (default: on with ANALYZE) |
| `VERBOSE` | Show additional output |
| `FORMAT` | JSON, TEXT, XML, YAML |

### Reading EXPLAIN Output

```sql
                                     QUERY PLAN
------------------------------------------------------------------------------------
 Hash Join  (cost=1.11..2.19 rows=3 width=74) (actual time=0.025..0.028 rows=3 loops=1)
   Hash Cond: (o.customer_id = c.id)
   Buffers: shared hit=2
   ->  Seq Scan on orders o  (cost=0.00..1.03 rows=3 width=40) (actual time=0.005..0.006 rows=3 loops=1)
         Buffers: shared hit=1
   ->  Hash  (cost=1.05..1.05 rows=5 width=38) (actual time=0.009..0.010 rows=5 loops=1)
         Buckets: 1024  Batches: 1  Memory Usage: 9kB
         Buffers: shared hit=1
         ->  Seq Scan on customers c  (cost=0.00..1.05 rows=5 width=38) (actual time=0.003..0.004 rows=5 loops=1)
               Buffers: shared hit=1
 Planning Time: 0.109 ms
 Execution Time: 0.056 ms
```

#### Key Metrics

| Metric | Meaning | Problem If |
|--------|---------|------------|
| `cost=X..Y` | Estimated startup..total cost | Y is high |
| `rows=N` | Estimated rows | Very different from actual |
| `actual rows=N` | Actual rows returned | N is high |
| `loops=N` | Times node executed | N * rows matters |
| `Buffers: shared hit=N` | Pages from cache | Good |
| `Buffers: shared read=N` | Pages from disk | High = I/O bound |
| `Seq Scan` | Full table scan | On large tables |

---

## Common Performance Issues

### Issue 1: Sequential Scans on Large Tables

**Symptom:**
```sql
Seq Scan on orders  (cost=0.00..10000.00 rows=500000 width=40)
```

**Solution:** Add appropriate index

```typescript
await sql`CREATE INDEX orders_customer_id_idx ON orders (customer_id)`;
```

### Issue 2: Row Estimate Mismatch

**Symptom:**
```sql
(rows=10) (actual rows=50000)
```

**Solution:** Update statistics

```typescript
await sql`ANALYZE orders`;
// Or more detailed:
await sql`ANALYZE VERBOSE orders`;
```

### Issue 3: Nested Loop with High Rows

**Symptom:**
```sql
Nested Loop  (actual rows=1000000 loops=1)
  ->  Seq Scan on users  (actual rows=10000)
  ->  Index Scan on orders  (actual loops=10000)  -- 10000 index lookups!
```

**Solution:** Consider HashJoin or MergeJoin

```typescript
// Increase work_mem for hash operations
await sql`SET work_mem = '256MB'`;
```

### Issue 4: Buffer Reads vs Hits

**Symptom:**
```sql
Buffers: shared read=5000 hit=10  -- Mostly disk reads
```

**Solution:** Increase shared_buffers or optimize query to read less data

### Issue 5: Sort/Hash Disk Spillover

**Symptom:**
```sql
Sort Method: external merge  Disk: 102400kB
```

**Solution:** Increase work_mem

```typescript
await sql`SET work_mem = '512MB'`;  -- Session level
```

---

## Query Optimization Patterns

### 1. Use EXISTS Instead of IN for Subqueries

```typescript
// Bad: IN with subquery
await sql`
  SELECT * FROM orders
  WHERE customer_id IN (SELECT id FROM customers WHERE active)
`;

// Good: EXISTS (often more efficient)
await sql`
  SELECT * FROM orders o
  WHERE EXISTS (
    SELECT 1 FROM customers c
    WHERE c.id = o.customer_id AND c.active
  )
`;
```

### 2. Use LIMIT Early in CTEs

```typescript
// Bad: Process all, then limit
await sql`
  WITH all_orders AS (
    SELECT * FROM orders
  )
  SELECT * FROM all_orders LIMIT 10
`;

// Good: Limit early
await sql`
  WITH recent_orders AS (
    SELECT * FROM orders
    ORDER BY created_at DESC
    LIMIT 100
  )
  SELECT * FROM recent_orders WHERE status = 'pending' LIMIT 10
`;
```

### 3. Avoid SELECT *

```typescript
// Bad: Select all columns
await sql`SELECT * FROM orders WHERE id = ${id}`;

// Good: Select only needed columns
await sql`SELECT id, status, amount FROM orders WHERE id = ${id}`;
```

### 4. Use Covering Indexes for Index-Only Scans

```typescript
// Create covering index
await sql`
  CREATE INDEX orders_customer_covering_idx
  ON orders (customer_id)
  INCLUDE (status, amount)
`;

// Query can be satisfied from index alone
await sql`
  SELECT status, amount FROM orders WHERE customer_id = ${id}
`;
```

### 5. Batch Operations

```typescript
// Bad: Many small transactions
for (const item of items) {
  await sql`INSERT INTO products ${sql(item)}`;
}

// Good: Single transaction with batches
await sql.begin(async (tx) => {
  for (let i = 0; i < items.length; i += 1000) {
    const batch = items.slice(i, i + 1000);
    await tx`INSERT INTO products ${tx(batch)}`;
  }
});
```

### 6. Keyset Pagination Instead of OFFSET

```typescript
// Bad: OFFSET pagination (slow on large offsets)
await sql`
  SELECT * FROM orders
  ORDER BY created_at DESC
  LIMIT 20 OFFSET 10000
`;

// Good: Keyset pagination
await sql`
  SELECT * FROM orders
  WHERE created_at < ${lastSeenDate}
  ORDER BY created_at DESC
  LIMIT 20
`;
```

### 7. Pre-Filter Before Expensive Operations

```typescript
// Good: Filter first, then join
await sql`
  WITH filtered AS (
    SELECT * FROM orders
    WHERE status = 'pending' AND created_at > NOW() - INTERVAL '7 days'
  )
  SELECT f.*, c.name
  FROM filtered f
  JOIN customers c ON c.id = f.customer_id
`;
```

---

## Configuration Tuning

### Key Parameters

```typescript
// Check current settings
const settings = await sql`
  SELECT name, setting, unit, context
  FROM pg_settings
  WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'random_page_cost',
    'seq_page_cost'
  )
`;
```

### Recommended Settings

| Parameter | Description | Recommendation |
|-----------|-------------|----------------|
| `shared_buffers` | Memory for caching | 25% of RAM |
| `work_mem` | Per-operation memory | 64MB-256MB * |
| `maintenance_work_mem` | For VACUUM, CREATE INDEX | 512MB-1GB |
| `effective_cache_size` | Planner's cache estimate | 75% of RAM |
| `random_page_cost` | Random I/O cost (SSD) | 1.1-1.5 |

\* work_mem is per-operation, so set carefully for concurrent workloads

### Session-Level Tuning

```typescript
// For complex queries
await sql`SET work_mem = '256MB'`;
await sql`SET temp_buffers = '64MB'`;

// For bulk operations
await sql`SET maintenance_work_mem = '1GB'`;
```

---

## Statistics and Maintenance

### Update Statistics

```typescript
// Single table
await sql`ANALYZE orders`;

// With verbose output
await sql`ANALYZE VERBOSE orders`;

// All tables
await sql`ANALYZE`;
```

### Vacuum

```typescript
// Basic vacuum (reclaim space)
await sql`VACUUM orders`;

// Vacuum with analyze
await sql`VACUUM ANALYZE orders`;

// Full vacuum (rewrites table, exclusive lock)
await sql`VACUUM FULL orders`;

// Verbose output
await sql`VACUUM VERBOSE orders`;
```

### Check Table Bloat

```typescript
const bloat = await sql`
  SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
  FROM pg_stat_user_tables
  ORDER BY n_dead_tup DESC
  LIMIT 20
`;
```

### Autovacuum Status

```typescript
const autovacuum = await sql`
  SELECT
    name,
    setting
  FROM pg_settings
  WHERE name LIKE 'autovacuum%'
`;
```

---

## Index Performance

### Check Index Usage

```typescript
const indexUsage = await sql`
  SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
  FROM pg_stat_user_indexes
  ORDER BY idx_scan DESC
  LIMIT 20
`;
```

### Find Unused Indexes

```typescript
const unused = await sql`
  SELECT
    schemaname || '.' || relname AS table,
    indexrelname AS index,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
    idx_scan AS scans
  FROM pg_stat_user_indexes ui
  JOIN pg_index i ON ui.indexrelid = i.indexrelid
  WHERE NOT indisunique
    AND idx_scan = 0
  ORDER BY pg_relation_size(i.indexrelid) DESC
`;
```

### Find Duplicate Indexes

```typescript
const duplicates = await sql`
  SELECT
    pg_size_pretty(sum(pg_relation_size(idx))::bigint) AS size,
    (array_agg(idx))[1] AS keep_index,
    array_remove(array_agg(idx), (array_agg(idx))[1]) AS drop_indexes,
    array_agg(am) AS types
  FROM (
    SELECT
      indexrelid::regclass AS idx,
      indrelid::regclass AS tbl,
      am.amname AS am,
      (
        SELECT array_agg(a.attname ORDER BY c.ordinality)
        FROM pg_attribute a
        JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS c(colnum, ordinality) ON a.attnum = c.colnum
        WHERE a.attrelid = i.indrelid
      ) AS cols
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    JOIN pg_am am ON am.oid = c.relam
  ) sub
  GROUP BY tbl, cols
  HAVING count(*) > 1
`;
```

### Index Hit Ratio

```typescript
const [ratio] = await sql`
  SELECT
    sum(idx_blks_hit) AS hits,
    sum(idx_blks_read) AS reads,
    round(100.0 * sum(idx_blks_hit) / NULLIF(sum(idx_blks_hit) + sum(idx_blks_read), 0), 2) AS hit_ratio
  FROM pg_statio_user_indexes
`;
```

---

## Query Performance Analysis

### pg_stat_statements Extension

```typescript
// Enable extension
await sql`CREATE EXTENSION IF NOT EXISTS pg_stat_statements`;

// Find slowest queries
const slowQueries = await sql`
  SELECT
    query,
    calls,
    round(total_exec_time::numeric / 1000, 2) AS total_seconds,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    rows
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 20
`;

// Most called queries
const frequentQueries = await sql`
  SELECT
    query,
    calls,
    round(total_exec_time::numeric / 1000, 2) AS total_seconds
  FROM pg_stat_statements
  ORDER BY calls DESC
  LIMIT 20
`;

// Reset statistics
await sql`SELECT pg_stat_statements_reset()`;
```

### Lock Analysis

```typescript
const locks = await sql`
  SELECT
    pg_locks.pid,
    pg_class.relname AS table_name,
    pg_locks.mode,
    pg_locks.granted,
    pg_stat_activity.query,
    age(now(), pg_stat_activity.query_start) AS duration
  FROM pg_locks
  JOIN pg_class ON pg_locks.relation = pg_class.oid
  JOIN pg_stat_activity ON pg_locks.pid = pg_stat_activity.pid
  WHERE pg_class.relkind = 'r'
  ORDER BY duration DESC
`;
```

### Long-Running Queries

```typescript
const longQueries = await sql`
  SELECT
    pid,
    now() - query_start AS duration,
    state,
    query
  FROM pg_stat_activity
  WHERE state != 'idle'
    AND now() - query_start > interval '5 minutes'
  ORDER BY duration DESC
`;

// Terminate long-running query
await sql`SELECT pg_terminate_backend(${pid})`;
```

---

## Connection Management

### Check Connections

```typescript
const connections = await sql`
  SELECT
    state,
    count(*) AS count,
    max(now() - state_change) AS max_duration
  FROM pg_stat_activity
  WHERE datname = current_database()
  GROUP BY state
`;
```

### Idle Connection Cleanup

```typescript
// Terminate idle connections older than 10 minutes
await sql`
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state = 'idle'
    AND now() - state_change > interval '10 minutes'
    AND pid <> pg_backend_pid()
`;
```

### Connection Pool Settings (Bun.sql)

```typescript
const db = new SQL({
  hostname: "localhost",
  database: "myapp",
  max: 20,              // Max connections in pool
  idleTimeout: 30,      // Close idle after 30s
  maxLifetime: 3600,    // Max connection lifetime
  connectionTimeout: 30, // Connection timeout
});
```

---

## Monitoring Queries

### Table Access Statistics

```typescript
const tableStats = await sql`
  SELECT
    schemaname,
    relname,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_live_tup,
    n_dead_tup
  FROM pg_stat_user_tables
  ORDER BY seq_scan DESC
  LIMIT 20
`;
```

### Cache Hit Ratio

```typescript
const [cacheRatio] = await sql`
  SELECT
    sum(heap_blks_hit) AS heap_hits,
    sum(heap_blks_read) AS heap_reads,
    round(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) AS hit_ratio
  FROM pg_statio_user_tables
`;
// Target: > 99%
```

### Database Size

```typescript
const [size] = await sql`
  SELECT
    pg_size_pretty(pg_database_size(current_database())) AS database_size
`;

const tableSizes = await sql`
  SELECT
    relname AS table,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    pg_size_pretty(pg_relation_size(relid)) AS data_size,
    pg_size_pretty(pg_indexes_size(relid)) AS index_size
  FROM pg_catalog.pg_statio_user_tables
  ORDER BY pg_total_relation_size(relid) DESC
  LIMIT 20
`;
```

---

## Performance Checklist

### Before Production

- [ ] All frequently queried columns indexed
- [ ] Foreign keys indexed
- [ ] ANALYZE run on all tables
- [ ] pg_stat_statements enabled
- [ ] Connection pooling configured
- [ ] work_mem tuned for workload
- [ ] shared_buffers set appropriately

### Ongoing Monitoring

- [ ] Cache hit ratio > 99%
- [ ] No sequential scans on large tables
- [ ] Bloat under control (< 20% dead tuples)
- [ ] No unused indexes
- [ ] No long-running queries
- [ ] No lock contention

### Query Review

- [ ] EXPLAIN ANALYZE for new queries
- [ ] No SELECT * on large tables
- [ ] Appropriate LIMIT clauses
- [ ] Keyset pagination for large offsets
- [ ] Batched operations for bulk updates
