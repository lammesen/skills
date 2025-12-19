# EXPLAIN Output Analysis Guide

This guide helps you interpret PostgreSQL EXPLAIN and EXPLAIN ANALYZE output to identify and fix performance issues.

## Running EXPLAIN

### Basic EXPLAIN

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 123;
```

Shows the estimated query plan without executing.

### EXPLAIN ANALYZE

```sql
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 123;
```

Executes the query and shows actual timings. **Warning**: This runs the query!

### Full Analysis

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE, FORMAT JSON)
SELECT * FROM orders WHERE customer_id = 123;
```

Options:
- `ANALYZE`: Execute and show actual times
- `BUFFERS`: Show buffer/cache usage
- `COSTS`: Show estimated costs (default on)
- `TIMING`: Show actual timing per node (default on with ANALYZE)
- `VERBOSE`: Show additional info (output columns, etc.)
- `FORMAT`: TEXT (default), JSON, XML, YAML

## Understanding the Output

### Basic Structure

```
Seq Scan on orders  (cost=0.00..1234.00 rows=1000 width=100) (actual time=0.01..50.00 rows=950 loops=1)
^^^^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^^^ ^^^^^^^^^ ^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^ ^^^^^^^
Node type           Startup..Total     Est rows  Row width   Actual timing        Act rows  Loops
```

### Key Metrics

| Metric | Description | Warning Signs |
|--------|-------------|---------------|
| `cost=X..Y` | Estimated cost (X=startup, Y=total) | Y > 10000 |
| `rows=N` | Estimated rows | Very different from actual |
| `width=N` | Average row size in bytes | Very large |
| `actual time=X..Y` | Real execution time (ms) | Y > 100ms |
| `actual rows=N` | Real rows returned | >> estimated |
| `loops=N` | Times this node executed | N * other metrics |

### Buffer Statistics

```
Buffers: shared hit=100 read=50 written=10
         ^^^^^^^^^^^^^ ^^^^^^^ ^^^^^^^^^^
         From cache    From disk  Written to disk
```

- **hit**: Pages found in shared_buffers (good)
- **read**: Pages read from disk (I/O cost)
- **written**: Pages written (usually during checkpoints)

Goal: Maximize hits, minimize reads.

## Node Types

### Scan Nodes

| Node | Description | Performance |
|------|-------------|-------------|
| `Seq Scan` | Full table scan | Slow on large tables |
| `Index Scan` | Index lookup + heap fetch | Fast for selective queries |
| `Index Only Scan` | Index satisfies query | Fastest |
| `Bitmap Index Scan` | Index → bitmap | Good for multiple conditions |
| `Bitmap Heap Scan` | Fetch rows from bitmap | Follows bitmap index scan |

### Join Nodes

| Node | Description | Best For |
|------|-------------|----------|
| `Nested Loop` | For each outer row, scan inner | Small outer, indexed inner |
| `Hash Join` | Build hash table, probe | Equality joins, medium tables |
| `Merge Join` | Merge sorted inputs | Pre-sorted data, large tables |

### Other Nodes

| Node | Description |
|------|-------------|
| `Sort` | Sort rows (may spill to disk) |
| `Hash` | Build hash table for join |
| `Aggregate` | GROUP BY, COUNT, SUM, etc. |
| `Limit` | Return first N rows |
| `Materialize` | Cache results in memory |
| `CTE Scan` | Read from CTE |
| `Subquery Scan` | Read from subquery |

## Problem Patterns

### 1. Sequential Scan on Large Table

**Symptom:**
```
Seq Scan on orders  (cost=0.00..50000.00 rows=1000000 width=100)
```

**Solution:**
```sql
CREATE INDEX orders_customer_id_idx ON orders (customer_id);
```

### 2. Row Estimate Mismatch

**Symptom:**
```
Index Scan on orders  (rows=10) (actual rows=50000)
```

**Solution:**
```sql
ANALYZE orders;
```

### 3. Nested Loop with High Rows

**Symptom:**
```
Nested Loop  (actual time=0.05..5000.00 rows=1000000 loops=1)
  ->  Seq Scan on users  (actual rows=10000 loops=1)
  ->  Index Scan on orders  (actual rows=100 loops=10000)
```

