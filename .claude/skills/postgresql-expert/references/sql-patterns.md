# SQL Patterns Reference

Complete SQL syntax reference for PostgreSQL operations with Bun.sql.

## SELECT Syntax

### Basic SELECT

```sql
SELECT [ALL | DISTINCT [ON (expression [, ...])]]
    [* | expression [[AS] alias] [, ...]]
    [FROM from_item [, ...]]
    [WHERE condition]
    [GROUP BY [ALL | DISTINCT] grouping_element [, ...]]
    [HAVING condition]
    [WINDOW window_name AS (window_definition) [, ...]]
    [{UNION | INTERSECT | EXCEPT} [ALL | DISTINCT] select]
    [ORDER BY expression [ASC | DESC | USING operator] [NULLS {FIRST | LAST}] [, ...]]
    [LIMIT {count | ALL}]
    [OFFSET start [ROW | ROWS]]
    [FETCH {FIRST | NEXT} [count] {ROW | ROWS} {ONLY | WITH TIES}]
    [FOR {UPDATE | NO KEY UPDATE | SHARE | KEY SHARE} [OF table_name [, ...]] [NOWAIT | SKIP LOCKED] [...]]
```

### FROM Clause Options

```typescript
// Basic table reference
await sql`SELECT * FROM users`;

// Table alias
await sql`SELECT u.name FROM users u`;

// Subquery
await sql`SELECT * FROM (SELECT * FROM users WHERE active) AS active_users`;

// JOIN types
await sql`
  SELECT *
  FROM orders o
  INNER JOIN customers c ON c.id = o.customer_id
  LEFT JOIN shipping s ON s.order_id = o.id
  RIGHT JOIN returns r ON r.order_id = o.id
  FULL OUTER JOIN refunds rf ON rf.order_id = o.id
  CROSS JOIN categories cat
`;

// LATERAL join
await sql`
  SELECT u.*, latest.*
  FROM users u
  LEFT JOIN LATERAL (
    SELECT * FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC
    LIMIT 1
  ) latest ON true
`;

// NATURAL join (automatic column matching)
await sql`SELECT * FROM employees NATURAL JOIN departments`;

// USING clause
await sql`SELECT * FROM orders JOIN customers USING (customer_id)`;
```

### WHERE Clause Operators

```typescript
// Comparison operators
await sql`SELECT * FROM products WHERE price >= ${minPrice}`;
await sql`SELECT * FROM products WHERE name <> ${excluded}`;

// BETWEEN
await sql`SELECT * FROM orders WHERE created_at BETWEEN ${start} AND ${end}`;

// IN / NOT IN
await sql`SELECT * FROM users WHERE role IN ${sql(['admin', 'moderator'])}`;

// LIKE / ILIKE
await sql`SELECT * FROM products WHERE name ILIKE ${`%${search}%`}`;

// Regular expressions
await sql`SELECT * FROM users WHERE email ~ '^[a-z]+@example\\.com$'`;
await sql`SELECT * FROM users WHERE email ~* '^[a-z]+@example\\.com$'`; // case-insensitive

// NULL checks
await sql`SELECT * FROM users WHERE deleted_at IS NULL`;
await sql`SELECT * FROM users WHERE deleted_at IS NOT NULL`;

// Boolean
await sql`SELECT * FROM users WHERE active IS TRUE`;

// Array operators
await sql`SELECT * FROM products WHERE ${tag} = ANY(tags)`;
await sql`SELECT * FROM products WHERE tags @> ${sql.array(['electronics'])}`;
await sql`SELECT * FROM products WHERE tags && ${sql.array(['sale', 'new'])}`;

// EXISTS
await sql`
  SELECT * FROM customers c
  WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.id AND o.amount > 1000
  )
`;
```

### GROUP BY and Aggregates

```typescript
// Basic aggregation
await sql`
  SELECT
    category,
    COUNT(*) AS count,
    SUM(price) AS total,
    AVG(price) AS average,
    MIN(price) AS min_price,
    MAX(price) AS max_price
  FROM products
  GROUP BY category
`;

// FILTER clause for conditional aggregation
await sql`
  SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'active') AS active_count,
    SUM(amount) FILTER (WHERE type = 'credit') AS credit_total,
    SUM(amount) FILTER (WHERE type = 'debit') AS debit_total
  FROM transactions
