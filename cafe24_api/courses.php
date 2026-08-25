<?php
declare(strict_types=1);

require __DIR__ . '/db.php';

$q = trim((string) ($_GET['q'] ?? ''));
$params = [];
$sql = "
    SELECT id, source_key, region, city, name, address, phone, hole_count, status, updated_at
    FROM park_golf_courses
    WHERE status='active'
";
if ($q !== '') {
    $sql .= " AND (name LIKE :q OR address LIKE :q OR region LIKE :q OR city LIKE :q)";
    $params[':q'] = '%' . $q . '%';
}
$sql .= " ORDER BY region, city, name LIMIT 500";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);

json_response([
    'ok' => true,
    'courses' => $stmt->fetchAll(PDO::FETCH_ASSOC),
]);
