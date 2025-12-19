# pgvector Guide

Complete guide to vector similarity search with pgvector and Bun.sql.

## Installation

### Enable Extension

```typescript
await sql`CREATE EXTENSION IF NOT EXISTS vector`;
```

### Version Check

```typescript
const [{ version }] = await sql`SELECT extversion FROM pg_extension WHERE extname = 'vector'`;
```

---

## Vector Data Type

### Creating Tables with Vectors

```typescript
// Fixed dimension vector
await sql`
  CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    embedding vector(1536),  -- OpenAI text-embedding-ada-002
    metadata JSONB DEFAULT '{}'
  )
`;

// Common embedding dimensions:
// - OpenAI ada-002: 1536
// - OpenAI text-embedding-3-small: 1536
// - OpenAI text-embedding-3-large: 3072
// - Cohere embed-english-v3.0: 1024
// - Sentence Transformers: 384-768
// - CLIP: 512-768
```

### Altering Existing Tables

```typescript
await sql`ALTER TABLE documents ADD COLUMN embedding vector(1536)`;
```

---

## Inserting Vectors

### Basic Insert

```typescript
const embedding = [0.1, 0.2, 0.3, ...]; // Array of floats

await sql`
  INSERT INTO documents (content, embedding)
  VALUES (${content}, ${sql.array(embedding)}::vector)
`;
```

### Insert with Metadata

```typescript
await sql`
  INSERT INTO documents (content, embedding, metadata)
  VALUES (
    ${content},
    ${sql.array(embedding)}::vector,
    ${sql({ source: "upload", category: "technical" })}
  )
`;
```

### Bulk Insert

```typescript
const documents = [
  { content: "Doc 1", embedding: [...], category: "tech" },
  { content: "Doc 2", embedding: [...], category: "science" },
];

// Insert one at a time (with vector)
for (const doc of documents) {
  await sql`
    INSERT INTO documents (content, embedding, metadata)
    VALUES (
      ${doc.content},
      ${sql.array(doc.embedding)}::vector,
      ${sql({ category: doc.category })}
    )
  `;
}
```

### Update Embeddings

```typescript
await sql`
  UPDATE documents
  SET embedding = ${sql.array(newEmbedding)}::vector
  WHERE id = ${documentId}
`;
```

---

## Distance Functions

### L2 Distance (Euclidean)

```typescript
// Operator: <->
const similar = await sql`
  SELECT
    id,
    content,
    embedding <-> ${sql.array(queryEmbedding)}::vector AS distance
  FROM documents
  ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
  LIMIT ${k}
`;
```

### Cosine Distance

```typescript
// Operator: <=>
// Note: Returns distance (1 - similarity), not similarity
const similar = await sql`
  SELECT
    id,
    content,
    1 - (embedding <=> ${sql.array(queryEmbedding)}::vector) AS similarity
  FROM documents
  ORDER BY embedding <=> ${sql.array(queryEmbedding)}::vector
  LIMIT ${k}
`;
```

### Inner Product

