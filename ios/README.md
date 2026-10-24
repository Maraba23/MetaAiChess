# Xadrez no Ouvido para iPhone

O app usa a câmera do Ray-Ban Meta pra ver o lance do seu amigo. O Claude lê o tabuleiro, o Stockfish calcula a resposta e o lance é falado no seu ouvido.

```
Câmera do óculos ─► GlassesManager ─► MoveWatcher ─► Claude (qual lance foi feito?)
                                                         │
                     fala no óculos ◄─ Stockfish ◄─ tabuleiro (app/index.html)
```

O tabuleiro, o Stockfish e o texto falado são os mesmos da versão web (`../app/index.html`). O código Swift só cuida do óculos, da câmera, da leitura com o Claude e da voz.

## O que você precisa

- Mac com **Xcode 26.4 ou mais novo**
- iPhone com **iOS 17.2 ou mais novo**
- App **Meta AI** com o óculos pareado
- Alguém pra ler o tabuleiro, de um destes dois jeitos:
  - **O servidor do Mac**, que é grátis e usa o Claude Code da sua assinatura. Veja [../mac/README.md](../mac/README.md).
  - **Uma chave da API do Claude**, que é paga. Veja a seção de custo abaixo.
- **XcodeGen**: `brew install xcodegen`

## Passo a passo

1. **Ative o Modo Desenvolvedor no Meta AI.** No iPhone, abra o Meta AI › Configurações › Informações do app. Toque 5 vezes no número da versão e ative **Modo desenvolvedor**. Com isso, apps que não estão na App Store podem se conectar ao óculos.
2. **Baixe o repositório no Mac.** Baixe o repositório inteiro, porque o projeto usa os arquivos de `../app/`.
   ```sh
   git clone https://github.com/Maraba23/MetaAiChess.git
   cd MetaAiChess/ios
   ```
3. **Gere o projeto:**
   ```sh
   xcodegen generate
   open XadrezNoOuvido.xcodeproj
   ```
4. **Configure a assinatura.** No Xcode, vá em target › Signing & Capabilities, escolha seu Team e troque o Bundle Identifier por um seu, por exemplo `com.seunome.xadreznoouvido`.
5. **Rode no iPhone.** Conecte o iPhone por cabo, selecione-o como destino e aperte ▶. Na primeira vez, autorize o desenvolvedor no iPhone em Ajustes › Geral › VPN e Gerenciamento de Dispositivo.
6. **No app:**
   1. Toque na engrenagem. Escolha **Mac (grátis)**, preencha o endereço e o código que o `board_server.py` mostrou e toque em **Testar conexão**. Se preferir pagar pela API, escolha **API do Claude** e cole a chave.
   2. Toque em **Conectar óculos**. O Meta AI abre pra você autorizar e depois volta pro app.
   3. Toque em **Ligar câmera do óculos** e permita o acesso à câmera no Meta AI.
   4. Ative **Ler lances pelo óculos**.
   5. Escolha sua cor e toque em **Começar**.

## Durante a partida

- Na vez do seu amigo, o app olha o tabuleiro a cada 3 segundos (dá pra mudar nos ajustes).
- Um lance só entra no tabuleiro quando **duas leituras seguidas concordam**. Assim, a mão do seu amigo passando por cima não conta como lance.
- Depois do lance dele, o Stockfish responde e o lance sai no seu ouvido.
- **Olhe pro tabuleiro.** A câmera fica no óculos, então o app vê o que você vê. A miniatura no topo do app mostra o que a câmera está pegando.
- **Se o app errar ou demorar,** marque o lance tocando no tabuleiro, como na versão web. Isso sempre funciona.

## Custo

Com o **servidor do Mac**, a leitura não custa nada além da sua assinatura do Claude. As chamadas só contam no seu limite de uso, veja [../mac/README.md](../mac/README.md).

Com a **API do Claude**, o app usa por padrão o modelo **Opus 5.5**. Cada leitura do tabuleiro custa em torno de **US$ 0,01**. Numa partida de 40 lances, com o app olhando a cada 3 segundos, dá cerca de **US$ 1 a 3**.

Nos ajustes você pode trocar para o **Haiku 5.5**, que custa umas 30 vezes menos e responde mais rápido, mas pode errar mais.

Para modelos que não são Haiku, o app também pede ao servidor um **modelo reserva**: se o modelo principal recusar uma leitura, outro modelo tenta automaticamente. Isso é o parâmetro `fallbacks: "default"`.

## Limitações conhecidas

- O kit da Meta ainda está em **prévia para desenvolvedores**. O app não pode ir pra App Store, só roda instalado pelo Xcode.
- Com uma conta Apple gratuita, o app instalado **expira em 7 dias**. Pra renovar, é só rodar de novo pelo Xcode.
- Os entitlements de Wi-Fi (`HotspotConfiguration`) vieram do exemplo oficial da Meta e podem exigir uma conta paga do Apple Developer. Se o Xcode reclamar, apague essas duas chaves em `Config/XadrezNoOuvido.entitlements`. A câmera pode funcionar só por Bluetooth, em qualidade menor.
- Ainda não foi testado com o óculos de verdade.
