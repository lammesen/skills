-- ============================================================================
-- Trigger Template: {TRIGGER_NAME}
-- Table: {TABLE_NAME}
-- Purpose: {PURPOSE}
-- Author: {AUTHOR}
-- Created: {DATE}
-- ============================================================================

-- ============================================================================
-- TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION {FUNCTION_NAME}()
RETURNS TRIGGER
AS $$
DECLARE
  -- Variable declarations
  -- v_user_id INTEGER;
  -- v_old_value TEXT;
BEGIN
  -- ========================================================================
  -- Available Special Variables:
  -- ========================================================================
  -- NEW        - New row data (INSERT, UPDATE)
  -- OLD        - Old row data (UPDATE, DELETE)
  -- TG_OP      - Operation: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
  -- TG_NAME    - Trigger name
  -- TG_TABLE_NAME - Table name
  -- TG_TABLE_SCHEMA - Schema name
  -- TG_WHEN    - 'BEFORE', 'AFTER', 'INSTEAD OF'
  -- TG_LEVEL   - 'ROW', 'STATEMENT'
  -- TG_ARGV    - Arguments passed to trigger (TG_ARGV[0], TG_ARGV[1], etc.)
  -- ========================================================================

  -- INSERT operation
  IF TG_OP = 'INSERT' THEN
    -- Example: Set created_at timestamp
    -- NEW.created_at := NOW();

    -- Example: Set default values
    -- NEW.status := COALESCE(NEW.status, 'pending');

    {INSERT_LOGIC}

    RETURN NEW;

  -- UPDATE operation
  ELSIF TG_OP = 'UPDATE' THEN
    -- Example: Set updated_at timestamp
    -- NEW.updated_at := NOW();

    -- Example: Prevent certain changes
    -- IF OLD.id != NEW.id THEN
    --   RAISE EXCEPTION 'Cannot change id';
    -- END IF;

    -- Example: Track changes
    -- IF OLD.status IS DISTINCT FROM NEW.status THEN
    --   INSERT INTO status_history (record_id, old_status, new_status)
    --   VALUES (NEW.id, OLD.status, NEW.status);
    -- END IF;

    {UPDATE_LOGIC}

    RETURN NEW;

  -- DELETE operation
  ELSIF TG_OP = 'DELETE' THEN
    -- Example: Soft delete instead
    -- UPDATE {TABLE_NAME} SET deleted_at = NOW() WHERE id = OLD.id;
    -- RETURN NULL;  -- Prevents actual delete

    -- Example: Archive deleted record
    -- INSERT INTO {TABLE_NAME}_archive SELECT OLD.*;

    {DELETE_LOGIC}

    RETURN OLD;

  END IF;

  -- Should never reach here
  RETURN NULL;

EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't block operation (optional)
    -- RAISE WARNING 'Trigger error: %', SQLERRM;
    -- RETURN COALESCE(NEW, OLD);

    -- Or re-raise to block the operation
    RAISE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGER DEFINITION
-- ============================================================================

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS {TRIGGER_NAME} ON {TABLE_NAME};

-- Create new trigger
CREATE TRIGGER {TRIGGER_NAME}
  {TIMING}                           -- BEFORE | AFTER | INSTEAD OF
  {EVENTS}                           -- INSERT | UPDATE | DELETE [OR ...]
  ON {TABLE_NAME}
  FOR EACH {LEVEL}                   -- ROW | STATEMENT
  -- WHEN (condition)                -- Optional: Only fire when condition is true
  EXECUTE FUNCTION {FUNCTION_NAME}();

-- ============================================================================
-- EXAMPLES
-- ============================================================================

-- Example 1: Auto-update timestamps
-- CREATE TRIGGER set_updated_at
--   BEFORE UPDATE ON users
--   FOR EACH ROW
--   EXECUTE FUNCTION update_timestamps();

-- Example 2: Audit log trigger
-- CREATE TRIGGER audit_orders
--   AFTER INSERT OR UPDATE OR DELETE ON orders
--   FOR EACH ROW
--   EXECUTE FUNCTION audit_trigger_func();

-- Example 3: Conditional trigger (only on status change)
-- CREATE TRIGGER on_status_change
--   AFTER UPDATE OF status ON orders
--   FOR EACH ROW
--   WHEN (OLD.status IS DISTINCT FROM NEW.status)
--   EXECUTE FUNCTION notify_status_change();

-- Example 4: Statement-level trigger (for bulk operations)
-- CREATE TRIGGER after_bulk_insert
--   AFTER INSERT ON imports
--   FOR EACH STATEMENT
--   EXECUTE FUNCTION process_import_batch();

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- List triggers on table
-- SELECT tgname, tgtype, tgenabled
-- FROM pg_trigger
-- WHERE tgrelid = '{TABLE_NAME}'::regclass;

-- Test trigger (in transaction for safety)
-- BEGIN;
-- INSERT INTO {TABLE_NAME} (...) VALUES (...);
-- SELECT * FROM {TABLE_NAME} WHERE ...;
-- ROLLBACK;

-- ============================================================================
-- CLEANUP (if needed)
-- ============================================================================

-- DROP TRIGGER IF EXISTS {TRIGGER_NAME} ON {TABLE_NAME};
-- DROP FUNCTION IF EXISTS {FUNCTION_NAME}();