`;

// GROUPING SETS
await sql`
  SELECT region, category, SUM(sales)
  FROM orders
  GROUP BY GROUPING SETS (
    (region, category),
    (region),
    (category),
    ()
  )
`;

// CUBE (all combinations)
await sql`
  SELECT region, category, year, SUM(sales)
  FROM orders
  GROUP BY CUBE (region, category, year)
`;

// ROLLUP (hierarchical)
await sql`
  SELECT year, quarter, month, SUM(sales)
  FROM orders
  GROUP BY ROLLUP (year, quarter, month)
`;
```

### HAVING Clause

```typescript
await sql`
  SELECT category, COUNT(*) AS count
  FROM products
  GROUP BY category
  HAVING COUNT(*) > ${minCount}
`;

await sql`
  SELECT user_id, SUM(amount) AS total
  FROM orders
  GROUP BY user_id
  HAVING SUM(amount) > 1000
    AND COUNT(*) >= 5
`;
```

### ORDER BY Options

```typescript
// Basic ordering
await sql`SELECT * FROM products ORDER BY price DESC`;

// Multiple columns
await sql`SELECT * FROM products ORDER BY category ASC, price DESC`;

// NULLS handling
await sql`SELECT * FROM products ORDER BY discount DESC NULLS LAST`;

// Expression ordering
await sql`SELECT * FROM products ORDER BY price * quantity DESC`;

// Ordinal position
await sql`SELECT name, price FROM products ORDER BY 2 DESC`; // Order by price

// CASE-based ordering
await sql`
  SELECT * FROM orders
  ORDER BY
    CASE status
      WHEN 'urgent' THEN 1
      WHEN 'high' THEN 2
      WHEN 'normal' THEN 3
      ELSE 4
    END
`;
```

### LIMIT and OFFSET

```typescript
// Basic pagination
await sql`SELECT * FROM products LIMIT ${limit} OFFSET ${offset}`;

// FETCH syntax (SQL standard)
await sql`
  SELECT * FROM products
  ORDER BY created_at DESC
  FETCH FIRST ${limit} ROWS ONLY
`;

// WITH TIES (include all rows with same ordering value as last row)
await sql`
  SELECT * FROM products
  ORDER BY price DESC
  FETCH FIRST 10 ROWS WITH TIES
`;
```

### FOR UPDATE/SHARE (Locking)

```typescript
// Lock rows for update
await sql`
  SELECT * FROM accounts
  WHERE id = ${accountId}
  FOR UPDATE
`;

// Lock specific tables
await sql`
  SELECT * FROM orders o
  JOIN order_items oi ON oi.order_id = o.id
  WHERE o.id = ${orderId}
  FOR UPDATE OF orders
`;

// NOWAIT (fail if locked)
await sql`
  SELECT * FROM resources
  WHERE id = ${resourceId}
  FOR UPDATE NOWAIT
`;

// SKIP LOCKED (skip locked rows)
await sql`
  SELECT * FROM job_queue
  WHERE status = 'pending'
  ORDER BY priority DESC
  LIMIT 1
  FOR UPDATE SKIP LOCKED
`;
```

---

## INSERT Syntax

### Basic INSERT

```typescript
// Single row
await sql`
  INSERT INTO users (name, email)
  VALUES (${name}, ${email})
`;

// Multiple rows
await sql`
  INSERT INTO users (name, email)
  VALUES
    (${'Alice'}, ${'alice@example.com'}),
    (${'Bob'}, ${'bob@example.com'})
`;

// Object helper
await sql`INSERT INTO users ${sql({ name, email })}`;

// Bulk insert with array
await sql`INSERT INTO users ${sql(usersArray)}`;

// Pick specific columns
await sql`INSERT INTO users ${sql(userData, 'name', 'email')}`;
```

### INSERT with RETURNING

```typescript
const [user] = await sql`
  INSERT INTO users (name, email)
  VALUES (${name}, ${email})
  RETURNING id, created_at
`;

const inserted = await sql`
  INSERT INTO products ${sql(products)}
  RETURNING *
`;
```

### INSERT ON CONFLICT (Upsert)

