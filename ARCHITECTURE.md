# ARCHITECTURE.md — Como funciona e o que foi reaproveitado

## Visão geral

```
Finder (ESPAÇO)
   │
   ▼
Quick Look  ──►  PreviewExtension.appex  (com.apple.quicklook.preview)
                      │
                      ▼
               PreviewViewController : NSViewController, QLPreviewingController
                      │  preparePreviewOfFile(at:)
                      ▼
               ThumbnailCore.extractImage(from: url)  ──►  NSImage
                      │                                       │
                      │                                       ▼
                      │                                 NSImageView (.scaleProportionallyUpOrDown)
                      ▼
        ┌─────────────┴───────────────┬───────────────────────────┐
        ▼                             ▼                           ▼
   .3mf  (ZIP/OPC)            .gcode (texto)             .bgcode ("GCDE" binário)
   MiniZip + Compression      base64 nos comentários     parser de blocos
        │                             │                           │
        └─────────────► PNG/JPG/QOI ◄─┴───────────────────────────┘
                              │
                              ▼
                    QOIDecoder (se "qoif")  →  CGImage  →  NSImage
```

O mesmo `ThumbnailCore` é compilado **tanto no appex quanto no app host**, para
que o app possa exibir um preview de teste sem precisar instalar a extensão.

## Módulos do `ThumbnailCore` (Swift puro)

| Arquivo | Responsabilidade | Derivado de (ThumbHost3mf) |
|---|---|---|
| `ThumbnailExtractor.swift` | Despacha por extensão e devolve `NSImage` | `ThumbnailProvider.m`, `Thumbnail3MF.m`, `ThumbnailGCode.m` |
| `MiniZip.swift` | Leitor mínimo de ZIP (EOCD, ZIP64, central dir, inflate via `Compression`) | `Unzip3MF.m` (minizip) |
| `GCode.swift` | Acha e decodifica thumbnails base64 nos comentários do `.gcode` | `ThumbnailGCode.m` |
| `BinaryGCode.swift` | Percorre blocos do container "GCDE" e extrai o bloco de thumbnail | `ThumbnailBinaryGCode.m` |
| `QOIDecoder.swift` | Decodifica imagens QOI (`qoif`) para `CGImage` | `QOIFImageFromData.m` (port do qoi.h, MIT) |

## O que foi reaproveitado (e como)

A extração é uma **reimplementação clean-room em Swift** a partir do
*comportamento* do ThumbHost3mf (Apache-2.0). Em particular:

- **3MF** — abrir o `.3mf` como ZIP e procurar a imagem em `Metadata/…`. O
  original lia `Metadata/thumbnail.png|jpg` e `Metadata/plate_1.png|jpg`. Aqui a
  ordem de prioridade é: `thumbnail.png` → `plate_1.png` → `plate_1_small.png`
  → `top_1.png` → primeiro `*.png` em `Metadata/`.
- **gcode** — localizar o trecho entre `; thumbnail begin` e `; thumbnail end`,
  juntar as linhas, remover o `; ` de prefixo e decodificar base64. Pode haver
  vários tamanhos; escolhemos o de maior área.
- **bgcode** — validar magic `GCDE` + versão 1, percorrer blocos lendo
  `blockType`, `compressionType`, tamanhos e (se houver) checksum; o bloco
  `blockType == 5` é a imagem (PNG/JPG/QOI).
- **QOI** — porte direto do decoder de referência `qoi.h` (MIT) para Swift.

## MiniZip — detalhes

Para um `.3mf` (OPC = ZIP), o `MiniZip`:

1. Faz `mmap`/lê o arquivo e localiza o **End Of Central Directory (EOCD)**
   buscando a assinatura `0x06054b50` a partir do fim.
2. Se presente, segue o **ZIP64 EOCD locator** (`0x07064b50`) e o **ZIP64 EOCD**
   (`0x06064b50`) para offsets/contagens de 64 bits.
3. Itera as entradas do **central directory** (`0x02014b50`), casando o nome do
   arquivo desejado (case-insensitive na busca por extensão `.png` no fallback).
4. Lê o **local file header** (`0x04034b50`) da entrada e extrai os dados:
   - método **0 (stored)** → cópia direta;
   - método **8 (deflate)** → inflate via `Compression` (`COMPRESSION_ZLIB` em
     modo raw/`-MAX_WBITS`).

Só precisamos de uma entrada pequena (a imagem), então não há streaming
complexo: lê-se o necessário e descomprime em memória.

## Por que não renderizar a malha 3D (v1)

O objetivo do v1 é paridade de experiência com a miniatura embutida: o slicer já
gerou uma boa imagem do plate. Renderizar a malha exigiria parser de
`3D/3dmodel.model` (XML), triangulação e um renderizador — escopo do v2.
