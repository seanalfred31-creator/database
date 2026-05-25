# Learning Path

A structured guide to mastering PostgreSQL Advanced Features.

## Overview

This module teaches two critical PostgreSQL skills:
1. **JSONB Operations** - Flexible data modeling and querying
2. **Connection Pooling** - High-performance database access

Estimated time: 8-12 hours

## Prerequisites

- Basic SQL knowledge (SELECT, INSERT, UPDATE, DELETE)
- Familiarity with either PHP or Ruby
- Docker installed on your machine
- Understanding of JSON format

## Phase 1: Setup & Basics (1-2 hours)

### Goals
- Get environment running
- Understand JSONB basics
- Make first queries

### Steps

1. **Environment Setup** (30 min)
   - Follow `QUICKSTART.md`
   - Start Docker services
   - Test API endpoints
   - Connect to database

2. **JSONB Introduction** (30 min)
   - Read `docs/jsonb-guide.md` (sections 1-3)
   - Understand JSONB vs JSON
   - Learn basic operators (`->`, `->>`, `@>`)

3. **First Queries** (30 min)
   - Complete `exercises/01-jsonb-basics.md`
   - Practice extraction operators
   - Try containment queries

4. **Code Review** (30 min)
   - PHP: Review `src/JsonbOperations.php`
   - Ruby: Review `lib/jsonb_operations.rb`
   - Run `examples/basic-usage.php` or `examples/basic_usage.rb`

### Checkpoint
✓ Can query JSONB fields  
✓ Understand `->` vs `->>`  
✓ Can use `@>` for containment  
✓ Environment is working

## Phase 2: Advanced JSONB (2-3 hours)

### Goals
- Master complex queries
- Learn update operations
- Understand indexing

### Steps

1. **Advanced Queries** (45 min)
   - Read `docs/jsonb-guide.md` (sections 4-6)
   - Learn `jsonb_set()`, `jsonb_insert()`
   - Practice nested updates

2. **Exercises** (60 min)
   - Complete `exercises/02-jsonb-advanced.md`
   - Try aggregations
   - Practice complex filters

3. **Indexing Strategy** (45 min)
   - Read `docs/performance-optimization.md` (JSONB section)
   - Create GIN indexes
   - Compare query plans with EXPLAIN

4. **ORM Integration** (30 min)
   - PHP: Review `src/LaravelEloquent.php` or `src/DoctrineOrm.php`
   - Ruby: Review `lib/rails_active_record.rb`
   - Understand ORM patterns

### Checkpoint
✓ Can update nested JSONB  
✓ Understand GIN indexes  
✓ Can write complex queries  
✓ Know when to use JSONB

## Phase 3: Connection Pooling (2-3 hours)

### Goals
- Understand pooling benefits
- Configure PgBouncer
- Optimize for concurrency

### Steps

1. **Pooling Concepts** (45 min)
   - Read `docs/connection-pooling-guide.md` (sections 1-2)
   - Understand pool modes
   - Learn when to use pooling

2. **PgBouncer Setup** (30 min)
   - Review `docker-compose.yml`
   - Understand configuration
   - Monitor with `SHOW POOLS`

3. **Benchmarking** (45 min)
   - Run connection benchmarks
   - Compare direct vs pooled
   - Test under load

4. **Exercises** (60 min)
   - Complete `exercises/03-connection-pooling.md`
   - Tune pool sizes
   - Monitor statistics

### Checkpoint
✓ Understand transaction mode  
✓ Can configure PgBouncer  
✓ Know optimal pool sizes  
✓ Can monitor pool health

## Phase 4: Performance Optimization (2-3 hours)

### Goals
- Optimize queries
- Tune connection pools
- Handle high load

### Steps

1. **Query Optimization** (60 min)
   - Read `docs/performance-optimization.md`
   - Use EXPLAIN ANALYZE
   - Optimize slow queries

2. **Index Tuning** (45 min)
   - Create expression indexes
   - Use partial indexes
   - Monitor index usage

3. **Pool Tuning** (45 min)
   - Calculate optimal sizes
   - Test different modes
   - Handle saturation

4. **Load Testing** (30 min)
   - Simulate high concurrency
   - Monitor performance
   - Identify bottlenecks

