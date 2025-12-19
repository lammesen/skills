# Security Patterns Reference

Complete guide to PostgreSQL security including Row-Level Security (RLS), roles, and permissions with Bun.sql.

## Row-Level Security (RLS)

### Enabling RLS

```typescript
// Enable RLS on table
await sql`ALTER TABLE documents ENABLE ROW LEVEL SECURITY`;

// Force RLS for table owner too (optional)
await sql`ALTER TABLE documents FORCE ROW LEVEL SECURITY`;

// Check RLS status
const rlsStatus = await sql`
  SELECT relname, relrowsecurity, relforcerowsecurity
  FROM pg_class
  WHERE relname = 'documents'
`;
```

### Policy Basics

```sql
CREATE POLICY policy_name ON table_name
  [AS { PERMISSIVE | RESTRICTIVE }]
  [FOR { ALL | SELECT | INSERT | UPDATE | DELETE }]
  [TO { role_name | PUBLIC | CURRENT_USER }]
  USING (expression)           -- For reading (SELECT, UPDATE, DELETE)
  [WITH CHECK (expression)];   -- For writing (INSERT, UPDATE)
```

### Owner-Based Policy

```typescript
await sql`
  CREATE POLICY owner_policy ON documents
    FOR ALL
    USING (owner_id = current_setting('app.current_user_id')::INTEGER)
    WITH CHECK (owner_id = current_setting('app.current_user_id')::INTEGER)
`;

// Set user context before queries
await sql`SET app.current_user_id = ${userId}`;
const docs = await sql`SELECT * FROM documents`; // Only sees owned docs
```

### Multi-Tenant Isolation

```typescript
// Create tenant isolation policy
await sql`
  CREATE POLICY tenant_isolation ON data
    FOR ALL
    USING (tenant_id = current_setting('app.tenant_id')::UUID)
    WITH CHECK (tenant_id = current_setting('app.tenant_id')::UUID)
`;

// Set tenant context
await sql`SET app.tenant_id = ${tenantId}`;
```

### Role-Based Policies

```typescript
// Policy for specific role
await sql`
  CREATE POLICY admin_all_access ON documents
    FOR ALL
    TO admin_role
    USING (true)
`;

// Policy for authenticated users
await sql`
  CREATE POLICY user_read_public ON documents
    FOR SELECT
    TO authenticated
    USING (is_public = true OR owner_id = current_setting('app.current_user_id')::INTEGER)
`;
```

### Permissive vs Restrictive

```typescript
// PERMISSIVE (default): ORed together - any matching policy grants access
await sql`
  CREATE POLICY read_own ON documents
    AS PERMISSIVE
    FOR SELECT
    USING (owner_id = current_setting('app.user_id')::INTEGER)
`;

await sql`
  CREATE POLICY read_public ON documents
    AS PERMISSIVE
    FOR SELECT
    USING (is_public = true)
`;
-- User can read if they own it OR it's public

// RESTRICTIVE: ANDed with permissive - all must pass
await sql`
  CREATE POLICY not_deleted ON documents
    AS RESTRICTIVE
    FOR SELECT
    USING (deleted_at IS NULL)
`;
-- User can read if (own OR public) AND not_deleted
```

### Operation-Specific Policies

```typescript
// SELECT only
await sql`
  CREATE POLICY read_policy ON documents
    FOR SELECT
    USING (owner_id = current_setting('app.user_id')::INTEGER OR is_public)
`;

// INSERT with validation
await sql`
  CREATE POLICY insert_policy ON documents
    FOR INSERT
    WITH CHECK (owner_id = current_setting('app.user_id')::INTEGER)
`;

// UPDATE own documents only
await sql`
  CREATE POLICY update_policy ON documents
    FOR UPDATE
    USING (owner_id = current_setting('app.user_id')::INTEGER)
    WITH CHECK (owner_id = current_setting('app.user_id')::INTEGER)
`;

// DELETE own documents only
await sql`
  CREATE POLICY delete_policy ON documents
    FOR DELETE
    USING (owner_id = current_setting('app.user_id')::INTEGER)
`;
```

### Managing Policies

```typescript
// List policies
const policies = await sql`
  SELECT polname, polpermissive, polroles::regrole[], polcmd, polqual, polwithcheck
  FROM pg_policy
  WHERE polrelid = 'documents'::regclass
`;

// Drop policy
await sql`DROP POLICY IF EXISTS policy_name ON documents`;

// Disable RLS
await sql`ALTER TABLE documents DISABLE ROW LEVEL SECURITY`;
```

---

## Setting User Context

### Using SET

```typescript
// Session-level (persists until connection closes)
await sql`SET app.current_user_id = ${userId}`;

// Transaction-level (resets after transaction)
await sql.begin(async (tx) => {
  await tx`SET LOCAL app.current_user_id = ${userId}`;
  // Queries here use userId context
});
// Context reset after transaction
```

