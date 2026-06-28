# 3MF Preview — Quick Look para `.3mf`, `.gcode` e `.bgcode`

Extensão de **Quick Look Preview** para macOS. Ao apertar **ESPAÇO** no Finder
sobre um arquivo `.3mf`, `.gcode` ou `.bgcode`, mostra **em tamanho grande a
imagem (thumbnail) já embutida no arquivo** pelo slicer (PrusaSlicer, Bambu
Studio, Orca, etc.).

> É a peça que falta no [ThumbHost3mf](https://github.com/DavidPhillipOster/ThumbHost3mf):
> aquele projeto registra a **miniatura** (ícone no Finder, ponto de extensão
> `com.apple.quicklook.thumbnail`); este registra o **preview** (a janela grande
> do ESPAÇO, ponto `com.apple.quicklook.preview`). Os dois podem coexistir.

Escopo da v1: **apenas exibir a imagem embutida**. Renderização da malha 3D fica
para a v2 (ver `DECISIONS.md`).

---

## Pré-requisitos

- macOS (Apple Silicon ou Intel) com **Xcode** instalado.
- Uma **Apple ID** (a conta **grátis** / *Personal Team* basta — não é preciso a
  conta paga de Apple Developer).
- _(Opcional, só para regenerar o projeto)_ [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  `brew install xcodegen`. O `.xcodeproj` já vem commitado, então para apenas
  compilar você **não** precisa do XcodeGen.

---

## Como compilar no Xcode

1. Abra `MF3Preview.xcodeproj` no Xcode.
2. Selecione o target **MF3Preview** → aba **Signing & Capabilities**:
   - Marque **Automatically manage signing**.
   - Em **Team**, selecione seu **Personal Team** (seu nome / Apple ID grátis).
   - Faça o mesmo no target **PreviewExtension** (use o mesmo Team).
   > Com Personal Team o `Bundle Identifier` precisa ser único na sua conta.
   > Se o Xcode reclamar, troque o prefixo `com.guconstantino` por algo seu em
   > ambos os targets (mantendo o appex como `…<app>.PreviewExtension`).
3. Selecione o scheme **MF3Preview** e **Product → Build** (⌘B).

Pela linha de comando (debug):

```bash
xcodebuild -project MF3Preview.xcodeproj -scheme MF3Preview \
  -configuration Debug -destination 'platform=macOS' build
```

---

## Como instalar (OBRIGATÓRIO ir para `/Applications`)

O macOS só ativa a extensão de Quick Look se o app hospedeiro estiver em
**`/Applications`** (ou uma subpasta dela) — **não** em `~/Applications`,
Downloads ou Desktop.

1. No Xcode: **Product → Archive** (ou copie o `.app` da pasta de build).
2. Copie **`MF3Preview.app` para `/Applications`**.
3. **Rode o app uma vez** (duplo clique). Isso registra a extensão no sistema.
   Pode fechar em seguida — ele só precisa rodar uma vez para registrar.
4. _(Opcional)_ Confirme em **Ajustes do Sistema → Geral → Itens de início e
   Extensões → Quick Look** que **3MF Preview** aparece e está ativado.

### Passo do Gatekeeper (para outros usuários / máquinas)

Como o app **não é notarizado** (a notarização exige a conta paga), ao abrir em
outra máquina o macOS pode bloquear com "não foi possível verificar o
desenvolvedor". Para liberar (passo único):

> **Ajustes do Sistema → Privacidade e Segurança** → role até a mensagem sobre o
> app bloqueado → **"Abrir Mesmo Assim"** → confirme.

Na sua própria máquina (a que assinou com seu Personal Team) isso normalmente
nem aparece.

---

## Como testar

1. Baixe **localmente** um `.3mf` real **que tenha thumbnail** (a maioria dos
   exportados por PrusaSlicer/Bambu/Orca a partir de ~2021 tem).
   > ⚠️ Garanta que o arquivo está **baixado de verdade** — não um item de
   > **0 KB** ainda na nuvem do iCloud. Itens não baixados não têm conteúdo para
   > o Quick Look ler.
2. No Finder, selecione o arquivo e aperte **ESPAÇO**. Deve aparecer a imagem
   embutida em tamanho grande.

### Se o preview não aparecer

Reinicie o cache do Quick Look e o Finder:

```bash
qlmanage -r && qlmanage -r cache && killall Finder
```

Você também pode forçar um preview por linha de comando para depurar:

```bash
qlmanage -p /caminho/para/arquivo.3mf
```

E listar as extensões de Quick Look que o sistema enxerga:

```bash
pluginkit -mAvvv -p com.apple.quicklook.preview | grep -i mf3
```

Checklist de problemas comuns:
- O `.app` **não** está em `/Applications` → mova e rode-o de novo.
- O app nunca foi aberto após instalar → abra uma vez.
- O `.3mf` não tem thumbnail embutido, ou é um item de iCloud não baixado.
- Cache velho → rode os comandos `qlmanage -r …` acima.

---

## Tipos suportados

| Extensão | Origem do thumbnail | Formatos de imagem |
|---|---|---|
| `.3mf`   | imagem em `Metadata/…` dentro do ZIP/OPC | PNG (JPG/QOI também aceitos) |
| `.gcode` | PNG em base64 nos comentários | PNG (JPG/QOI também aceitos) |
| `.bgcode`| bloco de thumbnail no container "GCDE" | PNG / JPG / QOI |

Prioridade dos caminhos no `.3mf`: `Metadata/thumbnail.png` →
`Metadata/plate_1.png` → `Metadata/plate_1_small.png` → `Metadata/top_1.png` →
primeiro `*.png` em `Metadata/`.

---

## Distribuição (planejada para a v2 — ainda não implementada)

Sem conta paga de Apple Developer, o caminho grátis é um **Homebrew Tap próprio**
com o `.app` não-notarizado:

```bash
# (planejado, ainda não existe)
brew tap guconstantino/3mfpreview
brew install --cask 3mf-preview
```

…mais o **passo único do Gatekeeper** acima. A experiência sem fricção
(notarizada) exigiria a conta paga de US$99/ano — decisão consciente de adiar,
registrada em `DECISIONS.md` (seção 8).

---

## Licença e créditos

[Apache-2.0](LICENSE). A lógica de extração de thumbnails é uma reimplementação
em Swift derivada do [ThumbHost3mf](https://github.com/DavidPhillipOster/ThumbHost3mf)
de **David Phillip Oster** (Apache-2.0). O decoder QOI é um port do `qoi.h` de
Dominic Szablewski (MIT). Ver `NOTICE` e `ARCHITECTURE.md`.
