# 파크골프 관리자 컨트롤 타워

## 위치

- `cafe24_api/admin/index.php`
- `cafe24_api/admin/import_stage2_json.php`

## 역할

- 골프장 목록 검색
- 골프장 추가/수정/숨김
- A-F 코스별 1-9홀 거리/파 관리
- 사용자 제안 검토
- 앱에서 수집된 거리/파/익명 타수 샘플 요약 확인
- `parkgolf_stage2_master.json` DB 가져오기

## 서버 배포

1. `cafe24_api` 폴더를 Cafe24 PHP 웹 경로에 업로드합니다.
2. 기존 `db_config.php`를 `cafe24_api/db_config.php` 위치에 둡니다.
3. `cafe24_api/admin/admin_config.sample.php`를 복사해 `admin_config.php`로 만듭니다.
4. 아래 명령으로 만든 비밀번호 해시를 `PARKGOLF_ADMIN_PASSWORD_HASH`에 넣습니다.

```bash
php -r "echo password_hash('관리자비밀번호', PASSWORD_DEFAULT), PHP_EOL;"
```

5. 브라우저에서 `/cafe24_api/admin/index.php`를 엽니다.
6. `JSON 가져오기`에서 `parkgolf_stage2_master.json`을 업로드합니다.

## 직접 서버 접속

DB 접속 정보만으로는 파일 업로드나 서버 폴더 확인을 할 수 없습니다.
직접 서버에 접속하려면 Cafe24의 FTP/SFTP/SSH 접속 정보가 필요합니다.

필요 정보:

- 서버 주소
- FTP/SFTP/SSH 아이디
- 비밀번호 또는 키 파일
- 업로드할 웹 루트 경로

비밀번호나 키는 GitHub에 올리면 안 됩니다.
