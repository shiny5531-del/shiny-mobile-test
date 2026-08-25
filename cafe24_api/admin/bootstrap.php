<?php
declare(strict_types=1);

session_start();

$rootDir = dirname(__DIR__);
$configPath = $rootDir . '/db_config.php';
if (!is_file($configPath)) {
    http_response_code(500);
    exit('db_config.php 파일이 필요합니다.');
}

ob_start();
require $configPath;
ob_end_clean();

if (!isset($pdo) || !($pdo instanceof PDO)) {
    http_response_code(500);
    exit('PDO 연결을 확인할 수 없습니다.');
}

$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec("SET NAMES utf8mb4");

require_once __DIR__ . '/stage2_importer.php';

$adminConfig = __DIR__ . '/admin_config.php';
if (is_file($adminConfig)) {
    require $adminConfig;
}

function admin_password_hash_value(): string
{
    if (defined('PARKGOLF_ADMIN_PASSWORD_HASH')) {
        return (string) PARKGOLF_ADMIN_PASSWORD_HASH;
    }
    return '';
}

function ensure_admin_tables(PDO $pdo): void
{
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
            KEY idx_course (course_id),
            CONSTRAINT fk_course_holes_course
                FOREIGN KEY (course_id) REFERENCES park_golf_courses(id)
                ON DELETE CASCADE
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
}

function h(?string $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function request_value(string $key, string $default = ''): string
{
    return trim((string) ($_POST[$key] ?? $_GET[$key] ?? $default));
}

function seed_stage2_json_if_empty(PDO $pdo): void
{
    $count = (int) $pdo->query("SELECT COUNT(*) FROM park_golf_courses")->fetchColumn();
    if ($count > 0) {
        return;
    }

    $jsonPath = dirname(__DIR__) . '/data/parkgolf_stage2_master.json';
    if (!is_file($jsonPath)) {
        return;
    }

    $jsonText = file_get_contents($jsonPath);
    if ($jsonText === false || trim($jsonText) === '') {
        return;
    }

    import_stage2_json($pdo, $jsonText);
}

function require_login(): void
{
    if (!empty($_SESSION['park_admin_login'])) {
        return;
    }

    $hash = admin_password_hash_value();
    if ($hash === '') {
        return;
    }

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'login') {
        if (password_verify((string) ($_POST['password'] ?? ''), $hash)) {
            $_SESSION['park_admin_login'] = true;
            header('Location: index.php');
            exit;
        }
        $GLOBALS['login_error'] = '비밀번호가 맞지 않습니다.';
    }

    echo '<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="assets/admin.css"><title>관리자 로그인</title></head><body><main class="login"><form method="post" class="card"><h1>파크골프 관리자</h1><input type="hidden" name="action" value="login"><label>관리자 비밀번호</label><input type="password" name="password" autofocus>';
    if (!empty($GLOBALS['login_error'])) {
        echo '<p class="error">' . h($GLOBALS['login_error']) . '</p>';
    }
    echo '<button class="primary">로그인</button></form></main></body></html>';
    exit;
}

ensure_admin_tables($pdo);
seed_stage2_json_if_empty($pdo);
require_login();
