#!/bin/bash
# Monta um repositório APT assinado a partir de uma pasta de .deb.
#
#   packaging/build-repo.sh PASTA_DOS_DEB PASTA_DO_SITE CHAVE_GPG
#
# O resultado é estático (serve no GitHub Pages): pool/, dists/stable/ e a
# chave pública em gprengine.gpg.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# A página de entrada vem de site/ (a landing page do projeto).
cp -r "$REPO/site/." "$SITE/"
touch .nojekyll
echo "$SITE"
