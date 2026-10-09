# MedFlow

Sistema de clínicas com HTML/CSS/JavaScript, API PHP 8.3 e Supabase Auth/PostgreSQL. Inclui aprovação de clínicas, administração, recepção, atendimento médico e acompanhamento de senhas. Não inclui prontuários.

## Usar a instalação local

Abra http://127.0.0.1:5173. O serviço de usuário `medflow-dev.service` inicia frontend e API automaticamente ao entrar na sessão do computador.

```sh
systemctl --user status medflow-dev.service
systemctl --user restart medflow-dev.service
journalctl --user -u medflow-dev.service -n 50
```

Para instalar o serviço em outra máquina configurada: `bash scripts/install-local-service.sh`. Alternativamente, execute `bash scripts/dev.sh` e mantenha o terminal aberto. Logs ficam em `backend/var/`. Para desativar: `systemctl --user disable --now medflow-dev.service`.

## Fluxo operacional

1. O proprietário cria uma conta, confirma o e-mail e solicita sua clínica.
2. O superadministrador aprova ou rejeita a solicitação. Aprovação cria clínica e vínculo administrativo na mesma transação. Suspensão bloqueia operações clínicas.
3. O administrador cadastra especialidades e consultórios, convida médicos e recepcionistas e configura filas com médico e consultório.
4. Convites são compartilhados manualmente. O destinatário cria/confirma uma conta com o mesmo e-mail e aceita o link. Convites expiram em sete dias e podem ser revogados.
5. A recepção cadastra pacientes e registra chegada, incluindo prioridade quando aplicável. Cada chegada gera uma senha e um link individual válido por 48 horas.
6. O médico chama o próximo paciente, inicia e finaliza o atendimento ou registra ausência. Não pode manter dois chamados/atendimentos simultâneos.
7. O paciente acompanha posição, estimativa e consultório pelo link, sem login. A página atualiza a cada dez segundos e oferece notificações enquanto estiver aberta. Rotacionar o link invalida o anterior.

Se um paciente tiver conta confirmada, seu e-mail pode ser vinculado no cadastro pela recepção, habilitando o painel pessoal. Pacientes cadastrados antes da criação da conta continuam usando o link individual. Estimativas são aproximações operacionais.

## Arquitetura e segurança

A API valida cada token com Supabase Auth e usa a chave pública e o token do próprio usuário para consultar PostgREST. Não utiliza service_role. Senhas ficam exclusivamente no Supabase Auth. A seleção de clinic_id nunca prova autorização: API e banco verificam vínculo, função e estado da clínica.

Tabelas públicas têm RLS; referências clínicas usam FKs compostas. RPCs verificam permissões e executam alterações e auditoria atomicamente. Wrappers públicos são SECURITY INVOKER; implementações privadas SECURITY DEFINER possuem search_path vazio e privilégios limitados. O superadministrador gerencia metadados da plataforma e não ganha acesso a pacientes.

Convites e links usam tokens aleatórios de 32 bytes, armazenados somente como hash em tabelas privadas com acesso direto bloqueado. Acompanhamento público retorna apenas informações da própria senha, sem nomes ou dados de outros pacientes. A UI usa textContent, CSP e módulos locais. Sessões ficam em sessionStorage; uma evolução para BFF/cookies HttpOnly pode reforçar proteção contra código malicioso na origem.

O rate limiter PHP usa arquivos/flock e atende uma instância. Para múltiplas instâncias, configure limite compartilhado no gateway/Redis. Chamadas diretas ao Supabase permanecem protegidas por RLS/RPC, mas não passam pelo limite PHP. Não há confiança automática em X-Forwarded-For.

## Configurar outra instalação

1. Instale PHP 8.3+ com cURL e JSON, Composer e Python 3; Podman pode substituir o PHP local. Node é necessário para testes de frontend.
2. Crie um projeto Supabase e aplique **todas** as migrations de `supabase/migrations/` em ordem. Use a CLI vinculada ao projeto correto ou o SQL Editor. Não aplique `tests/postgres-auth-stub.sql` em Supabase.
3. Habilite e-mail/senha e confirmação de e-mail, desabilite usuários anônimos e configure SMTP para produção. Configure senha mínima de 12 caracteres e limites de Auth.
4. Configure Site URL `http://127.0.0.1:5173` e permita redirecionamentos para `/login.html` e `/recuperar.html` nessa origem. Adicione as URLs HTTPS reais quando publicar. localhost e 127.0.0.1 são origens diferentes.
5. Copie `.env.example` para `backend/.env`: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, FRONTEND_ORIGIN exata e RATE_LIMIT_DIR. Nunca publique esse arquivo.
6. Copie `frontend/js/config.example.js` para `frontend/js/config.js`: URL Supabase, chave pública e apiUrl. Apenas valores públicos pertencem a esse arquivo; ele é ignorado pelo Git.
7. Execute `composer install` em backend e `bash scripts/dev.sh` na raiz.

