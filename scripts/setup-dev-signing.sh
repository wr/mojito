#!/usr/bin/env bash
# One-time dev environment setup. Creates a stable, self-signed code signing
# identity so macOS TCC (Accessibility, Input Monitoring) remembers granted
# permissions across rebuilds.
#
# Why: ad-hoc-signed binaries (`-`) get a new cdhash on every rebuild, which
# makes TCC treat each build as a different app. Granting once with a stable
# identity means subsequent rebuilds inherit the grants.
#
# This script:
#  1. Generates a fresh RSA private key with a strong random PKCS12 password
#     held only in this script's memory + a self-signed X.509 cert
#     (CN="Mojito Dev").
#  2. Imports both into your login keychain, restricting private-key access
#     to `codesign`, `xcodebuild`, and `productbuild` only. The previous
#     version of this script used `-A` (whitelist ALL apps) which let any
#     installed binary sign code as "Mojito Dev" without a prompt.
#  3. Adds the cert to YOUR user trust store (no sudo, no System.keychain).
#     The earlier version added the cert as a system-wide trustRoot, which
#     made it usable for code-signing trust by anything running on the box.
#  4. Verifies via `security find-identity -p codesigning`.
#
# Idempotent — re-running is a no-op once the identity is installed.
#
# Threat model: if local malware gains your user-level privileges it can still
# read login.keychain-db (encrypted at rest, unlocked at login). The narrower
# private-key ACL and user-scoped trust limit blast radius compared to the
# earlier version, but neither version protects against a fully-compromised
# user account. Don't reuse this identity for anything you actually distribute.

set -euo pipefail

CERT_NAME="Mojito Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "✓ Code signing identity '$CERT_NAME' is already installed."
  exit 0
fi

echo "Creating self-signed code signing identity '$CERT_NAME'..."
echo

WORK_DIR="$(mktemp -d)"
chmod 700 "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# Generate key + self-signed X.509 cert with codeSigning EKU.
openssl req -newkey rsa:2048 -nodes \
  -keyout "$WORK_DIR/key.pem" \
  -x509 -days 3650 \
  -out "$WORK_DIR/cert.pem" \
  -subj "/CN=$CERT_NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  >/dev/null 2>&1

# Random per-run PKCS12 password. The bundle lives in $WORK_DIR for the
# duration of this script (deleted by `trap`) and the password is never
# written to disk or printed — it's only used by the next two openssl /
# security invocations below.
P12_PASSWORD="$(openssl rand -base64 32)"
openssl pkcs12 -export \
  -inkey "$WORK_DIR/key.pem" \
  -in "$WORK_DIR/cert.pem" \
  -out "$WORK_DIR/bundle.p12" \
  -name "$CERT_NAME" \
  -password "pass:$P12_PASSWORD" \
  -legacy \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  >/dev/null 2>&1

# Import into login keychain. Restrict private-key access to the specific
# binaries that need it — no `-A` (allow any). This means the first time
# codesign runs after import it may prompt; click "Always Allow" once.
# The narrower ACL prevents arbitrary local processes from signing code as
# "Mojito Dev" without a TCC prompt.
security import "$WORK_DIR/bundle.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild \
  -T /usr/bin/productsign \
  >/dev/null

# Add the cert to the CURRENT USER's trust settings for code signing only.
# The previous version used `sudo` + `/Library/Keychains/System.keychain`
# (system-wide trustRoot), which let any user / process treat code signed by
# this key as trusted. User-scoped trust limits the blast radius to this
# login account, and avoids needing sudo.
echo "Marking '$CERT_NAME' as trusted for code signing in your user trust store..."
security add-trusted-cert \
  -r trustAsRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$WORK_DIR/cert.pem"

# Confirm.
if security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
  echo
  echo "✓ Identity '$CERT_NAME' is installed and trusted."
  echo
  echo "Next:"
  echo "  xcodegen generate"
  echo "  xcodebuild -scheme Mojito build"
  echo "Grant Accessibility + Input Monitoring once. Future rebuilds keep the grants."
else
  echo
  echo "✗ Setup didn't complete. Verify with:"
  echo "    security find-identity -p codesigning -v"
  exit 1
fi
