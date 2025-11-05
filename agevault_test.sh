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

trap 'rm -rf "$TEST_DIR"' EXIT INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }

# Generate key pair
age-keygen -o "$_AGE_SECRET_KEY_FILE"
age-keygen -y -o "$AGE_RECIPIENTS_FILE" "$_AGE_SECRET_KEY_FILE"
_AGE_SECRET_KEY=$(grep -v "^#" "$_AGE_SECRET_KEY_FILE")

TEST_FILE="$TEST_DIR/secret.txt"
ENCRYPTED_FILE="$TEST_FILE.age"
echo "hello world" > "$TEST_FILE"
cp "$TEST_FILE" "$TEST_FILE.orig"

# Test encryption with AGE_RECIPIENTS
echo "----> Test: encryption with AGE_RECIPIENTS"
# Generate two key pairs and concatenate their public keys into AGE_RECIPIENTS
AGE_KEY1="$TEST_DIR/key1.txt"
AGE_KEY2="$TEST_DIR/key2.txt"
AGE_PUB1="$TEST_DIR/key1.pub"
AGE_PUB2="$TEST_DIR/key2.pub"

age-keygen -o "$AGE_KEY1"
age-keygen -o "$AGE_KEY2"
age-keygen -y -o "$AGE_PUB1" "$AGE_KEY1"
age-keygen -y -o "$AGE_PUB2" "$AGE_KEY2"

export AGE_RECIPIENTS="$(cat "$AGE_PUB1"), $(cat "$AGE_PUB2") "
# This should encrypt using recipients from AGE_RECIPIENTS
$AGEVAULT_SCRIPT encrypt "$TEST_FILE"
rm "$TEST_FILE"
# Test decryption
for k in $AGE_KEY1 $AGE_KEY2; do
  AGE_SECRET_KEY_FILE=$k $AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
  cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
done
unset AGE_RECIPIENTS

# Test encryption
echo "----> Test: encryption"
$AGEVAULT_SCRIPT encrypt "$TEST_FILE"
[ -f "$ENCRYPTED_FILE" ] || fail "Encryption failed"

# Test encryption with --self using AGE_SECRET_KEY_FILE
echo "----> Test: encryption with --self (AGE_SECRET_KEY_FILE)"
rm -f "$ENCRYPTED_FILE"
unset AGE_SECRET_KEY
export AGE_SECRET_KEY_FILE="$_AGE_SECRET_KEY_FILE"
$AGEVAULT_SCRIPT encrypt --self "$TEST_FILE"
[ -f "$ENCRYPTED_FILE" ] || fail "Encryption with --self failed"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption after --self encryption did not match original"
rm "$TEST_FILE"

# Test encryption with --self using AGE_SECRET_KEY
echo "----> Test: encryption with --self (AGE_SECRET_KEY)"
rm -f "$ENCRYPTED_FILE"
cp "$TEST_FILE.orig" "$TEST_FILE"
export AGE_SECRET_KEY="$_AGE_SECRET_KEY"
unset AGE_SECRET_KEY_FILE
$AGEVAULT_SCRIPT encrypt --self "$TEST_FILE"
[ -f "$ENCRYPTED_FILE" ] || fail "Encryption with --self (AGE_SECRET_KEY) failed"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption after --self encryption (AGE_SECRET_KEY) did not match original"
rm "$TEST_FILE"
unset AGE_SECRET_KEY
export AGE_SECRET_KEY_FILE="$_AGE_SECRET_KEY_FILE"

# Test decryption with AGE_SECRET_KEY_FILE
echo "----> Test: decryption with AGE_SECRET_KEY_FILE"
unset AGE_SECRET_KEY
export AGE_SECRET_KEY_FILE="$_AGE_SECRET_KEY_FILE"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
rm "$TEST_FILE"

# Test decryption with AGE_SECRET_KEY
echo "----> Test: decryption with AGE_SECRET_KEY"
export AGE_SECRET_KEY="$_AGE_SECRET_KEY"
unset AGE_SECRET_KEY_FILE
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
rm "$TEST_FILE"

# Test decryption with AGE_SECRET_KEY and AGE_SECRET_KEY_FILE
echo "----> Test: decryption with AGE_SECRET_KEY and AGE_SECRET_KEY_FILE"
export AGE_SECRET_KEY="$_AGE_SECRET_KEY"
export AGE_SECRET_KEY_FILE="nonexistence"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"
cmp "$TEST_FILE" "$TEST_FILE.orig" || fail "Decryption did not match original"
rm "$TEST_FILE"
unset AGE_SECRET_KEY
export AGE_SECRET_KEY_FILE="$_AGE_SECRET_KEY_FILE"

