<?php
declare(strict_types=1);

require __DIR__ . '/db.php';

$courseId = int_range($_GET['course_id'] ?? null, 1, 999999999);
if ($courseId === null) {
    json_response(['ok' => false, 'error' => 'course_id is required'], 400);
}

$courseStmt = $pdo->prepare("
    SELECT id, source_key, region, city, name, address, phone, hole_count, status, updated_at
    FROM park_golf_courses
    WHERE id=? AND status='active'
");
$courseStmt->execute([$courseId]);
$course = $courseStmt->fetch(PDO::FETCH_ASSOC);
if (!$course) {
    json_response(['ok' => false, 'error' => 'course not found'], 404);
}

$holesStmt = $pdo->prepare("
    SELECT course_code, hole_no, distance_m, par, source, updated_at
    FROM park_golf_course_holes
    WHERE course_id=?
    ORDER BY course_code, hole_no
");
$holesStmt->execute([$courseId]);

json_response([
    'ok' => true,
    'course' => $course,
    'holes' => $holesStmt->fetchAll(PDO::FETCH_ASSOC),
]);
