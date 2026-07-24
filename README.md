# Dotfiles

This is a system to install various dotfiles (`.bashrc`, `.zshrc`, `helix/config.toml`, etc.)
to a configured location using symlinks.

## Example Configuration

Check out `configs/hx/dotfile.toml` for an example. 
The current `dotfile.toml` spec is as follows:

```toml
# Display name of the configuration, required.
name = "sample"

# Description of the configuration, required.
description = "dotfile configuration for sample"

# Pre-validations to run, these will be run against the PATH variable.
validation-commands = [
    ["git", "--help"],
    ["cargo", "--version"],
]

# Array of configurations, you can have as many configurations as you
# want here. Each `configs` section corresponds to a separate file to be symlinked.
[[configs]]

# Display name of this file to be symlinked, optional.
name = "samplerc"

# Path within the configuration directory, required.
path = ".samplerc"

# Installation path, required.
# Environment variables "$VAR/path/after/var" will be expanded
# Tilde "~/path/in/home/dir" will also be expanded
install_location = "~/.samplerc"

# Create another configuration file definition
[[configs]]
name = "otherrc"
path = ".otherrc"

# You can specify platform-specific locations to install
# Currently supported platforms: [windows, linux, macos]
# You can omit certain platforms if you don't want to
# use this `dotfile.toml` in that platform.
[configs.install_location]
windows = "$APPDATA/some/path/.otherrc"
linux = "~/.config/some/path/.otherrc"
macos = "~/.config/some/path/.otherrc"
```

## Installation

Build from source
```bash
git clone https://github.com/EDToaster/dotfiles.git
cd dotfiles
cargo install --path .
```

## Running dotfiles

Examples: 

Run validations on `configs/hx`
```bash
dotfiles configs/hx
```

Run installation on `configs/hx`
```bash
dotfiles -i configs/hx
```

## Adopting existing dotfiles

`dotfiles adopt` takes a dotfile that already lives at its install location,
moves it into a profile directory, registers it in that profile's
`dotfile.toml` for the current platform, and replaces the original with a
symlink pointing at the adopted copy.

```bash
dotfiles adopt --profile configs/hx --name "my config" --path ~/.config/foo/bar.toml
```

This will:
1. Add a `[[configs]]` entry to `configs/hx/dotfile.toml` with an
   `install_location` for the current platform (e.g. `linux`), preserving the
   file's existing comments and formatting.
2. Move `~/.config/foo/bar.toml` into `configs/hx/` (using its file name).
3. Symlink `~/.config/foo/bar.toml` back to the adopted copy.

The in-profile file name is derived from the source file name. Add `--dryrun`
to validate and print the intended actions without changing anything.

Adoption refuses to run (making no changes) if any of the following are true:
- the profile directory or its `dotfile.toml` does not exist,
- the source path does not exist, is not a regular file, or is already a symlink,
- a file with the same name already exists in the profile directory, or
- a config with the same path is already registered in the profile.
