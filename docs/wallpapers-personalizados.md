# Wallpapers personalizados

Um wallpaper do GprEngine é um **shader**: um programa pequeno que roda na
placa de vídeo e calcula a cor de cada pixel, a cada quadro. Você escreve uma
função; a animação vem de usar o tempo dentro dela.

Cada wallpaper é uma pasta em `~/.config/gprengine/wallpapers/`.

## Em um minuto

1. Na galeria, clique no **+** e em **Criar um wallpaper…**.
2. Dê um nome. O GprEngine cria a pasta, aplica o wallpaper e abre o
   `shader.glsl` no seu editor.
3. Edite e salve. **O wallpaper recarrega sozinho a cada vez que você salva.**

Se o shader tiver um erro, o wallpaper anterior continua na tela e o cartão na
galeria ganha um aviso: clique nele para ver a mensagem, com o número da linha
do seu arquivo.

## A pasta

```
por-do-sol/
├── manifest.json
└── content/
    └── shader.glsl
```

`manifest.json`:

```json
{
  "format": 1,
  "id": "por-do-sol",
  "name": "Pôr do sol",
  "author": "Seu nome",
  "type": "glsl",
  "entry": "content/shader.glsl"
}
```

| Campo | O que é |
|---|---|
| `format` | Sempre `1`. |
| `id` | Igual ao nome da pasta: letras minúsculas, números, `-` e `_`. |
| `name`, `author` | Aparecem no cartão da galeria. |
| `type` | `glsl` (os tipos `web` e `video` estão reservados para o futuro). |
| `entry` | O arquivo do shader, dentro da pasta. |
| `thumbnail` | Opcional: uma imagem sua para o cartão. Sem ela, o GprEngine tira uma foto do shader aos 5 segundos. |

Um wallpaper seu com o mesmo `id` de um que veio com o programa toma o lugar
dele: é o jeito de ajustar um existente sem mexer no original (copie a pasta
de `wallpapers/` para a sua e edite).

## O shader

O contrato é o do [Shadertoy](https://www.shadertoy.com): escreva só
`mainImage`.

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;          // de 0 a 1
    fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
}
```

A linguagem é GLSL 3.30. O que chega pronto para você:

| Valor | Tipo | O que é |
|---|---|---|
| `fragCoord` | `vec2` | Posição do pixel, em pixels. A origem é o canto **de baixo**, à esquerda. |
| `iResolution` | `vec3` | Largura e altura da tela em pixels (`.xy`). |
| `iTime` | `float` | Segundos de animação. Para quando o wallpaper pausa e segue o ajuste de velocidade. |
| `iTimeDelta` | `float` | Segundos desde o quadro anterior. |
| `iFrame` | `int` | Número do quadro. |
| `iDate` | `vec4` | Ano, mês (0 a 11), dia e segundos desde a meia-noite, na hora local, com a fração do segundo. |
| `iMouse` | `vec4` | Sempre zero: um wallpaper não recebe o mouse. |
| `iWeather` | `vec4` | Tempo de agora na cidade dos Ajustes, de 0 a 1: `x` nebulosidade, `y` chuva, `z` trovoada, `w` vento. Só é consultado (no Open-Meteo, a cada 15 min) enquanto o wallpaper atual usa `iWeather`; um valor novo entra aos poucos, em 90 s. |

Shaders de uma passada do Shadertoy costumam rodar só colando o código. Os que
usam `iChannel` (texturas), buffers ou áudio ainda não funcionam.

### Receitas

**Coordenadas sem distorção.** `uv` de 0 a 1 estica em telas largas. Para
círculos saírem redondos, centralize e divida pela altura:

```glsl
vec2 p = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;   // y de -0,5 a 0,5
float disco = step(length(p), 0.25);
```

**Bordas lisas.** `step` dá serrilhado. Use `smoothstep` com a largura de um
pixel:

```glsl
float px = 1.5 / iResolution.y;
float disco = smoothstep(px, -px, length(p) - 0.25);
```

**Formas em camadas.** Comece pelo fundo e misture cada forma por cima:

```glsl
vec3 col = vec3(0.05, 0.07, 0.16);                       // fundo
col = mix(col, vec3(1.0, 0.8, 0.5), disco);              // sol
col = mix(col, vec3(0.1, 0.2, 0.3), smoothstep(px, -px, uv.y - 0.3));  // mar
fragColor = vec4(col, 1.0);
```

**Movimento calmo.** Um wallpaper fica atrás do seu trabalho o dia inteiro:
multiplique o tempo por um fator pequeno (`iTime * 0.1`) e prefira `sin` a
mudanças bruscas.

**Relógio.** A hora vem em `iDate.w`:

```glsl
int segundos = int(iDate.w);
int hora = segundos / 3600, minuto = (segundos / 60) % 60;
```

Os wallpapers `relogio*` que vêm com o programa mostram como desenhar os
dígitos.

### Desempenho

O shader roda para cada pixel, 30 ou 60 vezes por segundo. Em uma tela 4K são
mais de 8 milhões de execuções por quadro.

- Laços longos (ruído com muitas oitavas, raymarching com muitos passos) são o
  que mais pesa. Comece com poucos passos e aumente olhando o uso da GPU.
- Em Ajustes, a **escala de renderização** e o **limite de quadros** aliviam um
  shader pesado sem mexer no código.
- O wallpaper pausa sozinho quando está coberto; não precisa tratar isso.

Os mais de 40 wallpapers em `wallpapers/` do repositório são exemplos para
ler e copiar.

## Compartilhar

**Enviar**: na galeria, clique com o botão direito no cartão e em **Exportar
para compartilhar…**. Sai um arquivo `<id>.gprwallpaper` (é um `.tar.gz` da
pasta).

**Receber**: **+** › **Instalar de um arquivo…**. A galeria mostra o nome, o
autor e os arquivos do pacote antes de instalar.

**Remover**: botão direito no cartão › **Remover** (só nos wallpapers da sua
pasta).

Um shader roda só na placa de vídeo: não lê arquivos, não acessa a rede e não
executa programas. O risco de instalar o wallpaper de um desconhecido é ele
ser pesado e deixar a máquina lenta; nesse caso, troque de wallpaper e remova.
O instalador recusa pacotes com caminhos para fora da pasta, links e arquivos
especiais.

### Publicar no catálogo

O catálogo da aba **Baixar** sai da pasta `wallpapers/` do repositório. Para
propor o seu, abra um pull request em
<https://github.com/gustavoreimche/gprengine-gnome> com a pasta do wallpaper
lá dentro.

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| O wallpaper não aparece na galeria | Falta o `manifest.json`, ou o `id` é diferente do nome da pasta. |
| Aviso no cartão | O shader não compilou. Clique para ver a linha. |
| Tela preta | `fragColor` não recebeu valor em algum caminho, ou a cor ficou negativa. |
| Imagem esticada | Use as coordenadas da receita "sem distorção". |
| `'cross' : redefinition` (ou outro nome) | A função tem o nome de uma que o GLSL já traz. Dê outro nome. |
