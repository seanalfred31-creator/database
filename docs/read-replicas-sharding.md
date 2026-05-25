# Read Replicas and Sharding Guide

Scale PostgreSQL horizontally with read replicas and sharding strategies.

## Table of Contents

1. [Read Replicas](#read-replicas)
2. [Sharding Strategies](#sharding-strategies)
3. [Implementation Patterns](#implementation-patterns)
4. [Monitoring and Maintenance](#monitoring-and-maintenance)

## Read Replicas

### Why Read Replicas?

**Benefits:**
- Distribute read load across multiple servers
- Reduce primary database load
- Improve query performance
- Geographic distribution
- Disaster recovery

**Use Cases:**
- Analytics queries
- Reporting dashboards
- Search functionality
- Read-heavy applications

### PostgreSQL Streaming Replication

#### Primary Configuration

```ini
# postgresql.conf on primary
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
synchronous_commit = on
```

#### Replica Configuration

```ini
# postgresql.conf on replica
hot_standby = on
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
hot_standby_feedback = on
```

#### Setup Replication

```bash
# On replica server
pg_basebackup -h primary-host -D /var/lib/postgresql/data -U replication -P -v -R -X stream -C -S replica_1
```

### Read/Write Splitting

#### PHP Implementation

```php
class ReadWriteSplitter
{
    private PDO $primary;
    private array $replicas;
    private int $replicaIndex = 0;

    public function __construct(array $primaryConfig, array $replicaConfigs)
    {
        // Primary connection (writes)
        $this->primary = $this->createConnection($primaryConfig);
        
        // Replica connections (reads)
        $this->replicas = array_map(
            fn($config) => $this->createConnection($config),
            $replicaConfigs
        );
    }

    public function write(string $sql, array $params = []): mixed
    {
        $stmt = $this->primary->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    public function read(string $sql, array $params = []): array
    {
        $replica = $this->getNextReplica();
        $stmt = $replica->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    private function getNextReplica(): PDO
    {
        // Round-robin load balancing
        $replica = $this->replicas[$this->replicaIndex % count($this->replicas)];
        $this->replicaIndex++;
        return $replica;
    }

    private function createConnection(array $config): PDO
    {
        $dsn = sprintf(
            "pgsql:host=%s;port=%d;dbname=%s",
            $config['host'],
            $config['port'],
            $config['database']
        );
        return new PDO($dsn, $config['username'], $config['password']);
    }
}

// Usage
$splitter = new ReadWriteSplitter(
    ['host' => 'primary.db', 'port' => 5432, 'database' => 'mydb', 'username' => 'user', 'password' => 'pass'],
    [
        ['host' => 'replica1.db', 'port' => 5432, 'database' => 'mydb', 'username' => 'user', 'password' => 'pass'],
        ['host' => 'replica2.db', 'port' => 5432, 'database' => 'mydb', 'username' => 'user', 'password' => 'pass']
    ]
);

// Write to primary
$splitter->write("INSERT INTO products (name, metadata) VALUES (?, ?::jsonb)", ['Product', '{}']);

// Read from replica
$products = $splitter->read("SELECT * FROM products WHERE metadata->>'brand' = ?", ['Dell']);
```

#### Ruby Implementation

```ruby
class ReadWriteSplitter
  def initialize(primary_url, replica_urls)
    @primary = Sequel.connect(primary_url)
    @replicas = replica_urls.map { |url| Sequel.connect(url) }
    @replica_index = 0
  end

  def write
    @primary.transaction do
      yield @primary
    end
  end

  def read
    replica = next_replica
    yield replica
  end

  private

  def next_replica
    replica = @replicas[@replica_index % @replicas.size]
    @replica_index += 1
    replica
  end
end

# Usage
splitter = ReadWriteSplitter.new(
  'postgresql://user:pass@primary:5432/mydb',
  [
    'postgresql://user:pass@replica1:5432/mydb',
    'postgresql://user:pass@replica2:5432/mydb'
  ]
)

# Write to primary
splitter.write do |db|
  db[:products].insert(name: 'Product', metadata: Sequel.pg_jsonb({}))
end

# Read from replica
products = splitter.read do |db|
  db[:products].where(Sequel.lit("metadata->>'brand' = 'Dell'")).all
end
```

### ActiveRecord Read Replica Support

```ruby
# config/database.yml
production:
  primary:
    adapter: postgresql
    host: primary.db
    database: mydb
    pool: 25

  primary_replica:
    adapter: postgresql
    host: replica.db
    database: mydb
    pool: 50
    replica: true

# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  
  connects_to database: { 
    writing: :primary, 
    reading: :primary_replica 
  }
end

# Automatic routing
Product.find(1)  # Reads from replica
Product.create!(name: 'New')  # Writes to primary

# Force primary
ActiveRecord::Base.connected_to(role: :writing) do
  Product.find(1)  # Reads from primary
end
```

### Replication Lag Monitoring

```sql
-- On primary: Check replication status
SELECT 
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  sync_state,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- On replica: Check lag
SELECT 
  now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

### Handling Replication Lag

```php
class ReplicationAwareQuery
{
    private ReadWriteSplitter $splitter;
    private float $maxLagSeconds = 5.0;

    public function readWithLagCheck(string $sql, array $params = []): array
    {
        $lag = $this->getReplicationLag();
        
        if ($lag > $this->maxLagSeconds) {
            // Lag too high, read from primary
            return $this->splitter->write($sql, $params)->fetchAll();
        }
        
        // Lag acceptable, read from replica
        return $this->splitter->read($sql, $params);
    }

    private function getReplicationLag(): float
    {
        $result = $this->splitter->read(
            "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag"
        );
        return (float)($result[0]['lag'] ?? 0);
    }
}
```

## Sharding Strategies

### Why Sharding?

**Benefits:**
- Horizontal scalability
- Distribute data across servers
- Reduce per-database load
- Improve query performance

**Challenges:**
- Complex application logic
- Cross-shard queries
- Data distribution
- Rebalancing

### Sharding Strategies

#### 1. Range-Based Sharding

Partition by value ranges.

```ruby
class RangeSharding
  def initialize(shard_configs)
    @shards = {}
    shard_configs.each do |range, config|
      @shards[range] = Sequel.connect(config[:url])
    end
  end

  def shard_for_id(id)
    case id
    when 1..1000
      @shards[1..1000]
    when 1001..2000
      @shards[1001..2000]
    else
      @shards[:default]
    end
  end

  def query(id, sql)
    shard = shard_for_id(id)
    shard.fetch(sql).all
  end
end
```

#### 2. Hash-Based Sharding

Partition by hash of key.

```php
class HashSharding
{
    private array $shards;
    private int $shardCount;

    public function __construct(array $shardConfigs)
    {
        $this->shardCount = count($shardConfigs);
        foreach ($shardConfigs as $index => $config) {
            $this->shards[$index] = $this->createConnection($config);
        }
    }

    public function shardForKey(string $key): PDO
    {
        $hash = crc32($key);
        $shardIndex = $hash % $this->shardCount;
        return $this->shards[$shardIndex];
    }

    public function query(string $key, string $sql, array $params = []): array
    {
        $shard = $this->shardForKey($key);
        $stmt = $shard->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    public function queryAllShards(string $sql, array $params = []): array
    {
        $results = [];
        foreach ($this->shards as $index => $shard) {
            $stmt = $shard->prepare($sql);
            $stmt->execute($params);
            $results[$index] = $stmt->fetchAll();
        }
        return $results;
    }
}

// Usage
$sharding = new HashSharding([
    ['host' => 'shard1.db', 'port' => 5432, 'database' => 'shard1', 'username' => 'user', 'password' => 'pass'],
    ['host' => 'shard2.db', 'port' => 5432, 'database' => 'shard2', 'username' => 'user', 'password' => 'pass'],
    ['host' => 'shard3.db', 'port' => 5432, 'database' => 'shard3', 'username' => 'user', 'password' => 'pass']
]);

// Query specific shard
$products = $sharding->query('user_123', "SELECT * FROM products WHERE user_id = ?", ['user_123']);

// Query all shards
$allProducts = $sharding->queryAllShards("SELECT COUNT(*) FROM products");
```

#### 3. Geographic Sharding

Partition by geographic region.

```ruby
class GeographicSharding
  REGIONS = {
    'us-east' => 'postgresql://user:pass@us-east.db:5432/mydb',
    'us-west' => 'postgresql://user:pass@us-west.db:5432/mydb',
    'eu-west' => 'postgresql://user:pass@eu-west.db:5432/mydb',
    'ap-south' => 'postgresql://user:pass@ap-south.db:5432/mydb'
  }

  def initialize
    @shards = REGIONS.transform_values { |url| Sequel.connect(url) }
  end

  def shard_for_region(region)
    @shards[region] || @shards['us-east']  # Default to us-east
  end

  def query(region, sql)
    shard = shard_for_region(region)
    shard.fetch(sql).all
  end
end

# Usage
sharding = GeographicSharding.new

# Query specific region
products = sharding.query('eu-west', "SELECT * FROM products WHERE region = 'eu-west'")
```

### Multi-Tenant Sharding

```php
class TenantSharding
{
    private array $shards;
    private array $tenantMap;

    public function __construct(array $shardConfigs, array $tenantMap)
    {
        foreach ($shardConfigs as $shardId => $config) {
            $this->shards[$shardId] = $this->createConnection($config);
        }
        $this->tenantMap = $tenantMap;
    }

    public function shardForTenant(string $tenantId): PDO
    {
        $shardId = $this->tenantMap[$tenantId] ?? 'default';
        return $this->shards[$shardId];
    }

    public function query(string $tenantId, string $sql, array $params = []): array
    {
        $shard = $this->shardForTenant($tenantId);
        
        // Add tenant filter to query
        $sql = $this->addTenantFilter($sql, $tenantId);
        
        $stmt = $shard->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    private function addTenantFilter(string $sql, string $tenantId): string
    {
        // Simple implementation - in production use query parser
        if (stripos($sql, 'WHERE') !== false) {
            return str_ireplace('WHERE', "WHERE tenant_id = '$tenantId' AND", $sql);
        }
        return $sql;
    }
}
```

### Cross-Shard Queries

```ruby
class CrossShardQuery
  def initialize(shards)
    @shards = shards
  end

  # Aggregate across all shards
  def aggregate(sql)
    results = []
    threads = @shards.map do |shard_name, db|
      Thread.new do
        [shard_name, db.fetch(sql).all]
      end
    end

    threads.each do |thread|
      shard_name, result = thread.value
      results.concat(result)
    end

    results
  end

  # Map-reduce pattern
  def map_reduce(map_sql, reduce_fn)
    # Map phase: query each shard
    mapped = @shards.map do |shard_name, db|
      db.fetch(map_sql).all
    end

    # Reduce phase: combine results
    reduce_fn.call(mapped.flatten)
  end
end

# Usage
cross_shard = CrossShardQuery.new(shards)

# Get total count across all shards
total = cross_shard.map_reduce(
  "SELECT COUNT(*) as count FROM products",
  ->(results) { results.sum { |r| r[:count] } }
)

# Get top products across all shards
top_products = cross_shard.map_reduce(
  "SELECT * FROM products ORDER BY metadata->>'price' DESC LIMIT 10",
  ->(results) { results.sort_by { |r| -r[:metadata]['price'].to_f }.first(10) }
)
```

## Implementation Patterns

### Consistent Hashing

```php
class ConsistentHashing
{
    private array $ring = [];
    private array $shards;
    private int $virtualNodes = 150;

    public function __construct(array $shards)
    {
        $this->shards = $shards;
        $this->buildRing();
    }

    private function buildRing(): void
    {
        foreach ($this->shards as $shardId => $shard) {
            for ($i = 0; $i < $this->virtualNodes; $i++) {
                $hash = crc32("$shardId:$i");
                $this->ring[$hash] = $shardId;
            }
        }
        ksort($this->ring);
    }

    public function getShardForKey(string $key): string
    {
        $hash = crc32($key);
        
        foreach ($this->ring as $ringHash => $shardId) {
            if ($hash <= $ringHash) {
                return $shardId;
            }
        }
        
        // Wrap around to first shard
        return reset($this->ring);
    }

    public function addShard(string $shardId, $shard): void
    {
        $this->shards[$shardId] = $shard;
        
        for ($i = 0; $i < $this->virtualNodes; $i++) {
            $hash = crc32("$shardId:$i");
            $this->ring[$hash] = $shardId;
        }
        ksort($this->ring);
    }

    public function removeShard(string $shardId): void
    {
        unset($this->shards[$shardId]);
        
        $this->ring = array_filter(
            $this->ring,
            fn($id) => $id !== $shardId
        );
    }
}
```

### Shard Routing Middleware

```ruby
class ShardRoutingMiddleware
  def initialize(app, sharding)
    @app = app
    @sharding = sharding
  end

  def call(env)
    request = Rack::Request.new(env)
    
    # Extract shard key from request
    shard_key = extract_shard_key(request)
    
    # Set shard for this request
    Thread.current[:current_shard] = @sharding.shard_for_key(shard_key)
    
    @app.call(env)
  ensure
    Thread.current[:current_shard] = nil
  end

  private

  def extract_shard_key(request)
    # Try header first
    return request.env['HTTP_X_SHARD_KEY'] if request.env['HTTP_X_SHARD_KEY']
    
    # Try session
    return request.session[:user_id] if request.session[:user_id]
    
    # Default
    'default'
  end
end

# Usage in config.ru
use ShardRoutingMiddleware, sharding_instance
run MyApp
```

## Monitoring and Maintenance

### Shard Health Monitoring

```sql
-- Check shard sizes
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check shard distribution
SELECT 
  'shard1' as shard,
  COUNT(*) as record_count,
  pg_size_pretty(pg_database_size(current_database())) as size
FROM products;
```

### Rebalancing Shards

```ruby
class ShardRebalancer
  def initialize(source_shard, target_shard)
    @source = source_shard
    @target = target_shard
  end

  def rebalance(table, condition)
    # Get records to move
    records = @source.fetch("SELECT * FROM #{table} WHERE #{condition}").all
    
    @target.transaction do
      records.each do |record|
        # Insert into target
        @target[table.to_sym].insert(record)
        
        # Delete from source
        @source[table.to_sym].where(id: record[:id]).delete
      end
    end
    
    records.size
  end
end
```

### Best Practices

1. **Read Replicas**
   - Monitor replication lag
   - Use connection pooling
   - Implement fallback to primary
   - Consider eventual consistency

2. **Sharding**
   - Choose appropriate shard key
   - Plan for rebalancing
   - Minimize cross-shard queries
   - Use consistent hashing for flexibility

3. **Monitoring**
   - Track shard sizes
   - Monitor query distribution
   - Alert on replication lag
   - Log cross-shard queries

4. **Maintenance**
   - Regular vacuum and analyze
   - Monitor disk space
   - Plan for shard splits
   - Test failover procedures
