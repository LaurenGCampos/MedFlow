<?php
declare(strict_types=1);
namespace MedFlow\Repositories;
interface Gateway {
    public function request(string $method, string $path, ?array $body = null): mixed;
}