### Using Function

```typescript
await sql`
  CREATE OR REPLACE FUNCTION set_user_context(user_id INTEGER)
  RETURNS VOID AS $$
  BEGIN
    PERFORM set_config('app.current_user_id', user_id::TEXT, false);
  END;
  $$ LANGUAGE plpgsql;
`;

// Use in application
await sql`SELECT set_user_context(${userId})`;
```

### Reading Context

```typescript
const [{ user_id }] = await sql`
  SELECT current_setting('app.current_user_id', true) AS user_id
`;
```

### Middleware Pattern

```typescript
// Wrapper for authenticated queries
async function authenticatedQuery<T>(
  userId: number,
  query: (sql: typeof import("bun").sql) => Promise<T>
): Promise<T> {
  return sql.begin(async (tx) => {
    await tx`SET LOCAL app.current_user_id = ${userId}`;
    return query(tx);
  });
}

// Usage
const docs = await authenticatedQuery(userId, (tx) =>
  tx`SELECT * FROM documents`
);
```

---

## Roles and Privileges

### Creating Roles

```typescript
// Basic role
await sql`CREATE ROLE app_user`;

// Role with login capability (user)
await sql`CREATE ROLE app_admin LOGIN PASSWORD 'secure_password'`;

// Role that inherits from another
await sql`CREATE ROLE manager INHERIT`;
await sql`GRANT app_user TO manager`;
```

### Role Hierarchy Example

```typescript
// Base roles (no login)
await sql`CREATE ROLE readonly`;
await sql`CREATE ROLE readwrite`;
await sql`CREATE ROLE admin`;

// Grant inheritance
await sql`GRANT readonly TO readwrite`;
await sql`GRANT readwrite TO admin`;

// Login roles
await sql`CREATE ROLE app_reader LOGIN PASSWORD 'xxx'`;
await sql`CREATE ROLE app_writer LOGIN PASSWORD 'yyy'`;
await sql`CREATE ROLE app_admin LOGIN PASSWORD 'zzz'`;

// Assign roles
await sql`GRANT readonly TO app_reader`;
await sql`GRANT readwrite TO app_writer`;
await sql`GRANT admin TO app_admin`;
```

### Table Privileges

```typescript
// Grant SELECT
await sql`GRANT SELECT ON documents TO readonly`;

// Grant all DML
await sql`GRANT SELECT, INSERT, UPDATE, DELETE ON documents TO readwrite`;

// Grant all (including DDL)
await sql`GRANT ALL ON documents TO admin`;

// Grant on all tables
await sql`GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly`;

// Default privileges for future tables
await sql`
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO readonly
`;
```

### Column-Level Privileges

```typescript
// Grant access to specific columns only
await sql`GRANT SELECT (id, name, email) ON users TO support_role`;
await sql`GRANT UPDATE (phone, address) ON users TO support_role`;
```

### Sequence Privileges

```typescript
// Required for INSERT with serial columns
await sql`GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO readwrite`;

// Default for future sequences
await sql`
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO readwrite
`;
```

### Revoking Privileges

```typescript
await sql`REVOKE INSERT ON documents FROM readonly`;
await sql`REVOKE ALL ON documents FROM PUBLIC`;
```

---

## Application Security Patterns

### Connection Pooling with RLS

```typescript
// Application connects with limited role
const db = new SQL({
  hostname: "localhost",
  database: "myapp",
  username: "app_user",  // Limited privileges
  password: process.env.DB_PASSWORD,
});

// Set context per request
async function handleRequest(userId: number) {
  return db.begin(async (tx) => {
    await tx`SET LOCAL app.current_user_id = ${userId}`;
    return tx`SELECT * FROM sensitive_data`;
  });
}
```

### Security Definer Functions

```typescript
// Function runs with creator's permissions
await sql`
  CREATE OR REPLACE FUNCTION get_user_profile(target_user_id INTEGER)
  RETURNS TABLE(name TEXT, email TEXT)
  SECURITY DEFINER
  SET search_path = public
  AS $$
  BEGIN
    -- Additional authorization check
    IF target_user_id != current_setting('app.current_user_id')::INTEGER
       AND NOT current_setting('app.is_admin', true)::BOOLEAN THEN
      RAISE EXCEPTION 'Access denied';
    END IF;

    RETURN QUERY
    SELECT users.name, users.email
    FROM users
    WHERE users.id = target_user_id;
  END;
  $$ LANGUAGE plpgsql;
`;
```

### Audit Logging

```typescript
await sql`
  CREATE TABLE audit_log (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    user_id INTEGER,
    old_data JSONB,
    new_data JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
  )
