# Implantação, Configuração & Operação — MedFlow

Este documento contém o guia passo a passo para configuração de novos ambientes de desenvolvimento, execução local contínua e publicação em produção do **MedFlow**.

---

## 1. Requisitos do Sistema

Para executar ou hospedar o MedFlow, são necessários:
- **Ambiente de Desenvolvimento:**
  - **PHP 8.3+** com extensões `curl`, `json`, `mbstring` (ou **Podman** / **Docker** com imagem `docker.io/library/php:8.3-cli`).
  - **Python 3.8+** (utilizado no servidor estático local e testes de concorrência).
  - **Node.js 18+** e **npm** (para execução de testes automatizados e Playwright).
  - **PostgreSQL 17** ou instância de projeto no **Supabase**.
- **Ambiente de Produção:**
  - **Frontend:** Vercel, Cloudflare Pages, Netlify ou servidor web Nginx/Apache servindo arquivos estáticos.
  - **Backend:** Servidor Linux (Ubuntu/Debian) com PHP 8.3-FPM, Nginx, TLS/HTTPS ativo e suporte a `flock`.
  - **Banco e Autenticação:** Projeto Supabase (PostgreSQL 17 gerenciado com GoTrue Auth).

---

## 2. Configuração do Projeto no Supabase

### 2.1. Criação do Projeto
1. Acesse o [Supabase Dashboard](https://supabase.com/dashboard) e crie um novo projeto.
2. Defina uma senha forte para o banco de dados e selecione a região mais próxima dos seus usuários (ex: `sa-east-1` São Paulo).

### 2.2. Aplicação das Migrações Canônicas
Aplique **todas** as migrações presentes na pasta `supabase/migrations/` em ordem cronológica estrita, utilizando a Supabase CLI ou o **SQL Editor** do dashboard:
1. `supabase/migrations/20261009002357_initial_schema.sql` (Estrutura base, perfis, clínicas, membros, filas e RLS)
2. `supabase/migrations/20261009043005_backfill_existing_profiles.sql` (Garantia de perfis existentes)
3. `supabase/migrations/20261009043435_clinic_operations.sql` (Operações atômicas, convites, tokens de senhas e RPCs)
4. `supabase/migrations/20261009045146_explicit_private_deny_policies.sql` (Políticas de bloqueio direto do schema private e índices)

> ⚠️ **Atenção:** **NÃO** aplique o arquivo `tests/postgres-auth-stub.sql` no Supabase! Esse arquivo é exclusivo para emulação em contêineres descartáveis de teste.

### 2.3. Configuração do Supabase Auth
No menu **Authentication** do Supabase Dashboard:
1. **Providers:**
   - Mantenha **Email** habilitado.
   - Ative **"Confirm email"** (obrigatório: o MedFlow exige confirmação de e-mail para qualquer ação operacional).
   - Desative **"Enable Anonymous Sign-ins"**.
2. **Password Security:**
   - Defina o tamanho mínimo da senha como **12 caracteres**.
3. **URL Configuration:**
   - **Site URL:** `http://127.0.0.1:5173` (ou domínio HTTPS de produção).
   - **Redirect URLs:** Adicione:
     - `http://127.0.0.1:5173/login.html`
     - `http://127.0.0.1:5173/recuperar.html`
     - Adicione as URLs equivalentes de produção quando publicar.
4. **SMTP (Produção):**
   - Em produção, configure um provedor SMTP próprio (Resend, SendGrid, Amazon SES) para entrega confiável de links de confirmação e recuperação de senha.

### 2.4. Criação do Primeiro Superadministrador da Plataforma
Nenhum cadastro público permite autopromoção. Para designar o primeiro superadministrador:
1. Crie uma conta normalmente pelo frontend (`/cadastro.html`) e confirme o e-mail pelo link recebido.
2. Obtenha o UUID do usuário na tabela `auth.users`.
3. No **SQL Editor** do Supabase, execute a transação auditada:
```sql
begin;
insert into public.platform_admins(user_id) 
values ('<SEU_USER_UUID>');

insert into public.audit_logs(actor_id, action, target_id, metadata) 
values ('<SEU_USER_UUID>', 'platform.admin_granted', '<SEU_USER_UUID>', '{"reason": "Setup inicial da plataforma"}'::jsonb);
commit;
```

---

## 3. Configuração das Variáveis de Ambiente Locais

### 3.1. Backend (`backend/.env`)
Copie o modelo `.env.example` para `backend/.env`:
```sh
cp .env.example backend/.env
```
Edite com as credenciais do seu projeto Supabase:
```ini
SUPABASE_URL=https://xxxxxxxxxxxxxxxxxxxx.supabase.co
SUPABASE_PUBLISHABLE_KEY=sbp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
FRONTEND_ORIGIN=http://127.0.0.1:5173
RATE_LIMIT_DIR=/tmp/medflow-rate-limit
```
> 🔒 **Segurança:** Nunca comite nem compartilhe o arquivo `backend/.env`. Ele já está incluído no `.gitignore`.

### 3.2. Frontend (`frontend/js/config.js`)
Copie o modelo de configuração pública:
```sh
cp frontend/js/config.example.js frontend/js/config.js
```
Edite `frontend/js/config.js` com os mesmos valores públicos:
```javascript
export const config = {
  supabaseUrl: 'https://xxxxxxxxxxxxxxxxxxxx.supabase.co',
  publishableKey: 'sbp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  apiUrl: 'http://127.0.0.1:8080/api'
};
```
> ⚠️ **Nota:** `frontend/js/config.js` contém apenas chaves públicas de cliente e é ignorado pelo Git.

---

## 4. Executando Localmente

### 4.1. Modo Interativo (`scripts/dev.sh`)
Execute na raiz do projeto:
```sh
bash scripts/dev.sh
```
O script executa as seguintes etapas automaticamente:
1. Verifica a existência dos arquivos `.env` e `config.js`.
2. Inicia o frontend em `http://127.0.0.1:5173` usando o servidor HTTP Python integrado.
3. Inicia a API PHP em `http://127.0.0.1:8080` (utilizando PHP local ou automaticamente subindo o contêiner Podman caso o PHP não esteja instalado na máquina hospedeira).
4. Monitora o status das portas e exibe os links no terminal.
5. Ao pressionar `Ctrl+C`, encerra graciosamente todos os processos filhos.

### 4.2. Modo Serviço de Usuário (`systemd`)
No Linux, você pode instalar o MedFlow como um serviço de usuário do systemd que inicia automaticamente junto com a sua sessão:
```sh
bash scripts/install-local-service.sh
```

Comandos de gerenciamento do serviço:
```sh
# Verificar status do serviço
systemctl --user status medflow-dev.service

# Reiniciar o serviço
systemctl --user restart medflow-dev.service

# Visualizar logs em tempo real
journalctl --user -u medflow-dev.service -f

# Desativar e parar o serviço
systemctl --user disable --now medflow-dev.service
```

---

## 5. Publicação em Produção

### 5.1. Deploy do Frontend (Vercel)
1. Conecte o repositório Git à [Vercel](https://vercel.com).
2. Configure as seguintes opções do projeto:
   - **Framework Preset:** `Other` (HTML/JS estático)
   - **Root Directory:** `frontend`
   - **Build Command:** *(deixe em branco)*
   - **Output Directory:** *(deixe em branco)*
3. **Geração do `config.js` no Deploy:**
   Como `frontend/js/config.js` é ignorado pelo Git, crie um script ou configure um Build Command para gerá-lo a partir de variáveis de ambiente:
   ```sh
   echo "export const config = { supabaseUrl: '$PROD_SUPABASE_URL', publishableKey: '$PROD_SUPABASE_KEY', apiUrl: '$PROD_API_URL' };" > js/config.js
   ```
4. **Atualização da CSP:**
   Atualize a diretiva `connect-src` no arquivo `frontend/vercel.json` para incluir a URL HTTPS final da sua API PHP.

### 5.2. Deploy do Backend (PHP 8.3 + Nginx)
1. Instale PHP 8.3-FPM e Nginx no servidor de produção.
2. Aponte o **Document Root** exclusivamente para a pasta `backend/public`.
3. Configure o bloco do Nginx encaminhando todas as rotas para o `index.php`:
```nginx
server {
    listen 443 ssl http2;
    server_name api.medflow.seudominio.com;

    ssl_certificate /etc/letsencrypt/live/api.medflow.seudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.medflow.seudominio.com/privkey.pem;

    root /var/www/medflow/backend/public;
    index index.php;

    client_max_body_size 16k;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param FRONTEND_ORIGIN "https://app.medflow.seudominio.com";
        fastcgi_param SUPABASE_URL "https://xxxxxxxxxxxxxxxxxxxx.supabase.co";
        fastcgi_param SUPABASE_PUBLISHABLE_KEY "sbp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx";
        fastcgi_param RATE_LIMIT_DIR "/var/run/medflow-rate-limit";
    }
}
```
4. Garanta permissão de escrita para o usuário `www-data` no diretório de rate limit:
```sh
mkdir -p /var/run/medflow-rate-limit
chown -R www-data:www-data /var/run/medflow-rate-limit
```

---

## 6. Runbook Operacional & Manutenção

### 6.1. Monitoramento de Logs
- **Logs da API Local:** `backend/var/api.log`
- **Logs do Frontend Local:** `backend/var/frontend.log`
- **Identificação de Erros:** Todas as respostas de erro incluem `request_id`. Para rastrear um chamado, busque o ID correspondente nos logs do sistema:
```sh
grep "7b8e3a201c9f4d1e" backend/var/api.log
```

### 6.2. Limpeza de Rate Limit
Em caso de bloqueio temporário durante testes ou manutenção:
```sh
rm -rf /tmp/medflow-rate-limit/*
```
No ambiente de produção:
```sh
rm -rf /var/run/medflow-rate-limit/*
```
