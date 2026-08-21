#!/usr/bin/env bash
# 3DGS (SplatSim) simulation with the OnePlanner E2E stack.
# Config ported from ~/Downloads/run_e2e_oneplanner_carla_0_10.sh, with:
#   - SplatSim LiDAR rendering (local image) instead of CARLA raycast
#   - spawn point inside the scene_c_unified.usdz 3DGS coverage
# Localization stack is OFF: carla_state_publisher (E2E infra) publishes
# /localization/kinematic_state and map->base_link TF from the CARLA GT pose.
source /opt/ros/jazzy/setup.bash
source /home/aw/autoware/install/setup.bash
export PYTHONNOUSERSITE=1
# SplatSim gRPC client uses protobuf; force pure-python impl for compatibility.
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
exec ros2 launch autoware_launch e2e_simulator.launch.xml \
  simulator_type:=carla \
  map_path:=/home/aw/autoware_data/maps/Odaiba \
  carla_map:=Odaiba \
  data_path:=/home/aw/autoware_data \
  vehicle_model:=sample_vehicle \
  sensor_model:=carla_sensor_kit \
  rviz:=true \
  localization:=false \
  host:=localhost port:=2000 timeout:=60 \
  force_load_world:=true \
  min_positive_throttle:=0.6 \
  min_positive_throttle_speed_threshold:=0.8 \
  no_rendering_mode:=True \
  vehicle_type:=vehicle.taxi.ford \
  spawn_point:=-2638.530,2189.059,6.966,0.0,0.0,148.0 \
  spawn_point_ground_snap:=True \
  spawn_point_ground_offset_z:=1.2 \
  initial_pose_ground_offset_z:=1.5 \
  map_origin_x:=92008.441357 \
  map_origin_y:=45335.052882 \
  use_light_weight_sensor_mapping:=True \
  sensor_mapping_file:=/home/aw/autoware_data/carla_sensor_mapping_splatsim_lidar.yaml \
  render_with_splatsim:=true \
  splatsim_render_lidar:=true \
  splatsim_render_camera:=false \
  splatsim_image:=splatsim:feat-lidar-sector-streaming \
  splatsim_tileset_path:=/home/masaya/workspace/scene_c_unified.usdz \
  use_e2e_planner:=true \
  e2e_planner_mode:=oneplanner
