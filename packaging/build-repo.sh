#!/bin/bash
# Monta um repositório APT assinado a partir de uma pasta de .deb.
#
#   packaging/build-repo.sh PASTA_DOS_DEB PASTA_DO_SITE CHAVE_GPG
#
# O resultado é estático (serve no GitHub Pages): pool/, dists/stable/ e a
# chave pública em gprengine.gpg.
set -euo pipefail

DEBS="$(realpath "$1")"
SITE="$(realpath -m "$2")"
KEY="$3"
URL="${REPO_URL:-https://gustavoreimche.github.io/gprengine-gnome}"

rm -rf "$SITE"
mkdir -p "$SITE/pool/main" "$SITE/dists/stable/main"
cp "$DEBS"/*.deb "$SITE/pool/main/"

cd "$SITE"
# O pacote é "all", mas o apt procura o índice da arquitetura da máquina.
for arch in amd64 arm64 all; do
    mkdir -p "dists/stable/main/binary-$arch"
    dpkg-scanpackages --multiversion pool/main > "dists/stable/main/binary-$arch/Packages" 2>/dev/null
    gzip -9kn "dists/stable/main/binary-$arch/Packages"
done

apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=GprEngine \
    -o APT::FTPArchive::Release::Label=GprEngine \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Architectures="amd64 arm64 all" \
    -o APT::FTPArchive::Release::Components=main \
    release dists/stable > "$SITE/Release.tmp"
mv "$SITE/Release.tmp" dists/stable/Release

gpg --batch --yes --local-user "$KEY" --clearsign -o dists/stable/InRelease dists/stable/Release
gpg --batch --yes --local-user "$KEY" --detach-sign --armor -o dists/stable/Release.gpg dists/stable/Release
gpg --batch --yes --export "$KEY" > gprengine.gpg

cat > index.html <<HTML
<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GprEngine: repositório APT</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 44rem; margin: 3rem auto; padding: 0 1rem; }
  pre { background: #8881; padding: 1rem; border-radius: 8px; overflow-x: auto; }
</style>
<h1>GprEngine</h1>
<p>Wallpapers vivos para o GNOME Shell. Para instalar no Ubuntu e receber as
atualizações pelo sistema:</p>
<pre>curl -fsSL $URL/gprengine.gpg | sudo tee /usr/share/keyrings/gprengine.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/gprengine.gpg] $URL stable main" | sudo tee /etc/apt/sources.list.d/gprengine.list
sudo apt update && sudo apt install gprengine</pre>
<p>Depois saia e entre na sessão e ative a extensão “GprEngine GNOME”.</p>
<p><a href="https://github.com/gustavoreimche/gprengine-gnome">Código-fonte</a></p>
</html>
HTML
touch .nojekyll
echo "$SITE"
