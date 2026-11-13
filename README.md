# Cidade Blocolândia

Site da @cidadeblocolandia: quem segue vira morador, ganha casa no mapa 3D e carteirinha.

- `index.html` — o site inteiro (página inicial, carteirinha, story e mapa 3D)
- `supabase/supabase.sql` — banco de dados (rodar no SQL Editor)
- `supabase/functions/pegar-casa/index.ts` — função que confere o captcha e cria o morador
- `supabase/supabase-captcha.sql` — trava: cadastro só pela função
- `supabase/supabase-enquetes.sql` — enquetes (votação entre opções); criar com `select criar_enquete(...)`
