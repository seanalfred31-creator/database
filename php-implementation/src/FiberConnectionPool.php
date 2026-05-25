<?php

namespace App;

use Fiber;
use PDO;

/**
 * PHP 8.1+ Fiber-based connection pool
 * Provides cooperative multitasking without blocking
 */
class FiberConnectionPool
{
    private array $connections = [];
    private array $available = [];
    private array $config;
    private int $maxConnections;
    private int $activeCount = 0;

    public function __construct(array $config, int $maxConnections = 20)
    {
        $this->config = $config;
        $this->maxConnections = $maxConnections;
    }

    /**
     * Get connection (creates if needed)
     */
    public function getConnection(): PDO
    {
        // Try to get available connection
        if (!empty($this->available)) {
            $connId = array_key_first($this->available);
            $conn = $this->available[$connId];
            unset($this->available[$connId]);
            return $conn;
        }

        // Create new connection if under limit
        if ($this->activeCount < $this->maxConnections) {
            $conn = $this->createConnection();
            $this->activeCount++;
            return $conn;
        }

        // Wait for available connection (simplified - in production use proper queue)
        Fiber::suspend();
        return $this->getConnection();
    }

    /**
     * Release connection back to pool
     */
    public function releaseConnection(PDO $conn): void
    {
        $connId = spl_object_id($conn);
        $this->available[$connId] = $conn;
    }

    /**
     * Create new PDO connection
     */
    private function createConnection(): PDO
    {
        $dsn = sprintf(
            "pgsql:host=%s;port=%d;dbname=%s",
            $this->config['host'],
            $this->config['port'],
            $this->config['database']
        );

        return new PDO(
            $dsn,
            $this->config['username'],
            $this->config['password'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_PERSISTENT => false
            ]
        );
    }

    /**
     * Execute query with automatic connection management
     */
    public function query(string $sql, array $params = []): array
    {
        $conn = $this->getConnection();
        
        try {
            $stmt = $conn->prepare($sql);
            $stmt->execute($params);
            return $stmt->fetchAll();
        } finally {
            $this->releaseConnection($conn);
        }
    }

    /**
     * Get pool statistics
     */
    public function getStats(): array
    {
        return [
            'max_connections' => $this->maxConnections,
            'active_connections' => $this->activeCount,
            'available_connections' => count($this->available),
            'in_use' => $this->activeCount - count($this->available)
        ];
    }
}

/**
 * Fiber-based concurrent query executor
 */
class FiberQueryExecutor
{
    private FiberConnectionPool $pool;
    private array $fibers = [];

    public function __construct(FiberConnectionPool $pool)
    {
        $this->pool = $pool;
    }

    /**
     * Execute multiple queries concurrently using Fibers
     */
    public function executeParallel(array $queries): array
    {
        $results = [];
        $fibers = [];

        // Create fibers for each query
        foreach ($queries as $key => $query) {
            $fiber = new Fiber(function () use ($query) {
                return $this->pool->query($query['sql'], $query['params'] ?? []);
            });

            $fibers[$key] = $fiber;
            $fiber->start();
        }

        // Resume fibers until all complete
        $completed = [];
        while (count($completed) < count($fibers)) {
            foreach ($fibers as $key => $fiber) {
                if (isset($completed[$key])) {
                    continue;
                }

                if ($fiber->isTerminated()) {
                    $results[$key] = $fiber->getReturn();
                    $completed[$key] = true;
                } elseif ($fiber->isSuspended()) {
                    $fiber->resume();
                }
            }

            // Yield to prevent busy waiting
            if (count($completed) < count($fibers)) {
                usleep(1000); // 1ms
            }
        }

        return $results;
    }

    /**
     * Execute queries with rate limiting
     */
    public function executeWithRateLimit(array $queries, int $maxConcurrent = 5): array
    {
        $results = [];
        $batches = array_chunk($queries, $maxConcurrent, true);

        foreach ($batches as $batch) {
            $batchResults = $this->executeParallel($batch);
            $results = array_merge($results, $batchResults);
        }

        return $results;
    }
}

/**
 * FrankenPHP Worker Mode Connection Pool
 * Optimized for FrankenPHP's worker mode
 */
class FrankenPHPConnectionPool
{
    private static ?self $instance = null;
    private array $connections = [];
    private array $config;
    private int $poolSize;

    private function __construct(array $config, int $poolSize = 20)
    {
        $this->config = $config;
        $this->poolSize = $poolSize;
        $this->initializePool();
    }

