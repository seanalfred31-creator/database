# Ruby ORM Comparison Guide

Compare ActiveRecord, Sequel, and ROM for PostgreSQL with JSONB.

## Overview

| Feature | ActiveRecord | Sequel | ROM |
|---------|-------------|--------|-----|
| Learning Curve | Easy | Moderate | Steep |
| Performance | Good | Excellent | Excellent |
| Flexibility | Moderate | High | Very High |
| JSONB Support | Good | Excellent | Excellent |
| Architecture | Active Record | Data Mapper | Repository Pattern |
| Best For | Rails apps | Performance | Complex domains |

## ActiveRecord

### Pros
- Integrated with Rails
- Convention over configuration
- Large ecosystem
- Easy to learn

### Cons
- Tight coupling
- Less flexible
- Performance overhead
- Magic can be confusing

### JSONB Example

```ruby
class Product < ActiveRecord::Base
  scope :by_brand, ->(brand) { where("metadata->>'brand' = ?", brand) }
  
  def brand
    metadata['brand']
  end
end

# Usage
Product.by_brand('Dell').where("(metadata->>'price')::numeric < 1000")
```

### When to Use
- Building Rails applications
- Rapid prototyping
- Standard CRUD operations
- Team familiar with Rails

## Sequel

### Pros
- Excellent performance
- Flexible query building
- Great PostgreSQL support
- Thread-safe
- Minimal overhead

### Cons
- Less Rails integration
- Smaller ecosystem
- Manual setup required

### JSONB Example

```ruby
DB[:products]
  .where(Sequel.lit("metadata->>'brand' = ?", 'Dell'))
  .where(Sequel.lit("(metadata->>'price')::numeric < 1000"))
  .all
```

### When to Use
- Performance-critical applications
- Non-Rails projects
- Complex SQL queries
- Connection pooling needs
- Microservices

## ROM (Ruby Object Mapper)

### Pros
- Clean architecture
- Explicit data flow
- Composable queries
- Type safety (with Dry::Types)
- Testable

### Cons
- Steep learning curve
- More boilerplate
- Smaller community
- Requires discipline

### JSONB Example

```ruby
class Products < ROM::Relation[:sql]
  def by_brand(brand)
    where(Sequel.lit("metadata->>'brand' = ?", brand))
  end
  
  def affordable
    where(Sequel.lit("(metadata->>'price')::numeric < 1000"))
  end
end

class ProductRepository < ROM::Repository[:products]
  def find_affordable_by_brand(brand)
    products.by_brand(brand).affordable.to_a
  end
end

# Usage
repo.find_affordable_by_brand('Dell')
```

### When to Use
- Complex business logic
- Domain-driven design
- Large teams
- Long-term maintainability
- Explicit over implicit

## Performance Comparison

### Query Execution (1000 iterations)

```ruby
require 'benchmark/ips'

Benchmark.ips do |x|
  x.report("ActiveRecord") do
    Product.where("metadata->>'brand' = 'Dell'").to_a
  end
  
  x.report("Sequel") do
    DB[:products].where(Sequel.lit("metadata->>'brand' = 'Dell'")).all
  end
  
  x.report("ROM") do
    repo.find_by_brand('Dell')
  end
  
  x.compare!
end
```

Typical results:
```
Sequel:      1500.0 i/s
ROM:         1450.0 i/s
ActiveRecord: 1200.0 i/s
```

### Memory Usage

```ruby
require 'memory_profiler'

# ActiveRecord
report = MemoryProfiler.report do
  Product.limit(1000).to_a
end
# ~2.5 MB allocated

# Sequel
report = MemoryProfiler.report do
  DB[:products].limit(1000).all
end
# ~1.8 MB allocated

# ROM
report = MemoryProfiler.report do
  repo.products.limit(1000).to_a
end
# ~2.0 MB allocated
```

## JSONB Operations Comparison

### Query by Brand

**ActiveRecord:**
```ruby
Product.where("metadata->>'brand' = ?", 'Dell')
```

**Sequel:**
```ruby
DB[:products].where(Sequel.lit("metadata->>'brand' = ?", 'Dell'))
```

**ROM:**
```ruby
products.by_brand('Dell')  # Custom relation method
```

### Update JSONB Field

**ActiveRecord:**
```ruby
product.update(
  metadata: product.metadata.merge(price: 99.99)
)
```

**Sequel:**
```ruby
DB[:products]
  .where(id: id)
  .update(Sequel.lit("metadata = jsonb_set(metadata, '{price}', ?::jsonb)", 99.99.to_json))
```

**ROM:**
```ruby
products
  .by_pk(id)
  .command(:update)
  .call(metadata: Sequel.lit("jsonb_set(metadata, '{price}', ?::jsonb)", 99.99.to_json))
```

