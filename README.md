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

### Key Bindings

Default key bindings that can be overridden by an environment variable:
- `enter/ctrl-y`: Select the branch/worktree to jump to.
- `ctrl-t`: Toggle the selection.

After invoking fzf, the following keybindings are expected (hard-coded by design):
- `ctrl-d`: Delete the selected branch.
- `ctrl-alt-d`: Extended delete.
    When deleting a worktree, delete the associated local branch;
    when deleting a local branch, delete the remote branch.
- `ctrl-o`: Show branch information.

### Available Commands and Subcommands

#### Branch Commands

- `fgb branch list [args]`:
    Lists the Git branches in the repository and exit.

- `fgb branch manage [args]`:
    Switch to existing branches in the git repository, delete them,
    or get information about branches.

#### Worktree Commands

- `fgb worktree list [args]`:
    Lists all worktrees in a bare Git repository and exit.

- `fgb worktree manage [args]`:
    Switch to existing worktrees in the bare Git repository or delete them.

- `fgb worktree add [args]`:
    Add a new worktree based on a selected Git branch.

- `fgb worktree total [args]`:
    **_Total_** control over worktrees.
    Add a new one, switch to an existing worktree in the bare Git repository,
    or delete them, optionally with corresponding branches.

##### Available options used in commands in appropriate combinations.

- By default, all commands list only local branches.
- `-r, --remotes`: Lists only remote branches.
- `-a, --all`: Lists both local and remote branches.
- `-s, --sort`: Sort branches by **_<sort>_**:
    - `-committerdate` (default )
    - `refname`
    - `authorname`
    - etc.
- `-f, --force`:
    Suppress confirmation dialog for non-destructive operations
- `-c, --confirm`:
    Automatic confirmation of the directory name for the new worktree
- `-d, --date-format`:
    Format for 'date' string:
    - `committerdate:relative` (default)
    - `%(authordate) %(committerdate:short)`
    -  `authordate:(relative|local|default|iso|iso-strict|rfc|short|raw)`
    - `authordate:format:'%Y-%m-%d %H:%M:%S'`
    - `committerdate:format-local:'%Y-%m-%d %H:%M:%S'`
- `-u, --author-format`:
    Format for 'author' string:
    - `committername` (default)
    - `authoremail`
    - `%(committername) %(committeremail)`
    - `%(authorname) %(authormail) / %(committername) %(committeremail)`

For more details on each command and its options,
you can use the `-h` or `--help` option. For example:

```sh
fgb branch manage --help
```

## TODO

- [ ] Improve Documentation
    - [ ] Include information on default fzf options
    - [ ] Add information on overriding default options using environment variables
    - [x] Provide details on default keybindings
    - [ ] Include screenshots
    - [ ] Add examples for configuring lazy loading and setting up aliases

## License

This script is licensed under the GPL License.
See the [LICENSE](LICENSE) file for more details.

## Contribution

Feel free to open issues or submit pull requests if you find bugs
or have suggestions for improvements.

## Inspiration

Inspired by [fzf-marks](https://github.com/urbainvaes/fzf-marks) and
[git-worktree.nvim](https://github.com/ThePrimeagen/git-worktree.nvim).
