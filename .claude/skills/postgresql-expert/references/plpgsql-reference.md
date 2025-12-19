# PL/pgSQL Reference

Complete guide to PostgreSQL procedural language with Bun.sql.

## Function Basics

### Basic Structure

```sql
CREATE OR REPLACE FUNCTION function_name(parameter_list)
RETURNS return_type
AS $$
DECLARE
  -- Variable declarations
BEGIN
  -- Function body
  RETURN value;
END;
$$ LANGUAGE plpgsql;
```

### Function Volatility

| Volatility | Description | Use Case |
|------------|-------------|----------|
| `VOLATILE` (default) | Can modify database, results vary | INSERT, UPDATE, DELETE, random() |
| `STABLE` | No modifications, consistent within query | SELECT only, NOW() |
| `IMMUTABLE` | Pure function, always same result | Math, string operations |

```typescript
await sql`
  CREATE OR REPLACE FUNCTION calculate_tax(amount NUMERIC)
  RETURNS NUMERIC
  IMMUTABLE
  AS $$
  BEGIN
    RETURN amount * 0.08;
  END;
  $$ LANGUAGE plpgsql;
`;
```

### Security Options

```typescript
// SECURITY INVOKER (default) - runs with caller's permissions
await sql`
  CREATE FUNCTION get_user_data(user_id INT)
  RETURNS TABLE(id INT, email TEXT)
  SECURITY INVOKER
  AS $$ ... $$ LANGUAGE plpgsql;
`;

// SECURITY DEFINER - runs with creator's permissions (like SUID)
await sql`
  CREATE FUNCTION admin_only_operation()
  RETURNS VOID
  SECURITY DEFINER
  SET search_path = public
  AS $$ ... $$ LANGUAGE plpgsql;
`;
```

---

## Variables and Types

### Declaration

```sql
DECLARE
  -- Basic types
  user_id INTEGER;
  user_name VARCHAR(100);
  total_amount NUMERIC(10, 2) := 0;
  is_active BOOLEAN DEFAULT true;
  created_at TIMESTAMP := NOW();

  -- Copy type from column
  user_email users.email%TYPE;

  -- Copy entire row type
  user_row users%ROWTYPE;

  -- Record (dynamic row)
  rec RECORD;

  -- Array
  tag_list TEXT[];

  -- JSONB
  metadata JSONB;

  -- Constant
  TAX_RATE CONSTANT NUMERIC := 0.08;
```

### Assignment

```sql
-- Direct assignment
user_name := 'John';

-- From SELECT
SELECT name INTO user_name FROM users WHERE id = user_id;

-- Multiple columns
SELECT name, email INTO user_name, user_email FROM users WHERE id = user_id;

-- Into record
SELECT * INTO rec FROM users WHERE id = user_id;

-- Strict (error if not exactly one row)
SELECT name INTO STRICT user_name FROM users WHERE id = user_id;
```

---

## Control Structures

### IF-THEN-ELSE

```sql
IF condition THEN
  -- statements
ELSIF another_condition THEN
  -- statements
ELSE
  -- statements
END IF;
```

```typescript
await sql`
  CREATE OR REPLACE FUNCTION get_price_tier(price NUMERIC)
  RETURNS TEXT
  AS $$
  BEGIN
    IF price < 10 THEN
      RETURN 'budget';
    ELSIF price < 50 THEN
      RETURN 'standard';
    ELSIF price < 100 THEN
      RETURN 'premium';
    ELSE
      RETURN 'luxury';
    END IF;
  END;
  $$ LANGUAGE plpgsql IMMUTABLE;
`;
```

### CASE

```sql
-- Simple CASE
CASE expression
  WHEN value1 THEN result1
  WHEN value2 THEN result2
  ELSE default_result
END

-- Searched CASE
CASE
  WHEN condition1 THEN result1
  WHEN condition2 THEN result2
  ELSE default_result
END
```

### Loops

#### Basic LOOP

```sql
LOOP
  -- statements
  EXIT WHEN condition;
END LOOP;
```

#### WHILE Loop

```sql
WHILE condition LOOP
  -- statements
END LOOP;
```

#### FOR Loop (Integer Range)

```sql
FOR i IN 1..10 LOOP
  -- statements (i goes 1, 2, ..., 10)
END LOOP;

FOR i IN REVERSE 10..1 LOOP
  -- statements (i goes 10, 9, ..., 1)
END LOOP;

FOR i IN 1..100 BY 10 LOOP
  -- statements (i goes 1, 11, 21, ..., 91)
END LOOP;
```

#### FOR Loop (Query Results)

```sql
FOR rec IN SELECT * FROM users WHERE active LOOP
  -- rec contains each row
  RAISE NOTICE 'User: %', rec.name;
END LOOP;

-- With dynamic query
FOR rec IN EXECUTE 'SELECT * FROM ' || table_name LOOP
  -- statements
END LOOP;
```

