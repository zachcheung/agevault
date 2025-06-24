#!/bin/sh

set -eu

# load config
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

set_sed_i() {
  if (sed --version >/dev/null 2>&1); then
    sed_i() { sed -i "$@"; }
  else
    sed_i() { sed -i '' "$@"; }
  fi
}

hash256() {
  if (command -v sha256sum >/dev/null 2>&1); then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
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

_agevault_decrypt_to_stdout() {
  if [ $# -eq 0 ]; then
    echo "missing file." >&2
    return 1
  fi

  file="$1"

  if [ -n "${AGE_SECRET_KEY:-}" ]; then
    printf '%s' "$AGE_SECRET_KEY" | age -d -i - "$file"
  else
    age -d -i "$AGE_SECRET_KEY_FILE" "$file"
  fi
}

agevault_decrypt() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  make_tmp_dir

  for f in "$@"; do
    case "$f" in
      *.age) d=${f%.age} ;;
      *) echo "'$f' is not a .age file." >&2; continue ;;
    esac
    if [ -e "$d" ]; then
      echo "[WARN] '$d' already exists." >&2
    fi
    tmp_file="$(mktemp -p "$TMP_DIR")"
    _agevault_decrypt_to_stdout "$f" > "$tmp_file"
    mv "$tmp_file" "$d"
    echo "'$f' is decrypted to '$d'."
  done
}

