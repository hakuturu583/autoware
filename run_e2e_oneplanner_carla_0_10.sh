#!/usr/bin/env bash
# Launch Autoware against CARLA 0.10.0 Odaiba using the oneplanner E2E stack.
set -eo pipefail

source /opt/ros/humble/setup.bash
source "$(dirname "${BASH_SOURCE[0]}")/install/setup.bash"

CARLA_ROOT="${CARLA_ROOT:-$HOME/Carla-0.10.0-Linux-Shipping}"
CARLA_WHEEL="$CARLA_ROOT/PythonAPI/carla/dist/carla-0.10.0-cp310-cp310-linux_x86_64.whl"
CARLA_PYTHON_DIR="${CARLA_PYTHON_DIR:-$HOME/.cache/carla-python-0.10.0}"
MAP_PATH="${MAP_PATH:-$HOME/autoware_data/maps/odaibatest}"
CARLA_MAP="${CARLA_MAP:-Odaiba}"
CARLA_VEHICLE_TYPE="${CARLA_VEHICLE_TYPE:-vehicle.taxi.ford}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$CARLA_PYTHON_DIR/carla.cpython-310-x86_64-linux-gnu.so" ]]; then
  mkdir -p "$CARLA_PYTHON_DIR"
  python3 - <<PY
import zipfile
with zipfile.ZipFile("$CARLA_WHEEL") as wheel:
    wheel.extractall("$CARLA_PYTHON_DIR")
PY
fi
# splatsim's gRPC client needs protobuf>=5 and grpcio, which live in the user
# site-packages (~/.local). PYTHONNOUSERSITE=1 (below, to keep the CARLA wheel's
# deps isolated) hides them, and the apt protobuf (3.12) is too old for the
# generated *_pb2.py (ImportError: cannot import name 'runtime_version'). Expose
# ONLY protobuf + grpc via a curated symlink dir so numpy/etc. stay isolated.
SPLATSIM_PYDEPS="${SPLATSIM_PYDEPS:-$HOME/.cache/splatsim-pydeps}"
USER_SITE="$(python3 -c 'import site,sys; sys.stdout.write(site.getusersitepackages())' 2>/dev/null || echo "$HOME/.local/lib/python3.10/site-packages")"
SPLATSIM_PYDEPS_PATH=""
if [[ -d "$USER_SITE/google" && -d "$USER_SITE/grpc" ]]; then
  mkdir -p "$SPLATSIM_PYDEPS"
  for pkg in google grpc; do
    ln -sfn "$USER_SITE/$pkg" "$SPLATSIM_PYDEPS/$pkg"
  done
  SPLATSIM_PYDEPS_PATH="$SPLATSIM_PYDEPS:"
else
  echo "WARNING: protobuf/grpc not found in user site-packages ($USER_SITE); splatsim LiDAR may fail to import" >&2
fi
export PYTHONNOUSERSITE=1
export PYTHONPATH="${SPLATSIM_PYDEPS_PATH}$CARLA_PYTHON_DIR:${PYTHONPATH:-}"

# Derived from the CARLA 0.10.0 Odaiba reference pose in PythonAPI/examples/rgl_test_autoware_demo.py:
#   map_x = carla_x + 92008.4413568
#   map_y = -carla_y + 45335.0528819
MAP_ORIGIN_X="${MAP_ORIGIN_X:-92008.441357}"
MAP_ORIGIN_Y="${MAP_ORIGIN_Y:-45335.052882}"

# Spawn at the START of the ego trajectory recorded in the v25 usdz splatsim
# scene (~/workspace/fg_plus_bg_background_v25_enu_ecef.usdz), so the ego begins
# exactly where the reconstructed drive began and the 3DGS scene is populated
# around it from frame 1.
#   Derivation: rig_trajectories.json rigs[0].poses[0] (world ENU, rig origin =
#   ground_under_rear_axle) -> ECEF via scene.json ecef_anchor -> WGS84 LLA ->
#   MGRS 54SUE local (matches Autoware odaibatest map.osm local_x/y, affine
#   residual ~1e-13) -> CARLA (map_x = carla_x + MAP_ORIGIN_X,
#   map_y = -carla_y + MAP_ORIGIN_Y; carla_yaw = -yaw_enu).
#   z is left at 10.9 as a safe hint; SPAWN_POINT_GROUND_SNAP re-grounds it
#   (raycast starts at CARLA z=1000 and ignores this value).
# Previous validated Odaiba spawn: -2341.209473,3139.423096,10.9,0.0,0.0,-120.0
SPAWN_POINT="${SPAWN_POINT:--2574.309,2109.126,10.9,0.0,0.0,56.180}"
if [[ "${CARLA_USE_REAL_CAMERA:-0}" == "1" ]]; then
  DEFAULT_SENSOR_MAPPING_FILE="$(pwd)/install/autoware_carla_interface/share/autoware_carla_interface/config/sensor_mapping_camera_preview.yaml"
  DEFAULT_NO_RENDERING_MODE=False
