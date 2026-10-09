<?php
declare(strict_types=1);
namespace MedFlow\Middleware;
use MedFlow\Repositories\Supabase;
use MedFlow\Services\ApiError;
final class Auth {
    public static function token(string $header): string {
        if (!preg_match('/^Bearer ([A-Za-z0-9._-]{20,8192})$/D', $header, $m)) throw new ApiError(401, 'unauthorized', 'Autenticação necessária.');
        return $m[1];
    }
    public static function user(Supabase $db): array {
        $user = $db->request('GET', '/auth/v1/user');
        if (empty($user['id']) || empty($user['email_confirmed_at']) || ($user['is_anonymous'] ?? false)) throw new ApiError(401, 'unauthorized', 'Confirme seu e-mail para continuar.');
        return $user;
    }
    public static function platform(Supabase $db): void {
        if ($db->request('GET', '/rest/v1/platform_admins?select=user_id&limit=1') === []) throw new ApiError(403, 'forbidden', 'Permissão de plataforma necessária.');
    }
}
