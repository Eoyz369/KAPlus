#!/usr/bin/env bash
# =============================================================================
#  ka  ·  Komari Agent 部署器
#  版本: 0.0.59        归档文件: ka-v<版本>.sh
#  版本规则: 每次修改 +0.0.1（0.0.1 → 0.0.2 → 0.0.3），旧文件全部保留
#
#  用法:
#    ka                     主菜单（↑↓ 选择，回车确认）
#    ka install             直接进安装向导
#    ka status              实例状态
#    ka logs <n|name|all>   查看日志
#    ka uninstall           卸载实例
#    ka version             版本与归档信息
#    ka bump                发布新版本（+0.1，旧版本文件保留）
#    ka self-install        安装到 /opt/ka 并建立 ka 命令
#
#  安装流程: 面板地址 → 粘贴 token（一行一个，空行结束）→ 参数 → 确认
#            节点数量 = token 数量，不再单独问“几个实例”
#  已有实例: 同时识别 systemd 与 OpenRC(Alpine) 服务，外加正在跑的进程兜底
#  界面: 256/16 色自适应；非交互终端退回编号菜单（KA_TUI=0 强制）
# =============================================================================

set -u

KA_VERSION="0.0.59"
KA_BUMP_STYLE="patch"
KA_INSTALLER="https://raw.githubusercontent.com/komari-monitor/komari-agent/refs/heads/main/install.sh"
KA_UPDATE_BASE="${KA_UPDATE_BASE:-https://raw.githubusercontent.com/Eoyz369/KAPlus/main}"
KA_CONF="${KA_CONF:-/etc/ka.conf}"

KA_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
KA_DIR="$(dirname "$KA_SELF")"

# ================================================================ 主题引擎 ===
COLOR_DEPTH=0
UTF8=0
B=""; DIM=""; RESET=""
PINK=""; PURP=""; BLUE=""; CYAN=""; GREEN=""; YELL=""; RED=""; GRAY=""; WHITE=""
G_OK="OK"; G_ERR="x"; G_WARN="!"; G_INFO="*"
G_DOT="o"; G_DOT_OFF="."; G_DOT_CUR="O"; G_BAR="|"; G_ARROW=">"; G_RULE="-"; G_FULL="#"; G_EMPTY="-"

detect_color() {
  COLOR_DEPTH=0
  [ "${KA_UI:-auto}" = "plain" ] && return 0
  [ -n "${NO_COLOR:-}" ] && return 0
  [ -t 1 ] || return 0
  local term="${TERM:-dumb}"
  case "$term" in dumb|'') return 0 ;; esac
  local n=8
  if command -v tput >/dev/null 2>&1; then
    n="$(tput colors 2>/dev/null || printf '8')"
  fi
  case "$n" in ''|*[!0-9]*) n=8 ;; esac
  if [ "$n" -ge 256 ]; then
    COLOR_DEPTH=256
  elif [ "${term#*256color}" != "$term" ]; then
    COLOR_DEPTH=256
  else
    COLOR_DEPTH=16
  fi
}

ui_init() {
  detect_color
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF8=1 ;;
    *) UTF8=0 ;;
  esac

  if [ "$COLOR_DEPTH" -eq 0 ]; then
    B=""; DIM=""; RESET=""
    PINK=""; PURP=""; BLUE=""; CYAN=""; GREEN=""; YELL=""; RED=""; GRAY=""; WHITE=""
    G_OK="[OK]"; G_ERR="[!!]"; G_WARN="[!]"; G_INFO="->"
    G_DOT="o"; G_DOT_OFF="."; G_DOT_CUR="O"; G_BAR="|"; G_ARROW=">"; G_RULE="-"; G_FULL="#"; G_EMPTY="-"
    return 0
  fi

  B=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  if [ "$COLOR_DEPTH" -ge 256 ]; then
    PINK=$'\033[38;5;212m'
    PURP=$'\033[38;5;141m'
    BLUE=$'\033[38;5;111m'
    CYAN=$'\033[38;5;117m'
    GREEN=$'\033[38;5;120m'
    YELL=$'\033[38;5;221m'
    RED=$'\033[38;5;210m'
    GRAY=$'\033[38;5;244m'
    WHITE=$'\033[38;5;255m'
  else
    PINK=$'\033[95m'; PURP=$'\033[35m'; BLUE=$'\033[94m'; CYAN=$'\033[96m'
    GREEN=$'\033[92m'; YELL=$'\033[93m'; RED=$'\033[91m'; GRAY=$'\033[90m'
    WHITE=$'\033[97m'
  fi

  if [ "$UTF8" -eq 1 ]; then
    G_OK="✔"; G_ERR="✘"; G_WARN="▲"; G_INFO="◆"
    G_DOT="●"; G_DOT_OFF="○"; G_DOT_CUR="◉"
    G_BAR="┃"; G_ARROW="▸"; G_RULE="─"; G_FULL="█"; G_EMPTY="░"
  fi
}
ui_init

# ================================================================ 文本工具 ===
say()  { printf '%s\n' "$*"; }
blank(){ printf '\n'; }

info() { printf '  %s%s%s %s\n' "$CYAN" "$G_INFO" "$RESET" "$*"; }
ok()   { printf '  %s%s%s %s\n' "$GREEN" "$G_OK" "$RESET" "$*"; }
warn() { printf '  %s%s%s %s\n' "$YELL" "$G_WARN" "$RESET" "$*"; }
err()  { printf '  %s%s%s %s\n' "$RED" "$G_ERR" "$RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
dim()  { printf '  %s%s%s\n' "$GRAY" "$*" "$RESET"; }

repeat() {
  local ch="$1" n="$2" i out=""
  for ((i = 0; i < n; i++)); do out+="$ch"; done
  printf '%s' "$out"
}

rainbow() {
  local s="$1" i out=""
  if [ "$COLOR_DEPTH" -eq 0 ]; then printf '%s' "$s"; return 0; fi
  local -a pal=("$PINK" "$PURP" "$BLUE" "$CYAN" "$GREEN" "$YELL")
  for ((i = 0; i < ${#s}; i++)); do
    out+="${pal[$((i % 6))]}${s:i:1}"
  done
  printf '%s%s' "$out" "$RESET"
}

rule() {
  local w="${1:-58}"
  local seg=$(((w + 3) / 4))
  local -a cols=("$PINK" "$PURP" "$BLUE" "$CYAN")
  local j i s
  if [ "$COLOR_DEPTH" -eq 0 ]; then
    printf '  %s\n' "$(repeat "$G_RULE" "$w")"
    return 0
  fi
  printf '  '
  for ((j = 0; j < 4; j++)); do
    s=""
    for ((i = 0; i < seg && j * seg + i < w; i++)); do s+="$G_RULE"; done
    printf '%s%s' "${cols[$j]}" "$s"
  done
  printf '%s\n' "$RESET"
}

banner() {
  printf '\n'
  printf '  %s\n' "$(rainbow 'K O M A R I   A G E N T')"
  printf '  %s%s%s\n' "$GRAY" "$(repeat "$G_RULE" 40)" "$RESET"
  printf '  %ska%s %s%sv%s  %s· 多实例部署 · NAT 友好%s\n' \
    "$B" "$RESET" "$GRAY" "$WHITE" "$KA_VERSION" "$GRAY" "$RESET"
  printf '\n'
}

step_header() {
  local cur="$1" total="$2" title="$3" dots="" i
  for ((i = 1; i <= total; i++)); do
    if [ "$i" -lt "$cur" ]; then
      dots+="${GREEN}${G_DOT}${RESET} "
    elif [ "$i" -eq "$cur" ]; then
      dots+="${YELL}${G_DOT_CUR}${RESET} "
    else
      dots+="${GRAY}${G_DOT_OFF}${RESET} "
    fi
  done
  printf '\n  %s %s%s/%s%s\n' "$dots" "$GRAY" "$cur" "$total" "$RESET"
  printf '  %s%s%s %s%s%s\n\n' "$PINK" "$G_BAR" "$RESET" "$B" "$title" "$RESET"
}

panel_row() {
  printf '  %s%s%s %s%s:%s %s%s%s\n' \
    "$PURP" "$G_BAR" "$RESET" "$GRAY" "$1" "$RESET" "$WHITE" "$2" "$RESET"
}

toggle_render() {
  if [ "${1:-0}" -eq 1 ]; then
    printf '%s[✔]%s 已开启' "$GREEN" "$RESET"
  else
    printf '%s[ ]%s 已关闭' "$GRAY" "$RESET"
  fi
}

progress() {
  local cur="$1" total="$2" width=24 filled i bar=""
  filled=$((cur * width / total))
  for ((i = 0; i < width; i++)); do
    if [ "$i" -lt "$filled" ]; then
      bar+="${GREEN}█${RESET}"
    else
      bar+="${GRAY}░${RESET}"
    fi
  done
  printf '\n  %s  %s%s / %s%s\n\n' "$bar" "$GRAY" "$cur" "$total" "$RESET"
}

# ================================================================ 交互引擎 ===
UI_TUI=0
PICK_RESULT=0
PICK_START=0
PICK_HINT=""
KEY=""

tui_init() {
  UI_TUI=0
  [ "${KA_TUI:-1}" = "0" ] && return 0
  [ -t 0 ] || return 0
  [ -t 1 ] || return 0
  [ "$COLOR_DEPTH" -gt 0 ] || return 0
  case "${TERM:-dumb}" in dumb) return 0 ;; esac
  UI_TUI=1
}

tui_restore() {
  if [ "${UI_TUI:-0}" -eq 1 ]; then printf '%s' $'\033[?25h'; fi
  if [ -n "${KA_TMP:-}" ] && [ -f "$KA_TMP" ]; then rm -f "$KA_TMP"; fi
}
trap 'tui_restore' EXIT
trap 'tui_restore; exit 130' INT TERM

screen_home() { printf '\033[H\033[J'; }
hide_cursor() { if [ "$UI_TUI" -eq 1 ]; then printf '%s' $'\033[?25l'; fi; return 0; }
show_cursor() { if [ "$UI_TUI" -eq 1 ]; then printf '%s' $'\033[?25h'; fi; return 0; }

read_key() {
  KEY=""
  local c c2 c3
  if ! IFS= read -rsn1 c; then KEY="EOF"; return 1; fi
  case "$c" in
    $'\x1b')
      if ! IFS= read -rsn1 -t 0.05 c2; then KEY="ESC"; return 0; fi
      case "$c2" in
        '['|'O')
          if ! IFS= read -rsn1 -t 0.05 c3; then KEY="ESC"; return 0; fi
          case "$c3" in
            A) KEY="UP" ;;
            B) KEY="DOWN" ;;
            C) KEY="RIGHT" ;;
            D) KEY="LEFT" ;;
            *) KEY="ESC" ;;
          esac ;;
        *) KEY="ESC" ;;
      esac ;;
    '') KEY="ENTER" ;;
    $'\n'|$'\r') KEY="ENTER" ;;
    ' ') KEY="SPACE" ;;
    q|Q) KEY="QUIT" ;;
    j) KEY="DOWN" ;;
    k) KEY="UP" ;;
    *) KEY="$c" ;;
  esac
}

CPU_PT=""
CPU_PI=""
SYS_TS=0
MEMPCT=""
DISKPCT=""
CPUPCT=""
MEM_TOTAL_KB=0
MEM_USED_KB=0
DISK_TOTAL_KB=0
DISK_USED_KB=0
MEMD=""
DISKD=""

human_kb() {
  local kb="${1:-0}"
  if [ "$kb" -ge 1048576 ]; then
    awk "BEGIN{printf \"%.1fG\", $kb/1048576}"
  elif [ "$kb" -ge 1024 ]; then
    awk "BEGIN{printf \"%.0fM\", $kb/1024}"
  else
    printf '%sK' "$kb"
  fi
}

mem_stats() {
  local key val total="" avail="" free="" buf="" cached=""
  MEMPCT=""
  MEM_TOTAL_KB=0
  MEM_USED_KB=0
  while read -r key val _; do
    case "$key" in
      MemTotal:)     total="$val" ;;
      MemAvailable:) avail="$val" ;;
      MemFree:)      free="$val" ;;
      Buffers:)      buf="$val" ;;
      Cached:)       cached="$val" ;;
    esac
  done < /proc/meminfo 2>/dev/null
  MEM_TOTAL_KB="${total:-0}"
  [ "$MEM_TOTAL_KB" -gt 0 ] || return 0
  if [ -z "$avail" ]; then
    avail=$(( ${free:-0} + ${buf:-0} + ${cached:-0} ))
  fi
  MEM_USED_KB=$((MEM_TOTAL_KB - avail))
  if [ "$MEM_USED_KB" -lt 0 ]; then MEM_USED_KB=0; fi
  MEMPCT=$((MEM_USED_KB * 100 / MEM_TOTAL_KB))
}

disk_stats() {
  local line total used cap i n pct p
  DISKPCT=""
  DISK_TOTAL_KB=0
  DISK_USED_KB=0
  p="${BASE_DIR:-/}"
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do
    p="$(dirname "$p")"
  done
  [ -d "$p" ] || p="/"
  line="$(df -k "$p" 2>/dev/null | tail -n 1)"
  [ -n "$line" ] || return 0
  local -a f=()
  read -r -a f <<< "$line"
  n="${#f[@]}"
  cap=0
  for ((i = 0; i < n; i++)); do
    case "${f[$i]}" in
      *%) cap=$((i + 1)); break ;;
    esac
  done
  # 以百分号列定位：total 在它前 3 列，used 在前 2 列
  [ "$cap" -ge 4 ] || return 0
  total="${f[$((cap - 4))]}"
  used="${f[$((cap - 3))]}"
  case "$total" in ''|*[!0-9]*) return 0 ;; esac
  case "$used" in ''|*[!0-9]*) return 0 ;; esac
  [ "$total" -gt 0 ] || return 0
  DISK_TOTAL_KB="$total"
  DISK_USED_KB="$used"
  pct=$((used * 100 / total))
  [ "$pct" -gt 100 ] && pct=100
  DISKPCT="$pct"
}

refresh_sys() {
  local now=$SECONDS
  if [ "$SYS_TS" -ne 0 ] && [ $((now - SYS_TS)) -lt 3 ]; then return 0; fi
  SYS_TS=$now
  mem_stats
  disk_stats
  MEMD=""
  if [ "${MEM_TOTAL_KB:-0}" -gt 0 ]; then
    MEMD="$(human_kb "$MEM_USED_KB")/$(human_kb "$MEM_TOTAL_KB")"
  fi
  DISKD=""
  if [ "${DISK_TOTAL_KB:-0}" -gt 0 ]; then
    DISKD="$(human_kb "$DISK_USED_KB")/$(human_kb "$DISK_TOTAL_KB")"
  fi
}

cpu_stats() {
  local t i pt pi dt di
  CPUPCT=""
  read -r t i <<< "$(awk '/^cpu /{print ($2+$3+$4+$5+$6+$7+$8), ($5+$6)}' /proc/stat 2>/dev/null)"
  [ -n "${t:-}" ] || return 0
  if [ -z "$CPU_PT" ]; then
    CPU_PT="$t"
    CPU_PI="$i"
    sleep 0.2
    read -r t i <<< "$(awk '/^cpu /{print ($2+$3+$4+$5+$6+$7+$8), ($5+$6)}' /proc/stat 2>/dev/null)"
  fi
  pt="$CPU_PT"
  pi="$CPU_PI"
  CPU_PT="$t"
  CPU_PI="$i"
  dt=$((t - pt))
  di=$((i - pi))
  if [ "$dt" -le 0 ]; then return 0; fi
  CPUPCT=$(((dt - di) * 100 / dt))
}

metric_seg() {
  local label="$1" pct="$2" detail="${3:-}" col bar i filled
  if [ -z "$pct" ]; then
    printf '%s●%s %s --' "$GRAY" "$RESET" "$label"
    return 0
  fi
  if [ "$pct" -ge 85 ]; then
    col="$RED"
  elif [ "$pct" -ge 60 ]; then
    col="$YELL"
  else
    col="$GREEN"
  fi
  filled=$(((pct * 10 + 99) / 100))
  if [ "$filled" -gt 10 ]; then filled=10; fi
  for ((i = 0; i < 10; i++)); do
    if [ "$i" -lt "$filled" ]; then
      bar+="${col}${G_FULL}"
    else
      bar+="${GRAY}${G_EMPTY}"
    fi
  done
  printf '%s●%s %s %s%% %s%s%s' \
    "$col" "$RESET" "$label" "$pct" "${detail:+$detail }" "$bar" "$RESET"
}

sys_line() {
  refresh_sys
  cpu_stats
  local load
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
  printf '  %s  %s\n' \
    "$(metric_seg "CPU" "$CPUPCT")" \
    "$(metric_seg "内存" "$MEMPCT" "$MEMD")"
  printf '  %s  %s●%s 负载 %s' \
    "$(metric_seg "磁盘" "$DISKPCT" "$DISKD")" \
    "$GRAY" "$RESET" "${load:-—}"
}

draw_header() {
  local title="$1" sub="${2:-}" line
  printf '  %s\n' "$(rainbow 'K O M A R I   A G E N T')"
  printf '  %s%s%s\n' "$GRAY" "$(repeat "$G_RULE" 40)" "$RESET"
  printf '%s\n' "$(sys_line)"
  printf '\n'
  printf '  %s%s%s  %s%s%s\n' "$PINK" "$G_BAR" "$RESET" "$B" "$title" "$RESET"
  if [ -n "$sub" ]; then
    printf '\n'
    while IFS= read -r line; do
      printf '  %s%s%s\n' "$GRAY" "$line" "$RESET"
    done <<< "$sub"
  fi
  printf '\n'
}

is_sep() { [ "${1:-}" = "──" ]; }

