# Release Notes - agevault v1.1.0

## v1.1.0 - Enhanced Run Command (August 14, 2024)

### 🎉 What's New

#### Enhanced `run` Command
- **`--decrypt-only` option** - Decrypt files without loading them as environment variables
- **Dual-mode operation** - Choose between environment loading (default) or file decryption
- **Improved flexibility** - Better support for commands that need access to decrypted files

### ✨ Features

#### Core Enhancements
- **Enhanced `run` command** with `--decrypt-only` flag for file decryption workflows
- **Improved shell completion** - Smart completion for new option and command contexts
- **Better documentation** - Comprehensive examples showing both run modes

### 🔧 Usage Examples

**Environment Mode (default):**
```bash
agevault run secrets.env.age -- ./deploy.sh
```

**Decrypt-only Mode:**
```bash
agevault run --decrypt-only config.json.age cert.pem.age -- docker run -v $(pwd):/data myapp
```

### 🛠️ Improvements
- Enhanced bash and zsh completion for `run` command options
- Updated help text with clear option descriptions
- Comprehensive test coverage for new functionality

---

# Release Notes - agevault v1.0.0

## v1.0.0 - Initial Release (August 14, 2024)

We're excited to announce the first major release of **agevault**, a simple yet powerful shell utility for managing [age](https://github.com/FiloSottile/age)-encrypted secrets with ease!

### 🎉 What's New

This is the initial stable release of agevault, bringing you a complete toolkit for secure secret management using the age encryption format.

### ✨ Features

#### Core Commands
- **`encrypt`** - Encrypt files using age encryption
- **`decrypt`** - Decrypt `.age` files back
- **`cat`** - Decrypt file contents to stdout
- **`edit`** - Securely edit encrypted files in-place
- **`reencrypt`** - Re-encrypt files with updated recipients
- **`rotate`** - Re-encrypt files with new keys and update recipients
- **`run`** - Decrypt environment files and run commands with loaded variables

#### Key Management
- **`key-add`** - Add public keys to recipients file
- **`key-get`** - Retrieve public keys from remote key server
- **`key-readd`** - Reset and add public keys to recipients file
- Remote key server integration for centralized key management

#### Developer Experience
- **Shell completion** support for Bash and Zsh
- **Git integration** with `git-setup` command for diff viewing
- Comprehensive help system
- Cross-platform compatibility (macOS and Linux)

#### Configuration & Flexibility
- Environment variable configuration support:
  - `AGE_SECRET_KEY` - Inline private key string
  - `AGE_SECRET_KEY_FILE` - Path to private key file
  - `AGE_RECIPIENTS` - Comma-separated recipients list
  - `AGE_RECIPIENTS_FILE` - Path to recipients file
  - `AGE_KEY_SERVER` - Remote key server URL
  - `AGE_PUBKEY_EXT` - Public key file extension
- Automatic recipients file discovery
- Secure temporary file handling
- Cross-platform sed compatibility

### 🚀 Installation

Install agevault with a single command:

```sh
sudo curl -fsSL https://raw.githubusercontent.com/zachcheung/agevault/main/agevault.sh -o /usr/local/bin/agevault && sudo chmod +x /usr/local/bin/agevault
```

### 🧠 Shell Completion Setup

**Bash:**

```sh
# Global installation
agevault completion bash | sudo tee /usr/share/bash-completion/completions/agevault > /dev/null

# Per-user installation (recommended)
echo 'source <(agevault completion bash)' >> ~/.bashrc
```

**Zsh:**

```sh
# Global installation
agevault completion zsh | sudo tee /usr/share/zsh/site-functions/_agevault > /dev/null

# Ensure completion is enabled
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
```

### 📋 Requirements

- POSIX-compatible shell (bash, zsh, dash, etc.)
- [age](https://github.com/FiloSottile/age) encryption tool
- Standard UNIX utilities (sed, cut, awk, etc.)

### 🔧 Quick Start

1. Generate your age key pair:

```sh
mkdir -pm 0700 ~/.age
age-keygen -o ~/.age/age.key
age-keygen -y -o ~/.age/age.pub ~/.age/age.key
```

2. Create a recipients file:

```sh
cp ~/.age/age.pub .age.txt
   ```

3. Start encrypting secrets:

```sh
echo "my secret" > secrets.txt
agevault encrypt secrets.txt
```

4. Edit encrypted files securely:

```sh
agevault edit secrets.txt.age
```

### 🎯 Key Benefits

- **Simple**: Intuitive command-line interface that feels natural
- **Secure**: Built on the robust age encryption standard
- **Flexible**: Supports multiple workflows and configuration options
- **Portable**: Single shell script with minimal dependencies
- **Developer-friendly**: Git integration and shell completion included

### 📚 Documentation

For detailed usage instructions, examples, and configuration options, see the [README.md](README.md).

### 🙏 Acknowledgments

agevault is built on top of the excellent [age](https://github.com/FiloSottile/age) encryption tool by Filippo Valsorda and contributors.

### 📄 License

[MIT License](LICENSE)

---

**Full Changelog**: Initial release - all features are new in v1.0.0

