#!/usr/bin/env bash
# Builds libfprint with the patched Chromebook FPMCU (crfpmoc) driver and
# installs it into /usr/local, so it overrides Ubuntu's libfprint without
# touching the packaged files.
#
#   ./install-fingerprint.sh              build + install
#   ./install-fingerprint.sh --uninstall  remove, back to stock libfprint
set -euo pipefail
cd "$(dirname "$0")"

REPO=https://gitlab.freedesktop.org/Xelef2000/libfprint.git
BRANCH=feature/crfpmoc
COMMIT=56442591a5c302a906289f30988fb50fc3d82ed6
SRC=libfprint-crfpmoc
BUILD=$SRC/build
LIBDIR=/usr/local/lib/x86_64-linux-gnu

if [[ "${1:-}" == "--uninstall" ]]; then
  sudo rm -f "$LIBDIR"/libfprint-2.so* "$LIBDIR"/pkgconfig/libfprint-2.pc \
    /usr/local/share/metainfo/org.freedesktop.libfprint.metainfo.xml
  sudo rm -rf /usr/local/include/libfprint-2
  sudo systemctl disable fprintd-sleep-fix.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/fprintd-sleep-fix.service
  sudo systemctl daemon-reload
  sudo ldconfig
  sudo systemctl restart fprintd || true
  echo "Removed. Ubuntu's stock libfprint is active again."
  exit 0
fi

sudo apt-get update
sudo apt-get install -y git meson ninja-build gcc pkg-config \
  libglib2.0-dev libgusb-dev libnss3-dev libpixman-1-dev libgudev-1.0-dev \
  libudev-dev libssl-dev libcairo2-dev

if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --branch "$BRANCH" "$REPO" "$SRC"
fi
git -C "$SRC" fetch --quiet origin "$BRANCH" || true
git -C "$SRC" checkout --quiet --force "$COMMIT"
for p in patches/*.patch; do
  echo "Applying $p"
  git -C "$SRC" apply "../$p"
done

meson setup "$BUILD" "$SRC" --wipe --prefix=/usr/local \
  --libdir=lib/x86_64-linux-gnu --buildtype=release \
  -Dintrospection=false -Ddoc=false -Dgtk-examples=false \
  -Dinstalled-tests=false -Dudev_rules=disabled -Dudev_hwdb=disabled
ninja -C "$BUILD"
sudo ninja -C "$BUILD" install
sudo ldconfig

# Stop fprintd before suspend: the crfpmoc driver cannot close the sensor
# while a verify is running, and fprintd is left broken after resume.
sudo install -m 644 systemd/fprintd-sleep-fix.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable fprintd-sleep-fix.service

echo "fprintd will now load: $(ldconfig -p | grep -m1 'libfprint-2.so.2 ' | awk '{print $NF}')"
sudo systemctl restart fprintd || true
sleep 1
fprintd-list "$USER" || true
echo
echo "Done. Reboot once before enrolling (the sensor may still hold a seed from this boot),"
echo "then run:  fprintd-enroll -f right-index-finger"
