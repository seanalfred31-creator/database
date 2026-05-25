# Performance Optimization Guide

Advanced techniques for optimizing PostgreSQL JSONB and connection pooling.

## JSONB Performance

### 1. Index Strategy

#### GIN Index (General Inverted Index)

Best for containment queries (`@>`, `?`, `?&`, `?|`):

```sql
-- Standard GIN index
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Query benefits
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';
SELECT * FROM products WHERE metadata ? 'discount';
```

#### GIN Index with jsonb_path_ops

Smaller and faster for simple containment:

```sql
-- More efficient for @> queries only
CREATE INDEX idx_products_metadata_path ON products 
USING GIN (metadata jsonb_path_ops);

-- Supports
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- Does NOT support
SELECT * FROM products WHERE metadata ? 'discount';  -- Won't use index
```

#### Expression Indexes

For frequently queried specific fields:

```sql
-- Index specific field
CREATE INDEX idx_products_brand ON products ((metadata->>'brand'));
CREATE INDEX idx_products_price ON products (((metadata->>'price')::numeric));

-- Queries use index
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
SELECT * FROM products WHERE (metadata->>'price')::numeric < 1000;
```

#### Partial Indexes

Index only relevant subset:

```sql
-- Index only active products
CREATE INDEX idx_active_products ON products USING GIN (metadata)
WHERE metadata->>'status' = 'active';

-- Index only premium products
CREATE INDEX idx_premium_products ON products (((metadata->>'price')::numeric))
WHERE (metadata->>'price')::numeric > 1000;
```

### 2. Query Optimization

#### Use Containment Operators

```sql
-- GOOD: Uses GIN index
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- BAD: Doesn't use GIN index efficiently
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
```

#### Avoid Function Calls in WHERE

```sql
-- BAD: Function prevents index usage
SELECT * FROM products WHERE LOWER(metadata->>'brand') = 'dell';

-- GOOD: Use expression index
CREATE INDEX idx_brand_lower ON products ((LOWER(metadata->>'brand')));
SELECT * FROM products WHERE LOWER(metadata->>'brand') = 'dell';
```

#### Batch Updates

```sql
-- BAD: Multiple round trips
UPDATE products SET metadata = jsonb_set(metadata, '{price}', '99.99') WHERE id = 'id1';
UPDATE products SET metadata = jsonb_set(metadata, '{price}', '99.99') WHERE id = 'id2';

-- GOOD: Single query
UPDATE products 
SET metadata = jsonb_set(metadata, '{price}', '99.99')
WHERE id IN ('id1', 'id2', 'id3');
```

### 3. Data Structure Optimization

#### Flatten When Possible

```sql
-- BAD: Deep nesting
{
  "product": {
    "details": {
      "pricing": {
        "amount": 99.99
      }
    }
  }
}

-- GOOD: Flatter structure
{
  "product_price": 99.99,
  "product_details": {...}
}
```

#### Normalize Large Arrays

```sql
-- BAD: Large array in JSONB
{
  "reviews": [
    {"user": "user1", "rating": 5, "comment": "..."},
    {"user": "user2", "rating": 4, "comment": "..."},
    // ... 1000 more reviews
  ]
}

-- GOOD: Separate table
CREATE TABLE product_reviews (
  product_id UUID REFERENCES products(id),
  user_id TEXT,
  rating INTEGER,
  comment TEXT
);
```

### 4. Monitoring Query Performance

```sql
-- Enable timing
\timing on

-- Analyze query plan
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- Check index usage
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes
WHERE tablename = 'products';

-- Find slow queries
SELECT 
  query,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_statements
WHERE query LIKE '%products%'
ORDER BY mean_time DESC
LIMIT 10;
```

## Connection Pooling Performance

### 1. Pool Sizing

#### Calculate Optimal Pool Size

```
Optimal Pool Size = ((core_count * 2) + effective_spindle_count)
```

For web applications:
```
Pool Size = (Number of CPU cores * 2) + 1
```

Example:
- 4 CPU cores
- Optimal pool: (4 * 2) + 1 = 9 connections

