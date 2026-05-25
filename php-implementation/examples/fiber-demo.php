<?php

/**
 * PHP 8.1+ Fiber Demo with Connection Pool
 * 
 * Requirements: PHP 8.1+
 * 
 * Run: php examples/fiber-demo.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

use App\FiberConnectionPool;
use App\FiberQueryExecutor;

// Check PHP version
if (PHP_VERSION_ID < 80100) {
    die("This demo requires PHP 8.1 or higher. Current version: " . PHP_VERSION . "\n");
}

// Configuration
$config = [
    'host' => getenv('DB_HOST') ?: 'localhost',
    'port' => (int)(getenv('DB_PORT') ?: 5433),
    'database' => getenv('DB_DATABASE') ?: 'advanced_pg',
    'username' => getenv('DB_USERNAME') ?: 'pguser',
    'password' => getenv('DB_PASSWORD') ?: 'pgpass',
];

echo "=== PHP Fiber Connection Pool Demo ===\n\n";

// Example 1: Basic Fiber Usage
echo "1. Basic Fiber usage...\n";

$fiber = new Fiber(function (): string {
    echo "  Fiber started\n";
    Fiber::suspend('suspended');
    echo "  Fiber resumed\n";
    return 'completed';
});

$result = $fiber->start();
echo "  Result after start: $result\n";

$result = $fiber->resume();
echo "  Result after resume: $result\n\n";

// Example 2: Fiber Connection Pool
echo "2. Fiber connection pool...\n";

$pool = new FiberConnectionPool($config, 10);
echo "  Pool initialized with 10 connections\n";

$stats = $pool->getStats();
echo "  Pool stats: " . json_encode($stats) . "\n\n";

// Example 3: Simple Query with Pool
echo "3. Simple query with fiber pool...\n";

$result = $pool->query("SELECT COUNT(*) as count FROM products");
echo "  Total products: {$result[0]['count']}\n\n";

// Example 4: Concurrent Queries with Fibers
echo "4. Concurrent queries with fibers...\n";

$executor = new FiberQueryExecutor($pool);

$queries = [
    'dell' => [
        'sql' => "SELECT COUNT(*) as count FROM products WHERE metadata->>'brand' = ?",
        'params' => ['Dell']
    ],
    'apple' => [
        'sql' => "SELECT COUNT(*) as count FROM products WHERE metadata->>'brand' = ?",
        'params' => ['Apple']
    ],
    'sony' => [
        'sql' => "SELECT COUNT(*) as count FROM products WHERE metadata->>'brand' = ?",
        'params' => ['Sony']
    ],
    'stats' => [
        'sql' => "SELECT 
                    AVG((metadata->>'price')::numeric) as avg_price,
                    MIN((metadata->>'price')::numeric) as min_price,
                    MAX((metadata->>'price')::numeric) as max_price
                  FROM products"
    ]
];

$startTime = microtime(true);
$results = $executor->executeParallel($queries);
$duration = microtime(true) - $startTime;

foreach ($results as $key => $result) {
    echo "  $key: " . json_encode($result[0]) . "\n";
}
echo "  Execution time: " . round($duration, 4) . "s\n\n";

// Example 5: Rate-Limited Execution
echo "5. Rate-limited execution (max 3 concurrent)...\n";

$manyQueries = [];
for ($i = 0; $i < 10; $i++) {
    $manyQueries["query_$i"] = [
        'sql' => "SELECT $i as query_num, COUNT(*) as count FROM products"
    ];
}

$startTime = microtime(true);
$results = $executor->executeWithRateLimit($manyQueries, 3);
$duration = microtime(true) - $startTime;

echo "  Executed " . count($results) . " queries in " . round($duration, 4) . "s\n";
echo "  Average: " . round($duration / count($results), 4) . "s per query\n\n";

// Example 6: Benchmark Sequential vs Fiber
echo "6. Benchmark: Sequential vs Fiber execution...\n";

$testQueries = [
    'q1' => ['sql' => "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", 'params' => ['Dell']],
    'q2' => ['sql' => "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", 'params' => ['Apple']],
    'q3' => ['sql' => "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", 'params' => ['Sony']],
    'q4' => ['sql' => "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", 'params' => ['HP']],
    'q5' => ['sql' => "SELECT COUNT(*) FROM products WHERE metadata->>'brand' = ?", 'params' => ['Lenovo']],
];

// Sequential execution
$startTime = microtime(true);
foreach ($testQueries as $query) {
    $pool->query($query['sql'], $query['params'] ?? []);
}
$sequentialTime = microtime(true) - $startTime;

// Fiber execution
$startTime = microtime(true);
$executor->executeParallel($testQueries);
$fiberTime = microtime(true) - $startTime;

echo "  Sequential: " . round($sequentialTime, 4) . "s\n";
echo "  Fiber: " . round($fiberTime, 4) . "s\n";
echo "  Speedup: " . round($sequentialTime / $fiberTime, 2) . "x\n\n";

// Example 7: Pool Statistics
echo "7. Final pool statistics...\n";

$stats = $pool->getStats();
echo "  Max connections: {$stats['max_connections']}\n";
echo "  Active connections: {$stats['active_connections']}\n";
echo "  Available connections: {$stats['available_connections']}\n";
echo "  In use: {$stats['in_use']}\n\n";

echo "=== Fiber demo completed! ===\n\n";

echo "Key takeaways:\n";
echo "  - Fibers enable cooperative multitasking\n";
echo "  - Connection pool manages resources efficiently\n";
echo "  - Concurrent execution improves throughput\n";
echo "  - Rate limiting prevents resource exhaustion\n";
echo "  - Fibers are simpler than callbacks\n";
