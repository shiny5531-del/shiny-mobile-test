<?php
declare(strict_types=1);

require __DIR__ . '/bootstrap.php';

$message = '';
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        $jsonText = '';
        if (isset($_FILES['json_file']) && is_uploaded_file($_FILES['json_file']['tmp_name'])) {
            $jsonText = (string) file_get_contents($_FILES['json_file']['tmp_name']);
        } else {
            $jsonText = (string) ($_POST['json_text'] ?? '');
        }

        $result = import_stage2_json($pdo, $jsonText);
        $message = number_format($result['courses']) . '개 골프장, ' . number_format($result['holes']) . '개 홀 정보를 가져왔습니다.';
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}
?>
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>JSON 가져오기</title>
  <link rel="stylesheet" href="assets/admin.css">
</head>
<body>
  <header class="top">
    <div>
      <h1>stage2 JSON 가져오기</h1>
      <p>첨부 JSON을 서버 DB 기준 데이터로 변환합니다.</p>
    </div>
    <a class="button" href="index.php">관리자로 돌아가기</a>
  </header>
  <?php if ($message !== ''): ?><div class="notice"><?=h($message)?></div><?php endif; ?>
  <?php if ($error !== ''): ?><div class="error"><?=h($error)?></div><?php endif; ?>
  <main class="grid" style="grid-template-columns:1fr">
    <section class="card">
      <form method="post" enctype="multipart/form-data" class="form">
        <label>JSON 파일 업로드<input type="file" name="json_file" accept=".json,application/json"></label>
        <label>또는 JSON 붙여넣기<textarea name="json_text" placeholder="parkgolf_stage2_master.json 내용을 붙여넣기"></textarea></label>
        <button class="primary">DB로 가져오기</button>
      </form>
    </section>
  </main>
</body>
</html>
