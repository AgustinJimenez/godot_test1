"""Print connected boundary-loop bounds for imported glTF meshes."""

from __future__ import annotations

import sys
from collections import defaultdict, deque
from pathlib import Path

import bpy


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(Path(sys.argv[sys.argv.index("--") + 1]).resolve()))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        edge_faces: dict[tuple[int, int], int] = defaultdict(int)
        for polygon in mesh.polygons:
            vertices = polygon.vertices
            for index in range(len(vertices)):
                edge = tuple(sorted((vertices[index], vertices[(index + 1) % len(vertices)])))
                edge_faces[edge] += 1
        boundary_edges = [edge for edge, count in edge_faces.items() if count == 1]
        adjacency: dict[int, set[int]] = defaultdict(set)
        for start, end in boundary_edges:
            adjacency[start].add(end)
            adjacency[end].add(start)
        remaining = set(adjacency)
        components: list[list[int]] = []
        while remaining:
            queue = deque([remaining.pop()])
            component = []
            while queue:
                vertex = queue.popleft()
                component.append(vertex)
                for neighbor in adjacency[vertex]:
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        queue.append(neighbor)
            components.append(component)
        print(f"BOUNDARY_MESH:{obj.name} edges={len(boundary_edges)} loops={len(components)}")
        for component in sorted(components, key=len, reverse=True):
            coordinates = [obj.matrix_world @ mesh.vertices[index].co for index in component]
            bounds = [
                (min(getattr(value, axis) for value in coordinates),
                 max(getattr(value, axis) for value in coordinates))
                for axis in ("x", "y", "z")
            ]
            center = sum(coordinates, coordinates[0] * 0.0) / len(coordinates)
            print(
                f"BOUNDARY_LOOP:{obj.name} vertices={len(component)} "
                f"center=({center.x:.4f},{center.y:.4f},{center.z:.4f}) "
                f"bounds={bounds}"
            )


if __name__ == "__main__":
    main()
