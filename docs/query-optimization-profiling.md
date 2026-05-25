# Query Optimization and Profiling Guide

Master PostgreSQL query optimization with JSONB and connection pooling.

## Table of Contents

1. [EXPLAIN Analysis](#explain-analysis)
2. [JSONB Query Optimization](#jsonb-query-optimization)
3. [Index Strategies](#index-strategies)
4. [Query Profiling Tools](#query-profiling-tools)
5. [Performance Monitoring](#performance-monitoring)
6. [Common Anti-Patterns](#common-anti-patterns)

## EXPLAIN Analysis

### Basic EXPLAIN

```sql
EXPLAIN SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
```

Output:
```
Seq Scan on products  (cost=0.00..25.88 rows=6 width=1234)
  Filter: ((metadata ->> 'brand'::text) = 'Dell'::text)
```

### EXPLAIN ANALYZE

```sql
EXPLAIN ANALYZE SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
```

Output:
```
Seq Scan on products  (cost=0.00..25.88 rows=6 width=1234) 
                      (actual time=0.012..0.234 rows=5 loops=1)
  Filter: ((metadata ->> 'brand'::text) = 'Dell'::text)
  Rows Removed by Filter: 95
Planning Time: 0.123 ms
Execution Time: 0.267 ms
```

### EXPLAIN with BUFFERS

```sql
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';
```

Output shows:
- Shared blocks hit/read
- Temp blocks read/written
- I/O timing

### Reading EXPLAIN Output

**Key Metrics:**

1. **Cost**: Estimated startup and total cost
   - Lower is better
   - Relative, not absolute

2. **Rows**: Estimated vs actual rows
   - Large difference = outdated statistics

3. **Width**: Average row size in bytes

4. **Actual Time**: Real execution time
   - startup time..total time

5. **Loops**: Number of times node executed

**Node Types:**

- **Seq Scan**: Full table scan (slow for large tables)
- **Index Scan**: Uses index (fast)
- **Index Only Scan**: Uses index without table access (fastest)
- **Bitmap Index Scan**: Multiple index scan
- **Nested Loop**: Join algorithm
- **Hash Join**: Join using hash table
- **Sort**: Sorting operation

## JSONB Query Optimization

### Problem: Slow JSONB Extraction

```sql
-- SLOW: Sequential scan
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';

-- Result: Seq Scan (cost=0.00..25.88)
```

### Solution 1: GIN Index

```sql
-- Create GIN index
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Now uses index
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';

-- Result: Bitmap Index Scan (cost=4.50..12.34)
```

### Solution 2: Expression Index

```sql
-- Create expression index
CREATE INDEX idx_products_brand ON products ((metadata->>'brand'));

-- Now uses index
EXPLAIN ANALYZE
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';

-- Result: Index Scan using idx_products_brand (cost=0.15..8.17)
```

### Comparison

```sql
-- Test query performance
\timing on

-- Without index
SELECT COUNT(*) FROM products WHERE metadata->>'brand' = 'Dell';
-- Time: 45.234 ms

-- With GIN index
SELECT COUNT(*) FROM products WHERE metadata @> '{"brand": "Dell"}';
-- Time: 2.156 ms

-- With expression index
SELECT COUNT(*) FROM products WHERE metadata->>'brand' = 'Dell';
-- Time: 1.234 ms
```

### Nested JSONB Queries

```sql
-- SLOW: No index on nested field
SELECT * FROM products WHERE metadata->'specs'->>'cpu' = 'i7';

-- Create expression index for nested field
CREATE INDEX idx_products_cpu ON products ((metadata->'specs'->>'cpu'));

-- Now fast
SELECT * FROM products WHERE metadata->'specs'->>'cpu' = 'i7';
```

### Array Containment

```sql
-- SLOW without index
SELECT * FROM products WHERE metadata->'tags' @> '["electronics"]';

-- GIN index helps
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Now fast
SELECT * FROM products WHERE metadata->'tags' @> '["electronics"]';
```

## Index Strategies

### GIN Index (General Inverted Index)

**Best for:**
- Containment queries (`@>`, `<@`)
- Existence queries (`?`, `?&`, `?|`)
- Full JSONB column indexing

```sql
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Supports these queries:
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';
SELECT * FROM products WHERE metadata ? 'discount';
SELECT * FROM products WHERE metadata ?& array['brand', 'price'];
```

**Size:** Larger than B-tree, smaller than jsonb_path_ops

### GIN with jsonb_path_ops

**Best for:**
- Only containment queries (`@>`)
- Smaller index size
- Faster updates

```sql
CREATE INDEX idx_products_metadata_path 
ON products USING GIN (metadata jsonb_path_ops);

-- Only supports @> operator
SELECT * FROM products WHERE metadata @> '{"brand": "Dell"}';
```

**Size:** ~30% smaller than standard GIN

### Expression Indexes

**Best for:**
- Specific field queries
- Frequently queried fields
- Type casting

```sql
-- Text field
CREATE INDEX idx_products_brand ON products ((metadata->>'brand'));

-- Numeric field with casting
CREATE INDEX idx_products_price ON products (((metadata->>'price')::numeric));

-- Nested field
CREATE INDEX idx_products_cpu ON products ((metadata->'specs'->>'cpu'));
```

### Partial Indexes

**Best for:**
- Filtering subset of data
- Reducing index size
- Conditional queries

```sql
-- Index only active products
CREATE INDEX idx_active_products ON products USING GIN (metadata)
WHERE metadata->>'status' = 'active';

-- Index only premium products
CREATE INDEX idx_premium_products ON products (((metadata->>'price')::numeric))
WHERE (metadata->>'price')::numeric > 1000;

-- Index only products with discount
CREATE INDEX idx_discounted_products ON products USING GIN (metadata)
WHERE metadata ? 'discount';
```

### Composite Indexes

```sql
-- Multiple fields
CREATE INDEX idx_products_brand_price 
ON products ((metadata->>'brand'), ((metadata->>'price')::numeric));

-- Query must match index order
SELECT * FROM products 
WHERE metadata->>'brand' = 'Dell' 
  AND (metadata->>'price')::numeric < 1000;
```

### Index Maintenance

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
WHERE tablename = 'products'
ORDER BY idx_scan DESC;

-- Check index size
SELECT 
  indexname,
  pg_size_pretty(pg_relation_size(indexname::regclass)) as size
FROM pg_indexes
WHERE tablename = 'products';

-- Rebuild index
REINDEX INDEX idx_products_metadata;

-- Update statistics
ANALYZE products;
```

## Query Profiling Tools

### pg_stat_statements

Enable in postgresql.conf:
```
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
```

Query slow queries:
```sql
SELECT 
  query,
  calls,
  total_time,
  mean_time,
  max_time,
  stddev_time,
  rows
FROM pg_stat_statements
WHERE query LIKE '%products%'
ORDER BY mean_time DESC
LIMIT 10;
```

### auto_explain

Enable in postgresql.conf:
```
shared_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = 1000  # Log queries > 1s
auto_explain.log_analyze = true
auto_explain.log_buffers = true
```

### PHP Profiling

```php
class QueryProfiler
{
    private array $queries = [];

    public function profile(callable $callback, string $label): mixed
    {
        $start = microtime(true);
        $memoryBefore = memory_get_usage();
        
        $result = $callback();
        
        $duration = microtime(true) - $start;
        $memoryUsed = memory_get_usage() - $memoryBefore;
        
        $this->queries[] = [
            'label' => $label,
            'duration' => $duration,
            'memory' => $memoryUsed,
            'timestamp' => date('Y-m-d H:i:s')
        ];
        
        return $result;
    }

    public function getStats(): array
    {
        return [
            'total_queries' => count($this->queries),
            'total_time' => array_sum(array_column($this->queries, 'duration')),
            'avg_time' => array_sum(array_column($this->queries, 'duration')) / count($this->queries),
            'slowest' => max(array_column($this->queries, 'duration')),
            'queries' => $this->queries
        ];
    }
}

// Usage
$profiler = new QueryProfiler();

$result = $profiler->profile(function () use ($pdo) {
    return $pdo->query("SELECT * FROM products WHERE metadata->>'brand' = 'Dell'")->fetchAll();
}, 'brand_query');

print_r($profiler->getStats());
```

### Ruby Profiling

```ruby
require 'benchmark'

class QueryProfiler
  def initialize
    @queries = []
  end

  def profile(label)
    memory_before = `ps -o rss= -p #{Process.pid}`.to_i
    
    result = nil
    time = Benchmark.realtime do
      result = yield
    end
    
    memory_after = `ps -o rss= -p #{Process.pid}`.to_i
    
    @queries << {
      label: label,
      duration: time,
      memory_delta: memory_after - memory_before,
      timestamp: Time.now
    }
    
    result
  end

  def stats
    {
      total_queries: @queries.size,
      total_time: @queries.sum { |q| q[:duration] },
      avg_time: @queries.sum { |q| q[:duration] } / @queries.size,
      slowest: @queries.max_by { |q| q[:duration] },
      queries: @queries
    }
  end
end

# Usage
profiler = QueryProfiler.new

result = profiler.profile('brand_query') do
  DB[:products].where(Sequel.lit("metadata->>'brand' = 'Dell'")).all
end

puts profiler.stats
```

## Performance Monitoring

### Key Metrics

1. **Query Duration**
   - Target: < 100ms for web requests
   - Alert: > 1000ms

2. **Connection Pool Usage**
   - Target: < 80% utilization
   - Alert: > 90% utilization

3. **Cache Hit Ratio**
   - Target: > 99%
   - Alert: < 95%

4. **Index Usage**
   - Target: All queries use indexes
   - Alert: Sequential scans on large tables

### Monitoring Queries

```sql
-- Active queries
SELECT 
  pid,
  usename,
  application_name,
  client_addr,
  state,
  query,
  now() - query_start as duration
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;

-- Long-running queries
SELECT 
  pid,
  now() - query_start as duration,
  query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 seconds'
ORDER BY duration DESC;

-- Blocking queries
SELECT 
  blocked_locks.pid AS blocked_pid,
  blocked_activity.usename AS blocked_user,
  blocking_locks.pid AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  blocked_activity.query AS blocked_statement,
  blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- Cache hit ratio
SELECT 
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;

-- Table sizes
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## Common Anti-Patterns

### Anti-Pattern 1: N+1 Queries

```php
// BAD: N+1 queries
$products = $pdo->query("SELECT * FROM products")->fetchAll();
foreach ($products as $product) {
    $metadata = json_decode($product['metadata'], true);
    // Process each product
}

// GOOD: Single query with filtering
$products = $pdo->query("
    SELECT * FROM products 
    WHERE metadata->>'status' = 'active'
")->fetchAll();
```

### Anti-Pattern 2: SELECT *

```sql
-- BAD: Fetches all columns
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';

-- GOOD: Only needed columns
SELECT id, name, metadata->>'brand' as brand, metadata->>'price' as price
FROM products 
WHERE metadata->>'brand' = 'Dell';
```

### Anti-Pattern 3: Function in WHERE

```sql
-- BAD: Function prevents index usage
SELECT * FROM products WHERE LOWER(metadata->>'brand') = 'dell';

-- GOOD: Use expression index or exact match
CREATE INDEX idx_brand_lower ON products ((LOWER(metadata->>'brand')));
SELECT * FROM products WHERE LOWER(metadata->>'brand') = 'dell';
```

### Anti-Pattern 4: OR Conditions

```sql
-- BAD: OR prevents index usage
SELECT * FROM products 
WHERE metadata->>'brand' = 'Dell' 
   OR metadata->>'brand' = 'Apple';

-- GOOD: Use IN or UNION
SELECT * FROM products 
WHERE metadata->>'brand' IN ('Dell', 'Apple');
```

### Anti-Pattern 5: Implicit Type Conversion

```sql
-- BAD: String comparison on numeric field
SELECT * FROM products WHERE metadata->>'price' > '1000';

-- GOOD: Explicit casting
SELECT * FROM products WHERE (metadata->>'price')::numeric > 1000;
```

### Anti-Pattern 6: Large OFFSET

```sql
-- BAD: Slow for large offsets
SELECT * FROM products ORDER BY id LIMIT 10 OFFSET 10000;

-- GOOD: Keyset pagination
SELECT * FROM products WHERE id > 10000 ORDER BY id LIMIT 10;
```

## Best Practices Summary

1. **Always use EXPLAIN ANALYZE** for slow queries
2. **Create appropriate indexes** for JSONB queries
3. **Use expression indexes** for frequently queried fields
4. **Monitor query performance** with pg_stat_statements
5. **Avoid anti-patterns** like N+1 queries and SELECT *
6. **Update statistics regularly** with ANALYZE
7. **Profile in production** to find real bottlenecks
8. **Set query timeouts** to prevent runaway queries
9. **Use connection pooling** to reduce overhead
10. **Monitor cache hit ratio** and tune shared_buffers