#### FOREACH (Arrays)

```sql
FOREACH tag IN ARRAY tag_list LOOP
  RAISE NOTICE 'Tag: %', tag;
END LOOP;

-- With slice
FOREACH item SLICE 1 IN ARRAY two_dimensional_array LOOP
  -- item is each row of the 2D array
END LOOP;
```

### Loop Control

```sql
-- Exit loop
EXIT;
EXIT WHEN condition;
EXIT label WHEN condition;  -- Exit outer loop

-- Skip to next iteration
CONTINUE;
CONTINUE WHEN condition;

-- Labels
<<outer_loop>>
FOR i IN 1..10 LOOP
  <<inner_loop>>
  FOR j IN 1..10 LOOP
    EXIT outer_loop WHEN i * j > 50;
  END LOOP inner_loop;
END LOOP outer_loop;
```

---

## Returning Data

### Single Value

```typescript
await sql`
  CREATE OR REPLACE FUNCTION get_user_count()
  RETURNS BIGINT
  AS $$
  DECLARE
    user_count BIGINT;
  BEGIN
    SELECT COUNT(*) INTO user_count FROM users;
    RETURN user_count;
  END;
  $$ LANGUAGE plpgsql STABLE;
`;
```

### RETURNS TABLE

```typescript
await sql`
  CREATE OR REPLACE FUNCTION get_active_users(min_orders INT DEFAULT 1)
  RETURNS TABLE(
    user_id INTEGER,
    user_name VARCHAR,
    order_count BIGINT
  )
  AS $$
  BEGIN
    RETURN QUERY
    SELECT
      u.id,
      u.name,
      COUNT(o.id)
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.id
    GROUP BY u.id
    HAVING COUNT(o.id) >= min_orders;
  END;
  $$ LANGUAGE plpgsql STABLE;
`;

// Call it
const users = await sql`SELECT * FROM get_active_users(5)`;
```

### RETURNS SETOF

```typescript
await sql`
  CREATE OR REPLACE FUNCTION get_users_by_role(role_name VARCHAR)
  RETURNS SETOF users
  AS $$
  BEGIN
    RETURN QUERY SELECT * FROM users WHERE role = role_name;
  END;
  $$ LANGUAGE plpgsql STABLE;
`;
```

### OUT Parameters

```typescript
await sql`
  CREATE OR REPLACE FUNCTION get_order_stats(
    customer_id INTEGER,
    OUT total_orders BIGINT,
    OUT total_amount NUMERIC,
    OUT avg_amount NUMERIC
  )
  AS $$
  BEGIN
    SELECT
      COUNT(*),
      COALESCE(SUM(amount), 0),
      COALESCE(AVG(amount), 0)
    INTO total_orders, total_amount, avg_amount
    FROM orders
    WHERE customer_id = get_order_stats.customer_id;
  END;
  $$ LANGUAGE plpgsql STABLE;
`;

const [stats] = await sql`SELECT * FROM get_order_stats(${customerId})`;
```

### RETURN NEXT (Row at a Time)

```typescript
await sql`
  CREATE OR REPLACE FUNCTION generate_date_series(
    start_date DATE,
    end_date DATE
  )
  RETURNS SETOF DATE
  AS $$
  DECLARE
    current_date DATE := start_date;
  BEGIN
    WHILE current_date <= end_date LOOP
      RETURN NEXT current_date;
      current_date := current_date + INTERVAL '1 day';
    END LOOP;
    RETURN;
  END;
  $$ LANGUAGE plpgsql IMMUTABLE;
`;
```

---

## Exception Handling

### Basic Exception Handling

```sql
BEGIN
  -- risky operation
EXCEPTION
  WHEN unique_violation THEN
    -- handle duplicate key
  WHEN foreign_key_violation THEN
    -- handle FK error
  WHEN OTHERS THEN
    -- catch all
END;
```

### Exception Variables

```sql
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error code: %, Message: %', SQLSTATE, SQLERRM;
    -- Also available:
    -- SQLSTATE: error code
    -- SQLERRM: error message
```

### GET DIAGNOSTICS

```sql
DECLARE
  row_count INTEGER;
  context TEXT;
BEGIN
  UPDATE users SET active = false WHERE last_login < NOW() - INTERVAL '1 year';
  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE 'Deactivated % users', row_count;
EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS context = PG_EXCEPTION_CONTEXT;
    RAISE NOTICE 'Error context: %', context;
END;
```

### Complete Example

