# Redis Stack Features Reference

Redis Stack extends Redis with additional modules: RedisJSON, RediSearch, RedisTimeSeries, and RedisBloom.

---

## RedisJSON

Store, query, and manipulate JSON documents natively.

### Storing Documents

```typescript
// Set entire document
await redis.send("JSON.SET", [
  "user:1",
  "$",
  JSON.stringify({
    name: "Alice",
    email: "alice@example.com",
    profile: { age: 30, city: "NYC" },
    tags: ["developer", "redis"],
    active: true
  })
]);

// Set if not exists
await redis.send("JSON.SET", ["user:1", "$", jsonData, "NX"]);

// Set if exists
await redis.send("JSON.SET", ["user:1", "$", jsonData, "XX"]);
```

### Path Queries (JSONPath)

```typescript
// Get entire document
const doc = await redis.send("JSON.GET", ["user:1"]);

// Get specific path
const name = await redis.send("JSON.GET", ["user:1", "$.name"]);           // '["Alice"]'
const age = await redis.send("JSON.GET", ["user:1", "$.profile.age"]);     // '[30]'

// Get multiple paths
const data = await redis.send("JSON.GET", ["user:1", "$.name", "$.email"]);

// Recursive descent
const allCities = await redis.send("JSON.GET", ["user:1", "$..city"]);     // All city values

// Array access
const firstTag = await redis.send("JSON.GET", ["user:1", "$.tags[0]"]);
const lastTag = await redis.send("JSON.GET", ["user:1", "$.tags[-1]"]);

// Wildcard
await redis.send("JSON.GET", ["user:1", "$.profile.*"]);                   // All profile fields

// Filter expressions
await redis.send("JSON.GET", ["users", "$[?(@.age > 25)]"]);               // Filter by condition
```

### Updating Documents

```typescript
// Set nested value
await redis.send("JSON.SET", ["user:1", "$.profile.city", '"LA"']);        // Note: JSON string

// Merge objects (Redis 7.4+)
await redis.send("JSON.MERGE", ["user:1", "$.profile", '{"country": "USA"}']);

// Delete path
await redis.send("JSON.DEL", ["user:1", "$.profile.city"]);

// Clear container (set to empty)
await redis.send("JSON.CLEAR", ["user:1", "$.tags"]);
```

### Numeric Operations

```typescript
// Increment number
await redis.send("JSON.NUMINCRBY", ["user:1", "$.profile.age", "1"]);      // age + 1
await redis.send("JSON.NUMINCRBY", ["user:1", "$.score", "-5"]);           // score - 5

// Multiply number
await redis.send("JSON.NUMMULTBY", ["user:1", "$.profile.score", "1.5"]);
```

### String Operations

```typescript
// Append to string
await redis.send("JSON.STRAPPEND", ["user:1", "$.name", '" Smith"']);      // "Alice Smith"

// Get string length
await redis.send("JSON.STRLEN", ["user:1", "$.name"]);
```

### Array Operations

```typescript
// Append to array
await redis.send("JSON.ARRAPPEND", ["user:1", "$.tags", '"expert"', '"senior"']);

// Insert at index
await redis.send("JSON.ARRINSERT", ["user:1", "$.tags", "0", '"priority"']); // Insert at beginning

// Get array length
await redis.send("JSON.ARRLEN", ["user:1", "$.tags"]);

// Find index
await redis.send("JSON.ARRINDEX", ["user:1", "$.tags", '"redis"']);        // -1 if not found

// Pop from array
await redis.send("JSON.ARRPOP", ["user:1", "$.tags"]);                     // Pop last
await redis.send("JSON.ARRPOP", ["user:1", "$.tags", "0"]);                // Pop first

// Trim array
await redis.send("JSON.ARRTRIM", ["user:1", "$.tags", "0", "4"]);          // Keep first 5
```

### Object Operations

```typescript
// Get object keys
await redis.send("JSON.OBJKEYS", ["user:1", "$.profile"]);                 // ["age", "city"]

// Get object length
await redis.send("JSON.OBJLEN", ["user:1", "$.profile"]);
```

