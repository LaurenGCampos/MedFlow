<?php
declare(strict_types=1);
namespace MedFlow\Controllers;
use MedFlow\Repositories\Gateway;
use MedFlow\Services\Validation;
final class ClinicController {
    public function __construct(private readonly Gateway $db) {}
    public function submit(array $body): mixed {
        $name = Validation::text($body, 'name', 3, 120);
        $email = Validation::text($body, 'contact_email', 3, 254);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) throw new \MedFlow\Services\ApiError(422, 'validation', 'E-mail inválido.');
        return $this->db->request('POST', '/rest/v1/rpc/submit_clinic_request', ['p_name' => $name, 'p_contact_email' => $email, 'p_city' => Validation::text($body, 'city', 2, 120)]);
    }
    public function decide(string $id, array $body): mixed {
        $decision = Validation::text($body, 'decision', 6, 8);
        if (!in_array($decision, ['approve', 'reject'], true)) throw new \MedFlow\Services\ApiError(422, 'validation', 'Decisão inválida.');
        $reason = $decision === 'reject' ? Validation::text($body, 'reason', 5, 500) : null;
        return $this->db->request('POST', '/rest/v1/rpc/decide_clinic_request', ['p_request_id' => $id, 'p_decision' => $decision, 'p_reason' => $reason]);
    }
}
