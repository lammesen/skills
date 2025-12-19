# JSON/JSONB Operations Reference

Complete reference for PostgreSQL JSON and JSONB operations with Bun.sql.

## JSON vs JSONB

| Feature | JSON | JSONB |
|---------|------|-------|
| Storage | Text (preserves whitespace, key order) | Binary (normalized) |
| Processing | Parse on each access | Pre-parsed, faster |
| Indexing | No GIN/GiST support | Full index support |
| Duplicate keys | Keeps all | Keeps last |
| Size | Smaller on disk | Larger (overhead) |
| Use case | Log storage, exact preservation | Most applications |

**Recommendation**: Use JSONB unless you need exact text preservation.

---

## Extraction Operators

### Arrow Operators

```typescript
// -> returns JSON/JSONB
await sql`SELECT data->'address' FROM users`;           // Object
await sql`SELECT data->'tags'->0 FROM users`;           // Array element
await sql`SELECT data->'address'->'city' FROM users`;   // Nested

// ->> returns TEXT
await sql`SELECT data->>'name' FROM users`;             // Text value
await sql`SELECT data->'address'->>'city' FROM users`;  // Nested text

// #> path extraction (returns JSON/JSONB)
await sql`SELECT data#>'{address,city}' FROM users`;
await sql`SELECT data#>'{items,0,name}' FROM orders`;

// #>> path extraction (returns TEXT)
await sql`SELECT data#>>'{address,city}' FROM users`;
await sql`SELECT data#>>'{contacts,0,email}' FROM users`;
```

### Extraction with Bun.sql

```typescript
const users = await sql`
  SELECT
    id,
    data->>'name' AS name,
    data->'address'->>'city' AS city,
    data#>>'{contacts,0,email}' AS primary_email,
    (data->>'age')::integer AS age
  FROM users
  WHERE data->>'status' = ${status}
`;
```

---

## Containment Operators

### @> Contains

```typescript
// Check if left contains right
await sql`SELECT * FROM products WHERE data @> '{"active": true}'`;
await sql`SELECT * FROM products WHERE data @> ${sql({ category: "electronics" })}`;

// Array containment
await sql`SELECT * FROM products WHERE data->'tags' @> '["sale"]'`;

// Nested containment
await sql`SELECT * FROM users WHERE data @> '{"address": {"country": "US"}}'`;
```

### <@ Is Contained By

```typescript
await sql`
  SELECT * FROM products
  WHERE data <@ '{"category": "electronics", "active": true, "featured": false}'
`;
```

---

## Existence Operators

### ? Key Exists

```typescript
// Single key exists
await sql`SELECT * FROM users WHERE data ? 'email'`;

// Key doesn't exist
await sql`SELECT * FROM users WHERE NOT (data ? 'deleted_at')`;
```

### ?| Any Key Exists

```typescript
await sql`
  SELECT * FROM users
  WHERE data ?| array['email', 'phone', 'address']
`;
```

### ?& All Keys Exist

```typescript
await sql`
  SELECT * FROM users
  WHERE data ?& array['email', 'phone', 'address']
`;
```

---

## JSON Path Queries (PostgreSQL 12+)

### Basic JSON Path

```typescript
// Check path exists
await sql`SELECT * FROM products WHERE data @? '$.tags[*] ? (@ == "sale")'`;

// Get matching values
await sql`
  SELECT jsonb_path_query(data, '$.items[*].price') AS prices
  FROM orders
`;

// Get all matching values as array
await sql`
  SELECT jsonb_path_query_array(data, '$.items[*].name') AS item_names
  FROM orders
`;

// Get first match
await sql`
  SELECT jsonb_path_query_first(data, '$.items[0].name') AS first_item
  FROM orders
`;
```

### JSON Path with Variables

```typescript
await sql`
  SELECT jsonb_path_query(
    data,
    '$.items[*] ? (@.price > $min && @.price < $max)',
    '{"min": 10, "max": 100}'
  ) AS filtered_items
  FROM orders
`;