### Checkpoint
✓ Can optimize queries  
✓ Know indexing strategies  
✓ Can tune pool sizes  
✓ Understand bottlenecks

## Phase 5: Real-World Applications (3-4 hours)

### Goals
- Apply to practical scenarios
- Build complete features
- Handle edge cases

### Steps

1. **Scenario Study** (60 min)
   - Read `exercises/04-real-world-scenarios.md`
   - Understand use cases
   - Review schema designs

2. **E-commerce Catalog** (60 min)
   - Implement product catalog
   - Handle variants
   - Add search functionality

3. **Session Management** (60 min)
   - Build session store
   - Implement expiration
   - Handle concurrency

4. **Analytics Events** (60 min)
   - Track events
   - Build funnels
   - Generate reports

### Checkpoint
✓ Can design JSONB schemas  
✓ Handle real workloads  
✓ Implement complete features  
✓ Know best practices

## Phase 6: Troubleshooting & Mastery (1-2 hours)

### Goals
- Debug common issues
- Handle edge cases
- Master advanced patterns

### Steps

1. **Troubleshooting** (45 min)
   - Read `docs/troubleshooting.md`
   - Practice debugging
   - Learn recovery techniques

2. **Advanced Patterns** (45 min)
   - Review `src/PdoInternals.php`
   - Study transaction handling
   - Learn batch operations

3. **Final Project** (optional)
   - Build complete application
   - Combine all concepts
   - Optimize for production

### Checkpoint
✓ Can debug issues  
✓ Handle edge cases  
✓ Ready for production  
✓ Confident with PostgreSQL

## Learning Resources

### Documentation
- `docs/jsonb-guide.md` - Complete JSONB reference
- `docs/connection-pooling-guide.md` - Pooling deep dive
- `docs/performance-optimization.md` - Optimization techniques
- `docs/troubleshooting.md` - Common issues

### Code Examples
- `php-implementation/src/` - PHP implementations (PDO, Laravel, Doctrine)
- `ruby-implementation/lib/` - Ruby implementations (Sequel, ActiveRecord, ROM, Async)
- `examples/` - Runnable examples for each language/ORM

### Exercises
- `exercises/01-jsonb-basics.md` - Start here
- `exercises/02-jsonb-advanced.md` - Advanced queries
- `exercises/03-connection-pooling.md` - Pooling practice
- `exercises/04-real-world-scenarios.md` - Real applications

## Tips for Success

1. **Hands-on Practice**
   - Don't just read - try every example
   - Experiment with variations
   - Break things and fix them

2. **Use EXPLAIN**
   - Always check query plans
   - Understand index usage
   - Measure performance

3. **Monitor Everything**
   - Watch connection pools
   - Track query times
   - Check resource usage

4. **Start Simple**
   - Master basics first
   - Add complexity gradually
   - Refactor as you learn

5. **Read Code**
   - Study implementations
   - Understand patterns
   - Learn from examples

## Assessment

Test your knowledge:

### JSONB
- [ ] Can extract nested fields
- [ ] Understand all operators
- [ ] Can update JSONB efficiently
- [ ] Know when to use GIN indexes
- [ ] Can write complex queries

### Connection Pooling
- [ ] Understand pool modes
- [ ] Can configure PgBouncer
- [ ] Know optimal pool sizes
- [ ] Can monitor pool health
- [ ] Handle connection issues

### Performance
- [ ] Can optimize queries
- [ ] Use EXPLAIN effectively
- [ ] Create proper indexes
- [ ] Tune for workload
- [ ] Handle high concurrency

### Real-World
- [ ] Design JSONB schemas
- [ ] Build complete features
- [ ] Handle edge cases
- [ ] Debug issues
- [ ] Production-ready code

## Next Steps

After completing this module:

1. **Build Projects**
   - Apply to your applications
   - Experiment with patterns
   - Share your learnings

2. **Explore Further**
   - PostgreSQL full-text search
   - Advanced indexing (BRIN, GIST)
   - Partitioning strategies
   - Replication and HA

3. **Stay Updated**
   - Follow PostgreSQL releases
   - Join community forums
   - Read performance blogs
   - Contribute back

## Getting Help

- Review `docs/troubleshooting.md`
- Check code examples
- Read PostgreSQL docs
- Ask in community forums

Good luck on your learning journey! 🚀
