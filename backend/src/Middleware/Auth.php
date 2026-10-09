<?php
declare(strict_types=1);
namespace MedFlow\Middleware;
use MedFlow\Repositories\Gateway;
use MedFlow\Services\ApiError;
final class Auth {
    public static function token(string $header): string {
        if (!preg_match('/^Bearer ([A-Za-z0-9._-]{20,8192})$/D', $header, $m)) throw new ApiError(401, 'unauthorized', 'Autenticação necessária.');
        return $m[1];
    }
    public static function user(Gateway $db): array {
        $user = $db->request('GET', '/auth/v1/user');
        if (empty($user['id']) || empty($user['email_confirmed_at']) || ($user['is_anonymous'] ?? false)) throw new ApiError(401, 'unauthorized', 'Confirme seu e-mail para continuar.');
        return $user;
    }
    public static function clinic(Gateway $db, string $user, string $clinic, ?string $action = null): void {
        $members = $db->request('GET', '/rest/v1/clinic_members?select=role,clinics(status)&active=eq.true&clinic_id=eq.' . rawurlencode($clinic) . '&user_id=eq.' . rawurlencode($user));
        $role = $members[0]['role'] ?? null;
        if (!$role || ($members[0]['clinics']['status'] ?? '') !== 'active') throw new ApiError(403, 'forbidden', 'Sem vínculo ativo com esta clínica.');
        if ($action === null) return;
        $permissions = [
            'admin'=>['specialty_edit','room_edit','queue_edit','patient_edit','settings','specialty','room','queue','queue_status','invite','revoke_invite','member','patient','checkin','cancel','tracking'],
            'receptionist'=>['patient_edit','patient','checkin','cancel','tracking'],
            'doctor'=>['call','start','finish','absent'],
            'patient'=>[]
        ];
        if (!in_array($action, $permissions[$role] ?? [], true)) throw new ApiError(403, 'forbidden', 'Sua função não permite esta operação.');
    }
    public static function platform(Gateway $db): void {
        if ($db->request('GET', '/rest/v1/platform_admins?select=user_id&limit=1') === []) throw new ApiError(403, 'forbidden', 'Permissão de plataforma necessária.');
    }
}