else
  DEFAULT_SENSOR_MAPPING_FILE="$(pwd)/install/autoware_carla_interface/share/autoware_carla_interface/config/sensor_mapping_lidar_only.yaml"
  DEFAULT_NO_RENDERING_MODE=True
fi
SENSOR_MAPPING_FILE="${SENSOR_MAPPING_FILE:-$DEFAULT_SENSOR_MAPPING_FILE}"
NO_RENDERING_MODE="${NO_RENDERING_MODE:-$DEFAULT_NO_RENDERING_MODE}"
CARLA_STATE_PUBLISH_TF="${CARLA_STATE_PUBLISH_TF:-True}"
AUTOWARE_LOCALIZATION="${AUTOWARE_LOCALIZATION:-false}"
NORMALIZE_STEER_COMMAND="${NORMALIZE_STEER_COMMAND:-True}"
STEER_COMMAND_GAIN="${STEER_COMMAND_GAIN:-1.25}"
STEERING_TIME_CONSTANT="${STEERING_TIME_CONSTANT:-0.12}"
STEER_RESPONSE_CALIBRATION_ENABLE="${STEER_RESPONSE_CALIBRATION_ENABLE:-False}"
STEER_RESPONSE_CALIBRATION_WHEEL_BASE="${STEER_RESPONSE_CALIBRATION_WHEEL_BASE:-2.79}"
if [[ -z "${STEER_RESPONSE_CALIBRATION_TABLE:-}" ]]; then
  # Measured on CARLA 0.10.0 Odaiba at about 2 m/s.
  # Format: target_curvature_1pm:required_carla_steer
  case "$CARLA_VEHICLE_TYPE" in
    vehicle.byd.j6gen2)
      STEER_RESPONSE_CALIBRATION_TABLE="0.0:0.0;0.0011704:0.1;0.0046857:0.2;0.0294556:0.5"
      ;;
    vehicle.taxi.ford|*)
      STEER_RESPONSE_CALIBRATION_TABLE="0.0:0.0;0.0035589:0.1;0.0140123:0.2;0.0314162:0.3;0.0879820:0.5;0.1767216:0.75;0.4809201:1.0"
      ;;
  esac
fi
INITIAL_POSE_GROUND_OFFSET_Z="${INITIAL_POSE_GROUND_OFFSET_Z:-1.5}"
SPAWN_POINT_GROUND_SNAP="${SPAWN_POINT_GROUND_SNAP:-True}"
SPAWN_POINT_GROUND_OFFSET_Z="${SPAWN_POINT_GROUND_OFFSET_Z:-1.2}"
MIN_POSITIVE_THROTTLE="${MIN_POSITIVE_THROTTLE:-0.6}"
MIN_POSITIVE_THROTTLE_SPEED_THRESHOLD="${MIN_POSITIVE_THROTTLE_SPEED_THRESHOLD:-0.8}"
RVIZ="${RVIZ:-true}"

find_existing_autoware_processes() {
  ps -eo pid=,cmd= | grep -E 'autoware_carla_interface|component_container(_mt)?|goal_pose_visualizer|command_mode_decider|autonomous_mode_transition_flag_node|rviz2|ros2 launch autoware_launch' | grep -vE 'grep -E|awk '
}

ONEPLANNER_BASE_PARAM_YAML="${ONEPLANNER_BASE_PARAM_YAML:-$ROOT_DIR/src/universe/autoware_universe/e2e/autoware_tensorrt_oneplanner/config/oneplanner.param.yaml}"
ONEPLANNER_PARAM_OVERRIDE_PATH="${ONEPLANNER_PARAM_OVERRIDE_PATH:-}"
ONEPLANNER_DELAY_STEP="${ONEPLANNER_DELAY_STEP:-2}"
ONEPLANNER_TEMPERATURE="${ONEPLANNER_TEMPERATURE:-}"
ONEPLANNER_ENABLE_WARM_START="${ONEPLANNER_ENABLE_WARM_START:-}"
ONEPLANNER_DEBUG_TENSOR_LOGGING="${ONEPLANNER_DEBUG_TENSOR_LOGGING:-}"

