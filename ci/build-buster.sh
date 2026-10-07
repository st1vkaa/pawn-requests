#!/usr/bin/env bash
# sscanf (компонент open.mp + legacy-плагин) под Debian 10 buster: glibc <= 2.28, libstdc++ gcc 8.
set -euxo pipefail
annot() { local m="${1//'%'/'%25'}"; m="${m//$'
'/'%0A'}"; echo "::error title=build::${m}"; }
trap 'annot "failed at line $LINENO: $BASH_COMMAND"' ERR
CMAKE_VERSION=3.25.1
MAX_GLIBC_MINOR=28

cat > /etc/apt/sources.list <<'SRC'
deb http://archive.debian.org/debian buster main
deb http://archive.debian.org/debian-security buster/updates main
SRC
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -yq --no-install-recommends g++-multilib make wget ca-certificates binutils
wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh
sh ./cmake-${CMAKE_VERSION}-linux-x86_64.sh --skip-license --prefix=/usr/local --exclude-subdir
rm ./cmake-${CMAKE_VERSION}-linux-x86_64.sh

cd /src
gcc --version
rm -rf build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)" > build.log 2>&1 || { annot "$(grep -iE "error|undefined" build.log | head -25)"; cat build.log; exit 1; }
cat build.log
SO=build/libsscanf.so
test -f "$SO"

echo "=== NEEDED"; objdump -p "$SO" | grep NEEDED
echo "=== GLIBC";  objdump -T "$SO" | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n -u
echo "=== GLIBCXX"; objdump -T "$SO" | grep -oE 'GLIBCXX_3\.4\.[0-9]+' | sort -t. -k3 -n -u
echo "=== entry points"; objdump -T "$SO" | grep -E ' (ComponentEntryPoint|Supports|Load|AmxLoad)$' || true
annot "NEEDED: $(objdump -p "$SO" | grep NEEDED | awk '{print $2}' | tr '
' ' ') | RAW: $(objdump -T "$SO" | grep '*UND*' | head -6)"
echo "=== unresolved (non-system) symbols"
UNRES=$(objdump -T "$SO" | grep '*UND*' | grep -vE '(GLIBC|GLIBCXX|CXXABI|GCC)_[0-9]' | grep -vE '^[0-9a-f]+ +w ' || true)
echo "$UNRES"
if [ -n "$UNRES" ]; then
    annot "unresolved: $(echo "$UNRES" | awk '{print $NF}' | head -40 | tr '
' ' ')"
    echo "SScanF.so ссылается на неопределённые символы — на сервере будет symbol lookup error"
    exit 1
fi
MAXV=$(objdump -T "$SO" | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n -u | tail -1 | cut -d. -f2)
[ "$MAXV" -le "$MAX_GLIBC_MINOR" ] || { echo "GLIBC_2.$MAXV > 2.$MAX_GLIBC_MINOR"; exit 1; }

rm -rf out && mkdir -p out/components out/plugins out/includes
cp "$SO" out/components/SScanF.so
cp "$SO" out/plugins/sscanf.so
cp sscanf2.inc out/includes/
chmod -R a+rwX out build
