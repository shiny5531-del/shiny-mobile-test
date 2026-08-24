<?php
declare(strict_types=1);

require __DIR__ . '/db.php';

$pdo->query('SELECT 1');
json_response(['ok' => true]);
