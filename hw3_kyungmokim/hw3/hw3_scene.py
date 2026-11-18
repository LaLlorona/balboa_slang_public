import json
import numpy as np
import buffer
import math
import os
import slangpy as spy
import trimesh

SPHERE = 0  # Must match Slang's ShapeType in hw3_common.slang
TRIANGLE_MESH = 1

def parse_triangle_mesh(filename):
    if filename.lower().endswith('.ply'):
        mesh = trimesh.load_mesh(filename, process=False)

        vertices = np.asarray(mesh.vertices, dtype=np.float32)
        faces = np.asarray(mesh.faces, dtype=np.uint32)
        vertex_normals = np.asarray(
            mesh.vertex_normals, dtype=np.float32)

    else:
        with open(filename) as f:
            mesh = json.load(f)

        vertices = np.array(mesh['vertices'], dtype=np.float32)
        faces = np.array(mesh['faces'], dtype=np.uint32)

        if 'vertex_normals' in mesh:
            vertex_normals = np.array(
                mesh['vertex_normals'], dtype=np.float32)
        else:
            # Generate smooth vertex normals.
            tri_mesh = trimesh.Trimesh(
                vertices=vertices,
                faces=faces,
                process=False)
            vertex_normals = np.asarray(
                tri_mesh.vertex_normals, dtype=np.float32)

    return vertices, faces, vertex_normals

def compose_transformations(transformations):
    """
        Given a list of transformations, compose them into a matrix.
    """
    # HW 3.4: copy paste your HW2.3 code here

    F = np.eye(4, dtype=np.float32)
    for transform in transformations:
        (transformType, transformValue), = transform.items()

        if (transformType == 'scale'):
            scaleMatrix = np.eye(4, dtype = np.float32)
            scaleMatrix[0, 0] = transformValue[0]
            scaleMatrix[1, 1] = transformValue[1]
            scaleMatrix[2, 2] = transformValue[2]
            F = scaleMatrix @ F

        if (transformType == 'rotate_x'):
            rotateMatrix = np.eye(4, dtype = np.float32)
            rotateMatrix[1, 1] = np.cos(math.radians(transformValue[0]))
            rotateMatrix[1, 2] = -np.sin(math.radians(transformValue[0]))
            rotateMatrix[2, 1] = np.sin(math.radians(transformValue[0]))
            rotateMatrix[2, 2] = np.cos(math.radians(transformValue[0]))
            F = rotateMatrix @ F
        if (transformType == 'rotate_y'):
            rotateMatrix = np.eye(4, dtype = np.float32)
            rotateMatrix[0, 0] = np.cos(math.radians(transformValue[0]))
            rotateMatrix[0, 2] = np.sin(math.radians(transformValue[0]))
            rotateMatrix[2, 0] = -np.sin(math.radians(transformValue[0]))
            rotateMatrix[2, 2] = np.cos(math.radians(transformValue[0]))
            F = rotateMatrix @ F
        if (transformType == 'rotate_z'):
            rotateMatrix = np.eye(4, dtype = np.float32)
            rotateMatrix[0, 0] = np.cos(math.radians(transformValue[0]))
            rotateMatrix[0, 1] = -np.sin(math.radians(transformValue[0]))
            rotateMatrix[1, 0] = np.sin(math.radians(transformValue[0]))
            rotateMatrix[1, 1] = np.cos(math.radians(transformValue[0]))
            F = rotateMatrix @ F


        if (transformType == 'translate'):
            translateMatrix = np.eye(4, dtype = np.float32)
            translateMatrix[0, 3] = transformValue[0]
            translateMatrix[1, 3] = transformValue[1]
            translateMatrix[2, 3] = transformValue[2]
            F = translateMatrix @ F

        if (transformType == 'lookat'):
            camPosition = np.array(transformValue['position'])
            camTarget = np.array(transformValue['target'])
            camUp = np.array(transformValue['up'])
            d = camTarget - camPosition
            d = d / np.linalg.norm(d)
            right = np.cross(d, camUp)
            right = right / np.linalg.norm(right)
            up = np.cross(right, d)
            lookAtMatrix = np.eye(4, dtype = np.float32)
            lookAtMatrix[0][0] = right[0]
            lookAtMatrix[1][0] = right[1]
            lookAtMatrix[2][0] = right[2]

            lookAtMatrix[0][1] = up[0]
            lookAtMatrix[1][1] = up[1]
            lookAtMatrix[2][1] = up[2]

            lookAtMatrix[0][2] = -d[0]
            lookAtMatrix[1][2] = -d[1]
            lookAtMatrix[2][2] = -d[2]

            lookAtMatrix[0][3] = camPosition[0]
            lookAtMatrix[1][3] = camPosition[1]
            lookAtMatrix[2][3] = camPosition[2]
            F = lookAtMatrix @ F

    return F
