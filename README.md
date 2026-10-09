# MedFlow — primeira fase

Frontend HTML/CSS/JavaScript, API PHP 8.3 e Supabase Auth/PostgreSQL. Nenhum prontuário, dados de demonstração ou credencial privilegiada. Painéis operacionais e acompanhamento de senhas ficam para fases posteriores.

## Arquitetura e autorização

O navegador autentica diretamente no Supabase Auth. A API valida o Bearer token via `/auth/v1/user` e consulta PostgREST com esse mesmo token e uma chave pública. Não usa `service_role`, conexão privilegiada ou SQL concatenado. Supabase é responsável pelo armazenamento de senhas. `clinic_id` selecionado nunca constitui autorização.

Vínculos ficam em `clinic_members`, permitindo funções diferentes por clínica. RLS exige vínculo e clínica ativa. Superadministradores leem metadados de clínicas, solicitações e auditoria da plataforma, mas não recebem acesso a pacientes/atendimentos. Nenhuma escrita clínica é habilitada nesta fase. As FKs compostas mantêm referências na mesma clínica.

Solicitações pendentes são registros de `clinic_requests`; a clínica é criada apenas na aprovação. `private.decide_clinic_request` bloqueia a solicitação com `FOR UPDATE`, verifica o administrador e grava clínica, vínculo, decisão e auditoria na mesma transação. Wrappers públicos usam SECURITY INVOKER; implementações SECURITY DEFINER têm search_path vazio, permissões revogadas de PUBLIC/anon e autorização explícita. Não há autopromoção pelo frontend.

## Instalação

1. Instale PHP 8.3+ com cURL, Composer, Python 3 e a CLI Supabase. Node é necessário apenas para testes JS.
2. Crie um projeto Supabase de desenvolvimento. Não é necessário fornecer uma chave service_role ao MedFlow.
3. Aplique `supabase/migrations/*_initial_schema.sql` no SQL Editor ou configure a CLI e aplique as migrations após revisar o destino. `database/migrations` documenta a localização canônica.
4. Em Supabase Auth, habilite e-mail/senha e confirmação de e-mail. Desabilite login anônimo. Configure senha mínima de 12 caracteres, limites de Auth e SMTP para produção.
5. Configure Site URL e URLs de redirecionamento: `http://localhost:5173/login.html` e `http://localhost:5173/recuperar.html`; adicione as URLs HTTPS de produção posteriormente. O frontend utiliza o fluxo implicit client-only de confirmação/recuperação e remove tokens do fragmento após validar o usuário.
6. Copie `.env.example` para `backend/.env`. Defina `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` e `FRONTEND_ORIGIN` exata (sem barra final). A configuração recusa Supabase sem HTTPS.
7. Copie `frontend/js/config.example.js` para `frontend/js/config.js` e preencha URL Supabase, chave pública e `apiUrl`. Este arquivo é público e só recebe valores públicos.
8. Execute:

```sh
cd backend
composer install
php -S localhost:8080 -t public public/index.php
```

Em outro terminal:

```sh
python3 -m http.server 5173 --directory frontend
```

Acesse http://localhost:5173. Cadastre o proprietário, confirme o e-mail e envie a solicitação.

## Primeiro superadministrador

Cadastre e confirme uma conta destinada à administração. No SQL Editor, como operador autorizado do projeto, execute usando o UUID real de `auth.users`:

```sql
insert into public.platform_admins(user_id) values ('UUID_REAL_DA_CONTA_CONFIRMADA');
```

Registre essa concessão no processo administrativo da organização. Nenhum seed cria superadministradores automaticamente. Faça login e acesse `/superadmin/index.html`. Aprovação cria o vínculo do proprietário; rejeição exige motivo. Repetições de decisão são recusadas.

## API

Todas as rotas exceto health requerem Bearer token e e-mail confirmado:

| Método | Rota | Acesso |
|---|---|---|
| GET | /api/health | Público, verifica apenas processo PHP |
| GET | /api/me | Usuário e vínculos visíveis |
| GET | /api/requests | Solicitações próprias ou de plataforma |
| POST | /api/requests | Usuário confirmado: name, contact_email, city |
| GET | /api/platform/dashboard | Superadministrador |
| POST | /api/requests/{uuid}/decision | Superadministrador: decision approve/reject; reason obrigatório na rejeição |

Respostas `{data: ...}` ou `{error: {code, message, request_id}}`. Consultas listam até 100 registros e auditoria até 20. Contagens refletem os registros carregados; paginação completa será necessária para grande volume.

## Hospedagem

