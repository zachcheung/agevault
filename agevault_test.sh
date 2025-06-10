#!/bin/sh

set -eu

# Setup test environment
TEST_DIR="$(mktemp -d)"
AGE_SECRET_KEY_FILE="$TEST_DIR/age.key"
AGE_RECIPIENTS_FILE="$TEST_DIR/recipients.txt"
AGEVAULT_SCRIPT="$(realpath ./agevault.sh)"

export AGE_SECRET_KEY_FILE AGE_RECIPIENTS_FILE

trap 'rm -rf "$TEST_DIR"' EXIT INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }

# Generate key pair
cd "$TEST_DIR"
age-keygen -o "$AGE_SECRET_KEY_FILE" 2> /dev/null
age-keygen -y -o "$AGE_RECIPIENTS_FILE" "$AGE_SECRET_KEY_FILE"

# 1. Test encryption and decryption
echo "----> Test: encryption and decryption"
TEST_FILE="$TEST_DIR/secret.txt"
ENCRYPTED_FILE="$TEST_FILE.age"
DECRYPTED_FILE="$TEST_DIR/decrypted.txt"
echo "hello world" > "$TEST_FILE"

$AGEVAULT_SCRIPT encrypt "$TEST_FILE"
[ -f "$ENCRYPTED_FILE" ] || fail "Encryption failed"

cp "$TEST_FILE" "$TEST_FILE.orig"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"

# 2. Test cat
echo "----> Test: cat"
DECRYPTED_CONTENT=$($AGEVAULT_SCRIPT cat "$ENCRYPTED_FILE")
[ "$DECRYPTED_CONTENT" = "hello world" ] || fail "cat output incorrect"

# 3. Test reencrypt (should still be valid)
echo "----> Test: reencrypt"
$AGEVAULT_SCRIPT reencrypt "$ENCRYPTED_FILE"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"

# 4. Test edit (non-interactive: simulate editor)
echo "----> Test: edit"
export EDITOR="sed -i s/world/universe/"
$AGEVAULT_SCRIPT edit "$ENCRYPTED_FILE"
CHANGED=$($AGEVAULT_SCRIPT cat "$ENCRYPTED_FILE")
[ "$CHANGED" = "hello universe" ] || fail "Edit did not apply"

# 5. Test key-add and key-readd
echo "----> Test: key-add"
mkdir -p "$TEST_DIR/keysrv"
echo "$(cat "$AGE_RECIPIENTS_FILE")" > "$TEST_DIR/keysrv/testuser.pub"
export AGE_KEY_SERVER="file://$TEST_DIR/keysrv"

mv "$AGE_RECIPIENTS_FILE" "$AGE_RECIPIENTS_FILE.orig"
$AGEVAULT_SCRIPT key-add testuser
cmp "$AGE_RECIPIENTS_FILE" "$AGE_RECIPIENTS_FILE.orig" || fail "key-add failed"

echo "----> Test: key-readd"
cat "$AGE_RECIPIENTS_FILE.orig" >> "$AGE_RECIPIENTS_FILE"
$AGEVAULT_SCRIPT key-readd testuser
cmp "$AGE_RECIPIENTS_FILE" "$AGE_RECIPIENTS_FILE.orig" || fail "key-readd failed"

echo "----> All tests passed."
