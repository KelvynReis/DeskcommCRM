---
impacto: nada_mudou
secao: corrigido
titulo: O stack local sobe em computador ARM64 (Mac com Apple Silicon)
---
A instalação local (`./ubuntu-local-installer.sh` e `pnpm local:up`) escolhe
sozinha a imagem do WhatsApp para a arquitetura da máquina. Antes, num
computador ARM64, a subida parava em "no matching manifest for linux/arm64/v8"
antes de qualquer serviço ficar de pé, porque a imagem usada só era publicada
para x86_64. Quem já tem `.env.local` recebe a referência certa na próxima
execução de `pnpm local:up`, sem regenerar chaves, portas nem a sessão de
WhatsApp pareada. A instalação numa VPS não muda: não há nada a fazer na
atualização.