detect_nics() {
  local p
  if [ -d /sys/class/net ]; then
    for p in /sys/class/net/*; do
      [ -e "$p" ] && basename "$p"
    done
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    ip -o link 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//'
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig -a 2>/dev/null | awk '/^[a-zA-Z0-9]/ {print $1}' | tr -d ':'
  fi
}

detect_mounts() {
  [ -r /proc/mounts ] || return 0
  awk '$2 !~ /^\/(proc|sys|dev|run)(\/|$)/ {print $2}' /proc/mounts 2>/dev/null \
    | awk '!seen[$0]++' | sort
}

pick_multi() { # 标题 副标题 分隔符 变量名 候选项...
  local title="$1" sub="$2" sep="$3" var="$4"
  shift 4
  local -a opts=("$@")
  local cur="${!var}" x c i found

  if [ "$UI_TUI" -eq 0 ]; then
    local tv
    ask "${title}（用 $sep 分隔，空=全部，- 清空）" "$cur" tv
    [ "$tv" = "-" ] && tv=""
    printf -v "$var" '%s' "$tv"
    return 0
  fi

  # 当前值拆开（用 read -a，避免路径被 glob 展开）
  local IFS_OLD="$IFS"
  local -a sel=()
  IFS="$sep" read -r -a sel <<< "$cur"
  IFS="$IFS_OLD"

  # 已配置但不在候选里的值也补进来
  for x in ${sel[@]+"${sel[@]}"}; do
    [ -n "$x" ] || continue
    found=0
    for c in ${opts[@]+"${opts[@]}"}; do
      if [ "$c" = "$x" ]; then found=1; break; fi
    done
    if [ "$found" -eq 0 ]; then opts+=("$x"); fi
  done

  local -a checked=()
  for ((i = 0; i < ${#opts[@]}; i++)); do
    checked+=(0)
    for x in ${sel[@]+"${sel[@]}"}; do
      if [ "$x" = "${opts[$i]}" ]; then checked[$i]=1; fi
    done
  done

  local n="${#opts[@]}" has_manual=1
  [ "${MULTI_NO_MANUAL:-0}" = "1" ] && has_manual=0
  local total=$((n + 1 + has_manual)) sel_i=0
  hide_cursor
  while :; do
    screen_home
    draw_header "$title" "$sub"
    for ((i = 0; i < n; i++)); do
      local mark
      if [ "${checked[$i]}" -eq 1 ]; then mark="${GREEN}[x]${RESET}"; else mark="${GRAY}[ ]${RESET}"; fi
      if [ "$i" -eq "$sel_i" ]; then
        printf '   %s❯%s %s %s\n' "$PINK" "$RESET" "$mark" "${opts[$i]}"
      else
        printf '     %s %s\n' "$mark" "${opts[$i]}"
      fi
    done
    printf '     %s──────%s\n' "$DIM" "$RESET"
    if [ "$has_manual" -eq 1 ]; then
      if [ "$sel_i" -eq "$n" ]; then
        printf '   %s❯%s %s\n' "$PINK" "$RESET" "手动输入…"
      else
        printf '     %s\n' "手动输入…"
      fi
    fi
    if [ "$sel_i" -eq $((n + has_manual)) ]; then
      printf '   %s❯%s %s\n' "$PINK" "$RESET" "${GREEN}完成${RESET}"
    else
      printf '     %s\n' "完成"
    fi
    printf '\n   %s空格/回车 勾选 · q 取消%s\n' "$GRAY" "$RESET"
    if ! read_key; then break; fi
    case "$KEY" in
      UP)   sel_i=$(((sel_i + total - 1) % total)) ;;
      DOWN) sel_i=$(((sel_i + 1) % total)) ;;
      QUIT|ESC) show_cursor; return 1 ;;
      ENTER|SPACE)
        if [ "$sel_i" -lt "$n" ]; then
          if [ "${checked[$sel_i]}" -eq 1 ]; then checked[$sel_i]=0; else checked[$sel_i]=1; fi
        elif [ "$has_manual" -eq 1 ] && [ "$sel_i" -eq "$n" ]; then
          show_cursor
          screen_home
          draw_header "$title" "手动追加（多个用 $sep 分隔，回车返回）"
          local add
          ask "追加" "" add
          if [ -n "$add" ]; then
            local -a adds=()
            IFS="$sep" read -r -a adds <<< "$add"
            IFS="$IFS_OLD"
            for x in ${adds[@]+"${adds[@]}"}; do
              [ -n "$x" ] || continue
              opts+=("$x"); checked+=("1")
            done
            n="${#opts[@]}"; total=$((n + 1 + has_manual))
            sel_i=$((n + has_manual))
          fi
          hide_cursor
        else
          break
        fi ;;
    esac
  done
  show_cursor

  local out=""
  for ((i = 0; i < n; i++)); do
    if [ "${checked[$i]}" -eq 1 ]; then
      if [ -n "$out" ]; then out+="$sep"; fi
      out+="${opts[$i]}"
    fi
  done
  printf -v "$var" '%s' "$out"
  return 0
}

select_nics_multi() { # 需要选中的网卡数量
  local want="$1" tmp="" x
  local -a c=()
  while IFS= read -r x; do [ -n "$x" ] && c+=("$x"); done <<< "$(auto_nics "")"
  while :; do
    if ! pick_multi "按网卡分配" "勾选 ${want} 块网卡（对应 ${want} 个实例）" "," tmp ${c[@]+"${c[@]}"}; then
      return 1
    fi
    NIC_MAP=()
    local IFS_OLD="$IFS"
    IFS=',' read -r -a NIC_MAP <<< "$tmp"
    IFS="$IFS_OLD"
    if [ "${#NIC_MAP[@]}" -eq "$want" ]; then return 0; fi
    warn "勾选了 ${#NIC_MAP[@]} 块，需要 $want 块"
  done
}

select_nics_any() {
  local tmp="" x
  local -a c=()
  while IFS= read -r x; do [ -n "$x" ] && c+=("$x"); done <<< "$(auto_nics "")"
  if ! pick_multi "按网卡批量" "勾选本批要装的网卡，剩下的下次再来" "," tmp ${c[@]+"${c[@]}"}; then
    return 1
  fi
  NIC_MAP=()
  local IFS_OLD="$IFS"
  IFS=',' read -r -a NIC_MAP <<< "$tmp"
  IFS="$IFS_OLD"
  if [ "${#NIC_MAP[@]}" -eq 0 ]; then
    warn "至少要选一块网卡"
    return 1
  fi
  return 0
}

used_nics() { # 已被现有实例绑定的网卡
  local i tok
  for ((i = 0; i < D_COUNT; i++)); do
    printf '%s\n' "${D_ARGS[$i]:-}"
  done | tr ' ' '\n' | (
    flag=0
    while IFS= read -r tok; do
      if [ "$flag" -eq 1 ]; then
        flag=0
        case "$tok" in
          ''|-*) ;;
          *) printf '%s\n' "$tok" | tr ',' '\n' ;;
        esac
      elif [ "$tok" = "--include-nics" ]; then
        flag=1
      else
        case "$tok" in
          --include-nics=*) printf '%s\n' "${tok#--include-nics=}" | tr ',' '\n' ;;
        esac
      fi
    done
  ) | sort -u
}

auto_nics() { # [名称通配过滤，如 fip*]
  local pat="${1:-}" n used
  used=" $(used_nics | tr '\n' ' ') "
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    case "$used" in
      *" $n "*) continue ;;
    esac
    case "$n" in
      lo|docker*|veth*|br-*|virbr*|sit*|tunl*|ip6tnl*|dummy*) continue ;;
    esac
    if [ -n "$pat" ]; then
      case "$n" in
        $pat) ;;
        *) continue ;;
      esac
    fi
    printf '%s\n' "$n"
  done <<< "$(detect_nics)"
}

auto_pick_nics() { # 需要数量（0=全部） [名称过滤]
  local want="${1:-0}" pat="${2:-}" n
  NIC_MAP=()
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    NIC_MAP+=("$n")
    if [ "$want" -gt 0 ] && [ "${#NIC_MAP[@]}" -ge "$want" ]; then break; fi
  done <<< "$(auto_nics "$pat")"
  if [ "${#NIC_MAP[@]}" -eq 0 ]; then return 1; fi
  if [ "$want" -gt 0 ] && [ "${#NIC_MAP[@]}" -lt "$want" ]; then return 1; fi
  return 0
}

next_free_suffix() {
  local n=1
  while service_name_taken "${SVC_PREFIX}-${n}"; do n=$((n + 1)); done
  printf '%s' "$n"
}

ask_start_index() { # 默认值；结果写入 NAME_START
  local def="$1" s i bad
  while :; do
    ask "起始编号（服务名从 ${SVC_PREFIX}-<N> 开始）" "$def" s
    case "$s" in ''|*[!0-9]*) warn "请输入数字"; continue ;; esac
    if [ "$s" -lt 1 ]; then warn "至少从 1 开始"; continue; fi
    bad=0
    for ((i = 0; i < INSTANCE_COUNT; i++)); do
      if service_name_taken "${SVC_PREFIX}-$((s + i))"; then bad=1; break; fi
    done
    if [ "$bad" -eq 0 ]; then
      NAME_START="$s"
      return 0
    fi
    warn "从 ${s} 开始会与已有服务重名"
  done
}

pick() {
  local title="$1" sub="$2"
  shift 2
  local -a items=("$@")
  local n="${#items[@]}" i v
  local hint="${PICK_HINT:-↑↓ 移动 · Enter 选择 · q 返回}"
  PICK_HINT=""
  if [ "$n" -eq 0 ]; then return 1; fi

  local -a av=()
  for ((i = 0; i < n; i++)); do
    if ! is_sep "${items[$i]}"; then av+=("$i"); fi
  done
  local m="${#av[@]}"
  if [ "$m" -eq 0 ]; then return 1; fi

  local sel="${av[0]}" pos=0
  if [ "${PICK_START:-0}" -ge 0 ] && [ "${PICK_START:-0}" -lt "$n" ] \
     && ! is_sep "${items[${PICK_START:-0}]}"; then
    sel="${PICK_START:-0}"
  fi
  PICK_START=0
  for ((i = 0; i < m; i++)); do
    if [ "${av[$i]}" -eq "$sel" ]; then pos="$i"; fi
  done

  if [ "$UI_TUI" -eq 0 ]; then
    printf '\n  %s%s%s  %s\n\n' "$PINK" "$G_BAR" "$RESET" "$title"
    if [ -n "$sub" ]; then printf '  %s%s%s\n\n' "$GRAY" "$sub" "$RESET"; fi
    local idx=0
    for ((i = 0; i < n; i++)); do
      if is_sep "${items[$i]}"; then
        printf '   %s──────%s\n' "$DIM" "$RESET"
      else
        idx=$((idx + 1))
        printf '   %s%s%d%s  %s\n' "$CYAN" "$B" "$idx" "$RESET" "${items[$i]}"
      fi
    done
    printf '\n'
    ask_int "选择" "$((pos + 1))" v 1 "$m"
    PICK_RESULT="${av[$((v - 1))]}"
    return 0
  fi

  hide_cursor
  while :; do
    screen_home
    draw_header "$title" "$sub"
    for ((i = 0; i < n; i++)); do
      if is_sep "${items[$i]}"; then
        printf '   %s──────%s\n' "$DIM" "$RESET"
      elif [ "$i" -eq "$sel" ]; then
        printf '   %s❯%s %s%s%s\n' "$PINK" "$RESET" "$B" "${items[$i]}" "$RESET"
      else
        printf '     %s\n' "${items[$i]}"
      fi
    done
    printf '\n   %s%s%s\n' "$GRAY" "$hint" "$RESET"
    if ! read_key; then show_cursor; return 1; fi
    case "$KEY" in
      UP)   pos=$(((pos + m - 1) % m)); sel="${av[$pos]}" ;;
      DOWN) pos=$(((pos + 1) % m)); sel="${av[$pos]}" ;;
      ENTER|SPACE) break ;;
      QUIT|ESC) show_cursor; return 2 ;;
      [0-9])
        v=$((KEY - 1))
        if [ "$v" -ge 0 ] && [ "$v" -lt "$m" ]; then pos="$v"; sel="${av[$pos]}"; fi ;;
    esac
  done
  show_cursor
  PICK_RESULT=$sel
  return 0
}

pause_any() {
  [ "$UI_TUI" -eq 1 ] || return 0
  printf '\n   %s按任意键返回…%s' "$GRAY" "$RESET"
  read_key >/dev/null 2>&1 || true
  printf '\n'
}

cfg_row() {
  local idx="$1" sel="$2" label="$3" value="$4"
  if [ "$idx" -eq "$sel" ]; then
    printf '   %s❯%s %s%s:%s %s\n' "$PINK" "$RESET" "$B" "$label" "$RESET" "$value"
  else
    printf '     %s:%s %s\n' "$label" "$RESET" "$value"
  fi
}

edit_num() {
  local label="$1" var="$2"
  show_cursor
  screen_home
  draw_header "高级参数" "修改后回车确认"
  ask_num "$label" "${!var}" "$var"
  hide_cursor
}

edit_int() {
  local label="$1" var="$2" lo="$3" hi="$4"
  show_cursor
  screen_home
  draw_header "高级参数" "修改后回车确认"
  ask_int "$label" "${!var}" "$var" "$lo" "$hi"
  hide_cursor
}

edit_str() {
  local label="$1" var="$2" v
  show_cursor
  screen_home
  draw_header "修改" "回车保留，输入 - 清空"
  ask "$label" "${!var}" v
  if [ "$v" = "-" ]; then v=""; fi
  printf -v "$var" '%s' "$v"
  hide_cursor
}

# ==================================================================== 配置 ===
ENDPOINT=""
BASE_DIR="/opt/komari"
SVC_PREFIX="komari-agent"
INTERVAL="1.0"
INFO_INTERVAL="5"
DISABLE_WEBSSH=0
DISABLE_AUTOUPDATE=0
MEM_CACHE=0
GET_IP_NIC=0
INSECURE=0
INCLUDE_NICS=""
EXCLUDE_NICS=""
MOUNT_POINTS=""
MONTH_ROTATE="0"
GPU_MONITOR=0
EXTRA_AGENT=""
INSTALL_VERSION=""
GH_PROXY=""
INSTANCE_COUNT=1
INSTALL_DELAY="${KA_INSTALL_DELAY:-0}"
MULTI=0
AUTH_MODE="token"
AD_KEY=""
BATCH_NIC=0
NIC_MAP=()
MULTI_NO_MANUAL=0
FORCE_SUFFIX=0
NAME_START=1
CANCELED=0
TOKENS=()
ARGS=()
IARGS=()

load_conf() {
  [ -f "$KA_CONF" ] || return 0
  # shellcheck disable=SC1090
  . "$KA_CONF" 2>/dev/null || return 0
  ENDPOINT="${KA_ENDPOINT:-$ENDPOINT}"
  BASE_DIR="${KA_BASE_DIR:-$BASE_DIR}"
  SVC_PREFIX="${KA_SVC_PREFIX:-$SVC_PREFIX}"
  INTERVAL="${KA_INTERVAL:-$INTERVAL}"
  INFO_INTERVAL="${KA_INFO_INTERVAL:-$INFO_INTERVAL}"
  DISABLE_WEBSSH="${KA_WEBSSH:-$DISABLE_WEBSSH}"
  DISABLE_AUTOUPDATE="${KA_AUTOUPDATE:-$DISABLE_AUTOUPDATE}"
  MEM_CACHE="${KA_MEMCACHE:-$MEM_CACHE}"
  GET_IP_NIC="${KA_GETIP:-$GET_IP_NIC}"
  INSECURE="${KA_INSECURE:-$INSECURE}"
  INCLUDE_NICS="${KA_INCLUDE_NICS:-$INCLUDE_NICS}"
  EXCLUDE_NICS="${KA_EXCLUDE_NICS:-$EXCLUDE_NICS}"
  MOUNT_POINTS="${KA_MOUNT_POINTS:-$MOUNT_POINTS}"
  MONTH_ROTATE="${KA_MONTH_ROTATE:-$MONTH_ROTATE}"
  GPU_MONITOR="${KA_GPU:-$GPU_MONITOR}"
  EXTRA_AGENT="${KA_EXTRA:-$EXTRA_AGENT}"
  INSTALL_VERSION="${KA_INSTALL_VERSION:-$INSTALL_VERSION}"
  GH_PROXY="${KA_GH_PROXY:-$GH_PROXY}"
  INSTANCE_COUNT="${KA_INSTANCE_COUNT:-$INSTANCE_COUNT}"
  INSTALL_DELAY="${KA_INSTALL_DELAY:-$INSTALL_DELAY}"
  AGENT_IMPL="${KA_IMPL:-$AGENT_IMPL}"
}

save_conf() {
  [ "$(id -u)" -eq 0 ] || return 0
  mkdir -p "$(dirname "$KA_CONF")" 2>/dev/null || return 0
  (
    umask 077
    cat > "$KA_CONF" <<EOF
# ka 生成的配置（不含 token）
KA_ENDPOINT='$ENDPOINT'
KA_BASE_DIR='$BASE_DIR'
KA_SVC_PREFIX='$SVC_PREFIX'
KA_INTERVAL='$INTERVAL'
KA_INFO_INTERVAL='$INFO_INTERVAL'
KA_WEBSSH='$DISABLE_WEBSSH'
KA_AUTOUPDATE='$DISABLE_AUTOUPDATE'
KA_MEMCACHE='$MEM_CACHE'
KA_GETIP='$GET_IP_NIC'
KA_INSECURE='$INSECURE'
KA_INCLUDE_NICS='$INCLUDE_NICS'
KA_EXCLUDE_NICS='$EXCLUDE_NICS'
KA_MOUNT_POINTS='$MOUNT_POINTS'
KA_MONTH_ROTATE='$MONTH_ROTATE'
KA_GPU='$GPU_MONITOR'
KA_EXTRA='$EXTRA_AGENT'
KA_INSTALL_VERSION='$INSTALL_VERSION'
KA_GH_PROXY='$GH_PROXY'
KA_INSTANCE_COUNT='$INSTANCE_COUNT'
KA_INSTALL_DELAY='$INSTALL_DELAY'
KA_IMPL='$AGENT_IMPL'
EOF
  ) 2>/dev/null || true
}

# ================================================================ 输入封装 ===
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

ask() {
  local prompt="$1" def="$2" __out="$3" __in
  if [ -n "$def" ]; then
    printf '  %s%s%s %s %s[%s]%s: ' "$PINK" "$G_ARROW" "$RESET" "$prompt" "$GRAY" "$def" "$RESET"
  else
    printf '  %s%s%s %s: ' "$PINK" "$G_ARROW" "$RESET" "$prompt"
  fi
  if ! IFS= read -r __in; then
    printf '\n'
    die "读取输入失败（不是交互式终端？）"
  fi
  __in="$(trim "$__in")"
  [ -z "$__in" ] && __in="$def"
  printf -v "$__out" '%s' "$__in"
}

ask_int() {
  local prompt="$1" def="$2" __out="$3" lo="$4" hi="$5" v
  while :; do
    ask "$prompt" "$def" v
    case "$v" in
      ''|*[!0-9]*) warn "请输入整数"; continue ;;
    esac
    if [ "$v" -lt "$lo" ] || [ "$v" -gt "$hi" ]; then
      warn "取值范围 $lo - $hi"; continue
    fi
    printf -v "$__out" '%s' "$v"
    return 0
  done
}

ask_num() {
  local prompt="$1" def="$2" __out="$3" v
  while :; do
    ask "$prompt" "$def" v
    case "$v" in
      ''|*[!0-9.]*|*.*.*) warn "请输入数字，例如 1 或 0.5"; continue ;;
    esac
    printf -v "$__out" '%s' "$v"
    return 0
  done
}

mask() {
  local s="$1"
  if [ "${#s}" -le 10 ]; then
    printf '****'
  else
    printf '%s…%s' "${s:0:4}" "${s: -4}"
  fi
}

# ================================================================ 环境/服务 ===
need_root() {
  if [ "$(id -u)" -eq 0 ]; then return 0; fi
  if command -v sudo >/dev/null 2>&1; then
    die "需要 root 权限：sudo ka"
  fi
  die "需要 root 权限：请用 root 登录或 su - 后再执行"
}

have_curl() { command -v curl >/dev/null 2>&1; }
have_wget() { command -v wget >/dev/null 2>&1; }

need_curl() {
  if have_curl || have_wget; then return 0; fi
  die "需要 curl 或 wget，请先安装其中一个"
}

dl_to() { # url 输出文件 [超时秒]
  local url="$1" out="$2" t="${3:-30}"
  if have_curl; then
    curl -fsSL --max-time "$t" "$url" -o "$out"
  else
    wget -q -T "$t" -O "$out" "$url"
  fi
}

dl_str() { # url [超时秒] → stdout
  local url="$1" t="${2:-8}"
  if have_curl; then
    curl -fsSL --max-time "$t" "$url"
  else
    wget -q -T "$t" -O - "$url"
  fi
}

http_code() { # url → 三位状态码或 000
  local url="$1"
  if have_curl; then
    curl -o /dev/null -sS -k -w '%{http_code}' --max-time 8 "$url" 2>/dev/null || printf '000'
  elif have_wget && wget -q --spider -T 8 "$url" >/dev/null 2>&1; then
    printf '200'
  else
    printf '000'
  fi
}

INIT_SYS=""
detect_init() {
  INIT_SYS="none"
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    INIT_SYS="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYS="openrc"
  elif [ -d /etc/init.d ] && [ -n "$(ls -A /etc/init.d 2>/dev/null)" ]; then
    INIT_SYS="openrc"
  fi
  printf '%s' "$INIT_SYS"
}

init_label() {
  case "$1" in
    systemd) printf 'systemd' ;;
    openrc)  printf 'OpenRC' ;;
    *)       printf '未知' ;;
  esac
}

inst_dir() {
  if [ "$FORCE_SUFFIX" -eq 1 ]; then
    printf '%s/nat%s' "$BASE_DIR" "$((NAME_START + $1 - 1))"
  elif [ "$INSTANCE_COUNT" -eq 1 ]; then
    printf '%s' "$BASE_DIR"
  else
    printf '%s/nat%s' "$BASE_DIR" "$1"
  fi
}
inst_svc() {
  if [ "$FORCE_SUFFIX" -eq 1 ]; then
    printf '%s-%s' "$SVC_PREFIX" "$((NAME_START + $1 - 1))"
  elif [ "$INSTANCE_COUNT" -eq 1 ]; then
    printf '%s' "$SVC_PREFIX"
  else
    printf '%s-%s' "$SVC_PREFIX" "$1"
  fi
}

build_args() {
  ARGS=(-e "$ENDPOINT" -i "$INTERVAL" --info-report-interval "$INFO_INTERVAL")
  [ "$DISABLE_WEBSSH" -eq 1 ]     && ARGS+=(--disable-web-ssh)
  [ "$DISABLE_AUTOUPDATE" -eq 1 ] && ARGS+=(--disable-auto-update)
  [ "$MEM_CACHE" -eq 1 ]          && ARGS+=(--memory-include-cache)
  [ "$GET_IP_NIC" -eq 1 ]         && ARGS+=(--get-ip-addr-from-nic)
  [ "$INSECURE" -eq 1 ]           && ARGS+=(-u)
  [ "$GPU_MONITOR" -eq 1 ]        && ARGS+=(--gpu)
  [ -n "$INCLUDE_NICS" ]          && ARGS+=(--include-nics "$INCLUDE_NICS")
  [ -n "$EXCLUDE_NICS" ]          && ARGS+=(--exclude-nics "$EXCLUDE_NICS")
  [ -n "$MOUNT_POINTS" ]          && ARGS+=(--include-mountpoint "$MOUNT_POINTS")
  [ "$MONTH_ROTATE" != "0" ]      && ARGS+=(--month-rotate "$MONTH_ROTATE")
  if [ -n "$EXTRA_AGENT" ]; then
    # shellcheck disable=SC2206
    ARGS+=($EXTRA_AGENT)
  fi
  return 0
}

install_args() {
  IARGS=()
  [ -n "$INSTALL_VERSION" ] && IARGS+=(--install-version "$INSTALL_VERSION")
  [ -n "$GH_PROXY" ]        && IARGS+=(--install-ghproxy "$GH_PROXY")
  return 0
}

# 从参数串里解析 -e / -t
EP=""
TK=""
AD=""
parse_args() {
  local -a av=($1)
  local i
  EP=""; TK=""; AD=""
  for ((i = 0; i < ${#av[@]}; i++)); do
    case "${av[$i]}" in
      -e|--endpoint)       EP="${av[$((i + 1))]:-}" ;;
      -t|--token)          TK="${av[$((i + 1))]:-}" ;;
      --auto-discovery)    AD="${av[$((i + 1))]:-}" ;;
    esac
  done
}

svc_state() { # 名字 类型
  local n="$1" k="$2"
  case "$k" in
    systemd) systemctl is-active "$n" 2>/dev/null ;;
    openrc)
      if rc-service "$n" status >/dev/null 2>&1; then printf 'active'; else printf 'inactive'; fi ;;
    proc)
      if [ -d "/proc/${n#pid-}" ]; then printf 'active'; else printf 'inactive'; fi ;;
  esac
}

svc_ctl() { # 动作 名字 类型
  local act="$1" n="$2" k="$3"
  case "$k" in
    systemd) systemctl "$act" "$n" >/dev/null 2>&1 ;;
    openrc)  rc-service "$n" "$act" >/dev/null 2>&1 ;;
    proc)
      case "$act" in
        stop) kill "${n#pid-}" >/dev/null 2>&1 ;;
        *) return 1 ;;
      esac ;;
  esac
}

svc_logs() { # 名字 类型 行数
  local n="$1" k="$2" lines="${3:-100}"
  case "$k" in
    systemd)
      journalctl -u "$n" -n "$lines" --no-pager 2>/dev/null ;;
    openrc)
      if [ -f "/var/log/$n.log" ]; then
        tail -n "$lines" "/var/log/$n.log"
      elif [ -f /var/log/komari-agent.log ]; then
        tail -n "$lines" /var/log/komari-agent.log
      elif command -v logread >/dev/null 2>&1; then
        logread 2>/dev/null | grep -i "$n" | tail -n "$lines"
      elif [ -f /var/log/messages ]; then
        grep -i "$n" /var/log/messages | tail -n "$lines"
      else
        return 1
      fi ;;
    *) return 1 ;;
  esac
}

svc_enabled() { # 名字 类型  local n="$1" k="$2"
  case "$k" in
    systemd) systemctl is-enabled "$n" 2>/dev/null || true ;;
    openrc)
      if rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx "$n"; then
        printf 'enabled'
      else
        printf 'disabled'
      fi ;;
    *) printf '—' ;;
  esac
}

# ============================================================ 已有实例扫描 ===
D_COUNT=0
D_NAME=(); D_KIND=(); D_EXE=(); D_DIR=(); D_EP=(); D_TK=(); D_TAG=(); D_ARGS=(); D_AD=()

add_instance() { # 名字 类型 可执行文件 面板 token 原始参数 自动发现密钥
  local name="$1" kind="$2" exe="$3" ep="$4" tk="$5" raw="${6:-}" ad="${7:-}"
  local dir tag
  dir="$(dirname "$exe")"
  tag="外部"
  case "$name" in
    "$SVC_PREFIX"|"$SVC_PREFIX"-*) tag="受管" ;;
  esac
  case "$dir" in
    "$BASE_DIR"|"${BASE_DIR%/}"/*|/opt/komari|/opt/komari/*) tag="受管" ;;
  esac
  D_NAME+=("$name"); D_KIND+=("$kind"); D_EXE+=("$exe"); D_DIR+=("$dir")
  D_EP+=("$ep"); D_TK+=("$tk"); D_TAG+=("$tag"); D_ARGS+=("$raw"); D_AD+=("$ad")
  D_COUNT=$((D_COUNT + 1))
}

discover_systemd() {
  local -a units=()
  local hit unit line exe raw
  while IFS= read -r hit; do
    [ -n "$hit" ] && units+=("$(basename "$hit" .service)")
  done <<< "$(grep -lis 'komari-agent' \
      /etc/systemd/system/*.service \
      /usr/lib/systemd/system/*.service \
      /lib/systemd/system/*.service 2>/dev/null)"
  while IFS= read -r unit; do
    [ -n "$unit" ] && units+=("${unit%.service}")
  done <<< "$(systemctl list-unit-files 'komari-agent*.service' --no-legend --no-pager 2>/dev/null | awk '{print $1}')"
  [ "${#units[@]}" -eq 0 ] && return 0

  local sorted
  sorted="$(printf '%s\n' "${units[@]}" | sort -u)"
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    line="$(systemctl cat "$unit.service" 2>/dev/null | sed -n 's/^ExecStart=//p' | head -n1)"
    [ -n "$line" ] || continue
    exe="${line%% *}"
    exe="${exe#-}"; exe="${exe%\"}"; exe="${exe#\"}"
    case "$exe" in *komari*) ;; *) continue ;; esac
    parse_args "$line"
    raw="${line#* }"
    [ "$raw" = "$line" ] && raw=""
    add_instance "$unit" systemd "$exe" "$EP" "$TK" "$raw" "$AD"
  done <<< "$sorted"
}

discover_openrc() {
  local f name exe args conf
  for f in /etc/init.d/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if ! printf '%s' "$name" | grep -qi 'komari'; then
      grep -qi 'komari' "$f" 2>/dev/null || continue
    fi
    exe="$(sed -n 's/^[[:space:]]*command=//p' "$f" 2>/dev/null | head -n1 | tr -d '"')"
    args="$(sed -n 's/^[[:space:]]*command_args=//p' "$f" 2>/dev/null | head -n1 | tr -d '"')"
    conf="/etc/conf.d/$name"
    if [ -z "$exe" ] && [ -f "$conf" ]; then
      exe="$(sed -n 's/^[[:space:]]*command=//p' "$conf" 2>/dev/null | head -n1 | tr -d '"')"
      args="$(sed -n 's/^[[:space:]]*command_args=//p' "$conf" 2>/dev/null | head -n1 | tr -d '"')"
    fi
    if [ -z "$exe" ]; then continue; fi
    parse_args "$args"
    add_instance "$name" openrc "$exe" "$EP" "$TK" "$args" "$AD"
  done
}

init_for_exe() { # 用可执行文件路径反查是哪个 init 脚本
  local exe="$1" f
  for f in /etc/init.d/*; do
    [ -f "$f" ] || continue
    if grep -qF "$exe" "$f" 2>/dev/null; then
      basename "$f"
      return 0
    fi
  done
  return 1
}

discover_procs() {
  local p cmd exe pid i covered
  for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    cmd="$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)"
    [ -n "$cmd" ] || continue
    exe="${cmd%% *}"
    case "$exe" in *komari*) ;; *) continue ;; esac
    pid="${p#/proc/}"
    [ "$pid" = "$$" ] && continue
    parse_args "$cmd"
    covered=0
    for ((i = 0; i < D_COUNT; i++)); do
      if [ "${D_EXE[$i]}" = "$exe" ]; then covered=$((i + 1)); break; fi
    done
    if [ "$covered" -gt 0 ]; then
      # 服务已登记，用真实命令行补全缺失的面板地址 / token / 参数
      local j=$((covered - 1))
      if [ -z "${D_EP[$j]}" ] && [ -n "$EP" ]; then D_EP[$j]="$EP"; fi
      if [ -z "${D_TK[$j]}" ] && [ -n "$TK" ]; then D_TK[$j]="$TK"; fi
      if [ -z "${D_ARGS[$j]}" ] && [ -n "$cmd" ]; then D_ARGS[$j]="${cmd#* }"; fi
      continue
    fi
    local svc
    if svc="$(init_for_exe "$exe")"; then
      add_instance "$svc" openrc "$exe" "$EP" "$TK" "${cmd#* }" "$AD"
    else
      add_instance "pid-$pid" proc "$exe" "$EP" "$TK" "${cmd#* }" "$AD"
    fi
  done
}

discover_instances() {
  D_COUNT=0
  D_NAME=(); D_KIND=(); D_EXE=(); D_DIR=(); D_EP=(); D_TK=(); D_TAG=(); D_ARGS=(); D_AD=()
  detect_init >/dev/null
  case "$INIT_SYS" in
    systemd) discover_systemd ;;
    openrc)  discover_openrc ;;
  esac
  discover_procs
}

count_managed() {
  local i n=0
  for ((i = 0; i < D_COUNT; i++)); do
    if [ "${D_TAG[$i]}" = "受管" ]; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

agent_mem_kb() { # 输出 "进程数 总RSS(KB)"
  local p cmd rss n=0 total=0
  for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    cmd="$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)"
    case "$cmd" in
      */komari/*|*/komari-agent*) ;;
      *) continue ;;
    esac
    rss="$(awk '/^VmRSS:/{print $2}' "$p/status" 2>/dev/null)"
    [ -n "$rss" ] || continue
    total=$((total + rss))
    n=$((n + 1))
  done
  printf '%s %s' "$n" "$total"
}

