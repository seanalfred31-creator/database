<?php

namespace App;

use PDO;
use PDOException;

class ConnectionPooling
{
    private array $config;
    private ?PDO $directConnection = null;
    private ?PDO $pooledConnection = null;

    public function __construct(array $config)
    {
        $this->config = $config;
    }

    /**
     * Get direct PostgreSQL connection
     */
    public function getDirectConnection(): PDO
    {
        if ($this->directConnection === null) {
            $dsn = sprintf(
                "pgsql:host=%s;port=%d;dbname=%s",
                $this->config['db_host'],
                $this->config['db_port'],
                $this->config['db_database']
            );

            $this->directConnection = new PDO(
                $dsn,
                $this->config['db_username'],
                $this->config['db_password'],
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                ]
            );
        }

        return $this->directConnection;
    }

    /**
     * Get pooled connection via PgBouncer
     */
    public function getPooledConnection(): PDO
    {
        if ($this->pooledConnection === null) {
            $dsn = sprintf(
                "pgsql:host=%s;port=%d;dbname=%s",
                $this->config['pgbouncer_host'],
                $this->config['pgbouncer_port'],
                $this->config['db_database']
            );

            $this->pooledConnection = new PDO(
                $dsn,
                $this->config['db_username'],
                $this->config['db_password'],
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_PERSISTENT => false, // PgBouncer handles pooling
                ]
            );
        }

        return $this->pooledConnection;
    }

    /**
     * Demonstrate connection pooling benefits
     */
    public function benchmarkConnections(int $iterations = 100): array
    {
        // Benchmark direct connections
        $directStart = microtime(true);
        for ($i = 0; $i < $iterations; $i++) {
            $conn = $this->getDirectConnection();
            $stmt = $conn->query("SELECT 1");
            $stmt->fetch();
        }
        $directTime = microtime(true) - $directStart;

        // Benchmark pooled connections
        $pooledStart = microtime(true);
        for ($i = 0; $i < $iterations; $i++) {
            $conn = $this->getPooledConnection();
            $stmt = $conn->query("SELECT 1");
            $stmt->fetch();
        }
        $pooledTime = microtime(true) - $pooledStart;

        return [
            'iterations' => $iterations,
            'direct_time' => round($directTime, 4),
            'pooled_time' => round($pooledTime, 4),
            'improvement' => round((($directTime - $pooledTime) / $directTime) * 100, 2) . '%'
        ];
    }

    /**
     * Get PgBouncer statistics
     */
    public function getPoolStats(): array
    {
        try {
            $conn = $this->getPooledConnection();
            $stmt = $conn->query("SHOW POOLS");
            return $stmt->fetchAll(PDO::FETCH_ASSOC);
        } catch (PDOException $e) {
            return ['error' => 'Unable to fetch pool stats: ' . $e->getMessage()];
        }
    }

    /**
     * Simulate high-concurrency scenario
     */
    public function simulateHighLoad(int $concurrentQueries = 50): array
    {
        $results = [];
        $start = microtime(true);

        for ($i = 0; $i < $concurrentQueries; $i++) {
            $conn = $this->getPooledConnection();
            $stmt = $conn->prepare("
                INSERT INTO sessions (user_id, data, expires_at)
                VALUES (:user_id, :data, NOW() + INTERVAL '1 hour')
            ");
            $stmt->execute([
                'user_id' => rand(1, 1000),
                'data' => json_encode(['session_id' => uniqid(), 'timestamp' => time()])
            ]);
        }

        $duration = microtime(true) - $start;

        return [
            'queries_executed' => $concurrentQueries,
            'total_time' => round($duration, 4),
            'queries_per_second' => round($concurrentQueries / $duration, 2)
        ];
    }
}
