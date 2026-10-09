<?php
declare(strict_types=1);
require dirname(__DIR__) . '/config/bootstrap.php';
use MedFlow\Services\ApiError;
use MedFlow\Middleware\Auth;
use MedFlow\Middleware\RateLimit;
use MedFlow\Repositories\Supabase;
use MedFlow\Controllers\ClinicController;
use MedFlow\Controllers\OperationsController;
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store'); header('X-Content-Type-Options: nosniff');
$requestId = bin2hex(random_bytes(8));
try {
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== '') {
        if ($origin !== (getenv('FRONTEND_ORIGIN') ?: 'http://localhost:5173')) throw new ApiError(403, 'origin', 'Origem não autorizada.');
        header('Access-Control-Allow-Origin: ' . $origin); header('Vary: Origin');
        header('Access-Control-Allow-Headers: Authorization, Content-Type'); header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    }
    $method = $_SERVER['REQUEST_METHOD'];
    if ($method === 'OPTIONS') { http_response_code(204); exit; }
    $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    if ($method === 'GET' && $path === '/api/health') { echo json_encode(['data' => ['status' => 'ok']]); exit; }
    RateLimit::check('ip:' . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'), 120);
    $body = [];
    if ($method === 'POST') {
        if (!str_starts_with($_SERVER['CONTENT_TYPE'] ?? '', 'application/json')) throw new ApiError(415, 'content_type', 'Envie JSON.');
        $raw = file_get_contents('php://input', false, null, 0, 16385);
        if (strlen($raw) > 16384) throw new ApiError(413, 'body_size', 'Requisição muito grande.');
        try { $body = json_decode($raw, true, 32, JSON_THROW_ON_ERROR); } catch (JsonException) { throw new ApiError(400, 'json', 'JSON inválido.'); }
        if (!is_array($body) || array_is_list($body)) throw new ApiError(400, 'json', 'Objeto JSON necessário.');
    }
    if ($method === 'POST' && $path === '/api/public/track') {
        $data = (new OperationsController(new Supabase('')))->track($body);
        echo json_encode(['data'=>$data], JSON_THROW_ON_ERROR); exit;
    }
    $token = Auth::token($_SERVER['HTTP_AUTHORIZATION'] ?? '');
    $db = new Supabase($token); $user = Auth::user($db);
    RateLimit::check('user:' . $user['id'], 60);
    $operations = new OperationsController($db);
    $controller = new ClinicController($db);
    if ($method === 'GET' && $path === '/api/me') {
        $data = ['id' => $user['id'], 'email' => $user['email'], 'platform_admin' => $db->request('GET', '/rest/v1/platform_admins?select=user_id&limit=1') !== [], 'memberships' => $db->request('GET', '/rest/v1/clinic_members?select=clinic_id,role,clinics(name,status)&active=eq.true&user_id=eq.' . rawurlencode($user['id']))];
    } elseif ($method === 'GET' && $path === '/api/requests') {
        $data = $db->request('GET', '/rest/v1/clinic_requests?select=*&order=created_at.desc&limit=100');
    } elseif ($method === 'POST' && $path === '/api/requests') {
        $data = $controller->submit($body); http_response_code(201);
    } elseif ($method === 'GET' && $path === '/api/platform/dashboard') {
        Auth::platform($db);
        $data = ['requests' => $db->request('GET', '/rest/v1/clinic_requests?select=*&status=eq.pending&order=created_at.asc&limit=100'), 'clinics' => $db->request('GET', '/rest/v1/clinics?select=id,name,status,created_at&order=created_at.desc&limit=100'), 'audit' => $db->request('GET', '/rest/v1/audit_logs?select=*&clinic_id=is.null&order=created_at.desc&limit=20')];
    } elseif ($method === 'POST' && preg_match('#^/api/requests/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/decision$#D', $path, $m)) {
        Auth::platform($db); $data = $controller->decide($m[1], $body);
    } elseif ($method === 'POST' && $path === '/api/invites/accept') {
        $data = $operations->accept($body);
    } elseif (preg_match('#^/api/clinics/([0-9a-f-]{36})/(workspace|actions|status)$#D', $path, $m)) {
        $clinic = $m[1];
        if ($method === 'GET' && $m[2] === 'workspace') {
            Auth::clinic($db, $user['id'], $clinic); $data = $operations->workspace($clinic);
        } elseif ($method === 'POST' && $m[2] === 'actions') {
            $action = \MedFlow\Services\Validation::text($body,'action',4,20);
            Auth::clinic($db, $user['id'], $clinic, $action); $data = $operations->operation($clinic,$body);
        } elseif ($method === 'POST' && $m[2] === 'status') {
            Auth::platform($db);
            $data = $db->request('POST','/rest/v1/rpc/platform_clinic_status',['p_clinic'=>$clinic,'p_status'=>\MedFlow\Services\Validation::text($body,'status',6,9),'p_reason'=>\MedFlow\Services\Validation::text($body,'reason',5,500)]);
        } else throw new ApiError(404, 'not_found', 'Rota não encontrada.');
    } else throw new ApiError(404, 'not_found', 'Rota não encontrada.');
    echo json_encode(['data' => $data], JSON_THROW_ON_ERROR);
} catch (ApiError $e) {
    http_response_code($e->status); if ($e->status === 429) header('Retry-After: 60');
    echo json_encode(['error' => ['code' => $e->errorCode, 'message' => $e->getMessage(), 'request_id' => $requestId]]);
} catch (Throwable $e) {
    error_log('MedFlow ' . $requestId . ' ' . get_class($e)); http_response_code(500);
    echo json_encode(['error' => ['code' => 'internal', 'message' => 'Erro interno.', 'request_id' => $requestId]]);
}
