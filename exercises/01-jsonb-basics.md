# Exercise 1: JSONB Basics

Practice fundamental JSONB operations.

## Setup

Start either PHP or Ruby implementation:

```bash
cd php-implementation  # or ruby-implementation
docker-compose up -d
```

## Tasks

### 1. Query Products by Brand

Write a query to find all products from "Sony".

<details>
<summary>Solution</summary>

```sql
SELECT * FROM products WHERE metadata->>'brand' = 'Sony';
```

API:
```bash
curl http://localhost:8000/products/brand/Sony
```
</details>

### 2. Find Products by Price Range

Find all products between $200 and $500.

<details>
<summary>Solution</summary>

```sql
SELECT * FROM products 
WHERE (metadata->>'price')::numeric BETWEEN 200 AND 500;
```

API:
```bash
curl "http://localhost:8000/products/search?min_price=200&max_price=500"
```
</details>

### 3. Query Nested Fields

Find all products with "wireless" type in specs.

<details>
<summary>Solution</summary>

```sql
SELECT * FROM products 
WHERE metadata->'specs'->>'type' = 'wireless';
```
</details>

### 4. Array Containment

Find products tagged with "audio".

<details>
<summary>Solution</summary>

```sql
SELECT * FROM products 
WHERE metadata->'tags' @> '["audio"]'::jsonb;
```

API:
```bash
curl http://localhost:8000/products/tag/audio
```
</details>

### 5. Update Product Price

Update the price of a product to $349.99.

<details>
<summary>Solution</summary>

```sql
UPDATE products 
SET metadata = jsonb_set(metadata, '{price}', '349.99'::jsonb)
WHERE name = 'Headphones';
```
</details>

### 6. Add Discount Field

Add a 15% discount to all electronics.

<details>
<summary>Solution</summary>

```sql
UPDATE products 
SET metadata = metadata || '{"discount": 15}'::jsonb
WHERE metadata->'tags' @> '["electronics"]'::jsonb;
```
</details>

## Challenge

Create a query that:
1. Finds products with price > $500
2. Tagged with "electronics"
3. Returns only name, brand, and price
4. Orders by price descending

<details>
<summary>Solution</summary>

```sql
SELECT 
  name,
  metadata->>'brand' as brand,
  (metadata->>'price')::numeric as price
FROM products
WHERE (metadata->>'price')::numeric > 500
  AND metadata->'tags' @> '["electronics"]'::jsonb
ORDER BY (metadata->>'price')::numeric DESC;
```
</details>