### Type and Debug

```typescript
// Get type
await redis.send("JSON.TYPE", ["user:1", "$.name"]);                       // "string"
await redis.send("JSON.TYPE", ["user:1", "$.tags"]);                       // "array"

// Debug memory
await redis.send("JSON.DEBUG", ["MEMORY", "user:1", "$.profile"]);

// Get multiple documents
await redis.send("JSON.MGET", ["user:1", "user:2", "user:3", "$.name"]);
```

---

## RediSearch

Full-text search and secondary indexing.

### Creating Indexes

```typescript
// Index on JSON documents
await redis.send("FT.CREATE", [
  "idx:products",
  "ON", "JSON",
  "PREFIX", "1", "product:",
  "SCHEMA",
  "$.name", "AS", "name", "TEXT", "WEIGHT", "5.0",
  "$.description", "AS", "description", "TEXT",
  "$.price", "AS", "price", "NUMERIC", "SORTABLE",
  "$.category", "AS", "category", "TAG",
  "$.brand", "AS", "brand", "TAG", "SORTABLE",
  "$.inStock", "AS", "inStock", "TAG",
  "$.location", "AS", "location", "GEO"
]);

// Index on Hash documents
await redis.send("FT.CREATE", [
  "idx:users",
  "ON", "HASH",
  "PREFIX", "1", "user:",
  "SCHEMA",
  "name", "TEXT",
  "email", "TAG",
  "age", "NUMERIC", "SORTABLE",
  "bio", "TEXT"
]);

// Drop index
await redis.send("FT.DROPINDEX", ["idx:products"]);
await redis.send("FT.DROPINDEX", ["idx:products", "DD"]);  // Also delete documents
```

### Index Field Types

| Type | Description | Options |
|------|-------------|---------|
| `TEXT` | Full-text searchable | `WEIGHT`, `NOSTEM`, `PHONETIC` |
| `TAG` | Exact match, comma-separated | `SEPARATOR`, `CASESENSITIVE` |
| `NUMERIC` | Number range queries | `SORTABLE` |
| `GEO` | Geographic coordinates | - |
| `VECTOR` | Vector embeddings | `FLAT`, `HNSW` |

### Full-Text Search

```typescript
// Basic search
await redis.send("FT.SEARCH", ["idx:products", "wireless headphones"]);

// Field-specific search
await redis.send("FT.SEARCH", ["idx:products", "@name:headphones"]);
await redis.send("FT.SEARCH", ["idx:products", "@name|description:wireless"]);

// Exact phrase
await redis.send("FT.SEARCH", ["idx:products", '"wireless headphones"']);

// Prefix search
await redis.send("FT.SEARCH", ["idx:products", "wire*"]);

// Fuzzy matching (Levenshtein distance)
await redis.send("FT.SEARCH", ["idx:products", "%headphnes%"]);   // 1 typo
await redis.send("FT.SEARCH", ["idx:products", "%%hedphones%%"]); // 2 typos
await redis.send("FT.SEARCH", ["idx:products", "%%%hedfones%%%"]); // 3 typos

// Negation
await redis.send("FT.SEARCH", ["idx:products", "headphones -wireless"]);

// Optional terms
await redis.send("FT.SEARCH", ["idx:products", "headphones ~bluetooth"]);
```

### Filter Queries

```typescript
// Numeric range
await redis.send("FT.SEARCH", ["idx:products", "@price:[50 200]"]);
await redis.send("FT.SEARCH", ["idx:products", "@price:[(50 (200]"]);  // Exclusive
await redis.send("FT.SEARCH", ["idx:products", "@price:[-inf 100]"]);

// Tag filter
await redis.send("FT.SEARCH", ["idx:products", "@category:{electronics}"]);
await redis.send("FT.SEARCH", ["idx:products", "@category:{electronics|audio}"]);  // OR
await redis.send("FT.SEARCH", ["idx:products", "@category:{electronics} @brand:{sony}"]);  // AND

// Geo filter
await redis.send("FT.SEARCH", [
  "idx:products",
  "@location:[-122.4194 37.7749 50 km]"
]);

// Boolean combinations
await redis.send("FT.SEARCH", ["idx:products",
  "(@name:headphones) (@price:[0 100]) (@category:{electronics})"
]);
```

