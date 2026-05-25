# PostgreSQL Advanced Features - Quick Reference

One-page cheat sheet for common operations.

## JSONB Operators

```sql
-- Extraction
metadata->'key'           -- Get JSON object (returns JSON)
metadata->>'key'          -- Get JSON object (returns text)
metadata->'a'->'b'        -- Nested access
metadata#>'{a,b,c}'       -- Path access (JSON)
metadata#>>'{a,b,c}'      -- Path access (text)

-- Containment
metadata @> '{"key":"val"}'     -- Contains
metadata <@ '{"key":"val"}'     -- Contained by
metadata->'tags' @> '["tag"]'   -- Array contains

-- Existence
metadata ? 'key'                -- Key exists
metadata ?& array['k1','k2']    -- All keys exist
metadata ?| array['k1','k2']    -- Any key exists

-- Modification
metadata || '{"new":"val"}'     -- Concatenate/merge
metadata - 'key'                -- Remove key
metadata #- '{path,to,key}'     -- Remove path
```

## JSONB Functions

```sql
-- Update
jsonb_set(target, '{path}', '"value"'::jsonb)
jsonb_insert(target, '{path}', '"value"'::jsonb)

-- Build
jsonb_build_object('k1', v1, 'k2', v2)
jsonb_build_array(v1, v2, v3)

-- Extract
jsonb_array_elements(jsonb_array)
jsonb_array_elements_text(jsonb_array)
jsonb_object_keys(jsonb_object)
jsonb_each(jsonb_object)
jsonb_each_text(jsonb_object)

-- Type
jsonb_typeof(jsonb_value)  -- Returns: object, array, string, number, boolean, null
```

## Common JSONB Queries

```sql
-- Find by exact match
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- Find by nested field
SELECT * FROM products WHERE metadata->'specs'->>'cpu' = 'i7';

-- Find by array element
SELECT * FROM products WHERE metadata->'tags' @> '["electronics"]';

-- Find by price range
SELECT * FROM products 
WHERE (metadata->>'price')::numeric BETWEEN 500 AND 1000;

-- Update nested value
UPDATE products 
SET metadata = jsonb_set(metadata, '{price}', '999.99'::jsonb)
WHERE id = 'some-id';

-- Add new key
UPDATE products 
SET metadata = metadata || '{"discount": 10}'::jsonb
WHERE metadata->>'brand' = 'Dell';

-- Remove key
UPDATE products 
SET metadata = metadata - 'discount'
WHERE metadata ? 'discount';

-- Get all unique values
SELECT DISTINCT metadata->>'brand' as brand FROM products;

-- Aggregate
SELECT 
  metadata->>'brand' as brand,
  COUNT(*) as count,
  AVG((metadata->>'price')::numeric) as avg_price
FROM products
GROUP BY metadata->>'brand';
```

## Indexing

```sql
-- GIN index (general)
CREATE INDEX idx_metadata ON products USING GIN (metadata);

-- GIN index (path ops - smaller, faster for @> only)
CREATE INDEX idx_metadata ON products USING GIN (metadata jsonb_path_ops);

-- Expression index (specific field)
CREATE INDEX idx_brand ON products ((metadata->>'brand'));
CREATE INDEX idx_price ON products (((metadata->>'price')::numeric));

-- Partial index
CREATE INDEX idx_active ON products USING GIN (metadata)
WHERE metadata->>'status' = 'active';

-- Composite index
CREATE INDEX idx_brand_price ON products 
((metadata->>'brand'), ((metadata->>'price')::numeric));
```

## Connection Pooling (PgBouncer)

```ini
# Basic Configuration
[databases]
mydb = host=localhost port=5432 dbname=mydb

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
pool_mode = transaction
max_client_conn = 100
default_pool_size = 25
```

```bash
# Admin Commands
psql -h localhost -p 6432 -U user pgbouncer

SHOW POOLS;           # Pool statistics
SHOW CLIENTS;         # Client connections
SHOW SERVERS;         # Server connections
SHOW DATABASES;       # Database configuration
SHOW CONFIG;          # Configuration
RELOAD;               # Reload config
PAUSE;                # Pause all pools
RESUME;               # Resume all pools
```

## PHP Quick Reference

```php
// PDO Connection
$pdo = new PDO(
    "pgsql:host=localhost;port=5432;dbname=mydb",
    "user",
    "password",
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

// JSONB Query
$stmt = $pdo->prepare("SELECT * FROM products WHERE metadata @> ?::jsonb");
$stmt->execute([json_encode(['brand' => 'Dell'])]);
$products = $stmt->fetchAll(PDO::FETCH_ASSOC);

// JSONB Update
$stmt = $pdo->prepare("
    UPDATE products 
    SET metadata = jsonb_set(metadata, '{price}', ?::jsonb)
    WHERE id = ?
");
$stmt->execute([json_encode(999.99), $id]);

// Laravel Eloquent
Product::whereRaw("metadata->>'brand' = ?", ['Dell'])->get();
Product::whereRaw("metadata @> ?::jsonb", [json_encode(['brand' => 'Dell'])])->get();
```

## Ruby Quick Reference

