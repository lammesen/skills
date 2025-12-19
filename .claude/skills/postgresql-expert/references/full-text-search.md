# Full-Text Search Reference

Complete guide to PostgreSQL full-text search with Bun.sql.

## Core Concepts

### tsvector - Document Representation

A `tsvector` is a sorted list of distinct lexemes (normalized words) with their positions.

```typescript
await sql`SELECT to_tsvector('english', 'The quick brown foxes jumped')`;
-- Result: 'brown':3 'fox':4 'jump':5 'quick':2
```

### tsquery - Search Query

A `tsquery` contains lexemes with optional operators for matching.

```typescript
await sql`SELECT to_tsquery('english', 'quick & brown')`;
-- Result: 'quick' & 'brown'
```

---

## Creating Search Vectors

### to_tsvector

```typescript
// Basic conversion
await sql`SELECT to_tsvector('english', ${text})`;

// With default config
await sql`SELECT to_tsvector(${text})`; // Uses default_text_search_config

// Multiple columns
await sql`
  SELECT to_tsvector('english', title || ' ' || body)
  FROM articles
`;

// With COALESCE for NULL handling
await sql`
  SELECT to_tsvector('english',
    COALESCE(title, '') || ' ' ||
    COALESCE(description, '') || ' ' ||
    COALESCE(body, '')
  )
  FROM articles
`;
```

### Weighted Vectors

Weight classes: A (most important) > B > C > D (least important)

```typescript
await sql`
  SELECT
    setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(subtitle, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(abstract, '')), 'C') ||
    setweight(to_tsvector('english', COALESCE(body, '')), 'D')
  FROM articles
`;
```

### Stored Search Vector Column

```typescript
// Add column
await sql`ALTER TABLE articles ADD COLUMN search_vector tsvector`;

// Populate
await sql`
  UPDATE articles SET search_vector =
    setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(body, '')), 'D')
`;

// Create GIN index
await sql`CREATE INDEX articles_search_idx ON articles USING GIN (search_vector)`;
```

---

## Creating Search Queries

### to_tsquery

Requires properly formatted input with operators:

```typescript
await sql`SELECT to_tsquery('english', 'cat & dog')`;      // AND
await sql`SELECT to_tsquery('english', 'cat | dog')`;      // OR
await sql`SELECT to_tsquery('english', '!cat')`;           // NOT
await sql`SELECT to_tsquery('english', 'cat <-> dog')`;    // FOLLOWED BY
await sql`SELECT to_tsquery('english', 'cat <2> dog')`;    // Within 2 words
```

### plainto_tsquery

Converts plain text, words connected with AND:

```typescript
await sql`SELECT plainto_tsquery('english', 'quick brown fox')`;
-- Result: 'quick' & 'brown' & 'fox'
```

### phraseto_tsquery

Creates phrase query (words must be adjacent):

```typescript
await sql`SELECT phraseto_tsquery('english', 'quick brown fox')`;
-- Result: 'quick' <-> 'brown' <-> 'fox'
```

### websearch_to_tsquery (PostgreSQL 11+)

Most user-friendly, supports common search syntax:

```typescript
// Basic search
await sql`SELECT websearch_to_tsquery('english', 'quick brown fox')`;
-- Result: 'quick' & 'brown' & 'fox'

// OR operator
await sql`SELECT websearch_to_tsquery('english', 'cat or dog')`;
-- Result: 'cat' | 'dog'

// Negation
await sql`SELECT websearch_to_tsquery('english', 'cat -dog')`;
-- Result: 'cat' & !'dog'

// Phrase (quoted)
await sql`SELECT websearch_to_tsquery('english', '"quick brown fox"')`;
-- Result: 'quick' <-> 'brown' <-> 'fox'
```

### Query with Prefix Matching

```typescript
await sql`SELECT to_tsquery('english', 'prog:*')`;
-- Matches: program, programming, programmer, etc.

// With websearch
await sql`SELECT websearch_to_tsquery('english', 'prog*')`;
```

