# Indexing Strategies Reference

Complete guide to PostgreSQL index types and selection with Bun.sql.

## Index Types Overview

| Index Type | Best For | Operators Supported |
|------------|----------|---------------------|
| B-tree | Equality, range, sorting | `<`, `<=`, `=`, `>=`, `>`, `BETWEEN`, `IN`, `IS NULL`, `LIKE 'foo%'` |
| Hash | Equality only | `=` |
| GIN | Arrays, JSONB, full-text | `@>`, `<@`, `&&`, `?`, `?|`, `?&`, `@@` |
| GiST | Geometric, range, nearest-neighbor | `<<`, `>>`, `@>`, `<@`, `&&`, `<->` |
| SP-GiST | Partitioned data (phone, IP) | Similar to GiST |
| BRIN | Large sequential data | Range comparisons |

---

## B-tree Index (Default)

Most common index type. Automatically used when you don't specify a type.

### When to Use

- Equality comparisons (`=`)
- Range queries (`<`, `<=`, `>`, `>=`, `BETWEEN`)
- Sorting (`ORDER BY`)
- `NULL` checks
- Pattern matching with leading constant (`LIKE 'foo%'`)

### Creating B-tree Indexes

```typescript
// Simple index
await sql`CREATE INDEX users_email_idx ON users (email)`;

// Descending order (for ORDER BY ... DESC)
await sql`CREATE INDEX orders_date_idx ON orders (created_at DESC)`;

// Multi-column index
await sql`CREATE INDEX orders_customer_date_idx ON orders (customer_id, created_at DESC)`;

// Unique index
await sql`CREATE UNIQUE INDEX users_email_unique_idx ON users (email)`;
```

### Multi-Column Index Considerations

Column order matters! The index can be used when:
- Querying leftmost columns
- Querying all indexed columns
- NOT when skipping leftmost columns

```typescript
// Index: (a, b, c)
// Uses index:
await sql`SELECT * FROM t WHERE a = 1`;
await sql`SELECT * FROM t WHERE a = 1 AND b = 2`;
await sql`SELECT * FROM t WHERE a = 1 AND b = 2 AND c = 3`;
await sql`SELECT * FROM t ORDER BY a, b, c`;

// Does NOT use index efficiently:
await sql`SELECT * FROM t WHERE b = 2`;         // Skips 'a'
await sql`SELECT * FROM t WHERE b = 2 AND c = 3`; // Skips 'a'
```

---

## Hash Index

Faster than B-tree for pure equality, but limited functionality.

### When to Use

- Only equality comparisons
- Column values are uniformly distributed
- No range queries needed

```typescript
await sql`CREATE INDEX users_uuid_hash_idx ON users USING HASH (uuid)`;

// Uses index:
await sql`SELECT * FROM users WHERE uuid = ${uuid}`;

// Does NOT use index:
await sql`SELECT * FROM users WHERE uuid > ${uuid}`;
```

### Limitations

- No range queries
- No ordering
- Cannot enforce uniqueness
- Historically less reliable (improved in PostgreSQL 10+)

---

## GIN Index (Generalized Inverted Index)

Optimized for values containing multiple elements (arrays, JSONB, full-text).

### When to Use

- Array containment queries
- JSONB containment queries
- Full-text search

### Array Indexes

```typescript
await sql`CREATE INDEX products_tags_idx ON products USING GIN (tags)`;

// Uses index:
await sql`SELECT * FROM products WHERE tags @> ARRAY['electronics']`;
await sql`SELECT * FROM products WHERE tags && ARRAY['sale', 'new']`;
await sql`SELECT * FROM products WHERE 'sale' = ANY(tags)`;
```

### JSONB Indexes

```typescript
// Full JSONB indexing
await sql`CREATE INDEX users_data_idx ON users USING GIN (data)`;

// Supports: @>, ?, ?|, ?&
await sql`SELECT * FROM users WHERE data @> '{"active": true}'`;
await sql`SELECT * FROM users WHERE data ? 'email'`;

// Optimized for @> containment only (smaller, faster)
await sql`CREATE INDEX users_data_path_idx ON users USING GIN (data jsonb_path_ops)`;
```

### Full-Text Search Indexes

```typescript
await sql`CREATE INDEX articles_search_idx ON articles USING GIN (search_vector)`;
await sql`SELECT * FROM articles WHERE search_vector @@ to_tsquery('english', 'database')`;
```

### Trigram Indexes (pg_trgm)