# ---------------------------------------------------------------- 元数据 ---
META_FILE="${KA_META:-/etc/ka-meta.tsv}"

http_get() { dl_str "$1" 4 2>/dev/null; }

detect_public_ip() {
  local u ip
  for u in "https://api.ip.sb/ip" "https://ipinfo.io/ip"; do
    ip="$(http_get "$u" | tr -d '[:space:]')"
    case "$ip" in
      ''|*[!0-9a-fA-F:.]*) continue ;;
    esac
    printf '%s' "$ip"
    return 0
  done
  return 1
}

detect_geo_label() {
  local ip="$1" j c cy
  j="$(http_get "http://ip-api.com/json/${ip}?lang=zh-CN&fields=status,country,city")"
  if printf '%s' "$j" | grep -q '"status":"success"'; then
    c="$(printf '%s' "$j" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')"
    cy="$(printf '%s' "$j" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')"
    if [ -n "$c" ] && [ -n "$cy" ]; then printf '%s·%s' "$c" "$cy"; return 0; fi
    if [ -n "$c" ]; then printf '%s' "$c"; return 0; fi
  fi
  j="$(http_get "https://ipinfo.io/${ip}/json")"
  c="$(printf '%s' "$j" | sed -n 's/.*"country": *"\([^"]*\)".*/\1/p')"
  cy="$(printf '%s' "$j" | sed -n 's/.*"city": *"\([^"]*\)".*/\1/p')"
  if [ -n "$c" ] && [ -n "$cy" ]; then printf '%s·%s' "$c" "$cy"; return 0; fi
  if [ -n "$c" ]; then printf '%s' "$c"; fi
  return 0
}

GEO_TRIED=0
GEO_IP=""
GEO_RESULT=""
geo_note() {
  GEO_RESULT=""
  [ "${KA_NO_GEO:-0}" = "1" ] && return 0
  if [ "$GEO_TRIED" -eq 0 ]; then
    GEO_TRIED=1
    GEO_IP="$(detect_public_ip || true)"
    if [ -n "$GEO_IP" ]; then
      GEO_RESULT="$(detect_geo_label "$GEO_IP")"
    fi
  fi
  return 0
}

meta_get() {
  [ -f "$META_FILE" ] || return 0
  awk -F "$(printf '\t')" -v k="$1" '$1 == k { print $2; exit }' "$META_FILE" 2>/dev/null
}

meta_set() {
  local name="$1" note="$2" tmp
  mkdir -p "$(dirname "$META_FILE")" 2>/dev/null || true
  tmp="${META_FILE}.tmp.$$"
  : > "$tmp" 2>/dev/null || { warn "无法写入 $META_FILE"; return 1; }
  if [ -f "$META_FILE" ]; then
    awk -F "$(printf '\t')" -v k="$name" '$1 != k' "$META_FILE" >> "$tmp" 2>/dev/null
  fi
  if [ -n "$note" ]; then
    printf '%s\t%s\n' "$name" "$note" >> "$tmp"
  fi
  if mv -f "$tmp" "$META_FILE" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
  warn "写入 $META_FILE 失败"
  return 1
}

find_idx() {
  local name="$1" i
  for ((i = 0; i < D_COUNT; i++)); do
    if [ "${D_NAME[$i]}" = "$name" ]; then printf '%s' "$i"; return 0; fi
  done
  return 1
}

# ------------------------------------------------ 安装器 / 服务操作工具 ---
KA_TMP=""
fetch_installer() {
  [ -n "$KA_TMP" ] && [ -s "$KA_TMP" ] && return 0
  need_curl
  KA_TMP="$(mktemp /tmp/ka-install.XXXXXX)" || return 1
  if ! dl_to "$KA_INSTALLER" "$KA_TMP" 120 || [ ! -s "$KA_TMP" ]; then
    rm -f "$KA_TMP"
    KA_TMP=""
    return 1
  fi
}

filter_args() { # 去掉 -e/-t/--auto-discovery 及其值，保留其余参数
  local -a av=($1)
  local i s=""
  for ((i = 0; i < ${#av[@]}; i++)); do
    case "${av[$i]}" in
      -e|--endpoint|-t|--token|--auto-discovery) i=$((i + 1)); continue ;;
      *) s+=" ${av[$i]}" ;;
    esac
  done
  printf '%s' "${s# }"
}

reinstall_service() { # 目录 服务名 面板 [token] [额外参数] [自动发现密钥]
  local dir="$1" name="$2" ep="$3" tk="${4:-}" extra="${5:-}" ad="${6:-}"
  local -a auth=()
  if [ -n "$ad" ]; then
    auth=(--auto-discovery "$ad")
  elif [ -n "$tk" ]; then
    auth=(-t "$tk")
  fi

  if [ "$AGENT_IMPL" = "zig" ]; then
    prepare_agent_cache zig 0 || return 1
    local args="-e $ep"
    [ -n "$tk" ] && args+=" -t $tk"
    [ -n "$ad" ] && args+=" --auto-discovery $ad"
    [ -n "$extra" ] && args+=" $extra"
    install_agent_local "$dir" "$name" "$args"
    return $?
  fi

  install_args
  # shellcheck disable=SC2086
  sh "$KA_TMP" -e "$ep" "${auth[@]}" "${IARGS[@]}" \
    --install-dir "$dir" --install-service-name "$name" $extra </dev/null
}

enable_start() { # 名字 类型
  local n="$1" k="$2"
  case "$k" in
    systemd) systemctl enable --now "$n" >/dev/null 2>&1 || true ;;
    openrc)
      rc-update add "$n" default >/dev/null 2>&1 || true
      rc-service "$n" start >/dev/null 2>&1 || true ;;
  esac
}

purge_service() { # 名字 类型：只删服务定义，不动目录
  local n="$1" k="$2"
  case "$k" in
    systemd)
      systemctl disable "$n" >/dev/null 2>&1 || true
      rm -f "/etc/systemd/system/$n.service"
      systemctl daemon-reload 2>/dev/null || true ;;
    openrc)
      rc-update del "$n" default >/dev/null 2>&1 || true
      rm -f "/etc/init.d/$n" ;;
  esac
}

remove_index() { # 下标 [force]
  local idx="$1" force="${2:-0}"
  local n="${D_NAME[$idx]}" k="${D_KIND[$idx]}" dir="${D_DIR[$idx]}"
  local go ok_dir=0 j shared=0

  # 目录是否被其它实例共用：单实例装在 /opt/komari，
  # 多开实例在 /opt/komari/natN，删父目录会把别人一起清掉
  for ((j = 0; j < D_COUNT; j++)); do
    [ "$j" -eq "$idx" ] && continue
    case "${D_DIR[$j]}" in
      "$dir"|"$dir"/*) shared=1; break ;;
    esac
  done

  if [ "$force" -eq 0 ]; then
    warn "将停止并删除 $n（$k）"
    dim "目录 $dir"
    if [ "$shared" -eq 1 ]; then
      warn "该目录下还有其它实例，目录会保留，只删这个服务"
      for ((j = 0; j < D_COUNT; j++)); do
        [ "$j" -eq "$idx" ] && continue
        case "${D_DIR[$j]}" in
          "$dir"|"$dir"/*) dim "  · ${D_NAME[$j]}  ${D_DIR[$j]}" ;;
        esac
      done
    fi
    ask "确认? (y/N)" "N" go
    case "$go" in
      [Yy]*) ;;
      *) warn "已跳过"; return 0 ;;
    esac
  fi

  case "$k" in
    systemd)
      systemctl disable --now "$n" >/dev/null 2>&1 || true
      rm -f "/etc/systemd/system/$n.service"
      systemctl daemon-reload ;;
    openrc)
      rc-service "$n" stop >/dev/null 2>&1 || true
      rc-update del "$n" default >/dev/null 2>&1 || true
      rm -f "/etc/init.d/$n" ;;
    proc)
      kill "${n#pid-}" >/dev/null 2>&1 || true ;;
  esac

  case "$dir" in
    /opt/komari*|/opt/ka*) ok_dir=1 ;;
  esac
  if [ "$ok_dir" -eq 0 ] && [ -n "${BASE_DIR:-}" ] && [ "$BASE_DIR" != "/" ]; then
    case "$dir" in
      "$BASE_DIR"|"${BASE_DIR%/}"/*) ok_dir=1 ;;
    esac
  fi

  if [ "$ok_dir" -eq 1 ] && [ "$k" != "proc" ] && [ "$shared" -eq 0 ]; then
    rm -rf "$dir"
    ok "$n 已卸载，目录 $dir 已删除"
  elif [ "$shared" -eq 1 ]; then
    ok "$n 已卸载"
    warn "目录 $dir 仍被其它实例使用，已保留"
  else
    ok "$n 已卸载"
  fi
}

# ==================================================================== 向导 ===
step_endpoint() {
  step_header 2 6 "面板地址"
  dim "填 Komari 面板地址，脚本会顺手探一下连通性"
  local v code
  while :; do
    ask "面板地址" "$ENDPOINT" v
    v="${v%/}"
    case "$v" in
      http://*|https://*) ENDPOINT="$v"; break ;;
      '') warn "面板地址不能为空" ;;
      *)  warn "必须以 http:// 或 https:// 开头" ;;
    esac
  done
  code="$(http_code "$ENDPOINT")"
  if [ "$code" = "000" ]; then
    warn "连不上 $ENDPOINT（网络 / 证书 / 地址有误），仍可继续尝试安装"
  else
    ok "面板可达（HTTP $code）"
  fi
  return 0
}

step_impl() {
  step_header 1 6 "Agent 实现"
  dim "Go 是官方实现最稳；Zig 更省内存，多实例更划算"
  blank
  local -a impls=(
    "Go · 官方版本，稳定，常驻约 18MB"
    "Zig · 轻量省内存，常驻约 1.2MB（多实例推荐）"
  )
  if [ "$AGENT_IMPL" = "zig" ]; then PICK_START=1; else PICK_START=0; fi
  pick "Agent 实现" "第 1/6 步 · 之后也能在高级参数里改" "${impls[@]}" || return 1
  if [ "$PICK_RESULT" -eq 1 ]; then
    AGENT_IMPL="zig"
  else
    AGENT_IMPL="go"
  fi
  return 0
}

token_exists() {
  if [ "${#TOKENS[@]}" -eq 0 ]; then return 1; fi
  local x
  for x in "${TOKENS[@]}"; do
    if [ "$x" = "$1" ]; then return 0; fi
  done
  return 1
}

step_auth() {
  step_header 3 6 "认证方式"
  dim "Token：在面板里逐个添加节点，一个节点一个 token"
  dim "自动发现：一个密钥批量注册，节点自动出现在面板"
  blank
  local -a items=("节点 Token · 逐个添加（推荐）" "自动发现 · 一个密钥批量注册")
  PICK_HINT="↑↓ 移动 · Enter 选择 · q 取消向导"
  pick "认证方式" "第 3/6 步 · 选择后进入下一步" "${items[@]}" || return 1
  if [ "$PICK_RESULT" -eq 1 ]; then
    AUTH_MODE="ad"
  else
    AUTH_MODE="token"
  fi
  return 0
}

step_ad() {
  dim "从面板的自动发现设置里复制密钥；每个实例会各自注册成独立节点"
  blank
  local key
  while :; do
    ask "自动发现密钥" "$AD_KEY" key
    [ -n "$key" ] && break
    warn "密钥不能为空"
  done
  AD_KEY="$key"
  blank
  BATCH_NIC=0
  NIC_MAP=()
  local -a dn=()
  local dx db dm
  while IFS= read -r dx; do [ -n "$dx" ] && dn+=("$dx"); done <<< "$(auto_nics "")"
  if [ "${#dn[@]}" -ge 2 ]; then
    ask "按网卡批量？每个网卡一个实例（可用 ${#dn[@]} 块）(y/N)" "N" db
    case "$db" in
      [Yy]*)
        BATCH_NIC=1
        local ub
        ub="$(used_nics | tr '\n' ' ')"
        if [ -n "${ub// /}" ]; then
          dim "已绑定网卡会自动跳过：$ub"
        fi
        ask_int "网卡分配方式（1=自动 2=手动勾选）" "1" dm 1 2
        if [ "$dm" -eq 1 ]; then
          local pf want avail_n
          dim "可用网卡：$(auto_nics "" | tr '\n' ' ')"
          ask "网卡名过滤（支持通配，如 fip*；空=全部）" "" pf
          avail_n="$(auto_nics "$pf" | wc -l | tr -d ' ')"
          [ -n "$avail_n" ] || avail_n=0
          if [ "$avail_n" -eq 0 ]; then
            warn "没有可用网卡（过滤：${pf:-无}）"
            return 1
          fi
          ask_int "本批安装数量（0=全部 ${avail_n} 块）" "0" want 0 999
          if [ "$want" -gt "$avail_n" ]; then
            warn "可用只有 $avail_n 块，按全部处理"
            want=0
          fi
          auto_pick_nics "$want" "$pf" || { warn "分配网卡失败"; return 1; }
        else
          select_nics_any || return 1
        fi
        INSTANCE_COUNT="${#NIC_MAP[@]}"
        ask_start_index "$(next_free_suffix)" || return 1
        FORCE_SUFFIX=1
        ask "让每个实例上报自己网卡的 IP? (Y/n)" "Y" db
        case "$db" in
          [Nn]*) ;;
          *) GET_IP_NIC=1 ;;
        esac
        ;;
    esac
  fi
  if [ "$BATCH_NIC" -eq 0 ]; then
    ask_int "实例数量" "$INSTANCE_COUNT" INSTANCE_COUNT 1 20
    FORCE_SUFFIX=0
    NAME_START=1
    if [ "$D_COUNT" -gt 0 ]; then
      FORCE_SUFFIX=1
      local n=1
      while service_name_taken "${SVC_PREFIX}-${n}"; do n=$((n + 1)); done
      NAME_START="$n"
    fi
  fi
  MULTI=0
  if [ "$INSTANCE_COUNT" -gt 1 ]; then MULTI=1; fi

  blank
  if [ "$BATCH_NIC" -eq 1 ]; then
    ok "自动发现 · ${INSTANCE_COUNT} 个实例 → ${SVC_PREFIX}-${NAME_START} 起（按网卡）"
    local i
    for ((i = 0; i < INSTANCE_COUNT; i++)); do
      printf '   %s#%s %s → %s%s\n' "$GRAY" "$((i + 1))" "${NIC_MAP[$i]}" "${SVC_PREFIX}-$((NAME_START + i))" "$RESET"
    done
  elif [ "$FORCE_SUFFIX" -eq 1 ]; then
    ok "自动发现 · ${INSTANCE_COUNT} 个实例 → ${SVC_PREFIX}-${NAME_START} 起"
  elif [ "$MULTI" -eq 1 ]; then
    ok "自动发现 · ${INSTANCE_COUNT} 个实例 → ${SVC_PREFIX}-1 … ${SVC_PREFIX}-${INSTANCE_COUNT}"
  else
    ok "自动发现 · 单实例 ${SVC_PREFIX}"
  fi
  return 0
}

step_tokens() {
  step_header 4 6 "节点 Token"
  if [ "$AUTH_MODE" = "ad" ]; then
    step_ad
    return $?
  fi
  dim "从面板「添加节点」复制 token，一行一个；直接回车结束"
  dim "支持一次粘贴多行，会自动拆分；节点数量 = token 数量"
  blank
  TOKENS=()
  local t prompt
  while :; do
    if [ "${#TOKENS[@]}" -eq 0 ]; then
      prompt="节点 1 的 token"
    else
      prompt="节点 $(( ${#TOKENS[@]} + 1 )) 的 token（回车结束）"
    fi
    ask "$prompt" "" t
    [ -z "$t" ] && break
    if token_exists "$t"; then
      warn "这个 token 已经填过了，跳过"
      continue
    fi
    TOKENS+=("$t")
    ok "已添加 #${#TOKENS[@]}  ${GRAY}$(mask "$t")${RESET}"
  done

  if [ "${#TOKENS[@]}" -eq 0 ]; then
    warn "至少要填一个 token"
    return 1
  fi
  INSTANCE_COUNT="${#TOKENS[@]}"
  MULTI=0
  if [ "$INSTANCE_COUNT" -gt 1 ]; then MULTI=1; fi

  BATCH_NIC=0
  NIC_MAP=()
  if [ "$INSTANCE_COUNT" -ge 2 ]; then
    local -a dn=()
    local dx db dm
    while IFS= read -r dx; do [ -n "$dx" ] && dn+=("$dx"); done <<< "$(auto_nics "")"
    if [ "${#dn[@]}" -ge 2 ]; then
      blank
      ask "按网卡分配？每实例只统计一块网卡（可用 ${#dn[@]} 块）(y/N)" "N" db
      case "$db" in
        [Yy]*)
          BATCH_NIC=1
          local ub
          ub="$(used_nics | tr '\n' ' ')"
          if [ -n "${ub// /}" ]; then
            dim "已绑定网卡会自动跳过：$ub"
          fi
          ask_int "网卡分配方式（1=自动 2=手动勾选）" "1" dm 1 2
          if [ "$dm" -eq 1 ]; then
            local pf
            dim "可用网卡：$(auto_nics "" | tr '\n' ' ')"
            ask "网卡名过滤（支持通配，如 fip*；空=全部）" "" pf
            if ! auto_pick_nics "$INSTANCE_COUNT" "$pf"; then
              warn "可用网卡不足 ${INSTANCE_COUNT} 块（过滤：${pf:-无}）"
              return 1
            fi
          else
            select_nics_multi "$INSTANCE_COUNT" || return 1
          fi
          ask_start_index "$(next_free_suffix)" || return 1
          FORCE_SUFFIX=1
          ask "让每个实例上报自己网卡的 IP? (Y/n)" "Y" db
          case "$db" in
            [Nn]*) ;;
            *) GET_IP_NIC=1 ;;
          esac
          ;;
      esac
    fi
  fi

  # 机器上已有实例：新节点从下一个空闲编号开始，绝不覆盖老实例
  if [ "$BATCH_NIC" -eq 0 ]; then
    FORCE_SUFFIX=0
    NAME_START=1
    if [ "$D_COUNT" -gt 0 ]; then
      FORCE_SUFFIX=1
      local n=1
      while service_name_taken "${SVC_PREFIX}-${n}"; do n=$((n + 1)); done
      NAME_START="$n"
    fi
  fi

  # 同一 token 只能对应一个节点，重复会互相顶掉
  local i k
  for ((i = 0; i < INSTANCE_COUNT; i++)); do
    for ((k = 0; k < D_COUNT; k++)); do
      if [ -n "${D_TK[$k]:-}" ] && [ "${D_TK[$k]}" = "${TOKENS[$i]}" ]; then
        warn "token 与已有实例 ${D_NAME[$k]} 相同，会抢同一个节点"
      fi
    done
  done

  blank
  if [ "$BATCH_NIC" -eq 1 ]; then
    ok "共 ${INSTANCE_COUNT} 个节点 → ${SVC_PREFIX}-${NAME_START} … ${SVC_PREFIX}-$((NAME_START + INSTANCE_COUNT - 1))（按网卡）"
    local i
    for ((i = 0; i < INSTANCE_COUNT; i++)); do
      printf '   %s#%s %s → %s%s\n' "$GRAY" "$((i + 1))" "${NIC_MAP[$i]}" "${SVC_PREFIX}-$((NAME_START + i))" "$RESET"
    done
  elif [ "$FORCE_SUFFIX" -eq 1 ] && [ "$INSTANCE_COUNT" -eq 1 ]; then
    ok "共 1 个节点 → ${SVC_PREFIX}-${NAME_START}（不动已有的 ${SVC_PREFIX}）"
  elif [ "$FORCE_SUFFIX" -eq 1 ]; then
    ok "共 ${INSTANCE_COUNT} 个节点 → ${SVC_PREFIX}-${NAME_START} … ${SVC_PREFIX}-$((NAME_START + INSTANCE_COUNT - 1))"
  elif [ "$MULTI" -eq 1 ]; then
    ok "共 ${INSTANCE_COUNT} 个节点 → ${SVC_PREFIX}-1 … ${SVC_PREFIX}-${INSTANCE_COUNT}"
  else
    ok "共 1 个节点 → 单实例 ${SVC_PREFIX}"
  fi
}

adv_run() { # 标题 副标题 绘制函数 编辑函数 项数
  local title="$1" sub="$2" draw="$3" edit="$4" n="$5"
  local sel=0
  hide_cursor
  while :; do
    screen_home
    draw_header "$title" "$sub"
    "$draw" "$sel"
    printf '\n   %s↑↓ 移动 · Enter 修改 · Esc 返回%s\n' "$GRAY" "$RESET"
    if ! read_key; then break; fi
    case "$KEY" in
      UP)   sel=$(((sel + n - 1) % n)) ;;
      DOWN) sel=$(((sel + 1) % n)) ;;
      ESC|QUIT) break ;;
      ENTER|SPACE)
        if ! "$edit" "$sel"; then break; fi ;;
    esac
  done
  show_cursor
  blank
}

ADV_MORE_DRAW="adv_draw2"
ADV_MORE_EDIT="adv_edit2"
ADV_MORE_N=9

adv_draw1() {
  local s="$1"
  cfg_row 0 "$s" "采集间隔"       "${YELL}${INTERVAL}${RESET} 秒"
  cfg_row 1 "$s" "信息上报间隔"   "${YELL}${INFO_INTERVAL}${RESET} 分钟"
  cfg_row 2 "$s" "禁用远程控制"   "$(toggle_render "$DISABLE_WEBSSH")"
  cfg_row 3 "$s" "禁用自动更新"   "$(toggle_render "$DISABLE_AUTOUPDATE")"
  cfg_row 4 "$s" "忽略不安全证书" "$(toggle_render "$INSECURE")"
  cfg_row 5 "$s" "包含缓冲区内存" "$(toggle_render "$MEM_CACHE")"
  cfg_row 6 "$s" "从网卡获取 IP"  "$(toggle_render "$GET_IP_NIC")"
  cfg_row 7 "$s" "详细 GPU 监控"  "$(toggle_render "$GPU_MONITOR")"
  cfg_row 8 "$s" "安装间隔"       "${YELL}${INSTALL_DELAY:-0}${RESET} 秒（0=不等待）"
  cfg_row 9 "$s" "更多设置"       "${GRAY}网络 / 磁盘 / 安装 →${RESET}"
  cfg_row 10 "$s" "完成并继续"    "${GREEN}→${RESET}"
}

adv_edit1() {
  case "$1" in
    0) edit_num "采集间隔（秒）" INTERVAL ;;
    1) edit_int "信息上报间隔（分钟）" INFO_INTERVAL 1 60 ;;
    2) [ "$DISABLE_WEBSSH" -eq 1 ] && DISABLE_WEBSSH=0 || DISABLE_WEBSSH=1 ;;
    3) [ "$DISABLE_AUTOUPDATE" -eq 1 ] && DISABLE_AUTOUPDATE=0 || DISABLE_AUTOUPDATE=1 ;;
    4) [ "$INSECURE" -eq 1 ] && INSECURE=0 || INSECURE=1 ;;
    5) [ "$MEM_CACHE" -eq 1 ] && MEM_CACHE=0 || MEM_CACHE=1 ;;
    6) [ "$GET_IP_NIC" -eq 1 ] && GET_IP_NIC=0 || GET_IP_NIC=1 ;;
    7) [ "$GPU_MONITOR" -eq 1 ] && GPU_MONITOR=0 || GPU_MONITOR=1 ;;
    8) edit_str "安装间隔（秒，可小数，0=不等待）" INSTALL_DELAY
       case "$INSTALL_DELAY" in
         ''|*[!0-9.]*) INSTALL_DELAY="0"; warn "已重置为 0" ;;
       esac ;;
    9) adv_run "更多设置" "网卡 / 挂载点 / 安装项" "$ADV_MORE_DRAW" "$ADV_MORE_EDIT" "$ADV_MORE_N" ;;
    10) return 1 ;;
  esac
  return 0
}

adv_draw2() {
  local s="$1" impl_txt
  if [ "$AGENT_IMPL" = "zig" ]; then
    impl_txt="${GREEN}Zig${RESET}（约 1.2MB）"
  else
    impl_txt="${YELL}Go${RESET}（官方，约 18MB）"
  fi
  cfg_row 0 "$s" "包含网卡"     "${WHITE}${INCLUDE_NICS:-全部}${RESET}"
  cfg_row 1 "$s" "排除网卡"     "${WHITE}${EXCLUDE_NICS:-无}${RESET}"
  cfg_row 2 "$s" "包含挂载点"   "${WHITE}${MOUNT_POINTS:-全部}${RESET}"
  cfg_row 3 "$s" "月重置日"     "${YELL}${MONTH_ROTATE}${RESET}（0=关闭）"
  cfg_row 4 "$s" "安装版本"     "${WHITE}${INSTALL_VERSION:-latest}${RESET}"
  cfg_row 5 "$s" "GitHub 代理"  "${WHITE}${GH_PROXY:-直连}${RESET}"
  cfg_row 6 "$s" "额外参数"     "${WHITE}${EXTRA_AGENT:-无}${RESET}"
  cfg_row 7 "$s" "Agent 实现"   "$impl_txt"
  cfg_row 8 "$s" "返回"         "${GREEN}←${RESET}"
}

multi_nics() {
  local title="$1" sub="$2" var="$3" x
  local -a c=()
  while IFS= read -r x; do [ -n "$x" ] && c+=("$x"); done <<< "$(detect_nics)"
  pick_multi "$title" "$sub" "," "$var" ${c[@]+"${c[@]}"}
}

multi_mounts() {
  local x
  local -a c=()
  while IFS= read -r x; do [ -n "$x" ] && c+=("$x"); done <<< "$(detect_mounts)"
  pick_multi "包含挂载点" "勾选要统计的挂载点；全不选=全部" ";" MOUNT_POINTS ${c[@]+"${c[@]}"}
}

adv_edit2() {
  case "$1" in
    0) multi_nics "包含网卡" "勾选要统计的网卡；全不选=全部" INCLUDE_NICS ;;
    1) multi_nics "排除网卡" "勾选要排除的网卡" EXCLUDE_NICS ;;
    2) multi_mounts ;;
    3) edit_int "月重置日（1-31，0=关闭）" MONTH_ROTATE 0 31
       if [ "$MONTH_ROTATE" != "0" ]; then
         dim "开启后每个实例会额外记录月流量状态，多占一点内存和磁盘"
       fi ;;
    4) edit_str "安装版本（如 1.2.13 / snapshot，空=latest）" INSTALL_VERSION ;;
    5) edit_str "GitHub 代理（如 https://ghproxy.net，空=直连）" GH_PROXY ;;
    6) edit_str "额外参数（原样传给 agent，空=无）" EXTRA_AGENT ;;
    7) if [ "$AGENT_IMPL" = "zig" ]; then AGENT_IMPL="go"; else AGENT_IMPL="zig"; fi ;;
    8) return 1 ;;
  esac
  return 0
}

# 修改已安装实例的参数时用这一屏（没有安装版本/代理）
inst_draw2() {
  local s="$1"
  cfg_row 0 "$s" "包含网卡"     "${WHITE}${INCLUDE_NICS:-全部}${RESET}"
  cfg_row 1 "$s" "排除网卡"     "${WHITE}${EXCLUDE_NICS:-无}${RESET}"
  cfg_row 2 "$s" "包含挂载点"   "${WHITE}${MOUNT_POINTS:-全部}${RESET}"
  cfg_row 3 "$s" "月重置日"     "${YELL}${MONTH_ROTATE}${RESET}（0=关闭）"
  cfg_row 4 "$s" "额外参数"     "${WHITE}${EXTRA_AGENT:-无}${RESET}"
  cfg_row 5 "$s" "返回"         "${GREEN}←${RESET}"
}

inst_edit2() {
  case "$1" in
    0) multi_nics "包含网卡" "勾选要统计的网卡；全不选=全部" INCLUDE_NICS ;;
    1) multi_nics "排除网卡" "勾选要排除的网卡" EXCLUDE_NICS ;;
    2) multi_mounts ;;
    3) edit_int "月重置日（1-31，0=关闭）" MONTH_ROTATE 0 31
       if [ "$MONTH_ROTATE" != "0" ]; then
         dim "开启后每个实例会额外记录月流量状态，多占一点内存和磁盘"
       fi ;;
    4) edit_str "额外参数（原样传给 agent，空=无）" EXTRA_AGENT ;;
    5) return 1 ;;
  esac
  return 0
}

step_advanced() {
  step_header 5 6 "高级参数"
  if [ "$UI_TUI" -eq 0 ]; then
    step_advanced_plain
    return 0
  fi
  adv_run "高级参数" "默认值够用，Esc 或「完成」继续" adv_draw1 adv_edit1 11
}

step_advanced_plain() {
  local ch v
  dim "输入编号修改，直接回车继续（输入 - 清空该项）"
  blank
  printf '   %s1%s   采集间隔        %s 秒\n' "$CYAN" "$RESET" "$INTERVAL"
  printf '   %s2%s   信息上报间隔    %s 分钟\n' "$CYAN" "$RESET" "$INFO_INTERVAL"
  printf '   %s3%s   禁用远程控制    %s\n' "$CYAN" "$RESET" "$(toggle_render "$DISABLE_WEBSSH")"
  printf '   %s4%s   禁用自动更新    %s\n' "$CYAN" "$RESET" "$(toggle_render "$DISABLE_AUTOUPDATE")"
  printf '   %s5%s   忽略不安全证书  %s\n' "$CYAN" "$RESET" "$(toggle_render "$INSECURE")"
  printf '   %s6%s   详细 GPU 监控   %s\n' "$CYAN" "$RESET" "$(toggle_render "$GPU_MONITOR")"
  printf '   %s7%s   包含网卡        %s\n' "$CYAN" "$RESET" "${INCLUDE_NICS:-全部}"
  printf '   %s8%s   排除网卡        %s\n' "$CYAN" "$RESET" "${EXCLUDE_NICS:-无}"
  printf '   %s9%s   包含挂载点      %s\n' "$CYAN" "$RESET" "${MOUNT_POINTS:-全部}"
  printf '   %s10%s  月重置日        %s\n' "$CYAN" "$RESET" "$MONTH_ROTATE"
  printf '   %s11%s  安装版本        %s\n' "$CYAN" "$RESET" "${INSTALL_VERSION:-latest}"
  printf '   %s12%s  GitHub 代理     %s\n' "$CYAN" "$RESET" "${GH_PROXY:-直连}"
  printf '   %s13%s  安装目录        %s\n' "$CYAN" "$RESET" "$BASE_DIR"
  printf '   %s14%s  服务名前缀      %s\n' "$CYAN" "$RESET" "$SVC_PREFIX"
  printf '   %s15%s  额外参数        %s\n' "$CYAN" "$RESET" "${EXTRA_AGENT:-无}"
  printf '   %s16%s  包含缓冲区内存  %s\n' "$CYAN" "$RESET" "$(toggle_render "$MEM_CACHE")"
  printf '   %s17%s  从网卡获取 IP   %s\n' "$CYAN" "$RESET" "$(toggle_render "$GET_IP_NIC")"
  blank
  while :; do
    ask "编号（回车继续）" "" ch
    case "$ch" in
      '') return 0 ;;
      1) ask_num "采集间隔（秒）" "$INTERVAL" INTERVAL ;;
      2) ask_int "信息上报间隔（分钟）" "$INFO_INTERVAL" INFO_INTERVAL 1 60 ;;
      3) [ "$DISABLE_WEBSSH" -eq 1 ] && DISABLE_WEBSSH=0 || DISABLE_WEBSSH=1 ;;
      4) [ "$DISABLE_AUTOUPDATE" -eq 1 ] && DISABLE_AUTOUPDATE=0 || DISABLE_AUTOUPDATE=1 ;;
      5) [ "$INSECURE" -eq 1 ] && INSECURE=0 || INSECURE=1 ;;
      6) [ "$GPU_MONITOR" -eq 1 ] && GPU_MONITOR=0 || GPU_MONITOR=1 ;;
      7) ask "包含网卡" "$INCLUDE_NICS" v; [ "$v" = "-" ] && v=""; INCLUDE_NICS="$v" ;;
      8) ask "排除网卡" "$EXCLUDE_NICS" v; [ "$v" = "-" ] && v=""; EXCLUDE_NICS="$v" ;;
      9) ask "包含挂载点" "$MOUNT_POINTS" v; [ "$v" = "-" ] && v=""; MOUNT_POINTS="$v" ;;
      10) ask_int "月重置日（0-31）" "$MONTH_ROTATE" MONTH_ROTATE 0 31 ;;
      11) ask "安装版本（空=latest）" "$INSTALL_VERSION" v; [ "$v" = "-" ] && v=""; INSTALL_VERSION="$v" ;;
      12) ask "GitHub 代理" "$GH_PROXY" v; [ "$v" = "-" ] && v=""; GH_PROXY="$v" ;;
      13) ask "安装目录" "$BASE_DIR" BASE_DIR ;;
      14) ask "服务名前缀" "$SVC_PREFIX" SVC_PREFIX ;;
      15) ask "额外参数" "$EXTRA_AGENT" v; [ "$v" = "-" ] && v=""; EXTRA_AGENT="$v" ;;
      16) [ "$MEM_CACHE" -eq 1 ] && MEM_CACHE=0 || MEM_CACHE=1 ;;
      17) [ "$GET_IP_NIC" -eq 1 ] && GET_IP_NIC=0 || GET_IP_NIC=1 ;;
      *) warn "没有 $ch 这个编号" ;;
    esac
    ok "已更新"
  done
}

service_name_taken() {
  local name="$1" i
  for ((i = 0; i < D_COUNT; i++)); do
    if [ "${D_NAME[$i]}" = "$name" ]; then return 0; fi
  done
  return 1
}

step_confirm() {
  build_args
  step_header 6 6 "确认部署"

  local clash="" i svc label auth_txt
  for ((i = 1; i <= INSTANCE_COUNT; i++)); do
    svc="$(inst_svc "$i")"
    if service_name_taken "$svc"; then clash+=" $svc"; fi
  done

  if [ "$AUTH_MODE" = "ad" ]; then
    auth_txt="自动发现（$(mask "$AD_KEY")）"
  else
    auth_txt="节点 Token"
  fi

  panel_row "面板地址" "$ENDPOINT"
  panel_row "认证方式" "$auth_txt"
  panel_row "Agent 实现" "$AGENT_IMPL"
  if [ "$BATCH_NIC" -eq 1 ]; then
    panel_row "网卡分配" "每实例一块（共 ${INSTANCE_COUNT} 块）"
  fi
  if [ "$MULTI" -eq 1 ]; then
    panel_row "实例数量" "${INSTANCE_COUNT} 个（多实例）"
  else
    panel_row "实例数量" "1 个（单实例）"
  fi
  panel_row "上报间隔" "${INTERVAL} 秒 / 信息 ${INFO_INTERVAL} 分钟"
  panel_row "远程控制" "$([ "$DISABLE_WEBSSH" -eq 1 ] && printf '已禁用' || printf '开启')"
  panel_row "自动更新" "$([ "$DISABLE_AUTOUPDATE" -eq 1 ] && printf '已禁用' || printf '开启')"
  panel_row "根目录"   "$BASE_DIR"
  if [ "${INSTALL_DELAY:-0}" != "0" ]; then
    panel_row "安装间隔" "${INSTALL_DELAY} 秒（错峰启动）"
  fi
  blank
  for ((i = 1; i <= INSTANCE_COUNT; i++)); do
    if [ "$AUTH_MODE" = "ad" ]; then
      label="自动发现"
    else
      label="$(mask "${TOKENS[$((i - 1))]:-}")"
    fi
    if [ "$BATCH_NIC" -eq 1 ]; then
      label="$label · ${NIC_MAP[$((i - 1))]}"
    fi
    printf '  %s%s%s %s#%s%s %s%s%s %s→ %s%s\n' \
      "$PURP" "$G_BAR" "$RESET" "$GRAY" "$i" "$RESET" \
      "$GRAY" "$label" "$RESET" \
      "$GRAY" "$(inst_dir "$i")" "$RESET"
  done
  blank
  if [ "$BATCH_NIC" -eq 1 ]; then
    dim "通用参数: ${ARGS[*]} --include-nics <每实例不同>"
  else
    dim "参数: ${ARGS[*]}"
  fi
  blank

  local go
  if [ -n "$clash" ]; then
    warn "以下服务已存在，安装会覆盖其配置：$clash"
    ask "输入 y 强制覆盖（回车返回修改）" "" go
    case "$go" in
      [Yy]) ;;
      *) CONFIRM=back; return 0 ;;
    esac
  else
    ask "开始安装?（回车开始 / b 返回修改 / q 取消）" "" go
    case "$go" in
      [Bb]) CONFIRM=back; return 0 ;;
      [Qq]) CONFIRM=cancel; return 0 ;;
    esac
  fi
  CONFIRM=install
}

agent_arch() {
  case "$(uname -m)" in
    x86_64|amd64)        printf 'amd64' ;;
    aarch64|arm64)       printf 'arm64' ;;
    armv7*|armv6*)       printf 'arm' ;;
    i386|i686)           printf '386' ;;
    loongarch64|loong64) printf 'loong64' ;;
    *) return 1 ;;
  esac
}

AGENT_CACHE="${KA_AGENT_CACHE:-/opt/ka/cache/komari-agent}"
AGENT_IMPL="${KA_IMPL:-go}"
AGENT_BIN=""
INSTALL_ERR=""

disk_avail_kb() {
  local p="${1:-/}" line cap i n
  [ -d "$p" ] || p="/"
  line="$(df -k "$p" 2>/dev/null | tail -n 1)"
  [ -n "$line" ] || return 1
  local -a f=()
  read -r -a f <<< "$line"
  n="${#f[@]}"
  cap=0
  for ((i = 0; i < n; i++)); do
    case "${f[$i]}" in
      *%) cap=$((i + 1)); break ;;
    esac
  done
  [ "$cap" -ge 4 ] || return 1
  printf '%s' "${f[$((cap - 2))]}"
}
AGENT_GOGC="${KA_AGENT_GOGC:-50}"
AGENT_MEMLIMIT="${KA_AGENT_MEMLIMIT:-32MiB}"
AGENT_GOMAXPROCS="${KA_AGENT_GOMAXPROCS:-1}"

agent_cache_path() { # 实现 → 缓存文件
  case "${1:-go}" in
    zig) printf '%s-zig' "$AGENT_CACHE" ;;
    *)   printf '%s' "$AGENT_CACHE" ;;
  esac
}

tune_service_env() { # 服务名 类型：给服务注入 Go 运行时内存参数
  local svc="$1" kind="$2" f tmp
  local gogc="$AGENT_GOGC" mem="$AGENT_MEMLIMIT" procs="$AGENT_GOMAXPROCS"
  case "$kind" in
    systemd)
      f="/etc/systemd/system/$svc.service"
      [ -f "$f" ] || return 1
      if grep -q 'GOGC=' "$f"; then return 0; fi
      tmp="$f.tmp.$$"
      awk -v line="Environment=\"GOGC=$gogc\" \"GOMEMLIMIT=$mem\" \"GOMAXPROCS=$procs\"" '
        { print }
        /^\[Service\]$/ && !ins { print line; ins = 1 }
      ' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
      mv -f "$tmp" "$f"
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    openrc)
      f="/etc/init.d/$svc"
      [ -f "$f" ] || return 1
      if grep -q 'GOGC=' "$f"; then return 0; fi
      tmp="$f.tmp.$$"
      {
        head -n 1 "$f"
        printf 'export GOGC=%s\n' "$gogc"
        printf 'export GOMEMLIMIT=%s\n' "$mem"
        printf 'export GOMAXPROCS=%s\n' "$procs"
        tail -n +2 "$f"
      } > "$tmp" || { rm -f "$tmp"; return 1; }
      chmod +x "$tmp"
      mv -f "$tmp" "$f"
      ;;
    *) return 1 ;;
  esac
  return 0
}

prepare_agent_cache() { # [实现] [强制刷新]
  local impl="${1:-$AGENT_IMPL}" force="${2:-0}"
  local arch dir url path ver tmp cache
  arch="$(agent_arch)" || return 1
  cache="$(agent_cache_path "$impl")"
  dir="$(dirname "$cache")"
  mkdir -p "$dir" 2>/dev/null || return 1

  # 已有缓存且不超过 7 天，直接用
  if [ "$force" -eq 0 ] && [ -s "$cache" ] && [ -z "${INSTALL_VERSION:-}" ]; then
    if [ -z "$(find "$cache" -mtime +7 2>/dev/null)" ]; then
      AGENT_BIN="$cache"
      return 0
    fi
  fi

  ver="${INSTALL_VERSION:-latest}"
  if [ "$ver" = "latest" ]; then
    path="latest/download"
  else
    path="download/$ver"
  fi
  case "$impl" in
    zig) url="https://github.com/luodaoyi/komari-zig-agent/releases/$path/komari-agent-linux-$arch" ;;
    *)   url="https://github.com/komari-monitor/komari-agent/releases/$path/komari-agent-linux-$arch" ;;
  esac
  if [ -n "${GH_PROXY:-}" ]; then url="$GH_PROXY/$url"; fi

  tmp="$cache.tmp.$$"
  info "下载 Agent 二进制（$impl，只下一次，后续复用）"
  if ! dl_to "$url" "$tmp" 300 || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 1
  fi
  chmod +x "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$cache"; then
    rm -f "$tmp"
    return 1
  fi
  chmod +x "$cache" 2>/dev/null || true
  AGENT_BIN="$cache"
  return 0
}

install_agent_local() { # 目录 服务名 参数串
  local dir="$1" svc="$2" args="$3" exe="$1/agent" out
  INSTALL_ERR=""
  mkdir -p "$dir" || { INSTALL_ERR="创建目录失败"; return 1; }

  case "$INIT_SYS" in
    openrc)
      rc-service "$svc" stop >/dev/null 2>&1 || true
      rc-update del "$svc" default >/dev/null 2>&1 || true
      rm -f "/etc/init.d/$svc" ;;
    systemd)
      systemctl stop "$svc" >/dev/null 2>&1 || true
      systemctl disable "$svc" >/dev/null 2>&1 || true
      rm -f "/etc/systemd/system/$svc.service"
      systemctl daemon-reload >/dev/null 2>&1 || true ;;
    *) return 1 ;;
  esac

  rm -f "$exe"
  [ -n "$AGENT_BIN" ] || { INSTALL_ERR="没有可用的 Agent 二进制"; return 1; }
  if ! cp -f "$AGENT_BIN" "$exe"; then
    INSTALL_ERR="复制二进制失败（磁盘可能已满）"
    return 1
  fi
  chmod +x "$exe" || { INSTALL_ERR="chmod 失败"; return 1; }

  case "$INIT_SYS" in
    openrc)
      {
        printf '#!/sbin/openrc-run\n'
        printf 'export GOGC=%s\n' "$AGENT_GOGC"
        printf 'export GOMEMLIMIT=%s\n' "$AGENT_MEMLIMIT"
        printf 'export GOMAXPROCS=%s\n\n' "$AGENT_GOMAXPROCS"
        printf 'name="Komari Agent Service"\n'
        printf 'description="Komari monitoring agent"\n'
        printf 'command="%s"\n' "$exe"
        printf 'command_args="%s"\n' "$args"
        printf 'command_user="root"\n'
        printf 'directory="%s"\n' "$dir"
        printf 'pidfile="/run/%s.pid"\n' "$svc"
        printf 'retry="SIGTERM/30"\n'
        printf 'supervisor=supervise-daemon\n\n'
        printf 'depend() {\n\tneed net\n\tafter network\n}\n'
      } > "/etc/init.d/$svc" || return 1
      chmod +x "/etc/init.d/$svc"
      rc-update add "$svc" default >/dev/null 2>&1 || true
      out="$(rc-service "$svc" start 2>&1)"
      if [ $? -ne 0 ]; then
        INSTALL_ERR="服务启动失败：$out"
        return 1
      fi
      ;;
    systemd)
      {
        printf '[Unit]\nDescription=Komari Agent Service\nAfter=network.target\n\n'
        printf '[Service]\nType=simple\n'
        printf 'Environment="GOGC=%s" "GOMEMLIMIT=%s" "GOMAXPROCS=%s"\n' \
          "$AGENT_GOGC" "$AGENT_MEMLIMIT" "$AGENT_GOMAXPROCS"
        printf 'ExecStart=%s %s\n' "$exe" "$args"
        printf 'WorkingDirectory=%s\nRestart=always\nUser=root\n\n' "$dir"
        printf '[Install]\nWantedBy=multi-user.target\n'
      } > "/etc/systemd/system/$svc.service" || return 1
      systemctl daemon-reload >/dev/null 2>&1 || true
      out="$(systemctl enable --now "$svc" 2>&1)"
      if [ $? -ne 0 ]; then
        INSTALL_ERR="服务启动失败：$out"
        return 1
      fi
      ;;
  esac
  return 0
}

do_install() {
  need_root; need_curl
  # 尽量放开进程数上限，批量起服务时 openrc-run 需要 fork
  ulimit -u unlimited 2>/dev/null || ulimit -u 8192 2>/dev/null || true
  # 容器里若 cgroup 可写，顺手把 pids 上限调到 max
  if [ -r /sys/fs/cgroup/pids.max ]; then
    local pm_before pm_after
    pm_before="$(cat /sys/fs/cgroup/pids.max 2>/dev/null)"
    if [ -n "$pm_before" ] && [ "$pm_before" != "max" ] && [ -w /sys/fs/cgroup/pids.max ]; then
      { printf 'max' > /sys/fs/cgroup/pids.max; } 2>/dev/null || true
      pm_after="$(cat /sys/fs/cgroup/pids.max 2>/dev/null)"
      if [ -n "$pm_after" ] && [ "$pm_after" != "$pm_before" ]; then
        ok "容器 pids 上限已从 $pm_before 调到 $pm_after"
      fi
    fi
  fi
  save_conf
  build_args
  install_args
  local tmp="" i token dir svc fails=0 fast=0 args_str consec=0 aborted=0 delay="${INSTALL_DELAY:-0}"
  local -a auth=()

  if prepare_agent_cache "$AGENT_IMPL"; then
    fast=1
    ok "Agent 已缓存（$AGENT_IMPL），${INSTANCE_COUNT} 个实例直接复制，不再重复下载"
    if [ "$INSTANCE_COUNT" -gt 20 ]; then
      if [ "$AGENT_IMPL" = "zig" ]; then
        dim "提示：每个实例复制一份 Agent（约 1MB），共约 $((INSTANCE_COUNT))MB 磁盘"
      else
        dim "提示：每个实例复制一份 Agent（约 11MB），共约 $((INSTANCE_COUNT * 11))MB 磁盘"
      fi
    fi
  elif [ "$AGENT_IMPL" = "zig" ]; then
    die "下载 Zig Agent 失败，检查网络或设置 GH_PROXY"
  else
    tmp="$(mktemp /tmp/ka-install.XXXXXX)" || die "无法创建临时文件"
    info "下载安装脚本…"
    if ! dl_to "$KA_INSTALLER" "$tmp" 120 || [ ! -s "$tmp" ]; then
      rm -f "$tmp"
      die "下载安装脚本失败，检查网络或换用 GitHub 代理"
    fi
    ok "安装脚本已就绪"
  fi

  if [ "$fast" -eq 1 ]; then
    local bsz bkb need avail memavail continue_go
    bsz="$(wc -c < "$AGENT_BIN" 2>/dev/null)"
    [ -n "$bsz" ] || bsz=0
    bkb=$((bsz / 1024))
    need=$((INSTANCE_COUNT * bkb))
    avail="$(disk_avail_kb "$BASE_DIR" 2>/dev/null)"
    [ -n "$avail" ] || avail=0
    if [ "$avail" -gt 0 ] && [ "$need" -gt "$avail" ]; then
      warn "磁盘空间不够：需要约 $((need / 1024)) MB，当前可用 $((avail / 1024)) MB"
      dim "改用 Zig 版（每实例约 1MB）或减少实例数，否则装到一半会失败"
      return 1
    fi
    local nmax pidsmax need_tasks bad=0
    need_tasks=$((INSTANCE_COUNT * 4 + 64))
    nmax="$(ulimit -u 2>/dev/null)"
    if [ -n "$nmax" ] && [ "$nmax" != "unlimited" ] && [ "${nmax:-0}" -gt 0 ] && [ "$need_tasks" -gt "$nmax" ]; then
      warn "进程数上限不够：预计需要约 $need_tasks 个线程，当前 ulimit -u = $nmax"
      bad=1
    fi
    if [ -r /sys/fs/cgroup/pids.max ]; then
      pidsmax="$(cat /sys/fs/cgroup/pids.max 2>/dev/null)"
      if [ -n "$pidsmax" ] && [ "$pidsmax" != "max" ] && [ "${pidsmax:-0}" -gt 0 ] && [ "$need_tasks" -gt "$pidsmax" ]; then
        warn "cgroup 进程数上限不够：pids.max=$pidsmax，预计需要约 $need_tasks 个线程"
        bad=1
      fi
    fi
    if [ "$bad" -eq 1 ]; then
      dim "可以先 ulimit -u unlimited；容器需平台调大 pids 限制；实在不行减少实例数"
      ask "仍然继续? (y/N)" "N" continue_go
      case "$continue_go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac
    fi

    memavail="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
    local per_mb
    case "$AGENT_IMPL" in
      zig) per_mb=2 ;;
      *)   per_mb=18 ;;
    esac
    if [ -n "$memavail" ] && [ $((INSTANCE_COUNT * per_mb * 1024)) -gt "$memavail" ]; then
      local need_mb=$((INSTANCE_COUNT * per_mb))
      warn "内存偏紧：${INSTANCE_COUNT} 个实例按 ${per_mb}MB/个 预留，需要约 ${need_mb}MB，当前可用 $((memavail / 1024))MB"
      if [ "$AGENT_IMPL" = "zig" ]; then
        dim "Zig 实测常驻约 1.2MB/个（251 个约 300MB），预留 2MB 是给上报峰值留余量"
        dim "继续装一般没问题；若被 OOM 杀掉，减少实例数即可"
      fi
      ask "仍然继续? (y/N)" "N" continue_go
      case "$continue_go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac
    fi
  fi

  for ((i = 1; i <= INSTANCE_COUNT; i++)); do
    token="${TOKENS[$((i - 1))]:-}"
    dir="$(inst_dir "$i")"
    svc="$(inst_svc "$i")"
    if [ "$BATCH_NIC" -eq 1 ]; then
      INCLUDE_NICS="${NIC_MAP[$((i - 1))]}"
      build_args
    fi
    auth=()
    if [ "$AUTH_MODE" = "ad" ]; then
      auth=(--auto-discovery "$AD_KEY")
    else
      auth=(-t "$token")
    fi
    progress "$i" "$INSTANCE_COUNT"
    if [ "$AUTH_MODE" = "ad" ]; then
      printf '  %s%s%s %s%s%s  %s自动发现注册%s\n' \
        "$PINK" "$G_BAR" "$RESET" "$B" "$svc" "$RESET" "$GRAY" "$RESET"
    else
      printf '  %s%s%s %s%s%s  %stoken %s%s\n' \
        "$PINK" "$G_BAR" "$RESET" "$B" "$svc" "$RESET" "$GRAY" "$(mask "$token")" "$RESET"
    fi

    if [ "$fast" -eq 1 ]; then
      args_str="$(printf '%s ' "${ARGS[@]}")${auth[*]}"
      args_str="${args_str% }"
      if install_agent_local "$dir" "$svc" "$args_str"; then
        ok "$svc 已安装并启动"
        consec=0
      else
        err "$svc 安装失败${INSTALL_ERR:+：$INSTALL_ERR}"
        fails=$((fails + 1))
        consec=$((consec + 1))
        if [ "$consec" -ge 3 ]; then
          err "连续 $consec 个失败"
          if [ -n "$INSTALL_ERR" ]; then dim "最后一次错误：$INSTALL_ERR"; fi
          local dav mav cont
          dav="$(disk_avail_kb "$BASE_DIR" 2>/dev/null)"
          mav="$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo 2>/dev/null)"
          dim "当前可用：磁盘 ${dav:+$((dav / 1024))MB}${dav:-?} · 内存 ${mav:-?}MB"
          ask "继续安装剩余 $((INSTANCE_COUNT - i)) 个?（y=继续 / N=停止）" "N" cont
          case "$cont" in
            [Yy]*) consec=0 ;;
            *) aborted=1; break ;;
          esac
        fi
      fi
    else
      case "$INIT_SYS" in
        systemd) systemctl stop "$svc" >/dev/null 2>&1 || true ;;
        openrc)  rc-service "$svc" stop >/dev/null 2>&1 || true ;;
      esac
      if sh "$tmp" "${ARGS[@]}" "${IARGS[@]}" "${auth[@]}" \
           --install-dir "$dir" --install-service-name "$svc" </dev/null; then
        case "$INIT_SYS" in
          systemd) systemctl enable --now "$svc" >/dev/null 2>&1 || true ;;
          openrc)  rc-service "$svc" start >/dev/null 2>&1 || true
                   rc-update add "$svc" default >/dev/null 2>&1 || true ;;
        esac
        if tune_service_env "$svc" "$INIT_SYS"; then
          svc_ctl restart "$svc" "$INIT_SYS" >/dev/null 2>&1 || true
        fi
        ok "$svc 已安装并启动"
      else
        err "$svc 安装失败"
        fails=$((fails + 1))
      fi
    fi
    if [ "$delay" != "0" ]; then sleep "$delay"; fi
  done
  if [ -n "$tmp" ]; then rm -f "$tmp"; fi

  local limit="$INSTANCE_COUNT"
  if [ "$aborted" -eq 1 ]; then
    limit=$((i - 1))
    err "已中止：完成 $limit 个，剩余 $((INSTANCE_COUNT - limit)) 个未安装"
  fi

  rule
  blank
  printf '  %s%s 部署结果 %s\n\n' "$B" "▍" "$RESET"
  for ((i = 1; i <= limit; i++)); do
    svc="$(inst_svc "$i")"
    local st_text act col dot
    act="$(svc_state "$svc" "$INIT_SYS")"
    if [ "$act" = "active" ]; then col="$GREEN"; dot="$G_DOT"; st_text="运行中"
    else col="$RED"; dot="$G_DOT_OFF"; st_text="$act"; fi
    printf '  %s%s%s %s %s%s%s\n' "$col" "$dot" "$RESET" "$svc" "$col" "$st_text" "$RESET"
  done
  blank
  if [ "$fails" -eq 0 ]; then
    ok "全部完成，面板里应能看到 ${INSTANCE_COUNT} 个在线节点"
  else
    warn "$fails 个实例失败，去「实例管理 → 查看日志」排查"
  fi
}

reset_install_state() {
  ENDPOINT=""
  BASE_DIR="/opt/komari"
  SVC_PREFIX="komari-agent"
  INTERVAL="1.0"
  INFO_INTERVAL="5"
  DISABLE_WEBSSH=0
  DISABLE_AUTOUPDATE=0
  MEM_CACHE=0
  GET_IP_NIC=0
  INSECURE=0
  GPU_MONITOR=0
  INCLUDE_NICS=""
  EXCLUDE_NICS=""
  MOUNT_POINTS=""
  MONTH_ROTATE="0"
  EXTRA_AGENT=""
  INSTALL_VERSION=""
  GH_PROXY=""
  AGENT_IMPL="go"
  INSTANCE_COUNT=1
  INSTALL_DELAY="${KA_INSTALL_DELAY:-0}"
  MULTI=0
  AUTH_MODE="token"
  AD_KEY=""
  BATCH_NIC=0
  NIC_MAP=()
  FORCE_SUFFIX=0
  NAME_START=1
  TOKENS=()
  ARGS=()
}

cmd_wizard() {
  [ -t 0 ] || die "向导需要交互式终端，请直接登录服务器后运行 ka"
  tui_init
  reset_install_state
  load_conf
  CANCELED=0
  CONFIRM=""
  discover_instances
  detect_init >/dev/null

  # 已有实例的面板地址直接沿用，避免让人重新敲一遍
  local k
  if [ -z "$ENDPOINT" ]; then
    for ((k = 0; k < D_COUNT; k++)); do
      if [ -n "${D_EP[$k]}" ]; then ENDPOINT="${D_EP[$k]}"; break; fi
    done
  fi

  if [ "$UI_TUI" -eq 1 ]; then screen_home; fi
  banner

  if [ "$D_COUNT" -gt 0 ]; then
    panel_row "已有实例" "$D_COUNT 个（$(init_label "$INIT_SYS")）"
    local j
    for ((j = 0; j < D_COUNT; j++)); do
      printf '  %s%s%s %s%s%s  %s%s%s  %s%s%s\n' \
        "$PURP" "$G_BAR" "$RESET" "$WHITE" "${D_NAME[$j]}" "$RESET" \
        "$GRAY" "${D_DIR[$j]}" "$RESET" \
        "$GRAY" "${D_EP[$j]:-—}" "$RESET"
    done
    blank
    warn "新增实例不会改动它们；但若服务名相同会被覆盖"
    if [ -n "$ENDPOINT" ]; then
      dim "面板地址将沿用：$ENDPOINT（下一步直接回车即可）"
    fi
    local go
    ask "继续新增实例? (y/N)" "N" go
    case "$go" in
      [Yy]*) ;;
      *) warn "已取消"; return 0 ;;
    esac
  fi

  step_impl || return 0
  step_endpoint || return 0
  step_auth || return 0
  step_tokens || return 0
  while :; do
    step_advanced
    step_confirm
    case "${CONFIRM:-install}" in
      back)   continue ;;
      cancel) return 0 ;;
    esac
    break
  done
  do_install
}

# ================================================================== 子命令 ===
cmd_status() {
  load_conf
  discover_instances
  detect_init >/dev/null

  if [ "$D_COUNT" -eq 0 ]; then
    warn "没有发现已安装的 komari-agent（$(init_label "$INIT_SYS")）"
    return 0
  fi

  printf '\n  %s%s%s %s实例状态%s %s(%s 个 · %s)%s\n' \
    "$PURP" "$G_BAR" "$RESET" "$B" "$RESET" "$GRAY" "$D_COUNT" "$(init_label "$INIT_SYS")" "$RESET"
  rule 66
  local i act col dot tag note tail_txt
  for ((i = 0; i < D_COUNT; i++)); do
    act="$(svc_state "${D_NAME[$i]}" "${D_KIND[$i]}")"
    case "$act" in
      active)   col="$GREEN"; dot="$G_DOT";     tag="运行中" ;;
      failed)   col="$RED";   dot="$G_ERR";     tag="失败" ;;
      inactive) col="$GRAY";  dot="$G_DOT_OFF"; tag="已停止" ;;
      *)        col="$YELL";  dot="$G_DOT_OFF"; tag="$act" ;;
    esac
    note="$(meta_get "${D_NAME[$i]}")"
    tail_txt="${D_EP[$i]:-—}"
    [ -n "$note" ] && tail_txt="$note · $tail_txt"
    printf '  %s%s%s %s%s%s  %s%s%s  %s%s%s  %s%s%s\n' \
      "$col" "$dot" "$RESET" \
      "$WHITE" "${D_NAME[$i]}" "$RESET" \
      "$CYAN" "${D_TAG[$i]}" "$RESET" \
      "$col" "$tag" "$RESET" \
      "$GRAY" "$tail_txt" "$RESET"
  done
  rule 66
  local conns="未知"
  if command -v ss >/dev/null 2>&1; then
    conns="$(ss -tnp 2>/dev/null | grep -c 'komari')"
  fi
  local mnum mkb
  read -r mnum mkb <<< "$(agent_mem_kb)"
  if [ "${mkb:-0}" -gt 0 ]; then
    printf '  %sAgent 进程 %s 个 · 内存约 %s MB%s\n' \
      "$GRAY" "$mnum" "$(awk "BEGIN{printf \"%.0f\", $mkb/1024}")" "$RESET"
  fi
  printf '  %s共 %s 个 · 面板连接 %s 条 · 受管 %s 个%s\n\n' \
    "$GRAY" "$D_COUNT" "$conns" "$(count_managed)" "$RESET"
}

cmd_doctor() {
  load_conf
  discover_instances
  detect_init >/dev/null
  if [ "$D_COUNT" -eq 0 ]; then
    warn "没有发现实例；先 ka install"
    return 0
  fi
  printf '\n  %s%s%s %s自检%s\n' "$PURP" "$G_BAR" "$RESET" "$B" "$RESET"
  rule 60
  local i act okc=0 code en
  for ((i = 0; i < D_COUNT; i++)); do
    act="$(svc_state "${D_NAME[$i]}" "${D_KIND[$i]}")"
    en="$(svc_enabled "${D_NAME[$i]}" "${D_KIND[$i]}")"
    if [ "$act" = "active" ]; then
      printf '  %s%s%s %s  服务运行中\n' "$GREEN" "$G_OK" "$RESET" "${D_NAME[$i]}"
      okc=$((okc + 1))
    else
      printf '  %s%s%s %s  服务未运行（%s）\n' "$RED" "$G_ERR" "$RESET" "${D_NAME[$i]}" "$act"
    fi
    if [ "$en" = "disabled" ]; then
      printf '  %s%s%s %s  未设置开机自启（重启后不会自动拉起）\n' "$YELL" "$G_WARN" "$RESET" "  "
    fi
    if [ -n "${D_EP[$i]}" ]; then
      code="$(http_code "${D_EP[$i]}")"
      if [ "$code" = "000" ]; then
        printf '  %s%s%s %s  面板连不上 %s\n' "$YELL" "$G_WARN" "$RESET" "  " "${D_EP[$i]}"
      else
        printf '  %s%s%s %s  面板可达 HTTP %s\n' "$GREEN" "$G_OK" "$RESET" "  " "$code"
      fi
    fi
  done
  rule 60
  local mrot=0 gpu_cnt=0 a
  for ((i = 0; i < D_COUNT; i++)); do
    a=" ${D_ARGS[$i]:-} "
    printf '%s' "$a" | grep -Eq -- '--month-rotate[= ]+[1-9]' && mrot=$((mrot + 1))
    printf '%s' "$a" | grep -Eq -- '--gpu([ =]|$)' && gpu_cnt=$((gpu_cnt + 1))
  done
  if [ "$mrot" -gt 0 ] || [ "$gpu_cnt" -gt 0 ]; then
    blank
    if [ "$mrot" -gt 0 ]; then
      dim "$mrot 个实例开启了月流量重置（--month-rotate），会额外占用一点内存和磁盘"
    fi
    if [ "$gpu_cnt" -gt 0 ]; then
      dim "$gpu_cnt 个实例开启了 GPU 监控（--gpu），没有显卡建议关掉"
    fi
  fi
  local pmax pcur
  pmax="$(cat /sys/fs/cgroup/pids.max 2>/dev/null)"
  pcur="$(cat /sys/fs/cgroup/pids.current 2>/dev/null)"
  if [ -n "$pmax" ] || [ -n "$pcur" ]; then
    dim "任务数：${pcur:-?} / ${pmax:-?}（容器 pids 上限；ulimit -u $(ulimit -u 2>/dev/null)）"
  fi
  printf '  %s%d/%d 个实例在运行%s\n\n' "$GRAY" "$okc" "$D_COUNT" "$RESET"
}

state_cn() {  case "$1" in
    active)   printf '运行中' ;;
    inactive) printf '已停止' ;;
    failed)   printf '失败' ;;
    '')       printf '未知' ;;
    *)        printf '%s' "$1" ;;
  esac
}

cmd_instances() {
  load_conf
  while :; do
    discover_instances
    if [ "$D_COUNT" -eq 0 ]; then
      warn "没有发现已安装的 komari-agent"
      return 0
    fi
    local -a items=()
    local i st note line
    for ((i = 0; i < D_COUNT; i++)); do
      st="$(svc_state "${D_NAME[$i]}" "${D_KIND[$i]}")"
      note="$(meta_get "${D_NAME[$i]}")"
      line="${D_NAME[$i]} · ${D_TAG[$i]} · $(state_cn "$st")"
      if [ -n "$note" ]; then line+=" · $note"; fi
      items+=("$line")
    done
    pick "实例管理" "共 ${D_COUNT} 个 · Enter 进入 · q 返回" "${items[@]}" || return 0
    cmd_instance_actions "$PICK_RESULT"
  done
}

cmd_instance_actions() {
  local idx="$1"
  local n="${D_NAME[$idx]}" k="${D_KIND[$idx]}"
  local st st_cn col dot en note title sub action
  st="$(svc_state "$n" "$k")"
  st_cn="$(state_cn "$st")"
  col="$YELL"; dot="$G_DOT_OFF"
  case "$st" in
    active)   col="$GREEN"; dot="$G_DOT" ;;
    inactive) col="$GRAY" ;;
    failed)   col="$RED"; dot="$G_ERR" ;;
  esac
  en="$(svc_enabled "$n" "$k")"
  note="$(meta_get "$n")"
  title="$n  ${col}${dot} ${st_cn}${RESET}"
  sub="类型 $k · 自启 $en"
  if [ -n "$note" ]; then sub+=" · 备注 $note"; fi
  sub+=$'\n'"目录 ${D_DIR[$idx]}"
  sub+=$'\n'"面板 ${D_EP[$idx]:-—}"
  if [ -n "${D_AD[$idx]:-}" ]; then
    sub+=$'\n'"认证 自动发现（$(mask "${D_AD[$idx]}")）"
  else
    sub+=$'\n'"Token $(mask "${D_TK[$idx]:-}")"
  fi

  local -a acts=() labels=()
  if [ "$k" = "proc" ]; then
    acts+=(cmdline); labels+=("查看命令行")
    acts+=(stop);    labels+=("停止进程")
  else
    acts+=(log);     labels+=("查看日志 · 最近 100 行")
    acts+=(restart); labels+=("重启服务")
    if [ "$st" = "active" ]; then
      acts+=(stop);  labels+=("停止服务")
    else
      acts+=(start); labels+=("启动服务")
    fi
    acts+=(params); labels+=("修改参数 · 采集 / 开关 / 网络")
    if [ "${D_TAG[$idx]}" = "受管" ]; then
      acts+=(upgrade); labels+=("升级 Agent · 沿用现有参数")
    fi
  fi
  if [ "${D_TAG[$idx]}" != "受管" ] || [ "$k" = "proc" ]; then
    acts+=(adopt); labels+=("接管为 ka 管理 · 保留 token")
  fi
  acts+=(note);      labels+=("设置备注 · 地区 / 用途")
  acts+=(sep);       labels+=("──")
  acts+=(uninstall); labels+=("${RED}卸载${RESET}")

  pick "$title" "$sub" "${labels[@]}" || return 0
  action="${acts[$PICK_RESULT]}"

  case "$action" in
    cmdline)
      printf '\n  %s\n\n' "$(tr '\0' ' ' < "/proc/${n#pid-}/cmdline" 2>/dev/null)"
      pause_any ;;
    log)
      printf '\n'
      if ! svc_logs "$n" "$k" 100; then warn "没有可读日志"; fi
      pause_any ;;
    restart)
      if svc_ctl restart "$n" "$k"; then ok "已重启 $n"; else warn "重启失败"; fi
      sleep 1 ;;
    stop)
      if svc_ctl stop "$n" "$k"; then ok "已停止 $n"; else warn "停止失败"; fi
      sleep 1 ;;
    start)
      if svc_ctl start "$n" "$k"; then ok "已启动 $n"; else warn "启动失败"; fi
      sleep 1 ;;
    params)  cmd_edit_params "$idx" ;;
    upgrade) cmd_upgrade "$n" ;;
    adopt)   cmd_adopt "$n" ;;
    note)    cmd_note "$n" ;;
    uninstall) remove_index "$idx" ;;
  esac
}

cmd_note() {
  load_conf
  discover_instances
  if [ "$D_COUNT" -eq 0 ]; then warn "没有发现实例"; return 0; fi
  local idx
  if [ $# -ge 1 ] && [ -n "$1" ]; then
    idx="$(find_idx "$1")" || { warn "找不到实例 $1"; return 1; }
    if [ $# -ge 2 ]; then
      meta_set "$1" "$2" && ok "备注已保存"
      return 0
    fi
  else
    local -a items=()
    local i
    for ((i = 0; i < D_COUNT; i++)); do
      items+=("${D_NAME[$i]} · $(meta_get "${D_NAME[$i]}")")
    done
    pick "设置备注" "地区 / 用途，留空清除" "${items[@]}" || return 0
    idx="$PICK_RESULT"
  fi
  local name="${D_NAME[$idx]}" old note def
  old="$(meta_get "$name")"
  def="$old"
  if [ -z "$old" ] && [ "${KA_NO_GEO:-0}" != "1" ]; then
    info "识别出口 IP 归属地…"
    geo_note
    if [ -n "$GEO_RESULT" ]; then
      dim "公网 IP ${GEO_IP} → ${GEO_RESULT}"
      def="$GEO_RESULT"
    else
      warn "识别失败（网络受限？），手动填写即可"
    fi
  fi
  ask "备注（地区 / 用途，输入 - 清空）" "$def" note
  if [ "$note" = "-" ]; then note=""; fi
  meta_set "$name" "$note" && ok "$name 备注 → ${note:-（空）}"
}

reset_settings() {
  INTERVAL="1.0"
  INFO_INTERVAL="5"
  DISABLE_WEBSSH=0
  DISABLE_AUTOUPDATE=0
  MEM_CACHE=0
  GET_IP_NIC=0
  INSECURE=0
  GPU_MONITOR=0
  INCLUDE_NICS=""
  EXCLUDE_NICS=""
  MOUNT_POINTS=""
  MONTH_ROTATE="0"
  EXTRA_AGENT=""
}

load_settings_from_args() {
  reset_settings
  local -a av=($1)
  local i a
  for ((i = 0; i < ${#av[@]}; i++)); do
    a="${av[$i]}"
    case "$a" in
      -e|--endpoint|-t|--token) i=$((i + 1)) ;;
      --auto-discovery)         i=$((i + 1)) ;;
      -i|--interval)            INTERVAL="${av[$((i + 1))]:-1.0}"; i=$((i + 1)) ;;
      --info-report-interval)   INFO_INTERVAL="${av[$((i + 1))]:-5}"; i=$((i + 1)) ;;
      --include-nics)           INCLUDE_NICS="${av[$((i + 1))]:-}"; i=$((i + 1)) ;;
      --exclude-nics)           EXCLUDE_NICS="${av[$((i + 1))]:-}"; i=$((i + 1)) ;;
      --include-mountpoint)     MOUNT_POINTS="${av[$((i + 1))]:-}"; i=$((i + 1)) ;;
      --month-rotate)           MONTH_ROTATE="${av[$((i + 1))]:-0}"; i=$((i + 1)) ;;
      --disable-web-ssh)        DISABLE_WEBSSH=1 ;;
      --disable-auto-update)    DISABLE_AUTOUPDATE=1 ;;
      -u|--ignore-unsafe-cert)  INSECURE=1 ;;
      --gpu)                    GPU_MONITOR=1 ;;
      --memory-include-cache)   MEM_CACHE=1 ;;
      --get-ip-addr-from-nic)   GET_IP_NIC=1 ;;
      --memory-mode-available)  : ;;
      *) EXTRA_AGENT="${EXTRA_AGENT:+$EXTRA_AGENT }$a" ;;
    esac
  done
}

cmd_edit_params() {
  local idx="$1"
  local n="${D_NAME[$idx]}" dir="${D_DIR[$idx]}"
  local k="${D_KIND[$idx]}" ep="${D_EP[$idx]:-}" tk="${D_TK[$idx]:-}" ad="${D_AD[$idx]:-}"
  if [ -z "$tk" ] && [ -z "$ad" ]; then
    warn "解析不到 $n 的 token / 自动发现密钥，无法修改参数"
    return 1
  fi
  if [ -z "$ep" ]; then
    warn "解析不到 $n 的面板地址，无法修改参数"
    return 1
  fi

  load_settings_from_args "${D_ARGS[$idx]:-}"
  ENDPOINT="$ep"

  ADV_MORE_DRAW="inst_draw2"
  ADV_MORE_EDIT="inst_edit2"
  ADV_MORE_N=6
  if [ "$UI_TUI" -eq 1 ]; then
    adv_run "修改参数" "$n · Esc 取消" adv_draw1 adv_edit1 11
  else
    step_advanced_plain
  fi
  ADV_MORE_DRAW="adv_draw2"
  ADV_MORE_EDIT="adv_edit2"
  ADV_MORE_N=9

  build_args
  blank
  panel_row "服务" "$n"
  panel_row "目录" "$dir"
  dim "新参数: ${ARGS[*]}"
  blank
  local go
  ask "应用并重启服务? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac

  if [ "$AGENT_IMPL" != "zig" ]; then
    fetch_installer || die "下载安装脚本失败"
  fi
  info "应用新参数到 $n"
  if params_apply "$idx"; then
    ok "$n 参数已更新并重启"
    return 0
  fi
  err "更新失败"
  return 1
}

cache_total_kb() {
  local f total=0 sz
  for f in "$AGENT_CACHE" "$AGENT_CACHE-zig"; do
    [ -f "$f" ] || continue
    sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
    total=$((total + ${sz:-0}))
  done
  printf '%s' "$total"
}

cmd_cache_clean() {
  need_root
  local -a files=()
  local f sz total=0
  for f in "$AGENT_CACHE" "$AGENT_CACHE-zig" /tmp/ka-install.* /tmp/ka-update.*; do
    [ -f "$f" ] || continue
    files+=("$f")
    sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
    total=$((total + ${sz:-0}))
  done
  if [ "${#files[@]}" -eq 0 ]; then
    ok "没有需要清理的下载文件"
    return 0
  fi

  printf '\n  %s%s%s %s下载文件%s\n' "$PURP" "$G_BAR" "$RESET" "$B" "$RESET"
  rule 56
  for f in "${files[@]}"; do
    sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
    printf '  %s  %s%s%s\n' "$(human_size "${sz:-0}")" "$GRAY" "$f" "$RESET"
  done
  rule 56
  blank
  warn "共 $(human_size "$total")，删除后下次安装会重新下载"
  local go
  ask "确认清理? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac
  for f in "${files[@]}"; do rm -f "$f" 2>/dev/null; done
  ok "已清理下载文件"
}

cmd_cleanup() {
  local ck ct
  ck="$(cache_total_kb)"
  ct="无"
  if [ "${ck:-0}" -gt 0 ]; then ct="$(human_size "$ck")"; fi
  local -a items=(
    "卸载实例 · 全部，或勾选多个"
    "清理下载缓存 · 当前 ${ct}"
    "卸载 ka 自身 · 保留实例"
    "全部清理 · 实例 + 缓存 + ka"
    "返回"
  )
  pick "卸载 / 清理" "只是范围不同，下面都不可恢复" "${items[@]}" || return 0
  case "$PICK_RESULT" in
    0) cmd_uninstall ;;
    1) cmd_cache_clean ;;
    2) cmd_self_uninstall ;;
    3) cmd_cleanup_all ;;
  esac
}

self_remove_files() {
  rm -f /usr/local/bin/ka 2>/dev/null
  rm -f "$KA_CONF" 2>/dev/null
  rm -f "$META_FILE" 2>/dev/null
  rm -f "$AGENT_CACHE" "$AGENT_CACHE-zig" 2>/dev/null
  rm -f /tmp/ka-install.* /tmp/ka-update.* 2>/dev/null
  case "$KA_DIR" in
    /opt/ka|/opt/ka/*) rm -rf "$KA_DIR" ;;
    *)
      rm -f "$KA_DIR"/ka "$KA_DIR"/ka.sh 2>/dev/null
      rm -f "$KA_DIR"/ka-v*.sh 2>/dev/null
      ;;
  esac
}

cmd_self_uninstall() {
  need_root
  warn "将删除 ka 自身：$KA_SELF"
  dim "同时清理 /usr/local/bin/ka、$KA_CONF、$META_FILE"
  dim "不会动任何 komari-agent 实例"
  local go
  ask "确认? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac
  self_remove_files
  ok "ka 已卸载；实例仍在运行，可随时用面板重新接管"
}

cmd_cleanup_all() {
  need_root
  load_conf
  warn "将卸载全部实例、清空下载缓存、删除 ka 自身"
  dim "此操作不可恢复"
  local go
  ask "输入 yes 确认全部清理（直接回车取消）" "" go
  [ "$go" = "yes" ] || { warn "已取消"; return 0; }
  discover_instances
  local i
  for ((i = 0; i < D_COUNT; i++)); do
    remove_index "$i" 1
  done
  rm -f "$AGENT_CACHE" "$AGENT_CACHE-zig" /tmp/ka-install.* /tmp/ka-update.* 2>/dev/null
  self_remove_files
  ok "已全部清理，退出"
  exit 0
}

upgrade_apply() { # 下标：原地升级一个实例
  local idx="$1"
  local n="${D_NAME[$idx]}" k="${D_KIND[$idx]}" dir="${D_DIR[$idx]}"
  local ep="${D_EP[$idx]:-}" tk="${D_TK[$idx]:-}" ad="${D_AD[$idx]:-}" extra
  if [ -z "$tk" ] && [ -z "$ad" ]; then
    warn "$n 缺少 token / 自动发现密钥，跳过"
    return 1
  fi
  extra="$(filter_args "${D_ARGS[$idx]:-}")"
  svc_ctl stop "$n" "$k" || true
  if reinstall_service "$dir" "$n" "$ep" "$tk" "$extra" "$ad"; then
    enable_start "$n" "$k"
    if tune_service_env "$n" "$k"; then
      svc_ctl restart "$n" "$k" >/dev/null 2>&1 || true
    fi
    ok "$n 已升级"
    return 0
  fi
  warn "$n 升级失败，尝试恢复"
  svc_ctl start "$n" "$k" || true
  return 1
}

params_apply() { # 下标：把当前全局参数套用到该实例
  local idx="$1"
  local n="${D_NAME[$idx]}" k="${D_KIND[$idx]}" dir="${D_DIR[$idx]}"
  local ep="${D_EP[$idx]:-}" tk="${D_TK[$idx]:-}" ad="${D_AD[$idx]:-}"
  local -a auth=()
  if [ -n "$ad" ]; then
    auth=(--auto-discovery "$ad")
  elif [ -n "$tk" ]; then
    auth=(-t "$tk")
  else
    warn "$n 缺少 token / 自动发现密钥，跳过"
    return 1
  fi
  ENDPOINT="$ep"
  build_args
  svc_ctl stop "$n" "$k" || true

  if [ "$AGENT_IMPL" = "zig" ]; then
    if ! prepare_agent_cache zig 0; then
      warn "下载 Zig Agent 失败"
      svc_ctl start "$n" "$k" || true
      return 1
    fi
    local args_str
    args_str="$(printf '%s ' "${ARGS[@]}")"
    args_str="${args_str% }"
    if install_agent_local "$dir" "$n" "$args_str"; then
      enable_start "$n" "$k"
      tune_service_env "$n" "$k" >/dev/null 2>&1 || true
      svc_ctl restart "$n" "$k" >/dev/null 2>&1 || true
      ok "$n 参数已更新"
      return 0
    fi
    warn "$n 更新失败，尝试恢复"
    svc_ctl start "$n" "$k" || true
    return 1
  fi

  if sh "$KA_TMP" "${ARGS[@]}" "${auth[@]}" \
       --install-dir "$dir" --install-service-name "$n" </dev/null; then
    enable_start "$n" "$k"
    if tune_service_env "$n" "$k"; then
      svc_ctl restart "$n" "$k" >/dev/null 2>&1 || true
    fi
    ok "$n 参数已更新"
    return 0
  fi
  warn "$n 更新失败，尝试恢复"
  svc_ctl start "$n" "$k" || true
  return 1
}

switch_impl_idx() { # 下标 目标实现
  local idx="$1" impl="$2"
  local n="${D_NAME[$idx]}" k="${D_KIND[$idx]}" dir="${D_DIR[$idx]}"
  local raw="${D_ARGS[$idx]:-}" bak="${D_DIR[$idx]}/agent.ka-bak"
  if [ -z "$raw" ]; then
    warn "$n 解析不到启动参数，跳过"
    return 1
  fi
  cp -f "$dir/agent" "$bak" 2>/dev/null || true
  if install_agent_local "$dir" "$n" "$raw" && [ "$(svc_state "$n" "$k")" = "active" ]; then
    rm -f "$bak"
    ok "$n 已切换到 $impl"
    return 0
  fi
  if [ -f "$bak" ]; then
    cp -f "$bak" "$dir/agent" 2>/dev/null && chmod +x "$dir/agent" 2>/dev/null
    rm -f "$bak"
    svc_ctl restart "$n" "$k" >/dev/null 2>&1 || true
  fi
  warn "$n 切换失败，已回滚"
  return 1
}

cmd_batch() {
  need_root
  load_conf
  discover_instances
  local -a SVC=()
  local i
  for ((i = 0; i < D_COUNT; i++)); do
    [ "${D_KIND[$i]}" = "proc" ] && continue
    SVC+=("$i")
  done
  if [ "${#SVC[@]}" -eq 0 ]; then
    warn "没有可批量操作的服务实例"
    return 0
  fi

  local -a actions=("重启服务" "停止服务" "启动服务" "──" "升级 Agent" "修改参数" "内存调优" "切换 Agent 实现" "──" "卸载实例")
  pick "批量操作" "共 ${#SVC[@]} 个服务实例" "${actions[@]}" || return 0

  local act
  case "$PICK_RESULT" in
    0) act="restart" ;;
    1) act="stop" ;;
    2) act="start" ;;
    4) act="upgrade" ;;
    5) act="params" ;;
    6) act="memtune" ;;
    7) act="switch" ;;
    9) act="remove" ;;
    *) return 0 ;;
  esac
  local act_cn
  case "$act" in
    restart) act_cn="重启" ;;
    stop)    act_cn="停止" ;;
    start)   act_cn="启动" ;;
    upgrade) act_cn="升级" ;;
    params)  act_cn="修改参数" ;;
    memtune) act_cn="内存调优" ;;
    switch)  act_cn="切换实现" ;;
    *)       act_cn="卸载" ;;
  esac

  local switch_impl=""
  if [ "$act" = "switch" ]; then
    local -a impls=("Zig · 常驻约 1.2MB（省内存）" "Go · 官方，约 18MB")
    pick "切换实现" "选择目标 Agent 实现" "${impls[@]}" || return 0
    if [ "$PICK_RESULT" -eq 0 ]; then switch_impl="zig"; else switch_impl="go"; fi
    act_cn="切换到 $switch_impl"
  fi

  local -a scope_items=("全部（${#SVC[@]} 个）" "手动勾选")
  pick "执行范围" "对哪些实例执行「${act_cn}」" "${scope_items[@]}" || return 0

  local -a targets=()
  if [ "$PICK_RESULT" -eq 0 ]; then
    targets=("${SVC[@]}")
  else
    local -a names=()
    for i in "${SVC[@]}"; do names+=("${D_NAME[$i]}"); done
    local picked_names=""
    MULTI_NO_MANUAL=1
    if ! pick_multi "选择实例" "勾选要${act_cn}的实例" "," picked_names "${names[@]}"; then
      MULTI_NO_MANUAL=0
      return 0
    fi
    MULTI_NO_MANUAL=0
    if [ -z "$picked_names" ]; then
      warn "没有勾选任何实例"
      return 0
    fi
    local IFS_OLD="$IFS"
    local -a picked=()
    IFS=',' read -r -a picked <<< "$picked_names"
    IFS="$IFS_OLD"
    local pn
    for pn in "${picked[@]}"; do
      for i in "${SVC[@]}"; do
        if [ "${D_NAME[$i]}" = "$pn" ]; then targets+=("$i"); fi
      done
    done
  fi
  if [ "${#targets[@]}" -eq 0 ]; then
    warn "没有选中实例"
    return 0
  fi

  # 批量改参数：先编辑一次，再套用到每个选中实例
  if [ "$act" = "params" ]; then
    local first="${targets[0]}"
    load_settings_from_args "${D_ARGS[$first]:-}"
    ENDPOINT="${D_EP[$first]:-}"
    ADV_MORE_DRAW="inst_draw2"
    ADV_MORE_EDIT="inst_edit2"
    ADV_MORE_N=6
    if [ "$UI_TUI" -eq 1 ]; then
      adv_run "批量修改参数" "编辑一次，套用到 ${#targets[@]} 个实例" adv_draw1 adv_edit1 11
    else
      step_advanced_plain
    fi
    ADV_MORE_DRAW="adv_draw2"
    ADV_MORE_EDIT="adv_edit2"
    ADV_MORE_N=9
  fi

  blank
  if [ "$act" = "remove" ]; then
    warn "将卸载 ${#targets[@]} 个实例（停服务并删除目录）"
  else
    warn "将对 ${#targets[@]} 个实例执行：$act_cn"
  fi
  for i in "${targets[@]}"; do
    dim "  · ${D_NAME[$i]}"
  done
  local go
  ask "确认? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac

  if [ "$act" = "upgrade" ] || [ "$act" = "params" ]; then
    fetch_installer || die "下载安装脚本失败"
  fi
  if [ "$act" = "switch" ]; then
    prepare_agent_cache "$switch_impl" 1 || die "下载 $switch_impl 版本失败"
  fi

  local okc=0
  for i in "${targets[@]}"; do
    case "$act" in
      restart|stop|start)
        if svc_ctl "$act" "${D_NAME[$i]}" "${D_KIND[$i]}"; then
          ok "${D_NAME[$i]} $act_cn"
          okc=$((okc + 1))
        else
          warn "${D_NAME[$i]} $act_cn 失败"
        fi ;;
      upgrade)
        if upgrade_apply "$i"; then okc=$((okc + 1)); fi ;;
      params)
        if params_apply "$i"; then okc=$((okc + 1)); fi ;;
      memtune)
        if tune_service_env "${D_NAME[$i]}" "${D_KIND[$i]}"; then
          svc_ctl restart "${D_NAME[$i]}" "${D_KIND[$i]}" >/dev/null 2>&1 || true
          ok "${D_NAME[$i]} 已应用内存参数"
          okc=$((okc + 1))
        else
          warn "${D_NAME[$i]} 应用内存参数失败"
        fi ;;
      switch)
        if switch_impl_idx "$i" "$switch_impl"; then okc=$((okc + 1)); fi ;;
      remove)
        remove_index "$i" 1
        okc=$((okc + 1)) ;;
    esac
  done
  if [ "$act" = "switch" ] && [ "$okc" -gt 0 ]; then
    AGENT_IMPL="$switch_impl"
    save_conf
  fi
  blank
  printf '  %s%d/%d 成功%s\n\n' "$GRAY" "$okc" "${#targets[@]}" "$RESET"
}

cmd_adopt() {
  need_root
  load_conf
  discover_instances
  detect_init >/dev/null
  if [ "$D_COUNT" -eq 0 ]; then warn "没有发现实例"; return 0; fi

  local idx
  if [ $# -ge 1 ] && [ -n "$1" ]; then
    idx="$(find_idx "$1")" || { warn "找不到实例 $1"; return 1; }
  else
    local -a items=()
    local i
    for ((i = 0; i < D_COUNT; i++)); do
      items+=("${D_NAME[$i]} · ${D_TAG[$i]} · $(svc_state "${D_NAME[$i]}" "${D_KIND[$i]}")")
    done
    pick "接管实例" "把外部 / 进程实例重装成 ka 管理的服务" "${items[@]}" || return 0
    idx="$PICK_RESULT"
  fi

  local on="${D_NAME[$idx]}" ok="${D_KIND[$idx]}" odir="${D_DIR[$idx]}"
  local ep="${D_EP[$idx]:-}" tk="${D_TK[$idx]:-}" ad="${D_AD[$idx]:-}" raw="${D_ARGS[$idx]:-}"

  if [ -z "$tk" ] && [ -z "$ad" ]; then
    warn "解析不到 $on 的 token / 自动发现密钥，无法自动接管"
    dim "可到面板复制该节点 token 后手动重装"
    return 1
  fi

  local nn nd n=1
  if [ "$on" = "$SVC_PREFIX" ]; then
    nn="$SVC_PREFIX"; nd="$odir"
  elif ! service_name_taken "$SVC_PREFIX"; then
    nn="$SVC_PREFIX"; nd="$BASE_DIR"
  else
    while [ "$n" -lt 100 ] && service_name_taken "${SVC_PREFIX}-${n}"; do
      n=$((n + 1))
    done
    nn="${SVC_PREFIX}-${n}"; nd="$BASE_DIR/nat$n"
  fi

  local extra
  extra="$(filter_args "$raw")"

  blank
  printf '  %s%s%s %s接管计划%s\n' "$PURP" "$G_BAR" "$RESET" "$B" "$RESET"
  panel_row "旧服务" "$on（$ok）"
  panel_row "新服务" "$nn"
  panel_row "新目录" "$nd"
  panel_row "面板" "${ep:-—}"
  if [ -n "$ad" ]; then
    panel_row "认证" "自动发现（$(mask "$ad")）"
  else
    panel_row "Token" "$(mask "$tk")"
  fi
  if [ -n "$extra" ]; then panel_row "保留参数" "$extra"; fi
  blank
  warn "先停旧服务再重装，期间约 10 秒离线"
  local go
  ask "确认接管? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac

  fetch_installer || die "下载安装脚本失败"

  info "停止旧服务 $on"
  svc_ctl stop "$on" "$ok" || true

  if reinstall_service "$nd" "$nn" "$ep" "$tk" "$extra" "$ad"; then
    enable_start "$nn" "$INIT_SYS"
    if [ "$on" != "$nn" ]; then
      purge_service "$on" "$ok"
      ok "旧服务 $on 已移除"
      if [ "$odir" != "$nd" ]; then
        dim "旧目录 $odir 保留未删"
      fi
    fi
    ok "接管完成 → $nn"
  else
    err "接管失败，正在回滚"
    svc_ctl start "$on" "$ok" || true
    return 1
  fi
}

cmd_upgrade() {
  need_root
  load_conf
  discover_instances
  detect_init >/dev/null
  if [ "$D_COUNT" -eq 0 ]; then warn "没有发现实例"; return 0; fi

  local -a cand=()
  local i
  if [ $# -ge 1 ] && [ -n "$1" ] && [ "$1" != "all" ]; then
    local one
    one="$(find_idx "$1")" || { warn "找不到实例 $1"; return 1; }
    cand=("$one")
  else
    for ((i = 0; i < D_COUNT; i++)); do cand+=("$i"); done
  fi

  local -a todo=()
  for i in "${cand[@]}"; do
    if [ "${D_TAG[$i]}" != "受管" ]; then
      warn "${D_NAME[$i]} 是外部实例，先「接管」再升级"
      continue
    fi
    if [ -z "${D_TK[$i]:-}" ] && [ -z "${D_AD[$i]:-}" ]; then
      warn "${D_NAME[$i]} 缺少 token / 自动发现密钥，跳过"
      continue
    fi
    if [ -z "${D_EP[$i]:-}" ]; then
      warn "${D_NAME[$i]} 缺少面板地址，跳过"
      continue
    fi
    todo+=("$i")
  done
  if [ "${#todo[@]}" -eq 0 ]; then return 0; fi

  blank
  for i in "${todo[@]}"; do
    printf '  %s%s%s %s\n' "$GRAY" "$G_ARROW" "$RESET" "${D_NAME[$i]}"
  done
  local go
  ask "升级以上 ${#todo[@]} 个实例? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac

  fetch_installer || die "下载安装脚本失败"
  local okc=0
  for i in "${todo[@]}"; do
    local n="${D_NAME[$i]}" k="${D_KIND[$i]}" dir="${D_DIR[$i]}"
    local ep="${D_EP[$i]}" tk="${D_TK[$i]:-}" ad="${D_AD[$i]:-}" extra
    extra="$(filter_args "${D_ARGS[$i]:-}")"
    info "升级 $n"
    svc_ctl stop "$n" "$k" || true
    if reinstall_service "$dir" "$n" "$ep" "$tk" "$extra" "$ad"; then
      enable_start "$n" "$k"
      ok "$n 已升级"
      okc=$((okc + 1))
    else
      err "$n 升级失败，尝试恢复"
      svc_ctl start "$n" "$k" || true
    fi
  done
  blank
  printf '  %s%d/%d 成功%s\n\n' "$GRAY" "$okc" "${#todo[@]}" "$RESET"
}

LOG_CLEAN_KEEP="${LOG_CLEAN_KEEP:-2000}"

human_size() {
  local b="${1:-0}"
  if [ "$b" -ge 1048576 ]; then
    awk "BEGIN{printf \"%.1f MB\", $b/1048576}"
  elif [ "$b" -ge 1024 ]; then
    awk "BEGIN{printf \"%.0f KB\", $b/1024}"
  else
    printf '%s B' "$b"
  fi
}

log_cron_path() {
  if [ -d /etc/periodic/daily ]; then
    printf '%s' /etc/periodic/daily/ka-logclean
  elif [ -d /etc/cron.daily ]; then
    printf '%s' /etc/cron.daily/ka-logclean
  fi
}

trim_log_file() { # 文件 [保留行数]
  local f="$1" n="${2:-$LOG_CLEAN_KEEP}" tmp sz
  [ -f "$f" ] || return 0
  sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
  [ "${sz:-0}" -lt 1048576 ] && return 0
  tmp="$f.tmp.$$"
  if tail -n "$n" "$f" > "$tmp" 2>/dev/null; then
    chmod 640 "$tmp" 2>/dev/null || true
    if mv -f "$tmp" "$f" 2>/dev/null; then
      return 0
    fi
  fi
  rm -f "$tmp"
  return 1
}

rotate_messages() {
  local f=/var/log/messages
  [ -f "$f" ] || return 0
  cp -f "$f" "$f.1" 2>/dev/null || return 1
  : > "$f" 2>/dev/null || return 1
  if command -v pidof >/dev/null 2>&1; then
    local p
    p="$(pidof syslogd 2>/dev/null || true)"
    [ -n "$p" ] && kill -HUP $p 2>/dev/null || true
  fi
  return 0
}

install_log_cron() {
  local p ka_bin
  p="$(log_cron_path)"
  if [ -z "$p" ]; then
    warn "没有找到每日任务目录（/etc/periodic/daily 或 /etc/cron.daily）"
    return 1
  fi
  ka_bin="/usr/local/bin/ka"
  [ -x "$ka_bin" ] || ka_bin="/opt/ka/ka"
  {
    printf '#!/bin/sh\n'
    printf '# 由 ka 生成的日志清理任务\n'
    printf '[ -x "%s" ] && "%s" logs clean --quiet >/dev/null 2>&1\n' "$ka_bin" "$ka_bin"
  } > "$p" || { warn "写入 $p 失败"; return 1; }
  chmod +x "$p"
  ok "已开启每日自动清理：$p"
}

remove_log_cron() {
  local p
  p="$(log_cron_path)"
  if [ -n "$p" ] && [ -f "$p" ]; then
    rm -f "$p"
    ok "已关闭每日自动清理"
  else
    warn "当前没有开启自动清理"
  fi
}

cmd_logs_clean() {
  need_root
  local mode="${1:-ask}"
  case "$mode" in
    --auto) install_log_cron; return $? ;;
    --off)  remove_log_cron; return $? ;;
    --quiet)
      local qf
      for qf in /var/log/komari*.log /var/log/ka-*.log; do
        [ -f "$qf" ] && trim_log_file "$qf"
      done
      return 0 ;;
  esac

  local -a files=()
  local f sz
  for f in /var/log/komari*.log /var/log/ka-*.log; do
    [ -f "$f" ] && files+=("$f")
  done

  printf '\n  %s%s%s %s日志占用%s\n' "$PURP" "$G_BAR" "$RESET" "$B" "$RESET"
  rule 56
  for f in "${files[@]}"; do
    sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"
    printf '  %s  %s%s%s\n' "$(human_size "${sz:-0}")" "$GRAY" "$f" "$RESET"
  done
  if [ -f /var/log/messages ]; then
    sz="$(wc -c < /var/log/messages 2>/dev/null | tr -d ' ')"
    printf '  %s  %s/var/log/messages%s（系统日志）\n' "$(human_size "${sz:-0}")" "$GRAY" "$RESET"
  fi
  if [ "${#files[@]}" -eq 0 ] && [ ! -f /var/log/messages ]; then
    warn "没有找到可清理的日志"
    return 0
  fi
  rule 56
  blank

  local go
  ask "清理 agent 日志?（大于 1MB 的文件保留最近 ${LOG_CLEAN_KEEP} 行）(y/N)" "N" go
  case "$go" in
    [Yy]*) ;;
    *) warn "已取消"; return 0 ;;
  esac

  for f in "${files[@]}"; do
    if trim_log_file "$f"; then
      ok "已清理 $f"
    fi
  done

  if [ -f /var/log/messages ]; then
    sz="$(wc -c < /var/log/messages 2>/dev/null | tr -d ' ')"
    if [ "${sz:-0}" -gt 10485760 ]; then
      local g2
      ask "/var/log/messages 超过 10MB，轮转它?（备份为 messages.1）(y/N)" "N" g2
      case "$g2" in
        [Yy]*) if rotate_messages; then ok "已轮转 /var/log/messages"; else warn "轮转失败"; fi ;;
      esac
    fi
  fi

  blank
  ask "开启每日自动清理? (y/N)" "N" go
  case "$go" in
    [Yy]*) install_log_cron ;;
  esac
}

cmd_logs() {
  if [ "${1:-}" = "clean" ]; then
    shift
    cmd_logs_clean "$@"
    return $?
  fi
  load_conf
  local id="${1:-1}" lines="${2:-80}"
  discover_instances
  if [ "$D_COUNT" -eq 0 ]; then die "没有安装任何实例"; fi

  local -a names=()
  local i
  for ((i = 0; i < D_COUNT; i++)); do names+=("${D_NAME[$i]}"); done

  local targets=()
  case "$id" in
    all)
      for ((i = 0; i < D_COUNT; i++)); do targets+=("$i"); done ;;
    *[!0-9]*)
      for ((i = 0; i < D_COUNT; i++)); do
        if [ "${D_NAME[$i]}" = "$id" ]; then targets+=("$i"); break; fi
      done
      [ "${#targets[@]}" -eq 0 ] && die "找不到实例 $id" ;;
    *)
      local idx=$((id - 1))
      if [ "$idx" -lt 0 ] || [ "$idx" -ge "$D_COUNT" ]; then die "编号超出范围"; fi
      targets=("$idx") ;;
  esac

  for i in "${targets[@]}"; do
    svc_logs "${D_NAME[$i]}" "${D_KIND[$i]}" "$lines" || warn "${D_NAME[$i]} 没有可读日志"
  done
}

cmd_uninstall() {
  need_root
  load_conf
  discover_instances
  if [ "$D_COUNT" -eq 0 ]; then warn "没有可卸载的实例"; return 0; fi

  local i j
  local -a scope=("全部（${D_COUNT} 个）" "手动勾选（可多选）")
  pick "卸载实例" "先选范围：全部，还是自己勾" "${scope[@]}" || return 0

  local -a targets=()
  if [ "$PICK_RESULT" -eq 0 ]; then
    for ((i = 0; i < D_COUNT; i++)); do targets+=("$i"); done
  else
    local -a names=()
    for ((i = 0; i < D_COUNT; i++)); do names+=("${D_NAME[$i]}"); done
    local picked=""
    MULTI_NO_MANUAL=1
    if ! pick_multi "选择实例" "勾选要卸载的实例（可多选）" "," picked "${names[@]}"; then
      MULTI_NO_MANUAL=0
      return 0
    fi
    MULTI_NO_MANUAL=0
    if [ -z "$picked" ]; then
      warn "没有勾选任何实例"
      return 0
    fi
    local IFS_OLD="$IFS"
    local -a sel=()
    IFS=',' read -r -a sel <<< "$picked"
    IFS="$IFS_OLD"
    local pn
    for pn in "${sel[@]}"; do
      for ((j = 0; j < D_COUNT; j++)); do
        if [ "${D_NAME[$j]}" = "$pn" ]; then targets+=("$j"); fi
      done
    done
  fi
  if [ "${#targets[@]}" -eq 0 ]; then
    warn "没有选中实例"
    return 0
  fi

  blank
  warn "将卸载 ${#targets[@]} 个实例（停服务 + 删除目录）"
  for i in "${targets[@]}"; do
    dim "  · ${D_NAME[$i]}"
  done
  local go
  if [ "${#targets[@]}" -ge "$D_COUNT" ]; then
    ask "输入 yes 确认全部卸载（直接回车取消）" "" go
    [ "$go" = "yes" ] || { warn "已取消"; return 0; }
  else
    ask "确认卸载? (y/N)" "N" go
    case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac
  fi

  for i in "${targets[@]}"; do
    remove_index "$i" 1
  done
}

# ================================================================ 版本维护 ===
ver_gt() { # $1 > $2 ?（纯数字比较，不依赖 sort -V）
  local a="$1" b="$2" i x y
  [ "$a" = "$b" ] && return 1
  local -a A=() B=()
  IFS=. read -r -a A <<< "$a"
  IFS=. read -r -a B <<< "$b"
  for ((i = 0; i < 3; i++)); do
    x="${A[$i]:-0}"
    y="${B[$i]:-0}"
    case "$x" in ''|*[!0-9]*) x=0 ;; esac
    case "$y" in ''|*[!0-9]*) y=0 ;; esac
    if [ "$x" -gt "$y" ]; then return 0; fi
    if [ "$x" -lt "$y" ]; then return 1; fi
  done
  return 1
}

ka_find_latest() {
  local files f v latest=""
  files="$(ls -1 "$KA_DIR"/ka-v[0-9]*.sh 2>/dev/null || true)"
  [ -z "$files" ] && return 0
  for f in $files; do
    v="$(basename "$f")"
    v="${v#ka-v}"
    v="${v%.sh}"
    if [ -z "$latest" ] || ver_gt "$v" "$latest"; then
      latest="$v"
    fi
  done
  printf '%s' "$latest"
}

cmd_update() {
  load_conf
  need_curl
  local check=0 clean=0 a
  for a in "$@"; do
    case "$a" in
      --check) check=1 ;;
      --clean) clean=1 ;;
    esac
  done

  local url="$KA_UPDATE_BASE/ka.sh"
  if [ -n "${GH_PROXY:-}" ]; then url="$GH_PROXY/$url"; fi

  local tmp
  tmp="$(mktemp /tmp/ka-update.XXXXXX)" || die "无法创建临时文件"
  info "检查更新：$url"
  if ! dl_to "$url" "$tmp" 30 || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    die "下载失败，检查网络或设置 GH_PROXY"
  fi

  local remote
  remote="$(sed -n 's/^KA_VERSION="\(.*\)"/\1/p' "$tmp" | head -n1)"
  if [ -z "$remote" ]; then
    rm -f "$tmp"
    die "远端脚本里没有版本号，可能地址不对"
  fi

  if [ "$remote" = "$KA_VERSION" ]; then
    rm -f "$tmp"
    ok "已是最新版本 v$KA_VERSION"
    return 0
  fi
  if ! ver_gt "$remote" "$KA_VERSION"; then
    rm -f "$tmp"
    ok "本地 v$KA_VERSION 不低于远端 v$remote"
    return 0
  fi

  panel_row "当前版本" "v$KA_VERSION"
  panel_row "最新版本" "v$remote"
  blank
  if [ "$check" -eq 1 ]; then
    rm -f "$tmp"
    dim "运行 ka update 安装"
    return 0
  fi

  need_root
  local go
  ask "更新到 v$remote? (Y/n)" "Y" go
  case "$go" in
    [Nn]*) rm -f "$tmp"; warn "已取消"; return 0 ;;
  esac

  local new_exec=""
  if [ -f "$KA_DIR/ka.sh" ] || ls "$KA_DIR"/ka-v*.sh >/dev/null 2>&1; then
    # 托管布局：写版本文件，launcher 会自动挑最新的
    local dst="$KA_DIR/ka-v$remote.sh"
    if [ -e "$dst" ]; then
      warn "$dst 已存在，未覆盖"
    else
      if ! cp -f "$tmp" "$dst" || ! chmod +x "$dst"; then
        rm -f "$tmp"; die "写入 $dst 失败"
      fi
    fi
    if [ -f "$KA_DIR/ka.sh" ]; then
      cp -f "$tmp" "$KA_DIR/ka.sh" && chmod +x "$KA_DIR/ka.sh"
    fi
    write_launcher "$KA_DIR"
    new_exec="$dst"
  else
    # 手动拷贝的单个脚本：原子替换，避免执行到一半被截断
    local new="$KA_SELF.new.$$"
    if ! cp -f "$tmp" "$new" || ! chmod +x "$new"; then
      rm -f "$tmp" "$new"; die "写入失败"
    fi
    if ! mv -f "$new" "$KA_SELF"; then
      rm -f "$tmp" "$new"; die "替换 $KA_SELF 失败"
    fi
    new_exec="$KA_SELF"
  fi

  rm -f "$tmp"
  ok "已更新到 v$remote"

  local f oldn=0
  local -a olds=()
  for f in "$KA_DIR"/ka-v*.sh; do
    [ -e "$f" ] || continue
    [ "$(readlink -f "$f")" = "$(readlink -f "$new_exec")" ] && continue
    olds+=("$f")
  done
  oldn="${#olds[@]}"
  if [ "$oldn" -gt 0 ]; then
    local c
    if [ "$clean" -eq 1 ]; then
      c="y"
    else
      ask "删除 $oldn 个旧版本文件?（只保留 v$remote）(y/N)" "N" c
    fi
    case "$c" in
      [Yy]*) for f in "${olds[@]}"; do rm -f "$f"; done
             ok "已删除 $oldn 个旧版本" ;;
    esac
  fi

  blank
  local sw
  ask "立即切换到新版本? (Y/n)" "Y" sw
  case "$sw" in
    [Nn]*) dim "下次运行 ka 就是 v$remote"; return 0 ;;
  esac
  exec bash "$new_exec"
}

ka_next_version() {
  local v="${1:-$KA_VERSION}" a b c
  IFS=. read -r a b c <<< "$v"
  a="${a:-0}"; b="${b:-0}"; c="${c:-1}"
  if [ "$KA_BUMP_STYLE" = "patch" ]; then
    c=$((c + 1))
  else
    b=$((b + 1))
  fi
  printf '%s.%s.%s' "$a" "$b" "$c"
}

cmd_bump() {
  local src="$KA_DIR/ka.sh" latest next dst
  [ -f "$src" ] || src="$KA_SELF"
  latest="$(ka_find_latest)"
  next="$(ka_next_version "${latest:-$KA_VERSION}")"
  dst="$KA_DIR/ka-v$next.sh"
  [ -e "$dst" ] && die "已存在 $(basename "$dst")，未做任何修改"

  local expr1 expr2
  expr1="s/^KA_VERSION=.*/KA_VERSION=\"$next\"/"
  expr2="s/^#  版本: [0-9.]+/#  版本: $next/"
  sed -E -e "$expr1" -e "$expr2" "$src" > "$dst" || die "写入失败"
  chmod +x "$dst" 2>/dev/null || true
  if [ "$(readlink -f "$src")" != "$(readlink -f "$dst")" ]; then
    sed -i -E -e "$expr1" -e "$expr2" "$src" 2>/dev/null || true
  fi
  ok "已发布 ka-v$next.sh（旧版本全部保留）"
  blank
  for dst in "$KA_DIR"/ka-v*.sh; do
    [ -e "$dst" ] || continue
    printf '   %s%s%s %s\n' "$GRAY" "$G_ARROW" "$RESET" "$(basename "$dst")"
  done
  blank
  dim "直接运行 ka 即可使用新版本"
}

write_launcher() { # 目录：生成/刷新 ka 启动器
  local dir="$1"
  cat > "$dir/ka" <<'KA_LAUNCHER'
#!/usr/bin/env bash
# ka 启动器：始终执行同目录下版本号最大的 ka-v*.sh
set -u
self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
dir="$(dirname "$self")"
best=""
bestv=""
for f in "$dir"/ka-v[0-9]*.sh; do
  [ -e "$f" ] || continue
  v="${f##*/}"
  v="${v#ka-v}"
  v="${v%.sh}"
  if [ -z "$best" ]; then
    best="$f"
    bestv="$v"
    continue
  fi
  IFS=. read -r -a A <<< "$v"
  IFS=. read -r -a B <<< "$bestv"
  bigger=0
  for i in 0 1 2; do
    x="${A[$i]:-0}"
    y="${B[$i]:-0}"
    case "$x" in ''|*[!0-9]*) x=0 ;; esac
    case "$y" in ''|*[!0-9]*) y=0 ;; esac
    if [ "$x" -gt "$y" ]; then bigger=1; break; fi
    if [ "$x" -lt "$y" ]; then bigger=-1; break; fi
  done
  if [ "$bigger" -eq 1 ]; then
    best="$f"
    bestv="$v"
  fi
