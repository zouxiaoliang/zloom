#!/bin/zsh
# vim: set ft=zsh fenc=utf-8 noai ts=8 et sts=4 sw=0 tw=80 nowrap :
local ZLOOM_SOURCE="$0:A:h"

-zlputs() { printf %s\\n "$@" ;}
-zlpute() { printf %s\\n "-- zloom: $*" >&2 ;}

-zlinit() { -zlputs "$*" >> "${ZLOOM_INIT}" ;}

# Invoke a lifecycle hook when the user defined one: `_zloom_post_add',
# `_zloom_post_del', `_zloom_post_sync' and `_zloom_post_update' run (with
# the command's argument) after the respective command finished. zsh has
# no event system, so zloom calls convention-named functions instead of
# fisher's fisher_* events; functions/ is the natural place to define them
# (the file is sourced on demand, so hooks also fire in a shell that has
# not loaded the generated init script yet, e.g. right after bootstrap).
-zloom-hook() {
    local fn="_zloom_post_${1}"
    shift
    if (( ! $+functions[${fn}] )) \
            && [[ -f "${ZLOOM_PLUGINS:A:h}/functions/${fn}.zsh" ]]; then
        source "${ZLOOM_PLUGINS:A:h}/functions/${fn}.zsh"
    fi
    (( $+functions[${fn}] )) && "${fn}" "$@"
    return 0
}


# Regenerable data (generated init script, plugin clones, snippet cache,
# completions stamp) lives in the XDG data directory, away from the
# program clone at ~/.zloom. Setups that predate the split keep using
# ~/.zloom, detected by a generated init script inside the clone.
if [[ -z "${ZLOOM_DIR}" ]]; then
    if [[ -f "${HOME}/.zloom/init.zsh" ]]; then
        ZLOOM_DIR="${HOME}/.zloom"
    else
        ZLOOM_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/zloom"
    fi
fi

if [[ -z "${ZLOOM_INIT}" ]]; then
    ZLOOM_INIT="${ZLOOM_DIR}/init.zsh"
fi

# Fisher-style plugin manifest, maintained by `zloom add', `zloom del'
# and `zloom snippet'. When the init script is missing, it is regenerated
# from this file (see zloom-init). It lives in the XDG config directory
# so the whole configuration can be synced as one folder; setups that
# predate this keep using ${ZLOOM_DIR}/plugins.zsh automatically.
if [[ -z "${ZLOOM_PLUGINS}" ]]; then
    if [[ -f "${ZLOOM_DIR}/plugins.zsh" ]]; then
        ZLOOM_PLUGINS="${ZLOOM_DIR}/plugins.zsh"
    else
        ZLOOM_PLUGINS="${XDG_CONFIG_HOME:-${HOME}/.config}/zloom/plugins.zsh"
    fi
fi

# The user can explicitly disable Zloom attempting to invoke `compinit`, or it
# will be automatically disabled if `compinit` appears to have already been
# invoked.
if [[ -z "${ZLOOM_AUTOLOAD_COMPINIT}" && -z "${(t)_comps}" ]]; then
    ZLOOM_AUTOLOAD_COMPINIT=1
fi

if [[ -n "${ZLOOM_CUSTOM_COMPDUMP}" ]]; then
    ZLOOM_COMPINIT_DIR_FLAG="-d ${(q)ZLOOM_CUSTOM_COMPDUMP}"
    ZLOOM_COMPINIT_FLAGS="${ZLOOM_COMPINIT_DIR_FLAG} ${ZLOOM_COMPINIT_FLAGS}"
fi

if [[ -z "${ZLOOM_LOADED}" ]]; then
    ZLOOM_LOADED=()
fi

if [[ -z "${ZLOOM_DEFERRED}" ]]; then
    ZLOOM_DEFERRED=()
fi

if [[ -z "${ZLOOM_ENV}" ]]; then
    ZLOOM_ENV=()
fi

if [[ -z "${ZLOOM_ALIAS}" ]]; then
    ZLOOM_ALIAS=()
fi

if [[ -z "${ZLOOM_EVAL}" ]]; then
    ZLOOM_EVAL=()
fi

if [[ -z "${ZLOOM_FUNC}" ]]; then
    ZLOOM_FUNC=()
fi

if [[ -z "${ZLOOM_PREZTO_OPTIONS}" ]]; then
    ZLOOM_PREZTO_OPTIONS=()
fi

if [[ -z "${ZLOOM_PREZTO_LOAD}" ]]; then
    ZLOOM_PREZTO_LOAD=()
fi

if [[ -z "${ZLOOM_COMPLETIONS}" ]]; then
    ZLOOM_COMPLETIONS=()
fi

if [[ -z "${ZLOOM_USE_PREZTO}" ]]; then
    ZLOOM_USE_PREZTO=0
fi

if [[ -z "${ZLOOM_PREZTO_LOAD_DEFAULT}" ]]; then
    ZLOOM_PREZTO_LOAD_DEFAULT=1
fi

if [[ -z "${ZLOOM_OH_MY_ZSH_REPO}" ]]; then
    ZLOOM_OH_MY_ZSH_REPO=robbyrussell
fi

if [[ "${ZLOOM_OH_MY_ZSH_REPO}" != */* ]]; then
    ZLOOM_OH_MY_ZSH_REPO="${ZLOOM_OH_MY_ZSH_REPO}/oh-my-zsh"
fi

if [[ -z "${ZLOOM_OH_MY_ZSH_BRANCH}" ]]; then
    ZLOOM_OH_MY_ZSH_BRANCH=master
fi

if [[ -z "${ZLOOM_PREZTO_REPO}" ]]; then
    ZLOOM_PREZTO_REPO=sorin-ionescu
fi

if [[ "${ZLOOM_PREZTO_REPO}" != */* ]]; then
    ZLOOM_PREZTO_REPO="${ZLOOM_PREZTO_REPO}/prezto"
fi

if [[ -z "${ZLOOM_PREZTO_BRANCH}" ]]; then
    ZLOOM_PREZTO_BRANCH=master
fi

-zloom-encode-url () {
    # Remove characters from a url that don't work well in a filename.
    # Inspired by -anti-get-clone-dir() method from antigen.
    local url="${1}"
    url="${url//\//-SLASH-}"
    url="${url//\:/-COLON-}"
    url="${url//\|/-PIPE-}"
    url="${url//~/-TILDE-}"
    -zlputs "$url"
}

# Fork-free variant of -zloom-get-clone-dir: stores the result in REPLY
# instead of writing to stdout, so the shell startup path can compute the
# clone directory without spawning command-substitution subshells.
-zloom-set-clone-dir() {
    local repo="${1}"
    local branch="${2:-master}"

    if [[ -e "${repo}/.git" ]]; then
        REPLY="${ZLOOM_DIR}/local/${repo:t}-${branch}"
    else
        # Repo directory will be location/reponame. Need to encode in case it
        # is a full url with characters that don't work well in a filename.
        local location="${repo:h}"
        location="${location//\//-SLASH-}"
        location="${location//\:/-COLON-}"
        location="${location//\|/-PIPE-}"
        location="${location//~/-TILDE-}"
        REPLY="${ZLOOM_DIR}/${location}/${repo:t}-${branch}"
    fi
}

-zloom-get-clone-dir() {
    -zloom-set-clone-dir "${@}"
    -zlputs "${REPLY}"
}

-zloom-get-clone-url() {
    local repo="${1}"

    if [[ -e "${repo}/.git" ]]; then
        -zlputs "${repo}"
    else
        # Sourced from antigen url resolution logic.
        # https://github.com/zsh-users/antigen/blob/master/antigen.zsh
        # Expand short github url syntax: `username/reponame'.
        if [[ $repo != *://* &&
              $repo != git://* &&
              $repo != https://* &&
              $repo != http://* &&
              $repo != ssh://* &&
              $repo != git@*:*/*
              ]]; then
            repo="https://github.com/${repo%.git}.git"
        fi
        -zlputs "${repo}"
    fi
}

# Split a fisher-style `owner/repo@ref' pin: REPLY gets the repository,
# REPLY_REF the pinned tag, branch or commit (empty when unpinned). Only
# the last path component is considered, so URLs with userinfo
# (`https://user@host/...'), git@ ssh remotes and local paths pass
# through untouched.
-zloom-split-ref() {
    local spec="${1}"
    REPLY="${spec}"
    REPLY_REF=""
    if [[ "${spec}" != /* && "${spec}" != .* && "${spec}" == */*@* ]] \
            && [[ "${spec##*/}" == *@* ]]; then
        REPLY="${spec%@*}"
        REPLY_REF="${spec##*@}"
    fi
}

# Query the remote HEAD branch of ${1}; REPLY is empty when the remote
# cannot be reached. Costs one `git ls-remote' and is used only by
# `zloom add' when no branch was pinned, so the manifest records the
# detected branch and later rebuilds stay deterministic offline.
-zloom-default-branch() {
    REPLY=""
    local url="$(-zloom-get-clone-url "${1}")"
    local sym
    sym="$(git ls-remote --symref "${url}" HEAD 2>/dev/null)"
    sym="${sym%%$'\n'*}"
    if [[ "${sym}" == ref:\ * ]]; then
        sym="${sym#ref: }"
        REPLY="${sym%%[[:space:]]*}"
        REPLY="${REPLY#refs/heads/}"
    fi
}

zloom-clone() {
    local repo="${1}"
    local branch="${2:-master}"
    local url="$(-zloom-get-clone-url ${repo})"
    local dir="$(-zloom-get-clone-dir ${repo} ${branch})"

    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
        if [[ "${branch}" == HEAD ]]; then
            # @HEAD pin (offline default-branch fallback): clone the
            # remote's default branch, whatever it is.
            git clone --depth=1 --recursive "${url}" "${dir}"
        else
            git clone --depth=1 --recursive -b "${branch}" "${url}" "${dir}"
        fi
    fi
}

-zloom-add-to-fpath() {
    local completion_path="${1}"

    # Add the directory to ZLOOM_COMPLETIONS array if not present
    if [[ ! "${ZLOOM_COMPLETIONS[@]}" =~ ${completion_path} ]]; then
        ZLOOM_COMPLETIONS+=("${completion_path}")
    fi
}

