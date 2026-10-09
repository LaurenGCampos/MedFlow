<?php
declare(strict_types=1);
namespace MedFlow\Services;
final class ApiError extends \RuntimeException {
    public function __construct(public readonly int $status, public readonly string $errorCode, string $message) { parent::__construct($message); }
}
