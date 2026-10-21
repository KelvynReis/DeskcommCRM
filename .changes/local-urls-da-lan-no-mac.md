---
impacto: nada_mudou
secao: corrigido
titulo: O ambiente local num Mac sobe conectado ao banco
---
No macOS, o `.env.local` do ambiente local passa a usar o endereço da máquina
na rede — o mesmo critério que já valia na VM Linux — em vez de `127.0.0.1`.
Dentro do contêiner, `127.0.0.1` é o próprio contêiner: o worker não alcançava
o PostgreSQL e ficava reiniciando, e o app registrava falha ao ler do banco.
Quem já tem `.env.local` recebe o endereço corrigido na próxima execução de
`pnpm local:up`, sem regenerar chaves, portas nem a sessão de WhatsApp pareada.
A instalação numa VPS não muda: não há nada a fazer na atualização.
