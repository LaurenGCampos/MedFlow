<?php
declare(strict_types=1);
require __DIR__ . '/../backend/config/bootstrap.php';
use MedFlow\Middleware\Auth;
use MedFlow\Middleware\RateLimit;
use MedFlow\Services\Validation;
use MedFlow\Services\ApiError;
$count = 0;
function expectError(callable $fn, int $status): void { global $count; try {$fn();} catch (ApiError $e) {if($e->status === $status){$count++;return;} throw $e;} throw new RuntimeException('Expected rejection'); }
expectError(fn()=>Auth::token(''),401);
expectError(fn()=>Auth::token('Bearer bad token'),401);
expectError(fn()=>Validation::text(['name'=>['attack']],'name',3,120),422);
expectError(fn()=>Validation::text(['name'=>"abc\n<script>"],'name',3,120),422);
expectError(fn()=>Validation::text(['name'=>'  '],'name',3,120),422);
if(Validation::text(['name'=>' Clínica '],'name',3,120)!=='Clínica')throw new RuntimeException('Validation failed'); $count++;
$dir=sys_get_temp_dir().'/medflow-tests-'.bin2hex(random_bytes(8));putenv('RATE_LIMIT_DIR='.$dir);
RateLimit::check('test',1);expectError(fn()=>RateLimit::check('test',1),429);
unlink($dir.'/'.hash('sha256','test'));rmdir($dir);

final class TestGateway implements \MedFlow\Repositories\Gateway {
    public array $calls = [];
    public function __construct(public array $responses = []) {}
    public function request(string $method, string $path, ?array $body = null): mixed { $this->calls[] = [$method,$path,$body]; return array_shift($this->responses) ?? []; }
}
$gateway = new TestGateway([["id"=>"fixture-ticket"]]);
$ops = new \MedFlow\Controllers\OperationsController($gateway);
$clinic = '42000000-0000-0000-0000-000000000001';
$ticket = '46000000-0000-0000-0000-000000000001';
$queue = '44000000-0000-0000-0000-000000000001';
$patient = '45000000-0000-0000-0000-000000000001';
expectError(fn()=>$ops->operation($clinic,['action'=>'checkin','queue_id'=>$queue,'patient_id'=>$patient,'priority'=>'false']),422);
expectError(fn()=>$ops->operation($clinic,['action'=>'queue','name'=>'Queue','doctor_id'=>'injection','room_id'=>$ticket,'specialty_id'=>$ticket,'expected_minutes'=>15]),422);
expectError(fn()=>$ops->track(['token'=>'invalid']),422);
$result=$ops->operation($clinic,['action'=>'checkin','queue_id'=>$queue,'patient_id'=>$patient,'priority'=>false,'clinic_id'=>'attacker-clinic','token'=>'attacker-token']);
if(strlen($result['token'])!==64 || $gateway->calls[0][2]['p_clinic']!==$clinic || $gateway->calls[0][2]['p_data']['token']==='attacker-token' || isset($gateway->calls[0][2]['p_data']['clinic_id']))throw new RuntimeException('Tenant or token validation failed');$count++;
$gateway=new TestGateway([[['role'=>'receptionist','clinics'=>['status'=>'active']]]]);
expectError(fn()=>Auth::clinic($gateway,'fixture-user',$clinic,'invite'),403);
$gateway=new TestGateway([[]]);expectError(fn()=>Auth::clinic($gateway,'fixture-user',$clinic),403);
$gateway=new TestGateway([[['role'=>'doctor','clinics'=>['status'=>'suspended']]]]);expectError(fn()=>Auth::clinic($gateway,'fixture-user',$clinic,'call'),403);
$gateway=new TestGateway([[['role'=>'doctor','clinics'=>['status'=>'active']]]]);Auth::clinic($gateway,'fixture-user',$clinic,'call');$count++;
$gateway=new TestGateway([['id'=>'fixture-user','is_anonymous'=>false,'email_confirmed_at'=>null]]);expectError(fn()=>Auth::user($gateway),401);
echo "$count assertions passed\n";

