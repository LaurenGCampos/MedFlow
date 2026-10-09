# Referência da API REST — MedFlow

Este documento é a referência oficial e completa da API REST do **MedFlow**, desenvolvida em **PHP 8.3**.

---

## 1. Convenções Globais

### 1.1. URLs Base
- **Desenvolvimento Local:** `http://127.0.0.1:8080` (ou `http://localhost:8080`)
- **Produção:** Definida pela variável de ambiente do frontend e certificado HTTPS.

### 1.2. Cabeçalhos HTTP Globais
- `Content-Type: application/json; charset=utf-8` (Obrigatório em requisições `POST`)
- `Cache-Control: no-store`
- `X-Content-Type-Options: nosniff`
- `Authorization: Bearer <access_token>` (Obrigatório em todas as rotas protegidas)

### 1.3. Formato Padrão de Resposta

#### Sucesso (HTTP 200 ou 201):
```json
{
  "data": { ... }
}
```

#### Erro (HTTP 4xx ou 5xx):
```json
{
  "error": {
    "code": "validation",
    "message": "Campo inválido: name",
    "request_id": "7b8e3a201c9f4d1e"
  }
}
```
> O `request_id` é gerado aleatoriamente (`bin2hex(random_bytes(8))`) a cada requisição para facilitar correlação de logs no servidor em caso de suporte ou auditoria.

### 1.4. Catálogo de Códigos de Status HTTP

| Código | Nome | Significado no MedFlow |
|---|---|---|
| `200` | OK | Requisição processada com sucesso. |
| `201` | Created | Recurso criado com sucesso (ex: submissão de solicitação de clínica). |
| `204` | No Content | Pré-vôo CORS (`OPTIONS`) processado com êxito. |
| `400` | Bad Request | Corpo JSON malformado ou não é um objeto JSON. |
| `401` | Unauthorized | Token ausente, inválido, expirado ou e-mail ainda não confirmado. |
| `403` | Forbidden | Origem não autorizada (CORS) ou perfil/função sem permissão para o recurso. |
| `404` | Not Found | Rota não existente. |
| `409` | Conflict | Conflito com o estado operacional atual (ex: médico tentando chamar dois pacientes ao mesmo tempo, ou tentativa de remoção do último administrador). |
| `413` | Payload Too Large | Corpo da requisição excede o limite máximo de 16 KB (16384 bytes). |
| `415` | Unsupported Media Type | Cabeçalho `Content-Type` não inicia com `application/json`. |
| `422` | Unprocessable Entity | Erro de validação de campo (tamanho, formato UUID, e-mail inválido, etc.). |
| `429` | Too Many Requests | Limite de taxa excedido. Inclui cabeçalho `Retry-After: 60`. |
| `500` | Internal Server Error | Erro inesperado capturado. Detalhes técnicos ocultos do cliente. |
| `502` | Bad Gateway | Falha de comunicação de rede ou resposta 5xx do upstream Supabase. |
| `503` | Service Unavailable | Integração Supabase não configurada ou banco sem migrations aplicadas. |

### 1.5. Políticas de Rate Limiting
- **Por IP de Origem:** Máximo de **120 requisições por minuto** por endereço IP (`$_SERVER['REMOTE_ADDR']`).
- **Por Usuário Autenticado:** Máximo de **60 requisições por minuto** por `user_id`.
- Ao estourar o limite, o servidor responde imediatamente com `HTTP 429` e mensagem `"Muitas tentativas. Aguarde um minuto."`.

---

## 2. Endpoints Públicos

### 2.1. Checagem de Saúde da API
Verifica se o processo PHP está respondendo (não executa consultas ao banco).
- **Método:** `GET`
- **Rota:** `/api/health`
- **Autenticação:** Nenhuma
- **Exemplo de Resposta (HTTP 200):**
```json
{
  "data": {
    "status": "ok"
  }
}
```