### Search Options

```typescript
await redis.send("FT.SEARCH", [
  "idx:products",
  "headphones",

  // Pagination
  "LIMIT", "0", "10",

  // Sorting
  "SORTBY", "price", "ASC",

  // Return specific fields
  "RETURN", "3", "name", "price", "category",

  // Highlight matches
  "HIGHLIGHT", "FIELDS", "1", "name",

  // Summarize long text
  "SUMMARIZE", "FIELDS", "1", "description", "LEN", "50",

  // Language for stemming
  "LANGUAGE", "english",

  // Explain query scoring
  "EXPLAINSCORE"
]);

// Return only count
await redis.send("FT.SEARCH", ["idx:products", "headphones", "LIMIT", "0", "0"]);
```

### Aggregations

```typescript
// Group by category with stats
await redis.send("FT.AGGREGATE", [
  "idx:products",
  "*",
  "GROUPBY", "1", "@category",
  "REDUCE", "COUNT", "0", "AS", "count",
  "REDUCE", "AVG", "1", "@price", "AS", "avg_price",
  "REDUCE", "MIN", "1", "@price", "AS", "min_price",
  "REDUCE", "MAX", "1", "@price", "AS", "max_price",
  "SORTBY", "2", "@count", "DESC",
  "LIMIT", "0", "10"
]);

// Available reducers
// COUNT, COUNT_DISTINCT, COUNT_DISTINCTISH
// SUM, AVG, MIN, MAX, STDDEV, QUANTILE
// FIRST_VALUE, TOLIST, RANDOM_SAMPLE

// Apply transformations
await redis.send("FT.AGGREGATE", [
  "idx:products",
  "*",
  "APPLY", "@price * 1.1", "AS", "price_with_tax",
  "APPLY", "upper(@name)", "AS", "name_upper"
]);

// Filter in aggregation
await redis.send("FT.AGGREGATE", [
  "idx:products",
  "*",
  "GROUPBY", "1", "@category",
  "REDUCE", "AVG", "1", "@price", "AS", "avg_price",
  "FILTER", "@avg_price > 50"
]);
```

### Autocomplete

```typescript
// Add suggestions
await redis.send("FT.SUGADD", ["autocomplete", "bluetooth headphones", "100"]);
await redis.send("FT.SUGADD", ["autocomplete", "wireless earbuds", "90", "PAYLOAD", "electronics"]);

// Get suggestions
await redis.send("FT.SUGGET", ["autocomplete", "blue", "FUZZY", "MAX", "5", "WITHPAYLOADS"]);

// Delete suggestion
await redis.send("FT.SUGDEL", ["autocomplete", "bluetooth headphones"]);

// Get suggestion count
await redis.send("FT.SUGLEN", ["autocomplete"]);
```

### Index Management

```typescript
// List indexes
await redis.send("FT._LIST", []);

// Get index info
await redis.send("FT.INFO", ["idx:products"]);

// Alter index (add fields)
await redis.send("FT.ALTER", [
  "idx:products",
  "SCHEMA", "ADD",
  "$.rating", "AS", "rating", "NUMERIC", "SORTABLE"
]);

// Alias management
await redis.send("FT.ALIASADD", ["products", "idx:products"]);
await redis.send("FT.ALIASUPDATE", ["products", "idx:products_v2"]);
await redis.send("FT.ALIASDEL", ["products"]);

// Synonyms
await redis.send("FT.SYNUPDATE", ["idx:products", "group1", "phone", "mobile", "cell"]);
```

---

## Vector Search

Semantic similarity search with vector embeddings.

### Creating Vector Indexes