```typescript
// Operator: <#>
// Note: Returns negative inner product for ORDER BY
// Best used with normalized vectors
const similar = await sql`
  SELECT
    id,
    content,
    (embedding <#> ${sql.array(queryEmbedding)}::vector) * -1 AS inner_product
  FROM documents
  ORDER BY embedding <#> ${sql.array(queryEmbedding)}::vector
  LIMIT ${k}
`;
```

### Distance Function Comparison

| Use Case | Function | Index Type |
|----------|----------|------------|
| General purpose | L2 (Euclidean) | `vector_l2_ops` |
| Normalized vectors, NLP | Cosine | `vector_cosine_ops` |
| Normalized vectors, performance | Inner Product | `vector_ip_ops` |

---

## Querying Vectors

### Basic Similarity Search

```typescript
async function searchSimilar(queryEmbedding: number[], k: number = 10) {
  return await sql`
    SELECT id, content, embedding <-> ${sql.array(queryEmbedding)}::vector AS distance
    FROM documents
    ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
    LIMIT ${k}
  `;
}
```

### Filtered Similarity Search

```typescript
async function searchByCategory(
  queryEmbedding: number[],
  category: string,
  k: number = 10
) {
  return await sql`
    SELECT id, content
    FROM documents
    WHERE metadata @> ${sql({ category })}
    ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
    LIMIT ${k}
  `;
}
```

### Threshold-Based Search

```typescript
// Return all documents within distance threshold
async function searchWithThreshold(
  queryEmbedding: number[],
  maxDistance: number = 0.5
) {
  return await sql`
    SELECT id, content, embedding <-> ${sql.array(queryEmbedding)}::vector AS distance
    FROM documents
    WHERE embedding <-> ${sql.array(queryEmbedding)}::vector < ${maxDistance}
    ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
  `;
}
```

### Combined Full-Text and Vector Search

```typescript
async function hybridSearch(
  query: string,
  queryEmbedding: number[],
  k: number = 10
) {
  return await sql`
    WITH text_search AS (
      SELECT id, ts_rank(search_vector, websearch_to_tsquery('english', ${query})) AS text_score
      FROM documents
      WHERE search_vector @@ websearch_to_tsquery('english', ${query})
    ),
    vector_search AS (
      SELECT id, 1 / (1 + embedding <-> ${sql.array(queryEmbedding)}::vector) AS vector_score
      FROM documents
    )
    SELECT
      d.id,
      d.content,
      COALESCE(ts.text_score, 0) * 0.3 + COALESCE(vs.vector_score, 0) * 0.7 AS combined_score
    FROM documents d
    LEFT JOIN text_search ts ON ts.id = d.id
    LEFT JOIN vector_search vs ON vs.id = d.id
    WHERE ts.text_score IS NOT NULL OR vs.vector_score > 0.5
    ORDER BY combined_score DESC
    LIMIT ${k}
  `;
}
```

---

## Indexing

### Index Types

| Index | Build Time | Query Time | Recall | Memory |
|-------|------------|------------|--------|--------|
| None | - | O(n) | 100% | Low |
| IVFFlat | Fast | Fast | 95-99% | Low |
| HNSW | Slow | Very Fast | 99%+ | High |

### IVFFlat Index

Best for: Large datasets, memory-constrained, frequent updates

```typescript
// Calculate optimal lists: sqrt(row_count)
// For 1M rows: ~1000 lists
const [{ count }] = await sql`SELECT COUNT(*) FROM documents`;
const lists = Math.floor(Math.sqrt(Number(count)));

// Create index after loading data
await sql`
  CREATE INDEX documents_embedding_ivfflat_idx
  ON documents
  USING ivfflat (embedding vector_l2_ops)
  WITH (lists = ${lists})
`;
```

### HNSW Index

Best for: High recall requirements, query-heavy workloads

```typescript
await sql`
  CREATE INDEX documents_embedding_hnsw_idx
  ON documents
  USING hnsw (embedding vector_l2_ops)
  WITH (m = 16, ef_construction = 64)
`;
```

#### HNSW Parameters

| Parameter | Description | Default | Trade-off |
|-----------|-------------|---------|-----------|
| `m` | Connections per node | 16 | Higher = better recall, more memory |
| `ef_construction` | Build-time search width | 64 | Higher = better recall, slower build |

### Index by Distance Type

```typescript
// L2 distance
await sql`CREATE INDEX idx ON docs USING hnsw (embedding vector_l2_ops)`;

// Cosine distance
await sql`CREATE INDEX idx ON docs USING hnsw (embedding vector_cosine_ops)`;

// Inner product
await sql`CREATE INDEX idx ON docs USING hnsw (embedding vector_ip_ops)`;
```

### Partial Indexes

```typescript
// Index only specific category
await sql`
  CREATE INDEX docs_tech_embedding_idx
  ON documents
  USING hnsw (embedding vector_l2_ops)
  WHERE metadata @> '{"category": "technical"}'
`;
```

---

## Query Tuning

### IVFFlat Tuning

```typescript
// Probes: Number of lists to search (default: 1)
// Higher = better recall, slower query
await sql`SET ivfflat.probes = 10`;

// Or per-query
await sql`
  SET LOCAL ivfflat.probes = 20;
  SELECT * FROM documents
  ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
  LIMIT 10
`;
```

#### Probes Guidelines

| Dataset Size | Recommended Probes | Approximate Recall |
|--------------|-------------------|-------------------|
| < 100K | 1-5 | 95%+ |
| 100K-1M | 10-20 | 95%+ |
| > 1M | 20-50 | 95%+ |

### HNSW Tuning

```typescript
// ef_search: Search-time exploration factor (default: 40)
// Higher = better recall, slower query
await sql`SET hnsw.ef_search = 100`;

// Or per-query
await sql`
  SET LOCAL hnsw.ef_search = 200;
  SELECT * FROM documents
  ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
  LIMIT 10
`;
```

---

## RAG (Retrieval-Augmented Generation) Patterns

### Basic RAG Context Retrieval

```typescript
async function getRAGContext(
  query: string,
  queryEmbedding: number[],
  k: number = 5,
  maxTokens: number = 2000
): Promise<string[]> {
  const results = await sql`
    SELECT content
    FROM documents
    ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
    LIMIT ${k}
  `;

  // Combine until token limit (simplified)
  const contexts: string[] = [];
  let totalLength = 0;
  const approxTokenRatio = 4; // ~4 chars per token

  for (const row of results) {
    const tokenEstimate = row.content.length / approxTokenRatio;
    if (totalLength + tokenEstimate > maxTokens) break;
    contexts.push(row.content);
    totalLength += tokenEstimate;
  }

  return contexts;
}
```

### Chunking Strategy

```typescript
async function storeWithChunks(
  documentId: string,
  content: string,
  chunkSize: number = 500,
  overlap: number = 50
) {
  const chunks: string[] = [];
  let start = 0;

  while (start < content.length) {
    const end = Math.min(start + chunkSize, content.length);
    chunks.push(content.slice(start, end));
    start += chunkSize - overlap;
  }

  for (let i = 0; i < chunks.length; i++) {
    const embedding = await getEmbedding(chunks[i]); // Your embedding API
    await sql`
      INSERT INTO document_chunks (document_id, chunk_index, content, embedding)
      VALUES (${documentId}, ${i}, ${chunks[i]}, ${sql.array(embedding)}::vector)
    `;
  }
}
```

### Reranking Pattern

```typescript
async function searchWithReranking(
  queryEmbedding: number[],
  k: number = 10,
  rerankTop: number = 50
) {
  // First pass: Get more candidates with vector search
  const candidates = await sql`
    SELECT id, content, embedding <-> ${sql.array(queryEmbedding)}::vector AS distance
    FROM documents
    ORDER BY embedding <-> ${sql.array(queryEmbedding)}::vector
    LIMIT ${rerankTop}
  `;

  // Second pass: Rerank with more expensive model
  const reranked = await rerankWithCrossEncoder(candidates);

  return reranked.slice(0, k);
}
```

### Multi-Query Retrieval

```typescript
async function multiQueryRetrieval(
  queries: string[],
  k: number = 10
) {
  const allEmbeddings = await Promise.all(
    queries.map(q => getEmbedding(q))
  );

  // Get candidates from each query
  const allResults = await Promise.all(
    allEmbeddings.map(embedding =>
      sql`
        SELECT id, content, embedding <-> ${sql.array(embedding)}::vector AS distance
        FROM documents
        ORDER BY embedding <-> ${sql.array(embedding)}::vector
        LIMIT ${k}
      `
    )
  );

  // Merge and deduplicate
  const seen = new Set<number>();
  const merged = [];

  for (const results of allResults) {
    for (const row of results) {
      if (!seen.has(row.id)) {
        seen.add(row.id);
        merged.push(row);
      }
    }
  }

  // Sort by minimum distance across all queries
  return merged.sort((a, b) => a.distance - b.distance).slice(0, k);
}
```

---

## Vector Operations

### Dimension

```typescript
await sql`SELECT vector_dims(embedding) FROM documents LIMIT 1`;
```

### Norm

```typescript
await sql`SELECT vector_norm(embedding) FROM documents LIMIT 1`;
```

### Normalize Vectors

```typescript
// Normalize in database
await sql`
  UPDATE documents
  SET embedding = embedding / vector_norm(embedding)
  WHERE vector_norm(embedding) > 0
`;

// Or use normalized on insert
const normalized = embedding.map(v => v / Math.sqrt(embedding.reduce((a, b) => a + b * b, 0)));
```

### Add/Subtract Vectors

```typescript
// Concept: king - man + woman = queen
await sql`
  SELECT
    (${sql.array(king)}::vector - ${sql.array(man)}::vector + ${sql.array(woman)}::vector) AS queen_embedding
`;
```

### Average Vectors

```typescript
// Cluster centroid
const [{ centroid }] = await sql`
  SELECT AVG(embedding) AS centroid
  FROM documents
  WHERE metadata @> '{"category": "technical"}'
`;
```

---

## Performance Best Practices

### 1. Use Appropriate Dimensions

```typescript
// Smaller dimensions = faster, less accurate
// Consider dimensionality reduction for large embeddings
```

### 2. Build Index After Loading

```typescript
// Drop index, bulk load, rebuild
await sql`DROP INDEX IF EXISTS documents_embedding_idx`;
// ... bulk insert ...
await sql`CREATE INDEX documents_embedding_idx ON documents USING hnsw (embedding vector_l2_ops)`;
```

### 3. Use Partial Indexes

```typescript
// Index only what you query
await sql`
  CREATE INDEX active_docs_embedding_idx
  ON documents USING hnsw (embedding vector_l2_ops)
  WHERE status = 'active'
`;
```

### 4. Pre-Filter When Possible

```typescript
// Narrow results before vector search
await sql`
  SELECT id, content
  FROM documents
  WHERE created_at > NOW() - INTERVAL '30 days'
    AND metadata @> '{"category": "tech"}'
  ORDER BY embedding <-> ${sql.array(query)}::vector
  LIMIT 10
`;
```

### 5. Tune Index Parameters

```typescript
// HNSW: increase m and ef_construction for better recall
await sql`CREATE INDEX idx ON docs USING hnsw (embedding vector_l2_ops) WITH (m = 32, ef_construction = 128)`;

// IVFFlat: balance lists with dataset size
const lists = Math.floor(Math.sqrt(rowCount));
```

### 6. Monitor Index Usage

```typescript
const plan = await sql`
  EXPLAIN ANALYZE
  SELECT * FROM documents
  ORDER BY embedding <-> ${sql.array(query)}::vector
  LIMIT 10
`;
```

---

## Maintenance

### Check Index Size

```typescript
await sql`
  SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
  FROM pg_stat_user_indexes
  WHERE indexrelname LIKE '%embedding%'
`;
```

### Vacuum After Large Updates

```typescript
await sql`VACUUM ANALYZE documents`;
```

### Reindex

```typescript
await sql`REINDEX INDEX CONCURRENTLY documents_embedding_idx`;
```
