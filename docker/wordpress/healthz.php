<?php
declare(strict_types=1);

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

mysqli_report(MYSQLI_REPORT_OFF);

$host = getenv('WORDPRESS_DB_HOST') ?: 'db:3306';
$user = getenv('WORDPRESS_DB_USER') ?: '';
$password = getenv('WORDPRESS_DB_PASSWORD') ?: '';
$database = getenv('WORDPRESS_DB_NAME') ?: '';

$port = 3306;
if (str_contains($host, ':')) {
    [$host, $portValue] = explode(':', $host, 2);
    $port = (int) $portValue;
}

$connection = mysqli_init();
if ($connection !== false) {
    mysqli_options($connection, MYSQLI_OPT_CONNECT_TIMEOUT, 2);
}
$connected = $connection !== false
    && @mysqli_real_connect($connection, $host, $user, $password, $database, $port);

if (!$connected || !@mysqli_query($connection, 'SELECT 1')) {
    http_response_code(503);
    echo "unhealthy\n";
    exit(1);
}

mysqli_close($connection);
http_response_code(200);
echo "healthy\n";