---

## Matching Operators

### @@ Match Operator

```typescript
// Vector @@ query
await sql`
  SELECT * FROM articles
  WHERE to_tsvector('english', body) @@ to_tsquery('english', 'database & performance')
`;

// With stored vector
await sql`
  SELECT * FROM articles
  WHERE search_vector @@ websearch_to_tsquery('english', ${searchQuery})
`;

// Query @@ vector (order doesn't matter)
await sql`
  SELECT * FROM articles
  WHERE to_tsquery('english', 'postgresql') @@ search_vector
`;
```

---

## Ranking Results

### ts_rank

Basic ranking based on frequency:

```typescript
const results = await sql`
  SELECT
    id,
    title,
    ts_rank(search_vector, query) AS rank
  FROM articles,
    websearch_to_tsquery('english', ${searchTerms}) AS query
  WHERE search_vector @@ query
  ORDER BY rank DESC
  LIMIT ${limit}
`;
```

### ts_rank with Normalization

```typescript
// Normalization options:
// 0: default (no normalization)
// 1: divide by 1 + log(document length)
// 2: divide by document length
// 4: divide by mean harmonic distance between extents
// 8: divide by number of unique words
// 16: divide by 1 + log(unique words)
// 32: divide by itself + 1

await sql`
  SELECT
    id,
    title,
    ts_rank(search_vector, query, 1) AS rank  -- Normalize by doc length
  FROM articles,
    to_tsquery('english', ${terms}) AS query
  WHERE search_vector @@ query
  ORDER BY rank DESC
`;
```

### ts_rank with Weights

```typescript
// Custom weights for A, B, C, D categories
await sql`
  SELECT
    id,
    title,
    ts_rank('{0.1, 0.2, 0.4, 1.0}', search_vector, query) AS rank
  FROM articles,
    to_tsquery('english', ${terms}) AS query
  WHERE search_vector @@ query
  ORDER BY rank DESC
`;
```

### ts_rank_cd (Cover Density Ranking)

Considers proximity of matching terms:

```typescript
await sql`
  SELECT
    id,
    title,
    ts_rank_cd(search_vector, query) AS rank
  FROM articles,
    to_tsquery('english', ${terms}) AS query
  WHERE search_vector @@ query
  ORDER BY rank DESC
`;
```

---

## Highlighting Results

### ts_headline

```typescript
const results = await sql`
  SELECT
    id,
    ts_headline(
      'english',
      body,
      query,
      'StartSel=<mark>, StopSel=</mark>, MaxWords=35, MinWords=15'
    ) AS snippet
  FROM articles,
    websearch_to_tsquery('english', ${searchTerms}) AS query
  WHERE search_vector @@ query
`;
```

### ts_headline Options

| Option | Description | Default |
|--------|-------------|---------|
| `StartSel` | String before match | `<b>` |
| `StopSel` | String after match | `</b>` |
| `MaxWords` | Max words in headline | 35 |
| `MinWords` | Min words in headline | 15 |
| `ShortWord` | Min word length to show | 3 |
| `HighlightAll` | Highlight all occurrences | false |
| `MaxFragments` | Max fragments to show | 0 (all) |
| `FragmentDelimiter` | Between fragments | ` ... ` |

```typescript
await sql`
  SELECT ts_headline(
    'english',
    body,
    query,
    'StartSel=<em class="highlight">, StopSel=</em>, MaxFragments=3, FragmentDelimiter= ... '
  ) AS snippet
  FROM articles,
    to_tsquery('english', ${terms}) AS query
  WHERE search_vector @@ query
`;
```

---

## Text Search Configuration

### Available Configurations

```typescript
const configs = await sql`SELECT cfgname FROM pg_ts_config`;
// simple, danish, dutch, english, finnish, french, german, hungarian,
// italian, norwegian, portuguese, romanian, russian, spanish, swedish, turkish
```