### 2.2. Acompanhamento Público de Senha
Consulta a situação da senha individual a partir do segredo de 64 hexadecimais entregue ao paciente.
- **Método:** `POST`
- **Rota:** `/api/public/track`
- **Autenticação:** Nenhuma
- **Payload:**
```json
{
  "token": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
}
```
- **Exemplo de Resposta (HTTP 200):**
```json
{
  "data": {
    "id": "46000000-0000-0000-0000-000000000001",
    "number": 14,
    "status": "waiting",
    "priority": false,
    "clinic": "Clínica Vida & Saúde",
    "queue": "Cardiologia Geral",
    "room": "Consultório 03",
    "called_at": null,
    "created_at": "2026-10-09T10:15:00Z",
    "position": 2,
    "estimated_minutes": 30
  }
}
```

---

## 3. Endpoints de Usuário & Solicitação de Clínica

### 3.1. Dados do Usuário Atual e Vínculos
Retorna a identidade do usuário, se possui papel de superadministrador da plataforma e suas clínicas ativas.
- **Método:** `GET`
- **Rota:** `/api/me`
- **Autenticação:** Bearer Token
- **Exemplo de Resposta (HTTP 200):**
```json
{
  "data": {
    "id": "11111111-2222-3333-4444-555555555555",
    "email": "medico@exemplo.com",
    "platform_admin": false,
    "memberships": [
      {
        "clinic_id": "42000000-0000-0000-0000-000000000001",
        "role": "doctor",
        "clinics": {
          "name": "Clínica Vida & Saúde",
          "status": "active"
        }
      }
    ]
  }
}
```

### 3.2. Listar Solicitações de Clínicas
Retorna as solicitações do próprio usuário (ou todas as 100 mais recentes se for superadministrador da plataforma).
- **Método:** `GET`
- **Rota:** `/api/requests`
- **Autenticação:** Bearer Token

### 3.3. Solicitar Abertura de Clínica
Envia proposta de abertura de clínica para análise da administração da plataforma.
- **Método:** `POST`
- **Rota:** `/api/requests`
- **Autenticação:** Bearer Token (usuário com e-mail confirmado)
- **Payload:**
```json
{
  "name": "Clínica São Camilo",
  "contact_email": "contato@saocamilo.com.br",
  "city": "Campinas"
}
```
- **Resposta:** `HTTP 201 Created` com UUID da solicitação criada.

---

## 4. Endpoints de Administração da Plataforma (*Superadmin*)

Todas as rotas desta seção exigem que o usuário autenticado esteja registrado em `public.platform_admins`.

### 4.1. Dashboard Global da Plataforma
Retorna contagem e listagem das solicitações pendentes, clínicas cadastradas e eventos recentes de auditoria.
- **Método:** `GET`
- **Rota:** `/api/platform/dashboard`
- **Autenticação:** Bearer Token (Platform Admin)
- **Exemplo de Resposta (HTTP 200):**
```json
{
  "data": {
    "requests": [
      {
        "id": "...",
        "name": "Clínica São Camilo",
        "contact_email": "contato@saocamilo.com.br",
        "city": "Campinas",
        "status": "pending",
        "created_at": "..."
      }
    ],
    "clinics": [
      {
        "id": "...",
        "name": "Clínica Vida & Saúde",
        "status": "active",
        "created_at": "..."
      }
    ],
    "audit": [
      {
        "action": "clinic_request.approved",
        "target_id": "...",
        "created_at": "..."
      }
    ]
  }
}
```

### 4.2. Julgar Solicitação de Clínica
Aprova ou rejeita uma solicitação pendente.
- **Método:** `POST`
- **Rota:** `/api/requests/{request_uuid}/decision`
- **Autenticação:** Bearer Token (Platform Admin)
- **Payload de Aprovação:**
```json
{
  "decision": "approve"
}
```
- **Payload de Rejeição:**
```json
{
  "decision": "reject",
  "reason": "Dados cadastrais incompletos e telefone corporativo não verificado."
}
```

### 4.3. Alterar Situação da Clínica
Permite suspender ou reativar uma clínica na plataforma.
- **Método:** `POST`
- **Rota:** `/api/clinics/{clinic_uuid}/status`
- **Autenticação:** Bearer Token (Platform Admin)
- **Payload:**
```json
{
  "status": "suspended",
  "reason": "Inadimplência contratual ou verificação regulatória pendente."
}
```

---

## 5. Endpoints de Convites