Transform = dict[str, list[float]]
KeyFrame = dict
def lerp_value(a, b, s):
    if isinstance(a, dict):
        return {k: lerp_value(a[k], b[k], s) for k in a}
    if isinstance(a, (list, tuple)):
        return [lerp_value(x, y, s) for x, y in zip(a, b)]
    return (1 - s) * a + s * b

def interpolate_transformation(transform_keyframes, t):
    # HW 3.4: copy your HW2.4 code here.

    # create a new transform from the two keyframes
    if (len(transform_keyframes) == 0):
        return []


    start_time : float = transform_keyframes[0]['time']
    end_time : float = transform_keyframes[len(transform_keyframes)-1]['time']
    
    result : list[Transform] = []
    
    if t <= start_time or t >= end_time :
        edgeIndex : int = 0 if t <= start_time else len(transform_keyframes) - 1
        edgeTransform : list[Transform] = transform_keyframes[edgeIndex]['transform']
        for item in edgeTransform:
            for name, values in item.items():
                result.append({name : lerp_value(values, values, 0)})
        return result
    
    interpolationStartIndex : int = 0
    for i in range(0, len(transform_keyframes) - 1, 1):
        intervalStartTime : float = transform_keyframes[i]['time']
        intervalEndTime : float = transform_keyframes[i + 1]['time']
        if intervalStartTime <= t and t < intervalEndTime :
            interpolationStartIndex = i
            break
    
    interpolationStartInfo = transform_keyframes[interpolationStartIndex]
    interpolationEndInfo = transform_keyframes[interpolationStartIndex + 1]
    interpolationValue : float = (t - interpolationStartInfo['time']) / (interpolationEndInfo['time'] - interpolationStartInfo['time'])
    startTransformInfo : Transform
    endTransformInfo : Transform
    for startTransformInfo, endTransformInfo in zip(interpolationStartInfo['transform'], interpolationEndInfo['transform']) :
        name : str
        values : list[float]
        for name, values in startTransformInfo.items():
            result.append({name: lerp_value(values, endTransformInfo[name], interpolationValue)})
    return result

def get_transformation(obj, t):
    transforms = obj.get('transform', [])
    if 'transform_keyframes' in obj:
        transforms = interpolate_transformation(
            obj['transform_keyframes'], t)
    return compose_transformations(transforms)

def build_bvh(vertices, faces, triangle_offset, bvh_nodes):
    # A recursive BVH builder that split the longest axis
    # using the median of the centroids. The leaf nodes
    # have maximum of 4 triangles.

    assert(len(faces) > 0)
    # Needs a copy because we will sort them during the recursion
    faces = faces.copy()
    centers = vertices[faces].mean(axis=1)

    def build(begin, end):
        node_id = len(bvh_nodes)
        # Important: append a node first
        # before the recursion, so that the order
        # is "preorder" 
        bvh_nodes.append(None)

        # Bounding box of all triangles in this node
        points = vertices[faces[begin:end]].reshape(-1, 3)
        bbox_min = points.min(axis=0)
        bbox_max = points.max(axis=0)

        # Stop recursion if the node has fewer than 4 triangles
        is_leaf = end - begin <= 4
        if not is_leaf:
            # Find the longest axis
            c = centers[begin:end]
            axis = np.argmax(c.max(axis=0) - c.min(axis=0))

            # Sort triangles by their centroids
            order = np.argsort(c[:, axis])
            faces[begin:end] = faces[begin:end][order]
            centers[begin:end] = c[order]

            # Split
            mid = (begin + end) // 2
            build(begin, mid)
            build(mid, end)

        bvh_nodes[node_id] = {
            'bbox_min': bbox_min,
            'bbox_max': bbox_max,
            'next_index': len(bvh_nodes),
            'triangle_begin': triangle_offset + begin,
            'triangle_end': triangle_offset + end,
            'is_leaf': is_leaf
        }

        return node_id

    root = build(0, len(faces))
    return root, faces

