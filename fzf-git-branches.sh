# Description: Manage Git branches and worktrees with fzf

command -v fzf >/dev/null 2>&1 || return

fgb() {
    local VERSION="0.2.0"

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
            --select-1 \
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
            local read_cmd ANS
            if [[ -n "${ZSH_VERSION-}" ]]; then
                read_cmd="read -k 1 ANS"
            else
                read_cmd="read -n 1 ANS"
            fi

            echo -en "$user_prompt (y|N): "
            eval "$read_cmd"
            echo # Move to the next line for a cleaner output

            case "$ANS" in
                [yY]) return 0 ;;
                *) return 1 ;;
            esac
        }


        __fgb_get_bare_repo_path() {
            # Get the path to the bare repository
            git worktree list --porcelain | \
                grep -E -B 2 "^bare$" | \
                grep -E "^worktree" | \
                cut -d " " -f 2
        }


        __fgb_get_list_of_worktrees() {
            # Get a list of worktrees
            git worktree list --porcelain | \
                grep -E "^branch refs/heads/" | \
                sed "s|branch refs/heads/||"
        }


        __fgb_is_positive_int_or_float() {
            # Check if the argument is a positive integer or a floating-point number
            if [[ $# -eq 0 ]]; then
                return 1
            fi
            local multiplier="$1"
            if [[ "$multiplier" =~ ^[0-9]+$ ]]; then
                return 0
            elif [[ "$multiplier" =~ ^[0-9]+\.[0-9]+$ ]]; then
                return 0
            else
                return 1
            fi
        }


        __fgb_get_segment_width_relative_to_window() {
            # Calculate the width of a segment relative to the width of the terminal window

            if [[ $# -eq 0 ]] || ! __fgb_is_positive_int_or_float "$1"; then
                echo "25"
                return
            else
                local multiplier; multiplier="$1"
            fi
            local width_of_window; width_of_window=$(tput cols)
            # Extract the width of the age column
            local available_width; available_width=$(( width_of_window - 5 ))
            echo "$available_width $multiplier" | awk '{printf("%.0f", $1 * $2)}'
        }


        __fgb_get_worktree_path_for_branch() {
            # Get the path to the worktree for a given branch

            if [ $# -eq 0 ]; then
                echo "Missing argument: branch name"
                return 1
            fi
            local branch_name="$1"
            local worktrees; worktrees="$(__fgb_get_list_of_worktrees)"
            local exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
            while IFS= read -r line; do
                if [[ "$line" == "$branch_name" ]]; then
                    git worktree list --porcelain | \
                        grep -E -B 2 "^branch refs/heads/${branch_name}$" | \
                        grep -E "^worktree" | \
                        cut -d " " -f 2
                fi
            done <<< "$worktrees"
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
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if [ "${#positional_args[@]}" -eq 0 ]; then
                echo "$0: Missing argument: list of branches"
                return 1
            fi

            local branch_name is_remote remote_name user_prompt exit_code
            local branches_to_delete="${positional_args[*]}"
            while IFS='' read -r branch_name; do
                is_remote=false

                if [[ "$branch_name" == remotes/*/* ]]; then
                    is_remote=true
                    remote_name="${branch_name#*/}"
                    remote_name="${remote_name%%/*}"
                fi

                if "$is_remote"; then
                    branch_name="${branch_name#remotes/*/}"
                    user_prompt=$(__fgb_stdout_unindented "
                        |${col_r}WARNING:${col_reset} \#
                        |Delete branch: '${col_b}${branch_name}${col_reset}' \#
                        |from remote: ${col_y}${remote_name}${col_reset}?
                    ")
                    # NOTE: Avoid --force here as it's no undoable operation for remote branches
                    if __fgb_confirmation_dialog "$user_prompt"; then
                        git push --delete "$remote_name" "$branch_name"
                        exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
                    fi
                else
                    user_prompt="${col_r}Delete${col_reset} local branch: ${branch_name}?"
                    if "$force" || __fgb_confirmation_dialog "$user_prompt"; then
                        local output
                        if ! output="$(git branch -d "$branch_name" 2>&1)"; then
                            local head_branch; head_branch="$(git rev-parse --abbrev-ref HEAD)"
                            echo "$output" >&2
                            if ! grep -q "^error: .* is not fully merged\.$" <<< "$output"; then
                                continue
                            fi
                            user_prompt=$(__fgb_stdout_unindented "

                                |${col_r}WARNING:${col_reset} \#
                                |The branch '${col_b}${branch_name}${col_reset}' \#
                                |is not yet merged into the \#
                                |'${col_g}${head_branch}${col_reset}' branch.

                                |Are you sure you want to delete it?
                            ")
                            # NOTE: Avoid --force here
                            # as it's not clear if intended for non-merged branches
                            if __fgb_confirmation_dialog "$user_prompt"; then
                                git branch -D "$branch_name"
                                exit_code=$?
                                if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
                            fi
                        fi
                    fi
                fi
            done <<< "$branches_to_delete"
        }


        __fgb_branch_list() {
            # List branches in a git repository

            local refname_width=75
            local author_width=40
            local sort_order="refname"
            local filter_list=""
            local list_remote_branches=false
            local list_all_branches=false

            while [ $# -gt 0 ]; do
                case "$1" in
                    --refname-width)
                        shift
                        refname_width="$1"
                        ;;
                    --refname-width=*)
                        refname_width="${1#*=}"
                        ;;
                    --author-width)
                        shift
                        author_width="$1"
                        ;;
                    --author-width=*)
                        author_width="${1#*=}"
                        ;;
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
                    -h | --help)
                        echo "${usage_message[branch_list]}"
                        return
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[branch_list]}" >&2
                        return 1
                        ;;
                    *)
                        echo "$0: Invalid argument: $1"
                        return 1
                        ;;
                esac
                shift
            done

            local num
            for num in "$refname_width" "$author_width"; do
                if ! __fgb_is_positive_int "$num"; then
                    echo "$0: Invalid value for argument: $num"
                    return 1
                fi
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

            local -A type_strip
            type_strip=(
                ["heads"]=2
                ["remotes"]=1
            )

            local ref_type ref_name format_string refs
            for ref_type in "${ref_types[@]}"; do
                format_string=$(__fgb_stdout_unindented "
                    |%(align:width=${refname_width})\#
                    |%(color:bold yellow)%(refname:lstrip=${type_strip[$ref_type]})\#
                    |%(color:reset)%(end) \#
                    |%(align:width=${author_width})\#
                    |%(color:green)%(committername)%(color:reset)%(end) \#
                    |(%(color:blue)%(committerdate:relative)%(color:reset))
                ")
                refs=$(git for-each-ref \
                        --format='%(refname)' \
                        --sort="$sort_order" \
                        refs/"$ref_type"
                )
                if [[ -n "$filter_list" ]]; then
                    filter_list="$(tr ";, " "\n" <<< "$filter_list")"
                    refs=$(grep -E "$filter_list" <<< "$refs")
                fi
                while read -r ref_name; do
                    git for-each-ref --format="$format_string" "$ref_name" --color=always
                done <<< "$refs"
            done
        }


        __fgb_branch_manage() {
            # Manage Git branches

            local sort_order="-committerdate"
            local force=false
            local positional_args=()
            local branch_list_args=()

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        shift
                        sort_order="$1"
                        ;;
                    --sort=*)
                        sort_order="${1#*=}"
                        ;;
                    -a | --all | -r | --remotes)
                        branch_list_args+=("$1")
                        ;;
                    --filter)
                        shift
                        branch_list_args+=("--filter $1")
                        ;;
                    --filter=*)
                        branch_list_args+=("--filter ${1#*=}")
                        ;;
                    -f | --force)
                        force=true
                        ;;
                    -h | --help)
                        echo "${usage_message[branch_manage]}"
                        return
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

            local del_key="ctrl-d"
            local fzf_cmd="\
                $FZF_CMD_GLOB \
                    --expect='$del_key' \
                    --header 'Manage Git Branches: ctrl-y:jump, ctrl-t:toggle, $del_key:delete' \
                "

            if [[ "${#positional_args[@]}" -gt 0 ]]; then
                fzf_cmd+=" --query='${positional_args[*]}'"
            fi

            local branch_list_cmd="\
                __fgb_branch_list \
                    --sort $sort_order \
                    --refname-width '$refname_width' \
                    --author-width '$author_width' \
                    ${branch_list_args[*]} \
                "

            local lines; lines="$(eval "$branch_list_cmd" | eval "$fzf_cmd" | cut -d " " -f 1)"

            if [[ -z "$lines" ]]; then
                return
            fi

            local key; key=$(head -1 <<< "$lines")

            if [[ $key == "$del_key" ]]; then
                if "$force"; then
                    __fgb_git_branch_delete "$(sed 1d <<< "$lines")" --force
                    return $?
                else
                    __fgb_git_branch_delete "$(sed 1d <<< "$lines")"
                    return $?
                fi
            else
                local branch_name; branch_name="$(tail -1 <<< "$lines")"
                if [[ "$branch_name" == remotes/*/* ]]; then
                    # Remove first two components of the reference name (remotes/<upstream>/)
                    branch_name="${branch_name#*/}"
                    branch_name="${branch_name#*/}"
                fi
                git switch "$branch_name"
                return $?
            fi
        }


        __fgb_branch() {
            local subcommand="$1"
            shift
            case $subcommand in
                list)
                    __fgb_branch_list \
                        --refname-width "$refname_width" \
                        --author-width "$author_width" \
                        "$@"
                    ;;
                manage)
                    __fgb_branch_manage "$@"
                    ;;
                -h | --help)
                    echo "${usage_message[branch]}"
                    return
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


        __fgb_is_positive_int() {
            # Check if the argument is a positive integer
            if ! [ "$1" -gt 0 ] 2>/dev/null; then
                return 1
            fi
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
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            if [ "${#positional_args[@]}" -eq 0 ]; then
                echo "$0: Missing argument: list of branches"
                return 1
            fi

            local worktrees_to_delete="${positional_args[*]}"
            local bare_path; bare_path="$(__fgb_get_bare_repo_path)"
            local exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
            local branch_name wt_path user_prompt
            while IFS='' read -r branch_name; do
                if [[ "$branch_name" == remotes/*/* ]]; then
                    # Remove first two components of the reference name (remotes/<upstream>/)
                    branch_name="${branch_name#*/}"
                    branch_name="${branch_name#*/}"
                fi
                wt_path="$(__fgb_get_worktree_path_for_branch "$branch_name")"
                if [[ -n "$wt_path" ]]; then
                    local is_in_target_wt=false
                    if [[ "$PWD" == "$wt_path" ]]; then
                        cd "$bare_path" && is_in_target_wt=true || return 1
                    fi
                    user_prompt=$(__fgb_stdout_unindented "
                        |${col_r}Delete${col_reset} worktree: \#
                        |${col_y}${wt_path}${col_reset}, \#
                        |for branch '${col_b}${branch_name}${col_reset}'?
                    ")
                    if "$force" || __fgb_confirmation_dialog "$user_prompt"; then
                        user_prompt=$(__fgb_stdout_unindented "
                            |${col_g}Deleted${col_reset} worktree: \#
                            |${col_y}${wt_path}${col_reset}, \#
                            |for branch '${col_b}${branch_name}${col_reset}'
                        ")
                        if ! git worktree remove "$branch_name"; then
                            local success_message="$user_prompt"
                            user_prompt=$(__fgb_stdout_unindented "

                                |${col_r}WARNING:${col_reset} \#
                                |This will permanently reset/delete the following files:

                                |$(script -q /dev/null -c "git -C \"$wt_path\" status --short")

                                |in the ${col_y}${wt_path}${col_reset} path.

                                |Are you sure you want to proceed?
                            ")
                            # NOTE: Avoid --force here as it's not undoable operation
                            if __fgb_confirmation_dialog "$user_prompt"; then
                                if git worktree remove "$branch_name" --force; then
                                    echo -e "$success_message"
                                fi
                            else
                                if "$is_in_target_wt"; then
                                    cd "$wt_path" || return 1
                                fi
                            fi
                        else
                            echo -e "$user_prompt"
                        fi
                    else
                        if "$is_in_target_wt"; then
                            cd "$wt_path" || return 1
                        fi
                    fi
                fi
            done <<< "$worktrees_to_delete"
        }


        __fgb_git_worktree_jump_or_create() {
            # Jump to an existing worktree or create a new one for a given branch

            if [ $# -eq 0 ]; then
                echo "Missing argument: branch name"
                return 1
            fi
            local branch_name="$1"
            if [[ "$branch_name" == remotes/*/* ]]; then
                # Remove first two components of the reference name (remotes/<upstream>/)
                branch_name="${branch_name#*/}"
                branch_name="${branch_name#*/}"
            fi
            local wt_path
            wt_path="$(__fgb_get_worktree_path_for_branch "$branch_name")"
            local message
            if [[ -n "$wt_path" ]]; then
                if cd "$wt_path"; then
                    message=$(__fgb_stdout_unindented "
                        |${col_g}Jumped${col_reset} to worktree: \#
                        |${col_y}${wt_path}${col_reset}, \#
                        |for branch '${col_b}${branch_name}${col_reset}'
                    ")
                    echo -e "$message"
                else
                    return 1
                fi
            else
                local bare_path; bare_path="$(__fgb_get_bare_repo_path)"
                local wt_path="${bare_path}/${branch_name}"
                if git worktree add "$wt_path" "$branch_name"; then
                    cd "$wt_path" || return 1
                    message=$(__fgb_stdout_unindented "
                    |Worktree ${col_y}${wt_path}${col_reset} \#
                    |for branch '${col_b}${branch_name}${col_reset}' created successfully.
                    |${col_g}Jumped${col_reset} there.
                    ")
                    echo -e "$message"
                fi
            fi
        }


        __fgb_git_worktree_list() {
            # List worktrees in a git repository

            if [[ -z "$(__fgb_get_bare_repo_path)" ]]; then
                echo "Not inside a bare Git repository. Exit..."
                return
            fi

            local sort_order="-committerdate"
            local force=false
            local positional_args=()
            local branch_list_args=()

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        shift
                        sort_order="$1"
                        ;;
                    --sort=*)
                        sort_order="${1#*=}"
                        ;;
                    -h | --help)
                        echo "${usage_message[worktree_list]}"
                        return
                        ;;
                    --* | -*)
                        echo "error: unknown option: \`$1'" >&2
                        echo "${usage_message[worktree_list]}" >&2
                        return 1
                        ;;
                    *)
                        positional_args+=("$1")
                        ;;
                esac
                shift
            done

            local wt_list; wt_list="$(git worktree list | sed '1d')"

            local -A wt_branches_map
            local branch_name line wt_branches=""
            while IFS='' read -r line; do
                branch_name="$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' <<< "$line")"
                wt_branches_map["$branch_name"]="$(cut -d' ' -f1 <<< "$line")"
                wt_branches+="${branch_name}\n"
            done <<< "$wt_list"
            wt_branches="$(echo -en "$wt_branches")" # Remove trailing newline

            local width_of_window; width_of_window=$(tput cols)
            local wt_path_width=0
            if [[ "$width_of_window" -gt 80 ]]; then
                local author_width refname_width
                refname_width="$(__fgb_get_segment_width_relative_to_window 0.27)"
                wt_path_width="$(__fgb_get_segment_width_relative_to_window 0.40)"
                author_width="$(__fgb_get_segment_width_relative_to_window 0.33)"
            fi

            local output
            output="$(
                __fgb_branch_list \
                    --sort "$sort_order" \
                    --refname-width "$refname_width" \
                    --author-width "$author_width" \
                    --filter "$wt_branches"
            )"

            refname_width="$(( refname_width + 2 ))"

            # Subtract 1 from the width to account for the space between the columns
            wt_path_width="$(( wt_path_width > 0 ? wt_path_width - 1 : 0 ))"

            local key rest_of_line start_position wt_path wt_path_len
            while IFS='' read -r line; do
                branch_name="$(cut -d' ' -f1 <<< "$line")"
                # shellcheck disable=SC2001
                key="$(sed "s/\x1B\[[0-9;]*[JKmsu]//g" <<< "$branch_name")"
                rest_of_line="$(echo "$line" | cut -d' ' -f2- | sed -e 's/^ *//')"
                wt_path="${wt_branches_map["$key"]}"
                wt_path_len="${#wt_path}"
                if [ "$wt_path_width" -gt 0 ]; then
                    if [ "$wt_path_len" -gt "$wt_path_width" ]; then
                        start_position=$(( wt_path_len - wt_path_width + 3 ))
                        wt_path="${wt_path:$start_position}"
                        wt_path=".../${wt_path#*/}"
                    fi
                    printf \
                        "%-${refname_width}s %-${wt_path_width}s %s\n" \
                        "[$branch_name]" \
                        "$wt_path" \
                        "$rest_of_line"
                else
                    printf \
                        "%-${refname_width}s %s\n" \
                        "[$branch_name]" \
                        "$rest_of_line"
                fi
            done <<< "$output"
        }


        __fgb_worktree_manage() {
            # Manage Git worktrees

            if [[ -z "$(__fgb_get_bare_repo_path)" ]]; then
                echo "Not inside a bare Git repository. Exit..."
                return
            fi

            local sort_order="-committerdate"
            local force=false
            local positional_args=()
            local branch_list_args=()

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s | --sort)
                        shift
                        sort_order="$1"
                        ;;
                    --sort=*)
                        sort_order="${1#*=}"
                        ;;
                    -a | --all | -r | --remotes)
                        branch_list_args+=("$1")
                        ;;
                    --filter)
                        shift
                        branch_list_args+=("--filter $1")
                        ;;
                    --filter=*)
                        branch_list_args+=("--filter ${1#*=}")
                        ;;
                    -f | --force)
                        force=true
                        ;;
                    -h | --help)
                        echo "${usage_message[worktree_manage]}"
                        return
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

            local del_key="ctrl-d"
            local fzf_cmd="\
                $FZF_CMD_GLOB \
                    --expect='$del_key' \
                    --header 'Manage Git Worktrees: ctrl-y:jump, ctrl-t:toggle, $del_key:delete' \
                "

            if [[ "${#positional_args[@]}" -gt 0 ]]; then
                fzf_cmd+=" --query='${positional_args[*]}'"
            fi

            local branch_list_cmd="\
                __fgb_branch_list \
                    --sort $sort_order \
                    --refname-width $refname_width \
                    --author-width $author_width \
                    ${branch_list_args[*]} \
                "

            local lines; lines="$(eval "$branch_list_cmd" | eval "$fzf_cmd" | cut -d " " -f 1)"

            if [[ -z "$lines" ]]; then
                return
            fi

            local key; key=$(head -1 <<< "$lines")

            if [[ $key == "$del_key" ]]; then
                if "$force"; then
                    __fgb_git_worktree_delete "$(sed 1d <<< "$lines")" --force
                    return $?
                else
                    __fgb_git_worktree_delete "$(sed 1d <<< "$lines")"
                    return $?
                fi
            else
                __fgb_git_worktree_jump_or_create "$(tail -1 <<< "$lines")"
                return $?
            fi
        }


        __fgb_worktree() {
            local subcommand="$1"
            shift
            case $subcommand in
                list)
                    __fgb_git_worktree_list "$@"
                    exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
                    ;;
                manage)
                    __fgb_worktree_manage "$@"
                    exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
                    ;;
                -h | --help)
                    echo "${usage_message[worktree]}"
                    return
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


        __fgb_set_colors() {
            declare -g col_reset='\033[0m'
            declare -g col_r='\033[1;31m'
            declare -g col_g='\033[1;32m'
            declare -g col_y='\033[1;33m'
            declare -g col_b='\033[1;34m'
        }


        __fgb_unset_colors() {
            unset col_reset col_r col_g col_y col_b
        }

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
            |  manage  Switch to or delete branches in a git repository
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
            |  --refname-width=<width>
            |          Set the width of the refname column
            |
            |  --author-width=<width>
            |          Set the width of the author column
            |
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            refname (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  --filter=<filter>
            |          Filter branches by <filter> string (semicolon, new line or comma separated)
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
            |Switch to or delete branches in a git repository
            |
            |Query:
            |  <query>  Query to filter branches by using fzf (optional)
            |
            |Options:
            |  --refname-width=<width>
            |          Set the width of the refname column
            |
            |  --author-width=<width>
            |          Set the width of the author column
            |
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            -committerdate (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  --filter=<filter>
            |          Filter branches by <filter> string (semicolon, new line or comma separated)
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
            |  manage  Create/switch to or delete worktrees in a git repository
            |
            |Options:
            |  -h, --help
            |          Show help message
            ")"

            ["worktree_list"]="$(__fgb_stdout_unindented "
            |Usage: fgb worktree list [<args>] [<query>]
            |
            |Create/switch to or delete worktrees in a git repository
            |
            |Query:
            |  <query>  Query to filter branches by using fzf (optional)
            |
            |Options:
            |  --refname-width=<width>
            |          Set the width of the refname column
            |
            |  --author-width=<width>
            |          Set the width of the author column
            |
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
            |Create/switch to or delete worktrees in a git repository
            |
            |Query:
            |  <query>  Query to filter branches by using fzf (optional)
            |
            |Options:
            |  --refname-width=<width>
            |          Set the width of the refname column
            |
            |  --author-width=<width>
            |          Set the width of the author column
            |
            |  -s, --sort=<sort>
            |          Sort branches by <sort>:
            |            -committerdate (default)
            |
            |  -r, --remotes
            |          List remote branches
            |
            |  --filter=<filter>
            |          Filter branches by <filter> string (semicolon, new line or comma separated)
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

        )


        # Define command and adjust arguments
        local fgb_command="${1:-}"
        shift
        local fgb_subcommand="${1:-}"

        local refname_width; refname_width="$(__fgb_get_segment_width_relative_to_window 0.67)"
        local author_width; author_width="$(__fgb_get_segment_width_relative_to_window 0.33)"

        __fgb_set_colors
        local exit_code=
        case "$fgb_command" in
            branch)
                case "$fgb_subcommand" in
                    "") echo -e "error: need a subcommand" >&2
                        echo "${usage_message[$fgb_command]}" >&2
                        return 1
                        ;;
                    *)
                        __fgb_branch "$@"
                        exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
                        ;;
                esac
                ;;
            worktree)
                case "$fgb_subcommand" in
                    "") echo -e "error: need a subcommand" >&2
                        echo "${usage_message[$fgb_command]}" >&2
                        return 1
                        ;;
                    *)
                        __fgb_worktree "$@"
                        exit_code=$?; if [ "$exit_code" -ne 0 ]; then return "$exit_code"; fi
                        ;;
                esac
                ;;
            -h | --help)
                echo "${usage_message[fgb]}"
                return
                ;;
            -v | --version)
                echo "$version_message"
                echo "$copyright_message"
                return
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

    __fgb_unset_colors

    unset -f \
        __fgb__functions \
        __fgb_branch \
        __fgb_branch_list \
        __fgb_branch_manage \
        __fgb_confirmation_dialog \
        __fgb_get_bare_repo_path \
        __fgb_get_list_of_worktrees \
        __fgb_get_segment_width_relative_to_window \
        __fgb_get_worktree_path_for_branch \
        __fgb_git_branch_delete \
        __fgb_git_worktree_delete \
        __fgb_git_worktree_jump_or_create \
        __fgb_git_worktree_list \
        __fgb_is_positive_int \
        __fgb_is_positive_int_or_float \
        __fgb_set_colors \
        __fgb_stdout_unindented \
        __fgb_unset_colors \
        __fgb_worktree \
        __fgb_worktree_manage

    return "$exit_code"
}
