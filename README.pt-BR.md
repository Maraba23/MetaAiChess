# Xadrez no Ouvido

**O melhor lance falado no seu ouvido enquanto você joga num tabuleiro de verdade.** O Stockfish calcula o lance e o celular fala pelo óculos Ray-Ban Meta ou por qualquer fone Bluetooth.

🇺🇸 [Read in English](README.md)

> Feito pra brincar com amigos. Usar em torneio, em partida valendo rating ou online é trapaça e dá banimento.

<!-- Coloque aqui um print ou GIF do app, por exemplo ![App no iPhone](docs/screenshot.png) -->

## Teste em 2 minutos

1. Conecte o fone ou o Ray-Ban Meta ao celular.
2. Abra **https://maraba23.github.io/MetaAiChess/app/** no navegador do celular (no iPhone, use o Safari).
3. Escolha sua cor e a força e toque em **Começar e testar o áudio**. Você deve ouvir "Pronto" no ouvido.
4. Quando seu amigo jogar, toque na peça que ele moveu e depois na casa de destino. O melhor lance sai no seu ouvido e aparece no tabuleiro.

Essa é a versão web inteira. Ela é grátis, não precisa instalar nada e foi testada num iPhone com o Ray-Ban Meta.

## Duas formas de usar

| | Versão web (`app/`) | App de iPhone (`ios/`) |
|---|---|---|
| Como o lance do adversário entra | Você toca no celular | A câmera do óculos vê |
| Saída de áudio | Qualquer fone Bluetooth ou óculos | Ray-Ban Meta |
| O que você precisa | Um navegador | Mac com Xcode, iPhone, Ray-Ban Meta e o Claude pra ler o tabuleiro |
| Custo | Grátis | Grátis com a sua assinatura do Claude (pelo Mac), ou ~US$ 1 a 3 por partida com a API do Claude |
| Situação | ✅ Testada no iPhone com o Ray-Ban Meta | ⚠️ Escrito, mas **nunca compilado**: espere ajustes no build |

## Como funciona

```
                  ┌──────────────── iPhone ─────────────────┐
 Ray-Ban Meta ──► │ imagens da câmera ─► MoveWatcher        │
  (câmera)        │                    │ "qual lance legal  │
                  │                    │  aparece aqui?"    │
                  │                    ▼                    │
                  │   ┌── Mac: board_server.py ─► claude -p │  (grátis, sua assinatura)
                  │   └── ou API do Claude                  │  (paga, chave da API)
                  │                    │ "e7e5"             │
                  │                    ▼                    │
                  │ app/index.html: tabuleiro + Stockfish 10│
                  │                    │ "Cavalo de gê 1    │
                  │                    ▼  para éfe 3"       │
 Ray-Ban Meta ◄── │ voz                                     │
  (alto-falante)  └─────────────────────────────────────────┘
```

- **O tabuleiro, as regras e o motor são o mesmo código em todo lugar.** O `app/index.html` roda o Stockfish 10, compilado para JavaScript, num Web Worker, e usa o chess.js para os lances legais. O app de iPhone carrega essa mesma página.
- **Ler o tabuleiro é escolher um lance de uma lista.** O leitor não precisa descobrir a posição inteira. Ele recebe a foto, a posição esperada e a lista de lances legais, e responde com um desses lances ou com "nenhum". Isso deixa a leitura bem mais confiável.
- **Um lance só entra quando duas leituras seguidas concordam.** Assim, a mão do adversário passando por cima do tabuleiro não conta como lance.
- **Tocar no tabuleiro sempre funciona.** Se a câmera errar, você marca o lance na mão e continua jogando.

## Como rodar cada parte

### Versão web

O `app/index.html` precisa ser aberto por um servidor. Abrir o arquivo direto não funciona, porque o navegador bloqueia o Web Worker em `file://`.

```sh
cd app && python3 -m http.server 8000
# abra http://<ip-do-computador>:8000 no celular
```

Pra hospedar a sua própria cópia, faça um fork do repositório e ative **Settings › Pages › Branch: main**.

### App de iPhone

Você precisa de:
- Mac com **Xcode 26.4+**
- iPhone com **iOS 17.2+**
- Ray-Ban Meta pareado no app **Meta AI**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Passos:
1. No Meta AI, ative o **Modo Desenvolvedor**: Configurações › Informações do app, toque 5 vezes no número da versão.
2. Gere e abra o projeto:
   ```sh
   brew install xcodegen
   cd ios && xcodegen generate && open XadrezNoOuvido.xcodeproj
   ```