# Test cat
echo "----> Test: cat"
DECRYPTED_CONTENT=$($AGEVAULT_SCRIPT cat "$ENCRYPTED_FILE")
[ "$DECRYPTED_CONTENT" = "hello world" ] || fail "cat output incorrect"

# Test reencrypt (should still be valid)
echo "----> Test: reencrypt"
$AGEVAULT_SCRIPT reencrypt "$ENCRYPTED_FILE"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"

# Test reencrypt --all
echo "----> Test: reencrypt --all"
git -C "$TEST_DIR" init
git -C "$TEST_DIR" add .
cd "$TEST_DIR"
$AGEVAULT_SCRIPT reencrypt --all
cd -
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"

# Test rotate
echo "----> Test: rotate with --new-key"
$AGEVAULT_SCRIPT rotate --new-key "$ROTATED_AGE_SECRET_KEY_FILE" "$ENCRYPTED_FILE"
export AGE_SECRET_KEY_FILE="$ROTATED_AGE_SECRET_KEY_FILE"
$AGEVAULT_SCRIPT decrypt "$ENCRYPTED_FILE"

# Test edit (non-interactive: simulate editor)
echo "----> Test: edit"
if (sed --version >/dev/null 2>&1); then
  export EDITOR="sed -i s/world/universe/"
else
  export EDITOR="sed -i '' s/world/universe/"
fi
$AGEVAULT_SCRIPT edit "$ENCRYPTED_FILE"
CHANGED=$($AGEVAULT_SCRIPT cat "$ENCRYPTED_FILE")
[ "$CHANGED" = "hello universe" ] || fail "Edit did not apply"

# Test run: load env from .age and run command (backwards compatibility)
echo "----> Test: run (backwards compatibility)"
echo "TEST_VAR=42" > "$TEST_DIR/envfile"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/envfile"

RESULT=$($AGEVAULT_SCRIPT run "$TEST_DIR/envfile.age" -- sh -c 'echo $TEST_VAR')
[ "$RESULT" = "42" ] || fail "agevault run did not set TEST_VAR"

# Test run with --env flag
echo "----> Test: run --env"
echo "ENV_VAR=test123" > "$TEST_DIR/envfile2"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/envfile2"

RESULT=$($AGEVAULT_SCRIPT run --env "$TEST_DIR/envfile2.age" -- sh -c 'echo $ENV_VAR')
[ "$RESULT" = "test123" ] || fail "agevault run --env did not set ENV_VAR"

# Test run --decrypt: decrypt files instead of loading env
echo "----> Test: run --decrypt"
echo "SECRET_DATA=sensitive" > "$TEST_DIR/datafile"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/datafile"
rm "$TEST_DIR/datafile"

# Should decrypt the file without loading as env vars
$AGEVAULT_SCRIPT run --decrypt "$TEST_DIR/datafile.age" -- test -f "$TEST_DIR/datafile"
[ -f "$TEST_DIR/datafile" ] || fail "agevault run --decrypt did not decrypt file"

# Verify the content is correct
CONTENT=$(cat "$TEST_DIR/datafile")
[ "$CONTENT" = "SECRET_DATA=sensitive" ] || fail "agevault run --decrypt content incorrect"

# Clean up for next test
rm "$TEST_DIR/datafile"

# Test run with both --env and --decrypt
echo "----> Test: run --env and --decrypt"
echo "DEPLOY_ENV=production" > "$TEST_DIR/deploy.env"
echo "database.conf content" > "$TEST_DIR/database.conf"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/deploy.env"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/database.conf"
rm "$TEST_DIR/deploy.env" "$TEST_DIR/database.conf"

RESULT=$($AGEVAULT_SCRIPT run --env "$TEST_DIR/deploy.env.age" --decrypt "$TEST_DIR/database.conf.age" -- sh -c "test -f \"$TEST_DIR/database.conf\" && echo \$DEPLOY_ENV")
[ "$RESULT" = "production" ] || fail "agevault run --env and --decrypt failed"
[ -f "$TEST_DIR/database.conf" ] || fail "agevault run --env and --decrypt did not decrypt file"

# Clean up for next test
rm "$TEST_DIR/database.conf"

# Test run with comma-separated files
echo "----> Test: run with comma-separated files"
echo "VAR1=value1" > "$TEST_DIR/env1"
echo "VAR2=value2" > "$TEST_DIR/env2"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/env1"
$AGEVAULT_SCRIPT encrypt "$TEST_DIR/env2"

RESULT=$($AGEVAULT_SCRIPT run --env "$TEST_DIR/env1.age,$TEST_DIR/env2.age" -- sh -c 'echo "$VAR1:$VAR2"')
[ "$RESULT" = "value1:value2" ] || fail "agevault run with comma-separated files failed"

# Test key-add and key-readd
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
