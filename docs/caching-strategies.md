# Caching Strategies for PostgreSQL

Optimize performance with intelligent caching layers.

## Table of Contents

1. [Query Result Caching](#query-result-caching)
2. [Application-Level Caching](#application-level-caching)
3. [PostgreSQL Internal Caching](#postgresql-internal-caching)
4. [Distributed Caching](#distributed-caching)
5. [Cache Invalidation](#cache-invalidation)

## Query Result Caching

### PHP with Redis

```php
class QueryCache
{
    private Redis $redis;
    private PDO $pdo;
    private int $ttl = 3600; // 1 hour

    public function __construct(Redis $redis, PDO $pdo)
    {
        $this->redis = $redis;
        $this->pdo = $pdo;
    }

    public function query(string $sql, array $params = [], ?int $ttl = null): array
    {
        $cacheKey = $this->getCacheKey($sql, $params);
        
        // Try cache first
        $cached = $this->redis->get($cacheKey);
        if ($cached !== false) {
            return json_decode($cached, true);
        }
        
        // Query database
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);
        $result = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        // Store in cache
        $this->redis->setex(
            $cacheKey,
            $ttl ?? $this->ttl,
            json_encode($result)
        );
        
        return $result;
    }

    public function invalidate(string $sql, array $params = []): void
    {
        $cacheKey = $this->getCacheKey($sql, $params);
        $this->redis->del($cacheKey);
    }

    public function invalidatePattern(string $pattern): void
    {
        $keys = $this->redis->keys($pattern);
        if (!empty($keys)) {
            $this->redis->del(...$keys);
        }
    }

    private function getCacheKey(string $sql, array $params): string
    {
        return 'query:' . md5($sql . serialize($params));
    }
}

// Usage
$redis = new Redis();
$redis->connect('localhost', 6379);

$cache = new QueryCache($redis, $pdo);

// Cached query
$products = $cache->query(
    "SELECT * FROM products WHERE metadata->>'brand' = ?",
    ['Dell'],
    3600
);

// Invalidate cache
$cache->invalidate(
    "SELECT * FROM products WHERE metadata->>'brand' = ?",
    ['Dell']
);

// Invalidate by pattern
$cache->invalidatePattern('query:*products*');
```

### Ruby with Redis

```ruby
require 'redis'
require 'digest'

class QueryCache
  def initialize(db, redis, ttl: 3600)
    @db = db
    @redis = redis
    @ttl = ttl
  end

  def query(sql, *params, ttl: nil)
    cache_key = generate_cache_key(sql, params)
    
    # Try cache first
    cached = @redis.get(cache_key)
    return JSON.parse(cached, symbolize_names: true) if cached
    
    # Query database
    result = @db.fetch(sql, *params).all
    
    # Store in cache
    @redis.setex(cache_key, ttl || @ttl, result.to_json)
    
    result
  end

  def invalidate(sql, *params)
    cache_key = generate_cache_key(sql, params)
    @redis.del(cache_key)
  end

  def invalidate_pattern(pattern)
    keys = @redis.keys(pattern)
    @redis.del(*keys) unless keys.empty?
  end

  private

  def generate_cache_key(sql, params)
    "query:#{Digest::MD5.hexdigest("#{sql}#{params.to_s}")}"
  end
end

# Usage
redis = Redis.new(host: 'localhost', port: 6379)
cache = QueryCache.new(DB, redis, ttl: 3600)

# Cached query
products = cache.query(
  "SELECT * FROM products WHERE metadata->>'brand' = ?",
  'Dell',
  ttl: 3600
)

# Invalidate
cache.invalidate(
  "SELECT * FROM products WHERE metadata->>'brand' = ?",
  'Dell'
)
```

## Application-Level Caching

### Memoization Pattern

```php
class MemoizedRepository
{
    private array $cache = [];
    private PDO $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    public function getProductById(string $id): ?array
    {
        if (isset($this->cache['product'][$id])) {
            return $this->cache['product'][$id];
        }

        $stmt = $this->pdo->prepare("SELECT * FROM products WHERE id = ?");
        $stmt->execute([$id]);
        $product = $stmt->fetch(PDO::FETCH_ASSOC);

        $this->cache['product'][$id] = $product;
        return $product;
    }

    public function getProductsByBrand(string $brand): array
    {
        $cacheKey = "brand:$brand";
        
        if (isset($this->cache['products'][$cacheKey])) {
            return $this->cache['products'][$cacheKey];
        }

        $stmt = $this->pdo->prepare("
            SELECT * FROM products WHERE metadata->>'brand' = ?
        ");
        $stmt->execute([$brand]);
        $products = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $this->cache['products'][$cacheKey] = $products;
        return $products;
    }

    public function clearCache(): void
    {
        $this->cache = [];
    }
}
```

### Fragment Caching

```ruby
class FragmentCache
  def initialize(redis)
    @redis = redis
  end

  def fetch(key, ttl: 3600)
    cached = @redis.get(key)
    return cached if cached

    result = yield
    @redis.setex(key, ttl, result)
    result
  end

  def write(key, value, ttl: 3600)
    @redis.setex(key, ttl, value)
  end

  def read(key)
    @redis.get(key)
  end

  def delete(key)
    @redis.del(key)
  end
end

# Usage
cache = FragmentCache.new(redis)

# Cache product list
products_html = cache.fetch('products:list', ttl: 600) do
  render_products_list
end

# Cache individual product
product_html = cache.fetch("product:#{id}", ttl: 3600) do
  render_product(id)
end
```

## PostgreSQL Internal Caching

### Shared Buffers

```sql
-- Check current setting
SHOW shared_buffers;

-- Recommended: 25% of system RAM
-- postgresql.conf
shared_buffers = 4GB
```

### Effective Cache Size

```sql
-- Tell PostgreSQL about OS cache
-- postgresql.conf
effective_cache_size = 12GB  -- 50-75% of system RAM
```

### Query Plan Caching

```php
class PreparedStatementCache
{
    private PDO $pdo;
    private array $statements = [];

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    public function execute(string $sql, array $params = []): array
    {
        if (!isset($this->statements[$sql])) {
            $this->statements[$sql] = $this->pdo->prepare($sql);
        }

        $stmt = $this->statements[$sql];
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
}
```

### Materialized Views

```sql
-- Create materialized view
CREATE MATERIALIZED VIEW product_stats AS
SELECT 
  metadata->>'brand' as brand,
  COUNT(*) as product_count,
  AVG((metadata->>'price')::numeric) as avg_price,
  MIN((metadata->>'price')::numeric) as min_price,
  MAX((metadata->>'price')::numeric) as max_price
FROM products
GROUP BY metadata->>'brand';

-- Create index on materialized view
CREATE INDEX idx_product_stats_brand ON product_stats(brand);

-- Refresh materialized view
REFRESH MATERIALIZED VIEW product_stats;

-- Refresh concurrently (non-blocking)
REFRESH MATERIALIZED VIEW CONCURRENTLY product_stats;

-- Query materialized view (fast!)
SELECT * FROM product_stats WHERE brand = 'Dell';
```

## Distributed Caching

### Redis Cluster

```php
class RedisClusterCache
{
    private RedisCluster $cluster;

    public function __construct(array $seeds)
    {
        $this->cluster = new RedisCluster(null, $seeds);
    }

    public function get(string $key): mixed
    {
        $value = $this->cluster->get($key);
        return $value !== false ? json_decode($value, true) : null;
    }

    public function set(string $key, mixed $value, int $ttl = 3600): bool
    {
        return $this->cluster->setex($key, $ttl, json_encode($value));
    }

    public function delete(string $key): bool
    {
        return $this->cluster->del($key) > 0;
    }

    public function mget(array $keys): array
    {
        $values = $this->cluster->mget($keys);
        return array_map(
            fn($v) => $v !== false ? json_decode($v, true) : null,
            $values
        );
    }
}

// Usage
$cache = new RedisClusterCache([
    'redis1:6379',
    'redis2:6379',
    'redis3:6379'
]);

$cache->set('product:123', ['name' => 'Laptop', 'price' => 999.99]);
$product = $cache->get('product:123');
```

### Memcached

```ruby
require 'dalli'

class MemcachedCache
  def initialize(servers)
    @client = Dalli::Client.new(servers, {
      namespace: 'myapp',
      compress: true,
      expires_in: 3600
    })
  end

  def fetch(key, ttl: 3600)
    cached = @client.get(key)
    return cached if cached

    result = yield
    @client.set(key, result, ttl)
    result
  end

  def get(key)
    @client.get(key)
  end

  def set(key, value, ttl: 3600)
    @client.set(key, value, ttl)
  end

  def delete(key)
    @client.delete(key)
  end

  def get_multi(*keys)
    @client.get_multi(*keys)
  end
end

# Usage
cache = MemcachedCache.new(['localhost:11211', 'localhost:11212'])

# Fetch with fallback
products = cache.fetch('products:all', ttl: 600) do
  DB[:products].all
end
```

## Cache Invalidation

### Time-Based Invalidation

```php
class TimedCache
{
    private Redis $redis;

    public function set(string $key, mixed $value, int $ttl): void
    {
        $data = [
            'value' => $value,
            'expires_at' => time() + $ttl
        ];
        $this->redis->set($key, json_encode($data));
    }

    public function get(string $key): mixed
    {
        $cached = $this->redis->get($key);
        if (!$cached) {
            return null;
        }

        $data = json_decode($cached, true);
        
        if (time() > $data['expires_at']) {
            $this->redis->del($key);
            return null;
        }

        return $data['value'];
    }
}
```

### Event-Based Invalidation

```ruby
class EventBasedCache
  def initialize(redis)
    @redis = redis
  end

  def on_product_update(product_id)
    # Invalidate specific product
    @redis.del("product:#{product_id}")
    
    # Invalidate product lists
    @redis.del("products:all")
    @redis.del("products:brand:#{product[:brand]}")
    
    # Invalidate related caches
    invalidate_pattern("products:*")
  end

  def on_product_create(product)
    # Invalidate lists
    @redis.del("products:all")
    @redis.del("products:brand:#{product[:brand]}")
  end

  def on_product_delete(product_id, brand)
    # Invalidate specific product
    @redis.del("product:#{product_id}")
    
    # Invalidate lists
    @redis.del("products:all")
    @redis.del("products:brand:#{brand}")
  end

  private

  def invalidate_pattern(pattern)
    keys = @redis.keys(pattern)
    @redis.del(*keys) unless keys.empty?
  end
end
```

### Cache Tags

```php
class TaggedCache
{
    private Redis $redis;

    public function set(string $key, mixed $value, array $tags, int $ttl = 3600): void
    {
        // Store value
        $this->redis->setex($key, $ttl, json_encode($value));
        
        // Store tags
        foreach ($tags as $tag) {
            $this->redis->sadd("tag:$tag", $key);
        }
    }

    public function get(string $key): mixed
    {
        $cached = $this->redis->get($key);
        return $cached ? json_decode($cached, true) : null;
    }

    public function invalidateTag(string $tag): void
    {
        $keys = $this->redis->smembers("tag:$tag");
        
        if (!empty($keys)) {
            $this->redis->del(...$keys);
            $this->redis->del("tag:$tag");
        }
    }
}

// Usage
$cache = new TaggedCache($redis);

// Cache with tags
$cache->set(
    'product:123',
    ['name' => 'Laptop'],
    ['products', 'brand:Dell', 'category:electronics'],
    3600
);

// Invalidate by tag
$cache->invalidateTag('brand:Dell');  // Invalidates all Dell products
```

### Write-Through Cache

```ruby
class WriteThroughCache
  def initialize(db, redis)
    @db = db
    @redis = redis
  end

  def get(id)
    # Try cache first
    cached = @redis.get("product:#{id}")
    return JSON.parse(cached, symbolize_names: true) if cached

    # Load from database
    product = @db[:products].where(id: id).first
    
    # Store in cache
    @redis.setex("product:#{id}", 3600, product.to_json) if product
    
    product
  end

  def update(id, data)
    # Update database
    @db[:products].where(id: id).update(data)
    
    # Update cache
    product = @db[:products].where(id: id).first
    @redis.setex("product:#{id}", 3600, product.to_json)
    
    product
  end

  def delete(id)
    # Delete from database
    @db[:products].where(id: id).delete
    
    # Delete from cache
    @redis.del("product:#{id}")
  end
end
```

## Cache Warming

```php
class CacheWarmer
{
    private QueryCache $cache;
    private PDO $pdo;

    public function __construct(QueryCache $cache, PDO $pdo)
    {
        $this->cache = $cache;
        $this->pdo = $pdo;
    }

    public function warmPopularProducts(): void
    {
        // Get popular products
        $stmt = $this->pdo->query("
            SELECT id FROM products 
            ORDER BY metadata->>'view_count' DESC 
            LIMIT 100
        ");
        $productIds = $stmt->fetchAll(PDO::FETCH_COLUMN);

        // Warm cache
        foreach ($productIds as $id) {
            $this->cache->query(
                "SELECT * FROM products WHERE id = ?",
                [$id],
                3600
            );
        }
    }

    public function warmBrandPages(): void
    {
        // Get all brands
        $stmt = $this->pdo->query("
            SELECT DISTINCT metadata->>'brand' as brand 
            FROM products
        ");
        $brands = $stmt->fetchAll(PDO::FETCH_COLUMN);

        // Warm cache for each brand
        foreach ($brands as $brand) {
            $this->cache->query(
                "SELECT * FROM products WHERE metadata->>'brand' = ?",
                [$brand],
                3600
            );
        }
    }
}
```

## Best Practices

1. **Cache Appropriately**
   - Cache expensive queries
   - Cache frequently accessed data
   - Don't cache everything

2. **Set Proper TTLs**
   - Short TTL for frequently changing data
   - Long TTL for static data
   - Consider cache warming

3. **Invalidation Strategy**
   - Invalidate on writes
   - Use cache tags for related data
   - Consider eventual consistency

4. **Monitor Cache Performance**
   - Track hit/miss ratio
   - Monitor cache size
   - Alert on high miss rates

5. **Handle Cache Failures**
   - Graceful degradation
   - Fallback to database
   - Log cache errors

6. **Security**
   - Don't cache sensitive data
   - Encrypt cached data if needed
   - Validate cached data

7. **Testing**
   - Test cache invalidation
   - Test cache warming
   - Test cache failures