agevault_cat() {
  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  for f in "$@"; do
    _agevault_decrypt_to_stdout "$f"
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

agevault_rotate() {
  if [ $# -eq 0 ]; then
    echo "Usage: agevault rotate [--new-key KEY_FILE] FILE [FILE...]" >&2
    return 1
  fi

  new_key="./age.key"
  # parse optional --new-key
  if [ "$1" = "--new-key" ]; then
    shift
    if [ $# -eq 0 ]; then
      echo "missing key path after --new-key." >&2
      return 1
    fi
    new_key="$1"
    shift
  fi

  if [ $# -eq 0 ]; then
    echo "missing files." >&2
    return 1
  fi

  if [ ! -f "$new_key" ]; then
    echo "[INFO] generating new key '$new_key'"
    age-keygen -o "$new_key"
  fi
  new_pub="$(age-keygen -y "$new_key")"
  if [ -n "${AGE_SECRET_KEY:-}" ]; then
    old_pub="$(printf '%s' "$AGE_SECRET_KEY" | age-keygen -y -)"
  else
    old_pub="$(age-keygen -y "$AGE_SECRET_KEY_FILE")"
  fi

  for f in "$@"; do
    rf=$(get_age_recipients_file "$f")
    sed_i "s/$old_pub/$new_pub/" "$rf"
    agevault_reencrypt "$f"
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

    orig_hash=$(hash256 "$tmp_file")
    ${EDITOR:-vi} "$tmp_file"
    new_hash=$(hash256 "$tmp_file")

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

agevault_run() {
  # collect files until we hit "--"
  env_files=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        env_files="$env_files $1"
        shift
        ;;
    esac
  done

  if [ -z "$env_files" ]; then
    echo "no env files provided" >&2
    return 1
  fi

  if [ "$#" -eq 0 ]; then
    echo "no command specified after '--'" >&2
    return 1
  fi

  make_tmp_dir

  set -a
  for f in $env_files; do
    tmp_env="$TMP_DIR/${f##*/}"
    agevault_cat "$f" >> "$tmp_env"
    . "$tmp_env"
    rm -f -- "$tmp_env"
  done
  set +a

  exec "$@"
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

agevault_git_setup() {
  textconv_cmd="agevault cat"
  scope="${1:---local}"
  case "$scope" in
    --global|--system|--local) ;;
    *) echo "unknown option: $scope" >&2; return 1 ;;
  esac

  if ! (git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    echo "not inside a Git repository." >&2
    return 1
  fi

  repo_root=$(git rev-parse --show-toplevel)
  attr_file="$repo_root/.gitattributes"

  # check and set the textconv command
  current=$(git config $scope --get diff.agevault.textconv || echo "")
  if [ "$current" != "$textconv_cmd" ]; then
    git config $scope diff.agevault.textconv "$textconv_cmd"
    echo "configured diff.agevault.textconv in ${scope#--}."
  else
    echo "already set diff.agevault.textconv in ${scope#--}."
  fi

  # handle .gitattributes
  line='**/*.age diff=agevault'

  if [ -f "$attr_file" ]; then
    if (grep -Eq '^\*\*/\*\.age diff=' "$attr_file"); then
      make_tmp_dir
      tmp_attr="$(mktemp -p "$TMP_DIR")"
      cp "$attr_file" "$tmp_attr"

      # apply the substitution on the temporary file
      sed_i -E "s|^\*\*/\*\.age diff=.*|$line|" "$tmp_attr"
      # if the content changed, update the original file and notify
      if ! (cmp -s "$attr_file" "${tmp_attr}"); then
        cp "${tmp_attr}" "$attr_file"
        echo "updated .gitattributes at the Git repository root."
      else
        echo "already set .gitattributes at the Git repository root."
      fi
    else
      echo "$line" >> "$attr_file"
      echo "configured .gitattributes at the Git repository root."
    fi
  else
    echo "$line" > "$attr_file"
    echo "created .gitattributes at the Git repository root."
  fi
}

agevault_help() {
  cat <<EOF
Usage: agevault <command> [options] [files...]

Commands:
  encrypt       Encrypt file(s)
  decrypt       Decrypt .age file(s)
  cat           Decrypt and print to stdout
  reencrypt     Re-encrypt file(s) with the current recipients file
  rotate        Re-encrypt file(s) with a new key (and update recipients file)
                Options:
                  --new-key <file>  Path to the new age private key (default: ./age.key)
  edit          Edit encrypted file(s) securely
  run           Decrypt and load file(s) into environment, then run command
  key-add       Add public key(s) to recipients file
  key-get       Fetch a public key from remote server
  key-readd     Reset and add public key(s)
  completion    Generate shell completion (bash/zsh)
  git-setup     Set up Git integration for agevault diff viewing
                - Configures 'diff.agevault.textconv' to use 'agevault cat'
                - Adds '**/*.age diff=agevault' to the .gitattributes at the Git repo root
                - Supports --local (default), --global, or --system for 'diff.agevault.textconv'
  help          Show this help

Environment:
  AGE_SECRET_KEY        Inline private key string (takes precedence)
  AGE_SECRET_KEY_FILE   Path to private key file (default: ~/.age/age.key)
  AGE_RECIPIENTS_FILE   Recipients file (default: .age.txt)
  AGE_KEY_SERVER        Required for key-add/key-get/key-readd

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

  local subcommands="encrypt decrypt cat reencrypt rotate edit run key-add key-get key-readd completion git-setup help"

  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    encrypt|decrypt|cat|reencrypt|edit|run)
      COMPREPLY=( $(compgen -f -- "$cur") )
      return 0
      ;;
    rotate)
      local has_new_key=false
      for word in "${COMP_WORDS[@]:1}"; do
        [[ "$word" == "--new-key" ]] && has_new_key=true
      done

      if [[ "$prev" == "--new-key" ]]; then
        COMPREPLY=( $(compgen -f -- "$cur") )
      else
        if $has_new_key; then
          COMPREPLY=( $(compgen -f -- "$cur") )
        else
          COMPREPLY=( $(compgen -W "--new-key" -f -- "$cur") )
        fi
      fi
      return 0
      ;;
    key-add|key-get|key-readd)
      return 0
      ;;
    git-setup)
      COMPREPLY=( $(compgen -W "--local --global --system" -- "$cur") )
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

local -a subcommands_list
subcommands_list=(
  'cat:Print decrypted content'
  'completion:Generate completion scripts'
  'decrypt:Decrypt files'
  'edit:Edit encrypted file'
  'encrypt:Encrypt files'
  'git-setup:Configure Git integration'
  'help:Show help'
  'key-add:Add remote key'
  'key-get:Get remote key'
  'key-readd:Reset and re-add remote keys'
  'reencrypt:Re-encrypt files'
  'rotate:Rotate key and re-encrypt'
  'run:Run command with decrypted env'
)

# Dispatch per subcommand
_arguments -C \
  '1: :->command_selector' \
  '2: :->command_args' \
  '*:: :->general_args'

case $state in
  command_selector)
    _describe 'command' subcommands_list
    ;;

  command_args)
    case $words[2] in # $words[2] is the subcommand
      encrypt|decrypt|cat|reencrypt|edit|run)
        _files # For these, just complete files
        ;;

      rotate)
        # Options are listed first, then positional arguments
        _arguments \
          '--new-key[Path to new age key file]:file:_files' \
          '*:files:_files'
        ;;

      key-add|key-get|key-readd)
        _message 'Provide username(s)'
        ;;

      git-setup)
        _values 'scope' --local --global --system
        ;;

      completion)
        _values 'shell' bash zsh
        ;;

      help)
        _message 'No further arguments'
        ;;
    esac
    ;;

  general_args)
    # This state will be hit if there are arguments after the command_args
    # and no specific rule for them was matched.
    ;;
esac
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
    rotate) agevault_rotate "$@" ;;
    edit) agevault_edit "$@" ;;
    run) agevault_run "$@" ;;
    key-add) agevault_key_add "$@" ;;
    key-get) agevault_key_get "$@" ;;
    key-readd) agevault_key_readd "$@" ;;
    completion) agevault_completion "$@" ;;
    git-setup) agevault_git_setup "$@" ;;
    help) agevault_help ;;
    *) echo "Unknown command: $cmd" >&2; exit 1 ;;
  esac
}

command -v age >/dev/null 2>&1 || {
  echo "'age' command not found." >&2
  exit 1
}

set_sed_i
agevault "$@"