// With Bun.sql parameters
const vars = JSON.stringify({ min_price: minPrice, max_price: maxPrice });
await sql`
  SELECT jsonb_path_query_array(
    data,
    '$.items[*] ? (@.price >= $min_price && @.price <= $max_price)',
    ${vars}::jsonb
  ) AS matching_items
  FROM orders
`;
```

### JSON Path Predicates

```typescript
// Existence check
await sql`
  SELECT * FROM orders
  WHERE jsonb_path_exists(data, '$.items[*] ? (@.quantity > 10)')
`;

// Match check
await sql`
  SELECT * FROM orders
  WHERE jsonb_path_match(data, '$.total > 1000')
`;
```

### JSON Path Syntax Reference

| Syntax | Description | Example |
|--------|-------------|---------|
| `$` | Root element | `$.name` |
| `.key` | Object member | `$.address.city` |
| `[n]` | Array element | `$.items[0]` |
| `[*]` | All array elements | `$.items[*].name` |
| `.*` | All object values | `$.*` |
| `.**` | All descendants | `$.**` |
| `? (expr)` | Filter expression | `$.items[*] ? (@.price > 10)` |
| `@` | Current element in filter | `? (@.active == true)` |
| `.type()` | Type of value | `$.price.type()` |
| `.size()` | Array/object size | `$.items.size()` |
| `.double()` | Convert to number | `$.price.double()` |
| `.ceiling()` | Round up | `$.price.ceiling()` |
| `.floor()` | Round down | `$.price.floor()` |
| `.abs()` | Absolute value | `$.discount.abs()` |
| `.keyvalue()` | Key-value pairs | `$.*.keyvalue()` |

---

## Modification Functions

### jsonb_set

```typescript
// Update nested value
await sql`
  UPDATE users
  SET data = jsonb_set(data, '{address,city}', '"New York"')
  WHERE id = ${userId}
`;

// Create missing path
await sql`
  UPDATE users
  SET data = jsonb_set(data, '{preferences,theme}', '"dark"', true)
  WHERE id = ${userId}
`;

// With Bun.sql parameter
await sql`
  UPDATE users
  SET data = jsonb_set(data, '{address,city}', ${JSON.stringify(city)}::jsonb)
  WHERE id = ${userId}
`;
```

### jsonb_insert

```typescript
// Insert into array (after position)
await sql`
  UPDATE products
  SET data = jsonb_insert(data, '{tags,0}', '"new_tag"', false)
  WHERE id = ${productId}
`;

// Insert before position
await sql`
  UPDATE products
  SET data = jsonb_insert(data, '{tags,0}', '"first_tag"', true)
  WHERE id = ${productId}
`;
```

### Concatenation (||)

```typescript
// Merge objects
await sql`
  UPDATE users
  SET data = data || '{"last_login": "2024-01-15T10:30:00Z"}'
  WHERE id = ${userId}
`;

// Add to array
await sql`
  UPDATE products
  SET data = jsonb_set(
    data,
    '{tags}',
    (data->'tags') || '"new_tag"'
  )
  WHERE id = ${productId}
`;

// Merge with Bun.sql
await sql`
  UPDATE users
  SET data = data || ${sql({ lastLogin: new Date().toISOString() })}::jsonb
  WHERE id = ${userId}
`;
```

### Key Removal (-)

```typescript
// Remove top-level key
await sql`UPDATE users SET data = data - 'temporary' WHERE id = ${userId}`;

// Remove multiple keys
await sql`UPDATE users SET data = data - '{temp1,temp2}' WHERE id = ${userId}`;

// Remove from array by index
await sql`UPDATE users SET data = data - 0 WHERE id = ${userId}`;
```

### Path Removal (#-)

```typescript
// Remove nested key
await sql`
  UPDATE users
  SET data = data #- '{address,apartment}'
  WHERE id = ${userId}
`;

