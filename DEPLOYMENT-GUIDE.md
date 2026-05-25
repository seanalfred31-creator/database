# Production Deployment Guide

Deploy PostgreSQL applications with confidence.

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Database Configuration](#database-configuration)
4. [Application Deployment](#application-deployment)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Backup & Recovery](#backup--recovery)
7. [Security Hardening](#security-hardening)

## Pre-Deployment Checklist

### Database Readiness

- [ ] All migrations tested in staging
- [ ] Indexes created for production queries
- [ ] VACUUM and ANALYZE scheduled
- [ ] Connection pool sized appropriately
- [ ] Replication configured (if using)
- [ ] Backup strategy implemented
- [ ] Monitoring tools configured
- [ ] SSL/TLS certificates ready
- [ ] Firewall rules defined
- [ ] Disaster recovery plan documented

### Application Readiness

- [ ] All tests passing (unit, integration, performance)
- [ ] Load testing completed
- [ ] Error handling verified
- [ ] Logging configured
- [ ] Environment variables set
- [ ] Secrets management configured
- [ ] Health check endpoints working
- [ ] Graceful shutdown implemented
- [ ] Rate limiting configured
- [ ] CORS policies set

### Performance Validation

- [ ] Query performance benchmarked
- [ ] Connection pool tested under load
- [ ] Cache hit ratios acceptable (>95%)
- [ ] Response times within SLA (<100ms)
- [ ] Memory usage profiled
- [ ] CPU usage acceptable (<70%)
- [ ] Disk I/O optimized
- [ ] Network latency measured

## Infrastructure Setup

### Cloud Provider Options

#### AWS

```yaml
# RDS PostgreSQL Configuration
DBInstanceClass: db.r6g.xlarge
Engine: postgres
EngineVersion: '16.1'
AllocatedStorage: 100
StorageType: gp3
MultiAZ: true
BackupRetentionPeriod: 7
PreferredBackupWindow: '03:00-04:00'
PreferredMaintenanceWindow: 'sun:04:00-sun:05:00'

# ElastiCache for Redis
CacheNodeType: cache.r6g.large
Engine: redis
EngineVersion: '7.0'
NumCacheNodes: 2
AutomaticFailoverEnabled: true
```

#### Google Cloud

```yaml
# Cloud SQL PostgreSQL
tier: db-custom-4-16384  # 4 vCPU, 16GB RAM
databaseVersion: POSTGRES_16
availabilityType: REGIONAL
backupConfiguration:
  enabled: true
  startTime: '03:00'
  pointInTimeRecoveryEnabled: true
  transactionLogRetentionDays: 7
```

#### DigitalOcean

```yaml
# Managed PostgreSQL
size: db-s-4vcpu-8gb
version: '16'
num_nodes: 2
region: nyc3
backup_restore:
  enabled: true
```

### Docker Compose Production

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    restart: always
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgresql.conf:/etc/postgresql/postgresql.conf
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  pgbouncer:
    image: edoburu/pgbouncer:latest
    restart: always
    environment:
      DATABASE_URL: postgres://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}
      POOL_MODE: transaction
      MAX_CLIENT_CONN: 1000
      DEFAULT_POOL_SIZE: 25
    ports:
      - "6432:5432"
    depends_on:
      postgres:
        condition: service_healthy

  app:
    build: .
    restart: always
    environment:
      DATABASE_URL: postgres://${DB_USER}:${DB_PASSWORD}@pgbouncer:5432/${DB_NAME}
      REDIS_URL: redis://redis:6379
    ports:
      - "8000:8000"
    depends_on:
      - pgbouncer
      - redis

  redis:
    image: redis:7-alpine
    restart: always
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"

volumes:
  postgres_data:
  redis_data:
```

## Database Configuration

### Production postgresql.conf

```ini
# Connection Settings
max_connections = 200
superuser_reserved_connections = 3

# Memory Settings
shared_buffers = 4GB                    # 25% of RAM
effective_cache_size = 12GB             # 75% of RAM
maintenance_work_mem = 1GB
work_mem = 20MB                         # RAM / max_connections / 10

# Checkpoint Settings
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1                  # For SSD
effective_io_concurrency = 200          # For SSD

# Write Ahead Log
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB

# Query Planning
random_page_cost = 1.1
cpu_tuple_cost = 0.01
cpu_index_tuple_cost = 0.005
cpu_operator_cost = 0.0025

# Logging
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000       # Log queries > 1s
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0

# Performance
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.max = 10000

# Autovacuum
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 10s
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
```

### PgBouncer Production Config

```ini
[databases]
production = host=postgres port=5432 dbname=myapp

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Pool Configuration
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 5

# Timeouts
server_idle_timeout = 600
server_lifetime = 3600
server_connect_timeout = 15
query_timeout = 0
query_wait_timeout = 120
client_idle_timeout = 0
idle_transaction_timeout = 0

# Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

# Performance
max_packet_size = 2147483647
pkt_buf = 4096
listen_backlog = 128
```

## Application Deployment

### PHP Deployment (Laravel)

```bash
#!/bin/bash
# deploy.sh

set -e

echo "🚀 Deploying Laravel Application..."

# Pull latest code
git pull origin main

# Install dependencies
composer install --no-dev --optimize-autoloader

# Clear and cache config
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run migrations
php artisan migrate --force

# Restart services
sudo systemctl restart php-fpm
sudo systemctl restart nginx

echo "✅ Deployment complete!"
```

### Ruby Deployment (Rails with Capistrano)

```ruby
# config/deploy.rb
lock '~> 3.18.0'

set :application, 'myapp'
set :repo_url, 'git@github.com:user/myapp.git'
set :deploy_to, '/var/www/myapp'
set :branch, 'main'

set :linked_files, %w{config/database.yml config/master.key}
set :linked_dirs, %w{log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}

set :keep_releases, 5

namespace :deploy do
  after :finishing, 'deploy:cleanup'
  
  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :sudo, :systemctl, :restart, :puma
    end
  end
  
  after :publishing, :restart
end
```

### Zero-Downtime Deployment

```bash
#!/bin/bash
# Blue-Green Deployment Script

BLUE_PORT=8000
GREEN_PORT=8001
CURRENT=$(curl -s http://localhost/health | jq -r '.port')

if [ "$CURRENT" == "$BLUE_PORT" ]; then
    NEW_PORT=$GREEN_PORT
    OLD_PORT=$BLUE_PORT
else
    NEW_PORT=$BLUE_PORT
    OLD_PORT=$GREEN_PORT
fi

echo "Deploying to port $NEW_PORT..."

# Deploy new version
docker-compose up -d app-$NEW_PORT

# Wait for health check
for i in {1..30}; do
    if curl -f http://localhost:$NEW_PORT/health; then
        echo "New version healthy!"
        break
    fi
    sleep 2
done

# Switch traffic
nginx -s reload

# Stop old version
docker-compose stop app-$OLD_PORT

echo "Deployment complete!"
```

## Monitoring & Alerting

### Prometheus Metrics

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
  
  - job_name: 'pgbouncer'
    static_configs:
      - targets: ['pgbouncer-exporter:9127']
  
  - job_name: 'application'
    static_configs:
      - targets: ['app:8000']
```

### Grafana Dashboards

Key metrics to monitor:

1. **Database Metrics**
   - Active connections
   - Transaction rate
   - Query duration (p50, p95, p99)
   - Cache hit ratio
   - Replication lag
   - Disk usage

2. **Application Metrics**
   - Request rate
   - Response time
   - Error rate
   - Connection pool usage
   - Cache hit ratio

3. **System Metrics**
   - CPU usage
   - Memory usage
   - Disk I/O
   - Network throughput

### Alert Rules

```yaml
# alerts.yml
groups:
  - name: database
    rules:
      - alert: HighConnectionCount
        expr: pg_stat_database_numbackends > 180
        for: 5m
        annotations:
          summary: "High connection count"
      
      - alert: SlowQueries
        expr: rate(pg_stat_statements_mean_time_seconds[5m]) > 1
        for: 5m
        annotations:
          summary: "Slow queries detected"
      
      - alert: ReplicationLag
        expr: pg_replication_lag_seconds > 60
        for: 5m
        annotations:
          summary: "Replication lag > 60s"
      
      - alert: LowCacheHitRatio
        expr: pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read) < 0.95
        for: 10m
        annotations:
          summary: "Cache hit ratio < 95%"
```

## Backup & Recovery

### Automated Backups

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/backups/postgres"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.sql.gz"

# Create backup
pg_dump -h localhost -U postgres -d myapp | gzip > $BACKUP_FILE

# Upload to S3
aws s3 cp $BACKUP_FILE s3://my-backups/postgres/

# Keep only last 7 days locally
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
```

### Point-in-Time Recovery

```bash
# Enable WAL archiving in postgresql.conf
archive_mode = on
archive_command = 'aws s3 cp %p s3://my-wal-archive/%f'

# Restore to specific point in time
pg_basebackup -h primary -D /var/lib/postgresql/data -U replication -P -v -R -X stream

# recovery.conf
restore_command = 'aws s3 cp s3://my-wal-archive/%f %p'
recovery_target_time = '2024-03-15 14:30:00'
```

## Security Hardening

### Database Security

```sql
-- Create application user with limited privileges
CREATE USER app_user WITH PASSWORD 'strong_password';
GRANT CONNECT ON DATABASE myapp TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Revoke public schema privileges
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Enable SSL
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET ssl_cert_file = '/path/to/server.crt';
ALTER SYSTEM SET ssl_key_file = '/path/to/server.key';

-- Restrict connections
-- pg_hba.conf
hostssl all app_user 10.0.0.0/8 md5
host all all 0.0.0.0/0 reject
```

### Application Security

```php
// PHP: Use environment variables
$dsn = sprintf(
    "pgsql:host=%s;port=%d;dbname=%s;sslmode=require",
    getenv('DB_HOST'),
    getenv('DB_PORT'),
    getenv('DB_NAME')
);

$pdo = new PDO($dsn, getenv('DB_USER'), getenv('DB_PASSWORD'), [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_EMULATE_PREPARES => false,
]);
```

```ruby
# Ruby: Use credentials
database_config = Rails.application.credentials.database

DB = Sequel.connect(
  adapter: 'postgres',
  host: database_config[:host],
  database: database_config[:name],
  user: database_config[:user],
  password: database_config[:password],
  sslmode: 'require'
)
```

## Post-Deployment Verification

```bash
#!/bin/bash
# verify-deployment.sh

echo "🔍 Verifying deployment..."

# Check application health
if ! curl -f http://localhost:8000/health; then
    echo "❌ Health check failed"
    exit 1
fi

# Check database connectivity
if ! psql -h localhost -U app_user -d myapp -c "SELECT 1"; then
    echo "❌ Database connection failed"
    exit 1
fi

# Check connection pool
if ! curl -f http://localhost:8000/pool-stats; then
    echo "❌ Connection pool check failed"
    exit 1
fi

# Run smoke tests
if ! ./run-smoke-tests.sh; then
    echo "❌ Smoke tests failed"
    exit 1
fi

echo "✅ Deployment verified successfully!"
```

## Rollback Procedure

```bash
#!/bin/bash
# rollback.sh

echo "⚠️  Rolling back deployment..."

# Revert to previous release
cd /var/www/myapp
ln -sfn releases/$(ls -t releases | sed -n 2p) current

# Restart services
sudo systemctl restart php-fpm
sudo systemctl restart nginx

# Verify rollback
if curl -f http://localhost:8000/health; then
    echo "✅ Rollback successful"
else
    echo "❌ Rollback failed - manual intervention required"
    exit 1
fi
```

## Best Practices

1. **Always test in staging first**
2. **Use blue-green or canary deployments**
3. **Monitor metrics during deployment**
4. **Have rollback plan ready**
5. **Document deployment process**
6. **Automate as much as possible**
7. **Keep backups before major changes**
8. **Test disaster recovery regularly**
9. **Use infrastructure as code**
10. **Implement proper logging and monitoring**