**Solution:**
- Increase `work_mem` to enable hash join
- Add better index
- Rewrite query

### 4. Sort Using Disk

**Symptom:**
```
Sort  (actual time=1000.00..1500.00 rows=1000000)
  Sort Key: created_at
  Sort Method: external merge  Disk: 102400kB
```

**Solution:**
```sql
SET work_mem = '256MB';
-- Or create index for ORDER BY
CREATE INDEX orders_created_at_idx ON orders (created_at DESC);
```

### 5. Bitmap Heap Scan with "Recheck Cond"

**Symptom:**
```
Bitmap Heap Scan on orders
  Recheck Cond: (status = 'pending')
  Rows Removed by Index Recheck: 50000
```

**Solution:**
```sql
SET work_mem = '256MB';  -- Larger bitmap
```

### 6. Hash Join Batches

**Symptom:**
```
Hash Join  (actual time=100..5000)
  ->  Hash  (actual time=50..50)
        Buckets: 65536  Batches: 16  Memory Usage: 8193kB
```

**Solution:**
```sql
SET work_mem = '512MB';  -- Reduce batches
```

## Analysis Workflow

### Step 1: Get the Plan

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
<your query here>;
```

### Step 2: Check Total Time

Look at the root node's `actual time`. If > 100ms, investigate.

### Step 3: Find Expensive Nodes

Look for nodes with:
- High `actual time`
- `Seq Scan` on large tables
- Row estimate mismatches
- Disk sorts or hash batches

### Step 4: Check Buffer Usage

Calculate hit ratio:
```
hit ratio = hits / (hits + reads)
```

Target: > 99%

### Step 5: Identify Root Cause

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| Seq Scan | Missing index | Add index |
| Row mismatch | Stale stats | ANALYZE |
| Disk sort | Low work_mem | Increase work_mem |
| Many loops | Bad join order | Rewrite query |
| Low hit ratio | Small shared_buffers | Increase shared_buffers |

### Step 6: Apply Fix

Make one change at a time and re-run EXPLAIN ANALYZE.

### Step 7: Verify Improvement

Compare before/after:
- Total execution time
- Scan types
- Buffer hits vs reads

## JSON Format Analysis

For programmatic analysis, use JSON format:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT * FROM orders WHERE customer_id = 123;
```

Key JSON paths:
- `[0].Plan."Node Type"` - Scan/join type
- `[0].Plan."Actual Total Time"` - Execution time
- `[0].Plan."Actual Rows"` - Rows returned
- `[0].Plan."Shared Hit Blocks"` - Cache hits
- `[0].Plan."Shared Read Blocks"` - Disk reads

## Quick Reference

### Good Signs
- Index Scan / Index Only Scan
- High buffer hits, low reads
- Actual rows ≈ estimated rows
- Memory sorts (not disk)
- Single loop iterations

### Warning Signs
- Seq Scan on tables > 10000 rows
- Actual rows >> estimated rows
- External merge sorts
- Nested loops with high loop counts
- Hash batches > 1
- Buffer reads >> hits

## Example Analysis

### Before Optimization

```
Seq Scan on orders  (cost=0.00..25000.00 rows=1000000 width=100) (actual time=0.01..500.00 rows=1000000 loops=1)
  Filter: (customer_id = 123)
  Rows Removed by Filter: 999000
  Buffers: shared hit=5000 read=20000
Planning Time: 0.1 ms
Execution Time: 550.00 ms
```

**Problems:**
- Seq Scan on 1M row table
- 999000 rows filtered (inefficient)
- 20000 buffer reads (I/O heavy)

### After Adding Index

```sql
CREATE INDEX orders_customer_id_idx ON orders (customer_id);
```

```
Index Scan using orders_customer_id_idx on orders  (cost=0.42..8.44 rows=1000 width=100) (actual time=0.01..0.50 rows=1000 loops=1)
  Index Cond: (customer_id = 123)
  Buffers: shared hit=50
Planning Time: 0.2 ms
Execution Time: 0.60 ms
```

**Improvements:**
- Index Scan (not Seq Scan)
- 1000 rows directly (not 1M filtered)
- 50 buffer hits (from cache)
- 550ms → 0.6ms (900x faster)
