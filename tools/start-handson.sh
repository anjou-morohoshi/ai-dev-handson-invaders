#!/usr/bin/env bash
# ハンズオン手順 3: herdr の画面を 3 つのペインにし、Claude Code を 3 つ起動して名前を付ける。
#   使い方: herdr の中のペイン（シェルの入力待ち）で  bash tools/start-handson.sh
#
#   ┌────────────┬────────────┐
#   │ controller │ agent-a    │   左   : このスクリプトを打ったペイン。最後にここで claude を起動する
#   │            ├────────────┤   右上 : agent-a
#   │            │ agent-b    │   右下 : agent-b
#   └────────────┴────────────┘
#
# - 今のタブのペインが 1 つなら、右・右下に分けて 3 つにする。3 つで上の形なら、分けずにそのまま使う。
# - ペイン ID はコマンドの結果（JSON）から読み取る。
# - 次のときは、何も変えずに理由を出して止まる:
#   ペインの数が 1・3 以外／3 つでも上の形でない／右のペインがシェルの入力待ちでない・別のフォルダーにいる／
#   controller・agent-a・agent-b のどれかの名前のエージェントがすでにいる
# - herdr 自体の起動は含まない（先に herdr を起動し、その中で打つ）。
set -euo pipefail

NAMES=(controller agent-a agent-b)
die() { echo "start-handson: $*" >&2; echo "start-handson: 何も変えずに止めました。" >&2; exit 1; }

[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || die "herdr の中で打ってください（先に herdr を起動する）。"
for c in herdr node claude; do command -v "${c}" >/dev/null || die "${c} が見つかりません。"; done

# clone したフォルダー（このスクリプトの 1 つ上）。3 つの Claude Code はここで起動する
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="${HERDR_PANE_ID}"

# 標準入力の JSON を読み、r（= .result）を使った JavaScript の式の値を出す（Node.js で読む）。
# 2 つ目からの引数は、式の中で a[0]・a[1]… として使える（シェルの値を式に直接埋め込まない）
#   例: herdr agent list | js 'r.agents.length'
#       herdr agent list | js 'r.agents.some((x) => x.name === a[0])' controller
js() {
  node -e '
    let s = ""; process.stdin.on("data", (c) => (s += c)).on("end", () => {
      const r = JSON.parse(s).result;
      const a = process.argv.slice(2);
      const v = eval(process.argv[1]);
      process.stdout.write(v === undefined || v === null ? "" : String(v));
    });' "$@"
}

# --- 1) 同じ名前のエージェントがいないか ---------------------------------------
dups="$(herdr agent list | js 'r.agents.map((x) => x.name).filter((n) => a.includes(n)).join(" ")' "${NAMES[@]}")" \
  || die "herdr agent list を読めませんでした。"
[ -z "${dups}" ] || die "同じ名前のエージェントがすでにいます: ${dups}（herdr agent list で確かめる）。"

# このペインで Claude Code などのエージェントが動いていないか（! で Claude Code の中から打った場合など）
self_agent="$(herdr pane get "${SELF}" | js 'r.pane.agent')" || die "このペイン（${SELF}）の情報を読めませんでした。"
[ -z "${self_agent}" ] || die "このペイン（${SELF}）では ${self_agent} が動いています。エージェントを終了し、シェルで打ってください。"

# --- 2) ペインの数と形を確かめ、右上・右下のペイン ID を決める ----------------------
layout="$(herdr pane layout --pane "${SELF}")" || die "ペインの配置（herdr pane layout）を読めませんでした。"
count="$(printf '%s' "${layout}" | js 'r.layout.panes.length')" || true
[ -n "${count}" ] || die "ペインの数を読み取れませんでした（herdr pane layout --current で確かめる）。"

# 右のペインがシェルの入力待ちで、clone したフォルダーにいるか（agent start が使える状態か）
check_shell_pane() {
  local id="$1" info shell fg cwd
  info="$(herdr pane process-info --pane "${id}")" || die "ペイン ${id} の情報を読めませんでした。"
  shell="$(printf '%s' "${info}" | js 'r.process_info.shell_pid')"
  fg="$(printf '%s' "${info}" | js 'r.process_info.foreground_process_group_id')"
  [ -n "${shell}" ] && [ "${shell}" = "${fg}" ] \
    || die "ペイン ${id} はシェルの入力待ちではありません（何かが動いています）。終了してから打ち直してください。"
  cwd="$(herdr pane get "${id}" | js 'r.pane.foreground_cwd || r.pane.cwd')" || die "ペイン ${id} の情報を読めませんでした。"
  [ "${cwd}" = "${ROOT}" ] \
    || die "ペイン ${id} のフォルダーが ${cwd} です。そのペインで cd ${ROOT} をしてから打ち直してください。"
}

case "${count}" in
  1)
    # 左右に分け（右上になる）、右を上下に分ける（右下になる）。入力はこのペインに残す
    RIGHT_TOP="$(herdr pane split --pane "${SELF}" --direction right --cwd "${ROOT}" --no-focus | js 'r.pane.pane_id')" || true
    [ -n "${RIGHT_TOP}" ] || die "ペインを左右に分けられませんでした。"
    RIGHT_BOTTOM="$(herdr pane split --pane "${RIGHT_TOP}" --direction down --cwd "${ROOT}" --no-focus | js 'r.pane.pane_id')" || true
    if [ -z "${RIGHT_BOTTOM}" ]; then
      # 分けた右のペインを閉じて、元の 1 つに戻してから止まる
      herdr pane close "${RIGHT_TOP}" >/dev/null 2>&1 \
        || echo "start-handson: 右のペイン（${RIGHT_TOP}）を閉じられませんでした。herdr pane close ${RIGHT_TOP} で閉じてください。" >&2
      die "右のペインを上下に分けられませんでした。"
    fi
    echo "ペインを 3 つに分けました: 左 ${SELF}・右上 ${RIGHT_TOP}・右下 ${RIGHT_BOTTOM}"
    ;;
  3)
    # 「左が全体の高さ・右に上下 2 つ」の形で、このペインが左かを座標から確かめる
    ids="$(printf '%s' "${layout}" | js '
      (() => {
        const L = r.layout, self = a[0];
        const me = L.panes.find((p) => p.pane_id === self);
        const others = L.panes.filter((p) => p.pane_id !== self);
        if (!me || me.rect.x !== L.area.x || me.rect.height !== L.area.height) return '';
        if (others.some((p) => p.rect.x <= me.rect.x || p.rect.x !== others[0].rect.x)) return '';
        others.sort((a, b) => a.rect.y - b.rect.y);
        if (others[0].rect.y === others[1].rect.y) return '';
        return others.map((p) => p.pane_id).join(" ");
      })()' "${SELF}")" || true
    [ -n "${ids}" ] || die "ペインが 3 つありますが、「左に 1 つ・右に上下 2 つ」でないか、このペインが左ではありません（herdr pane layout --current で確かめる）。"
    read -r RIGHT_TOP RIGHT_BOTTOM <<<"${ids}"
    check_shell_pane "${RIGHT_TOP}"
    check_shell_pane "${RIGHT_BOTTOM}"
    echo "今の 3 つのペインを使います: 左 ${SELF}・右上 ${RIGHT_TOP}・右下 ${RIGHT_BOTTOM}"
    ;;
  *)
    die "今のタブのペインが ${count} つです。1 つ（分けて使う）か 3 つ（そのまま使う）にしてから打ってください。"
    ;;