    /**
     * Get singleton instance (important for FrankenPHP worker mode)
     */
    public static function getInstance(array $config, int $poolSize = 20): self
    {
        if (self::$instance === null) {
            self::$instance = new self($config, $poolSize);
        }
        return self::$instance;
    }

    /**
     * Initialize connection pool
     */
    private function initializePool(): void
    {
        for ($i = 0; $i < $this->poolSize; $i++) {
            $this->connections[] = $this->createConnection();
        }
    }

    /**
     * Create PDO connection
     */
    private function createConnection(): PDO
    {
        $dsn = sprintf(
            "pgsql:host=%s;port=%d;dbname=%s",
            $this->config['host'],
            $this->config['port'],
            $this->config['database']
        );

        return new PDO(
            $dsn,
            $this->config['username'],
            $this->config['password'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_PERSISTENT => false, // Important: no persistent connections
                PDO::ATTR_EMULATE_PREPARES => false
            ]
        );
    }

    /**
     * Get connection from pool (round-robin)
     */
    public function getConnection(): PDO
    {
        static $index = 0;
        $conn = $this->connections[$index % $this->poolSize];
        $index++;
        return $conn;
    }

    /**
     * Execute query
     */
    public function query(string $sql, array $params = []): array
    {
        $conn = $this->getConnection();
        $stmt = $conn->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    /**
     * Health check - verify all connections
     */
    public function healthCheck(): array
    {
        $results = [];
        foreach ($this->connections as $index => $conn) {
            try {
                $conn->query('SELECT 1');
                $results[$index] = ['healthy' => true];
            } catch (\PDOException $e) {
                $results[$index] = ['healthy' => false, 'error' => $e->getMessage()];
                // Recreate connection
                $this->connections[$index] = $this->createConnection();
            }
        }
        return $results;
    }

    /**
     * Reset pool (useful between requests in worker mode)
     */
    public function reset(): void
    {
        // Rollback any open transactions
        foreach ($this->connections as $conn) {
            try {
                if ($conn->inTransaction()) {
                    $conn->rollBack();
                }
            } catch (\PDOException $e) {
                // Connection might be dead, recreate it
                $index = array_search($conn, $this->connections, true);
                if ($index !== false) {
                    $this->connections[$index] = $this->createConnection();
                }
            }
        }
    }
}

/**
 * PDO Persistent Connection Manager
 * Handles gotchas with PgBouncer
 */
class PersistentConnectionManager
{
    /**
     * Create connection with proper settings for PgBouncer
     */
    public static function createForPgBouncer(array $config): PDO
    {
        $dsn = sprintf(
            "pgsql:host=%s;port=%d;dbname=%s",
            $config['host'],
            $config['port'],
            $config['database']
        );

        $pdo = new PDO(
            $dsn,
            $config['username'],
            $config['password'],
            [
                // CRITICAL: Don't use persistent connections with PgBouncer
                PDO::ATTR_PERSISTENT => false,
                
                // Don't emulate prepares (PgBouncer transaction mode issue)
                PDO::ATTR_EMULATE_PREPARES => false,
                
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                
                // Disable prepared statement caching
                PDO::ATTR_STATEMENT_CLASS => ['PDOStatement']
            ]
        );

        return $pdo;
    }

    /**
     * Gotchas with persistent connections and PgBouncer
     */
    public static function getGotchas(): array
    {
        return [
            'persistent_connections' => [
                'issue' => 'PDO persistent connections bypass PgBouncer pooling',
                'solution' => 'Always use PDO::ATTR_PERSISTENT => false with PgBouncer',
                'reason' => 'Persistent connections stay open, defeating pool purpose'
            ],
            'prepared_statements' => [
                'issue' => 'Prepared statements don\'t work across PgBouncer transactions',
                'solution' => 'Use PDO::ATTR_EMULATE_PREPARES => false or prepare within transaction',
                'reason' => 'PgBouncer transaction mode clears prepared statements'
            ],
            'transaction_mode' => [
                'issue' => 'Session-level features unavailable in transaction mode',
                'solution' => 'Use session mode or avoid session-level features',
                'features' => ['LISTEN/NOTIFY', 'Temporary tables', 'Cursors']
            ],
            'connection_state' => [
                'issue' => 'Connection state not preserved between requests',
                'solution' => 'Don\'t rely on SET commands persisting',
                'example' => 'SET search_path won\'t persist'
            ]
        ];
    }
}