```typescript
// FLAT index (brute-force, best for small datasets)
await redis.send("FT.CREATE", [
  "idx:docs",
  "ON", "JSON",
  "PREFIX", "1", "doc:",
  "SCHEMA",
  "$.content", "AS", "content", "TEXT",
  "$.embedding", "AS", "embedding", "VECTOR", "FLAT", "6",
    "TYPE", "FLOAT32",
    "DIM", "384",              // Must match your embedding model
    "DISTANCE_METRIC", "COSINE"
]);

// HNSW index (approximate, best for large datasets)
await redis.send("FT.CREATE", [
  "idx:embeddings",
  "ON", "JSON",
  "PREFIX", "1", "doc:",
  "SCHEMA",
  "$.title", "AS", "title", "TEXT",
  "$.category", "AS", "category", "TAG",
  "$.embedding", "AS", "embedding", "VECTOR", "HNSW", "10",
    "TYPE", "FLOAT32",
    "DIM", "1536",             // OpenAI ada-002 dimension
    "DISTANCE_METRIC", "COSINE",
    "M", "16",                 // HNSW connections per layer (4-64)
    "EF_CONSTRUCTION", "200"   // HNSW construction quality (100-500)
]);
```

### Vector Index Parameters

| Algorithm | Parameter | Description | Default |
|-----------|-----------|-------------|---------|
| FLAT | TYPE | FLOAT32, FLOAT64, BFLOAT16 | FLOAT32 |
| FLAT | DIM | Vector dimensions | Required |
| FLAT | DISTANCE_METRIC | L2, IP, COSINE | L2 |
| HNSW | M | Max outgoing edges per node | 16 |
| HNSW | EF_CONSTRUCTION | Construction quality | 200 |
| HNSW | EF_RUNTIME | Search quality (query time) | 10 |

### Storing Vectors

```typescript
// Store as JSON array
async function storeDocument(id: string, content: string, embedding: number[]) {
  await redis.send("JSON.SET", [
    `doc:${id}`,
    "$",
    JSON.stringify({
      content,
      embedding  // Array of floats
    })
  ]);
}

// Store as binary blob (more efficient)
async function storeVectorBlob(id: string, embedding: Float32Array) {
  const blob = Buffer.from(embedding.buffer);
  await redis.send("HSET", [
    `vec:${id}`,
    "embedding", blob
  ]);
}
```

### KNN Vector Search

```typescript
// Prepare query vector as bytes
function vectorToBytes(embedding: number[]): Buffer {
  return Buffer.from(new Float32Array(embedding).buffer);
}

// KNN search (find K nearest neighbors)
async function semanticSearch(queryEmbedding: number[], k: number = 5) {
  const vecBytes = vectorToBytes(queryEmbedding);

  return await redis.send("FT.SEARCH", [
    "idx:docs",
    `(*)=>[KNN ${k} @embedding $vec AS score]`,
    "PARAMS", "2", "vec", vecBytes,
    "SORTBY", "score",
    "RETURN", "2", "content", "score",
    "DIALECT", "2"
  ]);
}

// KNN with pre-filter (hybrid search)
await redis.send("FT.SEARCH", [
  "idx:docs",
  "(@category:{technology})=>[KNN 10 @embedding $vec AS score]",
  "PARAMS", "2", "vec", queryVectorBytes,
  "SORTBY", "score",
  "DIALECT", "2"
]);
```

### Vector Range Search

```typescript
// Find all vectors within distance threshold
await redis.send("FT.SEARCH", [
  "idx:docs",
  "@embedding:[VECTOR_RANGE $radius $vec]=>{$YIELD_DISTANCE_AS: score}",
  "PARAMS", "4", "vec", queryVectorBytes, "radius", "0.5",
  "SORTBY", "score", "ASC",
  "DIALECT", "2"
]);

// Combined range + filter
await redis.send("FT.SEARCH", [
  "idx:docs",
  "(@category:{tech}) @embedding:[VECTOR_RANGE 0.3 $vec]",
  "PARAMS", "2", "vec", queryVectorBytes,
  "DIALECT", "2"
]);
```

### RAG Pattern (Retrieval Augmented Generation)

