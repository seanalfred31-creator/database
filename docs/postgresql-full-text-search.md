# PostgreSQL Full-Text Search with JSONB

Advanced full-text search capabilities for JSONB data.

## Table of Contents

1. [Full-Text Search Basics](#full-text-search-basics)
2. [JSONB Full-Text Search](#jsonb-full-text-search)
3. [Search Indexes](#search-indexes)
4. [Advanced Search Patterns](#advanced-search-patterns)
5. [Performance Optimization](#performance-optimization)

## Full-Text Search Basics

### Why Full-Text Search?

**Benefits:**
- Natural language search
- Ranking by relevance
- Stemming and language support
- Phrase matching
- Fuzzy matching

**Use Cases:**
- Product search
- Document search
- Content management
- Knowledge bases

### Basic Full-Text Search

```sql
-- Create tsvector column
ALTER TABLE products ADD COLUMN search_vector tsvector;

-- Populate search vector
UPDATE products 
SET search_vector = to_tsvector('english', name || ' ' || description);

-- Create GIN index
CREATE INDEX idx_products_search ON products USING GIN (search_vector);

-- Search
SELECT * FROM products 
WHERE search_vector @@ to_tsquery('english', 'laptop & gaming');
```

### Text Search Operators

```sql
-- Match query
SELECT * FROM products 
WHERE search_vector @@ to_tsquery('laptop');

-- Phrase search
SELECT * FROM products 
WHERE search_vector @@ phraseto_tsquery('gaming laptop');

-- Plain text search (automatic parsing)
SELECT * FROM products 
WHERE search_vector @@ plainto_tsquery('gaming laptop');

-- Web search syntax
SELECT * FROM products 
WHERE search_vector @@ websearch_to_tsquery('"gaming laptop" OR desktop');
```

## JSONB Full-Text Search

### Searching JSONB Fields

```sql
-- Search in JSONB text field
SELECT * FROM products
WHERE to_tsvector('english', metadata->>'description') 
      @@ to_tsquery('laptop');

-- Search multiple JSONB fields
SELECT * FROM products
WHERE to_tsvector('english', 
        name || ' ' || 
        metadata->>'description' || ' ' || 
        metadata->>'brand'
      ) @@ to_tsquery('dell & laptop');
```

### Generated Columns for JSONB Search

```sql
-- Add generated search column
ALTER TABLE products 
ADD COLUMN search_vector tsvector 
GENERATED ALWAYS AS (
  to_tsvector('english',
    coalesce(name, '') || ' ' ||
    coalesce(metadata->>'description', '') || ' ' ||
    coalesce(metadata->>'brand', '') || ' ' ||
    coalesce(array_to_string(
      ARRAY(SELECT jsonb_array_elements_text(metadata->'tags')), 
      ' '
    ), '')
  )
) STORED;

-- Create index
CREATE INDEX idx_products_search_vector 
ON products USING GIN (search_vector);

-- Search
SELECT * FROM products 
WHERE search_vector @@ websearch_to_tsquery('gaming laptop');
```

### PHP Implementation

```php
class FullTextSearch
{
    private PDO $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    /**
     * Search products with full-text search
     */
    public function searchProducts(string $query, int $limit = 20): array
    {
        $stmt = $this->pdo->prepare("
            SELECT 
                id,
                name,
                metadata,
                ts_rank(search_vector, query) as rank
            FROM products,
                 websearch_to_tsquery('english', :query) query
            WHERE search_vector @@ query
            ORDER BY rank DESC
            LIMIT :limit
        ");
        
        $stmt->bindValue(':query', $query, PDO::PARAM_STR);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Search with highlighting
     */
    public function searchWithHighlight(string $query, int $limit = 20): array
    {
        $stmt = $this->pdo->prepare("
            SELECT 
                id,
                name,
                metadata,
                ts_rank(search_vector, query) as rank,
                ts_headline('english', 
                    name || ' ' || metadata->>'description',
                    query,
                    'MaxWords=50, MinWords=25'
                ) as headline
            FROM products,
                 websearch_to_tsquery('english', :query) query
            WHERE search_vector @@ query
            ORDER BY rank DESC
            LIMIT :limit
        ");
        
        $stmt->bindValue(':query', $query, PDO::PARAM_STR);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Faceted search with JSONB
     */
    public function facetedSearch(string $query, array $filters = []): array
    {
        $sql = "
            SELECT 
                id,
                name,
                metadata,
                ts_rank(search_vector, websearch_to_tsquery('english', :query)) as rank
            FROM products
            WHERE search_vector @@ websearch_to_tsquery('english', :query)
        ";
        
        $params = ['query' => $query];
        
        if (isset($filters['brand'])) {
            $sql .= " AND metadata->>'brand' = :brand";
            $params['brand'] = $filters['brand'];
        }
        
        if (isset($filters['min_price'])) {
            $sql .= " AND (metadata->>'price')::numeric >= :min_price";
            $params['min_price'] = $filters['min_price'];
        }
        
        if (isset($filters['tag'])) {
            $sql .= " AND metadata->'tags' @> :tag::jsonb";
            $params['tag'] = json_encode([$filters['tag']]);
        }
        
        $sql .= " ORDER BY rank DESC LIMIT 50";
        
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);
        
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * Autocomplete suggestions
     */
    public function autocomplete(string $prefix, int $limit = 10): array
    {
        $stmt = $this->pdo->prepare("
            SELECT DISTINCT
                name,
                metadata->>'brand' as brand,
                ts_rank(search_vector, query) as rank
            FROM products,
                 to_tsquery('english', :prefix || ':*') query
            WHERE search_vector @@ query
            ORDER BY rank DESC
            LIMIT :limit
        ");
        
        $stmt->bindValue(':prefix', $prefix, PDO::PARAM_STR);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();
        
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
}

// Usage
$search = new FullTextSearch($pdo);

// Basic search
$results = $search->searchProducts('gaming laptop');

// Search with highlighting
$results = $search->searchWithHighlight('gaming laptop');

// Faceted search
$results = $search->facetedSearch('laptop', [
    'brand' => 'Dell',
    'min_price' => 500,
    'tag' => 'gaming'
]);

// Autocomplete
$suggestions = $search->autocomplete('gam');
```

### Ruby Implementation

```ruby
class FullTextSearch
  def initialize(db)
    @db = db
  end

  # Search products with full-text search
  def search_products(query, limit: 20)
    @db.fetch("
      SELECT 
        id,
        name,
        metadata,
        ts_rank(search_vector, websearch_to_tsquery('english', ?)) as rank
      FROM products
      WHERE search_vector @@ websearch_to_tsquery('english', ?)
      ORDER BY rank DESC
      LIMIT ?
    ", query, query, limit).all
  end

  # Search with highlighting
  def search_with_highlight(query, limit: 20)
    @db.fetch("
      SELECT 
        id,
        name,
        metadata,
        ts_rank(search_vector, q) as rank,
        ts_headline('english', 
          name || ' ' || metadata->>'description',
          q,
          'MaxWords=50, MinWords=25'
        ) as headline
      FROM products,
           websearch_to_tsquery('english', ?) q
      WHERE search_vector @@ q
      ORDER BY rank DESC
      LIMIT ?
    ", query, limit).all
  end

  # Faceted search
  def faceted_search(query, filters = {})
    dataset = @db[:products]
      .select(
        :id,
        :name,
        :metadata,
        Sequel.lit("ts_rank(search_vector, websearch_to_tsquery('english', ?)) as rank", query)
      )
      .where(Sequel.lit("search_vector @@ websearch_to_tsquery('english', ?)", query))

    dataset = dataset.where(Sequel.lit("metadata->>'brand' = ?", filters[:brand])) if filters[:brand]
    dataset = dataset.where(Sequel.lit("(metadata->>'price')::numeric >= ?", filters[:min_price])) if filters[:min_price]
    dataset = dataset.where(Sequel.lit("metadata->'tags' @> ?::jsonb", [filters[:tag]].to_json)) if filters[:tag]

    dataset.order(Sequel.desc(:rank)).limit(50).all
  end

  # Autocomplete
  def autocomplete(prefix, limit: 10)
    @db.fetch("
      SELECT DISTINCT
        name,
        metadata->>'brand' as brand,
        ts_rank(search_vector, to_tsquery('english', ? || ':*')) as rank
      FROM products
      WHERE search_vector @@ to_tsquery('english', ? || ':*')
      ORDER BY rank DESC
      LIMIT ?
    ", prefix, prefix, limit).all
  end
end

# Usage
search = FullTextSearch.new(DB)

# Basic search
results = search.search_products('gaming laptop')

# Search with highlighting
results = search.search_with_highlight('gaming laptop')

# Faceted search
results = search.faceted_search('laptop', 
  brand: 'Dell',
  min_price: 500,
  tag: 'gaming'
)

# Autocomplete
suggestions = search.autocomplete('gam')
```

## Search Indexes

### GIN Index for Full-Text Search

```sql
-- Standard GIN index
CREATE INDEX idx_products_search_vector 
ON products USING GIN (search_vector);

-- GIN index with fast update
CREATE INDEX idx_products_search_vector_fast 
ON products USING GIN (search_vector) 
WITH (fastupdate = on);
```

### Partial Index for Active Products

```sql
CREATE INDEX idx_active_products_search 
ON products USING GIN (search_vector)
WHERE metadata->>'status' = 'active';
```

### Multi-Column Index

```sql
CREATE INDEX idx_products_search_brand 
ON products USING GIN (search_vector, (metadata->>'brand'));
```

## Advanced Search Patterns

### Weighted Search

```sql
-- Weight different fields differently
SELECT 
  id,
  name,
  metadata,
  ts_rank_cd(
    setweight(to_tsvector('english', name), 'A') ||
    setweight(to_tsvector('english', metadata->>'description'), 'B') ||
    setweight(to_tsvector('english', metadata->>'brand'), 'C'),
    query
  ) as rank
FROM products,
     websearch_to_tsquery('english', 'gaming laptop') query
WHERE (
  setweight(to_tsvector('english', name), 'A') ||
  setweight(to_tsvector('english', metadata->>'description'), 'B') ||
  setweight(to_tsvector('english', metadata->>'brand'), 'C')
) @@ query
ORDER BY rank DESC;
```

### Fuzzy Search with Trigrams

```sql
-- Enable pg_trgm extension
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create trigram index
CREATE INDEX idx_products_name_trgm 
ON products USING GIN (name gin_trgm_ops);

-- Fuzzy search
SELECT 
  name,
  similarity(name, 'gaming laptop') as sim
FROM products
WHERE name % 'gaming laptop'
ORDER BY sim DESC
LIMIT 10;

-- Combined full-text and fuzzy search
SELECT 
  id,
  name,
  metadata,
  GREATEST(
    ts_rank(search_vector, query),
    similarity(name, 'gaming laptop')
  ) as rank
FROM products,
     websearch_to_tsquery('english', 'gaming laptop') query
WHERE search_vector @@ query
   OR name % 'gaming laptop'
ORDER BY rank DESC;
```

### Multi-Language Search

```sql
-- Add language column
ALTER TABLE products ADD COLUMN language VARCHAR(10) DEFAULT 'english';

-- Create language-specific search vectors
ALTER TABLE products 
ADD COLUMN search_vector_en tsvector 
GENERATED ALWAYS AS (
  to_tsvector('english', coalesce(name, '') || ' ' || coalesce(metadata->>'description', ''))
) STORED;

ALTER TABLE products 
ADD COLUMN search_vector_es tsvector 
GENERATED ALWAYS AS (
  to_tsvector('spanish', coalesce(name, '') || ' ' || coalesce(metadata->>'description', ''))
) STORED;

-- Create indexes
CREATE INDEX idx_products_search_en ON products USING GIN (search_vector_en);
CREATE INDEX idx_products_search_es ON products USING GIN (search_vector_es);

-- Search with language detection
SELECT * FROM products
WHERE CASE language
  WHEN 'english' THEN search_vector_en @@ websearch_to_tsquery('english', 'laptop')
  WHEN 'spanish' THEN search_vector_es @@ websearch_to_tsquery('spanish', 'portátil')
END;
```

### Search with Synonyms

```sql
-- Create synonym dictionary
CREATE TEXT SEARCH DICTIONARY synonym_dict (
    TEMPLATE = synonym,
    SYNONYMS = my_synonyms
);

-- my_synonyms file content:
-- laptop, notebook, portable computer
-- phone, mobile, smartphone
-- tv, television

-- Create custom configuration
CREATE TEXT SEARCH CONFIGURATION custom_english (COPY = english);
ALTER TEXT SEARCH CONFIGURATION custom_english
    ALTER MAPPING FOR asciiword WITH synonym_dict, english_stem;

-- Use custom configuration
SELECT * FROM products
WHERE to_tsvector('custom_english', name || ' ' || metadata->>'description')
      @@ to_tsquery('custom_english', 'laptop');
```

## Performance Optimization

### Optimize Search Vector Updates

```sql
-- Use trigger for automatic updates
CREATE OR REPLACE FUNCTION products_search_vector_update()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector := to_tsvector('english',
    coalesce(NEW.name, '') || ' ' ||
    coalesce(NEW.metadata->>'description', '') || ' ' ||
    coalesce(NEW.metadata->>'brand', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER products_search_vector_trigger
BEFORE INSERT OR UPDATE ON products
FOR EACH ROW
EXECUTE FUNCTION products_search_vector_update();
```

### Batch Update Search Vectors

```php
class SearchVectorUpdater
{
    private PDO $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    public function updateAllSearchVectors(int $batchSize = 1000): void
    {
        $offset = 0;
        
        do {
            $stmt = $this->pdo->prepare("
                UPDATE products
                SET search_vector = to_tsvector('english',
                    coalesce(name, '') || ' ' ||
                    coalesce(metadata->>'description', '') || ' ' ||
                    coalesce(metadata->>'brand', '')
                )
                WHERE id IN (
                    SELECT id FROM products
                    ORDER BY id
                    LIMIT :limit OFFSET :offset
                )
            ");
            
            $stmt->bindValue(':limit', $batchSize, PDO::PARAM_INT);
            $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
            $stmt->execute();
            
            $updated = $stmt->rowCount();
            $offset += $batchSize;
            
            echo "Updated $updated products (offset: $offset)\n";
            
        } while ($updated > 0);
    }
}
```

### Search Performance Monitoring

```sql
-- Check index usage
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
WHERE indexname LIKE '%search%'
ORDER BY idx_scan DESC;

-- Analyze search query performance
EXPLAIN ANALYZE
SELECT * FROM products
WHERE search_vector @@ websearch_to_tsquery('english', 'gaming laptop')
ORDER BY ts_rank(search_vector, websearch_to_tsquery('english', 'gaming laptop')) DESC
LIMIT 20;
```

## Best Practices

1. **Use Generated Columns**
   - Automatic updates
   - Consistent search vectors
   - Reduced application logic

2. **Choose Right Index**
   - GIN for full-text search
   - GIN with trigrams for fuzzy search
   - Partial indexes for filtered data

3. **Optimize Search Vectors**
   - Include relevant fields only
   - Use appropriate weights
   - Consider language-specific configurations

4. **Cache Search Results**
   - Cache popular searches
   - Use Redis for autocomplete
   - Implement search result pagination

5. **Monitor Performance**
   - Track search query times
   - Monitor index usage
   - Analyze slow searches

6. **Handle Edge Cases**
   - Empty search queries
   - Special characters
   - Very long queries
   - No results found

7. **User Experience**
   - Provide autocomplete
   - Show search suggestions
   - Highlight matching terms
   - Display relevance scores
