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
echo "$count assertions passed\n";
