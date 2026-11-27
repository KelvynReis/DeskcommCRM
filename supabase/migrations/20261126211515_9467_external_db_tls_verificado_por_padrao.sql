-- manifest: Verificação TLS completa por padrão em novas conexões externas; preserva modos já cadastrados.
alter table public.external_db_connections
  alter column ssl_mode set default 'verify-full';

comment on column public.external_db_connections.ssl_mode is
  'Modo TLS do banco externo. Default verify-full: verifica certificado e host; modos sem verificação exigem escolha explícita de compatibilidade.';
