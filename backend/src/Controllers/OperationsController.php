<?php
declare(strict_types=1);
namespace MedFlow\Controllers;
use MedFlow\Repositories\Gateway;
use MedFlow\Services\ApiError;
use MedFlow\Services\Validation;
final class OperationsController {
    public function __construct(private readonly Gateway $db) {}
    private function uuid(array $body, string $key): string {
        $value = Validation::text($body, $key, 36, 36);
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/Di', $value)) throw new ApiError(422, 'validation', 'Identificador inválido: ' . $key);
        return $value;
    }
    public function workspace(string $clinic): mixed { return $this->db->request('POST', '/rest/v1/rpc/clinic_workspace', ['p_clinic' => $clinic]); }
    public function operation(string $clinic, array $body): mixed {
        $action = Validation::text($body, 'action', 4, 20); $data = []; $secret = null;
        if (in_array($action, ['settings', 'specialty', 'room', 'queue', 'patient','specialty_edit','room_edit','queue_edit','patient_edit'], true)) $data['name'] = Validation::text($body, 'name', 2, 120);
        if (str_ends_with($action, '_edit')) $data['id'] = $this->uuid($body, 'id');
        if ($action === 'settings') {
            $data['timezone'] = Validation::text($body, 'timezone', 3, 80);
            $data['city'] = Validation::text($body, 'city', 2, 120);
            $data['contact_email'] = Validation::text($body, 'contact_email', 3, 254);
            if (!filter_var($data['contact_email'], FILTER_VALIDATE_EMAIL)) throw new ApiError(422, 'validation', 'E-mail inválido.');
        } elseif ($action === 'queue' || $action === 'queue_edit') {
            foreach ($action === 'queue' ? ['doctor_id', 'specialty_id', 'room_id'] : ['room_id'] as $field) $data[$field] = $this->uuid($body, $field);
            $minutes = filter_var($body['expected_minutes'] ?? null, FILTER_VALIDATE_INT, ['options'=>['min_range'=>1,'max_range'=>240]]);
            if ($minutes === false) throw new ApiError(422, 'validation', 'Duração esperada deve estar entre 1 e 240 minutos.');
            $data['expected_minutes'] = $minutes;
        } elseif ($action === 'invite') {
            $data['email'] = Validation::text($body, 'email', 3, 254); $data['role'] = Validation::text($body, 'role', 5, 12);
            if (!filter_var($data['email'], FILTER_VALIDATE_EMAIL)) throw new ApiError(422, 'validation', 'E-mail inválido.');
            $secret = bin2hex(random_bytes(32)); $data['token'] = $secret;
        } elseif ($action === 'patient') {
            $email = $body['email'] ?? '';
            if (!is_string($email) || ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL))) throw new ApiError(422, 'validation', 'E-mail inválido.');
            $data['email'] = trim($email);
        } elseif ($action === 'checkin') {
            $data['queue_id'] = $this->uuid($body, 'queue_id'); $data['patient_id'] = $this->uuid($body, 'patient_id');
            if (!is_bool($body['priority'] ?? null)) throw new ApiError(422, 'validation', 'Prioridade inválida.');
            $data['priority'] = $body['priority']; $secret = bin2hex(random_bytes(32)); $data['token'] = $secret;
        } elseif ($action === 'call') $data['queue_id'] = $this->uuid($body, 'queue_id');
        elseif ($action === 'member') {
            $data['user_id'] = $this->uuid($body, 'user_id'); $data['role'] = Validation::text($body, 'role', 5, 12);
            if (!is_bool($body['active'] ?? null)) throw new ApiError(422, 'validation', 'Situação inválida.');
            $data['active'] = $body['active'];
        } elseif (in_array($action, ['queue_status','tracking','cancel','start','finish','absent','revoke_invite'], true)) {
            $data['id'] = $this->uuid($body, 'id');
            if ($action === 'queue_status') $data['status'] = Validation::text($body, 'status', 4, 6);
            if ($action === 'tracking') { $secret = bin2hex(random_bytes(32)); $data['token'] = $secret; }
        } elseif (!in_array($action, ['settings','specialty','room','specialty_edit','room_edit','patient_edit'], true)) throw new ApiError(422, 'validation', 'Operação inválida.');
        $result = $this->db->request('POST', '/rest/v1/rpc/clinic_operation', ['p_clinic'=>$clinic,'p_action'=>$action,'p_data'=>$data]);
        if ($secret) $result['token'] = $secret;
        return $result;
    }
    public function accept(array $body): mixed { return $this->db->request('POST', '/rest/v1/rpc/accept_staff_invite', ['p_token'=>self::secureToken($body)]); }
    public function track(array $body): mixed { return $this->db->request('POST', '/rest/v1/rpc/track_ticket', ['p_token'=>self::secureToken($body)]); }
    private static function secureToken(array $body): string {
        $token = Validation::text($body, 'token', 64, 64);
        if (!preg_match('/^[a-f0-9]{64}$/D', $token)) throw new ApiError(422, 'validation', 'Código inválido.');
        return $token;
    }
}
