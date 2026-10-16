#!/bin/bash
# 只需运行一次：在“登录”钥匙串里创建一个本机自用的代码签名证书。
# 之后每次编译都用同一个证书签名，系统就能认出这是同一个应用，
# 辅助功能和“控制音乐”的授权不会因为重新编译而失效。
set -euo pipefail

NAME="DesktopLyrics Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "证书“$NAME”已经存在，不用再创建。"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout pass:desktoplyrics

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P desktoplyrics -T /usr/bin/codesign
echo "接下来系统会要求输入登录密码，用来信任这个证书（只用于代码签名）。"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "完成。以后运行 ./scripts/build-app.sh 会自动使用这个证书。"
