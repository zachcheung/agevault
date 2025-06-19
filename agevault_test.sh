#!/bin/sh

set -eu

if [ -f /etc/alpine-release ]; then
  apk add --no-cache age coreutils curl
fi

# Setup test environment
TEST_DIR="$(mktemp -d)"
_AGE_SECRET_KEY_FILE="$TEST_DIR/age.key"
ROTATED_AGE_SECRET_KEY_FILE="$TEST_DIR/new.key"
AGE_RECIPIENTS_FILE="$TEST_DIR/recipients.txt"
AGEVAULT_SCRIPT="$(realpath ./agevault.sh)"

export AGE_RECIPIENTS_FILE

#trap 'rm -rf "$TEST_DIR"' EXIT INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }

# Generate key pair
age-keygen -o "$_AGE_SECRET_KEY_FILE" 2> /dev/null
age-keygen -y -o "$AGE_RECIPIENTS_FILE" "$_AGE_SECRET_KEY_FILE"
_AGE_SECRET_KEY=$(grep -v "^#" "$_AGE_SECRET_KEY_FILE")

# 1. Test encryption
echo "----> Test: encryption"
TEST_FILE="$TEST_DIR/secret.txt"
ENCRYPTED_FILE="$TEST_FILE.age"
DECRYPTED_FILE="$TEST_DIR/decrypted.txt"
echo "hello world" > "$TEST_FILE"

$AGEVAULT_SCRIPT encrypt "$TEST_FILE"
[ -f "$ENCRYPTED_FILE" ] || fail "Encryption failed"

# 2. Test decryption with AGE_SECRET_KEY_FILE
echo "----> Test: decryption with AGE_SECRET_KEY_FILE"
unset AGE_SECRET_KEY
export AGE_SECRET_KEY_FILE="$_AGE_SECRET_KEY_FILE"
mv "$TEST_FILE" "$TEST_FILE.orig"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
rm "$TEST_FILE"

# 3. Test decryption with AGE_SECRET_KEY
echo "----> Test: decryption with AGE_SECRET_KEY"
export AGE_SECRET_KEY="$_AGE_SECRET_KEY"
unset AGE_SECRET_KEY_FILE
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
rm "$TEST_FILE"

# 3. Test decryption with AGE_SECRET_KEY and AGE_SECRET_KEY_FILE
echo "----> Test: decryption with AGE_SECRET_KEY and AGE_SECRET_KEY_FILE"
export AGE_SECRET_KEY="$_AGE_SECRET_KEY"
export AGE_SECRET_KEY_FILE="nonexistence"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
rm "$TEST_FILE"
unset AGE_SECRET_KEY
export AGE_SECRET_KEY_FILE="$_AGE_SECRET_KEY_FILE"

# 4. Test cat
echo "----> Test: cat"
DECRYPTED_CONTENT=$($AGEVAULT_SCRIPT cat "$ENCRYPTED_FILE")
[ "$DECRYPTED_CONTENT" = "hello world" ] || fail "cat output incorrect"

# 5. Test reencrypt (should still be valid)
echo "----> Test: reencrypt"
$AGEVAULT_SCRIPT reencrypt "$ENCRYPTED_FILE"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"

# 6. Test rotate
echo "----> Test: rotate with --new-key"
$AGEVAULT_SCRIPT rotate --new-key "$ROTATED_AGE_SECRET_KEY_FILE" "$ENCRYPTED_FILE"
export AGE_SECRET_KEY_FILE="$ROTATED_AGE_SECRET_KEY_FILE"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"

# 7. Test edit (non-interactive: simulate editor)
echo "----> Test: edit"
export EDITOR="sed -i s/world/universe/"
$AGEVAULT_SCRIPT edit "$ENCRYPTED_FILE"
CHANGED=$($AGEVAULT_SCRIPT cat "$ENCRYPTED_FILE")
[ "$CHANGED" = "hello universe" ] || fail "Edit did not apply"

# 8. Test run: load env from .age and run command
echo "----> Test: run"
echo "TEST_VAR=42" > "$TEST_DIR/envfile"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/envfile"

RESULT=$($AGEVAULT_SCRIPT run "$TEST_DIR/envfile.age" -- sh -c 'echo $TEST_VAR')
[ "$RESULT" = "42" ] || fail "agevault run did not set TEST_VAR"

# 9. Test key-add and key-readd
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
