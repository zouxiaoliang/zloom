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
zl() {  # run a script inside the current sandbox; WATCHED (file list) reaches it
    zsh -c "
        export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home'
        [[ -n '${WATCHED:-}' ]] && export ZLOOM_RESET_ON_CHANGE='${WATCHED}'
        source '${REPO}/zloom.zsh'
        ${1}
    " 2>&1
}
# Git fixture: a bare repository at $1.git, branch master, tag v1,
# shipping plug.plugin.zsh. The working clone at $1.work is KEPT so tests
# can commit a new revision and move the tag upstream.
gitfix() {
    git init -q -b master "${1}.work"
    printf 'PLUGIN_TAG=ok\n' > "${1}.work/plug.plugin.zsh"
    git -C "${1}.work" add -A
    git -C "${1}.work" -c user.email=t@t -c user.name=t commit -qm fixture
    git -C "${1}.work" tag v1
    git init -q --bare -b master "${1}.git"
    git -C "${1}.work" push -q "${1}.git" master v1
}
# Publish a new revision from the fixture's working clone: plug.plugin.zsh
# becomes $1 and the result is pushed to master ($2 = extra git push args).
gitpublish() {
    print -r -- "PLUGIN_TAG=$1" >! "${2}.work/plug.plugin.zsh"
    git -C "${2}.work" -c user.email=t@t -c user.name=t commit -qam "$1"
    git -C "${2}.work" push -q ${=~3} "${2}.git" master
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

print "13. lifecycle hooks fire after their command"
sandbox
mkdir -p "${T}/xdg/zloom/functions"
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
print -r -- '_zloom_post_sync() { print -r -- fired >! "${ZLOOM_HOOK_MARKER}" }' >! "${T}/xdg/zloom/functions/_zloom_post_sync.zsh"
zsh -c "
    export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home' ZLOOM_HOOK_MARKER='${T}/hook'
    source '${REPO}/zloom.zsh'
    zloom sync >/dev/null 2>&1
"
[[ -f "${T}/hook" ]] && ok "_zloom_post_sync ran" || no "_zloom_post_sync ran"
zsh -c "
    export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home' ZLOOM_HOOK_MARKER='${T}/hook2'
    source '${REPO}/zloom.zsh'
    zloom add '${T}/plug' >/dev/null 2>&1
" 2>/dev/null
[[ -f "${T}/hook2" ]] || ok "undefined hooks are skipped silently" || no "undefined hooks are skipped silently"
rm -rf "${T}"

print "14. zloom update pulls, skips tag pins, resets init"
sandbox
gitfix "${T}/bare"
print -r -- "load file://${T}/bare.git@master" >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1
[[ -f "${T}/data/init.zsh" ]] || { mkdir -p "${T}/xdg/zloom"; print 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"; zl 'true' >/dev/null 2>&1; print -r -- "load file://${T}/bare.git@master" >! "${T}/xdg/zloom/plugins.zsh"; zl 'true' >/dev/null 2>&1; }
zl 'zloom update >/dev/null 2>&1; echo rc=$?' | grep -q 'rc=0' && ok "update succeeds on a branch clone" || no "update succeeds on a branch clone"
[[ -f "${T}/data/init.zsh" ]] && no "update resets init.zsh" || ok "update resets init.zsh"
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=ok' && ok "shell after update rebuilds and loads" || no "shell after update rebuilds and loads"
rm -rf "${T}"

print "15. bootstrap shell loads drop-ins (first shell is complete)"
sandbox
mkdir -p "${T}/xdg/zloom"/{conf.d,functions,themes}
print -r -- 'CONF=1' >! "${T}/xdg/zloom/conf.d/c.zsh"
print -r -- 'fz() { :; }' >! "${T}/xdg/zloom/functions/f.zsh"
print -r -- 'TH=1' >! "${T}/xdg/zloom/themes/t.zsh"
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'echo "first shell: conf=${CONF:-?} fn=$(( $+functions[fz] )) theme=${TH:-?}"' \
    | grep -q 'first shell: conf=1 fn=1 theme=1' \
    && ok "conf.d/functions/themes live in the bootstrap shell" \
    || no "conf.d/functions/themes live in the bootstrap shell"
rm -rf "${T}"

print "16. deferred plugins load synchronously in non-interactive shells"
sandbox
mkdir -p "${T}/plug"
print -r -- 'DEFERRED=1' >! "${T}/plug/p.plugin.zsh"
printf "defer %s\n" "${T}/plug" >! "${T}/xdg/zloom/plugins.zsh"
zl 'echo "deferred=${DEFERRED:-?}"' | grep -q 'deferred=1' \
    && ok "defer entry loads in a zsh -c shell" || no "defer entry loads in a zsh -c shell"
rm -rf "${T}"

print "17. ZLOOM_RESET_ON_CHANGE triggers on content changes"
sandbox
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
print -r -- 'one' >! "${T}/watch"
WATCHED="${T}/watch"
zl 'true' >/dev/null 2>&1
unset WATCHED
grep -q 'ZLOOM_CHANGE_RECORD' "${T}/data/init.zsh" && ok "watch recorded into init.zsh" || no "watch recorded into init.zsh"
# Rewrite after the recorded mtime: content changed, must reset.
sleep 1.1; print -r -- 'two' >! "${T}/watch"
WATCHED="${T}/watch"; out="$(zl 'true' 2>&1)"
grep -q 'changed; resetting' <<< "${out}" && ok "content change announces the reset" || no "content change announces the reset" "" "${out}"
[[ -f "${T}/data/init.zsh" ]] && no "content change deletes init.zsh" || ok "content change deletes init.zsh"
zl 'echo "rebuilt=${X:-?}"' | grep -q 'rebuilt=1' && ok "next shell rebuilds" || no "next shell rebuilds"
# Touch only: mtime moves, cksum does not, init must be kept.
sleep 1.1; touch "${T}/watch"
WATCHED="${T}/watch"; out="$(zl 'true' 2>&1)"; unset WATCHED
grep -q 'changed; resetting' <<< "${out}" && no "touch without a content change keeps init.zsh" || ok "touch without a content change keeps init.zsh"
[[ -f "${T}/data/init.zsh" ]] && ok "init.zsh survives a pure touch" || no "init.zsh survives a pure touch"
rm -rf "${T}"

print "18. classic mode: oh-my-zsh + loadall + save"
sandbox
git init -q -b master "${T}/omz"
mkdir -p "${T}/omz/plugins/foo"
print -r -- 'OMZ_BASE=1' >! "${T}/omz/oh-my-zsh.sh"
print -r -- 'FOO_PLUG=1' >! "${T}/omz/plugins/foo/foo.plugin.zsh"
git -C "${T}/omz" add -A
git -C "${T}/omz" -c user.email=t@t -c user.name=t commit -qm omz
mkdir -p "${T}/plug2"
print -r -- 'L2=1' >! "${T}/plug2/p2.plugin.zsh"
cat >! "${T}/rc" <<RC
export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/empty-xdg' ZDOTDIR='${T}' HOME='${T}/home'
export ZLOOM_OH_MY_ZSH_REPO='${T}/omz'
source '${REPO}/zloom.zsh'
zloom oh-my-zsh
zloom oh-my-zsh plugins/foo
zloom load '${T}/plug2'
print -r -- '${T}/plug2' | zloom loadall
echo "classic: omz=\${OMZ_BASE:-?} foo=\${FOO_PLUG:-?} l2=\${L2:-?}"
zloom save >/dev/null 2>&1
echo "saved: \$([[ -f \${ZLOOM_INIT} ]] && echo yes || echo no)"
grep -c 'oh-my-zsh.sh\|plugins/foo/foo.plugin.zsh\|plug2/p2.plugin.zsh' "\${ZLOOM_INIT}" | sed 's/^/init sources: /'
zsh -f -c "export ZLOOM_DIR='${T}/data'; source '\${ZLOOM_INIT}' >/dev/null 2>&1; echo \"from init: omz=\${OMZ_BASE:-?} foo=\${FOO_PLUG:-?} l2=\${L2:-?}\""
RC
zsh "${T}/rc" >! "${T}/out" 2>"${T}/err"
grep -q 'classic: omz=1 foo=1 l2=1' "${T}/out" && ok "oh-my-zsh, its plugins and loadall load live" || no "oh-my-zsh, its plugins and loadall load live" "" "$(grep -v '^-- zloom' "${T}/out" "${T}/err")"
grep -q 'saved: yes' "${T}/out" && ok "zloom save writes init.zsh" || no "zloom save writes init.zsh"
grep -q 'init sources: 3' "${T}/out" && ok "init.zsh sources all three files" || no "init.zsh sources all three files" "3" "$(grep 'init sources' "${T}/out")"
grep -q 'from init: omz=1 foo=1 l2=1' "${T}/out" && ok "sourcing init.zsh reproduces the classic setup" || no "sourcing init.zsh reproduces the classic setup" "" "$(grep 'from init' "${T}/out")"
rm -rf "${T}"

print "19. pinned tags: moved tag detected and followed, annotated tags not misreported"
sandbox
gitfix "${T}/bare"
print -r -- "load file://${T}/bare.git@v1" >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1
out="$(zl 'zloom list --outdated')"
grep -q '^ok ' <<< "${out}" && ok "lightweight tag in sync reads ok" || no "lightweight tag in sync reads ok" "" "${out}"
# Move the tag upstream, then verify both detection and the follow.
gitpublish v2 "${T}/bare"
git -C "${T}/bare.work" tag -f v1 >/dev/null
git -C "${T}/bare.work" push -qf "${T}/bare.git" v1
out="$(zl 'zloom list --outdated')"
grep -q '^outdated' <<< "${out}" && ok "moved tag reported as outdated" || no "moved tag reported as outdated" "" "${out}"
zl 'zloom sync --update >/dev/null 2>&1; echo rc=$?' | grep -q 'rc=0' && ok "sync --update succeeds" || no "sync --update succeeds"
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=v2' && ok "moved tag followed after sync --update" || no "moved tag followed after sync --update" "v2" "$(zl 'echo ${PLUGIN_TAG:-?}')"
out="$(zl 'zloom list --outdated')"
grep -q '^ok ' <<< "${out}" && ok "up to date afterwards" || no "up to date afterwards" "" "${out}"
# Annotated tag: refs/tags/<t> is a tag object, the peeled ref is the commit.
git -C "${T}/bare.work" -c user.email=t@t -c user.name=t tag -af v1 -m annotated >/dev/null
git -C "${T}/bare.work" push -qf "${T}/bare.git" v1
out="$(zl 'zloom list --outdated')"
grep -q '^ok ' <<< "${out}" && ok "annotated tag in sync reads ok (peeled ref)" || no "annotated tag in sync reads ok (peeled ref)" "" "${out}"
rm -rf "${T}"

print "20. clean removes stale snippet caches"
sandbox
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1
mkdir -p "${T}/data/snippets"
# Cached remote snippets carry URL-encoded names; clean matches them by
# their recorded .url sidecar, not by file name.
kept="${T}/data/snippets/http-COLON--SLASH--SLASH-example.com-SLASH-kept.zsh"
stale="${T}/data/snippets/http-COLON--SLASH--SLASH-example.com-SLASH-s.zsh"
print -r -- 'x' >! "${stale}"
print -r -- 'http://example.com/s.zsh' >! "${stale}.url"
print -r -- 'stub' >! "${stale}.zwc"
print -r -- 'body' >! "${kept}"
print -r -- 'http://example.com/kept.zsh' >! "${kept}.url"
print -l -- 'env X=1' 'snippet http://example.com/kept.zsh' >! "${T}/xdg/zloom/plugins.zsh"
out="$(zl 'zloom clean' 2>&1)"
grep -q 'example.com-SLASH-s.zsh' <<< "${out}" && ok "dry run lists the stale cache" || no "dry run lists the stale cache" "" "${out}"
grep -q 'example.com-SLASH-kept.zsh' <<< "${out}" && no "dry run keeps a listed snippet" || ok "dry run keeps a listed snippet"
[[ -f "${stale}" ]] && ok "dry run deletes nothing" || no "dry run deletes nothing"
zl 'zloom clean --force' >/dev/null 2>&1
[[ -e "${stale}" || -e "${stale}.url" || -e "${stale}.zwc" ]] \
    && no "--force removes the stale cache and its sidecars" || ok "--force removes the stale cache and its sidecars"
[[ -f "${kept}" ]] && ok "listed snippet cache survives" || no "listed snippet cache survives"
rm -rf "${T}"

print "21. doctor"
sandbox
print -r -- 'env X=1' >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1
out="$(zl 'zloom doctor' 2>&1)"; rc="$(zl 'zloom doctor >/dev/null 2>&1; echo rc=$?')"
grep -q 'all checks passed' <<< "${out}" && ok "healthy setup reports success" || no "healthy setup reports success" "" "${out}"
grep -q 'rc=0' <<< "${rc}" && ok "healthy setup exits 0" || no "healthy setup exits 0" "" "${rc}"
grep -q 'interactive shell starts in' <<< "${out}" && ok "reports a shell start time" || no "reports a shell start time" "" "${out}"
grep -q 'init.zsh sections, heaviest first' <<< "${out}" && ok "reports per-section init.zsh timing" || no "reports per-section init.zsh timing" "" "${out}"
grep -q 'General modules' <<< "${out}" && ok "section timing names the plugin section" || no "section timing names the plugin section" "" "${out}"
[[ -e "${T}/data/.zloom-doctor-probe.zsh" ]] && no "timing probe cleans up its temp file" || ok "timing probe cleans up its temp file"
grep -qE 'EPOCHREALTIME|__zloom_dt|__zloom_sec' "${T}/data/init.zsh" && no "real init.zsh carries no timing code" || ok "real init.zsh carries no timing code"
# Stale init + missing clone -> warnings and exit 1.
printf 'load file://%s/bare.git@v1\n' "${T}" >! "${T}/xdg/zloom/plugins.zsh"
out="$(zl 'zloom doctor' 2>&1)"; rc="$(zl 'zloom doctor >/dev/null 2>&1; echo rc=$?')"
grep -q 'manifest is newer than init.zsh' <<< "${out}" && ok "warns about a stale init.zsh" || no "warns about a stale init.zsh" "" "${out}"
grep -q 'clone(s) missing' <<< "${out}" && ok "warns about missing clones" || no "warns about missing clones" "" "${out}"
grep -q 'rc=1' <<< "${rc}" && ok "warnings make doctor exit 1" || no "warnings make doctor exit 1" "" "${rc}"
rm -rf "${T}"

print "22. doctor reports manifest lines the loader would ignore"
sandbox
cat >! "${T}/xdg/zloom/plugins.zsh" <<'MAN'
# a comment and a blank line are fine

env OK=1
load zsh-users/zsh-completions src
snippet https://example.com/a.zsh
env
bogus line here
alias
env X=1 snippet http://example.com/kept.zsh
snippet https://a.zsh https://b.zsh
env SPACED='two words'
alias ll 'ls -la'
func hello 'echo hi'
eval /opt/homebrew/bin/brew shellenv
MAN
zl 'true' >/dev/null 2>&1
out="$(zl 'zloom doctor' 2>&1)"
for n in 6 7 8 9 10; do
    grep -qE "^ +${n}: " <<< "${out}" && ok "flags manifest line ${n}" || no "flags manifest line ${n}" "" "$(grep -A8 'ignored by zloom' <<< "${out}")"
done
for n in 4 5 11 12 13 14 15; do
    grep -qE "^ +${n}: " <<< "${out}" && no "does not flag valid manifest line ${n}" || ok "does not flag valid manifest line ${n}"
done
grep -q '5 manifest line(s) ignored' <<< "${out}" && ok "counts the ignored lines" || no "counts the ignored lines" "" "${out}"
zl 'zloom doctor >/dev/null 2>&1; echo rc=$?' | grep -q 'rc=1' && ok "ignored lines make doctor exit 1" || no "ignored lines make doctor exit 1"
# A clean manifest must not trip the lint.
print -r -- 'env OK=1' >! "${T}/xdg/zloom/plugins.zsh"
out="$(zl 'zloom doctor' 2>&1)"
grep -q 'ignored by zloom' <<< "${out}" && no "a clean manifest raises no lint warning" || ok "a clean manifest raises no lint warning"
rm -rf "${T}"

print "23. version and selfupdate rollback"
sandbox
out="$(zl 'zloom version')"
grep -q '^version ' <<< "${out}" && ok "version prints a git revision" || no "version prints a git revision" "" "${out}"
zl 'zloom selfupdate --rollback >/dev/null 2>&1; echo rc=$?' | grep -q 'rc=1' \
    && ok "rollback without a recorded version fails safely" || no "rollback without a recorded version fails safely"
# Drive selfupdate against a throwaway clone of the program with an
# upstream it can pull from, then roll the update back.
git init -q -b master "${T}/prog-upstream"
print -r -- 'zloom-updated() { :; }' >! "${T}/prog-upstream/new.zsh"
cp "${REPO}/zloom.zsh" "${REPO}/_zloom" "${T}/prog-upstream/"
git -C "${T}/prog-upstream" add -A
git -C "${T}/prog-upstream" -c user.email=t@t -c user.name=t commit -qm base
BASE_REV="$(git -C "${T}/prog-upstream" rev-parse HEAD)"
git clone -q "${T}/prog-upstream" "${T}/prog"
print -r -- 'zloom-rolled-back() { :; }' >! "${T}/prog-upstream/new.zsh"
git -C "${T}/prog-upstream" -c user.email=t@t -c user.name=t commit -qam next
NEXT_REV="$(git -C "${T}/prog-upstream" rev-parse HEAD)"
cat >! "${T}/rc" <<RC
export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home'
source '${T}/prog/zloom.zsh'
zloom selfupdate >/dev/null 2>&1
echo "after update: \$(git -C '${T}/prog' rev-parse HEAD)"
zloom selfupdate --rollback >/dev/null 2>&1
echo "after rollback: \$(git -C '${T}/prog' rev-parse HEAD)"
zloom selfupdate --rollback >/dev/null 2>&1; echo "second rollback rc=\$?"
RC
zsh "${T}/rc" >! "${T}/out" 2>/dev/null
grep -q "after update: ${NEXT_REV}" "${T}/out" && ok "selfupdate pulls the new revision" || no "selfupdate pulls the new revision" "${NEXT_REV}" "$(cat "${T}/out")"
grep -q "after rollback: ${BASE_REV}" "${T}/out" && ok "--rollback restores the previous revision" || no "--rollback restores the previous revision" "${BASE_REV}" "$(cat "${T}/out")"
grep -q 'second rollback rc=1' "${T}/out" && ok "rollback record is consumed (no double rollback)" || no "rollback record is consumed (no double rollback)" "" "$(cat "${T}/out")"
rm -rf "${T}"

print "24. @HEAD pin: clones, follows the default branch, reads in sync"
sandbox
gitfix "${T}/bare"
print -r -- "load file://${T}/bare.git@HEAD" >! "${T}/xdg/zloom/plugins.zsh"
zl 'true' >/dev/null 2>&1
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=ok' && ok "@HEAD clone loads the default branch" || no "@HEAD clone loads the default branch"
# Clone dirs are <encoded location>/<repo>-<ref>, two levels deep.
head_dir=("${T}/data/"*/*bare.git-HEAD(N))
(( ${#head_dir} == 1 )) && ok "clone dir named after HEAD (${head_dir[1]:t})" || no "clone dir named after HEAD" "1 dir" "${#head_dir} dirs: ${head_dir[*]:t}"
git -C "${head_dir[1]}" symbolic-ref -q HEAD >/dev/null 2>&1 && no "@HEAD clone is detached" || ok "@HEAD clone is detached"
out="$(zl 'zloom list --outdated')"; grep -q '^ok ' <<< "${out}" && ok "@HEAD in sync reads ok" || no "@HEAD in sync reads ok" "" "${out}"
gitpublish v2 "${T}/bare"
out="$(zl 'zloom list --outdated')"; grep -q '^outdated' <<< "${out}" && ok "@HEAD reports a new default-branch tip" || no "@HEAD reports a new default-branch tip" "" "${out}"
zl 'zloom sync --update >/dev/null 2>&1'
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=v2' && ok "@HEAD follows the new tip" || no "@HEAD follows the new tip" "v2" "$(zl 'echo ${PLUGIN_TAG:-?}')"
out="$(zl 'zloom list --outdated')"; grep -q '^ok ' <<< "${out}" && ok "@HEAD back in sync" || no "@HEAD back in sync" "" "${out}"
# The reason @HEAD exists: following a RENAME of the remote's default
# branch. A plain `git pull' would keep tracking the old name.
gitpublish renamed "${T}/bare"
git -C "${T}/bare.work" branch -m master main
git -C "${T}/bare.work" push -q "${T}/bare.git" main
git -C "${T}/bare.git" symbolic-ref HEAD refs/heads/main
git -C "${T}/bare.git" branch -D master >/dev/null 2>&1
out="$(zl 'zloom sync --update 2>&1; echo rc=$?')"
grep -q 'rc=0' <<< "${out}" && ok "sync --update succeeds across a default-branch rename" || no "sync --update succeeds across a default-branch rename" "" "${out}"
zl 'echo "tag=${PLUGIN_TAG:-?}"' | grep -q 'tag=renamed' && ok "@HEAD follows the renamed default branch" || no "@HEAD follows the renamed default branch" "renamed" "$(zl 'echo ${PLUGIN_TAG:-?}')"
out="$(zl 'zloom list --outdated')"; grep -q '^ok ' <<< "${out}" && ok "@HEAD in sync after the rename" || no "@HEAD in sync after the rename" "" "${out}"
# A dead remote must surface as a failure, not as a silent no-op.
git -C "${head_dir[1]}" remote set-url origin "${T}/nonexistent.git"
zl '-zloom-pull-all >/dev/null 2>&1; echo rc=$?' | grep -qv 'rc=0' && ok "an unreachable remote fails the update" || no "an unreachable remote fails the update"
rm -rf "${T}"

print "25. eval entries: multi-word keys stay consistent across eval/del"
sandbox
mkdir -p "${T}/bin"
cat >! "${T}/bin/fake" <<'SH'
#!/bin/sh
echo "export ZLOOM_EVAL_MARK=$1"
SH
chmod +x "${T}/bin/fake"
print -r -- "eval ${T}/bin/fake one" >! "${T}/xdg/zloom/plugins.zsh"
print -r -- "eval ${T}/bin/fake two" >> "${T}/xdg/zloom/plugins.zsh"
# Re-running a multi-word eval must replace, not append.
zl "zloom eval '${T}/bin/fake one'" >/dev/null 2>&1
n="$(grep -c 'bin/fake one' "${T}/xdg/zloom/plugins.zsh")"
check "re-running a multi-word eval updates in place" "1" "${n}"
# del matches the whole command: removing 'fake one' must keep 'fake two'.
zl "zloom del '${T}/bin/fake one'" >/dev/null 2>&1
grep -q 'bin/fake one' "${T}/xdg/zloom/plugins.zsh" && no "del removes the right eval entry" || ok "del removes the right eval entry"
grep -q 'bin/fake two' "${T}/xdg/zloom/plugins.zsh" && ok "del keeps the eval entry sharing its first word" || no "del keeps the eval entry sharing its first word"
grep -q 'bin/fake one' "${T}/data/init.zsh" && no "init.zsh no longer runs the removed eval" || ok "init.zsh no longer runs the removed eval"
rm -rf "${T}"

print "26. prezto module loading"
sandbox
git init -q -b master "${T}/prezto"
mkdir -p "${T}/prezto/modules/first" "${T}/prezto/runcoms"
# A faithful stand-in for prezto's init.zsh: it defines pmodload, which
# sources <module>/init.zsh for each argument. (A stub without pmodload
# is exactly the case the loader must refuse rather than fake success.)
cat >! "${T}/prezto/init.zsh" <<'PZ'
PREZTO_INIT=1
pmodload() {
    local m
    for m in "$@"; do
        [[ -f "${PREZTO_HOME}/modules/${m}/init.zsh" ]] || { print -u2 "pmodload: no such module ${m}"; return 1; }
        source "${PREZTO_HOME}/modules/${m}/init.zsh"
    done
}
PZ
print -r -- 'FIRST_MODULE=1' >! "${T}/prezto/modules/first/init.zsh"
print -r -- 'stub' >! "${T}/prezto/runcoms/zshrc"
git -C "${T}/prezto" add -A
git -C "${T}/prezto" -c user.email=t@t -c user.name=t commit -qm prezto
cat >! "${T}/rc" <<RC
export ZLOOM_DIR='${T}/data' XDG_CONFIG_HOME='${T}/xdg' ZDOTDIR='${T}' HOME='${T}/home'
PREZTO_HOME='${T}/prezto'
source '${REPO}/zloom.zsh'
ZLOOM_PREZTO_REPO='${T}/prezto' ZLOOM_PREZTO_LOAD_DEFAULT=0 zloom prezto >/dev/null 2>&1
echo "base: rc=\$? init=\${PREZTO_INIT:-?} use=\${ZLOOM_USE_PREZTO}"
zloom prezto first; zloom prezto first; zloom prezto first
echo "module x3: rc=\$? first=\${FIRST_MODULE:-?} recorded=[\${ZLOOM_PREZTO_LOAD[*]}] n=\${#ZLOOM_PREZTO_LOAD}"
zloom prezto nosuchmodule >/dev/null 2>&1; echo "missing module: rc=\$?"
zloom save >/dev/null 2>&1
grep '^pmodload' "\${ZLOOM_INIT}" | sed 's/^/init line: /'
RC
zsh "${T}/rc" >! "${T}/out" 2>"${T}/err"
grep -q 'base: rc=0 init=1 use=1' "${T}/out" && ok "zloom prezto loads the prezto base" || no "zloom prezto loads the prezto base" "" "$(grep -v '^-- zloom' "${T}/out" "${T}/err")"
grep -q 'module x3: rc=0 first=1' "${T}/out" && ok "zloom prezto <module> loads a module" || no "zloom prezto <module> loads a module" "" "$(grep -v '^-- zloom' "${T}/out" "${T}/err")"
grep -q 'n=1' "${T}/out" && ok "a module requested repeatedly is recorded once" || no "a module requested repeatedly is recorded once" "1 entry" "$(grep 'module x3' "${T}/out")"
grep -q 'missing module: rc=1' "${T}/out" && ok "a failing module load is reported" || no "a failing module load is reported" "" "$(grep 'missing module' "${T}/out")"
grep -q "init line: pmodload 'first'\$" "${T}/out" && ok "init.zsh records the module exactly once" || no "init.zsh records the module exactly once" "" "$(grep 'init line' "${T}/out")"
# Asking for a module before the base must fail instead of pretending to load.
cat >! "${T}/rc2" <<RC
export ZLOOM_DIR='${T}/data2' XDG_CONFIG_HOME='${T}/xdg2' ZDOTDIR='${T}' HOME='${T}/home'
source '${REPO}/zloom.zsh'
ZLOOM_PREZTO_REPO='${T}/prezto' zloom prezto first >/dev/null 2>&1; echo "before base: rc=\$?"
RC
out="$(zsh "${T}/rc2" 2>/dev/null)"
grep -q 'before base: rc=1' <<< "${out}" && ok "a module ahead of the base fails loudly" || no "a module ahead of the base fails loudly" "" "${out}"
rm -rf "${T}"

print "27. completion: parses, registers with compsys, lists keys like del"
sandbox
zsh -n "${REPO}/_zloom" && ok "_zloom parses" || no "_zloom parses"
zsh -c "fpath=('${REPO}' \$fpath); autoload -Uz compinit; compinit -u -d '${T}/dump' >/dev/null 2>&1; print -r -- \${_comps[zloom]:-UNSET}" \
    | grep -qx '_zloom' && ok "compsys registers zloom -> _zloom" || no "compsys registers zloom -> _zloom"
cat >! "${T}/xdg/zloom/plugins.zsh" <<'MAN'
# comment line
load zsh-users/zsh-completions src
defer zsh-users/zsh-autosuggestions@v0.7.0   # trailing comment
snippet https://example.com/s.zsh
env EDITOR=vim
alias ll 'ls -la'
func hello 'echo hi'
eval /opt/homebrew/bin/brew shellenv
bogus line here
MAN
sed '$d' "${REPO}/_zloom" > "${T}/comp.zsh"       # drop the trailing dispatch call
out="$(zsh -c "source '${T}/comp.zsh'; ZLOOM_PLUGINS='${T}/xdg/zloom/plugins.zsh'; _zloom_manifest_entries")"
check "completion lists every del-able key" "zsh-users/zsh-completions
zsh-users/zsh-autosuggestions@v0.7.0
https://example.com/s.zsh
EDITOR
ll
hello
/opt/homebrew/bin/brew shellenv" "${out}"
out="$(zsh -c "source '${T}/comp.zsh'; ZLOOM_PLUGINS='${T}/nope/plugins.zsh' HOME='${T}/home'; _zloom_manifest_entries")"
check "missing manifest completes nothing" "" "${out}"
rm -rf "${T}"

print "28. steady state: generation is deterministic and free of command-side code"
sandbox
mkdir -p "${T}/xdg/zloom"/{conf.d,functions,themes,completions} "${T}/plug"
print -r -- 'C=1' >! "${T}/xdg/zloom/conf.d/c.zsh"
print -r -- 'f() { :; }' >! "${T}/xdg/zloom/functions/f.zsh"
print -r -- 'TH=1' >! "${T}/xdg/zloom/themes/t.zsh"
cat >! "${T}/xdg/zloom/plugins.zsh" <<MAN
env LC_ALL=en_US.UTF-8
eval /opt/homebrew/bin/brew shellenv
load ${T}/plug
defer ${T}/plug
alias list_proxy 'echo "http_proxy=\${http_proxy:=}";'
func hello 'echo hi'
MAN
zl 'true' >/dev/null 2>&1
cp "${T}/data/init.zsh" "${T}/first"
rm -f "${T}/data/init.zsh" "${T}/data/init.zsh.zwc"
zl 'true' >/dev/null 2>&1
cmp -s "${T}/first" "${T}/data/init.zsh" && ok "regenerating the same manifest is byte-identical" || no "regenerating the same manifest is byte-identical"
grep -qE 'EPOCHREALTIME|zmodload|doctor|outdated|-zloom-hook|zloom (sync|update)' "${T}/data/init.zsh" \
    && no "init.zsh contains no command-side code" || ok "init.zsh contains no command-side code"
zsh -n "${T}/data/init.zsh" 2>/dev/null && ok "generated init.zsh parses standalone" || no "generated init.zsh parses standalone"
rm -rf "${T}"

print
print "passed: ${passed}  failed: ${failed}"
(( failed == 0 )) || exit 1
exit 0
