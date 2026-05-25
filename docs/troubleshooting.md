# Troubleshooting Guide

Common issues and solutions for PostgreSQL JSONB and connection pooling.

## JSONB Issues

### Issue: Query Not Using Index

**Symptom:**
```sql
EXPLAIN ANALYZE SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
-- Shows Seq Scan instead of Index Scan
```

**Diagnosis:**
```sql
-- Check if index exists
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'products';

-- Check index usage
SELECT idx_scan, idx_tup_read 
FROM pg_stat_user_indexes 
WHERE indexrelname = 'idx_products_metadata';
```

**Solutions:**

1. Create appropriate index:
```sql
-- For ->> queries
CREATE INDEX idx_products_brand ON products ((metadata->>'brand'));

-- For @> queries
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);
```

2. Rewrite query to use containment:
```sql
-- Instead of
WHERE metadata->>'brand' = 'Dell'

-- Use
WHERE metadata @> '{"brand": "Dell"}'
```

3. Update statistics:
```sql
ANALYZE products;
```

### Issue: Invalid JSONB Syntax

**Symptom:**
```
ERROR: invalid input syntax for type json
```

**Solutions:**

1. Validate JSON before insert:
```php
$json = json_encode($data);
if (json_last_error() !== JSON_ERROR_NONE) {
    throw new Exception('Invalid JSON: ' . json_last_error_msg());
}
```

2. Use proper casting:
```sql
-- Correct
INSERT INTO products (metadata) VALUES ('{"key": "value"}'::jsonb);

-- Incorrect
INSERT INTO products (metadata) VALUES ('{"key": "value"}');
```

3. Handle special characters:
```php
$data = [
    'description' => "Product with \"quotes\" and \n newlines"
];
$json = json_encode($data, JSON_UNESCAPED_SLASHES);
```

### Issue: Slow JSONB Updates

**Symptom:**
Updates taking several seconds on large JSONB documents.

**Solutions:**

1. Use jsonb_set instead of full replacement:
```sql
-- Slow
UPDATE products SET metadata = '{"brand": "Dell", ...entire object...}';

-- Fast
UPDATE products SET metadata = jsonb_set(metadata, '{brand}', '"Dell"');
```

2. Batch updates:
```sql
-- Instead of multiple updates
UPDATE products SET metadata = jsonb_set(metadata, '{price}', '99.99') WHERE id = 'id1';
UPDATE products SET metadata = jsonb_set(metadata, '{price}', '99.99') WHERE id = 'id2';

-- Use single query
UPDATE products 
SET metadata = jsonb_set(metadata, '{price}', '99.99')
WHERE id IN ('id1', 'id2', 'id3');
```

3. Consider normalization for frequently updated fields:
```sql
-- Instead of updating JSONB
ALTER TABLE products ADD COLUMN price NUMERIC(10,2);
CREATE INDEX idx_products_price ON products(price);
```

### Issue: JSONB Size Limits

**Symptom:**
```
ERROR: string too long for tsvector
```

**Solutions:**

1. Check document size:
```sql
SELECT 
  id,
  pg_column_size(metadata) as size_bytes,
  pg_size_pretty(pg_column_size(metadata)) as size_pretty
FROM products
ORDER BY pg_column_size(metadata) DESC
LIMIT 10;
```

2. Split large documents:
```sql
-- Instead of storing large array in JSONB
CREATE TABLE product_reviews (
  product_id UUID REFERENCES products(id),
  review_data JSONB
);
```

3. Use TOAST compression:
```sql
-- PostgreSQL automatically compresses large JSONB
-- Check compression:
SELECT 
  attname,
  attstorage
FROM pg_attribute
WHERE attrelid = 'products'::regclass
  AND attname = 'metadata';
```

## Connection Pooling Issues

### Issue: Connection Pool Exhausted

**Symptom:**
```
FATAL: sorry, too many clients already
```

**Diagnosis:**
```sql
-- Check current connections
SELECT COUNT(*) FROM pg_stat_activity;

-- Check by state
SELECT state, COUNT(*) 
FROM pg_stat_activity 
GROUP BY state;

-- PgBouncer stats
SHOW POOLS;
SHOW CLIENTS;
```

**Solutions:**

1. Increase pool size:
```ini
# pgbouncer.ini
default_pool_size = 25  # Increase from 20
max_client_conn = 150   # Increase from 100
```