esac

# --- 3) 右上・右下で Claude Code を起動し、名前を付ける -------------------------
for pair in "agent-a ${RIGHT_TOP}" "agent-b ${RIGHT_BOTTOM}"; do
  read -r name pane <<<"${pair}"
  echo "${name}（${pane}）で Claude Code を起動しています（最大 30 秒ほど）…"
  if ! herdr agent start "${name}" --kind claude --pane "${pane}" >/dev/null; then
    echo "start-handson: ${name}（${pane}）を起動できませんでした。画面は herdr agent read ${pane} --lines 40 で見られます。" >&2
    echo "start-handson: 打ち直す前に、右のペインで起動した Claude Code を /exit で終了し、どちらもシェルの入力待ちにしてください" >&2
    echo "start-handson: （名前が残っていると「同じ名前のエージェントがすでにいます」で止まるため）。" >&2
    exit 1
  fi
done

# --- 4) このペインで Claude Code を起動し、controller と名付ける ------------------
# agent start は自分のペインには使えないため、claude を起動したあとに名前を付ける見張りを裏で動かす。
# 起動の直後は名前が外れることがあるので、付いた状態が 20 秒続くまで見て、外れたら付け直す（最大 2 分）。
(
  stable=0
  for _ in $(seq 1 60); do
    sleep 2
    now="$(herdr pane get "${SELF}" 2>/dev/null | js 'r.pane.agent' 2>/dev/null || true)"
    [ "${now}" = claude ] || { stable=0; continue; }
    cur="$(herdr agent list 2>/dev/null | js '(r.agents.find((x) => x.pane_id === a[0]) || {}).name' "${SELF}" 2>/dev/null || true)"
    if [ "${cur}" = controller ]; then
      stable=$((stable + 1)); [ "${stable}" -ge 10 ] && exit 0
    else
      stable=0; herdr agent rename "${SELF}" controller >/dev/null 2>&1 || true
    fi
  done
) </dev/null >/dev/null 2>&1 &
disown

echo "このペインで Claude Code（controller）を起動します。"
echo "起動したら、入力欄で  ! herdr agent list  を打ち、controller・agent-a・agent-b の 3 つが出ることを確かめてください。"
cd "${ROOT}"
exec claude
