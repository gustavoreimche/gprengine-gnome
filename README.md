# GprEngine GNOME

Wallpapers vivos para o GNOME Shell 50 (Wayland): shaders de fragmento
desenhados na GPU, que param de desenhar quando ninguém está olhando.
Inspirado no [PrimoEngine](https://engine.oprimo.dev/); irmão do
`gprdock`.

## Instalar

### Pelo repositório APT (Ubuntu, com atualização automática)

```bash
curl -fsSL https://gustavoreimche.github.io/gprengine-gnome/gprengine.gpg | sudo tee /usr/share/keyrings/gprengine.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/gprengine.gpg] https://gustavoreimche.github.io/gprengine-gnome stable main" | sudo tee /etc/apt/sources.list.d/gprengine.list
sudo apt update && sudo apt install gprengine
```

Depois saia e entre na sessão e ative a extensão:

```bash
gnome-extensions enable gprengine@gpr
```

As versões novas chegam junto com as atualizações do sistema. O `.deb` avulso
de cada versão fica em [Releases](https://github.com/gustavoreimche/gprengine-gnome/releases).

### A partir do código

```bash
./install.sh     # symlinks, schema, atalho da galeria
./ativar.sh      # liga a extensão
```

Depois saia e entre na sessão. Para remover: `./uninstall.sh`.

Usa o Python do sistema (`/usr/bin/python3`) com GTK 4 e libadwaita, que o
Ubuntu já traz.

### Lançar uma versão

Aumente o número em `packaging/VERSION` e envie para a `main`. O GitHub Actions
monta o `.deb` (`packaging/build-deb.sh`), publica a release e refaz o
repositório APT assinado e o catálogo no GitHub Pages
(`packaging/build-repo.sh`, `packaging/build-catalog.py`).

## Usar

- **Galeria**: app "GprEngine" no menu. Clique num cartão para aplicar; a
  aba Ajustes controla pausa, escala, FPS, placa de vídeo e a cidade
  do tempo (para os wallpapers que mostram chuva e nuvens de verdade).
- **Tile no gprdock**: adicione o widget "Wallpaper vivo" nas preferências
  do dock. O clique abre pausar, próximo, anterior e a galeria.
- **Botão direito da área de trabalho**: `tools/ding-menu.sh` põe um submenu
  GprEngine (galeria, próximo, anterior, recarregar) no menu do Desktop Icons
  do Ubuntu. Ele usa uma cópia da extensão em `~/.local/share`, sem mexer no
  sistema, e vale na próxima entrada na sessão. Com `--system` ele aplica
  também no arquivo de `/usr/share` (com sudo) e o submenu aparece na hora.
  Depois de atualizar o Ubuntu, rode de novo. Para desfazer:
  `tools/ding-menu.sh --remove`.
- **Linha de comando**:

  ```bash
  gdbus call --session --dest dev.gpr.GprEngine \
      --object-path /dev/gpr/GprEngine --method dev.gpr.GprEngine.Next
  ```

  Métodos: `Apply(id)`, `Next`, `Previous`, `SetPaused(bool, motivo)`,
  `Reload`, `List`, `Stats`.

## Baixar mais wallpapers

O pacote `.deb` traz um conjunto básico (`packaging/base-wallpapers.txt`). O
resto fica no catálogo: na galeria, a aba **Baixar** mostra o que você ainda
não tem e instala com um clique em `~/.config/gprengine/wallpapers/`.

O catálogo é publicado junto com o repositório APT, a partir de `wallpapers/`:
todo commit na `main` que mexe ali republica. Para um wallpaper novo aparecer
com miniatura, rode `tools/catalog-thumbs.py` antes do commit.

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

Na galeria: **+** › **Criar um wallpaper…**. O GprEngine cria a pasta em
`~/.config/gprengine/wallpapers/` com um shader de exemplo, aplica e abre o
arquivo; a cada vez que você salva, o wallpaper recarrega sozinho.

O shader segue o contrato do Shadertoy: escreva só `mainImage`.

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = vec4(uv, 0.5 + 0.5 * sin(iTime), 1.0);
}
```

Para compartilhar, clique com o botão direito no cartão e exporte um arquivo
`.gprwallpaper`; quem recebe usa **+** › **Instalar de um arquivo…**.

O guia completo (formato da pasta, valores disponíveis, receitas, desempenho)
está em [docs/wallpapers-personalizados.md](docs/wallpapers-personalizados.md).

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

Com `GPRDOCK=~/gprdock` o dock sobe junto, com o tile.

## Limites conhecidos

- "Coberto" é geométrico: janela transparente conta como cobertura.
- Com vários monitores todos mostram o mesmo wallpaper, e a pausa só entra
  quando todos estão cobertos.
- A placa dedicada depende do driver aceitar o offload no Wayland; se não
  aceitar, a extensão volta sozinha para a integrada. A galeria mostra qual
  está em uso.

## Licença

GPL-3.0-or-later. Veja [LICENSE](LICENSE).
