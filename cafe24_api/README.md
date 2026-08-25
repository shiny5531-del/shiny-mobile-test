# Cafe24 PHP API / 관리자

파크골프 앱 서버용 PHP + MySQL 패키지입니다.

## 포함 파일

```text
db_config.php
index.php
health.php
install_check.php
courses.php
course_holes.php
submit_suggestion.php
submit_round.php
get_hole_stats.php
schema.sql
admin/
data/parkgolf_stage2_master.json
```

## 접속

```text
https://도메인/업로드폴더/health.php
https://도메인/업로드폴더/install_check.php
https://도메인/업로드폴더/index.php
```

`index.php`는 `admin/index.php`로 이동합니다.

## 앱 전송 API

`submit_suggestion.php`는 앱의 홀 정보 제안을 받아
`park_golf_course_suggestions`에 신규 검토 건으로 저장합니다.

## 데이터

관리자 첫 접속 시 DB가 비어 있으면 `data/parkgolf_stage2_master.json`
기준으로 골프장과 홀 거리/파 정보를 자동 등록합니다.

## 주의

`db_config.php`에는 DB 비밀번호가 들어 있습니다.
사용자가 직접 서버에 업로드하는 ZIP에는 포함할 수 있지만 GitHub에는 올리지 않습니다.
