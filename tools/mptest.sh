#!/usr/bin/env bash
# Multiplayer test: a local dedicated server and one client, both -nosteam with their own data
# folders (mpenv/server, mpenv/client), on port 16361 so a normal server on 16261 is not touched.
# Three client runs: "on" (hang, wear, take off, swap), "relog" (new client, same server, ends with /quit),
# "restart" (server restarted too). See tests/NeckSlot_MPTest.lua.
#
#   bash tools/mptest.sh              the working tree; fails on a failed check or a server error
#   bash tools/mptest.sh BASE=HEAD    the mod from that git revision instead, to see the errors
#                                     from before a fix; reports them, does not fail on them
#
# Results: "[NeckSlotMP]" lines in mpenv/client/console_<mode>.txt and mpenv/server*.log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PZ_DIR="${PZ_DIR:-/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid}"
SRC_ENV="$ROOT/pzt-env/Zomboid"   # options and mods for a new client folder, from the pzt test folder
MP="$ROOT/mpenv"
SRV="$MP/server"
CLI="$MP/client"
TIMEOUT="${TIMEOUT:-600}"         # per client run
MIN_FREE_MB="${MIN_FREE_MB:-5000}" # server + client
MIN_COMMIT_MB="${MIN_COMMIT_MB:-300}" # stop before the machine runs out of commit
SERVER_HEAP="${SERVER_HEAP:-2048m}"
NAME=neckslot
BASE=""
for a in "$@"; do case "$a" in BASE=*) BASE="${a#BASE=}" ;; esac; done

if tasklist | grep -qi -E "ProjectZomboid64|^java.exe"; then
  echo "another game or java process is running; run one at a time"
  tasklist | grep -i -E "ProjectZomboid64|^java.exe"
  exit 2
fi
free_mb="$(powershell -NoProfile -Command "[int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024)" | tr -d '\r')"
if [ "$free_mb" -lt "$MIN_FREE_MB" ]; then
  echo "not enough free memory: $free_mb MB, need $MIN_FREE_MB MB (close the running game first)"
  exit 2
fi

MOD_DIR="$ROOT/Contents/mods/NeckSlot"
if [ -n "$BASE" ]; then
  rm -rf "$MP/base"
  mkdir -p "$MP/base"
  git -C "$ROOT" archive "$BASE" Contents/mods/NeckSlot | tar -x -C "$MP/base"
  MOD_DIR="$MP/base/Contents/mods/NeckSlot"
  echo "testing the mod from $BASE"
fi

install_mod() {
  rm -rf "$1/mods/NeckSlot"
  mkdir -p "$1/mods"
  cp -r "$MOD_DIR" "$1/mods/NeckSlot"
  mkdir -p "$1/mods/NeckSlot/42/media/lua/server"
  # same files on both sides; the client test only runs where its trigger file exists
  cp "$ROOT/tests/NeckSlot_MPTest.lua" "$1/mods/NeckSlot/42/media/lua/client/"
  cp "$ROOT/tests/NeckSlot_MPServer.lua" "$1/mods/NeckSlot/42/media/lua/server/"
}

# ---- server: fresh world every run
rm -rf "$SRV/Saves" "$SRV/db" "$MP"/server*.log
mkdir -p "$SRV/Server"
install_mod "$SRV"
cat > "$SRV/Server/$NAME.ini" <<EOF
Mods=NeckSlot
WorkshopItems=
Map=Muldraugh, KY
Open=true
Public=false
PauseEmpty=false
DoLuaChecksum=false
DefaultPort=16361
UDPPort=16362
SpawnPoint=10997,9699,0
EOF