3. No Xcode, escolha seu Team e um Bundle Identifier único, e rode no iPhone.
4. No app, toque em **Conectar óculos**, depois em **Ligar câmera do óculos**, e ative **Ler lances pelo óculos**.

O app usa o [Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios) 1.0.1 da Meta. Ele ainda está em prévia para desenvolvedores, e apps que usam esse kit não podem ir pra App Store. Guia completo: [ios/README.md](ios/README.md).

### Leitor de tabuleiro no Mac (grátis)

```sh
python3 mac/board_server.py   # mostra um endereço e um código
```

Digite o endereço e o código no app de iPhone (engrenagem › **Mac (grátis)**).

O servidor roda o `claude` oficial por linha de comando, **sem nenhuma ferramenta**. Ele só olha a imagem e responde. Isso usa a **sua** assinatura do Claude, e cada leitura conta no seu limite de uso. Você precisa do Claude Code instalado e com login feito, e do Python 3 (só a biblioteca padrão).

Fora do Wi-Fi de casa, conecte o celular e o Mac pelo [Tailscale](https://tailscale.com). Guia completo: [mac/README.md](mac/README.md).

## O que está testado e o que não está

| Parte | Situação |
|---|---|
| Versão web, Stockfish e voz pelo Ray-Ban Meta no iPhone | ✅ Testado |
| `claude -p` lendo uma imagem de tabuleiro (`e7e5 HIGH` / `NONE`, ~3 s) | ✅ Testado no Windows, com tabuleiros **desenhados**, não fotos reais |
| App de iPhone (kit da Meta, câmera, ponte com a página) | ⚠️ Nunca compilado; escrito no Windows a partir dos exemplos da Meta |
| Leitura com fotos reais do óculos (ângulo, sombra) | ❓ Só testando pra saber |
| iPhone falar com o Mac enquanto a câmera do óculos está ligada | ❓ Não se sabe ainda: a câmera pode ocupar o Wi-Fi do celular (o Tailscale deve contornar) |

## Problemas comuns

- **A versão web não toca som.** Tire o iPhone do modo silencioso e toque em **Começar** de novo: o iOS só deixa falar depois de um toque na tela. Se abriu o link dentro de outro app, tente pelo Safari.
- **A voz sai em inglês ou robótica.** No iPhone, vá em Ajustes › Acessibilidade › Conteúdo Falado › Vozes e baixe uma voz em português (Brasil).
- **"Pensando…" não termina.** O motor não carregou. Abra a página por um servidor, não pelo arquivo.
- **O app de iPhone não encontra o óculos.** Ative o Modo Desenvolvedor no Meta AI (veja acima). Só um app em desenvolvimento pode ficar conectado por vez.
- **"Mac não encontrado".** O celular e o Mac precisam estar na mesma rede, ou os dois no Tailscale. Confira também se o `board_server.py` está rodando.
- **O servidor do Mac avisa que o limite acabou.** O limite de uso da sua assinatura do Claude esgotou. Espere ele renovar ou marque os lances na mão.

## Ideias para contribuir

- **Ler o tabuleiro no próprio iPhone, sem IA:** comparar quais casas mudaram, por exemplo com o alinhamento de imagens do Vision da Apple, depois de calibrar os 4 cantos do tabuleiro uma vez.
- **Usar um modelo de visão local** (Ollama) no Mac, como mais uma opção grátis.
- **Manter um processo do `claude` sempre aberto**, com entrada stream-json, pra cada leitura não pagar o tempo de inicialização.
- **Adicionar voz e frases em inglês.** Hoje os lances são falados só em português.
- **Criar um modo para o Meta Ray-Ban Display**, mostrando o lance na lente.

## Organização do projeto

```
app/
  index.html        tabuleiro, regras, Stockfish e frases faladas (usado por tudo)
  stockfish.js      Stockfish 10, versão asm.js
  chess.min.js      chess.js 0.10.3
  licenses/         licenças de terceiros
ios/
  project.yml       definição do projeto para o XcodeGen
  Config/           Info.plist, entitlements
  XadrezNoOuvido/   app SwiftUI: óculos, câmera, leitores de lance, voz
mac/
  board_server.py   servidor HTTP que lê os lances com o Claude Code
```

## Licença

**GPL-3.0** (veja [LICENSE](LICENSE)), porque o projeto inclui o Stockfish.

- [Stockfish](https://github.com/official-stockfish/Stockfish), versão JS de [niklasf/stockfish.js](https://github.com/niklasf/stockfish.js): GPL-3.0
- [chess.js](https://github.com/jhlywa/chess.js): BSD-2-Clause
- O Meta Wearables Device Access Toolkit não vem neste repositório. O Xcode baixa o pacote, que tem a licença própria da Meta.
