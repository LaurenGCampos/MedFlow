# Estratégia & Execução de Testes — MedFlow

Este documento descreve detalhadamente a pirâmide de testes, os cenários automatizados e os procedimentos para execução de cada suíte de testes do **MedFlow**.

---

## 1. Visão Geral da Pirâmide de Testes

O MedFlow possui uma suíte abrangente de testes automatizados cobrindo todas as camadas críticas:

```
                  ┌───────────────────────┐
                  │ Testes E2E Navegador  │  8 testes Playwright (fluxos de ponta a ponta)
                  │  (workflow.spec.js)   │
               ┌──┴───────────────────────┴──┐
               │    Testes de Concorrência   │  3 testes multithread (race conditions)
               │      (concurrency.py)       │
            ┌──┴─────────────────────────────┴──┐
            │   Testes de RLS & SQL Operacional │  Isolamento multi-tenant & RPCs
            │      (rls.sql / operations.sql)   │
         ┌──┴───────────────────────────────────┴──┐
         │     Testes de Contrato Backend PHP      │  16 asserções de validação e segurança
         │             (backend.php)               │
      ┌──┴─────────────────────────────────────────┴──┐
      │          Testes Unitários Frontend            │  5 testes de autenticação e sessão
      │                (frontend.mjs)                 │
      └───────────────────────────────────────────────┘
```

---

## 2. Testes Unitários de Frontend (`tests/frontend.mjs`)

- **Objetivo:** Validar as funções do módulo de autenticação (`frontend/js/auth.js`) sem necessidade de conexão de rede ou navegador real.
- **Tecnologia:** Executor de testes nativo do Node.js (`node:test` e `node:assert/strict`).
- **Cenários Cobertos:**
  1. Delegação da verificação de senha diretamente ao Supabase (garantindo que senhas nunca sejam armazenadas no estado local).
  2. Renovação automática de sessões expiradas antes de qualquer requisição de API.
  3. Limpeza total de sessão no `sessionStorage` em caso de falha de refresh token.
  4. Mensagem explicativa e amigável em caso de tentativa de login com e-mail não confirmado.
  5. Mensagem clara em caso de credenciais incorretas.

### Execução:
```sh
npm test
```
*Saída esperada: 5 testes passando com sucesso.*

---

## 3. Testes de Validação e Segurança do Backend (`tests/backend.php`)

- **Objetivo:** Verificar rigorosamente as regras de segurança do gateway PHP:
  - Extração e validação de tokens Bearer no cabeçalho `Authorization`.
  - Sanitização de strings (rejeição de caracteres de controle, tags maliciosas e limites de tamanho).
  - Rate limiting baseado em arquivo com bloqueio HTTP 429.
  - Validação estrita de UUIDs em parâmetros de rotas e corpos JSON.
  - Prevenção de adulteração de tenant: garantia de que `clinic_id` enviado no payload seja ignorado e que o valor verificado na rota seja utilizado.
  - Bloqueio de operações para clínicas com status `suspended`.
  - Verificação de exigência de e-mail confirmado.

### Execução:
Com PHP 8.3 instalado localmente:
```sh
php tests/backend.php
```
Ou executando dentro do contêiner Podman/Docker:
```sh
podman run --rm -v "$PWD:/app:ro,z" -w /app docker.io/library/php:8.3-cli php tests/backend.php
```
*Saída esperada: `16 assertions passed`.*

### Verificação de Sintaxe PHP (Linting):
```sh
find backend tests -name '*.php' -exec php -l {} \;
```

---

## 4. Testes de Ponta a Ponta no Navegador (`tests/browser/workflow.spec.js`)

