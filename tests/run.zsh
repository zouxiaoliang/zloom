#!/bin/zsh
# zloom regression suite. Usage: zsh tests/run.zsh
#
# Every test runs in its own sandbox (temp HOME / XDG_CONFIG_HOME /
# ZLOOM_DIR). No network access: remote plugins are simulated with local
# bare git repositories reached through file:// URLs.
#
# exit status: 0 when every check passed, 1 otherwise.

emulate -L zsh
setopt extended_glob

REPO="${0:A:h:h}"
integer passed=0 failed=0

ok()  { (( passed++ )); print -r -- "  ok   $1"; }
no()  { (( failed++ ));  print -r -- "  FAIL $1${2:+ — expected [$2] got [$3]}"; }
check() {  # label expected actual
    if [[ "${3}" == "${2}" ]]; then ok "${1}"; else no "${1}" "${2}" "${3}"; fi
}

T=""           # current sandbox root
# Fresh sandbox with an (optionally empty) config directory.
sandbox() {
    T="$(mktemp -d)"
    mkdir -p "${T}/xdg/zloom" "${T}/home"
}
zl() {  # run a script inside the current sandbox
    zsh -c "
        export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home'
        source '${REPO}/zloom.zsh'
        ${1}
    " 2>&1
}
# Create a bare repository at $1.git with tag v1 shipping plug.plugin.zsh.
gitfix() {
    local w
    git init -q -b master "${1}.work"
    printf 'PLUGIN_TAG=ok\n' > "${1}.work/plug.plugin.zsh"
    git -C "${1}.work" add -A
    git -C "${1}.work" -c user.email=t@t -c user.name=t commit -qm fixture
    git -C "${1}.work" tag v1
    git init -q --bare -b master "${1}.git"
    git -C "${1}.work" push -q "${1}.git" master v1
    rm -rf "${1}.work"
}

print "1. bootstrap: manifest -> init.zsh -> fast path"
sandbox
print -r -- 'env SM=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'zloom saved >/dev/null && echo built' | grep -q built && ok "first shell builds init.zsh" || no "first shell builds init.zsh"
zl 'echo "env=${SM:-?} fast=$([[ -f ${ZLOOM_INIT} ]] && echo yes)"' | grep -q 'env=1 fast=yes' \
    && ok "second shell sources init (env applied)" || no "second shell sources init (env applied)"
rm -rf "${T}"

print "2. (qq) emission regression: alias/export values survive re-parsing"
sandbox
cat >! "${T}/xdg/zloom/plugins.zsh" <<'EOF'
env GREETING='hello world'
alias list_proxy 'echo "http_proxy=${http_proxy:=}";echo "https_proxy=${https_proxy:=}";'
alias spaced 'echo a  b'
EOF
zl 'zloom saved >/dev/null' >/dev/null
zsh -f -c "
    export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home'
    source '${T}/data/init.zsh'
    print -r -- \"lp=[\${aliases[list_proxy]:-FAIL}]\"
    print -r -- \"sp=[\${aliases[spaced]:-FAIL}]\"
    print -r -- \"gr=[\${GREETING:-FAIL}]\"
" >! "${T}/out"
check "alias with \${var:=} round-trips" \
    'echo "http_proxy=${http_proxy:=}";echo "https_proxy=${https_proxy:=}";' "$(sed -n 's/^lp=\[//p' "${T}/out" | sed 's/\]$//')"
grep -qF 'sp=[echo a  b]' "${T}/out" && ok "alias with double spaces round-trips" || no "alias with double spaces round-trips"
grep -qF 'gr=[hello world]' "${T}/out" && ok "export with spaces round-trips" || no "export with spaces round-trips"
rm -rf "${T}"

print "3. XDG default + old-location fallback"
sandbox
zl 'zloom env X 1 >/dev/null 2>&1; echo "${ZLOOM_PLUGINS}"' | grep -q "${T}/xdg/zloom/plugins.zsh" \
    && ok "manifest defaults to XDG config dir" || no "manifest defaults to XDG config dir"
rm -rf "${T}"
sandbox
mkdir -p "${T}/data"
print -r -- 'env OLD=1' >! "${T}/data/plugins.zsh"
zl 'echo "${ZLOOM_PLUGINS}"' | grep -q "${T}/data/plugins.zsh" \
    && ok "pre-existing \$ZLOOM_DIR/plugins.zsh wins" || no "pre-existing \$ZLOOM_DIR/plugins.zsh wins"
