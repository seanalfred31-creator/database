# Quick Start Guide

Get up and running with PostgreSQL Advanced Features in 5 minutes.

## Prerequisites

- Docker and Docker Compose installed
- Basic SQL knowledge
- Familiarity with PHP or Ruby

## Choose Your Track

### PHP Track (Laravel/Doctrine)

```bash
# Navigate to PHP implementation
cd php-implementation

# Start services (PostgreSQL + PgBouncer)
docker-compose up -d

# Install dependencies
docker-compose exec app composer install

# Copy environment file
docker-compose exec app cp .env.example .env

# Test the API
curl http://localhost:8000
```

Expected output:
```json
{
  "message": "PostgreSQL Advanced Features API",
  "endpoints": {
    "GET /products/brand/{brand}": "Get products by brand",
    ...
  }
}
```

### Ruby Track (Rails/Sequel)

```bash
# Navigate to Ruby implementation
cd ruby-implementation

# Start services
docker-compose up -d

# Install dependencies
docker-compose exec app bundle install

# Copy environment file
docker-compose exec app cp .env.example .env

# Test the API
curl http://localhost:3000
```

## Your First JSONB Query

### Via API

```bash
# PHP (port 8000)
curl http://localhost:8000/products/brand/Dell

# Ruby (port 3000)
curl http://localhost:3000/products/brand/Dell
```

### Via SQL

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U pguser -d advanced_pg

# Run JSONB query
SELECT * FROM products WHERE metadata->>'brand' = 'Dell';

# Exit
\q
```

## Test Connection Pooling

```bash
# Benchmark direct vs pooled connections
curl http://localhost:8000/benchmark

# Expected output:
{
  "iterations": 100,
  "direct_time": 0.8234,
  "pooled_time": 0.2156,
  "improvement": "73.82%"
}
```

## Explore the Code

### PHP Examples

```bash
# View JSONB operations
cat php-implementation/src/JsonbOperations.php

# View connection pooling
cat php-implementation/src/ConnectionPooling.php

# View Laravel examples
cat php-implementation/src/LaravelEloquent.php
```

### Ruby Examples

```bash
# View JSONB operations
cat ruby-implementation/lib/jsonb_operations.rb

# View connection pooling
cat ruby-implementation/lib/connection_pooling.rb

# View Rails examples
cat ruby-implementation/lib/rails_active_record.rb
```

## Try the Exercises

Start with the basics:

```bash
# Read the first exercise
cat exercises/01-jsonb-basics.md

# Connect to database
docker-compose exec postgres psql -U pguser -d advanced_pg

# Try the queries from the exercise
```

## Monitor PgBouncer

```bash
# Connect to PgBouncer admin console
docker-compose exec pgbouncer psql -h localhost -p 5432 -U pguser pgbouncer

# Show pool statistics
SHOW POOLS;

# Show active clients
SHOW CLIENTS;

# Exit
\q
```

## Common Commands

### Docker Management

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Restart a service
docker-compose restart postgres
```

### Database Access

```bash
# PostgreSQL (direct)
docker-compose exec postgres psql -U pguser -d advanced_pg

# PgBouncer (pooled)
docker-compose exec postgres psql -h pgbouncer -p 5432 -U pguser -d advanced_pg
```

### API Testing

```bash
# Test all endpoints
curl http://localhost:8000/products/brand/Dell
curl http://localhost:8000/products/cpu/i7
curl http://localhost:8000/products/tag/electronics
curl "http://localhost:8000/products/search?min_price=500&max_price=1000"
curl http://localhost:8000/benchmark
curl http://localhost:8000/pool-stats
```

## Next Steps

1. **Learn JSONB Basics**
   - Read `docs/jsonb-guide.md`
   - Complete `exercises/01-jsonb-basics.md`

2. **Master Connection Pooling**
   - Read `docs/connection-pooling-guide.md`
   - Complete `exercises/03-connection-pooling.md`

3. **Optimize Performance**
   - Read `docs/performance-optimization.md`
   - Run benchmarks and tune settings

4. **Build Real Applications**
   - Try `exercises/04-real-world-scenarios.md`
   - Implement your own use cases

## Troubleshooting

### Services won't start

```bash
# Check if ports are in use
netstat -an | grep 5432
netstat -an | grep 8000

# Use different ports in docker-compose.yml
ports:
  - "5433:5432"  # Instead of 5432:5432
```

### Can't connect to database

```bash
# Check service status
docker-compose ps

# View logs
docker-compose logs postgres

# Restart services
docker-compose restart
```

### API returns errors

```bash
# Check application logs
docker-compose logs app

# Verify database connection
docker-compose exec app php -r "new PDO('pgsql:host=postgres;dbname=advanced_pg', 'pguser', 'pgpass');"
```

## Getting Help

- Check `docs/troubleshooting.md` for common issues
- Review code examples in `src/` or `lib/`
- Read exercise solutions in `exercises/`
- Inspect Docker logs: `docker-compose logs`

## Clean Up

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (deletes database data)
docker-compose down -v

# Remove images
docker-compose down --rmi all
```

## What's Next?

Now that you're set up, dive into:

- **JSONB Operations**: Learn powerful JSON querying
- **Connection Pooling**: Optimize for high concurrency
- **Performance Tuning**: Make queries blazing fast
- **Real-world Patterns**: Build production-ready apps

Happy learning! 🚀
