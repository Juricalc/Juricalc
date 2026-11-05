# JURICALC — versão 3 (base técnica)

Sistema de gestão de cálculos jurídicos, projetado para acesso via navegador de computadores diferentes.

## Arquivos
- `schema.sql`: tabelas, permissões por linha (RLS), histórico e funções de gestão.
- `index.html`: interface inicial com autenticação Supabase, painel de cálculos e distribuição.

## Configuração
1. Crie um projeto em https://supabase.com e execute `schema.sql` no SQL Editor.
2. No `index.html`, substitua `COLOQUE_A_URL_SUPABASE` e `COLOQUE_A_CHAVE_PUBLICA_ANON` pelos valores públicos do projeto. **Nunca coloque a service_role key no navegador.**
3. Crie o primeiro usuário pelo painel de autenticação do Supabase. Para torná-lo administrador Felipe, execute no SQL Editor, substituindo o e-mail conforme necessário:
   `update public.profiles set display_name='Felipe', role='admin', can_assign=true where id=(select id from auth.users where email='brazfelipe061@gmail.com');`
4. Configure SMTP e modelos de convite/recuperação no Supabase Auth antes de enviar convites. Convites administrativos devem ser enviados por uma função de servidor com autenticação e autorização, nunca usando a chave privilegiada no navegador.
5. Hospede os arquivos por HTTPS. Configure os URLs permitidos no painel de autenticação do Supabase.

## Observações
Esta é uma base técnica inicial, não um sistema auditado ou pronto para dados jurídicos reais. Antes da produção, implementar e testar fluxos de convite e recuperação, e-mails de notificação, backups, proteção de dados pessoais, auditoria imutável e testes completos de autorização. O acesso deve ocorrer por HTTPS.