A primeira conta de plataforma deve ser uma conta real confirmada, concedida pelo operador autorizado no SQL Editor. Insira seu UUID em platform_admins e registre a concessão em audit_logs na mesma transação. Nenhum cadastro público permite autopromoção. Nesta instalação, a conta escolhida pelo proprietário já recebeu essa concessão auditada.

## API

Respostas usam `{data: ...}` ou `{error: {code, message, request_id}}`. Rotas autenticadas exigem Bearer token válido e e-mail confirmado.

| Método | Rota | Acesso |
|---|---|---|
| GET | /api/health | Público; saúde do processo, não teste do banco |
| POST | /api/public/track | Público; token individual |
| GET | /api/me | Usuário e vínculos |
| GET/POST | /api/requests | Solicitações próprias; plataforma pode consultar |
| GET | /api/platform/dashboard | Superadministrador |
| POST | /api/requests/{uuid}/decision | Superadministrador |
| POST | /api/clinics/{uuid}/status | Superadministrador |
| POST | /api/invites/accept | Destinatário confirmado |
| GET | /api/clinics/{uuid}/workspace | Vínculo ativo; dados conforme função |
| POST | /api/clinics/{uuid}/actions | Permissões específicas por ação |

Painel de plataforma carrega até 100 registros e auditoria recente; contagens representam os registros carregados. Cadastro operacional carrega até 500 pacientes recentes. Relatórios consideram 30 dias. Paginação e busca no servidor devem ser ampliadas para grande volume.

## Publicação

Frontend na Vercel: Root Directory `frontend`, sem framework. Gere `js/config.js` com valores públicos antes do deploy: ele não acompanha o Git. Atualize connect-src em `frontend/vercel.json` com a origem HTTPS da API. PHP deve ser hospedado separadamente, com document root `backend/public` e rotas encaminhadas a index.php. Configure TLS, CORS exato, display_errors desabilitado, variáveis de ambiente e diretório de rate limit gravável. Não publique backend como arquivos estáticos.

GitHub armazena o código; não conecta automaticamente a aplicação ao Supabase. Migrations e configurações de Auth continuam sendo etapas próprias. Esta instalação local está conectada ao projeto Supabase; hospedagem de produção ainda não foi realizada.

## Verificação

```sh
npm ci
npm test
php tests/backend.php
find backend tests -name '*.php' -exec php -l {} \;
npx playwright install chromium
npm run test:browser
```

Para integração SQL, use apenas uma base **descartável** com migrations aplicadas e execute tests/rls.sql e tests/operations.sql via psql com ON_ERROR_STOP. Os testes inserem fixtures identificadas por example.test e terminam em ROLLBACK. Em PostgreSQL simples e vazio, o stub de Auth pode ser usado somente nessa base descartável.

`python3 tests/concurrency.py` exige um contêiner PostgreSQL local chamado medflow-operations-postgres, com usuário postgres. Cria uma base de teste própria, aplica migrations e remove apenas essa base ao terminar.

Validação executada nesta entrega:

- Cinco testes de autenticação JavaScript e 16 verificações PHP.
- Oito testes Playwright dos fluxos de login, recepção, médico, administração, paciente, convite, acompanhamento e tela móvel, usando respostas simuladas explicitamente identificadas como testes.
- Migrations e testes de autorização/RLS/fluxo operacional em PostgreSQL 17 descartável.
- Concorrência: 16 chegadas simultâneas com numeração única, bloqueio de chegada duplicada e apenas uma chamada ativa entre oito tentativas simultâneas.
- Migrations aplicadas no Supabase real e verificações de schema/RLS/conectividade. Não foram realizados login com senha do usuário ou testes reais de entrega SMTP.

## Operação e privacidade

Sem CPF ou prontuários. Há nomes de pacientes, dados operacionais e auditoria: defina retenção, exclusão, backups, restauração, monitoramento, resposta a incidentes e termos antes do uso comercial. Não representa certificação LGPD. Relatórios CSV devem ser tratados como dados da clínica.

O acompanhamento usa polling; Realtime não é necessário para esta versão. Publicação, SMTP de produção, MFA administrativo e validação ponta a ponta com a equipe real continuam sendo configuração operacional. A proteção contra senhas vazadas está desativada no projeto; verifique disponibilidade e habilitação em [Supabase Password Security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
