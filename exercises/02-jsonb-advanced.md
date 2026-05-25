# Exercise 2: Advanced JSONB Operations

Practice complex JSONB queries and aggregations.

## Tasks

### 1. Extract All Unique Tags

Get a list of all unique tags across all products.

<details>
<summary>Solution</summary>

```sql
SELECT DISTINCT jsonb_array_elements_text(metadata->'tags') as tag
FROM products
ORDER BY tag;
```

Ruby API:
```bash
curl http://localhost:3000/products/tags
```
</details>

### 2. Count Products Per Brand

Aggregate products by brand with counts.

<details>
<summary>Solution</summary>

```sql
SELECT 
  metadata->>'brand' as brand,
  COUNT(*) as product_count
FROM products
GROUP BY metadata->>'brand'
ORDER BY product_count DESC;
```
</details>

### 3. Calculate Price Statistics

Get min, max, and average prices.

<details>
<summary>Solution</summary>

```sql
SELECT 
  COUNT(*) as total_products,
  MIN((metadata->>'price')::numeric) as min_price,
  MAX((metadata->>'price')::numeric) as max_price,
  AVG((metadata->>'price')::numeric) as avg_price
FROM products;
```

Ruby API:
```bash
curl http://localhost:3000/products/stats
```
</details>

### 4. Products Per Tag

Count how many products have each tag.

<details>
<summary>Solution</summary>

```sql
SELECT 
  tag,
  COUNT(*) as product_count
FROM products,
  jsonb_array_elements_text(metadata->'tags') as tag
GROUP BY tag
ORDER BY product_count DESC;
```
</details>

### 5. Update Nested Specs

Update the RAM specification for a laptop.

<details>
<summary>Solution</summary>

```sql
UPDATE products
SET metadata = jsonb_set(
  metadata, 
  '{specs,ram}', 
  '"32GB"'::jsonb
)
WHERE name = 'Laptop';
```
</details>

### 6. Conditional Bulk Update

Add "premium" flag to products over $800.

<details>
<summary>Solution</summary>

```sql
UPDATE products
SET metadata = metadata || '{"premium": true}'::jsonb
WHERE (metadata->>'price')::numeric > 800;
```
</details>

### 7. Complex Search

Find products that:
- Are from Apple OR Sony
- Cost less than $1000
- Have "electronics" tag

<details>
<summary>Solution</summary>

```sql
SELECT * FROM products
WHERE metadata->>'brand' IN ('Apple', 'Sony')
  AND (metadata->>'price')::numeric < 1000
  AND metadata->'tags' @> '["electronics"]'::jsonb;
```
</details>

## Challenge

Create a query that generates a product summary report:
- Brand name
- Number of products
- Average price
- Price range (min-max)
- All tags used by that brand

<details>
<summary>Solution</summary>

```sql
SELECT 
  metadata->>'brand' as brand,
  COUNT(*) as product_count,
  ROUND(AVG((metadata->>'price')::numeric), 2) as avg_price,
  MIN((metadata->>'price')::numeric) as min_price,
  MAX((metadata->>'price')::numeric) as max_price,
  jsonb_agg(DISTINCT tag) as all_tags
FROM products,
  jsonb_array_elements_text(metadata->'tags') as tag
GROUP BY metadata->>'brand'
ORDER BY product_count DESC;
```
</details>
