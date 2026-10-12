# GprEngine GNOME: desenho

Data: 2026-10-12

## Objetivo

Ter no Ubuntu (GNOME Shell 50, Wayland) wallpapers vivos no estilo do
PrimoEngine: shaders de fragmento desenhados na GPU, que param de desenhar
quando ninguém está olhando. Projeto irmão do `primodock-gnome`.

## Decisões

- **Primeira versão: shaders + pausa.** Cenas web, vídeo, reatividade a áudio,
  playlists e troca por horário ficam para depois. O `manifest.json` já reserva
  os tipos `web` e `video`.
- **Renderer em processo próprio + extensão fina.** No GNOME com Wayland não há
  `layer-shell`; só uma extensão consegue pôr algo atrás das janelas. Rodar o
  shader dentro do compositor faria um shader pesado derrubar o desktop
  inteiro, e web/vídeo não caberiam nesse modelo.
- **Renderer e galeria em Python (PyGObject).** O GJS não tem binding de
  OpenGL, e o `GtkGLArea` exige chamadas GL diretas. O Python do sistema já traz
  GTK4 e libadwaita; as chamadas GL vão por `ctypes` sobre a `libepoxy`. Nenhum
  pacote novo.
- **Contrato Shadertoy.** O autor escreve só `mainImage`; shaders de uma
  passada do Shadertoy rodam colando o código.
- **Catálogo próprio.** Os wallpapers embutidos são escritos por nós. Os
  pacotes de shader do PrimoEngine original são MSL/HLSL e não rodam aqui.
- **Galeria + tile no PrimoDock** para escolher e controlar.

## Arquitetura

| Peça | Tecnologia | Papel |
|---|---|---|
| Renderer | Python, GTK4, `GtkGLArea` | Uma janela por monitor. Carrega o pacote, compila o GLSL, desenha. Dono do nome D-Bus e do estado. |
| Extensão `gprengine@gpr` | GNOME Shell 50 | Sobe o renderer, põe a janela na camada de fundo, esconde do Alt+Tab e do overview, decide quando pausar. |
| Galeria | Python, GTK4, libadwaita | Grade de miniaturas, aplicar, ajustes. |
| Tile do dock | `primodock-gnome/widgets/engine.js` | Pausar, próximo, anterior, abrir a galeria. |

A extensão é a única que enxerga janelas, então é ela que detecta os motivos de
pausa. O renderer não sabe nada sobre janelas.

Se o renderer morrer, a extensão mostra o fundo estático do GNOME e tenta
religar com intervalo crescente, no máximo três vezes.

### D-Bus

Nome `dev.gpr.GprEngine`, objeto `/dev/gpr/GprEngine`, no barramento de
sessão.

| Membro | Tipo | Descrição |
|---|---|---|
| `Apply(s id)` | método | Troca o wallpaper |
| `Next()`, `Previous()` | método | Percorre a lista |
| `SetPaused(b pausado, s motivo)` | método | Liga ou desliga um motivo de pausa |
| `List() → s` | método | JSON com os pacotes e seus erros |
| `Current` | propriedade `s` | Id do wallpaper atual |
| `Paused` | propriedade `b` | Há algum motivo ativo |
| `Changed` | sinal | Estado mudou |

## Pacote

```
aurora/
├── manifest.json
├── thumb.png
└── content/
    └── shader.glsl
```

```json
{
  "format": 1,
  "id": "aurora",
  "name": "Aurora",
  "author": "gpr",
  "type": "glsl",
  "entry": "content/shader.glsl",
  "thumbnail": "thumb.png"
}
```

Embutidos em `~/.local/share/gprengine/wallpapers/`, os do usuário em
`~/.config/gprengine/wallpapers/`. Com o mesmo `id`, vale o do usuário.

Tipos `web` e `video` são listados como "ainda não suportado", sem erro de
formato.

## Contrato do shader

O renderer envolve o código com `#version 330 core` e os uniforms:

