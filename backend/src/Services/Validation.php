<?php
declare(strict_types=1);
namespace MedFlow\Services;
final class Validation {
    public static function text(array $body, string $key, int $min, int $max): string {
        $value = $body[$key] ?? null;
        if (!is_string($value) || !preg_match('//u', $value)) throw new ApiError(422, 'validation', 'Campo inválido: ' . $key);
        $value = trim($value);
        if (strlen($value) < $min || strlen($value) > $max || preg_match('/[\x00-\x1F\x7F]/', $value)) throw new ApiError(422, 'validation', 'Campo inválido: ' . $key);
        return $value;
    }
}
