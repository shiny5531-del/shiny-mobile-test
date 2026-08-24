<?php
declare(strict_types=1);

require __DIR__ . '/db.php';

$courseId = trim((string)($_GET['courseId'] ?? ''));
if ($courseId === '') {
    json_response(['error' => 'courseId is required'], 400);
}

$stmt = $pdo->prepare(
    'SELECT course_id, course_code, hole_no, distance_m, par, anonymous_scores_json
     FROM park_golf_hole_contributions
     WHERE course_id = :course_id
     ORDER BY course_code, hole_no'
);
$stmt->execute([':course_id' => $courseId]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

$groups = [];
foreach ($rows as $row) {
    $key = $row['course_id'] . '|' . $row['course_code'] . '|' . $row['hole_no'];
    if (!isset($groups[$key])) {
        $groups[$key] = [
            'courseId' => $row['course_id'],
            'courseCode' => $row['course_code'],
            'holeNo' => (int)$row['hole_no'],
            'distances' => [],
            'pars' => [],
            'scores' => [],
        ];
    }
    $groups[$key]['distances'][] = (int)$row['distance_m'];
    $groups[$key]['pars'][] = (int)$row['par'];
    $scores = json_decode((string)$row['anonymous_scores_json'], true);
    if (is_array($scores)) {
        foreach ($scores as $score) {
            $scoreInt = int_range($score, 1, 20);
            if ($scoreInt !== null) {
                $groups[$key]['scores'][] = $scoreInt;
            }
        }
    }
}

$facts = [];
foreach ($groups as $group) {
    sort($group['distances']);
    $distanceCount = count($group['distances']);
    $middle = intdiv($distanceCount, 2);
    $distanceM = $distanceCount % 2
        ? $group['distances'][$middle]
        : (int)round(($group['distances'][$middle - 1] + $group['distances'][$middle]) / 2);

    $parCounts = array_count_values($group['pars']);
    arsort($parCounts);
    $par = (int)array_key_first($parCounts);
    $scoreCount = count($group['scores']);
    $averageScore = $scoreCount > 0 ? round(array_sum($group['scores']) / $scoreCount, 1) : null;

    $facts[] = [
        'courseId' => $group['courseId'],
        'courseCode' => $group['courseCode'],
        'holeNo' => $group['holeNo'],
        'distanceM' => $distanceM,
        'par' => $par,
        'averageScore' => $averageScore,
        'difficultyOverPar' => $averageScore === null ? null : round($averageScore - $par, 1),
        'sampleCount' => $distanceCount,
        'scoreSampleCount' => $scoreCount,
        'confidence' => $distanceCount >= 5 ? 'trusted' : 'draft',
    ];
}

json_response(['facts' => $facts]);
