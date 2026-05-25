# PostgreSQL Advanced Features Module

Production-ready PostgreSQL with JSONB and connection pooling for PHP and Ruby.

## What You'll Learn

### Core Skills
- **JSONB Operations**: Flexible data modeling, complex queries, efficient indexing
- **Connection Pooling**: PgBouncer configuration, pool sizing, monitoring
- **Performance Optimization**: Query profiling, index strategies, bottleneck identification
- **Advanced Architecture**: Swoole, FrankenPHP, Fibers, Async Ruby, ROM patterns

### Language-Specific Implementations

**PHP Track:**
- Native PDO with JSONB
- Laravel Eloquent patterns
- Doctrine ORM integration
- Swoole async I/O
- FrankenPHP worker mode
- PHP 8.1+ Fibers

**Ruby Track:**
- Sequel ORM (lightweight, fast)
- ActiveRecord (Rails-compatible)
- ROM (Repository pattern)
- Async Ruby with Falcon
- ConnectionPool gem
- Puma thread safety

## Prerequisites

- Docker and Docker Compose installed
- Basic SQL knowledge
- Familiarity with either PHP or Ruby
- Understanding of JSON format

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for 5-minute setup guide.

### PHP Track

```bash
cd php-implementation
docker-compose up -d
docker-compose exec app composer install
curl http://localhost:8000
```

### Ruby Track

```bash
cd ruby-implementation
docker-compose up -d
docker-compose exec app bundle install
curl http://localhost:3000
```

## Module Structure

### Core Documentation
- `QUICKSTART.md` - 5-minute setup guide
- `LEARNING-PATH.md` - Structured 8-12 hour curriculum
- `README.md` - This file

### Implementation Code
- `php-implementation/` - PDO, Laravel, Doctrine, Swoole, FrankenPHP, Fibers
- `ruby-implementation/` - Sequel, ActiveRecord, ROM, Async, ConnectionPool

### Comprehensive Guides
- `docs/jsonb-guide.md` - Complete JSONB reference
- `docs/connection-pooling-guide.md` - PgBouncer deep dive
- `docs/performance-optimization.md` - Tuning strategies
- `docs/advanced-architecture-patterns.md` - Modern connection management
- `docs/query-optimization-profiling.md` - EXPLAIN analysis, profiling
- `docs/testing-strategies.md` - Unit, integration, performance tests
- `docs/troubleshooting.md` - Common issues and solutions
- `docs/ruby-orm-comparison.md` - ActiveRecord vs Sequel vs ROM
- `docs/async-ruby-guide.md` - Async patterns with Falcon

### Hands-on Exercises
- `exercises/01-jsonb-basics.md` - JSONB fundamentals
- `exercises/02-jsonb-advanced.md` - Complex queries and aggregations
- `exercises/03-connection-pooling.md` - Pooling optimization
- `exercises/04-real-world-scenarios.md` - Production use cases

### Runnable Examples
- `php-implementation/examples/` - Basic usage, Swoole server, Fiber demo
- `ruby-implementation/examples/` - Sequel, ActiveRecord, ROM, Async

## Topics Covered

### 1. JSONB Data Type
- Storing and querying JSON data
- JSONB operators (`->`, `->>`, `@>`, `?`, `||`)
- Functions (`jsonb_set`, `jsonb_insert`, `jsonb_array_elements`)
- GIN indexes for performance
- Expression indexes for specific fields
- Partial indexes for filtered data

### 2. Connection Pooling
- PgBouncer setup and configuration
- Pool modes (session, transaction, statement)
- Pool sizing calculations
- Monitoring and health checks
- Connection leak detection
- Automatic retry patterns

### 3. Performance Optimization
- EXPLAIN ANALYZE for query profiling
- Index strategies (GIN, expression, partial, composite)
- Query optimization techniques
- Cache hit ratio monitoring
- Slow query identification
- Anti-pattern avoidance

### 4. Advanced Architecture
- **PHP**: Swoole, FrankenPHP, Fibers, PDO gotchas
- **Ruby**: ConnectionPool gem, ActiveRecord multiplexing, Puma thread safety
- Async/concurrent patterns
- Sharding strategies
- Read/write splitting
- Circuit breaker pattern

### 5. Testing Strategies
- Unit testing (PHPUnit, RSpec)
- Integration testing
- Performance benchmarking
- Load testing
- Connection pool testing
- CI/CD integration

## Getting Started

1. **Setup Environment** (5 minutes)
   - Follow [QUICKSTART.md](QUICKSTART.md)
   - Choose PHP or Ruby track
   - Start Docker services

2. **Learn JSONB Basics** (1-2 hours)
   - Read [docs/jsonb-guide.md](docs/jsonb-guide.md)
   - Complete [exercises/01-jsonb-basics.md](exercises/01-jsonb-basics.md)
   - Run examples in your chosen language

3. **Master Connection Pooling** (2-3 hours)
   - Read [docs/connection-pooling-guide.md](docs/connection-pooling-guide.md)
   - Complete [exercises/03-connection-pooling.md](exercises/03-connection-pooling.md)
   - Benchmark and tune pool settings

4. **Optimize Performance** (2-3 hours)
   - Read [docs/query-optimization-profiling.md](docs/query-optimization-profiling.md)
   - Profile your queries with EXPLAIN
   - Implement proper indexing strategies

5. **Explore Advanced Patterns** (3-4 hours)
   - Read [docs/advanced-architecture-patterns.md](docs/advanced-architecture-patterns.md)
   - Try Swoole/Async examples
   - Experiment with different ORMs

6. **Build Real Applications** (3-4 hours)
   - Complete [exercises/04-real-world-scenarios.md](exercises/04-real-world-scenarios.md)
   - Apply patterns to your projects
   - Test and deploy

## Key Features

✅ **Production-Ready Code** - Battle-tested patterns and implementations  
✅ **Multiple ORMs** - Choose what fits your needs (PDO, Laravel, Doctrine, Sequel, ActiveRecord, ROM)  
✅ **Modern Patterns** - Swoole, FrankenPHP, Fibers, Async Ruby  
✅ **Comprehensive Testing** - Unit, integration, and performance tests  
✅ **Docker Everything** - Reproducible environments  
✅ **Real-World Examples** - E-commerce, sessions, analytics, multi-tenant  
✅ **Performance Focus** - Profiling, optimization, monitoring  
✅ **Best Practices** - Security, scalability, maintainability  

## Learning Path

Follow the structured [LEARNING-PATH.md](LEARNING-PATH.md) for optimal learning:

- **Phase 1**: Setup & Basics (1-2 hours)
- **Phase 2**: Advanced JSONB (2-3 hours)
- **Phase 3**: Connection Pooling (2-3 hours)
- **Phase 4**: Performance Optimization (2-3 hours)
- **Phase 5**: Real-World Applications (3-4 hours)
- **Phase 6**: Troubleshooting & Mastery (1-2 hours)

Total: 8-12 hours

## Support

- Check [docs/troubleshooting.md](docs/troubleshooting.md) for common issues
- Review code examples in `examples/` directories
- Read exercise solutions in `exercises/`
- Inspect Docker logs: `docker-compose logs`

## Contributing

Contributions welcome! Areas for improvement:
- Additional language implementations
- More real-world scenarios
- Performance benchmarks
- Additional ORM examples
- Documentation improvements

## License

MIT License - See LICENSE file for details

## Acknowledgments

Built with focus on production-ready PostgreSQL patterns for modern PHP and Ruby applications.
