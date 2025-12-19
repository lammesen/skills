-- Migration: {MIGRATION_NAME}
-- Version: {VERSION}
-- Created: {DATE}
-- Author: {AUTHOR}
-- Description: {DESCRIPTION}

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

BEGIN;

-- Pre-migration checks (optional)
DO $$
BEGIN
  -- Example: Check if prerequisite migration was applied
  -- IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = 'XXX') THEN
  --   RAISE EXCEPTION 'Prerequisite migration XXX not applied';
  -- END IF;
END $$;

-- Schema changes
-- Example: CREATE TABLE, ALTER TABLE, CREATE INDEX, etc.

{UP_SQL}

-- Record migration
INSERT INTO schema_migrations (version, description, applied_at)
VALUES ('{VERSION}', '{DESCRIPTION}', NOW())
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- ============================================================================
-- DOWN MIGRATION (for rollback)
-- ============================================================================

-- To rollback, execute the following in a separate transaction:
--
-- BEGIN;
--
-- {DOWN_SQL}
--
-- DELETE FROM schema_migrations WHERE version = '{VERSION}';
--
-- COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES (run after migration)
-- ============================================================================

-- SELECT * FROM schema_migrations WHERE version = '{VERSION}';
-- \d+ {TABLE_NAME}
-- SELECT COUNT(*) FROM {TABLE_NAME};

-- ============================================================================
-- NOTES
-- ============================================================================
--
-- - Always test migrations on a non-production database first
-- - For large tables, consider using CREATE INDEX CONCURRENTLY
-- - Remember to update application code if schema changes
-- - Consider data migration scripts if needed
--