```typescript
await sql`
  CREATE OR REPLACE FUNCTION safe_transfer(
    from_account INTEGER,
    to_account INTEGER,
    amount NUMERIC
  )
  RETURNS BOOLEAN
  AS $$
  DECLARE
    from_balance NUMERIC;
  BEGIN
    -- Check balance
    SELECT balance INTO from_balance
    FROM accounts
    WHERE id = from_account
    FOR UPDATE;

    IF from_balance IS NULL THEN
      RAISE EXCEPTION 'Account % not found', from_account;
    END IF;

    IF from_balance < amount THEN
      RAISE EXCEPTION 'Insufficient funds: % < %', from_balance, amount
        USING HINT = 'Add more funds to the account';
    END IF;

    -- Perform transfer
    UPDATE accounts SET balance = balance - amount WHERE id = from_account;
    UPDATE accounts SET balance = balance + amount WHERE id = to_account;

    RETURN true;

  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'Transfer failed: %', SQLERRM;
      RETURN false;
  END;
  $$ LANGUAGE plpgsql;
`;
```

### Common Error Codes

| Code | Condition Name | Description |
|------|----------------|-------------|
| 23505 | unique_violation | Duplicate key |
| 23503 | foreign_key_violation | FK constraint |
| 23502 | not_null_violation | NULL in NOT NULL column |
| 23514 | check_violation | CHECK constraint |
| 22012 | division_by_zero | Division by zero |
| P0001 | raise_exception | User-raised exception |
| P0002 | no_data_found | SELECT INTO returned no rows |
| P0003 | too_many_rows | SELECT INTO returned multiple rows |

---

## RAISE Statements

### Message Levels

```sql
RAISE DEBUG 'Debug message';
RAISE LOG 'Log message';
RAISE INFO 'Info message';
RAISE NOTICE 'Notice message';  -- Most common
RAISE WARNING 'Warning message';
RAISE EXCEPTION 'Error message';  -- Aborts transaction
```

### Formatting

```sql
RAISE NOTICE 'User % has % orders', user_name, order_count;
RAISE NOTICE 'Value: %', quote_literal(user_input);
RAISE NOTICE 'Identifier: %', quote_ident(column_name);
```

### Exception with Details

```sql
RAISE EXCEPTION 'Invalid operation'
  USING
    ERRCODE = 'P0001',
    DETAIL = 'Operation X requires permission Y',
    HINT = 'Contact administrator for access';
```

---

## Triggers

### Trigger Function Structure

```sql
CREATE OR REPLACE FUNCTION trigger_function_name()
RETURNS TRIGGER
AS $$
BEGIN
  -- Available special variables:
  -- NEW: new row (INSERT/UPDATE)
  -- OLD: old row (UPDATE/DELETE)
  -- TG_OP: operation ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  -- TG_NAME: trigger name
  -- TG_TABLE_NAME: table name
  -- TG_TABLE_SCHEMA: schema name
  -- TG_WHEN: 'BEFORE', 'AFTER', 'INSTEAD OF'
  -- TG_LEVEL: 'ROW', 'STATEMENT'
  -- TG_ARGV: array of trigger arguments

  RETURN NEW;  -- For BEFORE triggers
END;
$$ LANGUAGE plpgsql;
```

### Trigger Types

```sql
-- BEFORE trigger (can modify NEW, can cancel operation)
CREATE TRIGGER before_insert
  BEFORE INSERT ON table_name
  FOR EACH ROW
  EXECUTE FUNCTION trigger_function();

-- AFTER trigger (cannot modify row)
CREATE TRIGGER after_update
  AFTER UPDATE ON table_name
  FOR EACH ROW
  EXECUTE FUNCTION trigger_function();

-- INSTEAD OF (for views)
CREATE TRIGGER instead_of_insert
  INSTEAD OF INSERT ON view_name
  FOR EACH ROW
  EXECUTE FUNCTION trigger_function();

-- Statement-level
CREATE TRIGGER after_truncate
  AFTER TRUNCATE ON table_name
  FOR EACH STATEMENT
  EXECUTE FUNCTION trigger_function();
```

### Common Trigger Patterns

#### Audit Logging

```typescript
await sql`
  CREATE OR REPLACE FUNCTION audit_trigger_func()
  RETURNS TRIGGER AS $$
  BEGIN
    INSERT INTO audit_log (
      table_name,
      operation,
      old_data,
      new_data,
      changed_by,
      changed_at
    ) VALUES (
      TG_TABLE_NAME,
      TG_OP,
      CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) END,
      CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) END,
      current_user,
      NOW()
    );

    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
`;

await sql`
  CREATE TRIGGER audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger_func()
`;
```

#### Auto-Update Timestamps

```typescript
await sql`
  CREATE OR REPLACE FUNCTION update_timestamps()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.updated_at := NOW();
    IF TG_OP = 'INSERT' THEN
      NEW.created_at := NOW();
    END IF;
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
`;

await sql`
  CREATE TRIGGER set_timestamps
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamps()
`;
```