### Setting Default Configuration

```typescript
// Session level
await sql`SET default_text_search_config = 'english'`;

// Database level
await sql`ALTER DATABASE mydb SET default_text_search_config = 'english'`;
```

### Using Multiple Languages

```typescript
// Store language with content
await sql`
  CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    title TEXT,
    body TEXT,
    language REGCONFIG DEFAULT 'english',
    search_vector TSVECTOR
  )
`;

// Update vector using stored language
await sql`
  UPDATE articles
  SET search_vector = to_tsvector(language, COALESCE(title, '') || ' ' || COALESCE(body, ''))
`;

// Search with matching language
await sql`
  SELECT * FROM articles
  WHERE search_vector @@ to_tsquery(language, ${terms})
    AND language = ${lang}::regconfig
`;
```

---

## Indexing

### GIN Index

Best for most full-text search use cases:

```typescript
// On stored vector column
await sql`CREATE INDEX articles_search_idx ON articles USING GIN (search_vector)`;

// On expression
await sql`
  CREATE INDEX articles_search_idx
  ON articles
  USING GIN (to_tsvector('english', title || ' ' || body))
`;
```

### GiST Index

Alternative with different trade-offs:
- Lossy (requires recheck)
- Better for nearest-neighbor searches
- Faster to build

```typescript
await sql`CREATE INDEX articles_search_gist_idx ON articles USING GIST (search_vector)`;
```

### Partial Index

```typescript
await sql`
  CREATE INDEX published_articles_search_idx
  ON articles
  USING GIN (search_vector)
  WHERE status = 'published'
`;
```

### Concurrent Index Creation

```typescript
await sql`CREATE INDEX CONCURRENTLY articles_search_idx ON articles USING GIN (search_vector)`;
```

---

## Trigger for Auto-Update

### Complete Trigger Setup

```typescript
// Create function
await sql`
  CREATE OR REPLACE FUNCTION articles_search_vector_update()
  RETURNS trigger AS $$
  BEGIN
    NEW.search_vector :=
      setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
      setweight(to_tsvector('english', COALESCE(NEW.subtitle, '')), 'B') ||
      setweight(to_tsvector('english', COALESCE(NEW.body, '')), 'D');
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
`;

// Create trigger
await sql`
  CREATE TRIGGER articles_search_vector_trigger
    BEFORE INSERT OR UPDATE OF title, subtitle, body
    ON articles
    FOR EACH ROW
    EXECUTE FUNCTION articles_search_vector_update()
`;
```

### Multi-Language Trigger

```typescript
await sql`
  CREATE OR REPLACE FUNCTION articles_search_vector_update()
  RETURNS trigger AS $$
  BEGIN
    NEW.search_vector :=
      setweight(to_tsvector(NEW.language, COALESCE(NEW.title, '')), 'A') ||
      setweight(to_tsvector(NEW.language, COALESCE(NEW.body, '')), 'D');
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
`;
```

---

## Advanced Patterns

### Combined Full-Text and LIKE Search

```typescript
// Full-text for relevance, LIKE for partial matches
const results = await sql`
  WITH fts_results AS (
    SELECT id, title, ts_rank(search_vector, query) AS rank
    FROM articles,
      websearch_to_tsquery('english', ${searchTerms}) AS query
    WHERE search_vector @@ query
  ),
  like_results AS (
    SELECT id, title, 0.5 AS rank
    FROM articles
    WHERE title ILIKE ${`%${searchTerms}%`}
      AND id NOT IN (SELECT id FROM fts_results)
  )
  SELECT * FROM fts_results
  UNION ALL
  SELECT * FROM like_results
  ORDER BY rank DESC
  LIMIT ${limit}
`;
```

### Synonyms with Thesaurus

