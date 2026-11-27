import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

import { expect, it } from "vitest";

const container = process.env.TEST_DB_CONTAINER;
if (!container) throw new Error("Rode via pnpm test:db em Postgres descartável");

it("TLS completo é o default no baseline e reaplicar a migration preserva configurações explícitas", () => {
  const migration = readFileSync("supabase/migrations/20261126211515_9467_external_db_tls_verificado_por_padrao.sql", "utf8");
  const sql = `
    begin;
    select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'external_db_connections' and column_name = 'ssl_mode';
    insert into public.organizations (id, slug, legal_name, display_name)
      values ('13000000-0000-4000-8000-000000000013', 'kt013-tls', 'Teste TLS', 'Teste TLS');
    insert into public.external_db_connections
      (organization_id, label, host, database_name, username, password_encrypted, password_iv, password_tag, ssl_mode)
      select '13000000-0000-4000-8000-000000000013', modo, 'db.example.com', 'teste', 'leitor',
        decode('00', 'hex'), decode('00', 'hex'), decode('00', 'hex'), modo
      from unnest(array['disable','prefer','require','verify-ca','verify-full']) as modo;
    ${migration}
    ${migration}
    select string_agg(ssl_mode, ',' order by label) from public.external_db_connections
      where organization_id = '13000000-0000-4000-8000-000000000013';
    rollback;
  `;
  const resultado = execFileSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-tA"], { input: sql, encoding: "utf8" });
  expect(resultado).toContain("'verify-full'::text");
  expect(resultado).toContain("disable,prefer,require,verify-ca,verify-full");
});
