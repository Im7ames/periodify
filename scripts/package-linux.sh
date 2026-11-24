#!/usr/bin/env bash
set -euo pipefail
: "${LINUX_GPG_PRIVATE_KEY:?Missing existing Linux signing key}"
: "${LINUX_GPG_PASSPHRASE:?Missing Linux signing passphrase}"
test -d build/linux/x64/release/bundle || { echo 'Run flutter build linux --release before packaging.' >&2; exit 1; }
mkdir -p artifacts build/deb/DEBIAN build/deb/opt/periodify build/deb/usr/share/applications
cp -a build/linux/x64/release/bundle/. build/deb/opt/periodify/
cat > build/deb/DEBIAN/control <<EOF
Package: periodify
Version: ${TAG#v}
Architecture: amd64
Maintainer: Periodify <noreply@github.com>
Depends: libgtk-3-0, libstdc++6, libsecret-1-0
Description: Offline Bromcom timetable companion
EOF
cat > build/deb/usr/share/applications/periodify.desktop <<EOF
[Desktop Entry]
Name=Periodify
Exec=/opt/periodify/periodify
Type=Application
Categories=Education;
Terminal=false
EOF
dpkg-deb --build --root-owner-group build/deb artifacts/periodify-linux.deb
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'rm -rf "$GNUPGHOME"' EXIT
printf '%s' "$LINUX_GPG_PRIVATE_KEY" | gpg --batch --import
# Preserve compatibility with the existing key created by Windows GnuPG.
passphrase_format='%s\n'
if [[ ${LINUX_GPG_PASSPHRASE_SUFFIX_CR:-false} == true ]]; then
  passphrase_format='%s\r\n'
fi
printf "$passphrase_format" "$LINUX_GPG_PASSPHRASE" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --armor --detach-sign artifacts/periodify-linux.deb
gpg --verify artifacts/periodify-linux.deb.asc artifacts/periodify-linux.deb
gpg --armor --export > artifacts/linux-signing-key.asc
