#!/usr/bin/env bash
# FootballTray — package and install script
# Usage:
#   ./package.sh              # package .plasmoid + install locally
#   ./package.sh bump         # bump patch version, commit, tag, push, package
#   ./package.sh bump minor   # bump minor version
#   ./package.sh install      # just install from plasmoid/ dir
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(python3 -c "import json; print(json.load(open('plasmoid/metadata.json'))['KPlugin']['Version'])")
PKG="fotballtray-v${VERSION}.plasmoid"

bump_version() {
    local bump="${1:-patch}"
    local old="$VERSION"
    IFS='.' read -r maj min pat <<< "$VERSION"
    case "$bump" in
        major) maj=$((maj + 1)); min=0; pat=0 ;;
        minor) min=$((min + 1)); pat=0 ;;
        patch) pat=$((pat + 1)) ;;
    esac
    local new="${maj}.${min}.${pat}"
    python3 -c "
import json
p = json.load(open('plasmoid/metadata.json'))
p['KPlugin']['Version'] = '$new'
json.dump(p, open('plasmoid/metadata.json', 'w'), indent=4)
with open('plasmoid/metadata.json', 'a') as f: f.write('\n')
"
    echo "Bumped: $old → $new"
    VERSION="$new"
    PKG="fotballtray-v${VERSION}.plasmoid"
}

package() {
    rm -f "$PKG"
    echo "Packaging $PKG ..."
    (cd plasmoid && zip -r "../$PKG" . -x "*.backup" "*.pyc" "__pycache__/*" ".git/*") >/dev/null
    echo "  Created $PKG ($(du -h "$PKG" | cut -f1))"
}

install_local() {
    echo "Installing locally ..."
    kpackagetool6 -t Plasma/Applet -i plasmoid/ 2>&1 || true
    echo "  Installed. Run: plasmashell --replace &"
}

case "${1:-}" in
    bump)
        bump_version patch
        git add plasmoid/metadata.json
        git commit -m "Bump version to $VERSION"
        git tag "v$VERSION"
        git push && git push --tags
        package
        echo ""
        echo "Pushed v$VERSION to GitHub."
        echo "To publish on KDE Store: upload $PKG at https://store.kde.org"
        ;;
    minor)
        bump_version minor
        git add plasmoid/metadata.json
        git commit -m "Bump version to $VERSION"
        git tag "v$VERSION"
        git push && git push --tags
        package
        ;;
    major)
        bump_version major
        git add plasmoid/metadata.json
        git commit -m "Bump version to $VERSION"
        git tag "v$VERSION"
        git push && git push --tags
        package
        ;;
    install)
        install_local
        ;;
    *)
        package
        install_local
        ;;
esac