// Remove array element by path
await sql`
  UPDATE orders
  SET data = data #- '{items,0}'
  WHERE id = ${orderId}
`;
```

---

## Construction Functions

### json_build_object

```typescript
const result = await sql`
  SELECT json_build_object(
    'id', id,
    'name', name,
    'email', email,
    'created_at', created_at
  ) AS user_json
  FROM users
  WHERE id = ${userId}
`;
```

### json_build_array

```typescript
const result = await sql`
  SELECT json_build_array(
    name,
    email,
    created_at
  ) AS user_array
  FROM users
`;
```

### json_object

```typescript
// From key-value arrays
await sql`SELECT json_object('{name,email}', '{John,john@example.com}')`;

// From two arrays
await sql`SELECT json_object(array['a','b'], array['1','2'])`;
```

### row_to_json

```typescript
const result = await sql`
  SELECT row_to_json(u) AS user_json
  FROM users u
  WHERE id = ${userId}
`;

// With pretty printing
await sql`SELECT row_to_json(u, true) FROM users u`;
```

### to_json / to_jsonb

```typescript
await sql`SELECT to_jsonb(ARRAY[1, 2, 3])`;
await sql`SELECT to_jsonb(ROW(1, 'text', true))`;
```

---

## Aggregation Functions

### json_agg

```typescript
const result = await sql`
  SELECT
    category,
    json_agg(name ORDER BY name) AS product_names
  FROM products
  GROUP BY category
`;

// With full object
await sql`
  SELECT
    o.id AS order_id,
    json_agg(
      json_build_object(
        'product', p.name,
        'quantity', oi.quantity,
        'price', oi.price
      )
    ) AS items
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.id
  JOIN products p ON p.id = oi.product_id
  GROUP BY o.id
`;
```

### json_object_agg

```typescript
const result = await sql`
  SELECT json_object_agg(key, value) AS config
  FROM settings
  WHERE category = 'display'
`;

// Create lookup object
await sql`
  SELECT json_object_agg(sku, price) AS price_lookup
  FROM products
  WHERE active = true
`;
```

### jsonb_agg with FILTER

```typescript
await sql`
  SELECT
    customer_id,
    jsonb_agg(order_id) FILTER (WHERE status = 'completed') AS completed_orders,
    jsonb_agg(order_id) FILTER (WHERE status = 'pending') AS pending_orders
  FROM orders
  GROUP BY customer_id
`;
```

---

## Expansion Functions

### jsonb_each / jsonb_each_text

```typescript
// Expand object to rows (key, value)
await sql`
  SELECT key, value
  FROM users,
  jsonb_each(data->'preferences')
`;

// Text values
await sql`
  SELECT key, value
  FROM users,
  jsonb_each_text(data->'settings')
`;
```

### jsonb_array_elements

```typescript
// Expand array to rows
await sql`
  SELECT
    o.id,
    item->>'name' AS item_name,
    (item->>'price')::numeric AS price
  FROM orders o,
  jsonb_array_elements(o.data->'items') AS item
`;

// With ordinality (position)
await sql`
  SELECT
    o.id,
    position,
    item->>'name' AS item_name
  FROM orders o,
  jsonb_array_elements(o.data->'items') WITH ORDINALITY AS t(item, position)
`;
```

### jsonb_to_record

```typescript
await sql`
  SELECT *
  FROM jsonb_to_record('{"name": "John", "age": 30}'::jsonb)
  AS x(name text, age int)
`;

// From table
await sql`
  SELECT t.*
  FROM users u,
  jsonb_to_record(u.data) AS t(name text, email text, age int)
`;
```

### jsonb_to_recordset

```typescript
await sql`
  SELECT *
  FROM jsonb_to_recordset('[{"a":1,"b":"x"},{"a":2,"b":"y"}]'::jsonb)
  AS x(a int, b text)
`;

