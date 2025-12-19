/**
 * PostgreSQL Database Test Template
 *
 * This template provides patterns for testing PostgreSQL operations using Bun.sql and bun:test.
 *
 * Usage:
 * 1. Copy this template to your test directory
 * 2. Update the imports and configuration
 * 3. Replace placeholder names with your actual entities
 * 4. Run with: bun test
 */

import {
  describe,
  test,
  expect,
  beforeAll,
  afterAll,
  beforeEach,
  afterEach,
} from "bun:test";
import { SQL } from "bun";

// ============================================================================
// Test Database Configuration
// ============================================================================

const TEST_DB_URL = process.env.TEST_DATABASE_URL || "postgres://localhost:5432/myapp_test";

const testDb = new SQL(TEST_DB_URL);

// ============================================================================
// Test Utilities
// ============================================================================

/**
 * Truncate tables and reset sequences
 */
async function truncateTables(...tables: string[]) {
  for (const table of tables) {
    await testDb`TRUNCATE ${testDb.identifier(table)} RESTART IDENTITY CASCADE`;
  }
}

/**
 * Create test data factory
 */
function createUserFactory(overrides: Partial<User> = {}): User {
  return {
    email: `user-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`,
    name: "Test User",
    role: "user",
    ...overrides,
  };
}

/**
 * Insert test user
 */
async function insertTestUser(data: Partial<User> = {}): Promise<User> {
  const user = createUserFactory(data);
  const [inserted] = await testDb`
    INSERT INTO users ${testDb(user)}
    RETURNING *
  `;
  return inserted;
}

// ============================================================================
// Type Definitions
// ============================================================================

interface User {
  id?: number;
  email: string;
  name: string;
  role: string;
  created_at?: Date;
  updated_at?: Date;
}

// ============================================================================
// Test Suite Setup
// ============================================================================