```ruby
# Sequel Connection
DB = Sequel.connect('postgresql://user:pass@localhost/mydb')

# JSONB Query
products = DB[:products]
  .where(Sequel.lit("metadata @> ?::jsonb", {brand: 'Dell'}.to_json))
  .all

# JSONB Update
DB[:products]
  .where(id: id)
  .update(Sequel.lit("metadata = jsonb_set(metadata, '{price}', ?::jsonb)", 999.99.to_json))

# ActiveRecord
Product.where("metadata->>'brand' = ?", 'Dell')
Product.where("metadata @> ?::jsonb", {brand: 'Dell'}.to_json)
```

## Performance Optimization

```sql
-- Analyze query
EXPLAIN ANALYZE SELECT * FROM products WHERE metadata->>'brand' = 'Dell';

-- Update statistics
ANALYZE products;

-- Rebuild index
REINDEX INDEX idx_metadata;

-- Check index usage
SELECT 
  schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE tablename = 'products'
ORDER BY idx_scan DESC;

-- Check cache hit ratio
SELECT 
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as cache_hit_ratio
FROM pg_statio_user_tables;

-- Find slow queries
SELECT 
  query, calls, mean_time, max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

## Monitoring Queries

```sql
-- Active connections
SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active';

-- Long-running queries
SELECT 
  pid, now() - query_start as duration, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '5 seconds'
ORDER BY duration DESC;

-- Database size
SELECT pg_size_pretty(pg_database_size('mydb'));

-- Table sizes
SELECT 
  tablename,
  pg_size_pretty(pg_total_relation_size(tablename::regclass)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(tablename::regclass) DESC;

-- Kill query
SELECT pg_terminate_backend(pid);
```

## Common Patterns

### N+1 Query Prevention

```php
// Bad
$products = $pdo->query("SELECT * FROM products")->fetchAll();
foreach ($products as $product) {
    $brand = json_decode($product['metadata'], true)['brand'];
}

// Good
$products = $pdo->query("
    SELECT id, name, metadata->>'brand' as brand 
    FROM products
")->fetchAll();
```

### Batch Operations

```php
// Batch insert
$stmt = $pdo->prepare("INSERT INTO products (name, metadata) VALUES (?, ?::jsonb)");
foreach ($products as $product) {
    $stmt->execute([$product['name'], json_encode($product['metadata'])]);
}

// Better: Single query
$values = [];
$params = [];
foreach ($products as $product) {
    $values[] = "(?, ?::jsonb)";
    $params[] = $product['name'];
    $params[] = json_encode($product['metadata']);
}
$sql = "INSERT INTO products (name, metadata) VALUES " . implode(', ', $values);
$pdo->prepare($sql)->execute($params);
```

### Caching Pattern

```php
$cacheKey = "products:brand:$brand";
$products = $redis->get($cacheKey);

if (!$products) {
    $stmt = $pdo->prepare("SELECT * FROM products WHERE metadata->>'brand' = ?");
    $stmt->execute([$brand]);
    $products = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $redis->setex($cacheKey, 3600, json_encode($products));
} else {
    $products = json_decode($products, true);
}
```

## Docker Commands

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f postgres
docker-compose logs -f pgbouncer

# Execute SQL
docker-compose exec postgres psql -U user -d mydb

# Backup database
docker-compose exec postgres pg_dump -U user mydb > backup.sql

# Restore database
docker-compose exec -T postgres psql -U user mydb < backup.sql

# Stop services
docker-compose down

# Remove volumes
docker-compose down -v
```

## Useful psql Commands

```sql
\l                  -- List databases
\c dbname           -- Connect to database
\dt                 -- List tables
\d tablename        -- Describe table
\di                 -- List indexes
\df                 -- List functions
\du                 -- List users
\timing on          -- Enable query timing
\x                  -- Toggle expanded output
\q                  -- Quit
```

## Environment Variables

```bash
# PostgreSQL
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=mydb
export PGUSER=user
export PGPASSWORD=password

# Connection string
export DATABASE_URL="postgresql://user:pass@localhost:5432/mydb"

# PgBouncer
export PGBOUNCER_HOST=localhost
export PGBOUNCER_PORT=6432
```

## Testing

```bash
# PHP
vendor/bin/phpunit
vendor/bin/phpunit --filter testName

# Ruby
bundle exec rspec
bundle exec rspec spec/models/product_spec.rb

# Load testing
ab -n 1000 -c 10 http://localhost:8000/products
```

## Troubleshooting

```sql
-- Check locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Check blocking queries
SELECT 
  blocked.pid AS blocked_pid,
  blocking.pid AS blocking_pid,
  blocked.query AS blocked_query,
  blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking 
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));

-- Check replication lag
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;

-- Vacuum analyze
VACUUM ANALYZE products;

-- Check table bloat
SELECT 
  schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
  n_dead_tup
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

## Quick Links

- [Full JSONB Guide](docs/jsonb-guide.md)
- [Connection Pooling Guide](docs/connection-pooling-guide.md)
- [Performance Optimization](docs/performance-optimization.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Module Index](MODULE-INDEX.md)
