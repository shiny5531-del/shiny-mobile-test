# Cafe24 PHP API

카페24 웹호스팅에서 PHP와 MySQL로 홀 거리/파/익명 타수 샘플을 저장하는 API입니다.

## 배치

카페24 서버의 같은 폴더에 아래 파일을 올립니다.

```text
db_config.php
db.php
health.php
submit_round.php
get_hole_stats.php
schema.sql
```

`db_config.php`는 비밀번호가 들어 있으므로 GitHub에 올리지 않습니다.

## 확인

```text
https://도메인/api/health.php
```

정상 응답:

```json
{"ok":true}
```
