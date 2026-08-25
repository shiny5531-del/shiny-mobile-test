<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$result = [
    'php_version' => PHP_VERSION,
    'db_config_exists' => is_file(__DIR__ . '/db_config.php'),
    'pdo_available' => false,
    'tables' => [],
    'error' => null,
];

try {
    ob_start();
    require __DIR__ . '/db_config.php';
    ob_end_clean();

    if (!isset($pdo) || !($pdo instanceof PDO)) {
        throw new RuntimeException('PDO connection variable not found');
    }

    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $result['pdo_available'] = true;

    require_once __DIR__ . '/admin/stage2_importer.php';

    $pdo->exec("
        CREATE TABLE IF NOT EXISTS park_golf_courses (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            source_key VARCHAR(120) NOT NULL DEFAULT '',
            region VARCHAR(80) NOT NULL DEFAULT '',
            city VARCHAR(80) NOT NULL DEFAULT '',
            name VARCHAR(160) NOT NULL,
            address VARCHAR(255) NOT NULL DEFAULT '',
            phone VARCHAR(80) NOT NULL DEFAULT '',
            hole_count SMALLINT UNSIGNED NOT NULL DEFAULT 0,
            status ENUM('active','draft','hidden') NOT NULL DEFAULT 'active',
            memo TEXT NULL,
            updated_at DATETIME NOT NULL,
            created_at DATETIME NOT NULL,
            UNIQUE KEY uq_source_key (source_key),
            KEY idx_name (name),
            KEY idx_region (region, city),
            KEY idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS park_golf_course_holes (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            course_id BIGINT UNSIGNED NOT NULL,
            course_code VARCHAR(8) NOT NULL,
            hole_no TINYINT UNSIGNED NOT NULL,
            distance_m SMALLINT UNSIGNED NOT NULL DEFAULT 0,
            par TINYINT UNSIGNED NOT NULL DEFAULT 3,
            source VARCHAR(40) NOT NULL DEFAULT 'admin',
            confidence DECIMAL(4,3) NOT NULL DEFAULT 1.000,
            updated_at DATETIME NOT NULL,
            created_at DATETIME NOT NULL,
            UNIQUE KEY uq_course_hole (course_id, course_code, hole_no),
            KEY idx_course (course_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS park_golf_course_suggestions (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            suggestion_type ENUM('course','hole','correction') NOT NULL DEFAULT 'correction',
            course_id BIGINT UNSIGNED NULL,
            payload_json MEDIUMTEXT NOT NULL,
            status ENUM('new','reviewing','approved','rejected') NOT NULL DEFAULT 'new',
            admin_note TEXT NULL,
            created_at DATETIME NOT NULL,
            reviewed_at DATETIME NULL,
            KEY idx_status (status),
            KEY idx_course (course_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS park_golf_hole_contributions (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            course_id VARCHAR(80) NOT NULL,
            course_name VARCHAR(160) NOT NULL DEFAULT '',
            course_code VARCHAR(8) NOT NULL,
            hole_no TINYINT UNSIGNED NOT NULL,
            distance_m SMALLINT UNSIGNED NOT NULL,
            par TINYINT UNSIGNED NOT NULL,
            anonymous_scores_json TEXT NOT NULL,
            client_id_hash VARCHAR(80) NOT NULL DEFAULT 'anonymous',
            created_at DATETIME NOT NULL,
            INDEX idx_course_hole (course_id, course_code, hole_no),
            INDEX idx_created_at (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");
    $courseCount = (int) $pdo->query("SELECT COUNT(*) FROM park_golf_courses")->fetchColumn();
    if ($courseCount === 0 && is_file(__DIR__ . '/data/parkgolf_stage2_master.json')) {
        import_stage2_json($pdo, (string) file_get_contents(__DIR__ . '/data/parkgolf_stage2_master.json'));
    }

    foreach ([
        'park_golf_courses',
        'park_golf_course_holes',
        'park_golf_course_suggestions',
        'park_golf_hole_contributions',
    ] as $table) {
        $stmt = $pdo->query("SHOW TABLES LIKE " . $pdo->quote($table));
        $result['tables'][$table] = (bool) $stmt->fetchColumn();
    }
} catch (Throwable $e) {
    if (ob_get_level() > 0) {
        ob_end_clean();
    }
    $result['error'] = $e->getMessage();
}

echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