### Complex Search

**ActiveRecord:**
```ruby
Product
  .where("metadata->>'brand' = ?", 'Dell')
  .where("(metadata->>'price')::numeric BETWEEN ? AND ?", 500, 1000)
  .where("metadata->'tags' @> ?::jsonb", ['electronics'].to_json)
```

**Sequel:**
```ruby
DB[:products]
  .where(Sequel.lit("metadata->>'brand' = ?", 'Dell'))
  .where(Sequel.lit("(metadata->>'price')::numeric BETWEEN ? AND ?", 500, 1000))
  .where(Sequel.lit("metadata->'tags' @> ?::jsonb", ['electronics'].to_json))
```

**ROM:**
```ruby
products
  .by_brand('Dell')
  .price_range(500, 1000)
  .with_tag('electronics')
```

## Connection Pooling

### ActiveRecord

```ruby
# config/database.yml
production:
  adapter: postgresql
  pool: 25
  timeout: 5000
  checkout_timeout: 5
```

### Sequel

```ruby
DB = Sequel.connect(
  'postgresql://user:pass@host/db',
  max_connections: 25,
  pool_timeout: 5,
  connect_timeout: 5
)
```

### ROM

```ruby
ROM.container(:sql, database_url) do |config|
  config.gateways[:default].connection.pool.max_size = 25
end
```

## Async Support

### ActiveRecord
- Limited async support
- Use with Async gem requires care
- Connection pool not async-aware

### Sequel
- Thread-safe by default
- Works well with Async gem
- Connection pool handles concurrency

### ROM
- Built on Sequel
- Same async capabilities
- Clean separation helps testing

## Testing

### ActiveRecord

```ruby
RSpec.describe Product do
  it "finds by brand" do
    create(:product, metadata: { brand: 'Dell' })
    expect(Product.by_brand('Dell').count).to eq(1)
  end
end
```

### Sequel

```ruby
RSpec.describe "Products" do
  it "finds by brand" do
    DB[:products].insert(name: 'Test', metadata: Sequel.pg_jsonb(brand: 'Dell'))
    expect(DB[:products].where(Sequel.lit("metadata->>'brand' = 'Dell'")).count).to eq(1)
  end
end
```

### ROM

```ruby
RSpec.describe ProductRepository do
  let(:repo) { ProductRepository.new(rom) }
  
  it "finds by brand" do
    repo.create_product('Test', { brand: 'Dell' })
    expect(repo.find_by_brand('Dell').size).to eq(1)
  end
end
```

## Migration Strategies

### From ActiveRecord to Sequel

1. Keep models initially
2. Replace queries gradually
3. Use Sequel for new features
4. Migrate critical paths first

### From ActiveRecord to ROM

1. Start with repositories
2. Keep ActiveRecord for reads
3. Use ROM for writes
4. Gradually migrate domains

### From Sequel to ROM

1. Wrap Sequel in repositories
2. Add relations layer
3. Introduce structs
4. Refactor incrementally

## Decision Matrix

Choose **ActiveRecord** if:
- Building Rails application
- Team knows Rails well
- Standard CRUD operations
- Rapid development priority

Choose **Sequel** if:
- Performance is critical
- Complex SQL queries needed
- Non-Rails application
- Connection pooling important
- Microservices architecture

Choose **ROM** if:
- Complex business logic
- Large codebase
- Multiple data sources
- Domain-driven design
- Long-term maintainability
- Team values explicit code

## Hybrid Approach

You can use multiple ORMs:

```ruby
# ActiveRecord for simple models
class User < ActiveRecord::Base
end

# Sequel for performance-critical queries
ANALYTICS_DB = Sequel.connect(ENV['ANALYTICS_URL'])

# ROM for complex domains
class OrderRepository < ROM::Repository[:orders]
  # Complex order processing logic
end
```

## Recommendations

### Small Projects
- Use ActiveRecord (if Rails) or Sequel

### Medium Projects
- Sequel for flexibility and performance
- Consider ROM for complex domains

### Large Projects
- ROM for maintainability
- Sequel for performance-critical paths
- ActiveRecord for simple CRUD

### Microservices
- Sequel for lightweight footprint
- ROM for complex services

## Resources

### ActiveRecord
- [Rails Guides](https://guides.rubyonrails.org/active_record_basics.html)
- [API Documentation](https://api.rubyonrails.org/)

### Sequel
- [Official Documentation](https://sequel.jeremyevans.net/)
- [PostgreSQL Guide](https://sequel.jeremyevans.net/rdoc/files/doc/postgresql_rdoc.html)

### ROM
- [Official Website](https://rom-rb.org/)
- [Learn ROM](https://rom-rb.org/learn/)
- [ROM SQL](https://github.com/rom-rb/rom-sql)