rm -rf "${T}"

print "4. snippets inside the config dir are stored and resolved relative"
sandbox
mkdir -p "${T}/xdg/zloom/snippets"
print -r -- 'SNIP=1' >! "${T}/xdg/zloom/snippets/s.zsh"
( cd /tmp && zsh -c "
    export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home'
    source '${REPO}/zloom.zsh'
    zloom snippet snippets/s.zsh >/dev/null 2>&1
    grep '^snippet' \"\${ZLOOM_PLUGINS}\"
" ) >! "${T}/out"
check "manifest stores relative path" "snippet snippets/s.zsh" "$(cat "${T}/out")"
zl 'echo "snip=${SNIP:-?}"' | grep -q 'snip=1' && ok "relative entry resolves from any cwd" || no "relative entry resolves from any cwd"
rm -rf "${T}"

print "5. load order: conf.d -> config.zsh -> plugins -> functions -> themes"
sandbox
mkdir -p "${T}/xdg/zloom"/{conf.d,functions,themes} "${T}/plug"
print -r -- 'typeset -ga ORDER; ORDER+=conf' >! "${T}/xdg/zloom/conf.d/10-conf.zsh"
print -r -- 'ORDER+=config' >! "${T}/xdg/zloom/config.zsh"
print -r -- 'ORDER+=func' >! "${T}/xdg/zloom/functions/f.zsh"
print -r -- 'ORDER+=theme' >! "${T}/xdg/zloom/themes/t.zsh"
print -r -- 'ORDER+=plugin' >! "${T}/plug/p.plugin.zsh"
print -r -- "load ${T}/plug" >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1     # build init once (first shell only bootstraps)
zl '[[ "${ORDER[*]}" == "conf config plugin func theme" ]] && echo ORDER_OK' | grep -q ORDER_OK \
    && ok "documented load order holds" || no "documented load order holds" "conf config plugin func theme" "$(zl 'echo ${ORDER[*]:-?}' | tail -1)"
rm -rf "${T}"

print "6. drop-in directories need no rebuild"
sandbox
mkdir -p "${T}/xdg/zloom/functions"
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1     # build init once
print -r -- 'DROPIN=1' >! "${T}/xdg/zloom/functions/late.zsh"
zl 'echo "dropin=${DROPIN:-?}"' | grep -q 'dropin=1' && ok "file dropped after build just works" || no "file dropped after build just works"
rm "${T}/xdg/zloom/functions/late.zsh"
zl '(( $+functions[none] )) ; echo "gone=$(( $+DROPIN ))"' | grep -q 'gone=0' && ok "removed file stops loading" || no "removed file stops loading"
rm -rf "${T}"

print "7. completions stamp decides compinit mode"
sandbox
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
print -r -- 'compinit() { print -r -- compinit "$@" }' >! "${T}/stub"
zl 'true' >/dev/null 2>&1
rm -f "${T}/data/completions.stamp"    # observe first-run state
mode() { zsh -f -c "source '${T}/stub'; source '${T}/data/init.zsh'" 2>/dev/null; }
check "first run does a full compinit" "compinit" "$(mode)"
check "unchanged list takes the -C fast path" "compinit -C" "$(mode)"
mkdir -p "${T}/xdg/zloom/completions"
printf '#compdef zl-t\n_zl-t() { _message hi }\n' >! "${T}/xdg/zloom/completions/_zl-t"
check "new completion file triggers a rescan" "compinit" "$(mode)"
check "and settles back to -C" "compinit -C" "$(mode)"
ln -s /nonexistent/_x "${T}/xdg/zloom/completions/_x"
check "dangling symlinks are ignored" "compinit -C" "$(mode)"
rm -rf "${T}"

print "8. functions-only config bootstraps; empty config stays silent"
sandbox
n=$(zl 'true' 2>&1 | grep -c 'Building'); check "empty config does not bootstrap" "0" "${n}"
mkdir -p "${T}/xdg/zloom/functions"; print -r -- 'f() { :; }' >! "${T}/xdg/zloom/functions/f.zsh"
n=$(zl 'true' 2>&1 | grep -c 'Building'); check "functions alone bootstrap" "1" "${n}"
rm -rf "${T}"

print "9. @ref splitting rules"
sandbox
zl '
-zloom-split-ref zsh-users/zsh-autosuggestions;        print "a:${REPLY}|${REPLY_REF}"
-zloom-split-ref zsh-users/zsh-autosuggestions@v0.7.0; print "b:${REPLY}|${REPLY_REF}"
-zloom-split-ref https://github.com/u/r.git@v1;        print "c:${REPLY}|${REPLY_REF}"
-zloom-split-ref https://user@host/r;                  print "d:${REPLY}|${REPLY_REF}"
-zloom-split-ref git@github.com:u/r.git;               print "e:${REPLY}|${REPLY_REF}"
-zloom-split-ref /local/repo@v1;                       print "f:${REPLY}|${REPLY_REF}"
' >! "${T}/out"
check "plain spec untouched"        "zsh-users/zsh-autosuggestions|"  "$(sed -n 's/^a://p' "${T}/out")"
check "owner/repo@ref splits"       "zsh-users/zsh-autosuggestions|v0.7.0" "$(sed -n 's/^b://p' "${T}/out")"
check "https URL @ref splits"       "https://github.com/u/r.git|v1"  "$(sed -n 's/^c://p' "${T}/out")"
check "URL userinfo @ untouched"    "https://user@host/r|"            "$(sed -n 's/^d://p' "${T}/out")"
check "git@ ssh remote untouched"   "git@github.com:u/r.git|"         "$(sed -n 's/^e://p' "${T}/out")"
check "local path untouched"        "/local/repo@v1|"                 "$(sed -n 's/^f://p' "${T}/out")"
rm -rf "${T}"

print "10. @ref end-to-end: clone, manifest round-trip, clean"
sandbox
gitfix "${T}/bare"
print -r -- "load file://${T}/bare.git@v1" >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=ok' && ok "pinned clone loads" || no "pinned clone loads"
grep -q "^source .*bare.git-v1" "${T}/data/init.zsh" && ok "init sources the -v1 clone dir" || no "init sources the -v1 clone dir"
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'zloom clean --force >/dev/null 2>&1'
[[ -e "${T}/data/"*bare.git-v1* ]] 2>/dev/null && no "clean removes the @ref clone" || ok "clean removes the @ref clone"
rm -rf "${T}"

print "11. zloom sync: clone missing, rebuild, reconcile"
sandbox
gitfix "${T}/bare"
print -r -- "load file://${T}/bare.git@v1" >! "${T}/xdg/zloom/plugins.zsh"
zl 'zloom sync >/dev/null 2>&1; echo rc=$?' | grep -q 'rc=0' && ok "sync succeeds" || no "sync succeeds"
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=ok' && ok "sync installed and enabled the plugin" || no "sync installed and enabled the plugin"
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'zloom sync --clean >/dev/null 2>&1'
[[ -e "${T}/data/"*bare.git-v1* ]] 2>/dev/null && no "sync --clean removes the orphan clone" || ok "sync --clean removes the orphan clone"
rm -rf "${T}"

print "12. data directory defaults: XDG data home, legacy layout falls back"
sandbox
zsh -c "
    export XDG_CONFIG_HOME='${T}/xdg' XDG_DATA_HOME='${T}/xdgdata' ZDOTDIR='${T}' HOME='${T}/home'
    source '${REPO}/zloom.zsh'
    echo \"\${ZLOOM_DIR}\"
" >! "${T}/out"
check "fresh setup uses XDG data home" "${T}/xdgdata/zloom" "$(cat "${T}/out")"
mkdir -p "${T}/home/.zloom"; touch "${T}/home/.zloom/init.zsh"
zsh -c "
    export XDG_CONFIG_HOME='${T}/xdg' XDG_DATA_HOME='${T}/xdgdata' ZDOTDIR='${T}' HOME='${T}/home'
    source '${REPO}/zloom.zsh'
    echo \"\${ZLOOM_DIR}\"
" >! "${T}/out"
check "legacy ~/.zloom with init.zsh wins" "${T}/home/.zloom" "$(cat "${T}/out")"
rm -rf "${T}"

print
print "passed: ${passed}  failed: ${failed}"
(( failed == 0 )) || exit 1
exit 0