done
if [ -z "$best" ]; then
  if [ -f "$dir/ka.sh" ]; then
    best="$dir/ka.sh"
  else
    echo "ka: 找不到 ka-v*.sh 或 ka.sh" >&2
    exit 1
  fi
fi
exec bash "$best" "$@"
KA_LAUNCHER
  chmod +x "$dir/ka"
}

cmd_self_install() {
  need_root
  local target="${1:-/opt/ka}"
  local src="$KA_SELF"

  case "$src" in
    /dev/fd/*|/proc/*/fd/*)
      die "请先下载到文件再执行：wget -qO /tmp/ka.sh <地址> && sudo bash /tmp/ka.sh self-install" ;;
  esac
  [ -f "$src" ] || die "找不到当前脚本文件：$src"

  if [ "$(readlink -f "$KA_DIR")" = "$(readlink -f "$target")" ] && [ -d "$target" ]; then
    ln -sf "$target/ka" /usr/local/bin/ka
    ok "已在 $target，已重建软链 /usr/local/bin/ka"
    return 0
  fi

  mkdir -p "$target" || die "无法创建 $target"
  cp -f "$src" "$target/ka.sh" || die "写入 $target/ka.sh 失败"
  chmod +x "$target/ka.sh"

  local base="$target/ka-v$KA_VERSION.sh"
  if [ ! -e "$base" ]; then
    cp -f "$src" "$base" && chmod +x "$base"
  fi

  local f
  for f in "$KA_DIR"/ka-v*.sh; do
    [ -e "$f" ] || continue
    [ "$(readlink -f "$f")" = "$(readlink -f "$base")" ] && continue
    cp -f "$f" "$target"/ 2>/dev/null || true
  done

  write_launcher "$target"

  ln -sf "$target/ka" /usr/local/bin/ka
  ok "已安装到 $target（v$KA_VERSION）"
  dim "直接运行： ka"
}

cmd_version() {
  banner
  panel_row "版本"     "v$KA_VERSION"
  panel_row "运行文件" "$KA_SELF"
  panel_row "发布目录" "$KA_DIR"
  panel_row "配置文件" "$KA_CONF"
  panel_row "初始化"   "$(init_label "$(detect_init)")"
  local style_text
  if [ "$KA_BUMP_STYLE" = "patch" ]; then
    style_text="patch（每次 +0.0.1）"
  else
    style_text="minor（每次 +0.1）"
  fi
  panel_row "版本规则" "$style_text"
  blank
  printf '  %s%s%s %s归档版本%s\n' "$PURP" "$G_BAR" "$RESET" "$B" "$RESET"
  rule 52
  local f found=0
  for f in "$KA_DIR"/ka-v*.sh; do
    [ -e "$f" ] || continue
    printf '   %s%s%s %s\n' "$GRAY" "$G_ARROW" "$RESET" "$(basename "$f")"
    found=1
  done
  if [ "$found" -eq 0 ]; then
    dim "（无）"
    dim "提示：当前 ka 像是手动拷贝的，运行 ka self-install 可启用版本归档"
  fi
  blank
}

cmd_help() {
  banner
  cat <<EOF
  ${B}安装${RESET}
    ka                    主菜单（↑↓ 选择）
    ka install            直接进入安装向导

  ${B}管理${RESET}
    ka status             实例状态（systemd / OpenRC 都认）
    ka doctor             一键自检（服务 / 自启 / 面板连通）
    ka adopt [名字]       接管外部实例（保留 token，重装为 ka 管理）
    ka upgrade [all|名字]  原地升级 Agent（沿用现有参数）
    ka batch              批量重启 / 停止 / 启动
    ka note [名字] [备注]  设置实例备注（地区/用途）
    ka hostname [名字]    修改本机主机名
    ka logs <n|name|all>  查看日志，默认 80 行
    ka logs clean         清理 agent 日志（可开每日自动清理）

  ${B}清理${RESET}
    ka uninstall          卸载实例（停服务 + 删目录）
    ka self-uninstall     卸载 ka 自身（保留实例）

  ${B}版本${RESET}
    ka update [--check|--clean]  更新 ka（--clean 顺手删旧版本）
    ka version            版本与归档信息
    ka bump               发布新版本，旧文件保留
    ka self-install       安装到 /opt/ka 并建立全局 ka 命令

  ${B}环境变量${RESET}
    KA_CONF               配置文件路径，默认 /etc/ka.conf
    KA_TUI=0              关闭方向键菜单（用编号菜单）
    KA_UI=plain           关闭彩色（也可用 NO_COLOR=1）

EOF
}

# ==================================================================== 菜单 ===
valid_hostname() {
  local h="$1"
  [ -n "$h" ] || return 1
  [ "${#h}" -le 63 ] || return 1
  case "$h" in
    *[!A-Za-z0-9.-]*) return 1 ;;
    -*|.*|*-|*.) return 1 ;;
  esac
  return 0
}

etc_hostname() {
  local h=""
  if [ -r /etc/hostname ]; then
    h="$(head -n 1 /etc/hostname 2>/dev/null)"
  fi
  printf '%s' "$h"
}

in_container() {
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then return 0; fi
  grep -qaE '(docker|lxc|kubepods|containerd|podman)' /proc/1/cgroup 2>/dev/null && return 0
  return 1
}

has_cap_sys_admin() {
  local cap
  cap="$(awk '/^CapEff:/{print $2}' /proc/self/status 2>/dev/null)"
  [ -n "$cap" ] || return 1
  [ $((0x$cap & 0x200000)) -ne 0 ]
}

cmd_hostname() {
  need_root
  local cur new go
  cur="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)"
  printf '\n  %s%s%s %s主机名%s\n' "$PURP" "$G_BAR" "$RESET" "$B" "$RESET"
  panel_row "当前" "${cur:-未知}"
  blank

  if [ $# -ge 1 ] && [ -n "$1" ]; then
    new="$1"
  else
    ask "新主机名（留空取消）" "" new
  fi
  [ -z "$new" ] && { warn "已取消"; return 0; }
  if ! valid_hostname "$new"; then
    warn "主机名不合法：只能含字母、数字、点、连字符，长度 1-63，不能以 . 或 - 开头结尾"
    return 1
  fi
  ask "确认把主机名改为 $new? (y/N)" "N" go
  case "$go" in [Yy]*) ;; *) warn "已取消"; return 0 ;; esac

  detect_init >/dev/null
  local applied=0 errf msg
  errf="$(mktemp /tmp/ka-hostname.XXXXXX 2>/dev/null || printf '')"
  [ -z "$errf" ] && errf=/dev/null

  if [ "$INIT_SYS" = "systemd" ] && command -v hostnamectl >/dev/null 2>&1; then
    if hostnamectl set-hostname "$new" 2>"$errf"; then applied=1; fi
  fi
  if [ "$applied" -eq 0 ]; then
    if ! printf '%s\n' "$new" > /etc/hostname 2>"$errf"; then
      msg="$(cat "$errf" 2>/dev/null)"
      rm -f "$errf"
      warn "写入 /etc/hostname 失败${msg:+：$msg}"
      return 1
    fi
    local hok=0
    if command -v hostname >/dev/null 2>&1 && hostname "$new" 2>"$errf"; then
      hok=1
    fi
    if [ "$hok" -eq 0 ] && [ -x /bin/hostname ] && /bin/hostname "$new" 2>>"$errf"; then
      hok=1
    fi
    if [ "$hok" -eq 0 ] && command -v busybox >/dev/null 2>&1 && busybox hostname "$new" 2>>"$errf"; then
      hok=1
    fi
    if [ "$hok" -eq 0 ]; then
      # 再试 /proc 接口（等价系统调用，少数环境只开这个）
      printf '%s' "$new" > /proc/sys/kernel/hostname 2>>"$errf" || true
    fi
    if [ "$(hostname 2>/dev/null)" != "$new" ]; then
      msg="$(cat "$errf" 2>/dev/null)"
      warn "设置内核主机名失败${msg:+：$msg}"
    fi
  fi
  rm -f "$errf"

  local now saved
  now="$(hostname 2>/dev/null)"
  saved="$(etc_hostname)"
  if [ "$saved" = "$new" ]; then
    ok "/etc/hostname 已写入 $saved"
  else
    warn "/etc/hostname 内容是 ${saved:-空}"
  fi

  if [ "$now" = "$new" ]; then
    ok "内核主机名已生效：$now"
    dim "bash 的 \\h 是启动时缓存的：当前会话提示符不会变，重新登录或 exec bash -l 才会显示新名字"
    return 0
  fi

  warn "内核主机名还是 ${now:-未知}（没有生效）"
  if ! has_cap_sys_admin; then
    dim "当前环境缺少 CAP_SYS_ADMIN，内核不允许改主机名（容器最常见）"
    dim "容器里的主机名由运行时决定，请在宿主机侧设置"
  elif in_container; then
    dim "检测到容器环境：内核主机名由宿主机/运行时决定"
    dim "要改请在宿主机侧设置：LXC 配置、docker run --hostname"
  else
    dim "手动看完整报错：hostname $new"
  fi
  return 1
}

cmd_menu() {
  [ -t 0 ] || die "菜单需要交互式终端；可用 ka install / ka status 等子命令"
  tui_init
  load_conf
  if [ ! -e /usr/local/bin/ka ] && [ ! -f "$KA_DIR/ka.sh" ]; then
    warn "当前只是临时运行，还没安装成命令"
    dim "执行 ka self-install 后，就能在任意目录直接输入 ka"
  fi

  local -a items=()
  local sub
  while :; do
    discover_instances
    detect_init >/dev/null
    local hk hf hs
    hk="$(hostname 2>/dev/null)"
    hf="$(etc_hostname)"
    if [ -n "$hf" ] && [ "$hf" != "$hk" ]; then
      hs="$hk（文件 $hf）"
    else
      hs="$hk"
    fi
    if [ "$D_COUNT" -eq 0 ]; then
      sub="v$KA_VERSION · $(init_label "$INIT_SYS") · 未发现实例 · $hs"
    else
      sub="v$KA_VERSION · $(init_label "$INIT_SYS") · ${D_COUNT} 个实例 · $hs"
    fi
    items=("安装 / 新增实例" "实例管理" "批量操作" "自检" "修改主机名" "清理日志" "卸载 / 清理" "检查更新" "退出")
    PICK_HINT="↑↓ 移动 · Enter 选择 · q 退出"
    pick "主菜单" "$sub" "${items[@]}" || return 0
    case "$PICK_RESULT" in
      0) cmd_wizard; pause_any ;;
      1) cmd_instances; pause_any ;;
      2) cmd_batch; pause_any ;;
      3) cmd_doctor; pause_any ;;
      4) cmd_hostname; pause_any ;;
      5) cmd_logs clean; pause_any ;;
      6) cmd_cleanup; pause_any ;;
      7) cmd_update; pause_any ;;
      8) return 0 ;;
    esac
  done
}

# ==================================================================== 入口 ===
main() {
  local cmd="${1:-menu}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    menu|'')              cmd_menu ;;
    wizard|install)       cmd_wizard ;;
    status)               cmd_status ;;
    doctor|check)         cmd_doctor ;;
    adopt)                cmd_adopt "$@" ;;
    upgrade)              cmd_upgrade "$@" ;;
    batch)                cmd_batch ;;
    note)                 cmd_note "$@" ;;
    logs)                 cmd_logs "$@" ;;
    uninstall|remove)     cmd_uninstall ;;
    cleanup)              cmd_cleanup ;;
    self-uninstall)       cmd_self_uninstall ;;
    version|-v|--version) cmd_version ;;
    hostname)             cmd_hostname "$@" ;;
    update)               cmd_update "$@" ;;
    bump)                 cmd_bump ;;
    self-install)         cmd_self_install "$@" ;;
    help|-h|--help)       cmd_help ;;
    *) err "未知命令: $cmd"; cmd_help; exit 1 ;;
  esac
}

main "$@"
