CREATE TABLE IF NOT EXISTS park_golf_hole_contributions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  course_id VARCHAR(80) NOT NULL,
  course_name VARCHAR(160) NOT NULL DEFAULT '',
  course_code CHAR(1) NOT NULL,
  hole_no TINYINT UNSIGNED NOT NULL,
  distance_m SMALLINT UNSIGNED NOT NULL,
  par TINYINT UNSIGNED NOT NULL,
  anonymous_scores_json TEXT NOT NULL,
  client_id_hash VARCHAR(80) NOT NULL DEFAULT 'anonymous',
  created_at DATETIME NOT NULL,
  INDEX idx_course_hole (course_id, course_code, hole_no),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