-zloom-source() {
    local file="${1}"
    local base="${file:t}"
    if [[ ! "${ZLOOM_LOADED[@]}" =~ "${file}" && ! "${base}" =~ "^_" ]]; then
        ZLOOM_LOADED+=("${file}")
        source "${file}"

        completion_path="${file:h}"

        -zloom-add-to-fpath "${completion_path}"

        # Byte-compile the script so later shells parse wordcode instead of
        # source text. Only compiled when the script is newer than an existing
        # .zwc, so `zloom update` automatically invalidates stale bytecode.
        if [[ ! -s "${file}.zwc" || "${file}" -nt "${file}.zwc" ]]; then
            zcompile -U -- "${file}" 2>/dev/null
        fi
    fi
}

# Single entry point used by the plugin-location cascade below: sources the
# file right away, or records it in ZLOOM_DEFERRED instead when invoked via
# `zloom defer` (turbo mode).
-zloom-load-file() {
    local file="${1}"

    # Recording mode (manifest replay during -zloom-rebuild): resolve the
    # entry into ZLOOM_LOADED / ZLOOM_DEFERRED without sourcing it, so the
    # init script can be regenerated for plugins that may already be
    # active in this session (e.g. after `zloom del').
    if [[ -n "${ZLOOM_RECORDING}" ]]; then
        local base="${file:t}"
        [[ "${base}" =~ "^_" ]] && return 0

        if [[ -n "${ZLOOM_DEFERRING}" ]]; then
            local recorded
            for recorded in "${ZLOOM_DEFERRED[@]}"; do
                [[ "${recorded}" == "${file}" ]] && return 0
            done
            ZLOOM_DEFERRED+=("${file}")
        elif [[ " ${ZLOOM_LOADED[@]} " != *" ${file} "* ]]; then
            ZLOOM_LOADED+=("${file}")
        fi

        # Completion directories still join fpath so the regenerated
        # init.zsh sets them up as usual; only the sourcing is skipped.
        -zloom-add-to-fpath "${file:h}"

        # Byte-compile now so the first real source is fast as well.
        if [[ ! -s "${file}.zwc" || "${file}" -nt "${file}.zwc" ]]; then
            zcompile -U -- "${file}" 2>/dev/null
        fi
        return 0
    fi

    if [[ -z "${ZLOOM_DEFERRING}" ]]; then
        -zloom-source "${file}"
        return 0
    fi

    # turbo: record the file for deferred sourcing after the first prompt.
    # Autoload-style files (name starting with `_') are skipped, exactly
    # like in -zloom-source.
    local base="${file:t}"
    [[ "${base}" =~ "^_" ]] && return 0

    local recorded
    for recorded in "${ZLOOM_DEFERRED[@]}"; do
        [[ "${recorded}" == "${file}" ]] && return 0
    done
    ZLOOM_DEFERRED+=("${file}")

    # Completion directories still join fpath synchronously so compinit
    # picks them up as usual; only the sourcing is deferred.
    -zloom-add-to-fpath "${file:h}"

    # Byte-compile now so the deferred source is fast as well.
    if [[ ! -s "${file}.zwc" || "${file}" -nt "${file}.zwc" ]]; then
        zcompile -U -- "${file}" 2>/dev/null
    fi
}

-zloom-prezto-option(){
    local module=${1}
    shift
    local option=${1}
    shift
    local params
    params=${@}
    if [[ ${module} =~ "^:" ]]; then
        module=${module[1,]}
    fi
    if [[ ! $module =~ "^(\*|module|prezto:module):" ]]; then
        module="module:$module"
    fi
    if [[ ! $module =~ "^(prezto):" ]]; then
        module="prezto:$module"
    fi
    local cmd="zstyle ':${module}' $option ${params}"

    # execute in place
    eval $cmd

    if [[ ! "${ZLOOM_PREZTO_OPTIONS[@]}" =~ "${cmd}" ]]; then
        ZLOOM_PREZTO_OPTIONS+=("${cmd}")
    fi
}

-zloom-prezto-load(){
    local params="$*"
    local cmd="pmodload ${params[@]}"

    # execute in place
    eval $cmd

    if [[ ! "${ZLOOM_PREZTO[@]}" =~ "${cmd}" ]]; then
        ZLOOM_PREZTO_LOAD+=("${params[@]}")
    fi
}

