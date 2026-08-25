<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$message = '';
$error = '';

function redirect_with_course(int $courseId): void
{
    header('Location: index.php?course_id=' . $courseId);
    exit;
}

function safe_count(PDO $pdo, string $sql): int
{
    try {
        return (int) $pdo->query($sql)->fetchColumn();
    } catch (Throwable $e) {
        return 0;
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = (string) ($_POST['action'] ?? '');

    try {
        if ($action === 'logout') {
            $_SESSION = [];
            session_destroy();
            header('Location: index.php');
            exit;
        }

        if ($action === 'save_course') {
            $id = (int) ($_POST['id'] ?? 0);
            $now = date('Y-m-d H:i:s');
            $params = [
                ':source_key' => request_value('source_key'),
                ':region' => request_value('region'),
                ':city' => request_value('city'),
                ':name' => request_value('name'),
                ':address' => request_value('address'),
                ':phone' => request_value('phone'),
                ':hole_count' => max(0, (int) request_value('hole_count', '0')),
                ':status' => request_value('status', 'active'),
                ':memo' => request_value('memo'),
                ':updated_at' => $now,
            ];
            if ($params[':name'] === '') {
                throw new RuntimeException('골프장명은 필수입니다.');
            }

            if ($id > 0) {
                $params[':id'] = $id;
                $stmt = $pdo->prepare("UPDATE park_golf_courses SET source_key=:source_key, region=:region, city=:city, name=:name, address=:address, phone=:phone, hole_count=:hole_count, status=:status, memo=:memo, updated_at=:updated_at WHERE id=:id");
                $stmt->execute($params);
                redirect_with_course($id);
            }

            $params[':created_at'] = $now;
            $stmt = $pdo->prepare("INSERT INTO park_golf_courses (source_key, region, city, name, address, phone, hole_count, status, memo, updated_at, created_at) VALUES (:source_key, :region, :city, :name, :address, :phone, :hole_count, :status, :memo, :updated_at, :created_at)");
            $stmt->execute($params);
            redirect_with_course((int) $pdo->lastInsertId());
        }

        if ($action === 'save_holes') {
            $courseId = (int) ($_POST['course_id'] ?? 0);
            if ($courseId <= 0) {
                throw new RuntimeException('골프장을 먼저 선택해 주세요.');
            }
            $now = date('Y-m-d H:i:s');
            $codes = $_POST['course_code'] ?? [];
            $holes = $_POST['hole_no'] ?? [];
            $distances = $_POST['distance_m'] ?? [];
            $pars = $_POST['par'] ?? [];

            $stmt = $pdo->prepare("
                INSERT INTO park_golf_course_holes
                    (course_id, course_code, hole_no, distance_m, par, source, updated_at, created_at)
                VALUES
                    (:course_id, :course_code, :hole_no, :distance_m, :par, 'admin', :updated_at, :created_at)
                ON DUPLICATE KEY UPDATE
                    distance_m=VALUES(distance_m),
                    par=VALUES(par),
                    source='admin',
                    updated_at=VALUES(updated_at)
            ");

            for ($i = 0; $i < count($codes); $i++) {
                $code = strtoupper(trim((string) ($codes[$i] ?? '')));
                $holeNo = (int) ($holes[$i] ?? 0);
                $distance = (int) ($distances[$i] ?? 0);
                $par = (int) ($pars[$i] ?? 0);
                if ($code === '' || $holeNo < 1 || $holeNo > 9 || $par < 3 || $par > 5) {
                    continue;
                }
                $stmt->execute([
                    ':course_id' => $courseId,
                    ':course_code' => $code,
                    ':hole_no' => $holeNo,
                    ':distance_m' => max(0, $distance),
                    ':par' => $par,
                    ':updated_at' => $now,
                    ':created_at' => $now,
                ]);
            }
            redirect_with_course($courseId);
        }

        if ($action === 'update_suggestion') {
            $stmt = $pdo->prepare("UPDATE park_golf_course_suggestions SET status=:status, admin_note=:admin_note, reviewed_at=:reviewed_at WHERE id=:id");
            $stmt->execute([
                ':id' => (int) ($_POST['id'] ?? 0),
                ':status' => request_value('status', 'reviewing'),
                ':admin_note' => request_value('admin_note'),
                ':reviewed_at' => date('Y-m-d H:i:s'),
            ]);
            $message = '제안 상태를 변경했습니다.';
        }
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}

$keyword = request_value('q');
$courseId = (int) request_value('course_id', '0');

$stats = [
    'courses' => safe_count($pdo, "SELECT COUNT(*) FROM park_golf_courses"),
    'holes' => safe_count($pdo, "SELECT COUNT(*) FROM park_golf_course_holes"),
    'suggestions' => safe_count($pdo, "SELECT COUNT(*) FROM park_golf_course_suggestions WHERE status IN ('new','reviewing')"),
    'contribs' => safe_count($pdo, "SELECT COUNT(*) FROM park_golf_hole_contributions"),
];

$sql = "SELECT * FROM park_golf_courses";
$params = [];
if ($keyword !== '') {
    $sql .= " WHERE name LIKE :q OR address LIKE :q OR region LIKE :q OR city LIKE :q";
    $params[':q'] = '%' . $keyword . '%';
}
$sql .= " ORDER BY updated_at DESC, id DESC LIMIT 80";
$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$courses = $stmt->fetchAll(PDO::FETCH_ASSOC);

$selectedCourse = null;
if ($courseId > 0) {
    $stmt = $pdo->prepare("SELECT * FROM park_golf_courses WHERE id=?");
    $stmt->execute([$courseId]);
    $selectedCourse = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
}

$holeRows = [];
if ($selectedCourse) {
    $stmt = $pdo->prepare("SELECT * FROM park_golf_course_holes WHERE course_id=? ORDER BY course_code, hole_no");
    $stmt->execute([$courseId]);
    $holeRows = $stmt->fetchAll(PDO::FETCH_ASSOC);
}

$suggestions = [];
$contribs = [];
try {
    $suggestions = $pdo
        ->query("SELECT * FROM park_golf_course_suggestions ORDER BY FIELD(status,'new','reviewing','approved','rejected'), id DESC LIMIT 30")
        ->fetchAll(PDO::FETCH_ASSOC);
    $contribs = $pdo
        ->query("SELECT course_name, course_code, hole_no, COUNT(*) AS samples, ROUND(AVG(distance_m)) AS avg_distance, ROUND(AVG(par), 2) AS avg_par, MAX(created_at) AS latest_at FROM park_golf_hole_contributions GROUP BY course_name, course_code, hole_no ORDER BY latest_at DESC LIMIT 40")
        ->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    $error = $error !== '' ? $error : '일부 통계 테이블을 읽지 못했습니다.';
}
?>
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>파크골프 컨트롤 타워</title>
  <link rel="stylesheet" href="assets/admin.css">
</head>
<body>
  <header class="top">
    <div>
      <h1>파크골프 컨트롤 타워</h1>
      <p>골프장 데이터, 홀 거리/파, 사용자 제안, 수집 데이터 관리</p>
    </div>
    <form method="post"><input type="hidden" name="action" value="logout"><button>로그아웃</button></form>
  </header>

  <?php if ($message !== ''): ?><div class="notice"><?=h($message)?></div><?php endif; ?>
  <?php if ($error !== ''): ?><div class="error"><?=h($error)?></div><?php endif; ?>

  <section class="stats">
    <div><strong><?=number_format($stats['courses'])?></strong><span>골프장</span></div>
    <div><strong><?=number_format($stats['holes'])?></strong><span>홀 정보</span></div>
    <div><strong><?=number_format($stats['suggestions'])?></strong><span>검토 제안</span></div>
    <div><strong><?=number_format($stats['contribs'])?></strong><span>수집 샘플</span></div>
  </section>

  <main class="grid">
    <section class="card">
      <div class="section-head">
        <h2>골프장 목록</h2>
        <a class="button" href="import_stage2_json.php">JSON 가져오기</a>
      </div>
      <form class="search" method="get">
        <input name="q" value="<?=h($keyword)?>" placeholder="골프장명, 지역, 주소 검색">
        <button>검색</button>
      </form>
      <div class="list">
        <?php foreach ($courses as $course): ?>
          <a class="row <?=$courseId === (int) $course['id'] ? 'active' : ''?>" href="?course_id=<?=(int)$course['id']?>&q=<?=urlencode($keyword)?>">
            <strong><?=h($course['name'])?></strong>
            <span><?=h(trim($course['region'] . ' ' . $course['city']))?> · <?=h((string)$course['hole_count'])?>홀</span>
            <small><?=h($course['address'])?></small>
          </a>
        <?php endforeach; ?>
      </div>
    </section>

    <section class="card">
      <h2><?=$selectedCourse ? '골프장 수정' : '골프장 추가'?></h2>
      <form method="post" class="form">
        <input type="hidden" name="action" value="save_course">
        <input type="hidden" name="id" value="<?=h((string)($selectedCourse['id'] ?? 0))?>">
        <label>골프장명<input name="name" required value="<?=h($selectedCourse['name'] ?? '')?>"></label>
        <div class="cols">
          <label>광역/도<input name="region" value="<?=h($selectedCourse['region'] ?? '')?>"></label>
          <label>시군구<input name="city" value="<?=h($selectedCourse['city'] ?? '')?>"></label>
        </div>
        <label>주소<input name="address" value="<?=h($selectedCourse['address'] ?? '')?>"></label>
        <div class="cols">
          <label>전화<input name="phone" value="<?=h($selectedCourse['phone'] ?? '')?>"></label>
          <label>홀수<input name="hole_count" type="number" value="<?=h((string)($selectedCourse['hole_count'] ?? 18))?>"></label>
        </div>
        <div class="cols">
          <label>상태
            <select name="status">
              <?php foreach (['active'=>'공개','draft'=>'작성중','hidden'=>'숨김'] as $key => $label): ?>
                <option value="<?=$key?>" <?=($selectedCourse['status'] ?? 'active') === $key ? 'selected' : ''?>><?=$label?></option>
              <?php endforeach; ?>
            </select>
          </label>
          <label>원본키<input name="source_key" value="<?=h($selectedCourse['source_key'] ?? '')?>"></label>
        </div>
        <label>메모<textarea name="memo"><?=h($selectedCourse['memo'] ?? '')?></textarea></label>
        <button class="primary">골프장 저장</button>
      </form>

      <?php if ($selectedCourse): ?>
        <h2>홀 거리 / 파</h2>
        <form method="post" class="holes">
          <input type="hidden" name="action" value="save_holes">
          <input type="hidden" name="course_id" value="<?=(int)$selectedCourse['id']?>">
          <?php
            $existing = [];
            foreach ($holeRows as $hole) {
                $existing[$hole['course_code'] . '-' . $hole['hole_no']] = $hole;
            }
            $codes = ['A','B','C','D','E','F'];
            foreach ($codes as $code):
          ?>
            <h3><?=$code?>코스</h3>
            <div class="hole-grid">
              <?php for ($i = 1; $i <= 9; $i++):
                $hole = $existing[$code . '-' . $i] ?? null;
              ?>
                <div class="hole-cell">
                  <input type="hidden" name="course_code[]" value="<?=$code?>">
                  <input type="hidden" name="hole_no[]" value="<?=$i?>">
                  <b><?=$i?>홀</b>
                  <input name="distance_m[]" type="number" placeholder="m" value="<?=h((string)($hole['distance_m'] ?? ''))?>">
                  <select name="par[]">
                    <?php foreach ([3,4,5] as $par): ?>
                      <option value="<?=$par?>" <?=((int)($hole['par'] ?? 3)) === $par ? 'selected' : ''?>>P<?=$par?></option>
                    <?php endforeach; ?>
                  </select>
                </div>
              <?php endfor; ?>
            </div>
          <?php endforeach; ?>
          <button class="primary">홀 정보 저장</button>
        </form>
      <?php endif; ?>
    </section>

    <section class="card">
      <h2>사용자 제안</h2>
      <?php foreach ($suggestions as $row): ?>
        <form method="post" class="proposal">
          <input type="hidden" name="action" value="update_suggestion">
          <input type="hidden" name="id" value="<?=(int)$row['id']?>">
          <strong>#<?=(int)$row['id']?> <?=h($row['suggestion_type'])?></strong>
          <small><?=h($row['created_at'])?></small>
          <pre><?=h($row['payload_json'])?></pre>
          <select name="status">
            <?php foreach (['new'=>'신규','reviewing'=>'검토중','approved'=>'승인','rejected'=>'반려'] as $key => $label): ?>
              <option value="<?=$key?>" <?=$row['status'] === $key ? 'selected' : ''?>><?=$label?></option>
            <?php endforeach; ?>
          </select>
          <textarea name="admin_note" placeholder="관리자 메모"><?=h($row['admin_note'])?></textarea>
          <button>상태 저장</button>
        </form>
      <?php endforeach; ?>
    </section>

    <section class="card">
      <h2>수집 데이터 요약</h2>
      <table>
        <thead><tr><th>골프장</th><th>홀</th><th>샘플</th><th>평균거리</th><th>평균파</th></tr></thead>
        <tbody>
          <?php foreach ($contribs as $row): ?>
            <tr>
              <td><?=h($row['course_name'])?></td>
              <td><?=h($row['course_code'])?>-<?=h((string)$row['hole_no'])?></td>
              <td><?=h((string)$row['samples'])?></td>
              <td><?=h((string)$row['avg_distance'])?>m</td>
              <td><?=h((string)$row['avg_par'])?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </section>
  </main>
</body>
</html>
