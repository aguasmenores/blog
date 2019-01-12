#!/bin/bash

PREFIX=/opt/qbittorrent
SUDO=sudo
CWD=$(pwd)
NPROC=$(nproc)

echo "Heu instaŀlat les dependències? (s/N)"
read DEP_INSTALLED

while [[ $DEP_INSTALLED =~ [^sS] ]]; do
    if [[ -z $DEP_INSTALLED || $DEP_INSTALLED == "[nN]"]]; then
        echo "Pots instaŀlar automàticament les depèndencies amb la comanda apt-get build-dep nom_paquet. Els paquets de Debian GNU/Linux necessaris són: libtorrent-rasterbar9 i libqt5core5a"
        echo "Dependències de"
        echo "Sortint."
        exit 0
    fi
    echo "Si us plau, respon amb S o N."
    read DEP_INSTALLED
done    

# Offline Qt Downloads, offline installer, source packages & other releases
# https://www.qt.io/offline-installers
echo "Descarregant Qt"
wget http://download.qt.io/official_releases/qt/5.12/5.12.0/single/qt-everywhere-src-5.12.0.tar.xz
echo "Descarregant Boost"
wget https://dl.bintray.com/boostorg/release/1.69.0/source/boost_1_69_0.tar.gz
echo "Descarregant libtorrent"
wget https://github.com/arvidn/libtorrent/releases/download/libtorrent_1_1_12/libtorrent-rasterbar-1.1.12.tar.gz
echo "Descarregant qBittorrent"
wget https://github.com/qbittorrent/qBittorrent/archive/release-4.1.5.tar.gz

echo "Descomprimint Qt"
tar -Jxvf qt-everywhere-src-5.12.0.tar.xz
echo "Descomprimint Boost"
tar -zxvf boost_1_69_0.tar.gz
echo "Descomprimint libtorrent"
tar -zxvf libtorrent-rasterbar-1.1.12.tar.gz
echo "Descomprimint qBittorrent"
tar -zxvf release-4.1.5.tar.gz
mv release-4.1.5 qbittorrent-4.1.5

echo "Instaŀlant Boost"
# https://www.boost.org/doc/libs/1_69_0/more/getting_started/unix-variants.html
cd boost_1_69_0.tar.gz
./bootstrap.sh $PREFIX
$SUDO ./b2 install

cd $CWD

echo "Instaŀlant Qt"
cd qt-everywhere-src-5.12.0
./configure --prefix=$PREFIX
make -j $NPROC
$SUDO make install

cd $CWD

echo "Instaŀlant Libtorrent"
cd libtorrent-rasterbar-1.1.12
./configure --prefix=$PREFIX --with-boost=$PREFIX
make -j $NPROC
$SUDO make install

cd $CWD

echo "Instaŀlant qtBittorrent"
cd qbittorrent-4.1.5
PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig/ ./configure --prefix=/opt/qbittorrent/ --with-boost=/opt/qbittorrent --disable-gui
make -j $NPROC
$SUDO make install

cd $CWD