describe("Database Tests", () => {
  // Run once before all tests in this file
  beforeAll(async () => {
    // Verify database connection
    const [{ now }] = await testDb`SELECT NOW() as now`;
    console.log(`Connected to test database at ${now}`);

    // Create test schema if needed
    await testDb`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        name VARCHAR(255) NOT NULL,
        role VARCHAR(50) DEFAULT 'user',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `;

    // Create indexes if needed
    await testDb`
      CREATE INDEX IF NOT EXISTS users_email_idx ON users (email)
    `;
  });

  // Run once after all tests in this file
  afterAll(async () => {
    // Clean up test data
    await testDb`TRUNCATE users RESTART IDENTITY CASCADE`;

    // Close connection
    await testDb.close();
  });

  // Run before each test
  beforeEach(async () => {
    // Reset tables to clean state
    await truncateTables("users");
  });

  // Run after each test
  afterEach(async () => {
    // Optional: Log test completion, clean up temp data
  });

  // ==========================================================================
  // CRUD Operation Tests
  // ==========================================================================

  describe("User CRUD Operations", () => {
    test("creates a user", async () => {
      const userData = createUserFactory({
        email: "test@example.com",
        name: "Test User",
      });

      const [user] = await testDb`
        INSERT INTO users ${testDb(userData)}
        RETURNING *
      `;

      expect(user.id).toBeDefined();
      expect(user.email).toBe("test@example.com");
      expect(user.name).toBe("Test User");
      expect(user.created_at).toBeInstanceOf(Date);
    });

    test("reads a user by id", async () => {
      const created = await insertTestUser({ email: "read@example.com" });

      const [found] = await testDb`
        SELECT * FROM users WHERE id = ${created.id}
      `;

      expect(found).toBeDefined();
      expect(found.email).toBe("read@example.com");
    });

    test("updates a user", async () => {
      const user = await insertTestUser();

      const [updated] = await testDb`
        UPDATE users
        SET name = 'Updated Name', updated_at = NOW()
        WHERE id = ${user.id}
        RETURNING *
      `;

      expect(updated.name).toBe("Updated Name");
      expect(updated.updated_at.getTime()).toBeGreaterThan(user.created_at!.getTime());
    });

    test("deletes a user", async () => {
      const user = await insertTestUser();

      await testDb`DELETE FROM users WHERE id = ${user.id}`;

      const [found] = await testDb`SELECT * FROM users WHERE id = ${user.id}`;
      expect(found).toBeUndefined();
    });
  });

  // ==========================================================================
  // Constraint Tests
  // ==========================================================================

  describe("Constraints", () => {
    test("enforces unique email constraint", async () => {
      await insertTestUser({ email: "unique@example.com" });

      expect(async () => {
        await insertTestUser({ email: "unique@example.com" });
      }).toThrow();
    });

    test("enforces NOT NULL constraints", async () => {
      expect(async () => {
        await testDb`INSERT INTO users (email) VALUES ('missing-name@example.com')`;
      }).toThrow();
    });
  });

  // ==========================================================================
  // Transaction Tests
  // ==========================================================================

  describe("Transactions", () => {
    test("commits successful transaction", async () => {
      await testDb.begin(async (tx) => {
        await tx`INSERT INTO users ${tx({ email: "tx1@example.com", name: "TX User 1", role: "user" })}`;
        await tx`INSERT INTO users ${tx({ email: "tx2@example.com", name: "TX User 2", role: "user" })}`;
      });

      const [{ count }] = await testDb`SELECT COUNT(*) FROM users`;
      expect(Number(count)).toBe(2);
    });

    test("rolls back failed transaction", async () => {
      try {
        await testDb.begin(async (tx) => {
          await tx`INSERT INTO users ${tx({ email: "rollback@example.com", name: "Rollback User", role: "user" })}`;
          throw new Error("Intentional rollback");
        });
      } catch {
        // Expected
      }

      const [{ count }] = await testDb`SELECT COUNT(*) FROM users`;
      expect(Number(count)).toBe(0);
    });

    test("supports savepoints", async () => {
      await testDb.begin(async (tx) => {
        await tx`INSERT INTO users ${tx({ email: "outer@example.com", name: "Outer User", role: "user" })}`;

        try {
          await tx.savepoint(async (sp) => {
            await sp`INSERT INTO users ${sp({ email: "inner@example.com", name: "Inner User", role: "user" })}`;
            throw new Error("Rollback savepoint");
          });
        } catch {
          // Savepoint rolled back
        }

        // Outer transaction continues
        await tx`INSERT INTO users ${tx({ email: "after@example.com", name: "After User", role: "user" })}`;
      });

      const [{ count }] = await testDb`SELECT COUNT(*) FROM users`;
      expect(Number(count)).toBe(2); // outer + after, not inner
    });
  });

  // ==========================================================================
  // Query Tests
  // ==========================================================================

  describe("Complex Queries", () => {
    beforeEach(async () => {
      // Seed test data
      await testDb`
        INSERT INTO users (email, name, role) VALUES
          ('admin@example.com', 'Admin User', 'admin'),
          ('user1@example.com', 'User One', 'user'),
          ('user2@example.com', 'User Two', 'user'),
          ('mod@example.com', 'Moderator', 'moderator')
      `;
    });

    test("filters by role", async () => {
      const users = await testDb`
        SELECT * FROM users WHERE role = ${"user"}
      `;

      expect(users.length).toBe(2);
      expect(users.every(u => u.role === "user")).toBe(true);
    });

    test("orders by column", async () => {
      const users = await testDb`
        SELECT * FROM users ORDER BY name ASC
      `;

      expect(users[0].name).toBe("Admin User");
      expect(users[3].name).toBe("User Two");
    });

    test("uses LIMIT and OFFSET", async () => {
      const page1 = await testDb`SELECT * FROM users ORDER BY id LIMIT 2 OFFSET 0`;
      const page2 = await testDb`SELECT * FROM users ORDER BY id LIMIT 2 OFFSET 2`;

      expect(page1.length).toBe(2);
      expect(page2.length).toBe(2);
      expect(page1[0].id).not.toBe(page2[0].id);
    });

    test("uses IN clause", async () => {
      const roles = ["admin", "moderator"];
      const users = await testDb`
        SELECT * FROM users WHERE role IN ${testDb(roles)}
      `;

      expect(users.length).toBe(2);
    });

    test("uses aggregate functions", async () => {
      const [stats] = await testDb`
        SELECT
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE role = 'user') as user_count
        FROM users
      `;

      expect(Number(stats.total)).toBe(4);
      expect(Number(stats.user_count)).toBe(2);
    });
  });

  // ==========================================================================
  // Error Handling Tests
  // ==========================================================================

  describe("Error Handling", () => {
    test("handles PostgreSQL errors", async () => {
      try {
        await testDb`SELECT * FROM nonexistent_table`;
        expect(true).toBe(false); // Should not reach here
      } catch (error) {
        expect(error).toBeDefined();
        // Check error properties if using SQL.PostgresError
      }
    });

    test("provides error details for constraint violations", async () => {
      await insertTestUser({ email: "duplicate@example.com" });

      try {
        await insertTestUser({ email: "duplicate@example.com" });
      } catch (error: any) {
        expect(error.code).toBe("23505"); // unique_violation
      }
    });
  });

  // ==========================================================================
  // Performance Tests (Optional)
  // ==========================================================================

  describe("Performance", () => {
    test.skip("bulk insert performance", async () => {
      const users = Array.from({ length: 1000 }, (_, i) => ({
        email: `bulk${i}@example.com`,
        name: `Bulk User ${i}`,
        role: "user",
      }));

      const start = performance.now();
      await testDb`INSERT INTO users ${testDb(users)}`;
      const duration = performance.now() - start;

      console.log(`Bulk insert of 1000 rows took ${duration.toFixed(2)}ms`);
      expect(duration).toBeLessThan(5000); // Should complete in under 5 seconds
    });
  });
});
