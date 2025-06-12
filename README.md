# agevault

`agevault` is a simple shell utility for managing [age](https://github.com/FiloSottile/age)-encrypted secrets with ease.

### 📦 Installation

```sh
sudo curl -fsSL https://raw.githubusercontent.com/zachcheung/agevault/main/agevault.sh -o /usr/local/bin/agevault && sudo chmod +x /usr/local/bin/agevault
```

#### 🧠 Shell Completion

- **Bash**

To install completion globally (recommended):

```sh
agevault completion bash | sudo tee /usr/share/bash-completion/completions/agevault > /dev/null
```

Or, to configure it in your `~/.bashrc` for per-user usage:

```sh
# ~/.bashrc
source <(agevault completion bash)
```

- **Zsh**

```sh
agevault completion zsh | sudo tee /usr/local/share/zsh/site-functions/_agevault > /dev/null
```

Ensure Zsh completion is initialized:

```sh
# ~/.zshrc
autoload -Uz compinit
compinit
```

### 🚀 Usage

agevault expects an age recipients file named `.age.txt` in the same directory as the secret file.

| Command    | Description                                            | Example                        |
|------------|--------------------------------------------------------|--------------------------------|
| encrypt    | Encrypt one or more files using the recipients file    | agevault encrypt secrets       |
| decrypt    | Decrypt .age files                                     | agevault decrypt secrets.age   |
| cat        | Print decrypted content to stdout                      | agevault cat secrets.age       |
| reencrypt  | Re-encrypt files (e.g., after updating recipients)     | agevault reencrypt secrets.age |
| edit       | Decrypt, open in editor, then re-encrypt after editing | agevault edit secrets.age      |
| key-add    | Add a public key from a remote key server              | agevault key-add alice         |
| key-readd  | Reset and re-add a list of public keys                 | agevault key-readd alice bob   |
| key-get    | Fetch and print a public key from the key server       | agevault key-get alice         |
| completion | Print bash or zsh completion code                      | agevault completion zsh        |

In most cases, you can simply use `agevault edit` — it handles encryption, decryption, and editing of secrets in one step.

#### 📂 Example

```console
~ # export PS1='# '
# cd $(mktemp -d)
# mkdir -pm 0700 ~/.age
# age-keygen -o ~/.age/age.key && age-keygen -y -o ~/.age/age.pub ~/.age/age.key
# cp ~/.age/age.pub .age.txt
# echo "my secret" > secrets

# agevault encrypt secrets
'secrets' is encrypted to 'secrets.age'.
# rm secrets

# agevault decrypt secrets.age
'secrets.age' is decrypted to 'secrets'.

# cat secrets && rm secrets
my secret

# agevault cat secrets.age
my secret

# agevault edit secrets.age
'secrets.age' is updated.

# agevault cat secrets.age
my new secret

# age-keygen -o ./age.key
# age-keygen -y -o ./age.pub ./age.key
# export AGE_SECRET_KEY_FILE=./age.key

# agevault cat secrets.age
age: error: no identity matched any of the recipients

# unset AGE_SECRET_KEY_FILE
# cat ./age.pub >> .age.txt

# agevault reencrypt secrets.age
'secrets.age' is reencrypted.

# export AGE_SECRET_KEY_FILE=./age.key
# agevault cat secrets.age
my new secret
```

### 🔐 Configuration

You can configure `agevault` with the following environment variables.

**Note:** These must be **exported** in your shell session or shell profile (`~/.bashrc`, `~/.zshrc`, etc.) for `agevault` to read them:

| Variable            | Description                     | Default         |
|---------------------|---------------------------------|-----------------|
| AGE_SECRET_KEY_FILE | Path to your age private key    | ~/.age/age.key  |
| AGE_RECIPIENTS_FILE | Path to the recipients list     | .age.txt in CWD |
| AGE_KEY_SERVER      | Base URL for remote public keys | (must be set)   |

### 🌐 Key Management

To enable key management, set the key server URL:

```sh
export AGE_KEY_SERVER="https://keys.example.com"
```

It expects each key at `$AGE_KEY_SERVER/<username>.pub`.

#### Add a recipient key:

```sh
agevault key-add alice
```

#### Re-add (reset) recipient list:

```sh
agevault key-readd alice bob
```

### License

[MIT](LICENSE)