#### Monitor Pool Saturation

```sql
-- Check active connections
SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active';

-- Check connection states
SELECT state, COUNT(*) 
FROM pg_stat_activity 
GROUP BY state;

-- PgBouncer stats
SHOW POOLS;
SHOW CLIENTS;
```

### 2. PgBouncer Tuning

#### Transaction Mode (Recommended)

```ini
[pgbouncer]
pool_mode = transaction
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5

# Timeouts
server_idle_timeout = 600
server_lifetime = 3600
query_timeout = 0

# Performance
max_client_conn = 100
max_db_connections = 20
```

#### Session Mode (For Compatibility)

```ini
[pgbouncer]
pool_mode = session
default_pool_size = 10  # Lower than transaction mode
server_idle_timeout = 300
```

### 3. Application-Level Pooling

#### PHP (PDO)

```php
// Configure connection pool
$options = [
    PDO::ATTR_PERSISTENT => false,  // Let PgBouncer handle pooling
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_EMULATE_PREPARES => false,  // Use native prepared statements
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
];

// Connection timeout
$dsn = "pgsql:host=pgbouncer;port=6432;dbname=mydb;connect_timeout=5";
```

#### Ruby (Sequel)

```ruby
DB = Sequel.connect(
  'postgresql://user:pass@pgbouncer:6432/mydb',
  max_connections: 20,
  pool_timeout: 5,
  connect_timeout: 5,
  keepalives: 1,
  keepalives_idle: 30,
  keepalives_interval: 10,
  keepalives_count: 3
)
```

### 4. Connection Leak Prevention

#### Automatic Cleanup

```php
// PHP: Use try-finally
try {
    $pdo->beginTransaction();
    // ... operations ...
    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    throw $e;
} finally {
    // Connection returned to pool automatically
}
```

```ruby
# Ruby: Use block syntax
DB.transaction do
  # ... operations ...
  # Connection automatically returned
end
```

#### Monitor Leaks

```sql
-- Long-running connections
SELECT 
  pid,
  usename,
  application_name,
  client_addr,
  state,
  now() - state_change as duration
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;

-- Kill long-running query
SELECT pg_terminate_backend(pid);
```

## Benchmarking

### 1. JSONB Query Benchmarks

```sql
-- Create test data
INSERT INTO products (name, metadata)
SELECT 
  'Product ' || i,
  jsonb_build_object(
    'brand', 'Brand' || (i % 10),
    'price', (random() * 1000)::numeric(10,2),
    'tags', jsonb_build_array('tag' || (i % 5))
  )
FROM generate_series(1, 100000) i;

-- Benchmark containment query
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata @> '{"brand": "Brand5"}';

-- Benchmark extraction query
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata->>'brand' = 'Brand5';

-- Compare with index
CREATE INDEX idx_test ON products USING GIN (metadata);
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata @> '{"brand": "Brand5"}';
```

### 2. Connection Pool Benchmarks

```bash
# Apache Bench - Direct connection
ab -n 1000 -c 10 http://localhost:8000/products/brand/Dell

# Apache Bench - Pooled connection
ab -n 1000 -c 50 http://localhost:8000/products/brand/Dell

# Monitor during test
watch -n 1 'psql -h pgbouncer -p 6432 -U user -c "SHOW POOLS" pgbouncer'
```

## Best Practices Summary

1. **Indexing**
   - Use GIN indexes for JSONB containment queries
   - Create expression indexes for frequently queried fields
   - Use partial indexes to reduce index size

2. **Queries**
   - Prefer `@>` over `->>` for indexed queries
   - Avoid function calls in WHERE clauses
   - Batch operations when possible

3. **Connection Pooling**
   - Use transaction mode for web apps
   - Size pools based on CPU cores
   - Monitor for saturation and leaks

4. **Monitoring**
   - Track query performance with EXPLAIN ANALYZE
   - Monitor index usage
   - Watch connection pool statistics

5. **Testing**
   - Benchmark with realistic data volumes
   - Test under concurrent load
   - Profile both queries and connections
