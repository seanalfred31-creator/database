<?php

/**
 * Basic usage examples for PostgreSQL Advanced Features
 * 
 * Run: php examples/basic-usage.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

use App\JsonbOperations;
use App\ConnectionPooling;

// Configuration
$config = [
    'db_host' => getenv('DB_HOST') ?: 'localhost',
    'db_port' => (int)(getenv('DB_PORT') ?: 5433),
    'db_database' => getenv('DB_DATABASE') ?: 'advanced_pg',
    'db_username' => getenv('DB_USERNAME') ?: 'pguser',
    'db_password' => getenv('DB_PASSWORD') ?: 'pgpass',
    'pgbouncer_host' => getenv('PGBOUNCER_HOST') ?: 'localhost',
    'pgbouncer_port' => (int)(getenv('PGBOUNCER_PORT') ?: 6433),
];

echo "=== PostgreSQL Advanced Features - Basic Usage ===\n\n";

// Initialize connection pooling
echo "1. Setting up connection pooling...\n";
$pooling = new ConnectionPooling($config);
$pdo = $pooling->getPooledConnection();
echo "✓ Connected via PgBouncer\n\n";

// Initialize JSONB operations
$jsonb = new JsonbOperations($pdo);

// Example 1: Query by brand
echo "2. Querying products by brand (Dell)...\n";
$dellProducts = $jsonb->getProductsByBrand('Dell');
foreach ($dellProducts as $product) {
    echo "  - {$product['name']} (Brand: {$product['brand']})\n";
}
echo "\n";

// Example 2: Query by CPU
echo "3. Querying products by CPU (i7)...\n";
$i7Products = $jsonb->getProductsByCpu('i7');
foreach ($i7Products as $product) {
    echo "  - {$product['name']} (CPU: {$product['cpu']})\n";
}
echo "\n";

// Example 3: Query by tag
echo "4. Querying products by tag (electronics)...\n";
$electronics = $jsonb->getProductsByTag('electronics');
echo "  Found " . count($electronics) . " products\n\n";

// Example 4: Complex search
echo "5. Complex search (Apple products, $500-$1000)...\n";
$results = $jsonb->searchProducts([
    'brand' => 'Apple',
    'min_price' => 500,
    'max_price' => 1000
]);
foreach ($results as $product) {
    $metadata = json_decode($product['metadata'], true);
    echo "  - {$product['name']}: \${$metadata['price']}\n";
}
echo "\n";

// Example 5: Update product price
echo "6. Updating product price...\n";
$firstProduct = $dellProducts[0] ?? null;
if ($firstProduct) {
    $oldMetadata = json_decode($firstProduct['metadata'], true);
    $oldPrice = $oldMetadata['price'];
    $newPrice = $oldPrice * 0.9; // 10% discount
    
    $jsonb->updateProductPrice($firstProduct['id'], $newPrice);
    echo "  ✓ Updated {$firstProduct['name']} from \${$oldPrice} to \${$newPrice}\n\n";
    
    // Restore original price
    $jsonb->updateProductPrice($firstProduct['id'], $oldPrice);
}

// Example 6: Add and remove discount
echo "7. Adding discount to product...\n";
if ($firstProduct) {
    $jsonb->addProductDiscount($firstProduct['id'], 15);
    echo "  ✓ Added 15% discount\n";
    
    $jsonb->removeProductDiscount($firstProduct['id']);
    echo "  ✓ Removed discount\n\n";
}

// Example 7: Benchmark connection pooling
echo "8. Benchmarking connection pooling...\n";
$benchmark = $pooling->benchmarkConnections(50);
echo "  Iterations: {$benchmark['iterations']}\n";
echo "  Direct time: {$benchmark['direct_time']}s\n";
echo "  Pooled time: {$benchmark['pooled_time']}s\n";
echo "  Improvement: {$benchmark['improvement']}\n\n";

// Example 8: Simulate high load
echo "9. Simulating high load (50 concurrent queries)...\n";
$loadTest = $pooling->simulateHighLoad(50);
echo "  Queries executed: {$loadTest['queries_executed']}\n";
echo "  Total time: {$loadTest['total_time']}s\n";
echo "  Queries per second: {$loadTest['queries_per_second']}\n\n";

// Example 9: Get pool statistics
echo "10. PgBouncer pool statistics...\n";
$stats = $pooling->getPoolStats();
if (isset($stats['error'])) {
    echo "  Note: {$stats['error']}\n";
} else {
    foreach ($stats as $pool) {
        echo "  Database: {$pool['database']}\n";
        echo "  Active connections: {$pool['cl_active']}\n";
        echo "  Waiting clients: {$pool['cl_waiting']}\n";
        break; // Show first pool only
    }
}
echo "\n";

echo "=== All examples completed successfully! ===\n";
echo "\nNext steps:\n";
echo "  - Review the code in src/JsonbOperations.php\n";
echo "  - Try the exercises in exercises/\n";
echo "  - Read the guides in docs/\n";
echo "  - Experiment with your own queries\n";
