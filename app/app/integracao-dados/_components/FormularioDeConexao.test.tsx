import { render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";

import type { ConexaoExternaRow } from "@/hooks/external-db/useConexoesExternas";

import { FormularioDeConexao } from "./FormularioDeConexao";

vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));
vi.mock("@/hooks/i18n/useT", () => ({ useT: () => (texto: string) => texto }));

const LEGADA: ConexaoExternaRow = {
  id: "c1", organization_id: "o1", label: "Legada", host: "db.example.com", port: 5432,
  database_name: "teste", username: "leitor", ssl_mode: "require", enabled: true,
  max_rows: 200, max_filters: 20, max_response_bytes: 30000, customer_key_column: null,
  customer_key_kind: null, last_tested_at: null, last_test_ok: null, last_test_error: null,
  source_mode: "list", sources_count: 0, db_type: "postgres", last_test_aviso: null,
  created_by: null, created_at: "2026-11-26", updated_at: "2026-11-26",
};

function abrir(conexao?: ConexaoExternaRow) {
  render(<QueryClientProvider client={new QueryClient()}><FormularioDeConexao open onOpenChange={vi.fn()} conexao={conexao} /></QueryClientProvider>);
}

describe("segurança TLS do formulário", () => {
  it("nova conexão seleciona verificação de certificado e host", () => {
    abrir();
    expect(screen.getByLabelText("Segurança da conexão (TLS)").textContent).toBe("Verificar certificado e host");
    expect(screen.queryByText(/Use apenas por compatibilidade/)).toBeNull();
  });

  it.each(["require", "prefer"])("preserva %s explícito ao editar e avisa sobre identidade", (ssl_mode) => {
    abrir({ ...LEGADA, ssl_mode });
    expect(screen.getByLabelText("Segurança da conexão (TLS)").textContent).toBe(ssl_mode === "require" ? "Obrigatório (sem verificar certificado)" : "Preferir TLS");
    expect(screen.getByText(/não verifica o certificado nem a identidade/)).toBeTruthy();
  });

  it("avisa quando o TLS está desligado", () => {
    abrir({ ...LEGADA, ssl_mode: "disable" });
    expect(screen.getByText(/envia os dados sem TLS/)).toBeTruthy();
  });

  it("avisa que verify-ca no MySQL não confere o host", () => {
    abrir({ ...LEGADA, ssl_mode: "verify-ca", db_type: "mysql", port: 3306 });
    expect(screen.getByText(/não confirma o host/)).toBeTruthy();
  });
});
