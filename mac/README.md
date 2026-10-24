# Servidor do Mac (leitura grátis do tabuleiro)

Durante a partida, o app de iPhone manda as fotos do óculos pra cá. O servidor pergunta ao **Claude Code** do seu Mac qual lance o seu amigo fez e devolve a resposta pro iPhone. Isso usa a **sua assinatura do Claude**, sem pagar API.

```
iPhone ──foto + lances legais──► board_server.py ──► claude -p (sua assinatura)
       ◄────── "e7e5" ─────────┘
```

## Requisitos

- **Claude Code** instalado no Mac e com login feito (rode `claude` uma vez pra entrar).
- **Python 3.** O que vem no macOS já serve, e o servidor não precisa de nenhuma biblioteca extra.
- O iPhone precisa conseguir acessar o Mac pela rede (veja a seção "Rede" abaixo).

## Como usar

```sh
cd mac
python3 board_server.py
```

O servidor mostra algo assim:

```
  Xadrez no Ouvido · servidor do Mac
  No iPhone, em Ajustes › Leitura pelo Mac, coloque:
    Endereço: http://192.168.0.12:8765
    Código:   a1b2c3
```

No app de iPhone:
1. Abra a engrenagem e escolha **Mac (grátis)**.
2. Digite o endereço e o código que o servidor mostrou.
3. Toque em **Testar conexão**.

O código fica salvo em `~/.xadrez-no-ouvido-token`, então ele continua o mesmo quando você reinicia o servidor.

Durante a partida, cada leitura aparece numa linha, com o tempo que levou e a resposta do Claude:

```
[21:04:12] 2.9s  e7e5 high  (resposta: 'e7e5 HIGH')
[21:04:31] 2.4s  none low  (resposta: 'NONE')
```

## Opções

| Opção | Pra que serve |
|---|---|
| `--model haiku` | Mais rápido e gasta menos do seu limite de uso. Pode ler pior. |
| `--model opus` | Lê melhor, mas é mais lento e gasta mais limite. |
| `--save-frames fotos/` | Salva cada foto recebida, pra você ver o que o óculos está enxergando. |
| `--port 8765` | Muda a porta. |

O modelo padrão é o `sonnet`.

## Testado

O comando `claude -p` foi testado com imagens de tabuleiro desenhadas por computador, e não com fotos reais do óculos:

| Caso | Resposta | Tempo |
|---|---|---|
| Depois de 1.e4 e5 | `e7e5 HIGH` (correto) | ~3 s |
| Depois de 1.e4, sem lance das pretas | `NONE` (correto) | ~2,5 s |

Com fotos de verdade, tiradas de lado e com sombra, a leitura vai ser mais difícil.

## Limite de uso da assinatura

As chamadas contam no limite da sua assinatura, como se você estivesse usando o Claude Code normalmente. Numa partida, o servidor faz de 12 a 20 chamadas por minuto, mas só enquanto seu amigo pensa.

Rode `/usage` no Claude Code antes de jogar. Se o limite acabar, o servidor mostra o erro e você pode marcar os lances tocando no tabuleiro do app.

O servidor também remove a variável `ANTHROPIC_API_KEY` antes de chamar o `claude`. Se ela estivesse definida, o `claude -p` cobraria pela API em vez de usar a assinatura.

## Rede

- **Na sua casa:** o iPhone e o Mac precisam estar no mesmo Wi-Fi.
- **Na casa do seu amigo:** instale o [Tailscale](https://tailscale.com), que é gratuito, no Mac e no iPhone. No app, use o IP `100.x.x.x` que o Tailscale mostra pro Mac.
- **Ainda não testado:** a câmera do óculos pode usar o Wi-Fi do iPhone pra mandar o vídeo. Se o botão **Testar conexão** falhar enquanto a câmera estiver ligada, use o Tailscale, que funciona pela internet do celular.

## Segurança

- Só quem tem o código consegue usar o servidor.
- O Claude Code roda **sem nenhuma ferramenta** (`--tools ""`). Ele só olha a foto e responde, e não consegue mexer em arquivos nem rodar comandos no Mac.
- A resposta só é aceita se for um lance legal da lista.
- Use apenas para você. A assinatura do Claude é pessoal, e as regras da Anthropic não permitem oferecer esse acesso a outras pessoas.