`;

await sql`
  CREATE OR REPLACE FUNCTION audit_trigger()
  RETURNS TRIGGER AS $$
  BEGIN
    INSERT INTO audit_log (
      table_name,
      operation,
      user_id,
      old_data,
      new_data,
      ip_address
    ) VALUES (
      TG_TABLE_NAME,
      TG_OP,
      current_setting('app.current_user_id', true)::INTEGER,
      CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) END,
      CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) END,
      current_setting('app.client_ip', true)::INET
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD;
    ELSE RETURN NEW;
    END IF;
  END;
  $$ LANGUAGE plpgsql;
`;

await sql`
  CREATE TRIGGER audit_sensitive_data
    AFTER INSERT OR UPDATE OR DELETE ON sensitive_data
    FOR EACH ROW
    EXECUTE FUNCTION audit_trigger()
`;
```

---

## SQL Injection Prevention

### Parameterized Queries (Bun.sql)

```typescript
// SAFE: Parameterized query
await sql`SELECT * FROM users WHERE email = ${email}`;

// SAFE: Object insertion
await sql`INSERT INTO users ${sql({ name, email })}`;

// SAFE: Array values
await sql`SELECT * FROM users WHERE id IN ${sql([1, 2, 3])}`;
```

### Dynamic Identifiers

```typescript
// UNSAFE: String concatenation
await sql`SELECT * FROM ${tableName}`;  // DON'T DO THIS

// SAFE: Whitelist approach
const allowedTables = ['users', 'orders', 'products'];
if (!allowedTables.includes(tableName)) {
  throw new Error('Invalid table name');
}
await sql`SELECT * FROM ${sql.identifier(tableName)}`;

// Alternative: Use dedicated functions
await sql`
  CREATE FUNCTION get_table_data(table_name TEXT)
  RETURNS SETOF RECORD
  AS $$
  BEGIN
    -- Validate table name
    IF table_name NOT IN ('users', 'orders', 'products') THEN
      RAISE EXCEPTION 'Invalid table';
    END IF;

    RETURN QUERY EXECUTE format('SELECT * FROM %I', table_name);
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER;
`;
```

---

## Encryption

### Column Encryption with pgcrypto

```typescript
await sql`CREATE EXTENSION IF NOT EXISTS pgcrypto`;

// Encrypt data
await sql`
  INSERT INTO users (email, ssn_encrypted)
  VALUES (
    ${email},
    pgp_sym_encrypt(${ssn}, ${encryptionKey})
  )
`;

// Decrypt data
const [user] = await sql`
  SELECT
    email,
    pgp_sym_decrypt(ssn_encrypted, ${encryptionKey}) AS ssn
  FROM users
  WHERE id = ${userId}
`;
```

### Password Hashing

```typescript
// Hash password
await sql`
  INSERT INTO users (email, password_hash)
  VALUES (
    ${email},
    crypt(${password}, gen_salt('bf', 10))
  )
`;

// Verify password
const [{ valid }] = await sql`
  SELECT password_hash = crypt(${password}, password_hash) AS valid
  FROM users
  WHERE email = ${email}
`;
```

---

## Connection Security

### SSL/TLS Configuration

```typescript
const db = new SQL({
  hostname: "localhost",
  database: "myapp",
  tls: true,  // Enable TLS
  // Or with options:
  tls: {
    rejectUnauthorized: true,
    ca: await Bun.file("ca-certificate.pem").text(),
  },
});
```

### Limiting Connection Permissions

```sql
-- Limit connections to specific database
ALTER ROLE app_user CONNECTION LIMIT 100;

-- Restrict by IP in pg_hba.conf
# TYPE  DATABASE    USER        ADDRESS         METHOD
hostssl myapp       app_user    10.0.0.0/8      scram-sha-256
```

---

## Best Practices Checklist

### Role Security
- [ ] Use least-privilege principle
- [ ] Create separate roles for different access levels
- [ ] Never use superuser for application connections
- [ ] Regularly audit role memberships

### RLS Security
- [ ] Enable RLS on sensitive tables
- [ ] Use restrictive policies for additional constraints
- [ ] Test policies with different user contexts
- [ ] Consider FORCE ROW LEVEL SECURITY for owner tables

### Data Security
- [ ] Encrypt sensitive data at rest
- [ ] Use TLS for all connections
- [ ] Hash passwords with bcrypt/scrypt
- [ ] Implement audit logging for sensitive operations

### Query Security
- [ ] Always use parameterized queries
- [ ] Whitelist dynamic identifiers
- [ ] Validate user input
- [ ] Use SECURITY DEFINER functions carefully

### Monitoring
- [ ] Log authentication attempts
- [ ] Monitor for privilege escalation
- [ ] Set up alerts for suspicious activity
- [ ] Regular security audits