#### Validation

```typescript
await sql`
  CREATE OR REPLACE FUNCTION validate_order_item()
  RETURNS TRIGGER AS $$
  BEGIN
    IF NEW.quantity <= 0 THEN
      RAISE EXCEPTION 'Quantity must be positive, got: %', NEW.quantity;
    END IF;

    IF NEW.unit_price < 0 THEN
      RAISE EXCEPTION 'Price cannot be negative, got: %', NEW.unit_price;
    END IF;

    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
`;
```

#### Computed Column

```typescript
await sql`
  CREATE OR REPLACE FUNCTION compute_order_total()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.total := NEW.quantity * NEW.unit_price * (1 - COALESCE(NEW.discount, 0));
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
`;
```

#### Conditional Trigger

```sql
CREATE TRIGGER log_price_changes
  AFTER UPDATE OF price ON products
  FOR EACH ROW
  WHEN (OLD.price IS DISTINCT FROM NEW.price)
  EXECUTE FUNCTION log_price_change();
```

---

## Dynamic SQL

### EXECUTE

```sql
EXECUTE 'SELECT * FROM ' || quote_ident(table_name);

-- With parameters (safer)
EXECUTE 'SELECT * FROM users WHERE id = $1' USING user_id;

-- Into variable
EXECUTE 'SELECT name FROM users WHERE id = $1' INTO user_name USING user_id;

-- With format (PostgreSQL 9.1+)
EXECUTE format('SELECT * FROM %I WHERE %I = $1', table_name, column_name)
INTO rec
USING search_value;
```

### format() Function

```sql
format('%s', 'value')           -- String substitution
format('%I', 'column_name')     -- Identifier (quoted if needed)
format('%L', 'O''Brien')        -- Literal (properly escaped)
format('%1$s %2$s', 'a', 'b')   -- Positional
```

### Complete Example

```typescript
await sql`
  CREATE OR REPLACE FUNCTION dynamic_search(
    table_name TEXT,
    search_column TEXT,
    search_value TEXT
  )
  RETURNS SETOF RECORD
  AS $$
  BEGIN
    RETURN QUERY EXECUTE format(
      'SELECT * FROM %I WHERE %I ILIKE %L',
      table_name,
      search_column,
      '%' || search_value || '%'
    );
  END;
  $$ LANGUAGE plpgsql;
`;
```

---

## Procedures (PostgreSQL 11+)

### Procedure vs Function

| Feature | Function | Procedure |
|---------|----------|-----------|
| Return value | Required | Optional (OUT params) |
| Transaction control | No | Yes (COMMIT/ROLLBACK) |
| Call syntax | SELECT | CALL |

### Creating Procedures

```typescript
await sql`
  CREATE OR REPLACE PROCEDURE process_pending_orders()
  AS $$
  DECLARE
    order_rec RECORD;
    processed INTEGER := 0;
  BEGIN
    FOR order_rec IN
      SELECT * FROM orders WHERE status = 'pending' FOR UPDATE SKIP LOCKED
    LOOP
      -- Process order
      UPDATE orders SET status = 'processing' WHERE id = order_rec.id;
      processed := processed + 1;

      -- Commit every 100 orders
      IF processed % 100 = 0 THEN
        COMMIT;
      END IF;
    END LOOP;

    COMMIT;
  END;
  $$ LANGUAGE plpgsql;
`;

// Call procedure
await sql`CALL process_pending_orders()`;
```

### With Parameters

```typescript
await sql`
  CREATE OR REPLACE PROCEDURE transfer_funds(
    from_id INTEGER,
    to_id INTEGER,
    amount NUMERIC,
    INOUT success BOOLEAN DEFAULT false
  )
  AS $$
  BEGIN
    UPDATE accounts SET balance = balance - amount WHERE id = from_id;
    UPDATE accounts SET balance = balance + amount WHERE id = to_id;
    success := true;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      success := false;
      ROLLBACK;
  END;
  $$ LANGUAGE plpgsql;
`;

const [result] = await sql`CALL transfer_funds(1, 2, 100.00, NULL)`;
```

---

## Best Practices

1. **Use STRICT SELECT INTO** when expecting exactly one row
2. **Always handle exceptions** in functions that modify data
3. **Use SECURITY DEFINER carefully** with SET search_path
4. **Prefer STABLE/IMMUTABLE** when function doesn't modify data
5. **Use RETURN QUERY** instead of loops when possible
6. **Quote identifiers** with quote_ident() or format(%I)
7. **Quote literals** with quote_literal() or format(%L)
8. **Keep functions focused** - single responsibility
9. **Use triggers sparingly** - they can make debugging harder
10. **Document with COMMENT** - explain what the function does