def upload_scene(filename, module, slang_device, use_bvh = False):
    with open(filename) as f:
        scene = json.load(f)

    background = scene.get('background', (0.5, 0.5, 0.5))

    camera = {'cam_to_world': np.eye(4, dtype=np.float32),
              'fov_x': 90.0}

    if 'camera' in scene:
        camera['cam_to_world'] = \
            get_transformation(scene['camera'], 0.0)
        camera['fov_x'] = scene['camera'].get('fov_x', 90.0)

    # Triangle meshes loading + BVH building
    mesh_descs = []
    vertices_list = []
    normals_list = []
    triangles_list = []
    bvh_nodes = []

    vertex_offset = 0
    triangle_offset = 0

    scene_dir = os.path.dirname(filename)

    for mesh_data in scene.get('meshes', []):
        mesh_filename = os.path.join(
            scene_dir, mesh_data['filename'])
        vertices, faces, vertex_normals = \
            parse_triangle_mesh(mesh_filename)

        # Construct the BVH and reorder triangles
        # The returned faces is a copy of our
        # original faces.
        if use_bvh:
            bvh_root_index, faces = build_bvh(
                vertices, faces, triangle_offset, bvh_nodes)
        else:
            bvh_root_index = 0

        mesh_descs.append({
            'vertex_offset': vertex_offset,
            'triangle_begin': triangle_offset,
            'triangle_end': triangle_offset + len(faces),
            'bvh_root_index': bvh_root_index
        })

        vertices_list.append(vertices)
        normals_list.append(vertex_normals)
        triangles_list.append(faces)

        vertex_offset += len(vertices)
        triangle_offset += len(faces)

    # Merge into global arrays
    if len(mesh_descs) > 0:
        vertices = np.concatenate(vertices_list).astype(np.float32)
        normals = np.concatenate(normals_list).astype(np.float32)
        triangles = np.concatenate(triangles_list).astype(np.uint32)
    else:
        # Use dummy entries if the scene has no meshes
        vertices = np.zeros((1, 3), dtype=np.float32)
        normals = np.zeros((1, 3), dtype=np.float32)
        triangles = np.zeros((1, 3), dtype=np.uint32)

    # Parse object instances.
    spheres = []
    shapes = []

    for obj in scene['objects']:
        if obj['type'] == 'sphere':
            shape_type = SPHERE
            shape_index = len(spheres)
            spheres.append({
                'center': obj['center'],
                'radius': obj['radius']
            })
        elif obj['type'] == 'mesh':
            shape_type = TRIANGLE_MESH
            shape_index = obj['index']
        else:
            raise ValueError(f"Unknown shape type: {obj['type']}")

        obj_to_world = get_transformation(obj, 0.0)
        world_to_obj = np.linalg.inv(obj_to_world)

        shapes.append({
            'type': shape_type,
            'index': shape_index,
            'Kd': obj['Kd'],
            'Kr': obj['Kr'],
            'world_to_obj': world_to_obj,
            'obj_to_world': obj_to_world
        })

    lights = scene['lights']

    max_depth = scene.get('max_depth', 20)

    bindings = {
        'background': spy.float3(background),
        'camera': camera,
        'shapes': buffer.create_structured_buffer(
            slang_device, module.Shape, shapes),
        'num_shapes': len(shapes),
        'spheres': buffer.create_structured_buffer(
            slang_device, module.Sphere, spheres),
        'meshes': buffer.create_structured_buffer(
            slang_device, module.TriangleMesh, mesh_descs),
        'vertices': buffer.structured_typed_buffer_from_numpy(
            slang_device, vertices, 'float3'),
        'vertex_normals': buffer.structured_typed_buffer_from_numpy(
            slang_device, normals, 'float3'),
        'triangles': buffer.structured_typed_buffer_from_numpy(
            slang_device, triangles, 'uint3'),
        'bvh_nodes': buffer.create_structured_buffer(
            slang_device, module.BVHNode, bvh_nodes),
        'lights': buffer.create_structured_buffer(
            slang_device, module.PointLight, lights),
        'num_lights': len(lights),
        'max_depth': max_depth
    }

    return bindings, scene, shapes
