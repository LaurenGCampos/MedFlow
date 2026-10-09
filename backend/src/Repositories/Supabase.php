<?php
declare(strict_types=1);
namespace MedFlow\Repositories;
use MedFlow\Services\ApiError;
final class Supabase {
    public function __construct(private readonly string $token) {}
    public function request(string $method, string $path, ?array $body = null): mixed {
        $url = rtrim(getenv('SUPABASE_URL') ?: '', '/');
        $key = getenv('SUPABASE_PUBLISHABLE_KEY') ?: '';
        if (!str_starts_with($url, 'https://') || !$key) throw new ApiError(503, 'configuration', 'Integração indisponível.');
        $curl = curl_init($url . $path);
        curl_setopt_array($curl, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 15, CURLOPT_HTTPHEADER => [
                'apikey: ' . $key, 'Authorization: Bearer ' . $this->token, 'Content-Type: application/json', 'Prefer: return=representation']]);
        if ($body !== null) curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode($body, JSON_THROW_ON_ERROR));
        $raw = curl_exec($curl); $status = curl_getinfo($curl, CURLINFO_RESPONSE_CODE); curl_close($curl);
        if ($raw === false || $status >= 500) throw new ApiError(502, 'upstream', 'Serviço temporariamente indisponível.');
        $data = json_decode($raw ?: 'null', true);
        if ($status >= 400) {
            $code = $data['code'] ?? '';
            if ($status === 401) throw new ApiError(401, 'unauthorized', 'Sessão inválida ou expirada.');
            if ($code === '42501' || $status === 403) throw new ApiError(403, 'forbidden', 'Acesso não autorizado.');
            if (in_array($code, ['23505', 'P0001'], true)) throw new ApiError(409, 'conflict', 'A operação conflita com o estado atual.');
            throw new ApiError(422, 'invalid_operation', 'Não foi possível concluir a operação.');
        }
        return $data;
    }
}