if [[ -z "$ONEPLANNER_PARAM_OVERRIDE_PATH" ]] && { [[ -n "$ONEPLANNER_DELAY_STEP" ]] || [[ -n "$ONEPLANNER_TEMPERATURE" ]] || [[ -n "$ONEPLANNER_ENABLE_WARM_START" ]] || [[ -n "$ONEPLANNER_DEBUG_TENSOR_LOGGING" ]]; }; then
  override_args=(--base-yaml "$ONEPLANNER_BASE_PARAM_YAML")
  if [[ -n "$ONEPLANNER_DELAY_STEP" ]]; then
    override_args+=(--delay-step "$ONEPLANNER_DELAY_STEP")
  fi
  if [[ -n "$ONEPLANNER_TEMPERATURE" ]]; then
    override_args+=(--temperature "$ONEPLANNER_TEMPERATURE")
  fi
  if [[ -n "$ONEPLANNER_ENABLE_WARM_START" ]]; then
    override_args+=(--enable-warm-start "$ONEPLANNER_ENABLE_WARM_START")
  fi
  if [[ -n "$ONEPLANNER_DEBUG_TENSOR_LOGGING" ]]; then
    override_args+=(--debug-tensor-logging "$ONEPLANNER_DEBUG_TENSOR_LOGGING")
  fi
  ONEPLANNER_PARAM_OVERRIDE_PATH="$(python3 "$ROOT_DIR/tools/render_oneplanner_param_override.py" "${override_args[@]}")"
  echo "Using OnePlanner override params: $ONEPLANNER_PARAM_OVERRIDE_PATH"
fi

if [[ "$RVIZ" != "1" && "$RVIZ" != "true" && "$RVIZ" != "True" ]]; then
  echo "This launcher now requires RViz for user confirmation. Re-run with RVIZ=true." >&2
  exit 1
fi

existing_processes="$(find_existing_autoware_processes || true)"
if [[ -n "$existing_processes" ]]; then
  echo "Detected existing Autoware/RViz processes. Refusing to launch a second stack:" >&2
  echo "$existing_processes" >&2
  exit 1
fi

ros2 launch autoware_launch e2e_simulator.launch.xml \
  map_path:="$MAP_PATH" \
  vehicle_model:=sample_vehicle \
  sensor_model:=carla_sensor_kit \
  simulator_type:=carla \
  carla_map:="$CARLA_MAP" \
  force_load_world:=True \
  vehicle_type:="$CARLA_VEHICLE_TYPE" \
  no_rendering_mode:="$NO_RENDERING_MODE" \
  min_positive_throttle:="$MIN_POSITIVE_THROTTLE" \
  min_positive_throttle_speed_threshold:="$MIN_POSITIVE_THROTTLE_SPEED_THRESHOLD" \
  normalize_steer_command:="$NORMALIZE_STEER_COMMAND" \
  steer_command_gain:="$STEER_COMMAND_GAIN" \
  steering_time_constant:="$STEERING_TIME_CONSTANT" \
  steer_response_calibration_enable:="$STEER_RESPONSE_CALIBRATION_ENABLE" \
  steer_response_calibration_wheel_base:="$STEER_RESPONSE_CALIBRATION_WHEEL_BASE" \
  steer_response_calibration_table:="$STEER_RESPONSE_CALIBRATION_TABLE" \
  initial_pose_ground_offset_z:="$INITIAL_POSE_GROUND_OFFSET_Z" \
  timeout:=60 \
  rviz:="$RVIZ" \
  localization:="$AUTOWARE_LOCALIZATION" \
  use_light_weight_sensor_mapping:=True \
  sensor_mapping_file:="$SENSOR_MAPPING_FILE" \
  map_origin_x:="$MAP_ORIGIN_X" \
  map_origin_y:="$MAP_ORIGIN_Y" \
  spawn_point:="$SPAWN_POINT" \
  spawn_point_ground_snap:="$SPAWN_POINT_GROUND_SNAP" \
  spawn_point_ground_offset_z:="$SPAWN_POINT_GROUND_OFFSET_Z" \
  carla_state_publish_tf:="$CARLA_STATE_PUBLISH_TF" \
  use_e2e_planner:=true \
  e2e_planner_mode:=oneplanner \
  oneplanner_param_path_override:="$ONEPLANNER_PARAM_OVERRIDE_PATH" \
  "$@"
