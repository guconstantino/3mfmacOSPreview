# DECISIONS.md — Registro de decisões técnicas e log de desenvolvimento

Este documento é a fonte de verdade das decisões de projeto e um diário, em
ordem, dos passos executados. Cada decisão tem **contexto**, **decisão** e
**porquê**.

---

## 0. Objetivo do projeto

Criar uma **Quick Look Preview Extension** para macOS que, ao apertar **ESPAÇO**
no Finder sobre um arquivo `.3mf`, `.gcode` ou `.bgcode`, mostre **em tamanho
grande a imagem (thumbnail) já embutida no arquivo**.

Diferença em relação ao app de referência [ThumbHost3mf](https://github.com/DavidPhillipOster/ThumbHost3mf):
aquele registra apenas o ponto de extensão `com.apple.quicklook.thumbnail`
(o ícone/miniatura no Finder). Por isso a tecla ESPAÇO não mostra preview.
O que falta — e é o que este projeto entrega — é uma extensão no ponto
`com.apple.quicklook.preview`.

---

## 1. Projeto novo standalone (não um fork)

**Decisão:** Projeto novo e independente neste repositório, reaproveitando a
*lógica* de extração do ThumbHost3mf, não um fork dele.

**Porquê:** O ThumbHost3mf é um app AppKit Objective-C com um target de
*thumbnail*. Queremos um app enxuto, em Swift, com um target de *preview*.
Forkar traria muito código e configuração que não usaríamos. Reaproveitar só a
lógica de extração mantém o projeto pequeno e auditável.

---

## 2. Reimplementar em Swift puro (opção b), não portar o C/minizip (opção a)

**Decisão:** Reimplementar a extração em **Swift puro**, sem código C
vendorizado e **sem dependências externas** (sem SPM/CocoaPods).

**Porquê:**
- A única parte que precisa de "unzip" é o `.3mf` (que é um ZIP no formato OPC).
  Os formatos `.gcode` (texto com thumbnail PNG em base64 nos comentários) e
  `.bgcode` (binário "GCDE" com blocos; thumbnails podem ser PNG/JPG/QOI) exigem
  parsers próprios de qualquer forma — minizip não ajuda neles.
- Para o ZIP do `.3mf`, basta um **leitor mínimo de ZIP** (localiza uma entrada
  pelo nome, lê o cabeçalho local e descomprime) usando o framework
  **`Compression`** da Apple para o DEFLATE. Inclui suporte a **ZIP64** (há
  `.3mf` reais em ZIP64, conforme histórico do ThumbHost3mf v1.7).
- Resultado: projeto 100% Swift, sem etapa de build de C, sem framework
  embarcado para assinar, appex menor — exatamente o "mantenha SIMPLES" do v1.

**Alternativa considerada:** `ZIPFoundation` via SPM. Rejeitada para o v1 por
adicionar resolução de pacote em build e um binário extra a assinar dentro do
appex, sem ganho real para ler um único arquivo pequeno de um OPC.

A lógica reimplementada deriva, em clean-room, do comportamento dos fontes
Objective-C/C do ThumbHost3mf (`Thumbnail3MF`, `ThumbnailGCode`,
`ThumbnailBinaryGCode`, `Unzip3MF`, `QOIFImageFromData`). Ver `ARCHITECTURE.md`.

---

## 3. Licenciamento e atribuição (Apache-2.0)

**Decisão:** Manter `LICENSE` Apache-2.0 e um `NOTICE` creditando
**David Phillip Oster** (ThumbHost3mf). O decoder QOI credita também a
implementação de referência de Dominic Szablewski (MIT).

**Porquê:** ThumbHost3mf é Apache-2.0; reusar sua lógica exige preservar
atribuição e aviso de licença. É o correto e exigido pela seção 4 da Apache-2.0.

---

## 4. Preview view-based (`QLPreviewingController`), não data-based

**Decisão:** Usar uma `NSViewController` que adota `QLPreviewingController` e
implementa `preparePreviewOfFile(at:)`, exibindo a imagem numa `NSImageView`
com `imageScaling = .scaleProportionallyUpOrDown`. Sem storyboard (view criada
programaticamente em `loadView`).

**Porquê:** É o caminho mais direto e confiável para "só mostrar a imagem
grande" (escopo v1). Evita incertezas da API data-based (`QLPreviewReply`) e não
precisa de storyboard. Renderizar a malha 3D fica para o v2.

---

## 5. UTIs e ponto de extensão

**Decisão:**
- `NSExtensionPointIdentifier = com.apple.quicklook.preview`.
- `QLSupportedContentTypes = [com.turbozen.3mf, com.turbozen.gcode,
  com.turbozen.bgcode]`.
- Declarar esses três como **`UTImportedTypeDeclarations`** (tipos *importados*),
  mapeando as extensões `3mf`/`gcode`/`bgcode`, pois os identificadores
  `com.turbozen.*` pertencem ao autor original (TurboZen / David Oster).

**Porquê:** `.3mf`/`.gcode`/`.bgcode` não têm UTI de sistema da Apple. Reusar os
identificadores `com.turbozen.*` (os mesmos do ThumbHost3mf) mantém
compatibilidade: se o ThumbHost3mf estiver instalado, ambos falam do mesmo tipo;
se não estiver, nossa declaração *imported* serve de fallback e o Quick Look
ainda casa os arquivos pela extensão.

---

## 6. Sandbox e assinatura (Apple ID grátis / Personal Team)

**Decisão:**
- App e appex com **App Sandbox** habilitado; entitlement de leitura do arquivo
  selecionado (`com.apple.security.files.user-selected.read-only`). O Quick Look
  concede ao appex acesso de leitura ao arquivo sob preview.
- **Assinatura local com Personal Team (Apple ID grátis)**, assinatura
  automática no Xcode. **Sem notarização** (exige conta paga de US$99/ano).

**Porquê:** O usuário não tem conta paga de Apple Developer. Um Personal Team
grátis assina e roda localmente sem problemas para uso pessoal. A ausência de
notarização significa que **outros** usuários precisarão do passo único do
Gatekeeper ("Abrir Mesmo Assim") — documentado no README.

**Consequência consciente (adiada):** distribuição sem fricção (notarizada)
exigiria a conta paga. Decidimos adiar (ver seção 8).

---

## 7. Geração do projeto Xcode via XcodeGen

**Decisão:** Descrever os targets em `project.yml` (XcodeGen) e **commitar também
o `.xcodeproj` gerado**. `project.yml` é a fonte de verdade; o `.xcodeproj`
commitado permite abrir no Xcode sem instalar o XcodeGen.

**Porquê:** Escrever um `.pbxproj` à mão para app + appex (com embedding,
entitlements, Info.plists e build settings) é frágil e propenso a erro.
O XcodeGen torna isso declarativo e reprodutível. Commitar o `.xcodeproj` evita
exigir a ferramenta de quem só quer abrir e compilar.

---

## 8. Distribuição (v2 — apenas planejado, NÃO implementado agora)

**Plano:** Sem conta paga, o caminho grátis é um **Homebrew TAP próprio** com o
`.app` **não-assinado/não-notarizado**: o usuário faz `brew tap guconstantino/...`
e `brew install --cask ...`, mais o passo único do Gatekeeper.

**Trade-off registrado:** A experiência "sem fricção" (notarizada, sem aviso do
Gatekeeper) exigiria a conta paga de **US$99/ano**. Decisão consciente de
**adiar** a notarização. Não montaremos o tap no v1.

---

## 9. Escopo v1 (mantenha SIMPLES)

- Mostrar **somente** a imagem embutida, em tamanho grande, ao apertar ESPAÇO.
- **Não** renderizar a malha 3D (v2).
- Prioridade dos caminhos da imagem dentro do ZIP do `.3mf`:
  1. `Metadata/thumbnail.png` (PrusaSlicer)
  2. `Metadata/plate_1.png` (Bambu/Orca)
  3. `Metadata/plate_1_small.png`
  4. `Metadata/top_1.png`
  5. fallback: o 1º `*.png` dentro de `Metadata/`
- `.gcode`: PNG em base64 nos comentários (`; thumbnail begin` … `; thumbnail end`).
- `.bgcode`: bloco de thumbnail no container binário "GCDE" (PNG/JPG/QOI).

---

## LOG DE DESENVOLVIMENTO (ordem cronológica)

- **Passo 1.** Clonado o repo vazio `guconstantino/3mfmacOSPreview` e, para
  estudo, o `DavidPhillipOster/ThumbHost3mf`. Lidos os fontes de extração
  (`Thumbnail3MF.m`, `ThumbnailGCode.m`, `ThumbnailBinaryGCode.m`, `Unzip3MF.h`,
  `QOIFImageFromData.m`) e o `Info.plist` do thumbnail.
- **Passo 2.** Adicionados `LICENSE` (Apache-2.0), `NOTICE` (atribuição a David
  Oster + MIT do QOI), `.gitignore`.
- **Passo 3.** Criados `DECISIONS.md` (este arquivo), `README.md` e
  `ARCHITECTURE.md` com o plano. **(commit deste checkpoint)**
- **Passo 4.** Implementado o `ThumbnailCore` em Swift puro (`QOIDecoder`,
  `MiniZip`, `GCode`, `BinaryGCode`, `ThumbnailExtractor`). Validado com `swiftc`
  contra fixtures gerados (`.3mf` em Deflate e `.gcode` com base64): ambos
  extraíram o PNG embutido corretamente. **(commit)**
- **Passo 5.** Criada a extensão `PreviewExtension` (`QLPreviewingController` +
  `preparePreviewOfFile(at:)` + `NSImageView` `.scaleProportionallyUpOrDown`),
  o app host SwiftUI `MF3Preview` (com um "Open File…" de teste), os
  `Info.plist`/entitlements e o `project.yml`. **(commit)**
- **Passo 6.** `xcodegen generate` + `xcodebuild` (Debug, sem assinatura):
  **BUILD SUCCEEDED**. O `.appex` é embarcado em `Contents/PlugIns/` e validado;
  os `Info.plist` processados resolvem o principal class
  (`PreviewExtension.PreviewViewController`) e os `QLSupportedContentTypes`.
- **Passo 7.** Build Release com **assinatura ad-hoc** (`-`) só para validação
  local; entitlements de sandbox aplicados. Instalado em
  `/Applications/MF3Preview.app` e registrado (`lsregister`/`pluginkit`).
  `pluginkit -m -p com.apple.quicklook.preview` lista a nossa extensão.
- **Passo 8.** Validação de integração headless: `mdls` mostra que um `.3mf`
  resolve para `kMDItemContentType = com.turbozen.3mf` — o mesmo UTI que a
  extensão declara, então o Quick Look roteará o preview para ela. Observação:
  `lsregister -dump` revelou que o **ThumbHost3mf já está instalado** nesta
  máquina (extensão de *thumbnail*), confirmando que os UTIs `com.turbozen.*`
  são os reais e que as duas extensões coexistem em pontos diferentes.
  **(commit)**

### Notas de validação / pendências

- A confirmação visual final (apertar **ESPAÇO** num `.3mf` real e ver a imagem)
  é uma ação de GUI e deve ser feita interativamente — não é observável de forma
  headless. Todos os pré-requisitos verificáveis por linha de comando passaram.
- O build instalado em `/Applications` foi assinado **ad-hoc** apenas para teste.
  Para uso estável, recompile no Xcode selecionando seu **Personal Team** (Apple
  ID grátis) em ambos os targets — mesmo bundle id, o LaunchServices apenas
  atualiza o registro.
- bgcode/QOI/ZIP64: a lógica é port fiel da referência, mas ainda não exercitada
  contra fixtures reais (faltam amostras). Fica como verificação futura.
