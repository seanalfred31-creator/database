# Ruby Implementation - PostgreSQL Advanced Features

Working examples using multiple Ruby ORMs: Sequel, ActiveRecord, and ROM.

## Quick Start

```bash
# Start services
docker-compose up -d

# Install dependencies
docker-compose exec app bundle install

# Copy environment file
docker-compose exec app cp .env.example .env

# Test the API
curl http://localhost:3000
```

## Ruby ORM Options

This implementation includes three popular Ruby ORMs:

### 1. Sequel (Default)
- Lightweight and fast
- Excellent PostgreSQL support
- Great for connection pooling
- See: `lib/jsonb_operations.rb`, `lib/connection_pooling.rb`

### 2. ActiveRecord
- Rails-compatible
- Convention over configuration
- Familiar to Rails developers
- See: `lib/rails_active_record.rb`

### 3. ROM (Ruby Object Mapper)
- Repository pattern
- Clean architecture
- Explicit data flow
- See: `lib/rom_repository.rb`

### 4. Async Ruby
- High-concurrency operations
- Falcon web server
- Non-blocking I/O
- See: `lib/async_operations.rb`

## API Endpoints

### JSONB Operations

```bash
# Get products by brand
curl http://localhost:3000/products/brand/Dell

# Get products by CPU
curl http://localhost:3000/products/cpu/i7

# Get products by tag
curl http://localhost:3000/products/tag/electronics

# Search with filters
curl "http://localhost:3000/products/search?brand=Apple&min_price=500&max_price=1000"

# Get price statistics
curl http://localhost:3000/products/stats

# Get all unique tags
curl http://localhost:3000/products/tags
```

### Connection Pooling

```bash
# Benchmark direct vs pooled connections
curl http://localhost:3000/benchmark

# Get pool statistics
curl http://localhost:3000/pool-stats

# Simulate high load
curl "http://localhost:3000/load-test?queries=100"

# Test transaction pooling
curl http://localhost:3000/transaction-test
```

### Async Operations (Falcon Server)

```bash
# Start Falcon server
falcon serve --config config/falcon.rb

# Parallel brand queries
curl "http://localhost:3000/products/brands?brands=Dell,Apple,Sony"

# Parallel aggregations
curl http://localhost:3000/aggregations
```

## Running Examples

### Basic Sequel Usage
```bash
ruby examples/basic_usage.rb
```

### ActiveRecord Examples
```bash
ruby examples/activerecord_usage.rb
```

### ROM Examples
```bash
ruby examples/rom_usage.rb
```

### Async Examples
```bash
ruby examples/async_usage.rb
```

## Key Concepts Demonstrated

### JSONB with Sequel

```ruby
# Query JSONB fields
db[:products].where(Sequel.lit("metadata->>'brand' = ?", 'Dell'))

# Array containment
db[:products].where(Sequel.lit("metadata->'tags' @> ?::jsonb", ['electronics'].to_json))

# Update JSONB
db[:products].update(Sequel.lit("metadata = jsonb_set(metadata, '{price}', ?::jsonb)", 999.99.to_json))

# Merge JSONB
db[:products].update(Sequel.lit("metadata = metadata || ?::jsonb", { discount: 10 }.to_json))
```

### JSONB with ActiveRecord

```ruby
# Scopes
Product.by_brand('Dell').price_range(500, 1000).with_tag('electronics')

# Virtual attributes
product.brand  # Extracts from metadata
product.price = 99.99  # Updates metadata
```

### JSONB with ROM

```ruby
# Relations
products.by_brand('Dell').price_range(500, 1000).with_tag('electronics')

# Repository
repo.find_by_brand('Dell')
repo.search(brand: 'Apple', min_price: 500, max_price: 1000)
```

### Async Operations

```ruby
# Parallel queries
Async do
  results = async_ops.parallel_brand_queries(['Dell', 'Apple', 'Sony']).wait
end

# Concurrent updates
Async do
  results = async_ops.concurrent_price_updates(updates).wait
end
```

## Code Structure

- `lib/jsonb_operations.rb` - Sequel JSONB patterns
- `lib/connection_pooling.rb` - Connection pooling strategies
- `lib/rails_active_record.rb` - ActiveRecord examples
- `lib/rom_repository.rb` - ROM repository pattern
- `lib/async_operations.rb` - Async/concurrent operations
- `config.ru` - Rack application with API
- `config/falcon.rb` - Falcon async server config
- `examples/` - Runnable examples for each ORM

## ORM Comparison

See `docs/ruby-orm-comparison.md` for detailed comparison of:
- Performance characteristics
- JSONB support
- Connection pooling
- Use cases
- Migration strategies

## Learning Path

1. **Start with Sequel** - `lib/jsonb_operations.rb`
   - Lightweight and fast
   - Great for learning PostgreSQL features

2. **Try ActiveRecord** - `lib/rails_active_record.rb`
   - If you're familiar with Rails
   - Convention over configuration

3. **Explore ROM** - `lib/rom_repository.rb`
   - For complex domains
   - Clean architecture patterns

4. **Experiment with Async** - `lib/async_operations.rb`
   - High-concurrency scenarios
   - Non-blocking I/O patterns

## Performance Tips

- Use Sequel for performance-critical paths
- Use ROM for complex business logic
- Use ActiveRecord for rapid development
- Use Async for high-concurrency workloads
- Always use connection pooling (PgBouncer)
