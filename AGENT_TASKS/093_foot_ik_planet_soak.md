# 093 Foot IK soak on the planet

Request (user, mid-port of 092): once the C++ port is done, test the IK on the planet as many times as possible: load the planet scene, walk for a
while, read the IK logs; when something is off in the logs, find the bug and fix it. Same 4-minute loop. Run windows on screen 1, in the background.

## Plan
- Use the planet lab grounded (`--grounded --walk-check` / `--forest-walk`, FootIKV2Debug logs, scripts/trace_v2.sh) and read the logs.
- Record each finding and fix below.

## Log
