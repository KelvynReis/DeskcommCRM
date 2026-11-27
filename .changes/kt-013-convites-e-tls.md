---
impacto: exige_acao
secao: corrigido
titulo: Convites falham com segurança e novas conexões verificam o servidor
---

Falhas ao consultar a revogação de um convite impedem o aceite e orientam uma nova tentativa. Convites legados continuam aceitos quando a consulta termina com sucesso sem encontrar uma linha.

Novas conexões de banco externo verificam certificado e host por padrão. Cadastros existentes preservam o modo escolhido; modos sem verificação ou sem TLS exibem um aviso no formulário. No MySQL, verificar certificado e host exige o hostname do certificado, em vez de IP literal. Um cadastro existente em verify-full com IP precisará desse ajuste. Certificados privados exigem confiança no runtime ou escolha explícita de compatibilidade.

Destino: núcleo — proteção de autorização e do conector existente, sem dependência de extensão.

## Requer atenção

Se uma conexão MySQL já usa `verify-full` com IP literal, edite Dados externos e informe o hostname presente no certificado antes de usá-la novamente. Para novas conexões com CA privada, configure a confiança no runtime ou escolha explicitamente um modo de compatibilidade, ciente do aviso de segurança. Os demais cadastros mantêm seu modo atual.
