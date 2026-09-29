# Rendering, Map & UI

## Map
Metal-backed high-density rendering. Pipeline:
`World -> spatial index -> visible tiles/regions -> visible assets/routes -> LOD/clustering -> GPU buffers -> Metal`.

World view uses clusters/aggregates. Regional views use reduced detail. Individual high detail is reserved for relevant/selected assets.

## Visual motion
Simulation stores operational truth such as route/departure/arrival. Rendering interpolates visual position without writing authoritative state every second/frame.

## UI
SwiftUI/management UI consumes read models. It never scans or mutates world state directly. Large tables use indexed queries, pagination/virtualization and incremental updates.

## Thermal
Presentation may degrade gracefully under pressure—labels, effects, LOD, map update rate/frame target—without altering business/economic outcomes.
