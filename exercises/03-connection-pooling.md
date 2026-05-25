# Exercise 3: Connection Pooling

Understand and optimize connection pooling.

## Tasks

### 1. Benchmark Connections

Compare direct vs pooled connection performance.

```bash
# PHP
curl http://localhost:8000/benchmark

# Ruby
curl http://localhost:3000/benchmark
```

Questions:
- What's the performance difference?
- Why is pooling faster?
- When would direct connections be acceptable?

### 2. Monitor Pool Statistics

Check current pool status.

```bash
# Connect to PgBouncer admin
psql -h localhost -p 6432 -U pguser pgbouncer

# Show pools
SHOW POOLS;

# Show clients
SHOW CLIENTS;

# Show servers
SHOW SERVERS;
```

Questions:
- How many connections are in the pool?
- How many are active vs idle?
- What's the max pool size?

### 3. Simulate High Load

Test pool behavior under load.

```bash
# PHP
curl "http://localhost:8000/load-test?queries=100"

# Ruby
curl "http://localhost:3000/load-test?queries=100"
```

Monitor during load:
```bash
watch -n 1 'psql -h localhost -p 6432 -U pguser -c "SHOW POOLS" pgbouncer'
```

Questions:
- Does the pool saturate?
- Are clients waiting?
- What's the queries per second rate?

### 4. Test Transaction Pooling

Understand transaction mode behavior.

```bash
# Ruby (has dedicated endpoint)
curl http://localhost:3000/transaction-test
```

Questions:
- How does transaction mode affect performance?
- What are the limitations?
- When should you use session mode instead?

### 5. Tune Pool Size

Experiment with different pool sizes.

Edit `docker-compose.yml`:
```yaml
pgbouncer:
  environment:
    DEFAULT_POOL_SIZE: 10  # Try 5, 10, 20, 50
```

Restart and benchmark:
```bash
docker-compose restart pgbouncer
curl http://localhost:8000/benchmark
```

Questions:
- What's the optimal pool size?
- How does it relate to your workload?
- What happens with too small/large pools?

## Challenge 1: Connection Leak Detection

Create a script that:
1. Opens multiple connections
2. Doesn't close them properly
3. Monitors pool exhaustion
4. Implements proper cleanup

## Challenge 2: Pool Saturation Recovery

Simulate and recover from pool saturation:
1. Set very small pool size (2-3)
2. Generate high concurrent load
3. Monitor client waiting
4. Implement retry logic
5. Tune pool to handle load

## Challenge 3: Multi-Database Pooling

Configure PgBouncer for multiple databases:
1. Add second database to config
2. Set per-database pool sizes
3. Test isolation between pools
4. Monitor resource distribution

<details>
<summary>Multi-Database Config Example</summary>

```ini
[databases]
db1 = host=postgres port=5432 dbname=db1 pool_size=10
db2 = host=postgres port=5432 dbname=db2 pool_size=20

[pgbouncer]
pool_mode = transaction
max_client_conn = 100
```
</details>
