# JSONB Operations Guide

PostgreSQL's JSONB type provides efficient storage and querying of JSON data with indexing support.

## Why JSONB?

- Binary storage format (faster than JSON)
- Supports indexing (GIN indexes)
- Rich set of operators and functions
- Schema flexibility with SQL power

## Common Operators

### Extraction Operators

```sql
-- Extract as JSON (returns JSON type)
SELECT metadata->'brand' FROM products;

-- Extract as text (returns text type)
SELECT metadata->>'brand' FROM products;

-- Extract nested field
SELECT metadata->'specs'->'cpu' FROM products;
SELECT metadata->'specs'->>'cpu' FROM products;

-- Extract array element
SELECT metadata->'tags'->0 FROM products;
```

### Containment Operators

```sql
-- Does left contain right?
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- Does right contain left?
SELECT * FROM products WHERE '{"brand": "Dell"}' <@ metadata;

-- Array containment
SELECT * FROM products WHERE metadata->'tags' @> '["electronics"]';
```

### Modification Operators

```sql
-- Concatenate/merge
UPDATE products SET metadata = metadata || '{"discount": 10}';

-- Remove key
UPDATE products SET metadata = metadata - 'discount';

-- Remove multiple keys
UPDATE products SET metadata = metadata - ARRAY['discount', 'old_price'];
```

## Essential Functions

### jsonb_set()

Update nested values:

```sql
-- Update price
UPDATE products 
SET metadata = jsonb_set(metadata, '{price}', '999.99'::jsonb)
WHERE id = 'some-uuid';

-- Update nested value
UPDATE products 
SET metadata = jsonb_set(metadata, '{specs,ram}', '"32GB"'::jsonb)
WHERE id = 'some-uuid';

-- Create missing keys (4th parameter = true)
UPDATE products 
SET metadata = jsonb_set(metadata, '{warranty}', '"2 years"'::jsonb, true)
WHERE id = 'some-uuid';
```

### jsonb_insert()

Insert values at specific positions:

```sql
-- Insert into array
UPDATE products 
SET metadata = jsonb_insert(metadata, '{tags,0}', '"featured"'::jsonb)
WHERE id = 'some-uuid';
```

### jsonb_array_elements()

Expand JSONB array to rows:

```sql
-- Get all tags as separate rows
SELECT jsonb_array_elements_text(metadata->'tags') as tag
FROM products;

-- Count products per tag
SELECT tag, COUNT(*) 
FROM products, jsonb_array_elements_text(metadata->'tags') as tag
GROUP BY tag;
```

## Indexing Strategies

### GIN Index (Recommended)

```sql
-- Index entire JSONB column
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Query benefits from index
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';
```

### Expression Index

```sql
-- Index specific field
CREATE INDEX idx_products_brand ON products ((metadata->>'brand'));

-- Query uses index
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
```

### Partial Index

```sql
-- Index only active products
CREATE INDEX idx_active_products ON products USING GIN (metadata)
WHERE metadata->>'status' = 'active';
```

## Performance Tips

1. Use `@>` for containment queries (uses GIN index)
2. Cast to numeric for price comparisons: `(metadata->>'price')::numeric`
3. Use `->>` for text extraction, `->` for JSON extraction
4. Create expression indexes for frequently queried fields
5. Use `jsonb_set()` instead of full object replacement

## Common Patterns

### Search by Multiple Criteria

```sql
SELECT * FROM products
WHERE metadata @> '{"brand": "Dell"}'
  AND (metadata->>'price')::numeric < 1000
  AND metadata->'tags' @> '["electronics"]';
```

### Aggregate JSONB Data

```sql
SELECT 
  metadata->>'brand' as brand,
  COUNT(*) as product_count,
  AVG((metadata->>'price')::numeric) as avg_price
FROM products
GROUP BY metadata->>'brand';
```

### Update Multiple Fields

```sql
UPDATE products
SET metadata = metadata 
  || '{"discount": 10}'::jsonb
  || '{"updated_at": "2024-03-01"}'::jsonb
WHERE metadata->>'brand' = 'Dell';
```

### Conditional Updates

```sql
UPDATE products
SET metadata = CASE
  WHEN (metadata->>'price')::numeric > 1000 
  THEN metadata || '{"premium": true}'::jsonb
  ELSE metadata || '{"premium": false}'::jsonb
END;
```