```typescript
// Update on conflict
await sql`
  INSERT INTO users (email, name)
  VALUES (${email}, ${name})
  ON CONFLICT (email) DO UPDATE SET
    name = EXCLUDED.name,
    updated_at = NOW()
`;

// Do nothing on conflict
await sql`
  INSERT INTO users (email, name)
  VALUES (${email}, ${name})
  ON CONFLICT DO NOTHING
`;

// Conflict on constraint
await sql`
  INSERT INTO orders (user_id, product_id, quantity)
  VALUES (${userId}, ${productId}, ${quantity})
  ON CONFLICT ON CONSTRAINT orders_user_product_unique DO UPDATE SET
    quantity = orders.quantity + EXCLUDED.quantity
`;

// Conditional upsert
await sql`
  INSERT INTO prices (product_id, price)
  VALUES (${productId}, ${price})
  ON CONFLICT (product_id)
  WHERE effective_date < NOW()
  DO UPDATE SET price = EXCLUDED.price
`;
```

### INSERT from SELECT

```typescript
await sql`
  INSERT INTO archived_orders
  SELECT * FROM orders
  WHERE created_at < NOW() - INTERVAL '1 year'
`;

await sql`
  INSERT INTO user_stats (user_id, total_orders, total_spent)
  SELECT
    user_id,
    COUNT(*),
    SUM(amount)
  FROM orders
  GROUP BY user_id
`;
```

---

## UPDATE Syntax

### Basic UPDATE

```typescript
await sql`
  UPDATE users
  SET name = ${name}, email = ${email}
  WHERE id = ${userId}
`;

// Object helper
await sql`UPDATE users SET ${sql(updates)} WHERE id = ${userId}`;
```

### UPDATE with FROM

```typescript
await sql`
  UPDATE orders o
  SET status = 'shipped'
  FROM shipments s
  WHERE s.order_id = o.id
    AND s.shipped_at IS NOT NULL
`;

await sql`
  UPDATE products p
  SET category_name = c.name
  FROM categories c
  WHERE c.id = p.category_id
`;
```

### UPDATE with Subquery

```typescript
await sql`
  UPDATE products
  SET price = (
    SELECT AVG(price)
    FROM products p2
    WHERE p2.category_id = products.category_id
  )
  WHERE price IS NULL
`;
```

### UPDATE with CTE

```typescript
await sql`
  WITH to_update AS (
    SELECT id
    FROM orders
    WHERE status = 'pending'
      AND created_at < NOW() - INTERVAL '7 days'
  )
  UPDATE orders
  SET status = 'expired'
  WHERE id IN (SELECT id FROM to_update)
`;
```

### UPDATE RETURNING

```typescript
const updated = await sql`
  UPDATE users
  SET last_login = NOW()
  WHERE id = ${userId}
  RETURNING id, last_login
`;
```

---

## DELETE Syntax

### Basic DELETE

```typescript
await sql`DELETE FROM users WHERE id = ${userId}`;

await sql`DELETE FROM sessions WHERE expires_at < NOW()`;
```

### DELETE with USING

```typescript
await sql`
  DELETE FROM order_items oi
  USING orders o
  WHERE oi.order_id = o.id
    AND o.status = 'cancelled'
`;
```

### DELETE with CTE

```typescript
await sql`
  WITH deleted AS (
    DELETE FROM orders
    WHERE status = 'cancelled'
      AND created_at < NOW() - INTERVAL '90 days'
    RETURNING *
  )
  INSERT INTO archived_orders
  SELECT * FROM deleted
`;
```

### DELETE RETURNING

```typescript
const deleted = await sql`
  DELETE FROM temporary_files
  WHERE created_at < NOW() - INTERVAL '1 day'
  RETURNING id, file_path
`;
```

### TRUNCATE

```typescript
// Faster than DELETE for removing all rows
await sql`TRUNCATE users`;

// Cascade to foreign key tables
await sql`TRUNCATE orders CASCADE`;

// Restart identity columns
await sql`TRUNCATE users RESTART IDENTITY`;

// Multiple tables
await sql`TRUNCATE orders, order_items, shipping`;
```

---

## Common Table Expressions (CTEs)

### Basic CTE

```typescript
await sql`
  WITH active_users AS (
    SELECT * FROM users WHERE active = true
  )
  SELECT * FROM active_users WHERE created_at > ${date}
