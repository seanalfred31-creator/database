# Testing Strategies for PostgreSQL Applications

Comprehensive testing guide for JSONB operations and connection pooling.

## Table of Contents

1. [Unit Testing](#unit-testing)
2. [Integration Testing](#integration-testing)
3. [Performance Testing](#performance-testing)
4. [Connection Pool Testing](#connection-pool-testing)
5. [Test Data Management](#test-data-management)
6. [CI/CD Integration](#cicd-integration)

## Unit Testing

### PHP with PHPUnit

#### Setup

```php
// tests/bootstrap.php
<?php

require_once __DIR__ . '/../vendor/autoload.php';

// Test database configuration
$testConfig = [
    'host' => getenv('TEST_DB_HOST') ?: 'localhost',
    'port' => (int)(getenv('TEST_DB_PORT') ?: 5433),
    'database' => getenv('TEST_DB_DATABASE') ?: 'test_db',
    'username' => getenv('TEST_DB_USERNAME') ?: 'pguser',
    'password' => getenv('TEST_DB_PASSWORD') ?: 'pgpass',
];
```

#### JSONB Operations Test

```php
// tests/JsonbOperationsTest.php
<?php

use PHPUnit\Framework\TestCase;
use App\JsonbOperations;

class JsonbOperationsTest extends TestCase
{
    private PDO $pdo;
    private JsonbOperations $jsonb;

    protected function setUp(): void
    {
        $this->pdo = $this->createTestConnection();
        $this->jsonb = new JsonbOperations($this->pdo);
        $this->seedTestData();
    }

    protected function tearDown(): void
    {
        $this->cleanupTestData();
    }

    public function testGetProductsByBrand(): void
    {
        $products = $this->jsonb->getProductsByBrand('TestBrand');
        
        $this->assertIsArray($products);
        $this->assertCount(2, $products);
        $this->assertEquals('TestBrand', $products[0]['brand']);
    }

    public function testGetProductsByCpu(): void
    {
        $products = $this->jsonb->getProductsByCpu('i7');
        
        $this->assertNotEmpty($products);
        $this->assertEquals('i7', $products[0]['cpu']);
    }

    public function testUpdateProductPrice(): void
    {
        $productId = $this->createTestProduct();
        
        $result = $this->jsonb->updateProductPrice($productId, 999.99);
        
        $this->assertTrue($result);
        
        // Verify update
        $stmt = $this->pdo->prepare("
            SELECT (metadata->>'price')::numeric as price 
            FROM products WHERE id = ?
        ");
        $stmt->execute([$productId]);
        $product = $stmt->fetch();
        
        $this->assertEquals(999.99, $product['price']);
    }

    public function testSearchProducts(): void
    {
        $results = $this->jsonb->searchProducts([
            'brand' => 'TestBrand',
            'min_price' => 100,
            'max_price' => 500
        ]);
        
        $this->assertIsArray($results);
        foreach ($results as $product) {
            $metadata = json_decode($product['metadata'], true);
            $this->assertEquals('TestBrand', $metadata['brand']);
            $this->assertGreaterThanOrEqual(100, $metadata['price']);
            $this->assertLessThanOrEqual(500, $metadata['price']);
        }
    }

    private function createTestConnection(): PDO
    {
        global $testConfig;
        $dsn = sprintf(
            "pgsql:host=%s;port=%d;dbname=%s",
            $testConfig['host'],
            $testConfig['port'],
            $testConfig['database']
        );
        return new PDO($dsn, $testConfig['username'], $testConfig['password']);
    }

    private function seedTestData(): void
    {
        $this->pdo->exec("
            INSERT INTO products (name, metadata) VALUES
            ('Test Product 1', '{\"brand\": \"TestBrand\", \"price\": 299.99, \"specs\": {\"cpu\": \"i7\"}}'),
            ('Test Product 2', '{\"brand\": \"TestBrand\", \"price\": 399.99, \"specs\": {\"cpu\": \"i5\"}}')
        ");
    }

    private function cleanupTestData(): void
    {
        $this->pdo->exec("DELETE FROM products WHERE metadata->>'brand' = 'TestBrand'");
    }

    private function createTestProduct(): string
    {
        $stmt = $this->pdo->prepare("
            INSERT INTO products (name, metadata) 
            VALUES (?, ?::jsonb) 
            RETURNING id
        ");
        $stmt->execute([
            'Test Product',
            json_encode(['brand' => 'TestBrand', 'price' => 199.99])
        ]);
        return $stmt->fetchColumn();
    }
}
```

#### Connection Pool Test

```php
// tests/ConnectionPoolingTest.php
<?php

use PHPUnit\Framework\TestCase;
use App\ConnectionPooling;

class ConnectionPoolingTest extends TestCase
{
    private ConnectionPooling $pooling;

    protected function setUp(): void
    {
        global $testConfig;
        $this->pooling = new ConnectionPooling($testConfig);
    }

    public function testGetDirectConnection(): void
    {
        $conn = $this->pooling->getDirectConnection();
        
        $this->assertInstanceOf(PDO::class, $conn);
        
        // Test connection works
        $result = $conn->query("SELECT 1")->fetch();
        $this->assertEquals(1, $result[0]);
    }

    public function testGetPooledConnection(): void
    {
        $conn = $this->pooling->getPooledConnection();
        
        $this->assertInstanceOf(PDO::class, $conn);
        
        // Test connection works
        $result = $conn->query("SELECT 1")->fetch();
        $this->assertEquals(1, $result[0]);
    }

    public function testBenchmarkConnections(): void
    {
        $results = $this->pooling->benchmarkConnections(10);
        
        $this->assertArrayHasKey('iterations', $results);
        $this->assertArrayHasKey('direct_time', $results);
        $this->assertArrayHasKey('pooled_time', $results);
        $this->assertArrayHasKey('improvement', $results);
        
        $this->assertEquals(10, $results['iterations']);
        $this->assertGreaterThan(0, $results['direct_time']);
        $this->assertGreaterThan(0, $results['pooled_time']);
    }

    public function testSimulateHighLoad(): void
    {
        $results = $this->pooling->simulateHighLoad(10);
        
        $this->assertArrayHasKey('queries_executed', $results);
        $this->assertArrayHasKey('total_time', $results);
        $this->assertArrayHasKey('queries_per_second', $results);
        
        $this->assertEquals(10, $results['queries_executed']);
        $this->assertGreaterThan(0, $results['queries_per_second']);
    }
}
```

### Ruby with RSpec

#### Setup

```ruby
# spec/spec_helper.rb
require 'sequel'
require 'dotenv'

Dotenv.load('.env.test')

RSpec.configure do |config|
  config.before(:suite) do
    # Setup test database
    DB = Sequel.connect(ENV['TEST_DATABASE_URL'])
  end

  config.before(:each) do
    DB.transaction(rollback: :always, auto_savepoint: true) do
      yield
    end
  end

  config.after(:suite) do
    DB.disconnect
  end
end
```

#### JSONB Operations Test

```ruby
# spec/jsonb_operations_spec.rb
require 'spec_helper'
require_relative '../lib/jsonb_operations'

RSpec.describe JsonbOperations do
  let(:jsonb) { JsonbOperations.new(DB) }

  before(:each) do
    # Seed test data
    DB[:products].insert(
      name: 'Test Product 1',
      metadata: Sequel.pg_jsonb(
        brand: 'TestBrand',
        price: 299.99,
        specs: { cpu: 'i7' },
        tags: ['electronics', 'test']
      )
    )
    
    DB[:products].insert(
      name: 'Test Product 2',
      metadata: Sequel.pg_jsonb(
        brand: 'TestBrand',
        price: 399.99,
        specs: { cpu: 'i5' },
        tags: ['electronics', 'test']
      )
    )
  end

  describe '#get_products_by_brand' do
    it 'returns products for given brand' do
      products = jsonb.get_products_by_brand('TestBrand')
      
      expect(products).to be_an(Array)
      expect(products.size).to eq(2)
      expect(products.first[:name]).to eq('Test Product 1')
    end

    it 'returns empty array for non-existent brand' do
      products = jsonb.get_products_by_brand('NonExistent')
      expect(products).to be_empty
    end
  end

  describe '#get_products_by_cpu' do
    it 'returns products with specified CPU' do
      products = jsonb.get_products_by_cpu('i7')
      
      expect(products).not_to be_empty
      expect(products.first[:cpu]).to eq('i7')
    end
  end

  describe '#get_products_by_tag' do
    it 'returns products with specified tag' do
      products = jsonb.get_products_by_tag('electronics')
      
      expect(products.size).to eq(2)
    end
  end

  describe '#update_product_price' do
    it 'updates product price' do
      product = DB[:products].first
      
      result = jsonb.update_product_price(product[:id], 999.99)
      
      expect(result).to be > 0
      
      updated = DB[:products].where(id: product[:id]).first
      expect(updated[:metadata]['price']).to eq(999.99)
    end
  end

  describe '#search_products' do
    it 'searches with multiple filters' do
      results = jsonb.search_products(
        brand: 'TestBrand',
        min_price: 200,
        max_price: 400
      )
      
      expect(results).not_to be_empty
      results.each do |product|
        expect(product[:metadata]['brand']).to eq('TestBrand')
        expect(product[:metadata]['price']).to be_between(200, 400)
      end
    end
  end

  describe '#get_price_statistics' do
    it 'returns price statistics' do
      stats = jsonb.get_price_statistics
      
      expect(stats[:total_products]).to eq(2)
      expect(stats[:avg_price]).to be_a(Numeric)
      expect(stats[:min_price]).to eq(299.99)
      expect(stats[:max_price]).to eq(399.99)
    end
  end
end
```

#### Connection Pool Test

```ruby
# spec/connection_pooling_spec.rb
require 'spec_helper'
require_relative '../lib/connection_pooling'

RSpec.describe ConnectionPooling do
  let(:direct_url) { ENV['TEST_DATABASE_URL'] }
  let(:pooled_url) { ENV['TEST_PGBOUNCER_URL'] || direct_url }
  let(:pooling) { ConnectionPooling.new(direct_url, pooled_url) }

  describe '#benchmark_connections' do
    it 'benchmarks direct vs pooled connections' do
      results = pooling.benchmark_connections(10)
      
      expect(results[:iterations]).to eq(10)
      expect(results[:direct_time]).to be > 0
      expect(results[:pooled_time]).to be > 0
      expect(results[:improvement]).to match(/\d+\.\d+%/)
    end
  end

  describe '#get_pool_stats' do
    it 'returns pool statistics' do
      stats = pooling.get_pool_stats
      
      expect(stats).to have_key(:direct_pool)
      expect(stats).to have_key(:pooled_pool)
      expect(stats[:direct_pool][:size]).to be > 0
    end
  end

  describe '#simulate_high_load' do
    it 'handles concurrent queries' do
      results = pooling.simulate_high_load(10)
      
      expect(results[:queries_executed]).to eq(10)
      expect(results[:total_time]).to be > 0
      expect(results[:queries_per_second]).to be > 0
    end
  end

  describe '#test_transaction_pooling' do
    it 'tests transaction handling' do
      results = pooling.test_transaction_pooling
      
      expect(results[:direct_transaction_time]).to be > 0
      expect(results[:pooled_transaction_time]).to be > 0
      expect(results[:note]).to be_a(String)
    end
  end
end
```

## Integration Testing

### Database Fixtures

```ruby
# spec/support/fixtures.rb
module Fixtures
  def self.create_products(count = 10)
    count.times do |i|
      DB[:products].insert(
        name: "Product #{i}",
        metadata: Sequel.pg_jsonb(
          brand: ['Dell', 'Apple', 'Sony'].sample,
          price: rand(100.0..1000.0).round(2),
          specs: {
            cpu: ['i5', 'i7', 'i9'].sample,
            ram: ['8GB', '16GB', '32GB'].sample
          },
          tags: ['electronics', 'computers'].sample(rand(1..2))
        )
      )
    end
  end

  def self.cleanup
    DB[:products].where(Sequel.lit("metadata->>'brand' IN ('Dell', 'Apple', 'Sony')")).delete
  end
end
```

### API Integration Tests

```php
// tests/Integration/ApiTest.php
<?php

use PHPUnit\Framework\TestCase;

class ApiTest extends TestCase
{
    private string $baseUrl = 'http://localhost:8000';

    public function testGetProductsByBrand(): void
    {
        $response = file_get_contents($this->baseUrl . '/products/brand/Dell');
        $data = json_decode($response, true);
        
        $this->assertIsArray($data);
        $this->assertArrayHasKey('brand', $data[0]);
        $this->assertEquals('Dell', $data[0]['brand']);
    }

    public function testSearchProducts(): void
    {
        $response = file_get_contents(
            $this->baseUrl . '/products/search?min_price=500&max_price=1000'
        );
        $data = json_decode($response, true);
        
        $this->assertIsArray($data);
        foreach ($data as $product) {
            $metadata = json_decode($product['metadata'], true);
            $this->assertGreaterThanOrEqual(500, $metadata['price']);
            $this->assertLessThanOrEqual(1000, $metadata['price']);
        }
    }

    public function testBenchmarkEndpoint(): void
    {
        $response = file_get_contents($this->baseUrl . '/benchmark');
        $data = json_decode($response, true);
        
        $this->assertArrayHasKey('iterations', $data);
        $this->assertArrayHasKey('direct_time', $data);
        $this->assertArrayHasKey('pooled_time', $data);
        $this->assertArrayHasKey('improvement', $data);
    }
}
```

## Performance Testing

### Load Testing with Apache Bench

```bash
#!/bin/bash
# tests/load-test.sh

echo "=== Load Testing PostgreSQL API ==="

# Test 1: Simple query
echo "Test 1: Simple brand query (1000 requests, 10 concurrent)"
ab -n 1000 -c 10 http://localhost:8000/products/brand/Dell

# Test 2: Complex search
echo "Test 2: Complex search (1000 requests, 50 concurrent)"
ab -n 1000 -c 50 "http://localhost:8000/products/search?min_price=500&max_price=1000"

# Test 3: Benchmark endpoint
echo "Test 3: Benchmark endpoint (100 requests, 10 concurrent)"
ab -n 100 -c 10 http://localhost:8000/benchmark

# Test 4: High concurrency
echo "Test 4: High concurrency (5000 requests, 100 concurrent)"
ab -n 5000 -c 100 http://localhost:8000/products/brand/Dell
```

### Performance Benchmarks

```ruby
# spec/performance/benchmark_spec.rb
require 'benchmark/ips'
require 'spec_helper'

RSpec.describe 'Performance Benchmarks' do
  let(:jsonb) { JsonbOperations.new(DB) }

  it 'benchmarks JSONB queries' do
    Benchmark.ips do |x|
      x.report('brand query') do
        jsonb.get_products_by_brand('Dell')
      end

      x.report('price range') do
        jsonb.search_products(min_price: 500, max_price: 1000)
      end

      x.report('tag query') do
        jsonb.get_products_by_tag('electronics')
      end

      x.compare!
    end
  end

  it 'benchmarks connection pooling' do
    pooling = ConnectionPooling.new(ENV['DATABASE_URL'], ENV['PGBOUNCER_URL'])

    Benchmark.ips do |x|
      x.report('direct connection') do
        pooling.direct_db.fetch('SELECT 1').first
      end

      x.report('pooled connection') do
        pooling.pooled_db.fetch('SELECT 1').first
      end

      x.compare!
    end
  end
end
```

## Connection Pool Testing

### Pool Saturation Test

```ruby
# spec/connection_pool_saturation_spec.rb
require 'spec_helper'

RSpec.describe 'Connection Pool Saturation' do
  it 'handles pool saturation gracefully' do
    pool = ConnectionPool.new(size: 5, timeout: 1) do
      Sequel.connect(ENV['DATABASE_URL'])
    end

    # Try to use more connections than available
    threads = 10.times.map do
      Thread.new do
        begin
          pool.with do |conn|
            sleep 0.5
            conn.fetch('SELECT 1').first
          end
          :success
        rescue ConnectionPool::TimeoutError
          :timeout
        end
      end
    end

    results = threads.map(&:value)
    
    # Some should succeed, some should timeout
    expect(results.count(:success)).to be > 0
    expect(results.count(:timeout)).to be > 0
  end
end
```

### Connection Leak Detection

```php
// tests/ConnectionLeakTest.php
<?php

use PHPUnit\Framework\TestCase;

class ConnectionLeakTest extends TestCase
{
    public function testNoConnectionLeaks(): void
    {
        $pool = new ConnectionPooling($config);
        
        // Get initial connection count
        $initialCount = $this->getConnectionCount();
        
        // Perform many operations
        for ($i = 0; $i < 100; $i++) {
            $conn = $pool->getPooledConnection();
            $conn->query("SELECT 1");
            // Connection should be released automatically
        }
        
        // Wait for connections to be released
        sleep(1);
        
        // Check connection count hasn't grown
        $finalCount = $this->getConnectionCount();
        
        $this->assertLessThanOrEqual($initialCount + 5, $finalCount);
    }

    private function getConnectionCount(): int
    {
        $pdo = new PDO(...);
        $stmt = $pdo->query("SELECT count(*) FROM pg_stat_activity WHERE datname = 'test_db'");
        return (int)$stmt->fetchColumn();
    }
}
```

## Test Data Management

### Database Seeder

```php
// tests/DatabaseSeeder.php
<?php

class DatabaseSeeder
{
    private PDO $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    public function seed(int $count = 100): void
    {
        $brands = ['Dell', 'Apple', 'Sony', 'HP', 'Lenovo'];
        $cpus = ['i5', 'i7', 'i9', 'Ryzen 5', 'Ryzen 7'];
        
        $stmt = $this->pdo->prepare("
            INSERT INTO products (name, metadata)
            VALUES (?, ?::jsonb)
        ");

        for ($i = 0; $i < $count; $i++) {
            $metadata = [
                'brand' => $brands[array_rand($brands)],
                'price' => rand(100, 2000) + (rand(0, 99) / 100),
                'specs' => [
                    'cpu' => $cpus[array_rand($cpus)],
                    'ram' => ['8GB', '16GB', '32GB'][array_rand(['8GB', '16GB', '32GB'])],
                    'storage' => ['256GB', '512GB', '1TB'][array_rand(['256GB', '512GB', '1TB'])]
                ],
                'tags' => array_slice(['electronics', 'computers', 'laptops', 'gaming'], 0, rand(2, 4))
            ];

            $stmt->execute([
                "Product $i",
                json_encode($metadata)
            ]);
        }
    }

    public function cleanup(): void
    {
        $this->pdo->exec("TRUNCATE TABLE products RESTART IDENTITY CASCADE");
    }
}
```

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: test_db
          POSTGRES_USER: pguser
          POSTGRES_PASSWORD: pgpass
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

      pgbouncer:
        image: edoburu/pgbouncer:latest
        env:
          DATABASE_URL: postgres://pguser:pgpass@postgres:5432/test_db
          POOL_MODE: transaction
          MAX_CLIENT_CONN: 100
          DEFAULT_POOL_SIZE: 20
        ports:
          - 6432:5432

    steps:
      - uses: actions/checkout@v3

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
          extensions: pdo, pdo_pgsql

      - name: Install dependencies
        run: composer install

      - name: Run tests
        env:
          TEST_DB_HOST: localhost
          TEST_DB_PORT: 5432
          TEST_DB_DATABASE: test_db
          TEST_DB_USERNAME: pguser
          TEST_DB_PASSWORD: pgpass
        run: vendor/bin/phpunit

      - name: Run Ruby tests
        run: |
          cd ruby-implementation
          bundle install
          bundle exec rspec
```

### Docker Compose for Testing

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  postgres-test:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: test_db
      POSTGRES_USER: pguser
      POSTGRES_PASSWORD: pgpass
    ports:
      - "5433:5432"

  pgbouncer-test:
    image: edoburu/pgbouncer:latest
    environment:
      DATABASE_URL: postgres://pguser:pgpass@postgres-test:5432/test_db
      POOL_MODE: transaction
    ports:
      - "6433:5432"
    depends_on:
      - postgres-test

  test-runner:
    build: .
    volumes:
      - .:/app
    environment:
      TEST_DB_HOST: postgres-test
      TEST_DB_PORT: 5432
      TEST_PGBOUNCER_HOST: pgbouncer-test
      TEST_PGBOUNCER_PORT: 5432
    depends_on:
      - postgres-test
      - pgbouncer-test
    command: vendor/bin/phpunit
```

Run tests:
```bash
docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

## Best Practices

1. **Isolate tests** - Use transactions or cleanup between tests
2. **Use test database** - Never test against production
3. **Seed realistic data** - Test with production-like data volumes
4. **Test edge cases** - Empty results, null values, large datasets
5. **Performance benchmarks** - Track query performance over time
6. **Connection pool tests** - Test saturation and leak scenarios
7. **Integration tests** - Test full request/response cycle
8. **CI/CD automation** - Run tests on every commit
9. **Coverage tracking** - Aim for >80% code coverage
10. **Load testing** - Test under realistic load conditions
