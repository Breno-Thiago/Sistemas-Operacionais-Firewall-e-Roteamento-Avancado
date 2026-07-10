# Relatório acadêmico

O arquivo `relatorio-academico.tex` contém o trabalho escrito. Ele usa as
ilustrações em `assets/images/` e gera o PDF em `paper/build/`. O comando abaixo
usa a instalação local de `latexmk` ou, se ela não existir, a imagem Docker
`texlive/texlive:latest-medium`.

```bash
cd paper
make pdf
```

As capturas reais usadas no relatório ficam em `paper/images/`:

- `dashboard-local.png`: roteiro de validação e terminal da VM;
- `opnsense-dashboard.png`: painel administrativo do firewall;
- `cockpit-local.png`: acesso local ao Cockpit no host Linux.

O LaTeX incorpora automaticamente os arquivos que estiverem presentes.

A pasta `local/` permanece ignorada pelo Git. Ela contém imagens de máquinas,
ISOs e chaves específicas do computador e não deve ser movida para `paper/`.