// Expand array column
await sql`
  SELECT o.id, item.*
  FROM orders o,
  jsonb_to_recordset(o.data->'items')
  AS item(name text, quantity int, price numeric)
`;
```

### jsonb_populate_record

```typescript
// Fill record type from JSONB
await sql`
  SELECT (jsonb_populate_record(null::users, data)).*
  FROM raw_user_data
`;
```

---

## Type Functions

### jsonb_typeof

```typescript
await sql`
  SELECT
    jsonb_typeof('null'::jsonb) AS null_type,      -- 'null'
    jsonb_typeof('true'::jsonb) AS bool_type,      -- 'boolean'
    jsonb_typeof('123'::jsonb) AS num_type,        -- 'number'
    jsonb_typeof('"text"'::jsonb) AS str_type,     -- 'string'
    jsonb_typeof('[]'::jsonb) AS arr_type,         -- 'array'
    jsonb_typeof('{}'::jsonb) AS obj_type          -- 'object'
`;
```

### Type checking in queries

```typescript
await sql`
  SELECT * FROM products
  WHERE jsonb_typeof(data->'price') = 'number'
`;

await sql`
  SELECT * FROM products
  WHERE jsonb_typeof(data->'tags') = 'array'
    AND jsonb_array_length(data->'tags') > 0
`;
```

---

## Utility Functions

### jsonb_strip_nulls

```typescript
await sql`
  SELECT jsonb_strip_nulls('{"a": 1, "b": null, "c": {"d": null}}'::jsonb)
`;
-- Result: {"a": 1, "c": {}}
```

### jsonb_pretty

```typescript
await sql`
  SELECT jsonb_pretty(data) AS formatted_json
  FROM users
  WHERE id = ${userId}
`;
```

### jsonb_array_length

```typescript
await sql`
  SELECT * FROM products
  WHERE jsonb_array_length(data->'tags') > 5
`;
```

### jsonb_object_keys

```typescript
await sql`
  SELECT jsonb_object_keys(data) AS key
  FROM users
  WHERE id = ${userId}
`;
```

---

## Indexing Strategies

### GIN Index (Default)

```typescript
// Full JSONB indexing
await sql`CREATE INDEX users_data_idx ON users USING GIN (data)`;

// Supports: @>, ?, ?|, ?&
await sql`SELECT * FROM users WHERE data @> '{"active": true}'`;
```

### GIN with jsonb_path_ops

```typescript
// Optimized for @> containment only
await sql`CREATE INDEX users_data_path_idx ON users USING GIN (data jsonb_path_ops)`;

// 2-3x smaller index, faster @> queries
await sql`SELECT * FROM users WHERE data @> '{"status": "active"}'`;
```

### Expression Index

```typescript
// Index specific key
await sql`CREATE INDEX users_email_idx ON users ((data->>'email'))`;

// Index nested path
await sql`CREATE INDEX users_city_idx ON users ((data#>>'{address,city}'))`;

// Index with type cast
await sql`CREATE INDEX users_age_idx ON users (((data->>'age')::integer))`;
```

### Partial Index

```typescript
await sql`
  CREATE INDEX active_users_data_idx ON users USING GIN (data)
  WHERE data->>'status' = 'active'
`;
```

---

## Performance Best Practices

1. **Use JSONB over JSON** for query performance
2. **Index frequently queried paths** with expression indexes
3. **Use GIN indexes** for containment queries
4. **Prefer jsonb_path_ops** when only using @> operator
5. **Extract hot columns** to regular columns if queried frequently
6. **Limit document size** (< 1MB recommended)
7. **Avoid deeply nested structures** (> 5 levels)
8. **Use partial indexes** for filtered queries
9. **Analyze query plans** with EXPLAIN ANALYZE

### Query Plan Example

```typescript
await sql`
  EXPLAIN (ANALYZE, FORMAT JSON)
  SELECT * FROM users
  WHERE data @> '{"status": "active"}'
`;
```
