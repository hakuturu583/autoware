#!/usr/bin/env python3
"""Render an override copy of the OnePlanner param YAML.

Reads a base ``oneplanner.param.yaml`` and writes a copy to a temporary file
with only the requested parameters replaced, then prints the path of the
generated file to stdout. ``run_e2e_oneplanner_carla_0_10.sh`` consumes that
path and passes it to the launch file via ``oneplanner_param_path_override:=``,
so experiment parameters can be injected at launch time without editing the
tracked YAML.

Only four keys are overridable; they all live directly under
``/**: -> ros__parameters:`` in the base file. Overriding is done as a
line-oriented text substitution (rather than a YAML load/dump round-trip) so
that comments, key ordering and ``$(var ...)`` / ``$(find-pkg-share ...)``
substitution strings are preserved verbatim.
"""

import argparse
import os
import re
import sys
import tempfile


def str2bool(value):
    """Parse a shell-style boolean string into a Python bool."""
    normalized = value.strip().lower()
    if normalized in ("true", "1", "yes", "on"):
        return True
    if normalized in ("false", "0", "no", "off"):
        return False
    raise argparse.ArgumentTypeError(f"expected a boolean value, got '{value}'")


# Maps each CLI option to the YAML key it overrides and how to render its value.
# The rendered value must be valid YAML for a ROS 2 parameter file.
OVERRIDES = {
    "delay_step": lambda v: str(int(v)),
    "temperature": lambda v: repr(float(v)),
    "enable_warm_start": lambda v: "true" if v else "false",
    "debug_tensor_logging": lambda v: "true" if v else "false",
}


def apply_override(text, key, rendered_value):
    """Replace the value of ``key:`` in ``text``, preserving indentation.

    The key is expected to appear exactly once as a block-style mapping entry.
    Any trailing inline comment on that line is dropped (the overridable keys
    carry no inline comments in the base file).
    """
    pattern = re.compile(rf"^(?P<indent>[ \t]*){re.escape(key)}:[ \t]*\S.*$", re.MULTILINE)
    matches = pattern.findall(text)
    if len(matches) == 0:
        sys.exit(f"error: key '{key}' not found in base yaml")
    if len(matches) > 1:
        sys.exit(f"error: key '{key}' is ambiguous ({len(matches)} matches) in base yaml")
    return pattern.sub(rf"\g<indent>{key}: {rendered_value}", text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-yaml", required=True, help="path to the base oneplanner.param.yaml")
    parser.add_argument("--delay-step", type=int, help="override delay_step")
    parser.add_argument("--temperature", type=float, help="override temperature")
    parser.add_argument("--enable-warm-start", type=str2bool, help="override enable_warm_start")
    parser.add_argument("--debug-tensor-logging", type=str2bool, help="override debug_tensor_logging")
    parser.add_argument("--output", help="write to this path instead of a temp file")
    args = parser.parse_args()

    if not os.path.isfile(args.base_yaml):
        sys.exit(f"error: base yaml not found: {args.base_yaml}")

    with open(args.base_yaml, encoding="utf-8") as f:
        text = f.read()

    for key, render in OVERRIDES.items():
        value = getattr(args, key)
        if value is not None:
            text = apply_override(text, key, render(value))

    if args.output:
        path = args.output
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        fd, path = tempfile.mkstemp(prefix="oneplanner_param_override_", suffix=".yaml")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)

    # stdout must contain only the generated path (captured via $(...) by callers).
    print(path)


if __name__ == "__main__":
    main()
