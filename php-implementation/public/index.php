<?php

require_once __DIR__ . '/../vendor/autoload.php';

use App\JsonbOperations;
use App\ConnectionPooling;

// Load environment variables
if (file_exists(__DIR__ . '/../.env')) {
    $dotenv = Dotenv\Dotenv::createImmutable(__DIR__ . '/..');
    $dotenv->load();
}

// Configuration
$config = [
    'db_host' => getenv('DB_HOST') ?: 'postgres',
    'db_port' => (int)(getenv('DB_PORT') ?: 5432),
    'db_database' => getenv('DB_DATABASE') ?: 'advanced_pg',
    'db_username' => getenv('DB_USERNAME') ?: 'pguser',
    'db_password' => getenv('DB_PASSWORD') ?: 'pgpass',
    'pgbouncer_host' => getenv('PGBOUNCER_HOST') ?: 'pgbouncer',
    'pgbouncer_port' => (int)(getenv('PGBOUNCER_PORT') ?: 5432),
];

// Initialize connection pooling
$pooling = new ConnectionPooling($config);
$pdo = $pooling->getPooledConnection();

// Initialize JSONB operations
$jsonb = new JsonbOperations($pdo);

// Simple routing
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

header('Content-Type: application/json');

try {
    switch ($path) {
        case '/':
            echo json_encode([
                'message' => 'PostgreSQL Advanced Features API',
                'endpoints' => [
                    'GET /products/brand/{brand}' => 'Get products by brand',
                    'GET /products/cpu/{cpu}' => 'Get products by CPU',
                    'GET /products/tag/{tag}' => 'Get products by tag',
                    'GET /products/search' => 'Search products (query params: brand, min_price, max_price, tag)',
                    'GET /benchmark' => 'Benchmark connection pooling',
                    'GET /pool-stats' => 'Get PgBouncer statistics',
                    'GET /load-test' => 'Simulate high load'
                ]
            ], JSON_PRETTY_PRINT);
            break;

        case (preg_match('#^/products/brand/(.+)$#', $path, $matches) ? true : false):
            $products = $jsonb->getProductsByBrand($matches[1]);
            echo json_encode($products, JSON_PRETTY_PRINT);
            break;

        case (preg_match('#^/products/cpu/(.+)$#', $path, $matches) ? true : false):
            $products = $jsonb->getProductsByCpu($matches[1]);
            echo json_encode($products, JSON_PRETTY_PRINT);
            break;

        case (preg_match('#^/products/tag/(.+)$#', $path, $matches) ? true : false):
            $products = $jsonb->getProductsByTag($matches[1]);
            echo json_encode($products, JSON_PRETTY_PRINT);
            break;

        case '/products/search':
            $filters = [];
            if (isset($_GET['brand'])) $filters['brand'] = $_GET['brand'];
            if (isset($_GET['min_price'])) $filters['min_price'] = (float)$_GET['min_price'];
            if (isset($_GET['max_price'])) $filters['max_price'] = (float)$_GET['max_price'];
            if (isset($_GET['tag'])) $filters['tag'] = $_GET['tag'];
            
            $products = $jsonb->searchProducts($filters);
            echo json_encode($products, JSON_PRETTY_PRINT);
            break;

        case '/benchmark':
            $iterations = isset($_GET['iterations']) ? (int)$_GET['iterations'] : 100;
            $results = $pooling->benchmarkConnections($iterations);
            echo json_encode($results, JSON_PRETTY_PRINT);
            break;

        case '/pool-stats':
            $stats = $pooling->getPoolStats();
            echo json_encode($stats, JSON_PRETTY_PRINT);
            break;

        case '/load-test':
            $queries = isset($_GET['queries']) ? (int)$_GET['queries'] : 50;
            $results = $pooling->simulateHighLoad($queries);
            echo json_encode($results, JSON_PRETTY_PRINT);
            break;

        default:
            http_response_code(404);
            echo json_encode(['error' => 'Not found'], JSON_PRETTY_PRINT);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()], JSON_PRETTY_PRINT);
}
