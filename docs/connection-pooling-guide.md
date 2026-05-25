# Connection Pooling Guide

Connection pooling reduces overhead and improves application performance by reusing database connections.

## Why Connection Pooling?

### Without Pooling
- Each request creates new connection
- TCP handshake + authentication overhead
- Limited by max_connections setting
- Slow under high concurrency

### With Pooling
- Connections reused across requests
- Minimal overhead per query
- Better resource utilization
- Handles high concurrency efficiently

## PgBouncer Overview

PgBouncer is a lightweight connection pooler for PostgreSQL.

### Pool Modes

#### Transaction Mode (Recommended)
- Connection returned to pool after transaction
- Most efficient for web applications
- Cannot use session-level features (temp tables, prepared statements)

```ini
pool_mode = transaction
```

#### Session Mode
- Connection held for entire client session
- Supports all PostgreSQL features
- Less efficient pooling

```ini
pool_mode = session
```

#### Statement Mode
- Connection returned after each statement
- Most aggressive pooling
- Very limited use cases

```ini
pool_mode = statement
```

## Configuration

### Basic PgBouncer Setup

```ini
[databases]
advanced_pg = host=postgres port=5432 dbname=advanced_pg

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Pool settings
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5

# Timeouts
server_idle_timeout = 600
server_lifetime = 3600
```

### Docker Compose Setup

```yaml
pgbouncer:
  image: edoburu/pgbouncer:latest
  environment:
    DATABASE_URL: postgres://user:pass@postgres:5432/dbname
    POOL_MODE: transaction
    MAX_CLIENT_CONN: 100
    DEFAULT_POOL_SIZE: 20
  ports:
    - "6432:5432"
```

## Application Configuration

### PHP (PDO)

```php
// Direct connection
$direct = new PDO(
    'pgsql:host=postgres;port=5432;dbname=advanced_pg',
    'pguser',
    'pgpass'
);

// Pooled connection via PgBouncer
$pooled = new PDO(
    'pgsql:host=pgbouncer;port=6432;dbname=advanced_pg',
    'pguser',
    'pgpass',
    [PDO::ATTR_PERSISTENT => false] // PgBouncer handles pooling
);
```

### Ruby (Sequel)

```ruby
# Direct connection
direct_db = Sequel.connect(
  'postgresql://pguser:pgpass@postgres:5432/advanced_pg',
  max_connections: 5
)

# Pooled connection via PgBouncer
pooled_db = Sequel.connect(
  'postgresql://pguser:pgpass@pgbouncer:6432/advanced_pg',
  max_connections: 20
)
```

## Monitoring

### PgBouncer Admin Console

```bash
# Connect to admin console
psql -h pgbouncer -p 6432 -U pguser pgbouncer

# Show pool statistics
SHOW POOLS;

# Show client connections
SHOW CLIENTS;

# Show server connections
SHOW SERVERS;

# Show configuration
SHOW CONFIG;
```

### Key Metrics

```sql
-- Active connections
SELECT COUNT(*) FROM pg_stat_activity;

-- Connection states
SELECT state, COUNT(*) 
FROM pg_stat_activity 
GROUP BY state;

-- Long-running queries
SELECT pid, now() - query_start as duration, query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

## Best Practices

### 1. Choose Right Pool Mode

- Web apps: Transaction mode
- Background jobs: Session mode
- Mixed workload: Multiple PgBouncer instances

### 2. Size Your Pool

```
default_pool_size = (total_connections - superuser_reserved) / num_databases
```

Example:
- PostgreSQL max_connections: 100
- Reserved: 3
- Databases: 2
- Pool size: (100 - 3) / 2 = 48

### 3. Handle Connection Errors

```php
try {
    $pdo->query("SELECT 1");
} catch (PDOException $e) {
    // Reconnect logic
    $pdo = createNewConnection();
}
```

### 4. Use Prepared Statements Carefully

In transaction mode, prepared statements are cleared after each transaction:

```php
// This works in transaction mode
$pdo->beginTransaction();
$stmt = $pdo->prepare("SELECT * FROM products WHERE id = ?");
$stmt->execute([$id]);
$pdo->commit();

// This may fail across transactions
$stmt = $pdo->prepare("SELECT * FROM products WHERE id = ?");
// ... later in different transaction ...
$stmt->execute([$id]); // May fail
```

### 5. Monitor Pool Saturation

```sql
-- Check if pool is saturated
SHOW POOLS;

-- Look for:
-- cl_waiting > 0 (clients waiting for connection)
-- sv_used = maxwait (all server connections in use)
```

## Troubleshooting

### Problem: Clients Waiting

```
cl_waiting > 0
```

Solution: Increase `default_pool_size` or optimize queries

### Problem: Connection Timeouts

```
server_idle_timeout too low
```

Solution: Increase timeout or use `server_reset_query`

### Problem: Transaction Mode Limitations

```
ERROR: prepared statement "..." does not exist
```

Solution: Use session mode or avoid cross-transaction prepared statements

### Problem: Too Many Connections

```
FATAL: sorry, too many clients already
```

Solution: Increase `max_client_conn` or reduce connection usage

## Performance Comparison

Typical improvements with PgBouncer:

- Connection overhead: 90% reduction
- Concurrent requests: 3-5x improvement
- Memory usage: 50% reduction
- Response time: 20-40% faster

## Testing Your Setup

```bash
# Benchmark direct connection
ab -n 1000 -c 10 http://localhost:8000/products/brand/Dell

# Benchmark pooled connection
ab -n 1000 -c 10 http://localhost:8000/benchmark

# Monitor during load
watch -n 1 'psql -h pgbouncer -p 6432 -U pguser -c "SHOW POOLS" pgbouncer'
```
