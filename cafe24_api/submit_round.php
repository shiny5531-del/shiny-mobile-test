<?php
declare(strict_types=1);

require __DIR__ . '/db.php';

$body = request_json();
$facts = isset($body['facts']) && is_array($body['facts']) ? $body['facts'] : [];
$clientIdHash = substr((string)($body['clientIdHash'] ?? 'anonymous'), 0, 80);
$accepted = 0;

$stmt = $pdo->prepare(
    'INSERT INTO park_golf_hole_contributions
    (course_id, course_name, course_code, hole_no, distance_m, par, anonymous_scores_json, client_id_hash, created_at)
    VALUES
    (:course_id, :course_name, :course_code, :hole_no, :distance_m, :par, :anonymous_scores_json, :client_id_hash, NOW())'
);

foreach ($facts as $fact) {
    if (!is_array($fact)) {
        continue;
    }
    $courseId = trim((string)($fact['courseId'] ?? ''));
    $courseName = trim((string)($fact['courseName'] ?? ''));
    $courseCode = strtoupper(trim((string)($fact['courseCode'] ?? '')));
    $holeNo = int_range($fact['holeNo'] ?? null, 1, 9);
    $distanceM = int_range($fact['distanceM'] ?? null, 1, 300);
    $par = int_range($fact['par'] ?? null, 3, 5);
    $scores = isset($fact['anonymousScores']) && is_array($fact['anonymousScores'])
        ? array_values(array_filter(array_map(
            fn($score) => int_range($score, 1, 20),
            $fact['anonymousScores']
        )))
        : [];

    if ($courseId === '' || !in_array($courseCode, ['A', 'B', 'C', 'D'], true)) {
        continue;
    }
    if ($holeNo === null || $distanceM === null || $par === null) {
        continue;
    }

    $stmt->execute([
        ':course_id' => $courseId,
        ':course_name' => $courseName,
        ':course_code' => $courseCode,
        ':hole_no' => $holeNo,
        ':distance_m' => $distanceM,
        ':par' => $par,
        ':anonymous_scores_json' => json_encode($scores, JSON_UNESCAPED_UNICODE),
        ':client_id_hash' => $clientIdHash,
    ]);
    $accepted++;
}

json_response(['accepted' => $accepted], $accepted > 0 ? 201 : 400);