- **Objetivo:** Simular interações reais de usuários em navegadores headless utilizando dados mockados explicitamente identificados como testes.
- **Tecnologia:** [Playwright Test](https://playwright.dev/).
- **Cenários Cobertos (8 testes):**
  1. **Roteamento de Login:** Recepcionista realiza login e é redirecionada para `/recepcao/index.html`.
  2. **Emissão de Senha:** Recepção realiza o check-in de um paciente, emite senha sequencial e gera diálogo com link de acompanhamento individual (`/acompanhar.html#<token>`).
  3. **Ciclo de Atendimento Médico:** Médico chama a senha aguardando, confirma início da consulta e finaliza o atendimento.
  4. **Gestão do Administrador:** Administrador cria convite restrito por e-mail, visualiza configurações de filas e acessa relatório com botão de exportação CSV.
  5. **Privacidade do Paciente:** Paciente autenticado visualiza somente suas próprias senhas e não possui acesso a ações clínicas ou nomes de terceiros.
  6. **Acompanhamento Público:** Paciente sem conta acessa `/acompanhar.html#<token>`, visualiza status e consultório, e o token é removido imediatamente da URL.
  7. **Aceite de Convite com Persistência:** Convite resiste ao redirecionamento de login e é aceito antes de entrar na clínica.
  8. **Responsividade Mobile:** A interface da recepção em tela de smartphone (390x844) se mantém contida na viewport sem overflow horizontal.

### Instalação do Navegador Playwright:
```sh
npx playwright install chromium
```

### Execução dos Testes no Navegador:
```sh
npm run test:browser
```

---

## 5. Testes de Isolamento e RLS no Banco de Dados (`tests/rls.sql`)

- **Objetivo:** Garantir que as políticas de Row Level Security (RLS) impeçam qualquer vazamento de dados entre tenants (*BOLA / Broken Object Level Authorization*).
- **Ambiente:** Executar **apenas em banco PostgreSQL descartável** com as migrações aplicadas.
- **Cenários Validados:**
  - Isolamento estrito entre Clínica A e Clínica B (usuário da Clínica A recebe contagem zero para pacientes da Clínica B).
  - Bloqueio de inserção direta em `platform_admins` para prevenir autopromoção.
  - Bloqueio de aprovação de clínica por usuários comuns.
  - Isolamento de solicitações de abertura de clínica (proprietário A não vê solicitações do proprietário B).
  - Isolamento do Superadministrador: o superadministrador tem acesso a metadados da plataforma, mas suas consultas diretas a `patients` retornam zero linhas.
  - Criação atômica de vínculo administrativo na aprovação de clínica.
  - Auditoria completa de aprovações e rejeições.

### Execução:
```sh
psql -v ON_ERROR_STOP=1 -f tests/rls.sql
```
*Todas as fixtures realizam `rollback` automático ao final da execução.*

---

## 6. Testes do Fluxo Operacional SQL (`tests/operations.sql`)

- **Objetivo:** Validar a execução ponta a ponta das stored procedures `private.clinic_operation`, `accept_staff_invite` e `clinic_workspace`.
- **Cenários Validados:**
  - Cadastro de especialidades, consultórios e filas.
  - Geração de convite para recepcionista com hash SHA-256 de 64 caracteres.
  - Tentativa de aceite de convite com e-mail incorreto é bloqueada.
  - Aceite de convite com e-mail correto é concluído com sucesso.
  - Tentativa de reutilização de convite aceito é bloqueada.
  - Registro de pacientes e dois check-ins simultâneos (um prioritário e um regular).
  - Tentativa de check-in duplicado para o mesmo paciente ativo é rejeitada com erro de unicidade.
  - Tentativa de recepcionista executar ação exclusiva de administrador é rejeitada.
  - Tentativa de acesso a workspace de outra clínica é rejeitada com erro de privilégio insuficiente.
  - Consulta do workspace por paciente autenticado retorna unicamente suas próprias senhas e **omite o array `patients`**.
  - A senha prioritária assume posição 1 mesmo tendo sido emitida após a senha regular.

### Execução:
```sh
psql -v ON_ERROR_STOP=1 -f tests/operations.sql
```

---

## 7. Testes de Concorrência & Condições de Corrida (*Race Conditions*) (`tests/concurrency.py`)

- **Objetivo:** Testar concorrência extrema simulando múltiplos clientes fazendo requisições no mesmo milissegundo.
- **Ambiente:** Executa contra o contêiner Podman local `medflow-operations-postgres`. Cria um banco temporário aleatório (`medflow_concurrency_<hash>`), aplica todas as migrações e descarta o banco ao final do teste.
- **Cenários Validados:**
  1. **16 Check-ins Simultâneos em Paralelo:** 16 threads realizam check-in ao mesmo tempo. Valida que todas recebem números sequenciais únicos de 1 a 16 sem lacunas ou duplicidades.
  2. **Check-in Duplicado Simultâneo:** 2 threads tentam fazer check-in simultaneamente para o mesmo paciente. Valida que exatamente 1 tem sucesso e a outra é bloqueada.
  3. **8 Chamadas Simultâneas de Médicos:** 8 threads tentam chamar pacientes na mesma fila ao mesmo tempo. Valida que as chamadas são serializadas e apenas 1 atendimento ativo é gerado.

### Execução:
```sh
python3 tests/concurrency.py
```
*Saída esperada:*
```
PASS: 16 concurrent ticket issues have unique sequential numbers
PASS: concurrent duplicate arrival produces exactly one ticket
PASS: 8 concurrent doctor calls produce exactly one active call
```