| Uniform | Tipo | Conteúdo |
|---|---|---|
| `iResolution` | `vec3` | Tamanho do framebuffer em pixels |
| `iTime` | `float` | Segundos desde o início, congelado enquanto pausado |
| `iTimeDelta` | `float` | Duração do último quadro |
| `iFrame` | `int` | Contador de quadros |
| `iMouse` | `vec4` | Sempre zero |
| `iDate` | `vec4` | Ano, mês, dia, segundos do dia |

Fora da v1: `iChannel0..3`, múltiplas passadas, áudio.

Shader que não compila mantém o wallpaper anterior; a galeria mostra o log do
compilador com a linha já descontada do cabeçalho.

## Pausa

A extensão mantém um conjunto de motivos. O wallpaper só volta quando o
conjunto esvazia.

| Motivo | Detecção | Padrão |
|---|---|---|
| Tela cheia | Janela em fullscreen no monitor | Pausa |
| Coberto | Janela maximizada, ou janelas cobrindo quase toda a área útil | Pausa |
| Tela desligada / bloqueada | Sessão ociosa, tela de bloqueio | Pausa |
| Bateria | UPower `DisplayDevice` em descarga | Continuar, limitar a 15 FPS ou pausar |
| Manual | Galeria ou tile do dock | Desligado |

A pausa entra depois de 500 ms estável; a retomada é imediata. Na visão geral
o wallpaper continua rodando.

Pausado, o renderer remove o `tick callback`: nenhum quadro, nenhum trabalho de
CPU ou GPU, e o `iTime` não salta ao retomar.

Limite conhecido: "coberto" é geométrico. Janela transparente conta como
cobertura. O ajuste "pausar quando coberto" pode ser desligado.

## Desempenho

- **Escala de renderização** 50 / 75 / 100 %, padrão 75 %: o shader desenha num
  framebuffer menor, ampliado na apresentação.
- **Limite de FPS** 30 / 60, padrão 30.
- **GPU**: Intel por padrão; NVIDIA opcional via PRIME offload.

Todos os monitores mostram o mesmo wallpaper na v1.

## Configuração

GSettings em `org.gnome.shell.extensions.gprengine`. A galeria escreve; a
extensão e o renderer reagem ao sinal de mudança.

## Testes

Num GNOME Shell headless isolado:

- Janela do renderer na camada de fundo, abaixo do DING, fora do Alt+Tab e do
  overview.
- Cada motivo de pausa entra e sai; com dois ativos, só volta quando ambos saem.
- Pausado, o contador de quadros não avança e o `iTime` não salta ao retomar.
- Shader inválido: wallpaper anterior continua, erro com a linha certa.
- Renderer morto: fundo estático, três tentativas de religar.
- Pacote `web` listado como não suportado, sem quebrar a grade.
- Cinco ciclos de ativar e desativar sem erro no log nem janela sobrando.
- Os seis embutidos compilam e mantêm 30 FPS na Intel a 75 %.

## O que mudou na implementação

- **Tamanho da janela.** O Mutter limita uma janela comum à área útil, e tela
  cheia esconderia o painel. A janela do renderer fica do maior tamanho que
  cabe na área útil com a proporção do monitor; o clone no fundo a amplia até
  a tela inteira.
- **Janela real invisível.** O que aparece é um `Clutter.Clone` dentro de cada
  `Meta.BackgroundActor`. A janela fica com opacidade zero, região de entrada
  vazia e um efeito vazio que a tira do recorte de oclusão do Mutter (sem ele
  o clone ganha um buraco atrás de cada janela aberta).
- **Tela bloqueada.** A extensão é desligada no bloqueio, então o renderer é
  encerrado e volta ao desbloquear.
- **Tile do dock.** O clique abre um painel com pausar, próximo, anterior e
  galeria. Rolagem e clique direito ficaram com o dock, que já os usa para
  trocar de perfil e abrir o menu.
- **`Mtk.Region` não é usável do GJS** (derruba o shell). A área coberta é
  calculada em JS.
- **Testes** foram feitos à mão com `tests/headless.sh`; não há suíte
  automatizada. Não verificados: convivência com o DING (ele não sobe na
  sessão isolada), GPU dedicada e desempenho em 4096x2560.
