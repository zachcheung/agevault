# agevault

`agevault` is a simple shell utility for managing [age](https://github.com/FiloSottile/age)-encrypted secrets with ease.

### 📦 Installation

```sh
sudo curl -fsSL https://raw.githubusercontent.com/zachcheung/agevault/main/agevault.sh -o /usr/local/bin/agevault && sudo chmod +x /usr/local/bin/agevault
```

#### 🧠 Shell Completion

- **Bash**

To install completion globally:

```sh
agevault completion bash | sudo tee /usr/share/bash-completion/completions/agevault > /dev/null
```

Or, to configure it in your `~/.bashrc` for per-user usage (recommended):

```sh
# ~/.bashrc
source <(agevault completion bash)
```

- **Zsh**

```sh
mkdir -p ~/.zsh/completions
agevault completion zsh > ~/.zsh/completions/_agevault
```

Then add to your `~/.zshrc`:

```sh
# ~/.zshrc
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit
compinit
```

### 🚀 Usage

By default, agevault expects an age recipients file named `.age.txt` in the same directory as the secret file. You can override this behavior by setting the `AGE_RECIPIENTS` or `AGE_RECIPIENTS_FILE` environment variable.

| Command    | Description                                                    | Example                                              |
| ---------- | -------------------------------------------------------------- | ---------------------------------------------------- |
| encrypt    | Encrypt file(s)                                                | agevault encrypt secrets                             |
|            | Options: `--self` - Encrypt using identity (secret key)        | agevault encrypt --self secrets                      |
| decrypt    | Decrypt .age file(s)                                           | agevault decrypt secrets.age                         |
| cat        | Decrypt and print to stdout                                    | agevault cat secrets.age                             |
| reencrypt  | Re-encrypt file(s) with updated recipients file                | agevault reencrypt secrets.age                       |
| rotate     | Re-encrypt file(s) with a new key (and update recipients file) | agevault rotate secrets.age                          |
| edit       | Edit encrypted file(s) securely                                | agevault edit secrets.age                            |
| run        | Decrypt and load file(s) into environment, then run command    | agevault run env.age -- npm start                    |
|            | Options: `--env` - Load files as environment variables         | agevault run --env secrets.env.age -- npm start      |
|            | Options: `--decrypt` - Decrypt files without loading env       | agevault run --decrypt secrets.age -- npm start      |
| key-add    | Add public key(s) to recipients file                           | agevault key-add alice                               |
| key-readd  | Reset and add public key(s)                                    | agevault key-readd alice bob                         |
| completion | Generate shell completion (bash/zsh)                           | agevault completion zsh                              |
| git-setup  | Set up Git integration for agevault diff viewing               | agevault git-setup                                   |

In most cases, you can simply use `agevault edit` — it handles encryption, decryption, and editing of secrets in one step.

#### 📂 Example

```console
~ $ export PS1='$ '
$ cd $(mktemp -d)
$ mkdir -pm 0700 ~/.age
$ age-keygen -o ~/.age/age.key && age-keygen -y -o ~/.age/age.pub ~/.age/age.key
$ cp ~/.age/age.pub .age.txt
$ echo "my secret" > secrets

$ agevault encrypt secrets
'secrets' is encrypted to 'secrets.age'.
$ rm secrets

# Encrypt using your own identity (no recipients file needed)
$ agevault encrypt --self secrets
'secrets' is encrypted to 'secrets.age'.

$ agevault decrypt secrets.age
'secrets.age' is decrypted to 'secrets'.

$ cat secrets && rm secrets
my secret

$ agevault cat secrets.age
my secret

$ agevault edit secrets.age
'secrets.age' is updated.

$ agevault cat secrets.age
my new secret

$ age-keygen -o ./age.key
$ age-keygen -y -o ./age.pub ./age.key

# Try decrypting with the new key (should fail because old pubkey was used for encryption)
$ AGE_SECRET_KEY_FILE=./age.key agevault cat secrets.age
age: error: no identity matched any of the recipients

$ cat ./age.pub >> .age.txt
# Re-encrypt the file with the updated recipients
$ agevault reencrypt secrets.age
'secrets.age' is reencrypted.

# Now decryption with the new key works
$ AGE_SECRET_KEY_FILE=./age.key agevault cat secrets.age
my new secret
```

#### 🏃 Run Command Examples

The `run` command supports multiple modes of operation:

**Environment Mode (default - backwards compatible):**

```console
$ echo "API_KEY=secret123" > .env
$ agevault encrypt .env
$ agevault run .env.age -- curl -H "Authorization: Bearer $API_KEY" api.example.com
```

**Explicit Environment Mode:**

```console
$ echo "DB_PASSWORD=secret" > database.env
$ agevault encrypt database.env
$ agevault run --env database.env.age -- ./deploy.sh
```

**Decrypt-only Mode:**

```console
$ echo "sensitive data" > secret.txt
$ agevault encrypt secret.txt
$ agevault run --decrypt secret.txt.age -- cat secret.txt
sensitive data
```

**Combined Mode (environment + decryption):**

```console
$ agevault run --env config.env.age --decrypt cert.pem.age -- docker run -v $(pwd):/data myapp
```

**Comma-separated Files:**

```console
$ agevault run --env "app.env.age,db.env.age" --decrypt "cert.pem.age,key.pem.age" -- ./start-server.sh
```

- `--env` loads files as environment variables
- `--decrypt` decrypts files to their original locations without loading as environment variables
- Files without flags are treated as environment files (backwards compatibility)
- Both options support comma-separated file lists

### 🔐 Configuration

You can configure `agevault` with the following environment variables.

**Note:** These must be **exported** in your shell session or shell profile (`~/.bashrc`, `~/.zshrc`, etc.) for `agevault` to read them:

| Variable              | Description                                           | Default                                            |
| --------------------- | ----------------------------------------------------- | -------------------------------------------------- |
| `AGE_SECRET_KEY`      | Inline private key string (takes precedence)          | (unset)                                            |
| `AGE_SECRET_KEY_FILE` | Path to your age private key                          | `~/.age/age.key`                                   |
| `AGE_RECIPIENTS`      | Comma-separated list of recipients (takes precedence) | (unset)                                            |
| `AGE_RECIPIENTS_FILE` | Path to the recipients list                           | `.age.txt` in same directory as the encrypted file |
| `AGE_KEY_SERVER`      | Base URL for remote public keys                       | (must be set if using key commands)                |
| `AGE_PUBKEY_EXT`      | Extension for Age public keys in the key server       | `pub`                                              |

> [!NOTE]
> `AGE_KEY_SERVER` **must be set** if you intend to use `key-add`, `key-get`, or `key-readd`.
>
> For best security practices, prefer using `AGE_SECRET_KEY_FILE` over `AGE_SECRET_KEY`.

#### 🌐 Key Management

To enable key management, set the key server URL:

```sh
export AGE_KEY_SERVER="https://keys.example.com"
```

By default, agevault expects each key at `$AGE_KEY_SERVER/<username>.pub`.

### License

[MIT](LICENSE)