```typescript
await sql`CREATE EXTENSION IF NOT EXISTS pg_trgm`;
await sql`CREATE INDEX products_name_trgm_idx ON products USING GIN (name gin_trgm_ops)`;

// Uses index:
await sql`SELECT * FROM products WHERE name % 'search'`;     // Similarity
await sql`SELECT * FROM products WHERE name ILIKE '%search%'`; // Pattern
```

---

## GiST Index (Generalized Search Tree)

Flexible index for geometric types, ranges, and nearest-neighbor searches.

### When to Use

- Geometric data (points, boxes, circles)
- Range types (int4range, tstzrange)
- Nearest-neighbor searches
- Exclusion constraints

### Geometric Indexes

```typescript
await sql`CREATE INDEX locations_point_idx ON locations USING GIST (coordinates)`;

// Nearest neighbor search
await sql`
  SELECT * FROM locations
  ORDER BY coordinates <-> point(${lat}, ${lng})
  LIMIT 10
`;

// Containment
await sql`
  SELECT * FROM locations
  WHERE coordinates <@ box(point(0,0), point(10,10))
`;
```

### Range Type Indexes

```typescript
await sql`CREATE INDEX reservations_period_idx ON reservations USING GIST (period)`;

// Overlapping ranges
await sql`
  SELECT * FROM reservations
  WHERE period && tstzrange(${start}, ${end})
`;

// Exclusion constraint (no overlapping reservations)
await sql`
  ALTER TABLE reservations
  ADD CONSTRAINT no_overlap
  EXCLUDE USING GIST (room_id WITH =, period WITH &&)
`;
```

### Full-Text Search (Alternative to GIN)

```typescript
await sql`CREATE INDEX articles_search_gist_idx ON articles USING GIST (search_vector)`;
// GiST is lossy but faster to build; GIN is lossless and faster to search
```

---

## SP-GiST Index (Space-Partitioned GiST)

For data that can be recursively partitioned into non-overlapping regions.

### When to Use

- Phone numbers
- IP addresses
- Hierarchical data

```typescript
// IP address range queries
await sql`CREATE INDEX access_log_ip_idx ON access_log USING SPGIST (ip_address inet_ops)`;

// Text prefix queries
await sql`CREATE INDEX users_phone_idx ON users USING SPGIST (phone)`;
```

---

## BRIN Index (Block Range Index)

Extremely compact index for large, naturally ordered data.

### When to Use

- Very large tables (millions of rows)
- Data inserted in order (time-series, logs)
- Range queries on ordered column
- Willing to trade some precision for small index size

### Creating BRIN Indexes

```typescript
// Default: 128 pages per range
await sql`CREATE INDEX logs_created_idx ON logs USING BRIN (created_at)`;

// Custom pages per range (smaller = more precise, larger index)
await sql`CREATE INDEX logs_created_idx ON logs USING BRIN (created_at) WITH (pages_per_range = 32)`;
```

### Size Comparison

For a 1GB table with 10M rows:
- B-tree: ~200MB
- BRIN: ~100KB

### Limitations

- Less precise than B-tree
- Best when data is physically ordered
- Must scan block ranges, not individual rows

---

## Partial Indexes

Index only a subset of rows.

### When to Use

- Frequently queried subset
- Excluding NULL values
- Status-based filtering

```typescript
// Only index active users
await sql`CREATE INDEX active_users_email_idx ON users (email) WHERE active = true`;

// Only pending orders
await sql`CREATE INDEX pending_orders_idx ON orders (created_at) WHERE status = 'pending'`;

// Exclude NULLs
await sql`CREATE INDEX orders_shipped_idx ON orders (shipped_at) WHERE shipped_at IS NOT NULL`;
```

### Query Must Match

```typescript
// Uses partial index (WHERE clause matches):
await sql`SELECT * FROM users WHERE email = ${email} AND active = true`;

// Does NOT use partial index:
await sql`SELECT * FROM users WHERE email = ${email}`;
```

---

## Expression Indexes

Index the result of an expression.

### When to Use

- Querying transformed values
- Case-insensitive searches
- Computed columns

```typescript
// Case-insensitive email lookup
await sql`CREATE INDEX users_email_lower_idx ON users (LOWER(email))`;
await sql`SELECT * FROM users WHERE LOWER(email) = LOWER(${email})`;

// Date extraction
await sql`CREATE INDEX orders_year_idx ON orders (EXTRACT(YEAR FROM created_at))`;
await sql`SELECT * FROM orders WHERE EXTRACT(YEAR FROM created_at) = 2024`;

// JSONB field
await sql`CREATE INDEX users_city_idx ON users ((data->>'city'))`;
await sql`SELECT * FROM users WHERE data->>'city' = ${city}`;

// Computed value
await sql`CREATE INDEX products_total_idx ON products ((price * quantity))`;
```

