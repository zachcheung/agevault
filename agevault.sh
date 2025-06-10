#!/bin/sh

set -eu

# Load config
AGE_SECRET_KEY_FILE="${AGE_SECRET_KEY_FILE:-$HOME/.age/age.key}"
AGE_RECIPIENTS_FILE="${AGE_RECIPIENTS_FILE:-.age.txt}"
AGE_KEY_SERVER="${AGE_KEY_SERVER:-}"
TMP_DIR=""

make_tmp_dir() {
  if [ -z "$TMP_DIR" ]; then
    TMP_DIR=$(mktemp -d -t .agevault.XXXXXX)
    trap 'rm -rf -- "$TMP_DIR"' EXIT INT TERM
  fi
}

check_age_recipients_file() {
  if [ ! -r "$AGE_RECIPIENTS_FILE" ]; then
    if [ ! -e "$AGE_RECIPIENTS_FILE" ]; then
      echo "'$AGE_RECIPIENTS_FILE' not found" >&2
    else
      echo "'$AGE_RECIPIENTS_FILE' is not readable" >&2
    fi
    return 1
  fi
}

agevault_encrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files" >&2
    return 1
  fi

  check_age_recipients_file

  for f in "$@"; do
    # TODO: check existence?
    age -R "$AGE_RECIPIENTS_FILE" -o "$f.age" "$f"
    echo "'$f' is encrypted to '$f.age'."
  done
}

agevault_decrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files" >&2
    return 1
  fi

  for f in "$@"; do
    case "$f" in
      *.age) d=${f%.age} ;;
      *) echo "'$f' is not a .age file" >&2; continue ;;
    esac
    # TODO: check existence?
    age -d -i "$AGE_SECRET_KEY_FILE" -o "$d" "$f"
    echo "'$f' is decrypted to '$d'."
  done
}

agevault_cat() {
  if [ $# -eq 0 ]; then
    echo "missing files" >&2
    return 1
  fi

  for f in "$@"; do
    age -d -i "$AGE_SECRET_KEY_FILE" "$f"
  done
}

agevault_reencrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files" >&2
    return 1
  fi

  make_tmp_dir
  check_age_recipients_file

  for f in "$@"; do
    tmp_file="$(mktemp -p "$TMP_DIR")"
    agevault_cat "$f" > "$tmp_file"
    age -R "$AGE_RECIPIENTS_FILE" -o "$f" "$tmp_file"
    echo "'$f' is reencrypted"
    rm -f -- "$tmp_file"
  done
}

agevault_edit() {
  if [ $# -eq 0 ]; then
    echo "missing files" >&2
    return 1
  fi

  make_tmp_dir
  check_age_recipients_file

  for f in "$@"; do
    base=$(basename "$f" .age)
    tmp_file="$(mktemp -p "$TMP_DIR" "agevault-edit-XXXXXX.$base")"

    if [ -e "$f" ]; then
      agevault_cat "$f" > "$tmp_file"
    else
      f="${f%.age}.age"
      if [ -e "$f" ]; then
        agevault_cat "$f" > "$tmp_file"
      fi
    fi

    orig_hash=$(sha256sum "$tmp_file" | cut -d' ' -f1)
    ${EDITOR:-vi} "$tmp_file"
    new_hash=$(sha256sum "$tmp_file" | cut -d' ' -f1)

    if [ "$orig_hash" != "$new_hash" ]; then
      age -R "$AGE_RECIPIENTS_FILE" -o "$f" "$tmp_file"
      echo "'$f' is updated"
    fi
    rm -f -- "$tmp_file"
  done
}

agevault_key_get() {
  if [ $# -eq 0 ]; then
    echo "missing user" >&2
    return 1
  fi

  if [ -z "$AGE_KEY_SERVER" ]; then
    echo "AGE_KEY_SERVER is not set" >&2
    return 1
  fi

  u=$1
  curl -fsSL "$AGE_KEY_SERVER/$u.pub"
}

agevault_key_add() {
  if [ $# -eq 0 ]; then
    echo "missing users" >&2
    return 1
  fi

  for u in "$@"; do
    agevault_key_get "$u" >> "$AGE_RECIPIENTS_FILE"
    echo "added '$u' to '$AGE_RECIPIENTS_FILE'"
  done
}

agevault_key_readd() {
  if [ $# -eq 0 ]; then
    echo "missing users" >&2
    return 1
  fi

  : > "$AGE_RECIPIENTS_FILE"
  agevault_key_add "$@"
}

agevault_help() {
  cat <<EOF
Usage: agevault <command> [args...]

Commands:
  encrypt       Encrypt file(s)
  decrypt       Decrypt .age file(s)
  cat           Print decrypted content
  edit          Edit encrypted file(s)
  reencrypt     Re-encrypt file(s) with updated recipients
  key-get       Fetch public key from key server
  key-add       Add one or more recipients
  key-readd     Overwrite recipients
  help          Show this message
EOF
}

agevault() {
  cmd="${1:-}"
  shift || true

  case "$cmd" in
    encrypt) agevault_encrypt "$@" ;;
    decrypt) agevault_decrypt "$@" ;;
    cat) agevault_cat "$@" ;;
    reencrypt) agevault_reencrypt "$@" ;;
    edit) agevault_edit "$@" ;;
    key-add) agevault_key_add "$@" ;;
    key-get) agevault_key_get "$@" ;;
    key-readd) agevault_key_readd "$@" ;;
    help) agevault_help ;;
    *) echo "Unknown command: $cmd" >&2; exit 1 ;;
  esac
}

command -v age >/dev/null 2>&1 || {
  echo "'age' command not found" >&2
  exit 1
}

agevault "$@"
