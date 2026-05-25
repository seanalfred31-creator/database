<?php

namespace App;

use Swoole\Coroutine;
use Swoole\Coroutine\Channel;
use Swoole\Coroutine\PostgreSQL;

/**
 * Swoole-based connection pool for PostgreSQL
 * Provides true async I/O and connection pooling
 */
class SwooleConnectionPool
{
    private Channel $pool;
    private array $config;
    private int $poolSize;
    private int $activeConnections = 0;

    public function __construct(array $config, int $poolSize = 20)
    {
        $this->config = $config;
        $this->poolSize = $poolSize;
        $this->pool = new Channel($poolSize);
        
        // Pre-populate pool
        $this->initializePool();
    }

    /**
     * Initialize connection pool
     */
    private function initializePool(): void
    {
        for ($i = 0; $i < $this->poolSize; $i++) {
            $conn = $this->createConnection();
            if ($conn) {
                $this->pool->push($conn);
                $this->activeConnections++;
            }
        }
    }

    /**
     * Create new PostgreSQL connection
     */
    private function createConnection(): ?PostgreSQL
    {
        $pg = new PostgreSQL();
        $connString = sprintf(
            "host=%s port=%d dbname=%s user=%s password=%s",
            $this->config['host'],
            $this->config['port'],
            $this->config['database'],
            $this->config['username'],
            $this->config['password']
        );

        if ($pg->connect($connString)) {
            return $pg;
        }

        return null;
    }

    /**
     * Get connection from pool
     */
    public function getConnection(float $timeout = 5.0): ?PostgreSQL
    {
        return $this->pool->pop($timeout);
    }

    /**
     * Return connection to pool
     */
    public function releaseConnection(PostgreSQL $conn): void
    {
        $this->pool->push($conn);
    }

    /**
     * Execute query with automatic connection management
     */
    public function query(string $sql, array $params = []): array
    {
        $conn = $this->getConnection();
        if (!$conn) {
            throw new \RuntimeException('Failed to get connection from pool');
        }

        try {
            // Prepare statement
            $stmt = $conn->prepare($sql);
            if (!$stmt) {
                throw new \RuntimeException('Failed to prepare statement');
            }

            // Execute with parameters
            $result = $conn->execute($stmt, $params);
            if ($result === false) {
                throw new \RuntimeException('Query execution failed');
            }

            // Fetch all results
            $rows = [];
            while ($row = $conn->fetchAssoc($result)) {
                $rows[] = $row;
            }

            return $rows;
        } finally {
            $this->releaseConnection($conn);
        }
    }

    /**
     * Execute multiple queries concurrently
     */
    public function parallelQueries(array $queries): array
    {
        $results = [];
        $wg = new Coroutine\WaitGroup();

        foreach ($queries as $key => $query) {
            $wg->add();
            
            Coroutine::create(function () use ($query, $key, &$results, $wg) {
                try {
                    $results[$key] = $this->query($query['sql'], $query['params'] ?? []);
                } catch (\Exception $e) {
                    $results[$key] = ['error' => $e->getMessage()];
                } finally {
                    $wg->done();
                }
            });
        }

        $wg->wait();
        return $results;
    }

    /**
     * Get pool statistics
     */
    public function getStats(): array
    {
        return [
            'pool_size' => $this->poolSize,
            'active_connections' => $this->activeConnections,
            'available_connections' => $this->pool->length(),
            'in_use' => $this->activeConnections - $this->pool->length()
        ];
    }

    /**
     * Close all connections
     */
    public function close(): void
    {
        while ($this->pool->length() > 0) {
            $conn = $this->pool->pop();
            // PostgreSQL connections close automatically
        }
    }
}

/**
 * Swoole HTTP Server with connection pooling
 */
class SwooleHttpServer
{
    private SwooleConnectionPool $pool;
    private \Swoole\Http\Server $server;

    public function __construct(array $dbConfig, string $host = '0.0.0.0', int $port = 9501)
    {
        $this->server = new \Swoole\Http\Server($host, $port);
        
        // Configure server
        $this->server->set([
            'worker_num' => 4,
            'enable_coroutine' => true,
            'max_coroutine' => 10000,
        ]);

        // Initialize connection pool on worker start
        $this->server->on('WorkerStart', function ($server, $workerId) use ($dbConfig) {
            $this->pool = new SwooleConnectionPool($dbConfig, 20);
        });

        // Handle requests
        $this->server->on('Request', function ($request, $response) {
            $this->handleRequest($request, $response);
        });
    }

