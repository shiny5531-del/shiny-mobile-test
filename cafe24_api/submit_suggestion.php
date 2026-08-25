<?php
declare(strict_types=1);

require __DIR__ . '/db.php';

$body = request_json();
$suggestionType = (string)($body['suggestionType'] ?? 'hole');
if (!in_array($suggestionType, ['course', 'hole', 'correction'], true)) {
    $suggestionType = 'correction';
}

$payload = isset($body['payload']) && is_array($body['payload']) ? $body['payload'] : [];
$courseIdRaw = $payload['courseId'] ?? null;
$courseId = filter_var($courseIdRaw, FILTER_VALIDATE_INT);
$facts = isset($payload['facts']) && is_array($payload['facts']) ? $payload['facts'] : [];

if ($suggestionType === 'hole' && count($facts) === 0) {
    json_response(['error' => 'No hole facts submitted'], 400);
}

$stmt = $pdo->prepare(
    'INSERT INTO park_golf_course_suggestions
    (suggestion_type, course_id, payload_json, status, created_at)
    VALUES
    (:suggestion_type, :course_id, :payload_json, "new", NOW())'
);

$stmt->execute([
    ':suggestion_type' => $suggestionType,
    ':course_id' => $courseId === false ? null : $courseId,
    ':payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
]);

json_response([
    'accepted' => count($facts),
    'suggestionId' => (int)$pdo->lastInsertId(),
], 201);
