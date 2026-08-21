#!/usr/bin/env bash
# Start CARLA 0.10.0 with the same low-load defaults used by the Autoware tests.
set -eo pipefail

CARLA_ROOT="${CARLA_ROOT:-$HOME/Carla-0.10.0-Linux-Shipping}"
CARLA_SERVER="$CARLA_ROOT/Linux/CarlaUnreal.sh"
if [[ -z "${CARLA_RENDER_MODE+x}" ]]; then
  CARLA_RENDER_MODE="nullrhi"
fi

if [[ ! -x "$CARLA_SERVER" ]]; then
  echo "CARLA server not found or not executable: $CARLA_SERVER" >&2
  exit 1
fi

case "$CARLA_RENDER_MODE" in
  nullrhi)
    CARLA_ARGS=(-nullrhi -quality-level=Low)
    ;;
  offscreen)
    CARLA_ARGS=(-RenderOffScreen -quality-level=Low)
    ;;
  onscreen)
    CARLA_ARGS=(-quality-level=Low)
    ;;
  *)
    echo "Unknown CARLA_RENDER_MODE '$CARLA_RENDER_MODE' (expected nullrhi, offscreen, or onscreen)" >&2
    exit 1
    ;;
esac

exec "$CARLA_SERVER" "${CARLA_ARGS[@]}" "$@"