    private function handleRequest($request, $response): void
    {
        $path = $request->server['request_uri'];
        $method = $request->server['request_method'];

        try {
            $result = match ($path) {
                '/' => $this->handleRoot(),
                '/products/brand' => $this->handleBrandQuery($request),
                '/parallel' => $this->handleParallelQueries(),
                '/stats' => $this->pool->getStats(),
                default => ['error' => 'Not found']
            };

            $response->header('Content-Type', 'application/json');
            $response->end(json_encode($result, JSON_PRETTY_PRINT));
        } catch (\Exception $e) {
            $response->status(500);
            $response->end(json_encode(['error' => $e->getMessage()]));
        }
    }

    private function handleRoot(): array
    {
        return [
            'message' => 'Swoole PostgreSQL Server',
            'server' => 'Swoole',
            'coroutines' => Coroutine::stats(),
            'endpoints' => [
                'GET /' => 'Server info',
                'GET /products/brand?brand=Dell' => 'Query by brand',
                'GET /parallel' => 'Parallel queries demo',
                'GET /stats' => 'Pool statistics'
            ]
        ];
    }

    private function handleBrandQuery($request): array
    {
        $brand = $request->get['brand'] ?? 'Dell';
        
        return $this->pool->query(
            "SELECT * FROM products WHERE metadata->>'brand' = $1",
            [$brand]
        );
    }

    private function handleParallelQueries(): array
    {
        $queries = [
            'dell' => [
                'sql' => "SELECT COUNT(*) as count FROM products WHERE metadata->>'brand' = $1",
                'params' => ['Dell']
            ],
            'apple' => [
                'sql' => "SELECT COUNT(*) as count FROM products WHERE metadata->>'brand' = $1",
                'params' => ['Apple']
            ],
            'sony' => [
                'sql' => "SELECT COUNT(*) as count FROM products WHERE metadata->>'brand' = $1",
                'params' => ['Sony']
            ],
            'stats' => [
                'sql' => "SELECT AVG((metadata->>'price')::numeric) as avg_price FROM products"
            ]
        ];

        return $this->pool->parallelQueries($queries);
    }

    public function start(): void
    {
        echo "Swoole server starting on http://0.0.0.0:9501\n";
        $this->server->start();
    }
}

/**
 * Swoole JSONB Operations with Coroutines
 */
class SwooleJsonbOperations
{
    private SwooleConnectionPool $pool;

    public function __construct(SwooleConnectionPool $pool)
    {
        $this->pool = $pool;
    }

    /**
     * Concurrent brand queries
     */
    public function getConcurrentBrands(array $brands): array
    {
        $results = [];
        $wg = new Coroutine\WaitGroup();

        foreach ($brands as $brand) {
            $wg->add();
            
            Coroutine::create(function () use ($brand, &$results, $wg) {
                $results[$brand] = $this->pool->query(
                    "SELECT * FROM products WHERE metadata->>'brand' = $1",
                    [$brand]
                );
                $wg->done();
            });
        }

        $wg->wait();
        return $results;
    }

    /**
     * Concurrent price updates
     */
    public function updatePricesConcurrently(array $updates): array
    {
        $results = [];
        $wg = new Coroutine\WaitGroup();

        foreach ($updates as $id => $price) {
            $wg->add();
            
            Coroutine::create(function () use ($id, $price, &$results, $wg) {
                try {
                    $this->pool->query(
                        "UPDATE products SET metadata = jsonb_set(metadata, '{price}', $1::jsonb) WHERE id = $2",
                        [json_encode($price), $id]
                    );
                    $results[$id] = ['success' => true];
                } catch (\Exception $e) {
                    $results[$id] = ['success' => false, 'error' => $e->getMessage()];
                }
                $wg->done();
            });
        }

        $wg->wait();
        return $results;
    }

    /**
     * Batch insert with coroutines
     */
    public function batchInsert(array $products, int $batchSize = 100): array
    {
        $batches = array_chunk($products, $batchSize);
        $results = [];
        $wg = new Coroutine\WaitGroup();

        foreach ($batches as $index => $batch) {
            $wg->add();
            
            Coroutine::create(function () use ($batch, $index, &$results, $wg) {
                $inserted = 0;
                foreach ($batch as $product) {
                    try {
                        $this->pool->query(
                            "INSERT INTO products (name, metadata) VALUES ($1, $2::jsonb)",
                            [$product['name'], json_encode($product['metadata'])]
                        );
                        $inserted++;
                    } catch (\Exception $e) {
                        // Log error
                    }
                }
                $results[$index] = ['inserted' => $inserted, 'total' => count($batch)];
                $wg->done();
            });
        }

        $wg->wait();
        return $results;
    }
}
