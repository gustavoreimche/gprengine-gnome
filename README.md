# PrimoEngine GNOME

Wallpapers vivos para o GNOME Shell 50 (Wayland): shaders de fragmento
desenhados na GPU, que param de desenhar quando ninguém está olhando.
Inspirado no [PrimoEngine](https://engine.oprimo.dev/); irmão do
`primodock-gnome`.

## Instalar

```bash
./install.sh     # symlinks, schema, atalho da galeria
./ativar.sh      # liga a extensão
```

Depois saia e entre na sessão. Para remover: `./uninstall.sh`.

Não precisa de pacote novo: usa o Python do sistema (`/usr/bin/python3`) com
GTK 4 e libadwaita, que o Ubuntu já traz.

## Usar

- **Galeria**: app "PrimoEngine" no menu. Clique num cartão para aplicar; a
  aba Ajustes controla pausa, escala, FPS e placa de vídeo.
- **Tile no PrimoDock**: adicione o widget "Wallpaper vivo" nas preferências
  do dock. O clique abre pausar, próximo, anterior e a galeria.
- **Linha de comando**:

  ```bash
  gdbus call --session --dest dev.gpr.PrimoEngine \
      --object-path /dev/gpr/PrimoEngine --method dev.gpr.PrimoEngine.Next
  ```

  Métodos: `Apply(id)`, `Next`, `Previous`, `SetPaused(bool, motivo)`,
  `Reload`, `List`, `Stats`.

## Quando ele pausa

| Motivo | Padrão |
|---|---|
| Janela em tela cheia | Pausa |
| Janelas cobrindo a área de trabalho (maximizada, ou 95 % da área útil) | Pausa; dá para desligar |
| Tela desligada | Pausa |
| Tela bloqueada | O renderer é encerrado e volta ao desbloquear |
| Na bateria | Limita a 15 FPS; dá para continuar ou pausar |

Pausado, o renderer não desenha nenhum quadro. Na visão geral ele volta a
rodar, porque ali o fundo aparece.

## Criar um wallpaper

Uma pasta em `~/.config/primoengine/wallpapers/` (o botão **+** da galeria a
abre):

```
meu-shader/
├── manifest.json
└── content/
    └── shader.glsl
```

```json
{
  "format": 1,
  "id": "meu-shader",
  "name": "Meu shader",
  "author": "você",
  "type": "glsl",
  "entry": "content/shader.glsl"
}
```

O shader segue o contrato do Shadertoy: escreva só `mainImage`.

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
}
```

Uniforms: `iResolution`, `iTime`, `iTimeDelta`, `iFrame`, `iDate`, e `iMouse`
(sempre zero). Shaders de uma passada do Shadertoy costumam rodar colando o
código; os que usam `iChannel`, buffers ou áudio ainda não.

Depois de salvar, use o botão de recarregar da galeria. Se o shader não
compilar, o cartão mostra o erro com a linha do seu arquivo e o wallpaper
anterior continua.

## Como funciona

| Peça | Onde | Papel |
|---|---|---|
| Renderer | `engine/renderer.py` | Uma janela por monitor com `GtkGLArea`; dono do D-Bus |
| Extensão | `extension.js`, `shell/` | Sobe o renderer, clona a janela dele no fundo, decide a pausa |
| Galeria | `engine/gallery.py` | Escolha e ajustes |

O desenho completo está em `docs/plans/`.

## Testar sem tocar na sessão

```bash
tests/headless.sh start            # GNOME Shell headless e isolado
tests/headless.sh shot /tmp/a.png
tests/headless.sh eval 'Main.overview.show()'
tests/headless.sh stop
```

Com `PRIMODOCK=~/primodock-gnome` o dock sobe junto, com o tile.

## Limites conhecidos

- "Coberto" é geométrico: janela transparente conta como cobertura.
- Com vários monitores todos mostram o mesmo wallpaper, e a pausa só entra
  quando todos estão cobertos.
- A placa dedicada depende do driver aceitar o offload no Wayland; se não
  aceitar, a extensão volta sozinha para a integrada. A galeria mostra qual
  está em uso.
