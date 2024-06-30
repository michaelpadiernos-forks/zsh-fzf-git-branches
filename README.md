# fzf-git-branches

A script to manage Git branches and worktrees using `fzf` in `bash` and `zsh`. It provides a
convenient way to handle Git branches and worktrees with a fuzzy finder interface.

## Features

- List, delete, and switch to Git branches and worktrees.
- Integrated with `fzf` for enhanced user interaction.
- Support for confirmation dialogs.
- ANSI output coloring for better readability.

## Requirements

- `git` (https://git-scm.com/)
- `fzf` (https://github.com/junegunn/fzf)
- Modern version of `bash` or `zsh`

## Installation

1. Clone the repository or download the script.

   ```sh
   git clone https://github.com/awerebea/fzf-git-branches.git ~/.fzf-git-branches
   ```

2. Source the script in your shell configuration file (`.bashrc`, `.zshrc`, etc.):

   ```sh
   source ~/.fzf-git-branches/fzf-git-branches.sh
   ```

3. Ensure `fzf` is installed and available in your `PATH`.

## Usage

To start using the script, call the `fgb` function in your terminal with a command and its options as arguments.

### Examples

Manage branches:

```sh
fgb branch manage
```

Manage worktrees:

```sh
fgb worktree total
```

This will open a fzf interface to manage your Git branches.

Key Bindings
enter/ctrl-y: Jump to the selected branch.
ctrl-t: Toggle the selection.
ctrl-d: Delete the selected branch.
ctrl-alt-d: Extended delete.
ctrl-o: Show branch information.

### Available Commands and Subcommands

#### Branch Commands

- `fgb branch list [args]`

  - **Purpose:** Lists the Git branches in the repository and exit. By default lists only local
    branches.
  - **Options:**
    - `remotes`: Lists only remote branches.
    - `all`: Lists both local and remote branches.
    - `sort`: Sort branches by **_<sort>_**: default `refname`

- `fgb branch manage [args]`
  - **Purpose:** Switch to existing branches in the git repository, delete them, or get information about branches. By default lists only local branches.
  - **Options:**
    - `--remotes`: Lists only remote branches.
    - `--all`: Lists both local and remote branches.
    - `--sort`: Sort branches by **_<sort>_**: default `refname`
    - `--force`: Suppress confirmation dialog for non-destructive operations

#### Worktree Commands

- `fgb worktree list [args]`

  - **Purpose:** Lists all worktrees in a bare Git repository and exit.
  - **Options:**
    - `--remotes`: Lists only remote branches.
    - `--all`: Lists both local and remote branches.
    - `--sort`: Sort branches by **_<sort>_**: default `refname`

- `fgb worktree manage [args]`

  - **Purpose:** Switch to existing worktrees in the bare Git repository or delete them.
  - **Options:**
    - `--sort`: Sort branches by **_<sort>_**: default `refname`
    - `--force`: Suppress confirmation dialog for non-destructive operations

- `fgb worktree add [args]`

  - **Purpose:** Add a new worktree based on a selected Git branch.
  - **Options:**
    - `--remotes`: Lists only remote branches.
    - `--all`: Lists both local and remote branches.
    - `--sort`: Sort branches by **_<sort>_**: default `refname`
    - `--confirm`: Automatic confirmation of the directory name for the new worktree
    - `--force`: Suppress confirmation dialog for non-destructive operations

- `fgb worktree total [args]`
  - **Purpose:** A **_total_** control over worktrees. Add a new one, switch to an existing
    worktree in the bare Git repository, or delete them, optionally with corresponding branches.
  - **Options:**
    - `--remotes`: Lists only remote branches.
    - `--all`: Lists both local and remote branches.
    - `--sort`: Sort branches by **_<sort>_**: default `refname`
    - `--confirm`: Automatic confirmation of the directory name for the new worktree
    - `--force`: Suppress confirmation dialog for non-destructive operations

For more details on each command and its options, you can use the `-h` or `--help` option. For
example:

```sh
fgb branch manage --help
```

## License

This script is licensed under the GPL License. See the [LICENSE](LICENSE) file for more details.

## Contribution

Feel free to open issues or submit pull requests if you find bugs or have suggestions for
improvements.

## Inspiration

Inspired by [fzf-marks](https://github.com/urbainvaes/fzf-marks).