2. Fix connection leaks:
```php
// Always close connections
try {
    $pdo->beginTransaction();
    // ... operations ...
    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    throw $e;
} finally {
    $pdo = null;  // Release connection
}
```

3. Implement connection timeout:
```php
$dsn = "pgsql:host=pgbouncer;port=6432;dbname=mydb;connect_timeout=5";
```

### Issue: Prepared Statement Errors with PgBouncer

**Symptom:**
```
ERROR: prepared statement "pdo_stmt_xxx" does not exist
```

**Cause:**
Transaction mode clears prepared statements after each transaction.

**Solutions:**

1. Use session mode (if needed):
```ini
# pgbouncer.ini
pool_mode = session
```

2. Disable persistent prepared statements:
```php
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_EMULATE_PREPARES => false,
    PDO::ATTR_PERSISTENT => false
]);
```

3. Prepare statements within transaction:
```php
$pdo->beginTransaction();
$stmt = $pdo->prepare("SELECT * FROM products WHERE id = ?");
$stmt->execute([$id]);
$pdo->commit();
```

### Issue: Slow Connection Establishment

**Symptom:**
First query takes 500ms+, subsequent queries are fast.

**Diagnosis:**
```bash
# Test connection time
time psql -h pgbouncer -p 6432 -U user -c "SELECT 1"
```

**Solutions:**

1. Use connection pooling (PgBouncer):
```yaml
# docker-compose.yml
pgbouncer:
  environment:
    POOL_MODE: transaction
    DEFAULT_POOL_SIZE: 20
```

2. Enable keepalive:
```php
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_PERSISTENT => false,
    PDO::PGSQL_ATTR_DISABLE_PREPARES => false
]);
```

3. Warm up pool:
```php
// On application start
for ($i = 0; $i < 5; $i++) {
    $pdo->query("SELECT 1");
}
```

### Issue: Connection Timeouts

**Symptom:**
```
FATAL: query_wait_timeout
```

**Solutions:**

1. Increase timeout:
```ini
# pgbouncer.ini
query_timeout = 30
query_wait_timeout = 120
```

2. Optimize slow queries:
```sql
-- Find slow queries
SELECT 
  query,
  mean_time,
  calls
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

3. Add query timeout in application:
```php
$pdo->setAttribute(PDO::ATTR_TIMEOUT, 30);
```

## Performance Issues

### Issue: High CPU Usage

**Diagnosis:**
```sql
-- Find expensive queries
SELECT 
  query,
  calls,
  total_time,
  mean_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Check for missing indexes
SELECT 
  schemaname,
  tablename,
  attname,
  n_distinct,
  correlation
FROM pg_stats
WHERE tablename = 'products';
```

**Solutions:**

1. Add missing indexes
2. Optimize queries
3. Use connection pooling
4. Consider read replicas

### Issue: High Memory Usage

**Diagnosis:**
```sql
-- Check table sizes
SELECT 
  tablename,
  pg_size_pretty(pg_total_relation_size(tablename::regclass)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(tablename::regclass) DESC;

-- Check JSONB sizes
SELECT 
  pg_size_pretty(SUM(pg_column_size(metadata))) as total_jsonb_size
FROM products;
```

**Solutions:**

1. Archive old data
2. Normalize large JSONB documents
3. Use partitioning
4. Increase shared_buffers

## Debugging Tools

### Enable Query Logging

```sql
-- Log slow queries
ALTER DATABASE mydb SET log_min_duration_statement = 1000;

-- Log all queries
ALTER DATABASE mydb SET log_statement = 'all';
```

### Monitor in Real-Time

```bash
# Watch active queries
watch -n 1 'psql -c "SELECT pid, state, query FROM pg_stat_activity WHERE state != '\''idle'\'';"'

# Watch PgBouncer
watch -n 1 'psql -h pgbouncer -p 6432 -U user -c "SHOW POOLS" pgbouncer'
```

### Analyze Query Plans

```sql
-- Basic explain
EXPLAIN SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- With execution stats
EXPLAIN ANALYZE SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- With buffers
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';
```

## Getting Help

1. Check PostgreSQL logs:
```bash
docker-compose logs postgres
```

2. Check PgBouncer logs:
```bash
docker-compose logs pgbouncer
```

3. Enable verbose error reporting:
```php
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
```

4. Use PostgreSQL's auto_explain:
```sql
LOAD 'auto_explain';
SET auto_explain.log_min_duration = 1000;
```