zloom-init() {
    if [[ -f "${ZLOOM_INIT}" ]]; then
        source "${ZLOOM_INIT}"
        return 0
    fi

    # Bootstrap only when the config directory actually has content: the
    # manifest, config.zsh or any drop-in file. The globs have to be
    # expanded here, outside `[[ ]]', for the (N) flag to apply.
    local -a _zloom_scan=(${ZLOOM_PLUGINS:h}/conf.d/*.zsh(N) \
        ${ZLOOM_PLUGINS:h}/functions/*.zsh(N) \
        ${ZLOOM_PLUGINS:h}/themes/*.zsh(N))
    if [[ -f "${ZLOOM_PLUGINS}" || -f "${ZLOOM_PLUGINS:h}/config.zsh" ]] \
            || (( ${#_zloom_scan} )); then
        -zlpute "Building ${ZLOOM_INIT} from ${ZLOOM_PLUGINS:h} ..."
        -zloom-rebuild live
    fi
}

zloom-reset() {
    -zlpute 'Deleting `'"${ZLOOM_INIT}"'` ...'
    if [[ -f "${ZLOOM_INIT}" ]]; then
        rm "${ZLOOM_INIT}"
    fi
    if [[ -f "${ZLOOM_INIT}.zwc" ]]; then
        rm "${ZLOOM_INIT}.zwc"
    fi
    if [[ -f "${ZLOOM_CUSTOM_COMPDUMP}" ]] || [[ -d "${ZLOOM_CUSTOM_COMPDUMP}" ]]; then
        -zlpute 'Deleting `'"${ZLOOM_CUSTOM_COMPDUMP}"'` ...'
        rm -r "${ZLOOM_CUSTOM_COMPDUMP}"
    fi
    if [[ -f "${ZLOOM_CUSTOM_COMPDUMP}.zwc" ]]; then
        -zlpute 'Deleting `'"${ZLOOM_CUSTOM_COMPDUMP}.zwc"'` ...'
        rm "${ZLOOM_CUSTOM_COMPDUMP}.zwc"
    fi
}

# Pull every clone concurrently (fisher-style). Branch checkouts update
# via `git pull'; detached pins (@tag, @HEAD) via fetch + checkout so a
# moved tag or a new default-branch tip is followed; commit-sha pins pin
# exact content and are skipped. Failures surface after all jobs finish;
# the exit status reflects them. Nothing here runs at shell startup.
-zloom-pull-all() {
    setopt localoptions extended_glob

    local repo pid ref dir line rc=0
    local -a words jobs=()

    for repo in "${ZLOOM_DIR}"/(^(.git|snippets))/*(N); do
        -zlpute "Updating '${repo}' ..."
        ( cd "${repo}" \
            && { git symbolic-ref -q HEAD >/dev/null || exit 0; } \
            && git pull --quiet \
            && git submodule update --init --recursive --quiet ) &
        jobs+=($!)
    done

    if [[ -f "${ZLOOM_PLUGINS}" ]]; then
        while IFS= read -r line; do
            -zloom-manifest-words "${line}"
            words=("${reply[@]}")
            (( ${#words} >= 2 )) || continue
            [[ "${words[1]}" == (load|defer) ]] || continue
            -zloom-split-ref "${words[2]}"
            ref="${REPLY_REF}"
            [[ -n "${ref}" ]] || continue
            [[ "${ref}" =~ '^[0-9a-f]{7,40}$' ]] && continue
            -zloom-set-clone-dir "${REPLY}" "${ref}"
            dir="${REPLY}"
            [[ -d "${dir}" ]] || continue
            # Attached branches are covered by the pull loop above.
            git -C "${dir}" symbolic-ref -q HEAD >/dev/null 2>&1 && continue
            -zlpute "Updating '${dir:t}' (${ref}) ..."
            if [[ "${ref}" == HEAD ]]; then
                ( cd "${dir}" \
                    && git fetch --quiet origin \
                    && git checkout --quiet FETCH_HEAD ) &
            else
                ( cd "${dir}" \
                    && git fetch --quiet origin \
                    && { git fetch --quiet origin "tag ${ref}" 2>/dev/null || :; } \
                    && git checkout --quiet "${ref}" \
                    && git submodule update --init --recursive --quiet ) &
            fi
            jobs+=($!)
        done < "${ZLOOM_PLUGINS}"
    fi

    for pid in "${jobs[@]}"; do
        wait "${pid}" || rc=1
    done
    return ${rc}
}

zloom-update() {
    # Refresh cached remote snippets via their recorded origin URLs.
    local url_file snippet_url
    for url_file in "${ZLOOM_DIR}"/snippets/*.url(N); do
        snippet_url="$(<${url_file})"
        -zlpute "Updating snippet '${snippet_url}' ..."
        -zloom-fetch-snippet "${snippet_url}" 1
    done

    -zloom-pull-all
    local rc=$?
    (( rc )) && -zlpute "update: one or more repositories failed to update"
    zloom-reset
    -zloom-hook update
    return ${rc}
}

# Called from the generated init.zsh with the recorded state of
# $ZLOOM_RESET_ON_CHANGE on stdin: one mtime line per file, followed by one
# cksum line per file. The mtime comparison uses the fork-free zsh/stat
# module, so the common "nothing changed" path costs no forks; cksum only
# runs when a file actually moved (or the module is unavailable).
-zloom-check-changed() {
    local -a _recorded
    local _line
    while IFS= read -r _line; do
        _recorded+=("${_line}")
    done

    local -a _files=(${=ZLOOM_RESET_ON_CHANGE})
    integer _i _n=${#_files}
    (( _n && ${#_recorded} >= _n )) || return 0

    integer _moved=0
    local -a _mt
    if zmodload zsh/stat 2>/dev/null; then
        for (( _i=1; _i<=_n; _i++ )); do
            if ! zstat -A _mt +mtime -- "${_files[_i]}" 2>/dev/null \
                    || [[ "${_mt[1]}" != "${_recorded[_i]}" ]]; then
                _moved=1
                break
            fi
        done
    else
        _moved=1
    fi

    if (( _moved )); then
        local -a _old=("${_recorded[_n+1,-1]}")
        local -a _new=("${(@f)$(cksum ${=_files} 2>/dev/null)}")
        if [[ "${(F)_new}" != "${(F)_old}" ]]; then
            printf %s\\n '-- zloom: Files in $ZLOOM_RESET_ON_CHANGE changed; resetting `init.zsh`...'
            zloom reset
        fi
    fi
    return 0
}

zloom-save() {
    -zlpute 'Creating `'"${ZLOOM_INIT}"'` ...'

    # The manifest dir and the init dir are distinct since the manifest
    # moved to the XDG config tree; nothing else creates the init dir on
    # a fresh machine.
    mkdir -p "${ZLOOM_INIT:h}"
    -zlputs "# {{{" >! "${ZLOOM_INIT}"
    -zlinit "# Generated by zloom."
    -zlinit "# This file will be overwritten the next time you run zloom save!"
    # Environment first, so plugins sourced below can rely on it. Values
    # are emitted (qq): the (q) backslash style breaks down for values
    # like `${https_proxy:=}' when re-parsed as an `export' argument.
    if (( ${#ZLOOM_ENV[@]} )); then
        -zlinit ""
        -zlinit "# ### Environment (zloom env)"
        for _zloom_e in "${ZLOOM_ENV[@]}"; do
            -zlinit "export ${${_zloom_e}%%=*}=${(qq)${${_zloom_e}#*=}}"
        done
    fi

    # Dynamic environment next (eval "$(command)"): still ahead of the
    # plugins, which may rely on the PATH or functions it sets up.
    if (( ${#ZLOOM_EVAL[@]} )); then
        -zlinit ""
        -zlinit "# ### Eval (zloom eval)"
        for _zloom_v in "${ZLOOM_EVAL[@]}"; do
            -zlinit "eval \"\$(${_zloom_v})\""
        done
    fi

    # User config, fish-style: conf.d/ drop-in fragments (alphabetical,
    # no registration needed) and then the main config.zsh -- still ahead
    # of the plugins, after the manifest-managed env/eval environment.
    # Emitted unconditionally: absent directories and files turn the
    # lines into no-ops, keeping everything opt-in.
    local _zloom_cfg="${ZLOOM_PLUGINS:h}"
    local _zloom_stamp="${ZLOOM_INIT:h}/completions.stamp"
    -zlinit ""
    -zlinit "# ### User config (${_zloom_cfg}/conf.d + config.zsh)"
    -zlinit "for _zloom_cf in ${(q)_zloom_cfg}/conf.d/*.zsh(N); do"
    -zlinit '    source "${_zloom_cf}"'
    -zlinit "done"
    -zlinit '[[ -f '"${(q)_zloom_cfg}"'/config.zsh ]] && source '"${(q)_zloom_cfg}"'/config.zsh'
    -zlinit "unset _zloom_cf"

    -zlinit ""
    # Single-quoted like the source lines below: a ZLOOM_DIR with spaces
    # would otherwise emit `ZSH=/path with space/...', which parses as an
    # env-prefixed command and fails with `no such file or directory'.
    -zloom-set-zsh
    -zlinit "ZSH=${(qq)REPLY}"
    if [[ ${ZLOOM_USE_PREZTO} == 1 ]]; then
        -zlinit ""
        -zlinit "# ### Prezto initialization"
        for option in "${ZLOOM_PREZTO_OPTIONS[@]}"; do
            -zlinit "${option}"
        done
    fi

    -zlinit ""
    -zlinit "# ### General modules"
    for file in "${ZLOOM_LOADED[@]}"; do
        # Deferred plugins are sourced after the first prompt (turbo); keep
        # them out of the synchronous section even if they were loaded in
        # this session already (e.g. by an older init.zsh or by the
        # non-interactive fallback of -zloom-turbo-install).
        [[ " ${ZLOOM_DEFERRED[@]} " == *" ${file} "* ]] && continue
        # Single-quoted via (qq): paths with spaces stay one word and the
        # raw path appears verbatim in the line (zloom clean greps for
        # it). The old form — (q) escapes inside double quotes — left
        # literal backslashes in the filename.
        -zlinit "source ${(qq)file}"
    done

    # Aliases come last, so they win over aliases defined by a plugin.
    # Values are emitted (qq) for the same reason as the env exports:
    # the (q) backslash style mis-parses values like
    # `echo "${https_proxy:=}";' as an `alias' argument -- an unterminated
    # quote swallows the rest of init.zsh.
    if (( ${#ZLOOM_ALIAS[@]} )); then
        -zlinit ""
        -zlinit "# ### Aliases (zloom alias)"
        for _zloom_a in "${ZLOOM_ALIAS[@]}"; do
            -zlinit "alias ${${_zloom_a}%%=*}=${(qq)${${_zloom_a}#*=}}"
        done
    fi

    # Functions come after aliases, so they win over plugin-provided ones.
    if (( ${#ZLOOM_FUNC[@]} )); then
        -zlinit ""
        -zlinit "# ### Functions (zloom func)"
        for _zloom_fn in "${ZLOOM_FUNC[@]}"; do
            -zlinit "${${_zloom_fn}%%=*}() { ${${_zloom_fn}#*=} }"
        done
    fi

    # Function files: one file per custom function in the `functions'
    # directory next to the manifest (e.g. ~/.config/zloom/functions/).
    # The scan loop lives in init.zsh itself, so dropping a file in (or
    # removing one) takes effect on the next shell without a rebuild.
    # Each file is byte-compiled on first use; `source' transparently
    # prefers the fresher .zwc. Emitted unconditionally: with the
    # directory absent the (N) glob expands to nothing and the loop is
    # a no-op, keeping the feature purely opt-in.
    -zlinit ""
    -zlinit "# ### Function files (${_zloom_cfg}/functions/, one file per function)"
    -zlinit "for _zloom_ff in ${(q)_zloom_cfg}/functions/*.zsh(N); do"
    -zlinit '    [[ -s "${_zloom_ff}.zwc" && "${_zloom_ff}" -nt "${_zloom_ff}.zwc" ]] || zcompile -U -- "${_zloom_ff}" 2>/dev/null'
    -zlinit '    source "${_zloom_ff}"'
    -zlinit "done"
    -zlinit "unset _zloom_ff"

    # Theme configs run after every plugin is sourced, so a prompt config
    # can address the framework it belongs to (e.g. ~/.p10k.zsh).
    -zlinit ""
    -zlinit "# ### Theme configs (${_zloom_cfg}/themes/)"
    -zlinit "for _zloom_th in ${(q)_zloom_cfg}/themes/*.zsh(N); do"
    -zlinit '    source "${_zloom_th}"'
    -zlinit "done"
    -zlinit "unset _zloom_th"

    # Set up fpath, load completions
    # NOTE: This *intentionally* doesn't use ${ZLOOM_COMPINIT_FLAGS}; the only
    #       available flags are meaningless in the presence of `-C`.
    -zlinit ""
    -zlinit "# ### Plugins & Completions"
    -zlinit 'fpath=('"${(@q)ZLOOM_COMPLETIONS}"' '"${(q)_zloom_cfg}"'/completions ${fpath})'
    if [[ ${ZLOOM_AUTOLOAD_COMPINIT} == 1 ]]; then
        -zlinit ""
        # `compinit -C` trusts the dump and never looks for completion files
        # added since it was written, which would defeat the drop-in
        # completions/ directory. Its file list is compared against a stamp
        # next to init.zsh instead: unchanged takes the fork-free -C path;
        # changed or first run does a full compinit that rescans fpath,
        # then refreshes the stamp.
        -zlinit 'autoload -Uz compinit && {'
        -zlinit "    zloom_cpls=(${(q)_zloom_cfg}/completions/*(Non-.))"
        -zlinit '    if [[ -f '"${(q)_zloom_stamp}"' && "${(j: :)zloom_cpls}" == "$(<'"${(q)_zloom_stamp}"')" ]]; then'
        -zlinit '        compinit -C'"${ZLOOM_COMPINIT_DIR_FLAG:+ ${ZLOOM_COMPINIT_DIR_FLAG}}"
        -zlinit '    else'
        -zlinit '        compinit'"${ZLOOM_COMPINIT_FLAGS:+ ${ZLOOM_COMPINIT_FLAGS}}"
        -zlinit '        print -r -- "${(j: :)zloom_cpls}" >! '"${(q)_zloom_stamp}"
        -zlinit '    fi'
        -zlinit '}'
        -zlinit 'unset zloom_cpls'
        # compinit reads the dump back with `source`, so byte-compiling it
        # speeds up every subsequent shell. Recompiled only when the dump
        # itself changed (e.g. after a full compinit run). The default dump
        # path is resolved at load time so ZDOTDIR is honored.
        -zlinit ""
        -zlinit 'zloom_dump="${ZLOOM_CUSTOM_COMPDUMP:-${ZDOTDIR:-$HOME}/.zcompdump}"'
        -zlinit 'if [[ -s ${zloom_dump} && ( ! -s ${zloom_dump}.zwc || ${zloom_dump} -nt ${zloom_dump}.zwc ) ]]; then'
        -zlinit '    zcompile -U -- "${zloom_dump}" 2>/dev/null'
        -zlinit 'fi'
        -zlinit 'unset zloom_dump'
    fi

    # Check for file changes
    if [[ ! -z "${ZLOOM_RESET_ON_CHANGE}" ]]; then
        -zlinit ""
        -zlinit "# ### Recompilation triggers"

        # Record mtimes and cksums; the runtime check (in
        # -zloom-check-changed) compares mtimes via the fork-free zsh/stat
        # module and only runs cksum when something actually moved.
        local -a _zloom_record=()
        local _zloom_f
        local -a _zloom_mt
        if ! zmodload zsh/stat 2>/dev/null; then
            for _zloom_f in ${=ZLOOM_RESET_ON_CHANGE}; do
                _zloom_record+=('__no_stat__')
            done
        else
            for _zloom_f in ${=ZLOOM_RESET_ON_CHANGE}; do
                if zstat -A _zloom_mt +mtime -- "${_zloom_f}" 2>/dev/null; then
                    _zloom_record+=("${_zloom_mt[1]}")
                else
                    _zloom_record+=('__missing__')
                fi
            done
        fi
        local _zloom_shas="$(cksum ${=ZLOOM_RESET_ON_CHANGE} 2>/dev/null)"
        local -a _zloom_sha_lines=("${(@f)_zloom_shas}")

        -zlinit "-zloom-check-changed <<'ZLOOM_CHANGE_RECORD'"
        for _zloom_f in "${_zloom_record[@]}" "${_zloom_sha_lines[@]}"; do
            -zlinit "${_zloom_f}"
        done
        -zlinit "ZLOOM_CHANGE_RECORD"
    fi

    # load prezto modules
    if [[ ${ZLOOM_USE_PREZTO} == 1 ]]; then
        -zlinit ""
        -zlinit "# ### Prezto modules"
        printf %s "pmodload" >> "${ZLOOM_INIT}"
        for module in "${ZLOOM_PREZTO_LOAD[@]}"; do
            printf %s " ${module}" >> "${ZLOOM_INIT}"
        done
    fi

    # Deferred plugins (turbo): install the one-shot hook that sources them
    # as soon as the first prompt is on screen.
    if [[ "${#ZLOOM_DEFERRED[@]}" -gt 0 ]]; then
        -zlinit ""
        -zlinit "# ### Deferred plugins (turbo)"
        -zlinit "ZLOOM_DEFERRED=("
        for file in "${ZLOOM_DEFERRED[@]}"; do
            -zlinit "    ${(q)file}"
        done
        -zlinit ")"
        -zlinit "-zloom-turbo-install"
    fi

    -zlinit ""
    -zlinit "# }}}"

    # Byte-compile the generated init file. Sourcing transparently prefers
    # the .zwc while it stays newer than init.zsh; regenerating or editing
    # init.zsh invalidates the bytecode automatically.
    zcompile -U -- "${ZLOOM_INIT}" 2>/dev/null

    zloom-apply
}

zloom-apply() {
    fpath=(${(q)ZLOOM_COMPLETIONS[@]} ${(q)${ZLOOM_PLUGINS:h}}/completions ${fpath})

    if [[ ${ZLOOM_AUTOLOAD_COMPINIT} == 1 ]]; then
        -zlpute "Initializing completions ..."

        autoload -Uz compinit && \
            compinit $ZLOOM_COMPINIT_FLAGS
    fi
}

# --- Turbo mode -------------------------------------------------------
# Called at the end of the generated init.zsh when `zloom defer` recorded
# plugins in ZLOOM_DEFERRED. Registers a one-shot zle file-descriptor
# handler: the moment the line editor first becomes idle waiting for input
# -- i.e. right after the first prompt is displayed -- the deferred plugins
# are sourced. Shells that never run the line editor (scripts, `zsh -c')
# load them synchronously instead; set ZLOOM_TURBO=0 to always load
# synchronously.

-zloom-turbo-load() {
    local file
    for file in "${ZLOOM_DEFERRED[@]}"; do
        -zloom-source "${file}"
    done
    ZLOOM_DEFERRED=()
}

-zloom-turbo-handler() {
    # One-shot: remove the handler before doing anything else, so the
    # permanently readable /dev/zero descriptor can never re-enter.
    zle -F "${ZLOOM_TURBO_FD}" 2>/dev/null
    exec {ZLOOM_TURBO_FD}<&- 2>/dev/null
    unset ZLOOM_TURBO_FD
    -zloom-turbo-load
    # Plugins may print or change the prompt while being sourced; force a
    # clean redisplay of the current line (widget-handler context).
    zle -R 2>/dev/null
}

-zloom-turbo-arm() {
    # Runs once from the first precmd, i.e. after every daemon spawned
    # during shell initialisation (p10k's gitstatusd closes inherited
    # descriptors above stderr, which would kill a descriptor opened at
    # init time before zle ever polls it).
    add-zsh-hook -d precmd -zloom-turbo-arm 2>/dev/null

    local fd=""
    if zmodload zsh/system 2>/dev/null; then
        sysopen -r -u fd /dev/zero 2>/dev/null
    fi
    if [[ -z "${fd}" ]]; then
        exec {fd}< <(:) 2>/dev/null || fd=""
    fi
    if [[ -z "${fd}" ]] || ! zle -N zloom_turbo_widget -- -zloom-turbo-handler 2>/dev/null \
            || ! zle -F -w "${fd}" zloom_turbo_widget 2>/dev/null; then
        [[ -n "${fd}" ]] && exec {fd}<&- 2>/dev/null
        -zloom-turbo-load
        return 0
    fi
    ZLOOM_TURBO_FD="${fd}"
}

-zloom-turbo-install() {
    (( ${#ZLOOM_DEFERRED[@]} )) || return 0

    # ZLOOM_TURBO=0 forces synchronous loading, e.g. for one-shot
    # `ZLOOM_TURBO=0 zsh -ic ...' invocations (see README).
    if [[ "${ZLOOM_TURBO}" == 0 ]]; then
        -zloom-turbo-load
        return 0
    fi

    # Non-interactive shells (scripts, `zsh -c') never run the line
    # editor, so there is nothing to defer to: load synchronously.
    # (An interactive `zsh -ic cmd' shell cannot be told apart from a real
    # interactive shell at this point; use ZLOOM_TURBO=0 there.)
    if [[ ! -o interactive ]]; then
        -zloom-turbo-load
        return 0
    fi

    # Defer the actual registration to the first precmd (see
    # -zloom-turbo-arm); the handler then fires right after the first
    # prompt is drawn. Fall back to direct registration when hooks are
    # unavailable.
    autoload -Uz add-zsh-hook 2>/dev/null
    if add-zsh-hook precmd -zloom-turbo-arm 2>/dev/null; then
        return 0
    fi
    -zloom-turbo-arm
}

-zloom-path-contains() {
    setopt localoptions nonomatch nocshnullglob nonullglob;
    [ -e "$1"/*"$2"(.,@[1]) ]
}

# Fork-free variant of -zloom-get-zsh: stores the result in REPLY.
-zloom-set-zsh(){
    if [[ ${ZLOOM_USE_PREZTO} == 1 ]]; then
        -zloom-set-clone-dir "$ZLOOM_PREZTO_REPO" "$ZLOOM_PREZTO_BRANCH"
    else
        -zloom-set-clone-dir "$ZLOOM_OH_MY_ZSH_REPO" "$ZLOOM_OH_MY_ZSH_BRANCH"
    fi
}

-zloom-get-zsh(){
    -zloom-set-zsh
    -zlputs "$REPLY"
}

# Resolve `zloom load'-style arguments to a plugin location directory,
# cloning the repository if needed. Sets REPLY to the location and REPLY_DIR
# to the clone directory (empty for local paths).
-zloom-resolve-location() {
    if [[ "$#" == 1 && ("${1[1]}" == '/' || "${1[1]}" == '.' ) ]]; then
        local location="${1}"
        REPLY="${location}"
        REPLY_DIR=""
    else
        local repo="${1}"
        local file="${2}"
        local branch="${3:-master}"
        local dir="$(-zloom-get-clone-dir ${repo} ${branch})"
        local location="${dir}/${file}"
        location=${location%/}

        # clone repo if not present
        if [[ ! -d "${dir}" ]]; then
            zloom-clone "${repo}" "${branch}"
        fi

        REPLY="${location}"
        REPLY_DIR="${dir}"
    fi
}

# Run the plugin-location cascade: source the plugin's script(s) or add the
# directory to fpath. ${1} is the location, ${2} the clone directory and
# ${3} the requested file (the latter two are only used for error
# reporting).
-zloom-visit-location() {
    local location="${1}"
    local dir="${2}"
    local file="${3}"

    # source the file
    if [[ -f "${location}" ]]; then
        -zloom-load-file "${location}"

    # Prezto modules have init.zsh files
    elif [[ -f "${location}/init.zsh" ]]; then
        -zloom-load-file "${location}/init.zsh"

    elif [[ -f "${location}.zsh-theme" ]]; then
        -zloom-load-file "${location}.zsh-theme"

    elif [[ -f "${location}.theme.zsh" ]]; then
        -zloom-load-file "${location}.theme.zsh"

    elif [[ -f "${location}.zshplugin" ]]; then
        -zloom-load-file "${location}.zshplugin"

    elif [[ -f "${location}.zsh.plugin" ]]; then
        -zloom-load-file "${location}.zsh.plugin"

    # Classic oh-my-zsh plugins have foo.plugin.zsh
    elif -zloom-path-contains "${location}" ".plugin.zsh" ; then
        for script (${location}/*\.plugin\.zsh(N)) -zloom-load-file "${script}"

    elif -zloom-path-contains "${location}" ".zsh" ; then
        for script (${location}/*\.zsh(N)) -zloom-load-file "${script}"

    elif -zloom-path-contains "${location}" ".sh" ; then
        for script (${location}/*\.sh(N)) -zloom-load-file "${script}"

    # Completions
    elif [[ -d "${location}" ]]; then
        -zloom-add-to-fpath "${location}"

    else
      if [[ -d ${dir:-$location} ]]; then
        -zlpute "Failed to load ${dir:-$location} -- ${file}"
      else
        -zlpute "Failed to load ${dir:-$location}"
      fi
      return 1
    fi
    return 0
}

zloom-load() {
    if [[ "$#" == 0 ]]; then
        -zlpute '`load` requires at least one parameter:'
        -zlpute '`zloom load <repo>[@ref] [location] [branch]`'
    else
        local -a _args=("${@}")
        # fisher-style `owner/repo@ref' pin: tag, branch or commit. The
        # ref overrides an explicit branch argument; URLs, git@ ssh
        # remotes and local paths are left untouched.
        -zloom-split-ref "${_args[1]}"
        if [[ -n "${REPLY_REF}" ]]; then
            _args=("${REPLY}" "${_args[2]:-}" "${REPLY_REF}")
        fi
        -zloom-resolve-location "${_args[@]}"
        local location="${REPLY}"
        local dir="${REPLY_DIR}"
        local file="${_args[2]}"
        -zloom-visit-location "${location}" "${dir}" "${file}"
    fi
}

# `zloom defer <repo> [location] [branch]`: like `zloom load`, but the
# plugin's scripts are recorded in ZLOOM_DEFERRED and sourced by
# -zloom-turbo-install as soon as the first prompt is on screen, instead of
# blocking shell startup (turbo mode). Completion directories still join
# fpath synchronously, so completions keep working as usual.
zloom-defer() {
    if [[ "$#" == 0 ]]; then
        -zlpute '`defer` requires at least one parameter:'
        -zlpute '`zloom defer <repo> [location] [branch]`'
        return 1
    fi

    ZLOOM_DEFERRING=1
    zloom-load "${@}"
    local rc=$?
    unset ZLOOM_DEFERRING
    return ${rc}
}

# --- Plugin manifest (fisher-style) -----------------------------------
# The manifest (${ZLOOM_PLUGINS}, default
# ${XDG_CONFIG_HOME:-${HOME}/.config}/zloom/plugins.zsh, falling back to
# a pre-existing ${ZLOOM_DIR}/plugins.zsh) is a plain-text list of
# everything zloom should load, one entry per line:
#
#     load zsh-users/zsh-completions src
#     defer zsh-users/zsh-autosuggestions
#     snippet https://example.com/config.zsh
#     env EDITOR=vim
#     alias ll 'ls -la'
#     eval /opt/homebrew/bin/brew shellenv
#     func hello 'echo Hello ${1:-zloom}'
#
# Besides plugins the manifest also records environment variables,
# aliases, eval commands and functions (`zloom env' / `zloom alias' /
# `zloom eval' / `zloom func'). `zloom add', `zloom del', `zloom
# snippet', `zloom env', `zloom alias', `zloom eval' and `zloom func'
# maintain the manifest and regenerate ${ZLOOM_INIT} from it. Blank lines
# and lines starting with a `#' are ignored. When the init script is
# missing, zloom rebuilds it from the manifest automatically (see
# zloom-init), so a new machine only needs the manifest file.

-zloom-manifest-append() {
    mkdir -p "${ZLOOM_PLUGINS:h}"
    -zlputs "$*" >> "${ZLOOM_PLUGINS}"
}

# Quote ${1} for a manifest line, but only when needed: words containing
# whitespace, quotes or backslashes are single-quoted so the (z)+(Q)
# lexing in -zloom-manifest-words round-trips them; plain words stay
# unquoted for a readable, fisher-style manifest.
-zloom-quote() {
    local w="${1}"
    if [[ -z "${w}" || "${w}" == *" "* || "${w}" == *$'\t'* || "${w}" == *"'"* \
            || "${w}" == *'"'* || "${w}" == *'\'* ]]; then
        REPLY="${(qq)w}"
    else
        REPLY="${w}"
    fi
}

# Lex one manifest line into the `reply' array: shell-style word splitting
# with comment and blank lines skipped and an unquoted trailing comment (a
# lone `#' word) removed. The (Q) flag performs quote removal, so quoted
# words (written by `zloom env'/`zloom alias' or by hand for values with
# spaces) arrive clean. An empty result means "skip this line".
-zloom-manifest-words() {
    reply=()
    local line="${1}"
    local i
    [[ "${line}" =~ '^[[:space:]]*($|#)' ]] && return 0
    reply=(${(Q)${(z)line}})
    for (( i = 1; i <= ${#reply}; i++ )); do
        if [[ "${reply[i]}" == "#" ]]; then
            reply=("${(@)reply[1,i-1]}")
            break
        fi
    done
    return 0
}

# Succeed when the manifest already has an entry named ${1} (the second
# field of a load/defer/snippet line).
-zloom-manifest-has() {
    local name="${1}"
    local line
    local -a words
    while IFS= read -r line; do
        -zloom-manifest-words "${line}"
        words=("${reply[@]}")
        if (( ${#words} >= 2 )) && [[ "${words[1]}" == (load|defer|snippet) ]] \
                && [[ "${words[2]}" == "${name}" ]]; then
            return 0
        fi
    done < "${ZLOOM_PLUGINS}"
    return 1
}

# Entry name used for matching in `zloom del' and -zloom-manifest-set:
# the second word of load/defer/snippet entries, the KEY/NAME part of
# `env KEY=VALUE', `alias NAME=VALUE' and `func NAME=BODY' entries (the
# latter also match hand-written NAME=VALUE lines), and the full command
# of `eval COMMAND' entries.
-zloom-manifest-key() {
    if [[ "${1}" == (env|alias|func) ]]; then
        REPLY="${${2}%%=*}"
    else
        REPLY="${2}"
    fi
}

# Replace every manifest entry whose key (see -zloom-manifest-key)
# equals ${1} with the single line ${2}, in place; fails when nothing
# matched. Used by `zloom env' / `zloom alias' to update an existing
# entry (hand-edited duplicates collapse into one line).
-zloom-manifest-set() {
    local key="${1}" new="${2}"
    local replaced=0
    local line
    local -a words out=()
    while IFS= read -r line; do
        -zloom-manifest-words "${line}"
        words=("${reply[@]}")
        if (( ${#words} >= 2 )) \
                && [[ "${words[1]}" == (load|defer|snippet|env|alias|func|eval) ]]; then
            -zloom-manifest-key "${words[1]}" "${words[2]}"
            if [[ "${REPLY}" == "${key}" ]]; then
                (( replaced )) || out+=("${new}")
                replaced=1
                continue
            fi
        fi
        out+=("${line}")
    done < "${ZLOOM_PLUGINS}"
    (( replaced )) || return 1
    if (( ${#out} )); then
        -zlputs "${out[@]}" >! "${ZLOOM_PLUGINS}"
    else
        : >! "${ZLOOM_PLUGINS}"
    fi
    return 0
}

# One-time note when a manifest is created for a setup that previously
# relied on the classic `if ! zloom saved' flow in .zshrc.
-zloom-manifest-adopt-note() {
    if [[ ! -f "${ZLOOM_PLUGINS}" && -f "${ZLOOM_INIT}" ]]; then
        -zlpute "note: creating ${ZLOOM_PLUGINS}; from now on the manifest is the"
        -zlpute "source of truth for init.zsh -- plugins currently loaded directly"
        -zlpute "in .zshrc should be added with \`zloom add' as well."
    fi
}

# Download a remote snippet into ${ZLOOM_DIR}/snippets; the cached path
# is reported in REPLY. ${2} forces a re-download (used by `zloom
# update'). The origin URL is kept in a `.url' sidecar file.
-zloom-fetch-snippet() {
    local url="${1}"
    local force="${2}"
    local dir="${ZLOOM_DIR}/snippets"
    local encoded="$(-zloom-encode-url "${url}")"
    local file="${dir}/${encoded}"

    REPLY="${file}"
    if [[ -z "${force}" && -s "${file}" ]]; then
        return 0
    fi

    if (( ! $+commands[curl] && ! $+commands[wget] )); then
        -zlpute "snippet: cannot fetch ${url}: neither curl nor wget found"
        return 1
    fi

    mkdir -p "${dir}"
    local tmp="${file}.tmp.$$"
    if (( $+commands[curl] )); then
        curl -fsSL --max-time 60 -o "${tmp}" "${url}" || { rm -f "${tmp}"; return 1; }
    else
        wget -q --timeout=60 -O "${tmp}" "${url}" || { rm -f "${tmp}"; return 1; }
    fi

    # Install atomically; a stale .zwc is recompiled on demand.
    mv -f "${tmp}" "${file}"
    -zlputs "${url}" >! "${file}.url"
    rm -f "${file}.zwc"
}

# Instruction behind manifest `snippet' entries: resolve a local path or
# remote URL to a single file and run it through the normal loading
# cascade (which records instead of sourcing while rebuilding). Relative
# paths resolve against the manifest directory, so a synced
# ~/.config/zloom works from any $HOME.
-zloom-snippet-apply() {
    local src="${1}"
    local file

    if [[ "${src}" == http://* || "${src}" == https://* ]]; then
        -zloom-fetch-snippet "${src}" || return 1
        file="${REPLY}"
    elif [[ -f "${src}" ]]; then
        file="${src:A}"
    elif [[ -f "${ZLOOM_PLUGINS:A:h}/${src}" ]]; then
        file="${ZLOOM_PLUGINS:A:h}/${src}"
    else
        -zlpute "snippet: no such file: ${src}"
        return 1
    fi

    -zloom-load-file "${file}"
}

# Instruction behind manifest `env' entries: export KEY=VALUE and
# record it in ZLOOM_ENV so zloom-save writes it into the init script.
# While rebuilding (ZLOOM_RECORDING) the export is skipped: `zloom env'
# already applied it live, and unrelated rebuilds (e.g. after `zloom
# add') must not clobber values overridden manually in this session.
-zloom-env-apply() {
    local entry="${1}"
    local key="${${entry}%%=*}"
    local value="${${entry}#*=}"

    if [[ "${entry}" != *=* ]] \
            || ! [[ "${key}" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]]; then
        -zlpute "env: expected KEY=VALUE with a valid name, got: ${entry}"
        return 1
    fi

    local i found=0
    for (( i = 1; i <= ${#ZLOOM_ENV}; i++ )); do
        if [[ "${${ZLOOM_ENV[i]}%%=*}" == "${key}" ]]; then
            ZLOOM_ENV[i]="${entry}"
            found=1
            break
        fi
    done
    (( found )) || ZLOOM_ENV+=("${entry}")

    [[ -n "${ZLOOM_RECORDING}" ]] && return 0
    export "${key}=${value}"
    return 0
}

# Instruction behind manifest `alias' entries: define the alias and
# record it in ZLOOM_ALIAS (same recording semantics as
# -zloom-env-apply). Accepts either the two-word form zloom writes
# (NAME, COMMAND) or, for hand-written `alias NAME=COMMAND' lines, a
# single NAME=COMMAND word.
-zloom-alias-apply() {
    local name="${1}"
    local value="${2}"

    # `alias NAME=COMMAND' shorthand: a lone word containing an =.
    if [[ -z "${value}" && "${name}" == *=* ]]; then
        value="${${name}#*=}"
        name="${${name}%%=*}"
    fi

    if ! [[ "${name}" =~ '^[A-Za-z_][A-Za-z0-9_:-]*$' ]]; then
        -zlpute "alias: invalid alias name: ${name}"
        return 1
    fi
    if [[ -z "${value}" ]]; then
        -zlpute "alias: ${name} is missing its command"
        return 1
    fi

    local i found=0
    for (( i = 1; i <= ${#ZLOOM_ALIAS}; i++ )); do
        if [[ "${${ZLOOM_ALIAS[i]}%%=*}" == "${name}" ]]; then
            ZLOOM_ALIAS[i]="${name}=${value}"
            found=1
            break
        fi
    done
    (( found )) || ZLOOM_ALIAS+=("${name}=${value}")

    [[ -n "${ZLOOM_RECORDING}" ]] && return 0
    alias "${name}=${value}"
    return 0
}

# Instruction behind manifest `eval' entries: run `eval "$(command)"'
# and record it in ZLOOM_EVAL. The command runs even while rebuilding
# (ZLOOM_RECORDING) so broken entries fail loudly; only the evaluation
# of its output is skipped then, mirroring the env/alias recording
# semantics.
-zloom-eval-apply() {
    local cmd="${1}"

    if [[ -z "${cmd}" ]]; then
        -zlpute "eval: missing command"
        return 1
    fi

    if (( ${ZLOOM_EVAL[(Ie)${cmd}]} )); then
        return 0
    fi

    local out
    # ${=cmd}: zsh does not word-split unquoted parameter expansions, so
    # the command has to be split explicitly before $() can run it.
    if ! out="$(${=cmd})"; then
        -zlpute "eval: command failed: ${cmd}"
        return 1
    fi
    ZLOOM_EVAL+=("${cmd}")

    [[ -n "${ZLOOM_RECORDING}" ]] && return 0
    eval "${out}"
    return 0
}

# Instruction behind manifest `func' entries: define a function and
# record it in ZLOOM_FUNC as NAME=BODY (same recording semantics as
# -zloom-env-apply). Accepts either the two-word form zloom writes
# (NAME, BODY) or, for hand-written `func NAME=BODY' lines, a single
# NAME=BODY word. The body is stored and emitted verbatim as zsh code
# on a single line.
-zloom-func-apply() {
    local name="${1}"
    local body="${2}"

    # `func NAME=BODY' shorthand: a lone word containing an =.
    if [[ -z "${body}" && "${name}" == *=* ]]; then
        body="${${name}#*=}"
        name="${${name}%%=*}"
    fi

    if ! [[ "${name}" =~ '^[A-Za-z_][A-Za-z0-9_:-]*$' ]]; then
        -zlpute "func: invalid function name: ${name}"
        return 1
    fi
    if [[ -z "${body}" ]]; then
        -zlpute "func: ${name} is missing its body"
        return 1
    fi

    local i found=0
    for (( i = 1; i <= ${#ZLOOM_FUNC}; i++ )); do
        if [[ "${${ZLOOM_FUNC[i]}%%=*}" == "${name}" ]]; then
            ZLOOM_FUNC[i]="${name}=${body}"
            found=1
            break
        fi
    done
    (( found )) || ZLOOM_FUNC+=("${name}=${body}")

    [[ -n "${ZLOOM_RECORDING}" ]] && return 0
    eval "${name}() { ${body} }"
    return 0
}

# Replay the manifest through the load/defer/snippet/env/eval/alias/func
# instructions. Entries execute in the same phase order as the
# generated init.zsh, regardless of their position in the file:
# env entries first (plugins may rely on them), then eval entries
# (dynamic environment: PATH, generated functions), then
# load/defer/snippet in manifest order, then aliases and functions (so
# they win over plugin-provided ones). Used by -zloom-rebuild, with
# ZLOOM_RECORDING set (or live, during the first-shell bootstrap).
-zloom-replay-manifest() {
    local line phase
    local -a words
    # A functions-only setup has no manifest file yet; nothing to replay.
    [[ -f "${ZLOOM_PLUGINS}" ]] || return 0
    for phase in env eval plugins aliases functions; do
        while IFS= read -r line; do
            -zloom-manifest-words "${line}"
            words=("${reply[@]}")
            (( ${#words} )) || continue
            case "${words[1]}" in
                load|defer|snippet)
                    [[ "${phase}" == plugins ]] || continue
                    case "${words[1]}" in
                        load)    zloom-load "${(@)words[2,-1]}" ;;
                        defer)   zloom-defer "${(@)words[2,-1]}" ;;
                        snippet) -zloom-snippet-apply "${words[2]}" \
                                     || -zlpute "manifest: failed to load snippet ${words[2]}" ;;
                    esac
                    ;;
                env)
                    [[ "${phase}" == env ]] || continue
                    -zloom-env-apply "${words[2]}" \
                        || -zlpute "manifest: ignoring bad env entry: ${line}" ;;
                eval)
                    [[ "${phase}" == eval ]] || continue
                    -zloom-eval-apply "${(j: :)words[2,-1]}" \
                        || -zlpute "manifest: ignoring bad eval entry: ${line}" ;;
                alias)
                    [[ "${phase}" == aliases ]] || continue
                    -zloom-alias-apply "${words[2]}" "${(j: :)words[3,-1]}" \
                        || -zlpute "manifest: ignoring bad alias entry: ${line}" ;;
                func)
                    [[ "${phase}" == functions ]] || continue
                    -zloom-func-apply "${words[2]}" "${(j: :)words[3,-1]}" \
                        || -zlpute "manifest: ignoring bad func entry: ${line}" ;;
                *)
                    [[ "${phase}" == plugins ]] || continue
                    -zlpute "manifest: ignoring unknown entry: ${line}" ;;
            esac
        done < "${ZLOOM_PLUGINS}"
    done
}

# Regenerate ${ZLOOM_INIT} from the manifest. With `live' (fresh-shell
# bootstrap) the entries are actually sourced first, mirroring the
# classic `zloom load ...; zloom save' flow; otherwise they are only
# recorded, because the plugins may already be active in this session.
-zloom-rebuild() {
    if [[ "${1}" == live ]]; then
        local _zloom_cf _zloom_ff _zloom_th
        local _zloom_cfg="${ZLOOM_PLUGINS:h}"

        # The bootstrap shell never sources the freshly generated
        # init.zsh, so mirror its order here to make the first shell
        # fully functional: conf.d + config.zsh ahead of the plugins
        # (PATH ready), function files and themes after them.
        for _zloom_cf in "${_zloom_cfg}"/conf.d/*.zsh(N); do
            source "${_zloom_cf}"
        done
        [[ -f "${_zloom_cfg}/config.zsh" ]] && source "${_zloom_cfg}/config.zsh"

        -zloom-replay-manifest
        zloom-save

        for _zloom_ff in "${_zloom_cfg}"/functions/*.zsh(N); do
            [[ -s "${_zloom_ff}.zwc" && "${_zloom_ff}" -nt "${_zloom_ff}.zwc" ]] \
                || zcompile -U -- "${_zloom_ff}" 2>/dev/null
            source "${_zloom_ff}"
        done
        for _zloom_th in "${_zloom_cfg}"/themes/*.zsh(N); do
            source "${_zloom_th}"
        done

        # ... and the turbo hook last, exactly like the init script (it
        # loads synchronously in non-interactive shells).
        -zloom-turbo-install
        return
    fi

    # Files sourced earlier in this session that are still deferred by
    # the manifest keep their "already loaded" marker, so the turbo hook
    # armed by `zloom add --defer' does not source them a second time.
    # Entries removed from the manifest deliberately lose theirs.
    local -a _sourced=("${ZLOOM_LOADED[@]}")
    local _f

    ZLOOM_LOADED=()
    ZLOOM_DEFERRED=()
    ZLOOM_COMPLETIONS=()
    ZLOOM_ENV=()
    ZLOOM_ALIAS=()
    ZLOOM_EVAL=()
    ZLOOM_FUNC=()

    ZLOOM_RECORDING=1
    -zloom-replay-manifest
    unset ZLOOM_RECORDING

    local -a _keep=()
    for _f in "${_sourced[@]}"; do
        [[ " ${ZLOOM_DEFERRED[@]} " == *" ${_f} "* ]] && _keep+=("${_f}")
    done
    ZLOOM_LOADED=("${_keep[@]}" "${ZLOOM_LOADED[@]}")

    zloom-save
}

# `zloom snippet <url-or-path>': load a single local or remote
# configuration file (like `zinit snippet'), record it in the manifest
# and regenerate the init script. Remote files are cached under
# ${ZLOOM_DIR}/snippets and refreshed by `zloom update'.
zloom-snippet() {
    if [[ "$#" != 1 ]]; then
        -zlpute '`snippet` requires exactly one parameter:'
        -zlpute '`zloom snippet <url-or-path>`'
        return 1
    fi
    local src="${1}"
    local cfgdir="${ZLOOM_PLUGINS:A:h}"

    # Local paths may be given relative to the manifest directory.
    if [[ "${src}" != http://* && "${src}" != https://* && ! -f "${src}" ]] \
            && [[ -f "${cfgdir}/${src}" ]]; then
        src="${cfgdir}/${src}"
    fi

    if [[ "${src}" != http://* && "${src}" != https://* && ! -f "${src}" ]]; then
        -zlpute "snippet: no such file: ${src}"
        return 1
    fi

    # Store local paths absolute so later rebuilds work from any cwd;
    # paths inside the manifest's own directory are stored relative to
    # it, so the whole config folder stays portable across machines.
    if [[ "${src}" != http://* && "${src}" != https://* ]]; then
        local abs="${src:A}"
        if [[ "${abs}" == "${cfgdir}"/* ]]; then
            src="${abs:$(( ${#cfgdir} + 1 ))}"
        else
            src="${abs}"
        fi
    fi

    if [[ -f "${ZLOOM_PLUGINS}" ]] && -zloom-manifest-has "${src}"; then
        -zlpute "snippet: ${src} is already listed in ${ZLOOM_PLUGINS}"
        return 1
    fi

    -zloom-snippet-apply "${src}" || return 1

    -zloom-quote "${src}"
    -zloom-manifest-append "snippet ${REPLY}"
    -zloom-rebuild
    -zlpute "snippet ${src} loaded; listed in ${ZLOOM_PLUGINS}"
}

# `zloom add [--defer] <plugin> [location] [branch]': clone (if needed)
# and load a plugin right away, record it in the manifest and regenerate
# the init script. With --defer the plugin is loaded by turbo mode
# right after the first prompt instead (see `zloom defer').
zloom-add() {
    local defer=""
    local -a args=()
    local arg
    for arg in "${@}"; do
        case "${arg}" in
            --defer|-d) defer=1 ;;
            *) args+=("${arg}") ;;
        esac
    done

    if (( ${#args} == 0 )); then
        -zlpute '`add` requires at least one parameter:'
        -zlpute '`zloom add [--defer] <plugin>[@ref] [location] [branch]`'
        return 1
    fi

    # When no branch is pinned, remember the remote's default branch in
    # the manifest (`user/repo@main'): clone dirs embed the branch, so a
    # recorded pin keeps later rebuilds deterministic and offline-safe.
    if (( ${#args} == 1 )); then
        local _repo="${args[1]}"
        -zloom-split-ref "${_repo}"
        _repo="${REPLY}"
        if [[ -z "${REPLY_REF}" && "${_repo}" != /* && "${_repo}" != .* ]]; then
            -zloom-default-branch "${_repo}"
            if [[ -n "${REPLY}" && "${REPLY}" != master ]]; then
                args[1]="${args[1]}@${REPLY}"
                -zlpute "add: ${_repo} defaults to branch ${REPLY}; pinning it"
            elif [[ -z "${REPLY}" ]]; then
                # Remote unreachable: pin @HEAD so the clone follows the
                # remote's default branch instead of assuming master.
                args[1]="${args[1]}@HEAD"
                -zlpute "add: cannot reach ${_repo}; pinning @HEAD (default branch)"
            fi
        fi
    fi

    -zloom-manifest-adopt-note

    local plugin="${args[1]}"
    if [[ -f "${ZLOOM_PLUGINS}" ]] && -zloom-manifest-has "${plugin}"; then
        -zlpute "add: ${plugin} is already listed in ${ZLOOM_PLUGINS}"
        return 1
    fi

    # Load (and clone if needed) right away so the plugin is active in
    # this session too.
    if [[ -n "${defer}" ]]; then
        zloom-defer "${args[@]}" || return 1
    else
        zloom-load "${args[@]}" || return 1
    fi

    # Quote each argument for the manifest so paths with spaces
    # round-trip through the (z)+(Q) lexing (see -zloom-quote).
    local -a _qargs=()
    for arg in "${args[@]}"; do
        -zloom-quote "${arg}"
        _qargs+=("${REPLY}")
    done
    if [[ -n "${defer}" ]]; then
        -zloom-manifest-append "defer ${_qargs[*]}"
    else
        -zloom-manifest-append "load ${_qargs[*]}"
    fi
    -zloom-rebuild

    if [[ -n "${defer}" ]]; then
        # Make the new plugin active in this session as well: the hook
        # only sources entries not already marked in ZLOOM_LOADED.
        -zloom-turbo-install
    fi
    -zlpute "added ${plugin}; listed in ${ZLOOM_PLUGINS}"
    -zloom-hook add "${plugin}"
}

# `zloom env KEY=VALUE' (or `zloom env KEY VALUE'): export KEY right away,
# record the entry in the manifest and regenerate the init script. In
# the generated init.zsh the entry is exported before anything else,
# so plugins can rely on it. Re-running `zloom env' for the same KEY
# updates the entry in place.
zloom-env() {
    local entry key
    local line

    if (( $# == 1 )); then
        entry="${1}"
    elif (( $# == 2 )); then
        entry="${1}=${2}"
    else
        -zlpute '`env` takes a KEY=VALUE pair:'
        -zlpute '`zloom env KEY=VALUE`  or  `zloom env KEY VALUE`'
        return 1
    fi

    # Apply (and validate) before touching the manifest.
    -zloom-env-apply "${entry}" || return 1
    key="${${entry}%%=*}"
    -zloom-quote "${${entry}#*=}"
    line="env ${key}=${REPLY}"

    -zloom-manifest-adopt-note
    if [[ ! -f "${ZLOOM_PLUGINS}" ]] || ! -zloom-manifest-set "${key}" "${line}"; then
        -zloom-manifest-append "${line}"
    fi
    -zloom-rebuild
    -zlpute "env ${key} exported; listed in ${ZLOOM_PLUGINS}"
}

# `zloom alias NAME=COMMAND' (or `zloom alias NAME COMMAND...'): define
# the alias right away, record the entry in the manifest and regenerate
# the init script. In the generated init.zsh aliases are defined after
# all plugins are sourced, so they win over plugin-provided aliases.
# Re-running `zloom alias' for the same NAME updates the entry in place.
zloom-alias() {
    local name value qname
    local line
    local -a _args=("${@}")

    if (( ${#_args} == 1 )) && [[ "${_args[1]}" == *=* ]]; then
        name="${${_args[1]}%%=*}"
        value="${${_args[1]}#*=}"
    elif (( ${#_args} >= 2 )); then
        name="${_args[1]}"
        value="${(j: :)_args[2,-1]}"
    fi
    if [[ -z "${name}" ]]; then
        -zlpute '`alias` takes a NAME=COMMAND pair:'
        -zlpute '`zloom alias NAME=COMMAND`  or  `zloom alias NAME COMMAND...`'
        return 1
    fi

    -zloom-alias-apply "${name}" "${value}" || return 1
    -zloom-quote "${name}"
    qname="${REPLY}"
    -zloom-quote "${value}"
    line="alias ${qname} ${REPLY}"

    -zloom-manifest-adopt-note
    if [[ ! -f "${ZLOOM_PLUGINS}" ]] || ! -zloom-manifest-set "${name}" "${line}"; then
        -zloom-manifest-append "${line}"
    fi
    -zloom-rebuild
    -zlpute "alias ${name} defined; listed in ${ZLOOM_PLUGINS}"
}

# `zloom eval <command...>': run `eval "$(command)"' right away, record
# the entry in the manifest and regenerate the init script. In the
# generated init.zsh eval entries run after the env exports but before
# any plugin is sourced, so plugins see the PATH and functions they set
# up. The command must succeed and its output is evaluated as zsh code,
# so only use commands that print shell code (brew shellenv, rbenv
# init ...). Re-running `zloom eval' with the same command replaces the
# entry in place; `zloom del' cannot undo an eval in the running shell.
zloom-eval() {
    local cmd line

    if (( $# == 0 )); then
        -zlpute '`eval` requires a command:'
        -zlpute '`zloom eval <command...>`'
        return 1
    fi
    cmd="${*}"

    # Apply (and validate) before touching the manifest.
    -zloom-eval-apply "${cmd}" || return 1
    -zloom-quote "${cmd}"
    line="eval ${REPLY}"

    -zloom-manifest-adopt-note
    if [[ ! -f "${ZLOOM_PLUGINS}" ]] || ! -zloom-manifest-set "${cmd}" "${line}"; then
        -zloom-manifest-append "${line}"
    fi
    -zloom-rebuild
    -zlpute "eval ${cmd} applied; listed in ${ZLOOM_PLUGINS}"
}

# `zloom func NAME BODY...' (or `zloom func NAME=BODY'): define the
# function right away, record the entry in the manifest and regenerate
# the init script. In the generated init.zsh functions are defined after
# all plugins and aliases, so they win over plugin-provided ones. The
# body is stored as a single line; anything larger belongs in a snippet.
# Re-running `zloom func' for the same NAME updates the entry in place.
zloom-func() {
    local name body qname
    local line
    local -a _args=("${@}")

    if (( ${#_args} == 1 )) && [[ "${_args[1]}" == *=* ]]; then
        name="${${_args[1]}%%=*}"
        body="${${_args[1]}#*=}"
    elif (( ${#_args} >= 2 )); then
        name="${_args[1]}"
        body="${(j: :)_args[2,-1]}"
    fi
    if [[ -z "${name}" ]]; then
        -zlpute '`func` takes a NAME and a BODY:'
        -zlpute '`zloom func NAME BODY...`  or  `zloom func NAME=BODY`'
        return 1
    fi

    -zloom-func-apply "${name}" "${body}" || return 1
    -zloom-quote "${name}"
    qname="${REPLY}"
    -zloom-quote "${body}"
    line="func ${qname} ${REPLY}"

    -zloom-manifest-adopt-note
    if [[ ! -f "${ZLOOM_PLUGINS}" ]] || ! -zloom-manifest-set "${name}" "${line}"; then
        -zloom-manifest-append "${line}"
    fi
    -zloom-rebuild
    -zlpute "func ${name} defined; listed in ${ZLOOM_PLUGINS}"
}

# `zloom del <name>': remove the plugin (or snippet) named ${1} from the
# manifest and regenerate the init script. The cloned files stay on
# disk, exactly like `zloom reset'; this only stops loading them. It
# cannot unload a plugin from the running shell.
zloom-del() {
    if [[ "$#" != 1 ]]; then
        -zlpute '`del` requires exactly one parameter:'
        -zlpute '`zloom del <plugin | snippet | env-KEY | alias-NAME | func-NAME>`'
        return 1
    fi
    local name="${1}"

    if [[ ! -f "${ZLOOM_PLUGINS}" ]]; then
        -zlpute "del: manifest ${ZLOOM_PLUGINS} not found"
        return 1
    fi

    local -a keep=()
    local removed=0 unset_env=0 unset_alias=0 unset_func=0
    local line
    local -a words
    while IFS= read -r line; do
        -zloom-manifest-words "${line}"
        words=("${reply[@]}")
        if (( ${#words} >= 2 )) \
                && [[ "${words[1]}" == (load|defer|snippet|env|alias|func|eval) ]]; then
            -zloom-manifest-key "${words[1]}" "${words[2]}"
            if [[ "${REPLY}" == "${name}" ]]; then
                removed=1
                [[ "${words[1]}" == env ]] && unset_env=1
                [[ "${words[1]}" == alias ]] && unset_alias=1
                [[ "${words[1]}" == func ]] && unset_func=1
            else
                keep+=("${line}")
            fi
        else
            keep+=("${line}")
        fi
    done < "${ZLOOM_PLUGINS}"

    if (( ! ${removed} )); then
        -zlpute "del: no manifest entry named ${name}"
        return 1
    fi

    if (( ${#keep} )); then
        -zlputs "${keep[@]}" >! "${ZLOOM_PLUGINS}"
    else
        : >! "${ZLOOM_PLUGINS}"
    fi
    -zloom-rebuild

    # Also remove the entry's effect from the running shell. Plugins and
    # eval entries cannot be unloaded (see above); env values, aliases
    # and functions can.
    (( unset_env )) && unset "${name}"
    (( unset_alias )) && unalias "${name}" 2>/dev/null
    (( unset_func )) && unfunction "${name}" 2>/dev/null

    -zlpute "removed ${name} (files stay on disk; init.zsh regenerated)"
    -zloom-hook del "${name}"
}

# `zloom sync [--clean]': make the world match the manifest — fisher's
# update model. Clones every load/defer repository that is missing on
# disk (concurrently), regenerates init.zsh from the manifest, and runs
# `zloom clean' on the result (deleting unreferenced clones with
# --clean). Hand edits to the manifest thus take effect with one
# command, no `zloom reset' plus a new shell needed.
zloom-sync() {
    local clean="" update=""
    while [[ "${1}" == -* ]]; do
        case "${1}" in
            --clean|-c)  clean=1 ;;
            --update|-u) update=1 ;;
            *)
                -zlpute '`sync` takes no positional parameters:'
                -zlpute '`zloom sync [--clean] [--update]`'
                return 1
                ;;
        esac
        shift
    done
    if (( $# > 0 )); then
        -zlpute '`sync` takes no positional parameters:'
        -zlpute '`zloom sync [--clean] [--update]`'
        return 1
    fi
    if [[ ! -f "${ZLOOM_PLUGINS}" ]]; then
        -zlpute "sync: manifest ${ZLOOM_PLUGINS} not found"
        return 1
    fi

    # Prefetch missing clones concurrently; the rebuild below then finds
    # every directory present and records entries in manifest order.
    # Repositories that fail to clone surface as load errors in the
    # rebuild, keeping the reporting in one place.
    local line repo branch dir
    local -a words jobs=()
    while IFS= read -r line; do
        -zloom-manifest-words "${line}"
        words=("${reply[@]}")
        (( ${#words} >= 2 )) || continue
        [[ "${words[1]}" == (load|defer) ]] || continue
        repo="${words[2]}"
        branch="${words[4]:-master}"
        -zloom-split-ref "${repo}"
        repo="${REPLY}"
        [[ -n "${REPLY_REF}" ]] && branch="${REPLY_REF}"
        [[ "${repo}" == /* || "${repo}" == .* ]] && continue
        -zloom-set-clone-dir "${repo}" "${branch}"
        dir="${REPLY}"
        [[ -d "${dir}" ]] && continue
        -zlpute "sync: cloning ${repo}@${branch} ..."
        ( zloom-clone "${repo}" "${branch}" ) &
        jobs+=($!)
    done < "${ZLOOM_PLUGINS}"
    (( ${#jobs} )) && wait "${jobs[@]}"

    # --update also pulls existing clones (fisher's update = reconcile
    # + fetch in one command).
    if [[ -n "${update}" ]]; then
        -zloom-pull-all \
            || -zlpute "sync: one or more repositories failed to update"
    fi

    -zloom-rebuild

    # Clones the manifest no longer references: report, or delete.
    if [[ -n "${clean}" ]]; then
        zloom-clean --force
    else
        zloom-clean
    fi
    -zloom-hook sync
    return 0
}

# `zloom clean': remove cloned plugins that the manifest no longer lists.
# Without --force it is a dry run that only reports them. Snippets and the
# zloom installation itself are never touched.
zloom-clean() {
    local force=""
    if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
        force=1
        shift
    fi
    if (( $# > 0 )); then
        -zlpute '`clean` takes no parameters:'
        -zlpute '`zloom clean [--force]`'
        return 1
    fi
    if [[ -z "${ZLOOM_DIR}" || ! -d "${ZLOOM_DIR}" ]]; then
        -zlpute "clean: ZLOOM_DIR is empty or missing; refusing to scan"
        return 1
    fi
    if [[ ! -f "${ZLOOM_PLUGINS}" ]]; then
        -zlpute "clean: manifest ${ZLOOM_PLUGINS} not found"
        return 1
    fi

    # Clone directories the manifest still references (load/defer entries;
    # single-argument /path or ./path entries load in place and have no
    # clone).
    local -a used=()
    local line repo branch
    local -a words
    while IFS= read -r line; do
        -zloom-manifest-words "${line}"
        words=("${reply[@]}")
        (( ${#words} )) || continue
        case "${words[1]}" in
            load|defer)
                repo="${words[2]}"
                branch="${words[4]:-master}"
                -zloom-split-ref "${repo}"
                repo="${REPLY}"
                [[ -n "${REPLY_REF}" ]] && branch="${REPLY_REF}"
                if (( ${#words} > 2 )) \
                        || [[ "${repo[1]}" != / && "${repo[1]}" != . ]]; then
                    -zloom-set-clone-dir "${repo}" "${branch}"
                    used+=("${REPLY}")
                fi
                ;;
        esac
    done < "${ZLOOM_PLUGINS}"

    # Clones actually on disk: location/repo-branch two levels below
    # ZLOOM_DIR; .git (the zloom clone itself) and the snippets cache are
    # never candidates.
    local -a candidates=()
    local loc sub
    for loc in "${ZLOOM_DIR}"/*(N/); do
        [[ "${loc:t}" == .git || "${loc:t}" == snippets ]] && continue
        for sub in "${loc}"/*(N/); do
            candidates+=("${sub}")
        done
    done

    local -a unused=()
    for sub in "${candidates[@]}"; do
        [[ " ${used[@]} " == *" ${sub} "* ]] || unused+=("${sub}")
    done

    if (( ! ${#unused} )); then
        -zlpute "clean: every cloned plugin is listed in ${ZLOOM_PLUGINS}"
        return 0
    fi

    -zlpute "cloned plugins not in ${ZLOOM_PLUGINS}:"
    for sub in "${unused[@]}"; do
        -zlputs "  ${sub}"
    done

    if [[ -z "${force}" ]]; then
        -zlpute 'dry run: re-run with `zloom clean --force` to delete them'
        return 0
    fi

    for sub in "${unused[@]}"; do
        # Belt and braces: never delete anything that escaped ZLOOM_DIR.
        if [[ "${sub}" != "${ZLOOM_DIR}"/* ]]; then
            -zlpute "clean: skipping suspicious path ${sub}"
            continue
        fi
        -zlpute "Removing ${sub} ..."
        rm -rf "${sub}"
        rmdir "${sub:h}" 2>/dev/null
    done

    # A stale init.zsh (e.g. generated before the manifest existed) may
    # still source what we just deleted; reset it so the next shell
    # rebuilds cleanly from the manifest.
    if [[ -f "${ZLOOM_INIT}" ]]; then
        local stale=0
        for sub in "${unused[@]}"; do
            grep -qF -- "${sub}" "${ZLOOM_INIT}" && stale=1
        done
        if (( stale )); then
            -zlpute "init.zsh references removed plugins; resetting (rebuilt from the manifest)"
            zloom-reset
        fi
    fi
}

# `zloom list': show the manifest entries with their kind — `load'
# (synchronous), `defer' (turbo, after the first prompt), `snippet'
# (single file), `env', `eval', `alias' and `func' — in load order.
# Legacy setups without a manifest keep the old behaviour: dump the
# generated init script.
zloom-list() {
    if [[ ! -f "${ZLOOM_PLUGINS}" ]]; then
        if [[ -f "${ZLOOM_INIT}" ]]; then
            cat "${ZLOOM_INIT}"
            return 0
        fi
        -zlpute '`init.zsh` missing, please use `zloom save` and then restart your shell.'
        return 1
    fi

    local line
    local -a words
    while IFS= read -r line; do
        -zloom-manifest-words "${line}"
        words=("${reply[@]}")
        (( ${#words} )) || continue
        case "${words[1]}" in
            load|defer|snippet)
                printf '%-9s%s\n' "${words[1]}" "${(j: :)words[2,-1]}"
                ;;
            env)
                printf '%-9s%s\n' env "${words[2]}"
                ;;
            eval)
                printf '%-9s%s\n' eval "${(j: :)words[2,-1]}"
                ;;
            alias)
                if (( ${#words} == 2 )); then
                    # hand-written `alias NAME=COMMAND' line
                    printf '%-9s%s\n' alias "${words[2]}"
                else
                    printf '%-9s%s\n' alias "${words[2]}=${(j: :)words[3,-1]}"
                fi
                ;;
            func)
                if (( ${#words} == 2 )); then
                    # hand-written `func NAME=BODY' line
                    printf '%-9s%s\n' func "${words[2]}"
                else
                    printf '%-9s%s\n' func "${words[2]}() { ${(j: :)words[3,-1]} }"
                fi
                ;;
            *)
                # Unknown entries are flagged so they get noticed (the
                # replay reports them as ignored as well).
                printf '%-9s%s\n' '?' "${(j: :)words}"
                ;;
        esac
    done < "${ZLOOM_PLUGINS}"
}

zloom-loadall() {
    # shameless copy from antigen

    # Bulk add many bundles at one go. Empty lines and lines starting with a `#`
    # are ignored. Everything else is given to `zloom-load` as is, no
    # quoting rules applied.

    local line

    grep '^[[:space:]]*[^[:space:]#]' | while read line; do
        # Using `eval` so that we can use the shell-style quoting in each line
        # piped to `antigen-bundles`.
        eval "zloom-load $line"
    done
}

zloom-saved() {
    [[ -f "${ZLOOM_INIT}" ]] && return 0 || return 1
}

zloom-selfupdate() {
    if [[ -e "${ZLOOM_SOURCE}/.git" ]]; then
        (cd "${ZLOOM_SOURCE}" \
            && git pull) \
            && zloom reset
    else
        -zlpute "Not running from a git repository; cannot automatically update."
        return 1
    fi
}

zloom-oh-my-zsh() {
    local repo="$ZLOOM_OH_MY_ZSH_REPO"
    local file="${1:-oh-my-zsh.sh}"

    zloom-load "${repo}" "${file}"
}

zloom-prezto() {
    local repo="$ZLOOM_PREZTO_REPO"
    local file="${1:-init.zsh}"

    # load prezto itself
    if [[ $# == 0 ]]; then
        ZLOOM_USE_PREZTO=1
        zloom-load "${repo}" "${file}"
        if [[ ${ZLOOM_PREZTO_LOAD_DEFAULT} != 0 ]]; then
            -zloom-prezto-load "'environment' 'terminal' 'editor' 'history' 'directory' 'spectrum' 'utility' 'completion' 'prompt'"
        fi

    # this is a prezto module
    elif [[ $# == 1 ]]; then
        local module=${file}
        if [[ -z ${file} ]]; then
            -zlpute 'Please specify which module to load using `zloom prezto <name of module>`'
            return 1
        fi
        -zloom-prezto-load "'$module'"

    # this is a prezto option
    else
        shift
        -zloom-prezto-option ${file} ${(qq)@}
    fi

}

zloom-pmodule() {
    local repo="${1}"
    local branch="${2:-master}"

    local dir="$(-zloom-get-clone-dir ${repo} ${branch})"

    # clone repo if not present
    if [[ ! -d "${dir}" ]]; then
        zloom-clone "${repo}" "${branch}"
    fi

    local module="${repo:t}"
    -zloom-prezto-load "'${module}'"
}

zloom() {
    local cmd="${1}"
    if [[ -z "${cmd}" ]]; then
        -zlputs 'usage: `zloom [command | instruction] [options]`'
        -zlputs "    plugin management: add, del, snippet, clean"
        -zlputs '    settings: env, alias, func, eval'
        -zlputs "    commands: list, saved, reset, sync, clone, update, selfupdate"
        -zlputs "    instructions: load, defer, oh-my-zsh, pmodule, prezto, save, apply"
        return 1
    fi

    shift

    if functions "zloom-${cmd}" > /dev/null ; then
        "zloom-${cmd}" "${@}"
    else
        -zlpute 'Command not found: `'"${cmd}"\`
        return 1
    fi
}

-zloom-set-zsh
ZSH="${REPLY}"
fpath=($ZLOOM_SOURCE $fpath)
zloom-init