Vercel: configure Root Directory `frontend`, sem framework e sem build. Gere `js/config.js` com valores públicos antes do deploy. Em `frontend/vercel.json`, substitua `http://localhost:8080` em connect-src pela origem HTTPS real da API. O PHP é hospedado separadamente, com document root `backend/public`, encaminhando as rotas para `index.php`. Nunca publique `backend/.env` ou o diretório backend como arquivos estáticos. Desabilite display_errors em produção e configure TLS e cabeçalhos no proxy.

O rate limiter usa arquivos com flock fora da raiz pública: funciona em uma instância PHP com disco compartilhado pelos workers. Para múltiplas instâncias substitua por Redis/limite no gateway. Não confia em X-Forwarded-For; configure IP real no proxy de confiança. Auth tem limites próprios no Supabase; chamadas diretas ao Data API continuam protegidas por RLS, constraints e autorização RPC, mas o rate limiter PHP não limita chamadas diretas. Para controles globais, limite também no gateway/Supabase.

Sessões ficam em sessionStorage, separadas por aba, sem armazenar senhas. CSP, uso de textContent e ausência de scripts remotos reduzem risco XSS; tokens em armazenamento JS permanecem acessíveis a código da origem. Uma evolução para sessões HttpOnly/BFF pode reforçar proteção. Logout revoga a sessão no Supabase; tokens de acesso já emitidos podem continuar válidos até expirar. Configure duração curta conforme o risco.

## Testes

```sh
node tests/frontend.mjs
php tests/backend.php
find backend tests -name '*.php' -exec php -l {} \;
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/rls.sql
```

O teste SQL exige uma base Supabase descartável com a migration aplicada. Insere contas de teste identificadas por `example.test` e reverte tudo com ROLLBACK. Verifica isolamento entre clínicas, bloqueio de aprovação pelo proprietário, proibição de autopromoção, isolamento de solicitações, criação transacional de vínculo, restrições FK e bloqueio de RPC anônima. Não execute contra produção.

## Privacidade e próximos passos

Dados coletados nesta fase: nome do proprietário, e-mail, nome da clínica, contato e cidade. Nenhum CPF ou prontuário. Definir políticas de retenção, exclusão, backup, resposta a incidentes e termos de uso com a organização antes da operação comercial. Isso não representa certificação de conformidade LGPD.

Próximas fases: gestão de membros com convites seguros, especialidades/consultórios, filas concorrentes, tickets, auditoria clínica, relatórios, MFA administrativo e monitoramento. Acesso público por token de paciente não está habilitado: exigirá token aleatório criptográfico, hash armazenado em schema privado, expiração, limitação de acesso e RPC retornando somente a senha do titular. Realtime será habilitado apenas com políticas apropriadas quando houver filas.

O banco remoto foi configurado em 09/10/2026 no projeto Supabase associado ao MedFlow. Foram aplicadas as migrations initial_schema e backfill_existing_profiles. As 12 tabelas têm RLS habilitado; as contas preexistentes receberam profiles. A hospedagem de produção e os testes completos de e-mail continuam pendentes.

## Validação desta entrega

- JavaScript: 3 testes de sessão passaram; sintaxe dos módulos validada.
- PHP 8.3.35: todos os 9 arquivos PHP passaram no lint; 7 verificações de validação/autenticação/rate limiting passaram.
- PostgreSQL 17 descartável: migration aplicada e teste SQL de autorização/isolamento executado com um stub mínimo de auth.users/auth.uid. Isso valida PostgreSQL/RLS, mas não substitui teste com o Supabase Auth real. `tests/postgres-auth-stub.sql` nunca deve ser aplicado em Supabase.
- Confirmação por e-mail, recuperação real, envio SMTP, implantação Vercel e integração ponta a ponta ainda não foram executados.

Referências consultadas: [Supabase Auth](https://supabase.com/docs/guides/auth/passwords), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [changelog](https://supabase.com/changelog).

## Iniciar frontend e API juntos

Com os arquivos de configuração preenchidos, execute na raiz do projeto:

```sh
bash scripts/dev.sh
```

O script utiliza PHP instalado ou o contêiner PHP via Podman, serve apenas a pasta frontend e verifica as duas portas. Servidores que já respondem são reutilizados. Mantenha o terminal aberto. Use http://127.0.0.1:5173 para corresponder ao CORS configurado. Logs locais ficam em backend/var, ignorados pelo Git.

Após a implantação remota: consultas RLS de perfil, membros, solicitações e clínicas foram verificadas com o papel authenticated em transação revertida, sem criar contas de teste ou alterar registros. Nenhuma função administrativa foi concedida automaticamente às contas existentes.