### 5.1. Aceitar Convite de Equipe
Resgata um convite de 64 hexadecimais gerado pelo administrador da clínica.
- **Método:** `POST`
- **Rota:** `/api/invites/accept`
- **Autenticação:** Bearer Token (o e-mail do token JWT deve ser idêntico ao e-mail para o qual o convite foi emitido).
- **Payload:**
```json
{
  "token": "7a8b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3"
}
```
- **Resposta:** `HTTP 200 OK` contendo o `clinic_id` associado.

---

## 6. Endpoints do Espaço da Clínica (*Workspace & Actions*)

### 6.1. Carregar Espaço da Clínica (*Workspace*)
Retorna todos os dados operacionais necessários para a interface de acordo com a função do usuário.
- **Método:** `GET`
- **Rota:** `/api/clinics/{clinic_uuid}/workspace`
- **Autenticação:** Bearer Token (Membro com vínculo ativo)
- **Dados Retornados por Papel:**
  - `admin`: Dados da clínica, especialidades, consultórios, filas, lista de até 500 pacientes mais recentes, senhas dos últimos 2 dias, integrantes, convites e métricas dos últimos 30 dias.
  - `receptionist`: Especialidades, consultórios, filas, até 500 pacientes mais recentes e senhas dos últimos 2 dias.
  - `doctor`: Consultórios, filas atribuídas ao médico e senhas da fila correspondente.
  - `patient`: Histórico individual das próprias senhas emitidas nos últimos 30 dias.

### 6.2. Executar Ação Clínica (*Actions*)
- **Método:** `POST`
- **Rota:** `/api/clinics/{clinic_uuid}/actions`
- **Autenticação:** Bearer Token (Membro com vínculo ativo e permissão compatível com a ação)

#### Catálogo de Ações Permitidas:

| Ação (`action`) | Papéis Permitidos | Campos Obrigatórios no Payload | Descrição |
|---|---|---|---|
| `settings` | `admin` | `name`, `timezone`, `city`, `contact_email` | Atualiza configurações institucionais da clínica. |
| `specialty` | `admin` | `name` | Cadastra nova especialidade médica. |
| `specialty_edit` | `admin` | `id`, `name` | Edita o nome de uma especialidade existente. |
| `room` | `admin` | `name` | Cadastra novo consultório ou sala. |
| `room_edit` | `admin` | `id`, `name` | Edita o nome de um consultório. |
| `queue` | `admin` | `name`, `specialty_id`, `doctor_id`, `room_id`, `expected_minutes` | Cria nova fila de atendimento. |
| `queue_edit` | `admin` | `id`, `name`, `room_id`, `expected_minutes` | Altera dados da fila (não permite alteração se houver tickets ativos). |
| `queue_status` | `admin` | `id`, `status` (`open` ou `closed`) | Abre ou fecha uma fila (fecha apenas se não houver senhas aguardando). |
| `invite` | `admin` | `email`, `role` | Gera convite de equipe de 7 dias com segredo de 64 hexadecimais retornado no campo `token`. |
| `revoke_invite` | `admin` | `id` | Revoga um convite pendente. |
| `member` | `admin` | `user_id`, `role`, `active` | Altera função ou ativação de membro (impede desativação do último administrador). |
| `patient` | `admin`, `receptionist` | `name`, `email` (opcional) | Cadastra novo paciente na clínica. |
| `patient_edit` | `admin`, `receptionist` | `id`, `name` | Corrige o nome de um paciente cadastrado. |
| `checkin` | `admin`, `receptionist` | `queue_id`, `patient_id`, `priority` (boolean) | Registra chegada, gera número de senha sequencial do dia e emite link de 48h. |
| `cancel` | `admin`, `receptionist` | `id` (ticket_id) | Cancela senha que estava em espera ou chamada. |
| `tracking` | `admin`, `receptionist` | `id` (ticket_id) | Gera novo link para a senha, invalidando o link público anterior. |
| `call` | `doctor` | `queue_id` | Chama o próximo paciente da fila atribuída ao médico (ordena por prioridade e chegada). |
| `start` | `doctor` | `id` (ticket_id) | Inicia o atendimento médico da senha chamada. |
| `finish` | `doctor` | `id` (ticket_id) | Conclui o atendimento médico e a consulta. |
| `absent` | `doctor` | `id` (ticket_id) | Registra ausência do paciente após ser chamado. |