`;
```

### Multiple CTEs

```typescript
await sql`
  WITH
  recent_orders AS (
    SELECT * FROM orders
    WHERE created_at > NOW() - INTERVAL '30 days'
  ),
  high_value AS (
    SELECT * FROM recent_orders
    WHERE amount > 1000
  )
  SELECT customer_id, COUNT(*), SUM(amount)
  FROM high_value
  GROUP BY customer_id
`;
```

### Recursive CTE

```typescript
// Tree traversal
await sql`
  WITH RECURSIVE tree AS (
    -- Base case
    SELECT id, name, parent_id, 1 AS depth, ARRAY[id] AS path
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Recursive case
    SELECT c.id, c.name, c.parent_id, t.depth + 1, t.path || c.id
    FROM categories c
    JOIN tree t ON c.parent_id = t.id
    WHERE c.id <> ALL(t.path)  -- Cycle prevention
  )
  SELECT * FROM tree ORDER BY path
`;

// Number sequence
await sql`
  WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 100
  )
  SELECT * FROM seq
`;
```

### Modifying CTEs

```typescript
// DELETE with CTE
await sql`
  WITH deleted AS (
    DELETE FROM old_logs
    WHERE created_at < NOW() - INTERVAL '1 year'
    RETURNING *
  )
  INSERT INTO archived_logs SELECT * FROM deleted
`;

// UPDATE with CTE
await sql`
  WITH updated AS (
    UPDATE products
    SET price = price * 1.1
    WHERE category = 'electronics'
    RETURNING *
  )
  SELECT category, AVG(price) FROM updated GROUP BY category
`;
```

---

## Window Functions

### Frame Specification

```sql
window_function() OVER (
    [PARTITION BY expression [, ...]]
    [ORDER BY expression [ASC | DESC | USING operator] [NULLS {FIRST | LAST}] [, ...]]
    [frame_clause]
)

frame_clause:
    { RANGE | ROWS | GROUPS } frame_start [ frame_exclusion ]
    { RANGE | ROWS | GROUPS } BETWEEN frame_start AND frame_end [ frame_exclusion ]

frame_start / frame_end:
    UNBOUNDED PRECEDING
    offset PRECEDING
    CURRENT ROW
    offset FOLLOWING
    UNBOUNDED FOLLOWING

frame_exclusion:
    EXCLUDE CURRENT ROW
    EXCLUDE GROUP
    EXCLUDE TIES
    EXCLUDE NO OTHERS
```

### Ranking Functions

```typescript
await sql`
  SELECT
    name,
    department,
    salary,
    ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS row_num,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS rank,
    DENSE_RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS dense_rank,
    NTILE(4) OVER (ORDER BY salary DESC) AS quartile,
    PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
    CUME_DIST() OVER (ORDER BY salary) AS cume_dist
  FROM employees
`;
```

### Value Functions

```typescript
await sql`
  SELECT
    date,
    value,
    LAG(value, 1) OVER w AS prev_value,
    LAG(value, 7) OVER w AS week_ago,
    LEAD(value, 1) OVER w AS next_value,
    FIRST_VALUE(value) OVER w AS first_val,
    LAST_VALUE(value) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_val,
    NTH_VALUE(value, 3) OVER w AS third_val
  FROM daily_metrics
  WINDOW w AS (ORDER BY date)
`;
```

### Aggregate Window Functions

```typescript
await sql`
  SELECT
    date,
    revenue,
    SUM(revenue) OVER (ORDER BY date) AS running_total,
    AVG(revenue) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS moving_avg_7d,
    SUM(revenue) OVER (PARTITION BY EXTRACT(YEAR FROM date)) AS yearly_total,
    COUNT(*) OVER () AS total_count
  FROM daily_sales
`;
```

### Named Windows

```typescript
await sql`
  SELECT
    product_id,
    sale_date,
    amount,
    SUM(amount) OVER w AS running_total,
    AVG(amount) OVER w AS running_avg
  FROM sales
  WINDOW w AS (PARTITION BY product_id ORDER BY sale_date)
`;
```

---

## Set Operations

### UNION

```typescript
// Remove duplicates
await sql`
  SELECT name, email FROM users
  UNION
  SELECT name, email FROM leads
