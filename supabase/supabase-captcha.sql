-- Cidade Blocolândia — trava de captcha
-- Rode SÓ DEPOIS de publicar a função "pegar-casa" e subir o site novo.
-- A partir daqui, ninguém cria morador direto pelo navegador: só pela função, que confere o captcha.

revoke execute on function public.pegar_casa(text) from anon, authenticated;
grant  execute on function public.pegar_casa(text) to service_role;
