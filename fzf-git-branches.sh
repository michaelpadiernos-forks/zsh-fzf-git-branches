# Description: Manage Git branches and worktrees with fzf

command -v fzf >/dev/null 2>&1 || return

fgb() {
    local VERSION="0.4.1"

    # Set the command to use for fzf
    local fzf_version
    fzf_version=$(fzf --version | awk -F. '{ print $1 * 1e6 + $2 * 1e3 + $3 }')
    local fzf_min_version=16001

    local FZF_ARGS_GLOB="\
            --ansi \
            --bind=ctrl-y:accept,ctrl-t:toggle+down \
            --cycle \
            --multi \
            --pointer='' \
            --preview 'git log --oneline --decorate --graph --color=always {1}' \
        "
    local FZF_CMD_GLOB
    if [[ $fzf_version -gt $fzf_min_version ]]; then
        FZF_CMD_GLOB="fzf --height 40% --reverse $FZF_ARGS_GLOB"
    elif [[ ${FZF_TMUX:-1} -eq 1 ]]; then
        FZF_CMD_GLOB="fzf-tmux -d${FZF_TMUX_HEIGHT:-40%}"
    else
        FZF_CMD_GLOB="fzf $FZF_ARGS_GLOB"
    fi

    __fgb__functions() {
        __fgb_confirmation_dialog() {
            # Confirmation dialog with a single 'y' character to accept

            local user_prompt="${1:-Are you sure?}"
            echo -en "$user_prompt (y|N): "

            local ANS
            if [[ -n "${ZSH_VERSION-}" ]]; then
                read -rk 1 ANS
            else
                read -rn 1 ANS
            fi
            echo # Move to the next line for a cleaner output

            case "$ANS" in
                [yY]) return 0 ;;
                *) return 1 ;;
            esac
        }


        __fgb_stdout_unindented() {
            # Print a string to stdout unindented

            # Usage: $0 "string"
            # String supposed to be indented with any number of any characters.
            # The first `|' character in the string will be treated as the start of the string.
            # The first and last lines of the string will be removed because they must be empty and
            # exist since a quoted literal starts with a new line after the opening quote and ends
            # with a new line before the closing quote, like this:

            # string="
            #     |line 1
            #     |line 2
            # "

            # source: https://unix.stackexchange.com/a/674903/424165

            # Concatenate lines that end with \# (backslash followed by a hash character) and then
            # remove indentation
            sed '1d;s/^[^|]*|//;$d' <<< "$(sed -z 's/\\#\n[^|]*|//g' <<< "$1")"
        }


        __fgb_git_branch_delete() {
            # Delete a Git branch

            local force=false
            local positional_args=()
            while [ $# -gt 0 ]; do
                case "$1" in
                    -f | --force)
                        force=true
                        ;;
                    "") ;; # Skip empty arguments
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if [ "${#positional_args[@]}" -eq 0 ]; then
                echo "$0: Missing argument: list of branches" >&2
                return 1
            fi

            local branch_name is_remote remote_name user_prompt
            local branches_to_delete="${positional_args[*]}"
            local -a array_of_lines
            if [[ -n "${ZSH_VERSION-}" ]]; then
                # shellcheck disable=SC2116,SC2296
                array_of_lines=("${(f@)$(echo "$branches_to_delete")}")
            else
                local line
                while IFS= read -r line; do
                    array_of_lines+=( "$line" )
                done <<< "$branches_to_delete"
            fi
            for branch_name in "${array_of_lines[@]}"; do
                is_remote=false

                if [[ "$branch_name" == remotes/*/* ]]; then
                    is_remote=true
                    remote_name="${branch_name#*/}"
                    remote_name="${remote_name%%/*}"
                fi

                if "$is_remote"; then
                    branch_name="${branch_name#remotes/*/}"
                    user_prompt=$(__fgb_stdout_unindented "
                        |${col_r_bold}WARNING:${col_reset} \#
                        |Delete branch: '${col_b_bold}${branch_name}${col_reset}' \#
                        |from remote: ${col_y_bold}${remote_name}${col_reset}?
                    ")
                    # NOTE: Avoid --force here as it's no undoable operation for remote branches
                    if __fgb_confirmation_dialog "$user_prompt"; then
                        git push --delete "$remote_name" "$branch_name" || return $?
                    fi
                else
                    user_prompt=$(__fgb_stdout_unindented "
                        |${col_r_bold}Delete${col_reset} \#
                        |local branch: \`${col_b_bold}${branch_name}${col_reset}'?
                    ")
                    if "$force" || __fgb_confirmation_dialog "$user_prompt"; then
                        local output
                        if ! output="$(git branch -d "$branch_name" 2>&1)"; then
                            local head_branch; head_branch="$(git rev-parse --abbrev-ref HEAD)"
                            if ! grep -q "^error: .* is not fully merged\.$" <<< "$output"; then
                                echo "$output"
                                continue
                            fi
                            user_prompt=$(__fgb_stdout_unindented "

                                |${col_r_bold}WARNING:${col_reset} \#
                                |The branch '${col_b_bold}${branch_name}${col_reset}' \#
                                |is not yet merged into the \#
                                |'${col_g_bold}${head_branch}${col_reset}' branch.

                                |Are you sure you want to delete it?
                            ")
                            # NOTE: Avoid --force here
                            # as it's not clear if intended for non-merged branches
                            if __fgb_confirmation_dialog "$user_prompt"; then
                                git branch -D "$branch_name" || return $?
                            fi
                        else
                            echo "$output"
                        fi
                    fi
                fi
            done
        }


        __fgb_git_branch_list() {
            # List branches in a git repository

            local sort_order="-committerdate"
            local filter_list=""
            local list_remote_branches=false
            local list_all_branches=false

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        shift
                        sort_order="$1"
                        ;;
                    --sort=*)
                        sort_order="${1#*=}"
                        ;;
                    --filter)
                        shift
                        filter_list="$1"
                        ;;
                    --filter=*)
                        filter_list="${1#*=}"
                        ;;
                    -r | --remotes)
                        list_remote_branches=true
                        ;;
                    -a | --all)
                        list_all_branches=true
                        ;;
                    *)
                        echo "$0: Invalid argument: $1" >&2
                        return 1
                        ;;
                esac
                shift
            done

            local ref_types=()
            if "$list_remote_branches"; then
                ref_types=("remotes")
            else
                ref_types=("heads")
            fi

            if "$list_all_branches"; then
                ref_types=("heads" "remotes")
            fi

            local ref_type ref_name refs
            for ref_type in "${ref_types[@]}"; do
                refs=$(git for-each-ref \
                        --format='%(refname)' \
                        --sort="$sort_order" \
                        refs/"$ref_type"
                )
                while read -r ref_name; do
                    if [[ -n "$filter_list" ]]; then
                        if ! grep -q -E "$ref_name$" <<< "$filter_list"; then
                            continue
                        fi
                    fi
                    git \
                        for-each-ref \
                        --format='%(refname):%(committername):%(committerdate:relative)' \
                        "$ref_name"
                done <<< "$refs"
            done
        }


        __fgb_branch_set_vars() {
            # Define branch related variables

            if [ $# -ne 1 ]; then
                echo "error: missing argument: branch list"
                return 41
            fi

            local branch_list="$1"
            local \
                line \
                branch \
                branch_name \
                branch_curr_width \
                author_name \
                author_curr_width
            while IFS= read -r line; do
                # Remove the longest suffix starting with ':'
                branch="${line%%:*}"
                branch_name="$branch"
                if [[ "$branch" == refs/heads/* ]]; then
                    # Remove first two segments of the reference name for local branches
                    branch_name="${branch_name#*/}"
                    branch_name="${branch_name#*/}"
                elif [[ "$branch" == refs/remotes/* ]]; then
                    # Remove the first segment of the reference name for remote branches
                    branch_name="${branch_name#*/}"
                fi
                # Remove the shortest prefix starting with ':'
                author_name="${line#*:}"
                # Remove the shortest suffix ending with ':'
                author_name="${author_name%:*}"
                c_branch_author_map["$branch"]="$author_name"
                # Remove the longest prefix ending with ':'
                c_branch_date_map["$branch"]="${line##*:}"
                # Calculate column widths
                branch_curr_width="${#branch_name}"
                c_branch_width="$((
                        branch_curr_width > c_branch_width ?
                        branch_curr_width :
                        c_branch_width
                ))"
                # Trim long author names with multiple parts delimited by '/'
                author_curr_width="${#author_name}"
                if [[ "$author_curr_width" -gt 25 && "$author_name" == *"/"* ]]; then
                    author_name=".../${author_name#*/}"
                    c_branch_author_map["$branch"]="$author_name"
                    author_curr_width="${#author_name}"
                fi

                c_author_width="$((
                        author_curr_width > c_author_width ?
                        author_curr_width :
                        c_author_width
                ))"
            done <<< "$branch_list"
        }


        __fgb_branch_list() {
            # List branches in a git repository

            while [ $# -gt 0 ]; do
                case "$1" in
                    -h | --help)
                        echo "${usage_message[branch_list]}"
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[branch_list]}" >&2
                        return 1
                        ;;
                    *)
                        echo "error: unknown argument: \`$1'" >&2
                        echo "${usage_message[branch_list]}" >&2
                        return 1
                        ;;
                esac
            done

            local total_width
            total_width="$(( c_branch_width + c_author_width + c_date_width + 3 ))"

            if [ "$total_width" -gt "$WIDTH_OF_WINDOW" ]; then
                c_show_author=false
                total_width="$(( total_width - c_author_width ))"
            fi

            if [ "$total_width" -gt "$WIDTH_OF_WINDOW" ]; then
                c_show_date=false
                total_width="$(( total_width - c_date_width ))"
            fi

            # Calculate spacers
            local spacer num_spacers=2
            spacer="$(
                echo "$WIDTH_OF_WINDOW $total_width $num_spacers" | \
                    awk '{printf("%.0f", ($1 - $2) / $3)}'
            )"
            if [ "$spacer" -lt 0 ]; then
                spacer=0
            else
                spacer=$(( spacer < 4 ? spacer : 4 ))
            fi

            local branch branch_name author_name author_date
            while IFS= read -r branch; do
                branch="${branch%%:*}"
                branch_name="$branch"
                if [[ "$branch" == refs/heads/* ]]; then
                    # Remove first two segments of the reference name for local branches
                    branch_name="${branch_name#*/}"
                    branch_name="${branch_name#*/}"
                elif [[ "$branch" == refs/remotes/* ]]; then
                    # Remove the first segment of the reference name for remote branches
                    branch_name="${branch_name#*/}"
                fi
                # Adjust the branch name column width based on the number of color code characters
                printf "%-$(( c_branch_width + 13 ))b" "[${col_y_bold}${branch_name}${col_reset}]"
                if "$c_show_author"; then
                    author_name="${c_branch_author_map["$branch"]}"
                    printf \
                        "%${spacer}s${col_g}%-${c_author_width}s${col_reset}" " " "$author_name"
                fi
                if "$c_show_date"; then
                    author_date="${c_branch_date_map["$branch"]}"
                    printf "%${spacer}s(${col_b}%s${col_reset})\n" " " "$author_date"
                fi
            done <<< "$c_branches"
        }


        __fgb_branch_manage() {
            # Manage Git branches

            local force
            while [ $# -gt 0 ]; do
                case "$1" in
                    -f | --force)
                        force="--force"
                        ;;
                    -h | --help)
                        echo "${usage_message[branch_manage]}"
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[branch_manage]}" >&2
                        return 1
                        ;;
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            local del_key="ctrl-d" info_key="ctrl-o"
            local header="Manage Git Branches:"
            header+=" ctrl-y:jump, ctrl-t:toggle, $del_key:delete, $info_key:info"
            local fzf_cmd="\
                $FZF_CMD_GLOB \
                    --expect='"$del_key,$info_key"' \
                    --header '$header' \
                "

            if [[ "${#positional_args[@]}" -gt 0 ]]; then
                fzf_cmd+=" --query='${positional_args[*]}'"
            fi

            local lines; lines="$(__fgb_branch_list | eval "$fzf_cmd" | cut -d' ' -f1)"

            if [[ -z "$lines" ]]; then
                return
            fi

            local key; key=$(head -1 <<< "$lines")

            # Remove brackets
            # shellcheck disable=SC2001
            lines="$(sed 's/^.\(.*\).$/\1/' <<< "$lines")"

            case $key in
                "$del_key") __fgb_git_branch_delete "$(sed 1d <<< "$lines")" "$force" ;;
                "$info_key")
                    local branch; branch="$(tail -1 <<< "$lines")"
                    echo -e "branch    : ${col_y_bold}${branch}${col_reset}"
                    echo -e "committer : ${col_g}$(
                        git log -1 --pretty=format:"%cn" "$branch"
                    )${col_reset}"
                    echo -e "date      : ${col_b}$(
                        git log -1 --format="%cd" --date=relative "$branch"
                    )${col_reset}"
                    echo -e "HEAD      : ${col_m}$(git rev-parse "$branch")${col_reset}"
                    ;;
                *)
                    if ! git rev-parse --show-toplevel &>/dev/null; then
                        echo "Not inside a Git worktree. Exit..." >&2
                        return 128
                    fi
                    local branch_name; branch_name="$(tail -1 <<< "$lines")"
                    if [[ "$branch_name" == remotes/*/* ]]; then
                        # Remove first two segments of the reference name (remotes/<upstream>/)
                        branch_name="${branch_name#*/}"
                        branch_name="${branch_name#*/}"
                    fi
                    git switch "$branch_name"
                    ;;
            esac
        }


        __fgb_branch() {
            # Manage Git branches

            local subcommand="$1" branch_list_args=() other_args=()
            shift

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --sort=*)
                        branch_list_args+=("$1")
                        ;;
                    -r | --remotes | -a | --all)
                        branch_list_args+=("$1")
                        ;;
                    *)
                        other_args+=("$1")
                        ;;
                esac
                shift
            done

            case $subcommand in
                list | manage)
                    if ! git rev-parse --git-dir &>/dev/null; then
                        echo "Not inside a Git repository. Exit..." >&2
                        return 128
                    fi
                    c_branches="$(__fgb_git_branch_list "${branch_list_args[@]}")"
                    __fgb_branch_set_vars "$c_branches"
                    case $subcommand in
                        list) __fgb_branch_list "${other_args[@]}" ;;
                        manage) __fgb_branch_manage "${other_args[@]}" ;;
                    esac
                    ;;
                -h | --help)
                    echo "${usage_message[branch]}"
                    ;;
                --* | -*)
                    echo "error: unknown option: \`$subcommand'" >&2
                    echo "${usage_message[branch]}" >&2
                    return 1
                    ;;
                *)
                    echo "error: unknown subcommand: \`$subcommand'" >&2
                    echo "${usage_message[branch]}" >&2
                    return 1
                    ;;
            esac
        }


        __fgb_git_worktree_delete() {
            # Delete a Git worktree for a given branch

            local force=false
            local positional_args=()
            while [ $# -gt 0 ]; do
                case "$1" in
                    -f | --force)
                        force=true
                        ;;
                    "") ;; # Skip empty arguments
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if [ "${#positional_args[@]}" -eq 0 ]; then
                echo "$0: Missing argument: list of branches" >&2
                return 1
            fi

            local \
                branch_name \
                error_pattern \
                is_in_target_wt=false \
                output \
                success_message \
                user_prompt \
                worktrees_to_delete="${positional_args[*]}" \
                wt_path
            local -a array_of_lines
            if [[ -n "${ZSH_VERSION-}" ]]; then
                # shellcheck disable=SC2116,SC2296
                array_of_lines=("${(f@)$(echo "$worktrees_to_delete")}")
            else
                local line
                while IFS= read -r line; do
                    array_of_lines+=( "$line" )
                done <<< "$worktrees_to_delete"
            fi
            for branch_name in "${array_of_lines[@]}"; do
                if [[ "$branch_name" == remotes/*/* ]]; then
                    # Remove first two segments of the reference name (remotes/<upstream>/)
                    branch_name="${branch_name#*/}"
                    branch_name="${branch_name#*/}"
                fi
                wt_path="${c_worktree_path_map["refs/heads/${branch_name}"]}"
                if [[ -n "$wt_path" ]]; then
                    # Process a branch with a corresponding worktree
                    is_in_target_wt=false
                    if [[ "$PWD" == "$wt_path" ]]; then
                        cd "$c_bare_repo_path" && is_in_target_wt=true || return 1
                    fi
                    user_prompt=$(__fgb_stdout_unindented "
                        |${col_r_bold}Delete${col_reset} worktree: \#
                        |${col_y_bold}${wt_path}${col_reset}, \#
                        |for branch '${col_b_bold}${branch_name}${col_reset}'?
                    ")
                    if "$force" || __fgb_confirmation_dialog "$user_prompt"; then
                        success_message=$(__fgb_stdout_unindented "
                            |${col_g_bold}Deleted${col_reset} worktree: \#
                            |${col_y_bold}${wt_path}${col_reset} \#
                            |for branch '${col_b_bold}${branch_name}${col_reset}'
                        ")
                        if ! output="$(git worktree remove "$wt_path" 2>&1)"; then
                            error_pattern="^fatal: .* contains modified or untracked files,"
                            error_pattern+=" use --force to delete it$"
                            if ! grep -q "$error_pattern" <<< "$output"; then
                                echo "$output"
                                continue
                            fi
                            user_prompt=$(__fgb_stdout_unindented "
                                |
                                |${col_r_bold}WARNING:${col_reset} \#
                                |This will permanently reset/delete the following files:
                                |
                                |$(script -q /dev/null -c "git -C \"$wt_path\" status --short")
                                |
                                |in the ${col_y_bold}${wt_path}${col_reset} path.
                                |
                                |Are you sure you want to proceed?
                            ")
                            # NOTE: Avoid --force here as it's not undoable operation
                            if __fgb_confirmation_dialog "$user_prompt"; then
                                if output="$( git worktree remove "$wt_path" --force)"; then
                                    echo -e "$success_message"
                                else
                                    echo "$output" >&2
                                fi
                                user_prompt=$(__fgb_stdout_unindented "
                                |${col_r_bold}Delete${col_reset} the corresponding \#
                                |'${col_b_bold}${branch_name}${col_reset}' branch as well?
                                ")
                                if __fgb_confirmation_dialog "$user_prompt"; then
                                    __fgb_git_branch_delete "$branch_name" --force
                                fi
                            else
                                if "$is_in_target_wt"; then
                                    cd "$wt_path" || return 1
                                fi
                            fi
                        else
                            if "$force"; then
                                echo -e "$success_message"
                            fi
                            user_prompt=$(__fgb_stdout_unindented "
                                |${col_r_bold}Delete${col_reset} the corresponding \#
                                |'${col_b_bold}${branch_name}${col_reset}' branch as well?
                            ")
                            if __fgb_confirmation_dialog "$user_prompt"; then
                                __fgb_git_branch_delete "$branch_name" --force
                            fi
                        fi
                    else
                        if "$is_in_target_wt"; then
                            cd "$wt_path" || return 1
                        fi
                    fi
                else
                    # Process a branch that doesn't have a corresponding worktree
                    "$force" && force="--force" || force=""
                    __fgb_git_branch_delete "$branch_name" "$force"
                fi
            done
        }


        __fgb_git_worktree_jump_or_add() {
            # Jump to an existing worktree or add a new one for a given branch

            if [ $# -eq 0 ]; then
                echo "Missing argument: branch name" >&2
                return 1
            fi

            local branch_name="$1" confirm="${2:-false}" remote_branch=
            if [[ "$branch_name" == remotes/*/* ]]; then
                # Remove first two segments of the reference name (remotes/<upstream>/)
                branch_name="${branch_name#*/}"
                remote_branch="$branch_name"
                branch_name="${branch_name#*/}"
            fi
            local wt_path
            wt_path="$(git worktree list | grep " \[${branch_name}\]$" | cut -d' ' -f1)"
            local message
            if [[ -n "$wt_path" ]]; then
                if cd "$wt_path"; then
                    message=$(__fgb_stdout_unindented "
                        |${col_g_bold}Jumped${col_reset} to worktree: \#
                        |${col_y_bold}${wt_path}${col_reset}, \#
                        |for branch '${col_b_bold}${branch_name}${col_reset}'
                    ")
                    echo -e "$message"
                else
                    return 1
                fi
            else
                if "$confirm"; then
                    wt_path="${c_bare_repo_path}/${branch_name}"
                else
                    if [[ -n "$remote_branch" ]]; then
                        printf "%b\n" "$(__fgb_stdout_unindented "
                        |Add a new worktree for '${col_b_bold}${branch_name}${col_reset}' \#
                        |(remote branch: '${col_y_bold}${remote_branch}${col_reset}').
                        |The path to the worktree must be absolute \#
                        |or relative to the path to the bare repository.
                        ")"
                    else
                        printf "%b\n" "$(__fgb_stdout_unindented "
                        |Add a new worktree for '${col_b_bold}${branch_name}${col_reset}'.
                        |The path to the worktree must be absolute \#
                        |or relative to the path to the bare repository.
                        ")"
                    fi
                    message="Enter the path: "
                    wt_path=""
                    wt_path="$branch_name"
                    if [[ -n "${ZSH_VERSION-}" ]]; then
                        vared -p "$message" wt_path
                    else
                        IFS= read -re -p "$message" -i "$wt_path" wt_path
                    fi
                    if [[ "$wt_path" != /* ]]; then
                        wt_path="${c_bare_repo_path}/${wt_path}" # Relative path provided
                    fi
                    wt_path="$(readlink -m "$wt_path")" # Normalize the path
                fi
                if git worktree add "$wt_path" "$branch_name"; then
                    cd "$wt_path" || return 1
                    message=$(__fgb_stdout_unindented "
                        |Worktree ${col_y_bold}${wt_path}${col_reset} \#
                        |for branch '${col_b_bold}${branch_name}${col_reset}' added successfully.
                        |${col_g_bold}Jumped${col_reset} there.
                    ")
                    echo -e "$message"
                fi
            fi
        }


        __fgb_worktree_list() {
            # List worktrees in a git repository

            local branch_list_args=()

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --sort=*)
                        branch_list_args+=("$1")
                        ;;
                    --filter)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --filter=*)
                        branch_list_args+=("$1")
                        ;;
                    -r | --remotes | -a | --all)
                        branch_list_args+=("$1")
                        ;;
                    -h | --help)
                        echo "${usage_message[worktree_list]}"
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[worktree_list]}" >&2
                        return 1
                        ;;
                    *)
                        echo "error: unknown argument: \`$1'" >&2
                        echo "${usage_message[worktree_list]}" >&2
                        return 1
                        ;;
                esac
                shift
            done

            if ! (git worktree list | grep -q " (bare)$") &>/dev/null; then
                echo "Not inside a bare Git repository. Exit..." >&2
                return 128
            fi

            local sorted_branches_list
            if ! sorted_branches_list="$(__fgb_git_branch_list "${branch_list_args[@]}")"; then
                echo -e "$sorted_branches_list" >&2
                return 1
            fi

            local total_width
            total_width="$((
                    c_branch_width + c_wt_path_width + c_author_width + c_date_width + 3
            ))"

            if [ "$total_width" -gt "$WIDTH_OF_WINDOW" ]; then
                c_show_wt_path=false
                c_show_wt_flag=true
                total_width="$(( total_width - c_wt_path_width + 1 ))"
            fi

            if [ "$total_width" -gt "$WIDTH_OF_WINDOW" ]; then
                c_show_author=false
                total_width="$(( total_width - c_author_width ))"
            fi

            if [ "$total_width" -gt "$WIDTH_OF_WINDOW" ]; then
                c_show_date=false
                total_width="$(( total_width - c_date_width ))"
            fi

            # Calculate spacers
            local spacer num_spacers=3
            if "$c_show_wt_flag"; then
                num_spacers="$(( num_spacers + 1 ))"
                total_width="$(( total_width + 2 ))"
            fi
            spacer="$(
                echo "$WIDTH_OF_WINDOW $total_width $num_spacers" | \
                    awk '{printf("%.0f", ($1 - $2) / $3)}'
            )"
            if [ "$spacer" -lt 0 ]; then
                spacer=0
            else
                spacer=$(( spacer < 4 ? spacer : 4 ))
            fi

            local branch wt_path author_name author_date
            while IFS= read -r branch; do
                branch="${branch%%:*}"
                branch_name="$branch"
                if [[ "$branch" == refs/heads/* ]]; then
                    # Remove first two segments of the reference name for local branches
                    branch_name="${branch_name#*/}"
                    branch_name="${branch_name#*/}"
                elif [[ "$branch" == refs/remotes/* ]]; then
                    # Remove the first segment of the reference name for remote branches
                    branch_name="${branch_name#*/}"
                fi
                # Adjust the branch name column width based on the number of color code characters
                printf "%-$(( c_branch_width + 13 ))b" "[${col_y_bold}${branch_name}${col_reset}]"
                if "$c_show_wt_path"; then
                    if [[ -n "${c_worktree_path_map["$branch"]}" ]]; then
                        wt_path="${c_worktree_path_map["$branch"]}"
                        wt_path="$(realpath --relative-to="$c_bare_repo_path" "$wt_path")"
                        if [[ ! "$wt_path" =~ ^\.\./ ]]; then
                            wt_path="./$wt_path"
                        fi
                    else
                        wt_path=" "
                    fi
                    printf \
                        "%${spacer}s${col_bold}%-${c_wt_path_width}s${col_reset}" \
                        " " \
                        "$wt_path"
                fi
                if "$c_show_wt_flag"; then
                    if [[ -n "${c_worktree_path_map["$branch"]}" ]]; then
                        wt_path="+"
                    else
                        wt_path=" "
                    fi
                    printf "%${spacer}s${col_bold}%s${col_reset}" " " "$wt_path"
                fi
                if "$c_show_author"; then
                    author_name="${c_branch_author_map["$branch"]}"
                    printf \
                        "%${spacer}s${col_g}%-${c_author_width}s${col_reset}" " " "$author_name"
                fi
                if "$c_show_date"; then
                    author_date="${c_branch_date_map["$branch"]}"
                    printf "%${spacer}s(${col_b}%s${col_reset})\n" " " "$author_date"
                fi
            done <<< "$sorted_branches_list"
        }


        __fgb_worktree_add() {
            # Add a new worktree for a given branch

            local branch_list_args=() positional_args=() confirm force

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --sort=*)
                        branch_list_args+=("$1")
                        ;;
                    -r | --remotes | -a | --all)
                        branch_list_args+=("$1")
                        ;;
                    -c | --confirm)
                        confirm=true
                        ;;
                    -f | --force)
                        force="--force"
                        ;;
                    -h | --help)
                        echo "${usage_message[worktree_add]}"
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[worktree_add]}" >&2
                        return 1
                        ;;
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if ! (git worktree list | grep -q " (bare)$") &>/dev/null; then
                echo "Not inside a bare Git repository. Exit..." >&2
                return 128
            fi

            local branches
            if ! branches="$(__fgb_git_branch_list "${branch_list_args[@]}")"; then
                echo -e "$branches" >&2
                return 1
            fi

            local line branch upstream wt_branch
            c_branches="$(while IFS= read -r line; do
                    branch="${line%%:*}"
                    if grep -q -E "${branch}$" <<< "$c_worktree_branches"; then
                        continue
                    fi
                    if [[ "$branch" == refs/remotes/* ]]; then
                        while IFS= read -r wt_branch; do
                            upstream="$(
                                git \
                                    for-each-ref \
                                    --format \
                                    '%(upstream)' "$wt_branch"
                            )"
                            if [[ "$branch" == "$upstream" ]]; then
                                continue 2
                            fi
                        done <<< "$c_worktree_branches"
                    fi
                    echo "$line"
            done <<< "$branches")"

            __fgb_branch_set_vars "$c_branches"

            local del_key="ctrl-d" info_key="ctrl-o" verbose_key="ctrl-v"
            local header="Add a Git Worktree:"
            header+=" ctrl-y:jump, ctrl-t:toggle, $del_key:delete, $info_key:info"
            header+=" $verbose_key:verbose"
            local fzf_cmd="\
                $FZF_CMD_GLOB \
                    --expect='"$del_key,$info_key,$verbose_key"' \
                    --header '$header' \
                "

            if [[ "${#positional_args[@]}" -gt 0 ]]; then
                fzf_cmd+=" --query='${positional_args[*]}'"
            fi

            local lines; lines="$(
                __fgb_branch_list | \
                    eval "$fzf_cmd" | \
                    cut -d' ' -f1
            )"

            if [[ -z "$lines" ]]; then
                return
            fi

            local key; key=$(head -1 <<< "$lines")

            # Remove brackets
            # shellcheck disable=SC2001
            lines="$(sed 's/^.\(.*\).$/\1/' <<< "$lines")"

            case $key in
                "$del_key") __fgb_git_branch_delete "$(sed 1d <<< "$lines")" "$force" ;;
                "$info_key")
                    branch="$(tail -1 <<< "$lines")"
                    echo -e "branch    : ${col_y_bold}${branch}${col_reset}"
                    echo -e "committer : ${col_g}$(
                        git log -1 --pretty=format:"%cn" "$branch"
                    )${col_reset}"
                    echo -e "date      : ${col_b}$(
                        git log -1 --format="%cd" --date=relative "$branch"
                    )${col_reset}"
                    echo -e "HEAD      : ${col_m}$(git rev-parse "$branch")${col_reset}"
                    ;;
                "$verbose_key") __fgb_git_worktree_jump_or_add "$(tail -1 <<< "$lines")" ;;
                *) __fgb_git_worktree_jump_or_add "$(tail -1 <<< "$lines")" "$confirm" ;;
            esac
        }


        __fgb_worktree_total() {
            # Manage Git worktrees

            local branch_list_args=() positional_args=()

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --sort=*)
                        branch_list_args+=("$1")
                        ;;
                    -r | --remotes | -a | --all)
                        branch_list_args+=("$1")
                        ;;
                    -c | --confirm)
                        confirm=true
                        ;;
                    -f | --force)
                        force="--force"
                        ;;
                    -h | --help)
                        echo "${usage_message[worktree_total]}"
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[worktree_total]}" >&2
                        return 1
                        ;;
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if ! (git worktree list | grep -q " (bare)$") &>/dev/null; then
                echo "Not inside a bare Git repository. Exit..." >&2
                return 128
            fi

            if ! c_branches="$(__fgb_git_branch_list "${branch_list_args[@]}")"; then
                echo -e "$c_branches" >&2
                return 1
            fi

            __fgb_branch_set_vars "$c_branches"

            local del_key="ctrl-d" info_key="ctrl-o" verbose_key="ctrl-v"
            local header="Manage Git Worktrees (total):"
            header+=" ctrl-y:jump, ctrl-t:toggle, $del_key:delete, $info_key:info"
            header+=" $verbose_key:verbose"
            local fzf_cmd="\
                $FZF_CMD_GLOB \
                    --expect='"$del_key,$info_key,$verbose_key"' \
                    --header '$header' \
                "

            if [[ "${#positional_args[@]}" -gt 0 ]]; then
                fzf_cmd+=" --query='${positional_args[*]}'"
            fi

            local lines; lines="$(
                __fgb_worktree_list "${branch_list_args[@]}" | \
                    eval "$fzf_cmd" | \
                    cut -d' ' -f1
            )"

            if [[ -z "$lines" ]]; then
                return
            fi

            local key; key=$(head -1 <<< "$lines")

            # Remove brackets
            # shellcheck disable=SC2001
            lines="$(sed 's/^.\(.*\).$/\1/' <<< "$lines")"

            case $key in
                "$del_key") __fgb_git_worktree_delete "$(sed 1d <<< "$lines")" "$force" ;;
                "$info_key")
                    local branch; branch="$(tail -1 <<< "$lines")"
                    echo -e "branch    : ${col_y_bold}${branch}${col_reset}"
                    local wt_path; wt_path="${c_worktree_path_map["refs/heads/${branch}"]}"
                    if [[ -n "$wt_path" ]]; then
                        echo -e "worktree  : ${col_bold}$wt_path${col_reset}"
                    fi
                    echo -e "committer : ${col_g}$(
                        git log -1 --pretty=format:"%cn" "$branch"
                    )${col_reset}"
                    echo -e "date      : ${col_b}$(
                        git log -1 --format="%cd" --date=relative "$branch"
                    )${col_reset}"
                    echo -e "HEAD      : ${col_m}$(git rev-parse "$branch")${col_reset}"
                    ;;
                "$verbose_key") __fgb_git_worktree_jump_or_add "$(tail -1 <<< "$lines")" ;;
                *) __fgb_git_worktree_jump_or_add "$(tail -1 <<< "$lines")" "$confirm" ;;
            esac
        }


        __fgb_worktree_manage() {
            # Manage Git worktrees

            local branch_list_args=() positional_args=() force

            while [ $# -gt 0 ]; do
                case "$1" in
                    -f | --force)
                        force="--force"
                        ;;
                    -s | --sort)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --sort=*)
                        branch_list_args+=("$1")
                        ;;
                    --filter)
                        branch_list_args+=("$1")
                        shift
                        branch_list_args+=("$1")
                        ;;
                    --filter=*)
                        branch_list_args+=("$1")
                        ;;
                    -h | --help)
                        echo "${usage_message[worktree_manage]}"
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[worktree_manage]}" >&2
                        return 1
                        ;;
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if ! (git worktree list | grep -q " (bare)$") &>/dev/null; then
                echo "Not inside a bare Git repository. Exit..." >&2
                return 128
            fi

            local del_key="ctrl-d" info_key="ctrl-o"
            local header="Manage Git Worktrees:"
            header+=" ctrl-y:jump, ctrl-t:toggle, $del_key:delete, $info_key:info"
            local fzf_cmd="\
                $FZF_CMD_GLOB \
                    --expect='"$del_key,$info_key"' \
                    --header '$header' \
                "

            if [[ "${#positional_args[@]}" -gt 0 ]]; then
                fzf_cmd+=" --query='${positional_args[*]}'"
            fi

            local lines; lines="$(
                __fgb_worktree_list "${branch_list_args[@]}" | \
                    eval "$fzf_cmd" | \
                    cut -d' ' -f1
            )"

            if [[ -z "$lines" ]]; then
                return
            fi

            local key; key=$(head -1 <<< "$lines")

            # Remove brackets
            # shellcheck disable=SC2001
            lines="$(sed 's/^.\(.*\).$/\1/' <<< "$lines")"

            case $key in
                "$del_key") __fgb_git_worktree_delete "$(sed 1d <<< "$lines")" "$force" ;;
                "$info_key")
                    local branch; branch="$(tail -1 <<< "$lines")"
                    echo -e "branch    : ${col_y_bold}${branch}${col_reset}"
                    local wt_path; wt_path="${c_worktree_path_map["refs/heads/${branch}"]}"
                    echo -e "worktree  : ${col_bold}$wt_path${col_reset}"
                    echo -e "committer : ${col_g}$(
                        git log -1 --pretty=format:"%cn" "$branch"
                    )${col_reset}"
                    echo -e "date      : ${col_b}$(
                        git log -1 --format="%cd" --date=relative "$branch"
                    )${col_reset}"
                    echo -e "HEAD      : ${col_m}$(git rev-parse "$branch")${col_reset}"
                    ;;
                *) __fgb_git_worktree_jump_or_add "$(tail -1 <<< "$lines")" ;;
            esac
        }


        __fgb_worktree_set_vars() {
            # Define worktree related variables

            if ! (git worktree list | grep -q " (bare)$") &>/dev/null; then
                echo "Not inside a bare Git repository. Exit..." >&2
                return 128
            fi

            c_bare_repo_path="$(
                git worktree list | \
                    grep " (bare)$" | \
                    rev | \
                    cut -d' ' -f2- | \
                    sed 's/^[[:space:]]*//' | \
                    rev
            )"

            local wt_list; wt_list="$(git worktree list | sed '1d')"

            # Remove brackets from the branch names (3rd column in the output) using sed
            c_worktree_branches="$(
                rev <<< "$wt_list" | cut -d' ' -f1 | rev | sed 's|^.\(.*\).$|\1|;s|^|refs/heads/|'
            )"

            __fgb_branch_set_vars "$c_worktree_branches"

            local \
                branch \
                line \
                wt_path \
                wt_path_curr_width
            while IFS= read -r line; do
                branch="$(
                    rev <<< "$line" | cut -d' ' -f1 | rev | sed 's|^.\(.*\).$|\1|;s|^|refs/heads/|'
                )"
                c_worktree_path_map["$branch"]="$(
                    rev <<< "$line" | cut -d' ' -f3- | sed 's/^[[:space:]]*//' | rev
                )"
                # Calculate column widths
                wt_path="${c_worktree_path_map["$branch"]}"
                wt_path="$(realpath --relative-to="$c_bare_repo_path" "$wt_path")"
                if [[ ! "$wt_path" =~ ^\.\./ ]]; then
                    wt_path="./$wt_path"
                fi
                wt_path_curr_width="${#wt_path}"
                c_wt_path_width="$((
                        wt_path_curr_width > c_wt_path_width ?
                        wt_path_curr_width :
                        c_wt_path_width
                ))"
            done <<< "$wt_list"
        }


        __fgb_worktree() {
            # Manage Git worktrees

            local subcommand="$1"
            shift
            case $subcommand in
                list | manage)
                    __fgb_worktree_set_vars || return $?

                    local positional_args=()
                    while [ $# -gt 0 ]; do
                        case "$1" in
                            --filter | --filter=* | -r | --remotes | -a | --all | -c | --confirm)
                                echo "error: unknown option: \`$1'" >&2
                                echo "${usage_message[worktree_$subcommand]}" >&2
                                return 1
                                ;;
                            *)
                                positional_args+=("$1")
                                ;;
                        esac
                        shift
                    done
                    case "$subcommand" in
                        list)
                            __fgb_worktree_list \
                                "${positional_args[@]}" \
                                --filter="$c_worktree_branches"
                            ;;
                        manage)
                            __fgb_worktree_manage \
                                "${positional_args[@]}" \
                                --filter="$c_worktree_branches"
                            ;;
                    esac
                    ;;
                add)
                    __fgb_worktree_set_vars || return $?
                    __fgb_worktree_add "$@"
                    ;;
                total)
                    __fgb_worktree_set_vars || return $?
                    __fgb_worktree_total "$@"
                    ;;
                -h | --help)
                    echo "${usage_message[worktree]}"
                    ;;
                --* | -*)
                    echo "error: unknown option: \`$subcommand'" >&2
                    echo "${usage_message[worktree]}" >&2
                    return 1
                    ;;
                *)
                    echo "error: unknown subcommand: \`$subcommand'" >&2
                    echo "${usage_message[worktree]}" >&2
                    return 1
                    ;;
            esac
        }


        # Declare "global" (commonly used) variables
        local \
            col_reset='\033[0m' \
            col_g='\033[32m' \
            col_b='\033[34m' \
            col_m='\033[35m' \
            col_bold='\033[1m' \
            col_r_bold='\033[1;31m' \
            col_g_bold='\033[1;32m' \
            col_y_bold='\033[1;33m' \
            col_b_bold='\033[1;34m' \
            c_bare_repo_path \
            c_branches="" \
            c_branch_width=0 \
            c_author_width=0 \
            c_worktree_branches="" \
            c_wt_path_width=0 \
            c_show_author=true \
            c_show_date=true \
            c_show_wt_flag=false \
            c_show_wt_path=true \
            c_date_width=17 # Example: (99 minutes ago)

        local -A \
            c_branch_author_map \
            c_branch_date_map \
            c_worktree_path_map

        # Define messages
        local version_message="fzf-git-branches, version $VERSION\n"
        local copyright_message
        copyright_message=$(__fgb_stdout_unindented "
            |Copyright (C) 2024 Andrei Bulgakov <https://github.com/awerebea>.

            |License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
            |This is free software; you are free to change and redistribute it.
            |There is NO WARRANTY, to the extent permitted by law.
        ")

        local -A usage_message=(
            ["fgb"]="$(__fgb_stdout_unindented "
            |Usage: fgb <command> [<args>]
            |
            |Commands:
            |  branch    Manage branches in a git repository
            |
            |  worktree  Manage worktrees in a git repository
            |
            |Options:
            |  -v, --version
            |            Show version information
            |
            |  -h, --help
            |            Show help message
            ")"

            ["branch"]="$(__fgb_stdout_unindented "
            |Usage: fgb branch <subcommand> [<args>]
            |
            |Subcommands:
            |  list    List branches in a git repository
            |
            |  manage  Switch to existing branches in the git repository or delete them
            |
            |Options:
            |  -h, --help
            |          Show help message
            ")"

            ["branch_list"]="$(__fgb_stdout_unindented "
            |Usage: fgb branch list [<args>]
            |
            |List branches in a git repository
            |
            |Options:
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            refname (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  -a, --all
            |          List all branches
            |
            |  -h, --help
            |          Show help message
            ")"

            ["branch_manage"]="$(__fgb_stdout_unindented "
            |Usage: fgb branch manage [<args>] [<query>]
            |
            |Switch to existing branches in the git repository or delete them
            |
            |Query:
            |  <query>  Query to filter branches by using fzf
            |
            |Options:
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            -committerdate (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  -a, --all
            |          List all branches
            |
            |  -f, --force
            |          Suppress confirmation dialog for non-dangerous operations
            |
            |  -h, --help
            |          Show help message
            ")"

            ["worktree"]="$(__fgb_stdout_unindented "
            |Usage: fgb worktree <subcommand> [<args>]
            |
            |Subcommands:
            |  list    List all worktrees in a bare git repository
            |
            |  manage  Switch to existing worktrees in the baregit repository or delete them
            |
            |  add     Add a new worktree based on a selected git branch
            |
            |  total   Add a new one, switch to an existing worktree in the bare git repository,
            |          or delete them, optionally with corresponding branches
            |
            |Options:
            |  -h, --help
            |          Show help message
            ")"

            ["worktree_list"]="$(__fgb_stdout_unindented "
            |Usage: fgb worktree list [<args>]
            |
            |List all worktrees in a bare git repository
            |
            |Options:
            |  -s, --sort=<sort>
            |          Sort worktrees by <sort>:
            |            -committerdate (default)
            |
            |  -h, --help
            |          Show help message
            ")"

            ["worktree_manage"]="$(__fgb_stdout_unindented "
            |Usage: fgb worktree manage [<args>] [<query>]
            |
            |Switch to existing worktrees in the bare git repository or delete them
            |
            |Query:
            |  <query>  Query to filter branches by using fzf
            |
            |Options:
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            -committerdate (default)
            |
            |  -f, --force
            |          Suppress confirmation dialog for non-dangerous operations
            |
            |  -h, --help
            |          Show help message
            ")"

            ["worktree_add"]="$(__fgb_stdout_unindented "
            |Usage: fgb worktree add [<args>] [<query>]
            |
            |Add a new worktree based on a selected git branch
            |
            |Query:
            |  <query>  Query to filter branches by using fzf
            |
            |Options:
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            -committerdate (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  -a, --all
            |          List all branches
            |
            |  -c, --confirm
            |          Automatic confirmation of the directory name for the new worktree
            |
            |  -f, --force
            |          Suppress confirmation dialog for non-dangerous operations
            |
            |  -h, --help
            |          Show help message
            ")"

            ["worktree_total"]="$(__fgb_stdout_unindented "
            |Usage: fgb worktree total [<args>] [<query>]
            |
            |Add a new one, switch to an existing worktree in the bare git repository, \#
            |or delete them, optionally with corresponding branches
            |
            |Query:
            |  <query>  Query to filter branches by using fzf
            |
            |Options:
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            -committerdate (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  -a, --all
            |          List all branches
            |
            |  -c, --confirm
            |          Automatic confirmation of the directory name for the new worktree
            |
            |  -f, --force
            |          Suppress confirmation dialog for non-dangerous operations
            |
            |  -h, --help
            |          Show help message
            ")"
        )

        # Define command and adjust arguments
        local fgb_command="${1:-}"
        shift
        local fgb_subcommand="${1:-}"

        local WIDTH_OF_WINDOW; WIDTH_OF_WINDOW=$(tput cols)

        case "$fgb_command" in
            branch)
                case "$fgb_subcommand" in
                    "") echo -e "error: need a subcommand" >&2
                        echo "${usage_message[$fgb_command]}" >&2
                        return 1
                        ;;
                    *) __fgb_branch "$@" ;;
                esac
                ;;
            worktree)
                case "$fgb_subcommand" in
                    "") echo -e "error: need a subcommand" >&2
                        echo "${usage_message[$fgb_command]}" >&2
                        return 1
                        ;;
                    *) __fgb_worktree "$@" ;;
                esac
                ;;
            -h | --help)
                echo "${usage_message[fgb]}"
                ;;
            -v | --version)
                echo "$version_message"
                echo "$copyright_message"
                ;;
            --* | -*)
                echo "error: unknown option: \`$fgb_command'" >&2
                echo "${usage_message[fgb]}" >&2
                return 1
                ;;
            "")
                echo "${usage_message[fgb]}" >&2
                return 1
                ;;
            *)
                echo "fgb: '$fgb_command' is not a fgb command. See 'fgb --help'." >&2
                return 1
                ;;
        esac
    }

    # Start here
    __fgb__functions "$@"
    local exit_code="$?"

    unset -f \
        __fgb__functions \
        __fgb_branch \
        __fgb_branch_list \
        __fgb_branch_manage \
        __fgb_branch_set_vars \
        __fgb_confirmation_dialog \
        __fgb_git_branch_delete \
        __fgb_git_branch_list \
        __fgb_git_worktree_delete \
        __fgb_git_worktree_jump_or_add \
        __fgb_stdout_unindented \
        __fgb_worktree \
        __fgb_worktree_add \
        __fgb_worktree_list \
        __fgb_worktree_manage \
        __fgb_worktree_total \
        __fgb_worktree_set_vars

    return "$exit_code"
}