```typescript
import { redis } from "bun";

interface Document {
  id: string;
  content: string;
  embedding: number[];
  metadata: Record<string, any>;
}

class VectorStore {
  private indexName: string;
  private dimension: number;

  constructor(indexName: string, dimension: number = 384) {
    this.indexName = indexName;
    this.dimension = dimension;
  }

  async createIndex() {
    try {
      await redis.send("FT.CREATE", [
        this.indexName,
        "ON", "JSON",
        "PREFIX", "1", "doc:",
        "SCHEMA",
        "$.content", "AS", "content", "TEXT",
        "$.metadata.source", "AS", "source", "TAG",
        "$.embedding", "AS", "embedding", "VECTOR", "HNSW", "8",
          "TYPE", "FLOAT32",
          "DIM", this.dimension.toString(),
          "DISTANCE_METRIC", "COSINE",
          "M", "16",
          "EF_CONSTRUCTION", "200"
      ]);
    } catch (e: any) {
      if (!e.message.includes("Index already exists")) throw e;
    }
  }

  async addDocument(doc: Document) {
    await redis.send("JSON.SET", [
      `doc:${doc.id}`,
      "$",
      JSON.stringify({
        content: doc.content,
        metadata: doc.metadata,
        embedding: doc.embedding
      })
    ]);
  }

  async search(queryEmbedding: number[], k: number = 5, filter?: string) {
    const vecBytes = Buffer.from(new Float32Array(queryEmbedding).buffer);

    const query = filter
      ? `(${filter})=>[KNN ${k} @embedding $vec AS score]`
      : `(*)=>[KNN ${k} @embedding $vec AS score]`;

    const results = await redis.send("FT.SEARCH", [
      this.indexName,
      query,
      "PARAMS", "2", "vec", vecBytes,
      "SORTBY", "score",
      "RETURN", "3", "content", "source", "score",
      "DIALECT", "2"
    ]);

    return this.parseSearchResults(results);
  }

  private parseSearchResults(results: any) {
    const [count, ...items] = results;
    const docs = [];

    for (let i = 0; i < items.length; i += 2) {
      const id = items[i];
      const fields = items[i + 1];
      docs.push({
        id: id.replace("doc:", ""),
        content: this.getField(fields, "content"),
        source: this.getField(fields, "source"),
        score: parseFloat(this.getField(fields, "score") || "0")
      });
    }

    return { count, docs };
  }

  private getField(fields: any[], name: string): string | undefined {
    for (let i = 0; i < fields.length; i += 2) {
      if (fields[i] === name) return fields[i + 1];
    }
    return undefined;
  }
}
```

---

## RedisTimeSeries

Time-series data storage and analysis.

### Creating Time Series

```typescript
// Create time series with retention
await redis.send("TS.CREATE", [
  "sensor:temp:1",
  "RETENTION", "86400000",       // 1 day in ms (0 = infinite)
  "ENCODING", "COMPRESSED",      // or "UNCOMPRESSED"
  "DUPLICATE_POLICY", "LAST",    // BLOCK, FIRST, LAST, MIN, MAX, SUM
  "LABELS", "location", "warehouse", "type", "temperature", "unit", "celsius"
]);

// Create if not exists
await redis.send("TS.CREATE", ["sensor:temp:1", "RETENTION", "86400000", "LABELS", "type", "temp"]);
```

### Adding Samples

```typescript
// Add single sample with auto timestamp
await redis.send("TS.ADD", ["sensor:temp:1", "*", "23.5"]);

// Add with specific timestamp
await redis.send("TS.ADD", ["sensor:temp:1", "1703001234567", "23.5"]);

// Add with on-duplicate handling
await redis.send("TS.ADD", ["sensor:temp:1", "*", "23.5", "ON_DUPLICATE", "LAST"]);

// Add multiple samples
await redis.send("TS.MADD", [
  "sensor:temp:1", "1703001234000", "23.5",
  "sensor:temp:2", "1703001234000", "24.1",
  "sensor:humidity:1", "1703001234000", "65.0"
]);

// Increment/Decrement
await redis.send("TS.INCRBY", ["counter:visits", "1"]);
await redis.send("TS.DECRBY", ["counter:visits", "1"]);
```

### Querying

