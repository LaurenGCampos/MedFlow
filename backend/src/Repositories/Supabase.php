<?php
declare(strict_types=1);
namespace MedFlow\Repositories;
use MedFlow\Services\ApiError;
final class Supabase implements Gateway {
    public function __construct(private readonly string $token) {}
    public function request(string $method, string $path, ?array $body = null): mixed {
        $url = rtrim(getenv('SUPABASE_URL') ?: '', '/');
        $key = getenv('SUPABASE_PUBLISHABLE_KEY') ?: '';
        if (!str_starts_with($url, 'https://') || !$key) throw new ApiError(503, 'configuration', 'Integração indisponível.');
        $curl = curl_init($url . $path);
        $headers = ['apikey: ' . $key, 'Content-Type: application/json', 'Prefer: return=representation'];
        if ($this->token !== '') $headers[] = 'Authorization: Bearer ' . $this->token;
        curl_setopt_array($curl, [CURLOPT_RETURNTRANSFER => true, CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_TIMEOUT => 15, CURLOPT_HTTPHEADER => $headers]);
        if ($body !== null) curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode($body, JSON_THROW_ON_ERROR));
        $raw = curl_exec($curl); $status = curl_getinfo($curl, CURLINFO_RESPONSE_CODE); curl_close($curl);
        if ($raw === false || $status >= 500) throw new ApiError(502, 'upstream', 'Serviço temporariamente indisponível.');
        $data = json_decode($raw ?: 'null', true);
        if ($status >= 400) {
            $code = $data['code'] ?? '';
            if ($code === 'PGRST205' || $code === 'PGRST202') throw new ApiError(503, 'database_setup', 'O banco MedFlow ainda não está preparado. Aplique a migration inicial no Supabase e confira a exposição das tabelas na API.');
            if ($status === 401) throw new ApiError(401, 'unauthorized', 'Sessão inválida ou expirada.');
            if ($code === '42501' || $status === 403) throw new ApiError(403, 'forbidden', 'Acesso não autorizado.');
            if (in_array($code, ['23505', 'P0001'], true)) {
                $messages = ['Finish current ticket first'=>'Finalize a senha atual antes de chamar outra.', 'No waiting tickets'=>'Não há pacientes aguardando nesta fila.', 'Invalid ticket transition'=>'A situação da senha mudou. Atualize a fila.', 'Last administrator'=>'A clínica precisa manter pelo menos um administrador ativo.', 'Close doctor queues first'=>'Feche as filas deste médico antes de alterar o vínculo.', 'Queue has active tickets'=>'Finalize ou cancele as senhas antes de fechar a fila.', 'Queue unavailable'=>'Esta fila está indisponível.', 'Membership already exists'=>'Esta conta já possui vínculo com a clínica.', 'Ticket cannot be cancelled'=>'Esta senha não pode mais ser cancelada.'];
                throw new ApiError(409, 'conflict', $messages[$data['message'] ?? ''] ?? 'A operação conflita com o estado atual. Pode haver um registro duplicado.');
            }
            if ($code === '22023') throw new ApiError(422, 'validation', 'Dados inválidos ou código expirado. Confira os campos.');
            throw new ApiError(422, 'invalid_operation', 'Não foi possível concluir a operação.');
        }
        return $data;
    }
}
