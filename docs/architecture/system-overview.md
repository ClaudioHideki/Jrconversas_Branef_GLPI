<!-- jrc-operational-init:v1 -->
# Visão do sistema — JRC Conversas Branef — GLPI

## Propósito e fronteira

Produto derivado do LAB2 com atendimento e extensão GLPI/intake específica da Branef.

**Stack:** Ruby/Rails, Vue, PostgreSQL, Redis/Sidekiq, GLPI e Broker.

**Natureza:** Brownfield. **Tipo de raiz:** application.

## Fluxo lógico

Canal → atendimento da empresa → classificação/intake autorizado → integração GLPI; o núcleo LAB2 permanece separado da extensão específica.

Esta é uma visão de responsabilidades baseada em fontes locais, não um levantamento dos hosts efetivos. Versão em execução, topologia física, portas produtivas e imagem implantada não foram verificadas neste bootstrap.

## Controle de versões

- Data da leitura: 2026-11-13.
- Branch local: `codex/branef-servicedesk-visual-20261113`.
- HEAD de origem antes da documentação: `1baef62a4bc48c83d132449af8abb6ba5bc87f08`.
- Origem Git: `https://github.com/ClaudioHideki/Jrconversas_Branef_GLPI.git`.
- [Contexto e versões declaradas](repository-context-init-v1.json).

Esse HEAD é a base documental observada e não será atualizado para fingir versão produtiva. A revisão documental, o software, o commit, a imagem publicada e a imagem em execução são informações distintas.

## Fontes atuais

- [AGENTS.md](<../../AGENTS.md>)
- [README.md](<../../README.md>)
- [package.json](<../../package.json>)
- [Gemfile](<../../Gemfile>)
- [db/schema.rb](<../../db/schema.rb>)
- [docs/superpowers/specs/2026-11-13-branef-cockpit-servicedesk-visual-design.md](<../../docs/superpowers/specs/2026-11-13-branef-cockpit-servicedesk-visual-design.md>)

## Pendências conhecidas

- Preservar o trabalho visual em andamento e as regras GLPI específicas.
- Validar classificação, roteamento e entrega antes de ativar integrações ou números.

O padrão de arquitetura JRC completo usa prancha integrada, fluxos, runtimes e quadro de versões com fontes; a referência visual aprovada é a arquitetura R03/R04 de 13/11/2026. Este índice não substitui aquelas pranchas nem os planos existentes.
