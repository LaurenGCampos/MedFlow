<?php
declare(strict_types=1);
namespace MedFlow\Middleware;
use MedFlow\Services\ApiError;
final class RateLimit {
    public static function check(string $identity, int $limit = 60): void {
        $dir = getenv('RATE_LIMIT_DIR') ?: sys_get_temp_dir() . '/medflow-rate-limit';
        if (!is_dir($dir) && !mkdir($dir, 0700, true) && !is_dir($dir)) throw new ApiError(503, 'limiter', 'Serviço indisponível.');
        $file = fopen($dir . '/' . hash('sha256', $identity), 'c+');
        if (!$file || !flock($file, LOCK_EX)) throw new ApiError(503, 'limiter', 'Serviço indisponível.');
        $state = json_decode(stream_get_contents($file), true) ?: ['start' => time(), 'count' => 0];
        if (time() - $state['start'] >= 60) $state = ['start' => time(), 'count' => 0];
        $state['count']++; ftruncate($file, 0); rewind($file); fwrite($file, json_encode($state)); fflush($file); flock($file, LOCK_UN); fclose($file);
        if ($state['count'] > $limit) throw new ApiError(429, 'rate_limit', 'Muitas tentativas. Aguarde um minuto.');
    }
}
