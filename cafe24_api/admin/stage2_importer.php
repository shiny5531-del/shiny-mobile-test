<?php
declare(strict_types=1);

function normal_course_key(string $value): string
{
    $value = preg_replace('/\[[^\]]+\]/u', '', $value) ?? $value;
    $value = str_replace(['파크골프장', '파크골프', '구장'], '', $value);
    $value = preg_replace('/\s+/u', '', $value) ?? $value;
    return mb_strtolower(trim($value), 'UTF-8');
}

function display_course_name(string $value): string
{
    return trim(preg_replace('/\[[^\]]+\]/u', '', $value) ?? $value);
}

function region_from_name(string $value): array
{
    preg_match_all('/\[([^\]]+)\]/u', $value, $matches);
    return [$matches[1][0] ?? '자료등록', $matches[1][1] ?? ''];
}

function import_stage2_json(PDO $pdo, string $jsonText): array
{
    $rows = json_decode($jsonText, true);
    if (!is_array($rows)) {
        throw new RuntimeException('JSON 형식을 확인해 주세요.');
    }

    $now = date('Y-m-d H:i:s');
    $courseStmt = $pdo->prepare("
        INSERT INTO park_golf_courses
            (source_key, region, city, name, address, phone, hole_count, status, memo, updated_at, created_at)
        VALUES
            (:source_key, :region, :city, :name, '', '-', :hole_count, 'active', :memo, :updated_at, :created_at)
        ON DUPLICATE KEY UPDATE
            region=VALUES(region),
            city=VALUES(city),
            name=VALUES(name),
            hole_count=GREATEST(hole_count, VALUES(hole_count)),
            updated_at=VALUES(updated_at)
    ");
    $selectCourse = $pdo->prepare("SELECT id FROM park_golf_courses WHERE source_key=?");
    $holeStmt = $pdo->prepare("
        INSERT INTO park_golf_course_holes
            (course_id, course_code, hole_no, distance_m, par, source, updated_at, created_at)
        VALUES
            (:course_id, :course_code, :hole_no, :distance_m, :par, 'stage2_json', :updated_at, :created_at)
        ON DUPLICATE KEY UPDATE
            distance_m=VALUES(distance_m),
            par=VALUES(par),
            source=VALUES(source),
            updated_at=VALUES(updated_at)
    ");

    $courseCount = 0;
    $holeCount = 0;
    $seenCourses = [];

    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $rawName = trim((string) ($row['golf_name'] ?? ''));
        if ($rawName === '') {
            continue;
        }
        $sourceKey = 'json-' . normal_course_key($rawName);
        [$region, $city] = region_from_name($rawName);
        $name = display_course_name($rawName);
        $totalHoles = (int) ($row['total_holes'] ?? 0);
        $courseStmt->execute([
            ':source_key' => $sourceKey,
            ':region' => $region,
            ':city' => $city,
            ':name' => $name,
            ':hole_count' => $totalHoles,
            ':memo' => 'stage2 JSON import',
            ':updated_at' => $now,
            ':created_at' => $now,
        ]);
        if (!isset($seenCourses[$sourceKey])) {
            $courseCount++;
            $seenCourses[$sourceKey] = true;
        }

        $selectCourse->execute([$sourceKey]);
        $courseId = (int) $selectCourse->fetchColumn();
        $courseCode = strtoupper(trim((string) ($row['course_type'] ?? '')));
        if ($courseCode === '') {
            $courseCode = 'A';
        }

        $holeInfoRaw = trim((string) ($row['hole_info_json'] ?? ''));
        if ($holeInfoRaw === '') {
            continue;
        }
        $holes = json_decode($holeInfoRaw, true);
        if (!is_array($holes)) {
            continue;
        }
        foreach ($holes as $hole) {
            if (!is_array($hole)) {
                continue;
            }
            $holeNo = (int) ($hole['hole'] ?? 0);
            $distance = (int) ($hole['distance'] ?? 0);
            $par = (int) ($hole['par'] ?? 0);
            if ($holeNo < 1 || $holeNo > 9 || $distance < 1 || $par < 3 || $par > 5) {
                continue;
            }
            $holeStmt->execute([
                ':course_id' => $courseId,
                ':course_code' => $courseCode,
                ':hole_no' => $holeNo,
                ':distance_m' => $distance,
                ':par' => $par,
                ':updated_at' => $now,
                ':created_at' => $now,
            ]);
            $holeCount++;
        }
    }

    return ['courses' => $courseCount, 'holes' => $holeCount];
}