# ---- client: fresh character every run
rm -rf "$CLI"
mkdir -p "$CLI/Lua"
for f in "$SRC_ENV"/*; do
  case "$(basename "$f")" in
    Saves|Screenshots|Logs|logs.zip|console.txt|latestSave.ini|db|pzt_control.txt) ;;
    *) cp -r "$f" "$CLI/" ;;
  esac
done
install_mod "$CLI"
printf 'VERSION = 1,\n\nmods\n{\n    mod = ZombieBuddy,\n    mod = PZTestHarness,\n    mod = NeckSlot,\n}\n\nmaps\n{\n}\n' > "$CLI/mods/default.txt"
# "autoload" makes the harness pass "click to start"; with no save it has nothing to continue
echo "flags autoload" > "$CLI/pzt_control.txt"

pids() {
  powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*NeckSlot*mpenv*' -and (\$_.Name -eq '$1' -or ('$1' -eq '' -and (\$_.Name -eq 'java.exe' -or \$_.Name -eq 'ProjectZomboid64.exe'))) } | ForEach-Object { \$_.ProcessId }" 2>/dev/null | tr -d '\r'
}
stop_all() {
  for pid in $(pids ""); do taskkill //PID "$pid" //F > /dev/null 2>&1 || true; done
}
trap stop_all EXIT

# $1 = server log file
start_server() {
  echo "starting server..."
  ( cd "$PZ_DIR" && ./jre64/bin/java.exe --enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED \
      -XX:+UseG1GC -XX:-CreateCoredumpOnCrash -XX:-OmitStackTraceInFastThrow -Xmx$SERVER_HEAP \
      "-Djava.library.path=./natives/;./natives/win64/;./" -cp "./;projectzomboid.jar" zombie.network.GameServer \
      -nosteam "-cachedir=$(cygpath -w "$SRV")" -servername $NAME -adminusername admin -adminpassword neckslot \
      > "$1" 2>&1 ) &
  local t0=$SECONDS
  until grep -q "SERVER STARTED" "$1" 2>/dev/null; do
    sleep 3
    if [ $((SECONDS - t0)) -gt 300 ]; then echo "server did not start"; tail -20 "$1"; exit 1; fi
  done
  echo "server started after $((SECONDS - t0))s"
}

# $1 = test mode; no -debug: a Lua error must not freeze the client in the debugger
run_client() {
  echo "$1" > "$CLI/Lua/neckslot_mptest.txt"
  rm -f "$CLI/console.txt"
  echo "starting client ($1)..."
  ( cd "$PZ_DIR" && ./ProjectZomboid64.exe "-agentlib:zbNative=policy=allow-all" -Xmx2048m -- \
      -nosteam -nosound "-cachedir=$(cygpath -w "$CLI")" > "$MP/client.log" 2>&1 ) &
  local finished=0 t0=$SECONDS
  while [ $((SECONDS - t0)) -lt "$TIMEOUT" ]; do
    sleep 3
    grep -aq "\[NeckSlotMP\] test done" "$CLI/console.txt" 2>/dev/null && { finished=1; break; }
    if [ $(((SECONDS - t0) % 30)) -lt 3 ]; then
      commit_mb="$(powershell -NoProfile -Command "[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory/1024)" | tr -d '\r')"
      if [ "$commit_mb" -lt "$MIN_COMMIT_MB" ]; then echo "free commit $commit_mb MB: stopping"; exit 2; fi
    fi
  done
  echo "client ($1): finished=$finished after $((SECONDS - t0))s"
  # it quits by itself, which saves the player on the server
  local t1=$SECONDS
  while [ -n "$(pids ProjectZomboid64.exe)" ] && [ $((SECONDS - t1)) -lt 60 ]; do sleep 3; done
  for pid in $(pids ProjectZomboid64.exe); do echo "client did not quit, killing it"; taskkill //PID "$pid" //F > /dev/null 2>&1 || true; done
  cp "$CLI/console.txt" "$CLI/console_$1.txt" 2>/dev/null || true
  sleep 5
}

start_server "$MP/server.log"
run_client on
run_client relog

# the relog run asked the server to save and quit (/quit)
t0=$SECONDS
while [ -n "$(pids java.exe)" ] && [ $((SECONDS - t0)) -lt 120 ]; do sleep 3; done
if [ -n "$(pids java.exe)" ]; then echo "server did not quit after /quit"; else echo "server quit after $((SECONDS - t0))s"; fi
stop_all
sleep 3
start_server "$MP/server2.log"
run_client restart

echo "--- client ---"
grep -ahE "\[NeckSlotMP\] (FAIL|RESULT|connect failed)|MOD:Neck Slot|STACK TRACE" "$CLI"/console_*.txt 2>/dev/null | tail -60 || true
echo "--- server ---"
grep -ahE "server location registered|MOD:Neck Slot" "$MP"/server*.log 2>/dev/null | tail -10 || true
nosuch=$(cat "$MP"/server*.log | grep -ac 'no such location "NeckSlot Neck"' || true)
packet=$(cat "$MP"/server*.log | grep -ac 'Error with packet of type: GameCharacterAttachedItem' || true)
pass=$(cat "$CLI"/console_*.txt | grep -ac "\[NeckSlotMP\] PASS" || true)
fail=$(cat "$CLI"/console_*.txt | grep -ac "\[NeckSlotMP\] FAIL" || true)
runs=$(cat "$CLI"/console_*.txt | grep -ac "\[NeckSlotMP\] test done" || true)
echo "server errors: no such location ${nosuch:-0}, attached item packet ${packet:-0}"
echo "MP total: pass ${pass:-0} fail ${fail:-0} (finished runs ${runs:-0} of 3)"
[ -n "$BASE" ] && exit 0
[ "${fail:-0}" = 0 ] && [ "${runs:-0}" = 3 ] && [ "${nosuch:-0}" = 0 ] && [ "${packet:-0}" = 0 ]
