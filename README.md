# Xadrez no Ouvido

Use o Ray-Ban Meta para ouvir o melhor lance numa partida de xadrez no tabuleiro físico. O Stockfish calcula o lance e o iPhone fala no alto-falante do óculos.

> Feito pra brincar com amigos. Não use em torneio nem em partida valendo rating: isso é trapaça e dá banimento.

## Duas versões

| | Versão web (`app/`) | App de iPhone (`ios/`) |
|---|---|---|
| Como você informa o lance do adversário | Tocando no tabuleiro do celular | A câmera do óculos vê o lance sozinha |
| Instalação | Nenhuma, abre no Safari | Mac com Xcode 26.4+ |
| Custo | Grátis | Grátis com o Mac (Claude Code da sua assinatura) ou API do Claude (~US$ 1 a 3 por partida) |
| Situação | Testada no iPhone com o óculos | Escrita, ainda não testada no aparelho |

Nas duas, o óculos funciona como fone Bluetooth: tudo que o iPhone fala sai no seu ouvido.

### Versão web

1. Conecte o óculos ao iPhone.
2. Abra `app/index.html` por um servidor. Pelo arquivo direto não funciona, porque o motor roda num Web Worker. Duas formas de fazer isso:
   - Ative o GitHub Pages neste repositório e abra `https://<seu-usuario>.github.io/MetaAiChess/app/`.
   - Ou rode um servidor local: `cd app && python3 -m http.server`.
3. Escolha sua cor e a força e toque em **Começar**. Você deve ouvir "Pronto" no óculos.
4. Quando seu amigo jogar, toque na peça que ele moveu e depois na casa de destino. O melhor lance sai no seu ouvido.

Recursos:
- **Humano:** o motor joga um pouco mais fraco, pra não ficar óbvio que é uma máquina.
- **Modo discreto:** escurece a tela e esconde o lance escrito.
- **Repetir no ouvido:** fala de novo o último lance.
- **Desfazer:** volta o último lance, caso você tenha jogado outro.

### App de iPhone

Aqui você não precisa tocar no celular. O app recebe o vídeo da câmera do óculos pelo [Meta Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios) e, na vez do seu amigo, pergunta qual dos lances legais aparece na foto. Quando duas leituras seguidas concordam, o lance entra no tabuleiro e o Stockfish responde no seu ouvido.

Quem lê a foto pode ser:
- **O seu Mac (grátis).** O [servidor do Mac](mac/README.md) usa o Claude Code da sua assinatura.
- **A API do Claude (paga).** Você cola uma chave da API no app.

O passo a passo de instalação está em [ios/README.md](ios/README.md).

## Como está organizado

```
app/
  index.html      tabuleiro, regras, Stockfish e texto falado (usado pelas duas versões)
  stockfish.js    Stockfish 10 compilado para JavaScript (asm.js)
  chess.min.js    chess.js 0.10.3, regras e lances legais
ios/
  project.yml     projeto Xcode (gerado com XcodeGen)
  XadrezNoOuvido/ código Swift: óculos, câmera, leitura do tabuleiro e voz
mac/
  board_server.py servidor que lê o tabuleiro com o Claude Code do Mac
```

## Licenças

Este projeto é distribuído sob a **GPL-3.0** (veja [LICENSE](LICENSE)), porque inclui o Stockfish.

- [Stockfish](https://github.com/official-stockfish/Stockfish), compilado para JavaScript por [niklasf/stockfish.js](https://github.com/niklasf/stockfish.js): GPL-3.0 ([app/licenses/stockfish-COPYING.txt](app/licenses/stockfish-COPYING.txt))
- [chess.js](https://github.com/jhlywa/chess.js): BSD-2-Clause ([app/licenses/chess.js-LICENSE.txt](app/licenses/chess.js-LICENSE.txt))
- O Meta Wearables Device Access Toolkit não vem neste repositório. O Xcode baixa o pacote, que tem a licença própria da Meta.
