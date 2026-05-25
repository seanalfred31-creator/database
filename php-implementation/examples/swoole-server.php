<?php

/**
 * Swoole HTTP Server with PostgreSQL Connection Pool
 * 
 * Requirements:
 * - Swoole extension: pecl install swoole
 * - PostgreSQL extension: pecl install swoole_postgresql
 * 
 * Run: php examples/swoole-server.php
 * Test: curl http://localhost:9501
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Swoole\Http\Server;
use Swoole\Http\Request;
use Swoole\Http\Response;
use Swoole\Coroutine;
use App\SwooleConnectionPool;

// Check if Swoole is installed
if (!extension_loaded('swoole')) {
    die("Swoole extension is not installed. Install with: pecl install swoole\n");
}

// Configuration
$config = [
    'host' => getenv('DB_HOST') ?: 'localhost',
    'port' => (int)(getenv('DB_PORT') ?: 5433),
    'database' => getenv('DB_DATABASE') ?: 'advanced_pg',
    'username' => getenv('DB_USERNAME') ?: 'pguser',
    'password' => getenv('DB_PASSWORD') ?: 'pgpass',
];

// Create server
$server = new Server('0.0.0.0', 9501);

// Configure server
$server->set([
    'worker_num' => 4,
    'enable_coroutine' => true,
    'max_coroutine' => 10000,
    'log_level' => SWOOLE_LOG_INFO,
]);

// Global connection pool (per worker)
$pool = null;

// Worker start - initialize connection pool
$server->on('WorkerStart', function (Server $server, int $workerId) use ($config, &$pool) {
    echo "Worker #{$workerId} started\n";
    
    try {
        $pool = new SwooleConnectionPool($config, 20);
        echo "Connection pool initialized with 20 connections\n";
    } catch (Exception $e) {
        echo "Failed to initialize connection pool: {$e->getMessage()}\n";
    }
});

// Handle HTTP requests
$server->on('Request', function (Request $request, Response $response) use (&$pool) {
    $path = $request->server['request_uri'];
    $method = $request->server['request_method'];

    // Set CORS headers
    $response->header('Access-Control-Allow-Origin', '*');
    $response->header('Content-Type', 'application/json');

    try {
        $result = match ($path) {
            '/' => handleRoot($pool),
            '/products/brand' => handleBrandQuery($pool, $request),
            '/products/search' => handleSearch($pool, $request),
            '/parallel' => handleParallelQueries($pool),
            '/stats' => handleStats($pool),
            '/benchmark' => handleBenchmark($pool),
            default => ['error' => 'Not found']
        };

        $response->end(json_encode($result, JSON_PRETTY_PRINT));
    } catch (Exception $e) {
        $response->status(500);
        $response->end(json_encode([
            'error' => $e->getMessage(),
            'trace' => $e->getTraceAsString()
        ]));
    }
});

// Route handlers
function handleRoot($pool): array
{
    return [
        'message' => 'Swoole PostgreSQL Server',
        'server' => 'Swoole ' . SWOOLE_VERSION,
        'php' => PHP_VERSION,
        'coroutines' => Coroutine::stats(),
        'pool_stats' => $pool ? $pool->getStats() : null,
        'endpoints' => [
            'GET /' => 'Server info',
            'GET /products/brand?brand=Dell' => 'Query by brand',
            'GET /products/search?min_price=500&max_price=1000' => 'Search products',
            'GET /parallel' => 'Parallel queries demo',
            'GET /stats' => 'Pool statistics',
            'GET /benchmark' => 'Benchmark concurrent queries'
        ]
    ];
}

function handleBrandQuery($pool, Request $request): array
{
    $brand = $request->get['brand'] ?? 'Dell';
    
    $results = $pool->query(
        "SELECT id, name, metadata->>'brand' as brand, metadata->>'price' as price 
         FROM products 
         WHERE metadata->>'brand' = $1 
         LIMIT 10",
        [$brand]
    );

    return [
        'brand' => $brand,
        'count' => count($results),
        'products' => $results
    ];
}

function handleSearch($pool, Request $request): array
{
    $minPrice = $request->get['min_price'] ?? 0;
    $maxPrice = $request->get['max_price'] ?? 10000;
    
    $results = $pool->query(
        "SELECT id, name, metadata->>'brand' as brand, metadata->>'price' as price 
         FROM products 
         WHERE (metadata->>'price')::numeric BETWEEN $1 AND $2 
         ORDER BY (metadata->>'price')::numeric 
         LIMIT 20",
        [$minPrice, $maxPrice]
    );

    return [
        'price_range' => ['min' => $minPrice, 'max' => $maxPrice],
        'count' => count($results),
        'products' => $results
    ];
}

function handleParallelQueries($pool): array
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
            'sql' => "SELECT 
                        COUNT(*) as total,
                        AVG((metadata->>'price')::numeric) as avg_price,
                        MIN((metadata->>'price')::numeric) as min_price,
                        MAX((metadata->>'price')::numeric) as max_price
                      FROM products"
        ]
    ];

    $startTime = microtime(true);
    $results = $pool->parallelQueries($queries);
    $duration = microtime(true) - $startTime;

    return [
        'results' => $results,
        'execution_time' => round($duration, 4),
        'queries_executed' => count($queries)
    ];
}

function handleStats($pool): array
{
    return [
        'pool' => $pool->getStats(),
        'coroutines' => Coroutine::stats(),
        'server' => [
            'swoole_version' => SWOOLE_VERSION,
            'php_version' => PHP_VERSION,
            'memory_usage' => memory_get_usage(true),
            'memory_peak' => memory_get_peak_usage(true)
        ]
    ];
}

function handleBenchmark($pool): array
{
    $iterations = 100;
    $concurrency = 50;
    
    $startTime = microtime(true);
    $wg = new Coroutine\WaitGroup();
    $results = [];

    for ($i = 0; $i < $concurrency; $i++) {
        $wg->add();
        
        Coroutine::create(function () use ($pool, $iterations, &$results, $wg, $i) {
            $queries = 0;
            $errors = 0;
            
            for ($j = 0; $j < $iterations / $concurrency; $j++) {
                try {
                    $pool->query("SELECT 1");
                    $queries++;
                } catch (Exception $e) {
                    $errors++;
                }
            }
            
            $results[$i] = ['queries' => $queries, 'errors' => $errors];
            $wg->done();
        });
    }

    $wg->wait();
    $duration = microtime(true) - $startTime;

    $totalQueries = array_sum(array_column($results, 'queries'));
    $totalErrors = array_sum(array_column($results, 'errors'));

    return [
        'iterations' => $iterations,
        'concurrency' => $concurrency,
        'total_queries' => $totalQueries,
        'total_errors' => $totalErrors,
        'duration' => round($duration, 4),
        'queries_per_second' => round($totalQueries / $duration, 2),
        'avg_latency_ms' => round(($duration / $totalQueries) * 1000, 2)
    ];
}

// Start server
echo "Starting Swoole server on http://0.0.0.0:9501\n";
echo "Press Ctrl+C to stop\n\n";

$server->start();
