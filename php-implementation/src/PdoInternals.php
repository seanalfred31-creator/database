<?php

namespace App;

use PDO;

/**
 * Deep dive into PDO internals and PostgreSQL-specific features
 */
class PdoInternals
{
    private PDO $pdo;

    public function __construct(PDO $pdo)
    {
        $this->pdo = $pdo;
    }

    /**
     * Demonstrate prepared statement handling with JSONB
     */
    public function preparedStatementExamples(): array
    {
        // Named parameters with JSONB
        $stmt = $this->pdo->prepare("
            SELECT * FROM products 
            WHERE metadata @> :filter::jsonb
        ");
        $stmt->execute(['filter' => json_encode(['brand' => 'Dell'])]);
        $namedResults = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Positional parameters
        $stmt = $this->pdo->prepare("
            SELECT * FROM products 
            WHERE metadata->>'brand' = ? 
            AND (metadata->>'price')::numeric < ?
        ");
        $stmt->execute(['Apple', 1000]);
        $positionalResults = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Reusable prepared statement
        $stmt = $this->pdo->prepare("
            SELECT * FROM products WHERE metadata->>'brand' = :brand
        ");
        
        $brands = ['Dell', 'Apple', 'Sony'];
        $allResults = [];
        foreach ($brands as $brand) {
            $stmt->execute(['brand' => $brand]);
            $allResults[$brand] = $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

        return [
            'named' => $namedResults,
            'positional' => $positionalResults,
            'reusable' => $allResults
        ];
    }

    /**
     * Transaction handling with JSONB operations
     */
    public function transactionExamples(): bool
    {
        try {
            $this->pdo->beginTransaction();

            // Insert new product
            $stmt = $this->pdo->prepare("
                INSERT INTO products (name, metadata)
                VALUES (:name, :metadata::jsonb)
                RETURNING id
            ");
            $stmt->execute([
                'name' => 'New Product',
                'metadata' => json_encode([
                    'brand' => 'TestBrand',
                    'price' => 99.99,
                    'tags' => ['test']
                ])
            ]);
            $newId = $stmt->fetchColumn();

            // Update related products
            $stmt = $this->pdo->prepare("
                UPDATE products
                SET metadata = metadata || '{\"related_to\": \"' || :id || '\"}'::jsonb
                WHERE metadata->>'brand' = :brand
            ");
            $stmt->execute(['id' => $newId, 'brand' => 'TestBrand']);

            // Verify changes
            $stmt = $this->pdo->prepare("
                SELECT COUNT(*) FROM products 
                WHERE metadata ? 'related_to'
            ");
            $stmt->execute();
            $count = $stmt->fetchColumn();

            if ($count > 0) {
                $this->pdo->commit();
                return true;
            } else {
                $this->pdo->rollBack();
                return false;
            }
        } catch (\PDOException $e) {
            $this->pdo->rollBack();
            throw $e;
        }
    }

    /**
     * Batch operations with JSONB
     */
    public function batchOperations(): array
    {
        $startTime = microtime(true);

        // Batch insert using single query
        $values = [];
        $params = [];
        for ($i = 0; $i < 100; $i++) {
            $values[] = "(?, ?::jsonb)";
            $params[] = "Product $i";
            $params[] = json_encode([
                'brand' => 'Batch Brand',
                'price' => rand(100, 1000),
                'tags' => ['batch', 'test'],
                'batch_id' => $i
            ]);
        }

        $sql = "INSERT INTO products (name, metadata) VALUES " . implode(', ', $values);
        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($params);

        $insertTime = microtime(true) - $startTime;

        // Batch update
        $startTime = microtime(true);
        $stmt = $this->pdo->prepare("
            UPDATE products
            SET metadata = metadata || '{\"batch_updated\": true}'::jsonb
            WHERE metadata->>'brand' = 'Batch Brand'
        ");
        $stmt->execute();
        $updateTime = microtime(true) - $startTime;

        // Batch delete
        $startTime = microtime(true);
        $stmt = $this->pdo->prepare("
            DELETE FROM products
            WHERE metadata->>'brand' = 'Batch Brand'
        ");
        $stmt->execute();
        $deleteTime = microtime(true) - $startTime;

        return [
            'insert_time' => round($insertTime, 4),
            'update_time' => round($updateTime, 4),
            'delete_time' => round($deleteTime, 4),
            'total_time' => round($insertTime + $updateTime + $deleteTime, 4)
        ];
    }

    /**
     * Advanced fetch modes with JSONB
     */
    public function fetchModeExamples(): array
    {
        $stmt = $this->pdo->query("SELECT * FROM products LIMIT 5");

        // Fetch as associative array
        $assoc = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Fetch as objects
        $stmt->execute();
        $objects = $stmt->fetchAll(PDO::FETCH_OBJ);

        // Fetch as custom class
        $stmt->execute();
        $stmt->setFetchMode(PDO::FETCH_CLASS, ProductDTO::class);
        $dtos = $stmt->fetchAll();

        // Fetch key-value pairs (id => name)
        $stmt = $this->pdo->query("SELECT id, name FROM products");
        $keyValue = $stmt->fetchAll(PDO::FETCH_KEY_PAIR);

        // Fetch grouped by brand
        $stmt = $this->pdo->query("
            SELECT metadata->>'brand' as brand, name, metadata
            FROM products
        ");
        $grouped = $stmt->fetchAll(PDO::FETCH_GROUP | PDO::FETCH_ASSOC);

        return [
            'associative' => $assoc,
            'objects' => $objects,
            'dtos' => $dtos,
            'key_value' => $keyValue,
            'grouped' => $grouped
        ];
    }

    /**
     * Error handling patterns
     */
    public function errorHandlingExamples(): array
    {
        $results = [];

        // Try invalid JSONB
        try {
            $stmt = $this->pdo->prepare("
                INSERT INTO products (name, metadata)
                VALUES ('Invalid', 'not valid json'::jsonb)
            ");
            $stmt->execute();
        } catch (\PDOException $e) {
            $results['invalid_json'] = [
                'error' => $e->getMessage(),
                'code' => $e->getCode()
            ];
        }

        // Try invalid JSONB path
        try {
            $stmt = $this->pdo->prepare("
                SELECT metadata->'nonexistent'->'nested'->>'field' 
                FROM products
            ");
            $stmt->execute();
            $results['invalid_path'] = $stmt->fetchAll();
        } catch (\PDOException $e) {
            $results['invalid_path'] = ['error' => $e->getMessage()];
        }

        // Handle type casting errors
        try {
            $stmt = $this->pdo->prepare("
                SELECT (metadata->>'invalid_number')::numeric 
                FROM products
            ");
            $stmt->execute();
            $results['type_cast'] = $stmt->fetchAll();
        } catch (\PDOException $e) {
            $results['type_cast'] = ['error' => $e->getMessage()];
        }

        return $results;
    }

    /**
     * Connection attribute inspection
     */
    public function inspectConnection(): array
    {
        return [
            'driver' => $this->pdo->getAttribute(PDO::ATTR_DRIVER_NAME),
            'server_version' => $this->pdo->getAttribute(PDO::ATTR_SERVER_VERSION),
            'client_version' => $this->pdo->getAttribute(PDO::ATTR_CLIENT_VERSION),
            'connection_status' => $this->pdo->getAttribute(PDO::ATTR_CONNECTION_STATUS),
            'autocommit' => $this->pdo->getAttribute(PDO::ATTR_AUTOCOMMIT),
            'persistent' => $this->pdo->getAttribute(PDO::ATTR_PERSISTENT),
            'server_info' => $this->pdo->getAttribute(PDO::ATTR_SERVER_INFO),
        ];
    }

    /**
     * Performance profiling
     */
    public function profileQueries(): array
    {
        $profiles = [];

        // Profile simple JSONB query
        $start = microtime(true);
        $stmt = $this->pdo->query("SELECT * FROM products WHERE metadata->>'brand' = 'Dell'");
        $stmt->fetchAll();
        $profiles['simple_query'] = microtime(true) - $start;

        // Profile complex JSONB query
        $start = microtime(true);
        $stmt = $this->pdo->query("
            SELECT * FROM products 
            WHERE metadata @> '{\"brand\": \"Dell\"}'
            AND (metadata->>'price')::numeric < 1000
            AND metadata->'tags' @> '[\"electronics\"]'
        ");
        $stmt->fetchAll();
        $profiles['complex_query'] = microtime(true) - $start;

        // Profile aggregation
        $start = microtime(true);
        $stmt = $this->pdo->query("
            SELECT 
                metadata->>'brand' as brand,
                COUNT(*) as count,
                AVG((metadata->>'price')::numeric) as avg_price
            FROM products
            GROUP BY metadata->>'brand'
        ");
        $stmt->fetchAll();
        $profiles['aggregation'] = microtime(true) - $start;

        return array_map(fn($time) => round($time, 6), $profiles);
    }
}

/**
 * Simple DTO for fetch mode example
 */
class ProductDTO
{
    public string $id;
    public string $name;
    public string $metadata;
    public string $created_at;

    public function getMetadataArray(): array
    {
        return json_decode($this->metadata, true);
    }

    public function getBrand(): ?string
    {
        return $this->getMetadataArray()['brand'] ?? null;
    }
}