`;

// Keep duplicates
await sql`
  SELECT name, email FROM users
  UNION ALL
  SELECT name, email FROM leads
`;
```

### INTERSECT

```typescript
await sql`
  SELECT user_id FROM orders
  INTERSECT
  SELECT user_id FROM reviews
`;
```

### EXCEPT

```typescript
await sql`
  SELECT user_id FROM users
  EXCEPT
  SELECT user_id FROM deleted_users
`;
```

### Combined Operations

```typescript
await sql`
  (SELECT name FROM products WHERE category = 'electronics')
  UNION
  (SELECT name FROM products WHERE price > 1000)
  EXCEPT
  (SELECT name FROM discontinued_products)
  ORDER BY name
`;
```

---

## Conditional Expressions

### CASE

```typescript
await sql`
  SELECT
    name,
    CASE status
      WHEN 'active' THEN 'Active User'
      WHEN 'pending' THEN 'Pending Verification'
      WHEN 'suspended' THEN 'Account Suspended'
      ELSE 'Unknown Status'
    END AS status_label
  FROM users
`;

await sql`
  SELECT
    name,
    CASE
      WHEN price < 10 THEN 'budget'
      WHEN price < 50 THEN 'mid-range'
      WHEN price < 100 THEN 'premium'
      ELSE 'luxury'
    END AS price_tier
  FROM products
`;
```

### COALESCE

```typescript
await sql`
  SELECT
    COALESCE(nickname, full_name, 'Anonymous') AS display_name
  FROM users
`;
```

### NULLIF

```typescript
// Returns NULL if arguments are equal (prevents division by zero)
await sql`
  SELECT
    total / NULLIF(count, 0) AS average
  FROM stats
`;
```

### GREATEST / LEAST

```typescript
await sql`
  SELECT
    GREATEST(price, min_price) AS effective_price,
    LEAST(quantity, max_quantity) AS available_quantity
  FROM products
`;
```

---

## Date/Time Operations

### Current Date/Time

```typescript
await sql`
  SELECT
    NOW() AS current_timestamp,
    CURRENT_DATE AS today,
    CURRENT_TIME AS current_time,
    CURRENT_TIMESTAMP AS timestamp_tz,
    LOCALTIME AS local_time,
    LOCALTIMESTAMP AS local_timestamp
`;
```

### Date Arithmetic

```typescript
await sql`
  SELECT
    created_at + INTERVAL '7 days' AS week_later,
    created_at - INTERVAL '1 month' AS month_ago,
    AGE(NOW(), created_at) AS age,
    NOW() - created_at AS duration
  FROM users
`;
```

### Date Extraction

```typescript
await sql`
  SELECT
    EXTRACT(YEAR FROM created_at) AS year,
    EXTRACT(MONTH FROM created_at) AS month,
    EXTRACT(DAY FROM created_at) AS day,
    EXTRACT(HOUR FROM created_at) AS hour,
    EXTRACT(DOW FROM created_at) AS day_of_week,
    EXTRACT(DOY FROM created_at) AS day_of_year,
    EXTRACT(WEEK FROM created_at) AS week,
    EXTRACT(QUARTER FROM created_at) AS quarter,
    EXTRACT(EPOCH FROM created_at) AS unix_timestamp
  FROM orders
`;
```

### Date Truncation

```typescript
await sql`
  SELECT
    DATE_TRUNC('day', created_at) AS day,
    DATE_TRUNC('week', created_at) AS week,
    DATE_TRUNC('month', created_at) AS month,
    DATE_TRUNC('quarter', created_at) AS quarter,
    DATE_TRUNC('year', created_at) AS year
  FROM orders
`;
```

### Date Formatting

```typescript
await sql`
  SELECT
    TO_CHAR(created_at, 'YYYY-MM-DD') AS date_iso,
    TO_CHAR(created_at, 'Mon DD, YYYY') AS date_readable,
    TO_CHAR(created_at, 'HH24:MI:SS') AS time_24h,
    TO_CHAR(created_at, 'Day, Month DD, YYYY') AS date_full
  FROM orders
`;
```

### Date Series Generation

```typescript
await sql`
  SELECT generate_series(
    ${startDate}::date,
    ${endDate}::date,
    '1 day'::interval
  ) AS date