```typescript
// Get latest sample
await redis.send("TS.GET", ["sensor:temp:1"]);

// Get range with aggregation
await redis.send("TS.RANGE", [
  "sensor:temp:1",
  "-", "+",                      // Full range (or timestamps)
  "AGGREGATION", "avg", "3600000", // Hourly average
  "COUNT", "24"                  // Limit results
]);

// Aggregation functions: avg, sum, min, max, range, count, first, last, std.p, std.s, var.p, var.s, twa

// Reverse range (newest first)
await redis.send("TS.REVRANGE", [
  "sensor:temp:1",
  "-", "+",
  "COUNT", "10"
]);

// Get multiple time series
await redis.send("TS.MGET", [
  "FILTER", "type=temperature"
]);

// Multi-range query
await redis.send("TS.MRANGE", [
  "-", "+",
  "FILTER", "location=warehouse",
  "AGGREGATION", "max", "3600000",
  "GROUPBY", "type",
  "REDUCE", "max"
]);
```

### Downsampling Rules

```typescript
// Create destination time series
await redis.send("TS.CREATE", ["sensor:temp:1:hourly", "RETENTION", "2592000000"]); // 30 days

// Create compaction rule
await redis.send("TS.CREATERULE", [
  "sensor:temp:1",               // Source
  "sensor:temp:1:hourly",        // Destination
  "AGGREGATION", "avg", "3600000" // Hourly average
]);

// Delete rule
await redis.send("TS.DELETERULE", ["sensor:temp:1", "sensor:temp:1:hourly"]);
```

### Labels and Metadata

```typescript
// Alter labels
await redis.send("TS.ALTER", [
  "sensor:temp:1",
  "LABELS", "location", "warehouse", "floor", "1"
]);

// Query by labels
await redis.send("TS.QUERYINDEX", ["location=warehouse", "floor=1"]);

// Get info
await redis.send("TS.INFO", ["sensor:temp:1"]);
```

---

## RedisBloom (Probabilistic)

Probabilistic data structures for space-efficient approximate operations.

### Bloom Filter

```typescript
// Create filter (capacity, error rate)
await redis.send("BF.RESERVE", ["emails", "0.01", "1000000"]);  // 1% false positive

// Add items
await redis.send("BF.ADD", ["emails", "user@example.com"]);
await redis.send("BF.MADD", ["emails", "a@b.com", "c@d.com", "e@f.com"]);

// Check existence
await redis.send("BF.EXISTS", ["emails", "user@example.com"]);  // 1 = maybe, 0 = definitely not
await redis.send("BF.MEXISTS", ["emails", "a@b.com", "unknown@x.com"]);

// Get info
await redis.send("BF.INFO", ["emails"]);
```

### Cuckoo Filter

```typescript
// Better for deletion, slightly larger
await redis.send("CF.RESERVE", ["items", "1000000"]);

await redis.send("CF.ADD", ["items", "item1"]);
await redis.send("CF.EXISTS", ["items", "item1"]);
await redis.send("CF.DEL", ["items", "item1"]);  // Can delete (unlike Bloom)

// Count occurrences (approximate)
await redis.send("CF.COUNT", ["items", "item1"]);
```

### Count-Min Sketch

```typescript
// Frequency estimation
await redis.send("CMS.INITBYDIM", ["page_views", "2000", "5"]);

// Increment count
await redis.send("CMS.INCRBY", ["page_views", "/home", "1", "/about", "1"]);

// Get count
await redis.send("CMS.QUERY", ["page_views", "/home", "/about"]);

// Merge sketches
await redis.send("CMS.MERGE", ["combined", "2", "sketch1", "sketch2"]);
```

### Top-K

```typescript
// Track top K items
await redis.send("TOPK.RESERVE", ["trending", "10", "50", "5", "0.9"]);

// Add items
await redis.send("TOPK.ADD", ["trending", "item1", "item2", "item1", "item3"]);
await redis.send("TOPK.INCRBY", ["trending", "item1", "5"]);

// Get top K
await redis.send("TOPK.LIST", ["trending"]);

// Check if in top K
await redis.send("TOPK.QUERY", ["trending", "item1", "item2"]);
```
