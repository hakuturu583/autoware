#!/usr/bin/env bash
# 3DGS シミュレーションのワンショット再起動(ホスト側で実行)。
# 全ROSプロセス駆除 → splatsimコンテナ削除 → CARLA再起動 → launch。
# (lanelet2 ローダは map.launch.xml 側で standalone 起動されるため手動投入は不要)
set -eo pipefail

DEV=aw-devel-autoware-devel-1
CARLA_ROOT="${CARLA_ROOT:-$HOME/Carla-0.10.0-Linux-Shipping/Carla-0.10.0-Linux-Shipping}"
CARLA_SCRIPT="${CARLA_SCRIPT:-$HOME/Downloads/data/run_carla_0_10.sh}"

echo "[1/4] devcontainer 内の ROS プロセスを駆除"
docker exec "$DEV" bash -c '
  kill -TERM $(pgrep -f "e2e_sim[u]lator.launch") 2>/dev/null; sleep 5
  PIDS=$(ps -eo pid,args | grep -E "\-\-ros-args" | grep -v grep | awk "{print \$1}")
  kill -KILL $PIDS 2>/dev/null; sleep 2
  echo "  残存ROSプロセス: $(ps -eo args | grep -cE "[\-]-ros-args")"' || true

echo "[2/4] splatsim コンテナ削除"
docker rm -f splatsim_top 2>/dev/null || true

echo "[3/4] CARLA 再起動(kill 後 12 秒待ち)"
pkill -9 -f "Carla[U]nreal" 2>/dev/null || true
sleep 12
CARLA_ROOT="$CARLA_ROOT" CARLA_RENDER_MODE=nullrhi \
  nohup bash "$CARLA_SCRIPT" > /tmp/carla_server.log 2>&1 &
disown
for i in $(seq 1 60); do
  ss -ltn | grep -q :2000 && { echo "  CARLA up (${i}s)"; break; }
  sleep 1
done
ss -ltn | grep -q :2000 || { echo "CARLA が起動しない (/tmp/carla_server.log 参照)" >&2; exit 1; }

echo "[4/4] Autoware + SplatSim launch(デタッチ)"
docker exec -d "$DEV" bash -lc \
  'bash /home/aw/autoware_data/launch_splatsim_3dgs.sh > /tmp/carla_3dgs.log 2>&1'

echo "完了。2〜3分後に RViz でゴール設定 → Engage。ログ: docker exec $DEV tail -f /tmp/carla_3dgs.log"