`;

await sql`
  SELECT
    d::date AS date,
    COALESCE(o.total, 0) AS total
  FROM generate_series(
    NOW() - INTERVAL '30 days',
    NOW(),
    '1 day'
  ) d
  LEFT JOIN (
    SELECT DATE_TRUNC('day', created_at) AS day, SUM(amount) AS total
    FROM orders
    GROUP BY 1
  ) o ON o.day = d::date
`;
```

---

## String Operations

### String Functions

```typescript
await sql`
  SELECT
    LOWER(name) AS lowercase,
    UPPER(name) AS uppercase,
    INITCAP(name) AS title_case,
    LENGTH(name) AS length,
    TRIM(name) AS trimmed,
    LTRIM(name) AS left_trimmed,
    RTRIM(name) AS right_trimmed,
    LEFT(name, 10) AS first_10,
    RIGHT(name, 10) AS last_10,
    SUBSTRING(name FROM 1 FOR 10) AS substring,
    REPLACE(name, 'old', 'new') AS replaced,
    REVERSE(name) AS reversed
  FROM users
`;
```

### String Concatenation

```typescript
await sql`
  SELECT
    first_name || ' ' || last_name AS full_name,
    CONCAT(first_name, ' ', last_name) AS concatenated,
    CONCAT_WS(', ', city, state, country) AS location
  FROM users
`;
```

### String Matching

```typescript
await sql`
  SELECT * FROM products WHERE name LIKE ${`%${search}%`}
`;

await sql`
  SELECT * FROM products WHERE name ILIKE ${`%${search}%`}
`;

await sql`
  SELECT * FROM products WHERE name ~ ${pattern}
`;

await sql`
  SELECT * FROM products WHERE name SIMILAR TO ${pattern}
`;
```

### String Splitting/Aggregation

```typescript
// Split string to array
await sql`SELECT string_to_array('a,b,c', ',') AS parts`;

// Array to string
await sql`SELECT array_to_string(tags, ', ') AS tag_list FROM products`;

// Split to rows
await sql`SELECT unnest(string_to_array('a,b,c', ',')) AS part`;

// Aggregate to string
await sql`
  SELECT
    category,
    string_agg(name, ', ' ORDER BY name) AS product_names
  FROM products
  GROUP BY category
`;
```

---

## Array Operations

### Array Creation

```typescript
await sql`SELECT ARRAY[1, 2, 3] AS arr`;
await sql`SELECT ARRAY['a', 'b', 'c'] AS arr`;
await sql`SELECT array_agg(id) FROM users`; // Aggregate to array
```

### Array Access

```typescript
await sql`SELECT tags[1] AS first_tag FROM products`; // 1-indexed
await sql`SELECT tags[1:3] AS first_three FROM products`; // Slice
```

### Array Operators

```typescript
// Contains
await sql`SELECT * FROM products WHERE tags @> ARRAY['sale']`;

// Is contained by
await sql`SELECT * FROM products WHERE tags <@ ARRAY['sale', 'new', 'featured']`;

// Overlap
await sql`SELECT * FROM products WHERE tags && ARRAY['sale', 'new']`;

// Concatenate
await sql`SELECT tags || 'new_tag' FROM products`;
await sql`SELECT tags || ARRAY['a', 'b'] FROM products`;
```

### Array Functions

```typescript
await sql`
  SELECT
    array_length(tags, 1) AS length,
    array_dims(tags) AS dimensions,
    array_upper(tags, 1) AS upper_bound,
    array_lower(tags, 1) AS lower_bound,
    array_position(tags, 'sale') AS position,
    array_remove(tags, 'old') AS without_old,
    array_replace(tags, 'old', 'new') AS replaced,
    array_append(tags, 'new') AS appended,
    array_prepend('first', tags) AS prepended,
    array_cat(tags, ARRAY['a', 'b']) AS concatenated
  FROM products
`;
```

### Unnest (Array to Rows)

```typescript
await sql`
  SELECT
    p.id,
    p.name,
    tag
  FROM products p,
  unnest(p.tags) AS tag
`;

// With ordinality (includes position)
await sql`
  SELECT
    p.id,
    tag,
    position
  FROM products p,
  unnest(p.tags) WITH ORDINALITY AS t(tag, position)
`;
```
