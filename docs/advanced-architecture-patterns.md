# Advanced Architecture Patterns

Deep dive into modern connection management for PHP and Ruby.

## Table of Contents

1. [PHP Patterns](#php-patterns)
   - Swoole Connection Pools
   - FrankenPHP Worker Mode
   - PHP Fibers
   - PDO with PgBouncer Gotchas

2. [Ruby Patterns](#ruby-patterns)
   - ConnectionPool Gem
   - ActiveRecord Multiplexing
   - Puma Thread Safety
   - Sequel Threaded Pools

## PHP Patterns

### Swoole Connection Pools

Swoole provides true async I/O and coroutines for PHP.

#### Basic Setup

```php
use Swoole\Coroutine;
use Swoole\Coroutine\PostgreSQL;

$pg = new PostgreSQL();
$conn = $pg->connect("host=localhost port=5432 dbname=test user=postgres");
```

#### Connection Pool Implementation

```php
class SwooleConnectionPool
{
    private Channel $pool;
    private int $poolSize;

    public function __construct(array $config, int $poolSize = 20)
    {
        $this->poolSize = $poolSize;
        $this->pool = new Channel($poolSize);
        
        // Pre-populate pool
        for ($i = 0; $i < $poolSize; $i++) {
            $this->pool->push($this->createConnection());
        }
    }

    public function getConnection(): PostgreSQL
    {
        return $this->pool->pop();
    }

    public function releaseConnection(PostgreSQL $conn): void
    {
        $this->pool->push($conn);
    }
}
```

#### Concurrent Queries

```php
$results = [];
$wg = new Coroutine\WaitGroup();

foreach ($brands as $brand) {
    $wg->add();
    
    Coroutine::create(function () use ($brand, &$results, $wg) {
        $conn = $pool->getConnection();
        $results[$brand] = $conn->query("SELECT * FROM products WHERE brand = ?", [$brand]);
        $pool->releaseConnection($conn);
        $wg->done();
    });
}

$wg->wait();
```

#### Benefits
- True async I/O
- Thousands of concurrent connections
- Minimal memory overhead
- Native PostgreSQL protocol support

#### Limitations
- Requires Swoole extension
- Different programming model
- Not compatible with traditional PHP frameworks

### FrankenPHP Worker Mode

FrankenPHP provides persistent worker processes for PHP applications.

#### Worker Mode Benefits

1. **Persistent Connections**: Connections survive between requests
2. **Reduced Overhead**: No connection setup per request
3. **Better Performance**: 3-5x faster than traditional PHP-FPM

#### Implementation

```php
class FrankenPHPConnectionPool
{
    private static ?self $instance = null;
    private array $connections = [];

    public static function getInstance(): self
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct()
    {
        // Initialize pool once per worker
        for ($i = 0; $i < 20; $i++) {
            $this->connections[] = new PDO(...);
        }
    }

    public function getConnection(): PDO
    {
        static $index = 0;
        return $this->connections[$index++ % count($this->connections)];
    }
}
```

#### Critical: Request Cleanup

```php
// Reset connections between requests
public function reset(): void
{
    foreach ($this->connections as $conn) {
        if ($conn->inTransaction()) {
            $conn->rollBack();
        }
    }
}
```

#### Caddy Configuration

```caddyfile
{
    frankenphp {
        worker {
            file public/index.php
            num 4
        }
    }
}

localhost {
    root * public
    php_server
}
```

### PHP 8.1+ Fibers

Fibers enable cooperative multitasking without callbacks.

#### Basic Fiber Usage

```php
$fiber = new Fiber(function (): void {
    $result = performQuery();
    Fiber::suspend($result);
});

$fiber->start();
$result = $fiber->resume();
```

#### Fiber-Based Connection Pool

```php
class FiberConnectionPool
{
    private array $available = [];
    private int $maxConnections = 20;

    public function getConnection(): PDO
    {
        if (!empty($this->available)) {
            return array_pop($this->available);
        }

        if (count($this->connections) < $this->maxConnections) {
            return $this->createConnection();
        }

        // Wait for available connection
        Fiber::suspend();
        return $this->getConnection();
    }

    public function releaseConnection(PDO $conn): void
    {
        $this->available[] = $conn;
    }
}
```

#### Concurrent Queries with Fibers

```php
$fibers = [];
foreach ($queries as $key => $query) {
    $fiber = new Fiber(function () use ($query) {
        $conn = $pool->getConnection();
        $result = $conn->query($query);
        $pool->releaseConnection($conn);
        return $result;
    });
    
    $fibers[$key] = $fiber;
    $fiber->start();
}

// Resume fibers until all complete
$results = [];
while (count($results) < count($fibers)) {
    foreach ($fibers as $key => $fiber) {
        if ($fiber->isTerminated()) {
            $results[$key] = $fiber->getReturn();
        } elseif ($fiber->isSuspended()) {
            $fiber->resume();
        }
    }
}
```

#### Benefits
- Native PHP (no extensions)
- Cooperative multitasking
- Better than callbacks
- Works with existing code

#### Limitations
- Not true async I/O
- Still blocks on I/O
- Requires PHP 8.1+

### PDO with PgBouncer Gotchas

Critical issues when using PDO with PgBouncer.

#### Gotcha #1: Persistent Connections

```php
// WRONG - Bypasses PgBouncer pooling
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_PERSISTENT => true  // DON'T DO THIS
]);

// CORRECT - Let PgBouncer handle pooling
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_PERSISTENT => false
]);
```

**Why**: Persistent PDO connections stay open, defeating PgBouncer's purpose.

#### Gotcha #2: Prepared Statements

```php
// WRONG - Prepared statement lost after transaction
$stmt = $pdo->prepare("SELECT * FROM products WHERE id = ?");
// ... later in different transaction ...
$stmt->execute([$id]);  // May fail!

// CORRECT - Prepare within transaction
$pdo->beginTransaction();
$stmt = $pdo->prepare("SELECT * FROM products WHERE id = ?");
$stmt->execute([$id]);
$pdo->commit();
```

**Why**: PgBouncer transaction mode clears prepared statements.

#### Gotcha #3: Session-Level Features

```php
// WRONG - Won't work in transaction mode
$pdo->exec("SET search_path TO myschema");
$pdo->exec("LISTEN notifications");
$pdo->exec("CREATE TEMP TABLE ...");

// CORRECT - Use session mode or avoid these features
// Or include in each query:
$pdo->query("SELECT * FROM myschema.products");
```

**Why**: Transaction mode doesn't preserve session state.

#### Gotcha #4: Connection State

```php
// WRONG - Assuming connection state persists
$pdo->exec("SET timezone TO 'UTC'");
// ... later request ...
// Timezone setting is gone!

// CORRECT - Set per query or use PgBouncer config
$pdo->query("SELECT * FROM products WHERE created_at > NOW() AT TIME ZONE 'UTC'");
```

#### Recommended PDO Configuration

```php
$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_PERSISTENT => false,           // Critical
    PDO::ATTR_EMULATE_PREPARES => false,     // Use native prepares
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
```

## Ruby Patterns

### ConnectionPool Gem Internals

The `connection_pool` gem provides thread-safe connection pooling.

#### Basic Usage

```ruby
require 'connection_pool'

pool = ConnectionPool.new(size: 25, timeout: 5) do
  Sequel.connect(database_url)
end

pool.with do |conn|
  conn[:products].first
end
```

#### How It Works

1. **Checkout**: Thread requests connection from pool
2. **Use**: Thread uses connection
3. **Checkin**: Connection returned to pool automatically
4. **Timeout**: If no connections available, wait up to timeout

#### Advanced Patterns

```ruby
# Custom pool with monitoring
class MonitoredPool
  def initialize(database_url, size: 25)
    @pool = ConnectionPool.new(size: size) do
      Sequel.connect(database_url)
    end
    @checkout_times = Concurrent::Map.new
  end

  def with_connection
    start_time = Time.now
    @pool.with do |conn|
      @checkout_times[Thread.current.object_id] = Time.now - start_time
      yield conn
    end
  end

  def stats
    {
      size: @pool.size,
      available: @pool.available,
      avg_checkout_time: @checkout_times.values.sum / @checkout_times.size
    }
  end
end
```

#### Reload After Fork

```ruby
# Before fork
pool = ConnectionPool.new { Sequel.connect(url) }

# After fork
pool.reload do |conn|
  conn.disconnect
  Sequel.connect(url)
end
```

### ActiveRecord Connection Multiplexing

ActiveRecord 6.1+ supports multiple databases and automatic read/write splitting.

#### Configuration

```ruby
# config/database.yml
production:
  primary:
    adapter: postgresql
    host: primary-host
    database: myapp
    pool: 25
  
  primary_replica:
    adapter: postgresql
    host: replica-host
    database: myapp
    pool: 50
    replica: true
  
  analytics:
    adapter: postgresql
    host: analytics-host
    database: analytics
    pool: 10
```

#### Model Configuration

```ruby
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  
  # Automatic read/write splitting
  connects_to database: { 
    writing: :primary, 
    reading: :primary_replica 
  }
end

class Product < ApplicationRecord
  # Writes go to primary
  # Reads go to replica
end
```

#### Manual Switching

```ruby
# Force read from primary
ActiveRecord::Base.connected_to(role: :writing) do
  Product.find(id)
end

# Force read from replica
ActiveRecord::Base.connected_to(role: :reading) do
  Product.where(brand: 'Dell').to_a
end
```

#### Sharding

```ruby
# Configure shards
class ApplicationRecord < ActiveRecord::Base
  connects_to shards: {
    shard_one: { writing: :shard_one_primary },
    shard_two: { writing: :shard_two_primary }
  }
end

# Use specific shard
ActiveRecord::Base.connected_to(shard: :shard_one) do
  Product.create!(name: 'Product')
end
```

### Puma Thread Safety

Puma is a concurrent web server that uses threads.

#### Configuration

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 4 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

preload_app!

before_fork do
  ActiveRecord::Base.connection_pool.disconnect!
end

on_worker_boot do
  ActiveRecord::Base.establish_connection
end
```

#### Connection Pool Sizing

```
Total Connections = Workers × Threads × Databases

Example:
- 4 workers
- 5 threads per worker
- 2 databases (primary + replica)
= 4 × 5 × 2 = 40 connections needed
```

#### Thread-Safe Patterns

```ruby
# Thread-local storage
class ThreadSafeRepository
  def connection
    Thread.current[:db_connection] ||= Sequel.connect(url)
  end

  def query(sql)
    connection.fetch(sql).all
  end
end

# Concurrent::Map for thread-safe storage
class ConnectionManager
  def initialize
    @connections = Concurrent::Map.new
  end

  def connection_for_thread
    @connections.compute_if_absent(Thread.current.object_id) do
      Sequel.connect(database_url)
    end
  end
end
```

### Sequel Threaded Connection Pools

Sequel's default pool is thread-safe and efficient.

#### Configuration

```ruby
DB = Sequel.connect(
  database_url,
  max_connections: 25,
  pool_timeout: 5,
  pool_class: Sequel::ThreadedConnectionPool,
  
  # Connection validation
  test: true,
  
  # Keep-alive
  keepalives: 1,
  keepalives_idle: 30,
  keepalives_interval: 10,
  keepalives_count: 3
)
```

#### Pool Monitoring

```ruby
pool = DB.pool

stats = {
  size: pool.size,
  max_size: pool.max_size,
  allocated: pool.allocated.size,
  available: pool.available_connections.size
}
```

#### Sharded Pools

```ruby
class ShardedPool
  def initialize(shard_configs)
    @shards = {}
    shard_configs.each do |name, config|
      @shards[name] = Sequel.connect(config[:url])
    end
  end

  def with_shard(shard_name)
    yield @shards[shard_name]
  end

  def shard_for_key(key)
    shard_index = key.hash % @shards.size
    @shards.keys[shard_index]
  end
end
```

## Comparison Matrix

| Feature | Swoole | FrankenPHP | Fibers | ConnectionPool | ActiveRecord | Sequel |
|---------|--------|------------|--------|----------------|--------------|--------|
| True Async | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Persistent Connections | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| Thread Safe | ✅ | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |
| Easy Setup | ❌ | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| Production Ready | ✅ | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |
| Learning Curve | High | Medium | Medium | Low | Low | Low |

## Best Practices

### PHP

1. **Use PgBouncer** with proper PDO configuration
2. **Avoid persistent connections** with PgBouncer
3. **Consider Swoole** for high-concurrency needs
4. **Try FrankenPHP** for Laravel/Symfony apps
5. **Experiment with Fibers** for cooperative multitasking

### Ruby

1. **Use ConnectionPool gem** for custom pools
2. **Configure Puma properly** for thread safety
3. **Size pools correctly**: threads × workers
4. **Monitor pool saturation** in production
5. **Use read replicas** with ActiveRecord multiplexing

## Resources

### PHP
- [Swoole Documentation](https://www.swoole.co.uk/)
- [FrankenPHP](https://frankenphp.dev/)
- [PHP Fibers RFC](https://wiki.php.net/rfc/fibers)

### Ruby
- [ConnectionPool Gem](https://github.com/mperham/connection_pool)
- [Puma Configuration](https://github.com/puma/puma)
- [Sequel Connection Pools](https://sequel.jeremyevans.net/rdoc/files/doc/connection_pools_rdoc.html)
