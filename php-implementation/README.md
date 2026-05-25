# PHP Implementation - PostgreSQL Advanced Features

Working examples using native PDO, Laravel, and Doctrine ORM.

## Quick Start

```bash
# Start services
docker-compose up -d

# Install dependencies
docker-compose exec app composer install

# Copy environment file
docker-compose exec app cp .env.example .env

# Test the API
curl http://localhost:8000
```

## API Endpoints

### JSONB Operations

```bash
# Get products by brand
curl http://localhost:8000/products/brand/Dell

# Get products by CPU
curl http://localhost:8000/products/cpu/i7

# Get products by tag
curl http://localhost:8000/products/tag/electronics

# Search with filters
curl "http://localhost:8000/products/search?brand=Apple&min_price=500&max_price=1000"
```

### Connection Pooling

```bash
# Benchmark direct vs pooled connections
curl http://localhost:8000/benchmark

# Get PgBouncer statistics
curl http://localhost:8000/pool-stats

# Simulate high load
curl "http://localhost:8000/load-test?queries=100"
```

## Key Concepts Demonstrated

### JSONB Operators

- `->` Extract JSON object field as JSON
- `->>` Extract JSON object field as text
- `@>` Contains (does left JSON contain right JSON)
- `||` Concatenate/merge JSONB objects
- `-` Remove key from JSONB object
- `jsonb_set()` Update nested values

### Connection Pooling Benefits

- Reduced connection overhead
- Better resource utilization
- Improved concurrency handling
- Transaction-level pooling with PgBouncer

## Code Structure

- `src/JsonbOperations.php` - JSONB query examples
- `src/ConnectionPooling.php` - Connection pooling patterns
- `public/index.php` - REST API implementation

## Learning Path

1. Review `src/JsonbOperations.php` for JSONB patterns
2. Test queries via API endpoints
3. Study `src/ConnectionPooling.php` for pooling strategies
4. Run benchmarks to see performance differences
5. Experiment with your own queries
