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

get_age_recipients_file() {
  if [ $# -eq 0 ]; then
    echo "missing file." >&2
    return 1
  fi

  f="$1"
  case "$AGE_RECIPIENTS_FILE" in
    */*) rf="$AGE_RECIPIENTS_FILE" ;;
    *)   rf="$(dirname "$f")/$AGE_RECIPIENTS_FILE" ;;
  esac

  if [ ! -r "$rf" ]; then
    if [ ! -e "$rf" ]; then
      echo "'$rf' not found." >&2
    else
      echo "'$rf' is not readable." >&2
    fi
    return 1
  fi

  printf "$rf"
}

agevault_encrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  for f in "$@"; do
    rf=$(get_age_recipients_file "$f")
    if [ -e "$f.age" ]; then
      echo "[WARN] '$f.age' already exists." >&2
    fi
    age -R "$rf" -o "$f.age" "$f"
    echo "'$f' is encrypted to '$f.age'."
  done
}

agevault_decrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  for f in "$@"; do
    case "$f" in
      *.age) d=${f%.age} ;;
      *) echo "'$f' is not a .age file." >&2; continue ;;
    esac
    if [ -e "$d" ]; then
      echo "[WARN] '$d' already exists." >&2
    fi
    age -d -i "$AGE_SECRET_KEY_FILE" -o "$d" "$f"
    echo "'$f' is decrypted to '$d'."
  done
}

agevault_cat() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  for f in "$@"; do
    age -d -i "$AGE_SECRET_KEY_FILE" "$f"
  done
}

agevault_reencrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  make_tmp_dir

  for f in "$@"; do
    rf=$(get_age_recipients_file "$f")
    tmp_file="$(mktemp -p "$TMP_DIR")"
    agevault_cat "$f" > "$tmp_file"
    age -R "$rf" -o "$f" "$tmp_file"
    echo "'$f' is reencrypted."
    rm -f -- "$tmp_file"
  done
}

agevault_edit() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  make_tmp_dir

  for f in "$@"; do
    rf=$(get_age_recipients_file "$f")
    base=$(basename "$f" .age)
    tmp_file="$(mktemp -p "$TMP_DIR" "agevault-edit-XXXXXX.$base")"
    encrypted_file_exists=false

    case "$f" in
      *.age)
        # edit database.yml.age, it is fine if encrypted file does not exist
        encrypted_file="$f"
        if [ -e "$encrypted_file" ]; then
          encrypted_file_exists=true
          agevault_cat "$encrypted_file" > "$tmp_file"
        fi
        ;;
      *)
        # edit database.yml
        encrypted_file="$f.age"
        if [ ! -e "$f" ]; then
          # database.yml does not exist, assuming user wants to edit database.yml.age
          if [ -e "$encrypted_file" ]; then
            encrypted_file_exists=true
            agevault_cat "$encrypted_file" > "$tmp_file"
          fi
        else
          # database.yml exists
          if [ ! -e "$encrypted_file" ]; then
            # database.yml.age does not exist, assuming user wants to edit database.yml.age
            cp "$f" "$tmp_file"
          else
            # database.yml.age exists
            echo "[WARN] both '$f' and '$encrypted_file' exist." >&2
            echo "[WARN] did you mean to edit '$encrypted_file'?" >&2
            echo "[WARN] consider using: agevault encrypt '$f'." >&2
            continue
          fi
        fi
        ;;
    esac

    orig_hash=$(sha256sum "$tmp_file" | cut -d' ' -f1)
    ${EDITOR:-vi} "$tmp_file"
    new_hash=$(sha256sum "$tmp_file" | cut -d' ' -f1)

    if [ "$orig_hash" != "$new_hash" ] || { [ ! -s "$tmp_file" ] && [ "$encrypted_file_exists" = false ]; }; then
      # file changes or (file is empty and encrypted_file does not exist)
      age -R "$rf" -o "$encrypted_file" "$tmp_file"
      if [ "$encrypted_file_exists" = false ]; then
        echo "'$encrypted_file' is encrypted."
      else
        echo "'$encrypted_file' is updated."
      fi
    fi
    rm -f -- "$tmp_file"
  done
}

agevault_key_get() {
  if [ $# -eq 0 ]; then
    echo "missing user." >&2
    return 1
  fi

  if [ -z "$AGE_KEY_SERVER" ]; then
    echo "AGE_KEY_SERVER is not set." >&2
    return 1
  fi

  u=$1
  curl -fsSL "$AGE_KEY_SERVER/$u.pub"
}

agevault_key_add() {
  if [ $# -eq 0 ]; then
    echo "missing users." >&2
    return 1
  fi

  for u in "$@"; do
    agevault_key_get "$u" >> "$AGE_RECIPIENTS_FILE"
    echo "added '$u' to '$AGE_RECIPIENTS_FILE'."
  done
}

agevault_key_readd() {
  if [ $# -eq 0 ]; then
    echo "missing users." >&2
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
  completion    Print shell completion script (bash or zsh)
  help          Show this message
EOF
}

agevault_completion() {
  shell=${1:-}
  case "$shell" in
    bash)
      cat <<'EOF'
# bash completion for agevault
_comp_cmd_agevault() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local subcommands="encrypt decrypt cat reencrypt edit key-add key-get key-readd help completion"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    cat|edit|decrypt|reencrypt|encrypt)
      COMPREPLY=( $(compgen -f -- "$cur") )
      return 0
      ;;
    key-add|key-get|key-readd)
      return 0
      ;;
  esac
}
complete -F _comp_cmd_agevault -o filenames agevault
EOF
      ;;
    zsh)
      cat <<'EOF'
#compdef agevault

_arguments -C \
  '1:command:(encrypt decrypt cat reencrypt edit key-add key-get key-readd help completion)' \
  '*::filename:_files'
EOF
      ;;
    *)
      echo "Usage: agevault completion <bash|zsh>" >&2
      return 1
      ;;
  esac
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
    completion) agevault_completion "$@" ;;
    help) agevault_help ;;
    *) echo "Unknown command: $cmd" >&2; exit 1 ;;
  esac
}

command -v age >/dev/null 2>&1 || {
  echo "'age' command not found." >&2
  exit 1
}

agevault "$@"