---

## Covering Indexes (INCLUDE)

Include additional columns for index-only scans.

### When to Use

- Avoiding table lookups
- Frequently selected columns
- Read-heavy workloads

```typescript
// Include columns not used for filtering but needed in SELECT
await sql`
  CREATE INDEX orders_customer_covering_idx
  ON orders (customer_id)
  INCLUDE (order_date, total_amount, status)
`;

// Query can be satisfied from index alone
await sql`
  SELECT order_date, total_amount, status
  FROM orders
  WHERE customer_id = ${customerId}
`;
```

---

## Concurrent Index Creation

Create indexes without blocking writes.

```typescript
// Non-blocking (but takes longer)
await sql`CREATE INDEX CONCURRENTLY users_email_idx ON users (email)`;

// Reindex concurrently
await sql`REINDEX INDEX CONCURRENTLY users_email_idx`;
```

### Considerations

- Takes longer than regular CREATE INDEX
- Requires more resources
- May fail if there are constraint violations
- Cannot be run in a transaction

---

## Index Selection Strategy

### Step 1: Identify Query Patterns

```typescript
// Enable pg_stat_statements to see slow queries
await sql`CREATE EXTENSION IF NOT EXISTS pg_stat_statements`;

// Find slow queries
const slowQueries = await sql`
  SELECT query, calls, mean_exec_time, rows
  FROM pg_stat_statements
  ORDER BY mean_exec_time DESC
  LIMIT 20
`;
```

### Step 2: Analyze Execution Plans

```typescript
const plan = await sql`
  EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
  SELECT * FROM orders WHERE customer_id = ${customerId}
`;

// Look for:
// - Seq Scan on large tables
// - High actual rows vs estimated
// - Buffer reads >> hits
```

### Step 3: Choose Index Type

| Query Pattern | Recommended Index |
|---------------|-------------------|
| `WHERE col = value` | B-tree or Hash |
| `WHERE col > value` | B-tree |
| `ORDER BY col` | B-tree |
| `WHERE col @> array` | GIN |
| `WHERE jsonb @> {...}` | GIN |
| `WHERE text @@ tsquery` | GIN |
| `ORDER BY col <-> point` | GiST |
| `WHERE range && range` | GiST |
| `WHERE col LIKE '%text%'` | GIN + pg_trgm |
| Sequential time-series | BRIN |

### Step 4: Verify Improvement

```typescript
// Before
await sql`EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 123`;

// Create index
await sql`CREATE INDEX orders_customer_idx ON orders (customer_id)`;

// After
await sql`EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 123`;
```

---

## Index Maintenance

### Check Index Usage

```typescript
const indexUsage = await sql`
  SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
  FROM pg_stat_user_indexes
  ORDER BY idx_scan ASC
`;
```

### Find Unused Indexes

```typescript
const unusedIndexes = await sql`
  SELECT
    schemaname || '.' || indexrelname AS index,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
    idx_scan
  FROM pg_stat_user_indexes ui
  JOIN pg_index i ON ui.indexrelid = i.indexrelid
  WHERE idx_scan = 0
    AND NOT indisunique
    AND NOT indisprimary
  ORDER BY pg_relation_size(i.indexrelid) DESC
`;
```

### Check Index Size

```typescript
const indexSizes = await sql`
  SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
  FROM pg_indexes
  WHERE schemaname = 'public'
  ORDER BY pg_relation_size(indexname::regclass) DESC
`;
```

### Reindex

```typescript
// Rebuild specific index
await sql`REINDEX INDEX orders_customer_idx`;

// Rebuild all indexes on table
await sql`REINDEX TABLE orders`;

// Concurrently (no blocking)
await sql`REINDEX INDEX CONCURRENTLY orders_customer_idx`;
```

### Drop Unused Indexes

```typescript
await sql`DROP INDEX IF EXISTS unused_index_name`;
```

---

## Best Practices

1. **Always index foreign keys** - Prevents full table scans on JOINs and DELETE cascades

2. **Index columns used in WHERE, JOIN, ORDER BY** - Most common performance wins

3. **Put selective columns first** - In multi-column indexes, most selective first

4. **Consider partial indexes** - For queries on common subsets

5. **Use covering indexes** - When you need index-only scans

6. **Avoid over-indexing** - Each index slows down writes

7. **Use CONCURRENTLY in production** - Avoid blocking queries

8. **Monitor and remove unused indexes** - They still cost write performance

9. **Match query conditions exactly** - Partial index predicates, expression indexes

10. **Test with production-like data** - Query planner decisions depend on data distribution
