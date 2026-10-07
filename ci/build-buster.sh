#!/usr/bin/env bash
# Сборка requests.so (x86, 32-bit) в Debian 10 buster -> glibc <= 2.28.
# Запускается внутри контейнера debian:buster, исходники смонтированы в /src.
set -euxo pipefail

CMAKE_VERSION=3.25.1
MAX_GLIBC_MINOR=28

# buster переехал в archive.debian.org
cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian buster main
deb http://archive.debian.org/debian-security buster/updates main
EOF
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid

export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update
apt-get install -yq --no-install-recommends \
    g++-multilib git ca-certificates make wget curl perl \
    python3 python3-pip python3-venv python3-setuptools \
    p7zip-full ninja-build pkg-config binutils

python3 -m venv /opt/conan
/opt/conan/bin/pip install --no-cache-dir --upgrade "pip<24.1"
/opt/conan/bin/pip install --no-cache-dir "conan<2"
ln -sf /opt/conan/bin/conan /usr/local/bin/conan

wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.sh
sh ./cmake-${CMAKE_VERSION}-linux-x86_64.sh --skip-license --prefix=/usr/local --exclude-subdir
rm ./cmake-${CMAKE_VERSION}-linux-x86_64.sh

cd /src
gcc --version
ldd --version 2>&1 | sed -n 1p

conan profile new default --detect --force
# все зависимости (cpprestsdk, boost, openssl, zlib) собираем из исходников этим же gcc 8,
# чтобы ни один готовый бинарь из conancenter не притащил символы новее glibc 2.28
export CONAN_BUILD_ALL=1
sed -i 's/BUILD missing/BUILD all/' CMakeLists.txt

rm -rf build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j"$(nproc)"

SO=$(find build test/plugins -name requests.so -type f -print -quit 2>/dev/null || true)
test -n "$SO"

echo "=== NEEDED"
objdump -p "$SO" | grep NEEDED
echo "=== GLIBC"
objdump -T "$SO" | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n -u
MAXV=$(objdump -T "$SO" | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n -u | tail -1 | cut -d. -f2)
if [ "$MAXV" -gt "$MAX_GLIBC_MINOR" ]; then
    echo "requests.so требует GLIBC_2.$MAXV > 2.$MAX_GLIBC_MINOR"
    exit 1
fi

echo "=== exported (defined) dynamic symbols"
rm -rf out && mkdir -p out/plugins out/includes
cp "$SO" out/plugins/requests.so
cp *.inc out/includes/
chmod -R a+rwX out build

# последнее поле objdump -T = имя символа
NAMES=$(objdump -T "$SO" | grep -v '*UND*' | awk 'NF>=6 {print $NF}' || true)
echo "=== exported: $(echo "$NAMES" | wc -l) symbols"
echo "$NAMES" | grep -vE '5boost' || true
echo "=== boost (безвредно при -Bsymbolic): $(echo "$NAMES" | grep -cE '5boost' || true)"
echo "$NAMES" | grep -E '5boost' | sed -n 1,30p || true

OSSL=$(echo "$NAMES" | grep -E '^(SSL_|SSL3_|TLS_|DTLS_|CRYPTO_|EVP_|BIO_|OPENSSL_|ERR_|X509|PEM_|RSA_|EC_|BN_|ASN1_|OBJ_|RAND_|ssl_|tls1_|ssl3_)' || true)
if [ -n "$OSSL" ]; then
    echo "=== OpenSSL exported:"
    echo "$OSSL" | sed -n 1,50p
    echo "requests.so экспортирует символы OpenSSL — конфликт с omp-server"
    exit 1
fi