```typescript
// Configure thesaurus in postgresql.conf
// thesaurus_file = 'thesaurus_sample'

await sql`
  ALTER TEXT SEARCH CONFIGURATION english
  ALTER MAPPING FOR asciiword WITH thesaurus_sample, english_stem
`;
```

### Search with Facets

```typescript
const results = await sql`
  WITH search_results AS (
    SELECT
      id,
      category,
      author_id,
      ts_rank(search_vector, query) AS rank
    FROM articles,
      websearch_to_tsquery('english', ${searchTerms}) AS query
    WHERE search_vector @@ query
  )
  SELECT
    json_build_object(
      'results', (
        SELECT json_agg(row_to_json(r))
        FROM (
          SELECT * FROM search_results
          ORDER BY rank DESC
          LIMIT ${limit}
        ) r
      ),
      'facets', json_build_object(
        'categories', (
          SELECT json_agg(json_build_object('name', category, 'count', cnt))
          FROM (
            SELECT category, COUNT(*) as cnt
            FROM search_results
            GROUP BY category
            ORDER BY cnt DESC
          ) c
        ),
        'total', (SELECT COUNT(*) FROM search_results)
      )
    ) AS response
`;
```

### Autocomplete / Search Suggestions

```typescript
// Using trigram similarity for typo tolerance
await sql`CREATE EXTENSION IF NOT EXISTS pg_trgm`;

await sql`CREATE INDEX articles_title_trgm_idx ON articles USING GIN (title gin_trgm_ops)`;

const suggestions = await sql`
  SELECT DISTINCT title
  FROM articles
  WHERE title % ${input}
    OR title ILIKE ${`${input}%`}
  ORDER BY
    similarity(title, ${input}) DESC,
    title
  LIMIT 10
`;
```

### Boosting Recent Content

```typescript
await sql`
  SELECT
    id,
    title,
    ts_rank(search_vector, query) *
    (1 + 1.0 / (EXTRACT(EPOCH FROM NOW() - created_at) / 86400 + 1)) AS rank
  FROM articles,
    to_tsquery('english', ${terms}) AS query
  WHERE search_vector @@ query
  ORDER BY rank DESC
`;
```

---

## Debugging Full-Text Search

### Inspect tsvector

```typescript
await sql`SELECT to_tsvector('english', ${text})`;
```

### Inspect tsquery

```typescript
await sql`SELECT websearch_to_tsquery('english', ${query})`;
```

### Debug Matching

```typescript
await sql`
  SELECT
    to_tsvector('english', ${text}) @@ websearch_to_tsquery('english', ${query}) AS matches,
    to_tsvector('english', ${text}) AS vector,
    websearch_to_tsquery('english', ${query}) AS query
`;
```

### View Lexemes

```typescript
await sql`
  SELECT * FROM ts_debug('english', ${text})
`;
-- Returns: alias, description, token, dictionaries, dictionary, lexemes
```

### Check Configuration

```typescript
await sql`
  SELECT * FROM ts_token_type('default')
`;

await sql`
  SELECT * FROM pg_ts_config_map
  WHERE mapcfg = 'english'::regconfig
`;
```

---

## Performance Tips

1. **Always use stored tsvector column** with GIN index
2. **Update search vectors via triggers** to keep in sync
3. **Use websearch_to_tsquery** for user input
4. **Limit result sets** before ranking (expensive operation)
5. **Consider partial indexes** for common filters
6. **Pre-filter with cheaper conditions** when possible
7. **Use ts_headline sparingly** (expensive to compute)

```typescript
// Good: filter first, then rank
await sql`
  WITH filtered AS (
    SELECT *
    FROM articles
    WHERE status = 'published'
      AND search_vector @@ query
    LIMIT 1000
  )
  SELECT *, ts_rank(search_vector, query) AS rank
  FROM filtered,
    to_tsquery('english', ${terms}) AS query
  ORDER BY rank DESC
  LIMIT 20
`;
```
