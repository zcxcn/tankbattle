extends Spatial
const Layout = preload("res://data/woodland_layout.gd")
var woodland = false
var blocks = []
var rng = RandomNumberGenerator.new()
var materials = {}
var surfaces = {}
var ground_body

func material(color, texture = ""):
	var key = str(color) + texture
	if materials.has(key): return materials[key]
	var m = SpatialMaterial.new()
	m.albedo_color = color
	m.roughness = 0.84
	if texture != "":
		m.albedo_texture = load(texture)
		m.albedo_texture.flags = Texture.FLAG_REPEAT | Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS
	materials[key] = m
	return m

func box(at, size, mat, collide = false):
	var mesh = CubeMesh.new()
	mesh.size = size
	if not surfaces.has(mat):
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[mat] = st
	surfaces[mat].append_from(mesh, 0, Transform(Basis(), at))
	if collide:
		var body = StaticBody.new()
		body.collision_layer = 1
		body.translation = at
		var shape = CollisionShape.new()
		var cube = BoxShape.new()
		cube.extents = size * 0.5
		shape.shape = cube
		body.add_child(shape)
		add_child(body)
		blocks.append(Rect2(Vector2(at.x-size.x/2,at.z-size.z/2),Vector2(size.x,size.z)))

func bake():
	for mat in surfaces:
		var mesh = surfaces[mat].commit()
		mesh.surface_set_material(0,mat)
		var instance = MeshInstance.new()
		instance.mesh = mesh
		add_child(instance)
	surfaces.clear()

func height_at(x,z):
	return Layout.height_at(x,z) if woodland else 0.0

func ground(at):
	return Vector3(at.x,height_at(at.x,at.z)+0.08,at.z)

func bridge_x(x):
	return clamp(round(x/96.0)*96.0,-96.0,96.0)

func allowed(at, radius=2.2):
	if abs(at.x)>140-radius or abs(at.z)>188-radius: return false
	if at.z>22-radius and at.z<50+radius and abs(at.x-bridge_x(at.x))>8-radius: return false
	for rect in blocks:
		if rect.grow(radius).has_point(Vector2(at.x,at.z)): return false
	return true

func route(from,to):
	# Keep the entire hull inside a bridge corridor before crossing the water.
	if (from.z>54 and to.z<54) or (from.z<18 and to.z>18):
		var x = bridge_x((from.x+to.x)*0.5)
		if abs(from.x-x)>3.0:
			return ground(Vector3(x,0,58 if from.z>36 else 14))
		return ground(Vector3(x,0,14 if from.z>36 else 58))
	if from.z>=18 and from.z<=54:
		return ground(Vector3(bridge_x(from.x),0,58 if to.z>36 else 14))
	return to

func build(is_woodland, seed_value):
	woodland = is_woodland
	rng.seed = seed_value
	var terrain = SurfaceTool.new()
	terrain.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step = 4
	for z in range(-192,192,step):
		for x in range(-144,144,step):
			var points = [Vector3(x,0,z),Vector3(x+step,0,z),Vector3(x,0,z+step),Vector3(x+step,0,z+step)]
			for index in [0,1,2,1,3,2]:
				var p = points[index]
				p.y = height_at(p.x,p.z)
				if p.z>=24 and p.z<=48: p.y = -3.5
				var road = Layout.road_distance(p.x,p.z)<7
				terrain.add_color(Color(0.51,0.48,0.36) if road else (Color(0.43,0.55,0.32) if woodland else Color(0.57,0.57,0.54)))
				terrain.add_uv(Vector2(p.x,p.z)*0.14)
				terrain.add_vertex(p)
	terrain.generate_normals()
	var ground_mesh = terrain.commit()
	var ground_mat = material(Color.white,"res://assets/materials/polyhaven/rough_concrete/rough_concrete_diff_1k.jpg")
	ground_mat.vertex_color_use_as_albedo = true
	ground_mesh.surface_set_material(0,ground_mat)
	var instance = MeshInstance.new()
	instance.mesh = ground_mesh
	add_child(instance)
	# The playable boundary should not expose the edge of a floating rectangle.
	var surround=MeshInstance.new()
	var surround_mesh=PlaneMesh.new()
	surround_mesh.size=Vector2(1400,1400)
	surround.mesh=surround_mesh
	surround.translation.y=-4
	var distant_ground=material(Color("697651") if woodland else Color("797b68"))
	surround.material_override=distant_ground
	add_child(surround)
	ground_body = StaticBody.new()
	var cs = CollisionShape.new()
	cs.shape = ground_mesh.create_trimesh_shape()
	ground_body.add_child(cs)
	add_child(ground_body)
	var water = MeshInstance.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(292,28)
	water.mesh = plane
	water.translation = Vector3(0,-0.7,36)
	var water_mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = "shader_type spatial; render_mode cull_disabled; void fragment(){float w=sin(UV.x*180.0+TIME*1.5)*sin(UV.y*80.0-TIME); ALBEDO=mix(vec3(0.06,0.19,0.22),vec3(0.19,0.38,0.40),w*0.25+0.4); ROUGHNESS=0.24;}"
	water_mat.shader = shader
	water.material_override = water_mat
	add_child(water)
	var concrete = material(Color("89918c"))
	var steel = material(Color("39494b"))
	for x in [-96,0,96]:
		box(Vector3(x,-0.25,36),Vector3(16,0.5,32),concrete,false)
		var bridge = StaticBody.new()
		bridge.translation = Vector3(x,-0.25,36)
		var bc = CollisionShape.new()
		var bs = BoxShape.new()
		bs.extents = Vector3(8,0.25,16)
		bc.shape = bs
		bridge.add_child(bc)
		add_child(bridge)
		for side in [-1,1]:
			box(Vector3(x+side*8,0.6,36),Vector3(0.22,0.2,32),steel)
			for z in range(22,51,4): box(Vector3(x+side*8,0.15,z),Vector3(0.25,1.0,0.25),steel)
	if woodland: forest()
	else: city()
	bake()

func city():
	var facade = material(Color("969a92"),"res://assets/materials/polyhaven/rough_concrete/rough_concrete_diff_1k.jpg")
	var glass = material(Color("294d60"))
	glass.metallic = 0.4
	glass.roughness = 0.25
	var trim = material(Color("c0b8a1"))
	for x in [-122,-70,-26,26,70,122]:
		for z in [-164,-110,-42,102,152]:
			var height = rng.randf_range(15,54)
			var width = rng.randf_range(12,17)
			var depth = 18.0
			box(Vector3(x,3,z),Vector3(width+2,6,depth+2),facade,true)
			for tier in range(3):
				var w = width-tier*2
				var d = depth-tier*2
				var h = height/3
				var y = 6+tier*h
				box(Vector3(x,y+h/2,z),Vector3(w,h,d),facade,true)
				box(Vector3(x,y+h,z),Vector3(w+0.5,0.3,d+0.5),trim)
				for floor_index in range(int(h/3)):
					var wy = y+1.6+floor_index*3
					for column in range(int(w/2.7)):
						for side in [-1,1]:box(Vector3(x-w/2+1.4+column*2.7,wy,z+side*(d/2+0.03)),Vector3(1.6,1.9,0.08),glass)
					for column in range(int(d/2.7)):
						for side in [-1,1]:box(Vector3(x+side*(w/2+0.03),wy,z-d/2+1.4+column*2.7),Vector3(0.08,1.9,1.6),glass)
			box(Vector3(x,height+7,z),Vector3(3,2,4),trim)

func descendants(node, type_name):
	var result=[]
	for child in node.get_children():
		if child.is_class(type_name): result.append(child)
		result += descendants(child,type_name)
	return result

func forest():
	var source = load("res://assets/models/environment/polyhaven_tree_small02/woodland_tree.glb").instance()
	var parts = descendants(source,"MeshInstance")
	var cells = {}
	var count = 0
	for attempt in range(1500):
		if count>=110: break
		var p = ground(Vector3(rng.randf_range(-135,135),0,rng.randf_range(-181,181)))
		if Layout.road_distance(p.x,p.z)<13 or (p.z>8 and p.z<64):continue
		if not allowed(p,6):continue
		var s = rng.randf_range(0.85,1.25)
		var key = Vector2(floor(p.x/64),floor(p.z/64))
		if not cells.has(key):cells[key]=[]
		cells[key].append(Transform(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*s),p))
		var trunk = StaticBody.new()
		trunk.translation=p+Vector3(0,3*s,0)
		var shape=CollisionShape.new()
		var cyl=CylinderShape.new()
		cyl.radius=0.5*s
		cyl.height=6*s
		shape.shape=cyl
		trunk.add_child(shape)
		add_child(trunk)
		blocks.append(Rect2(Vector2(p.x-0.5,p.z-0.5),Vector2(1,1)))
		count+=1
	for part in parts:
		var local = part.transform
		var parent = part.get_parent()
		while parent is Spatial:
			local = parent.transform*local
			parent=parent.get_parent()
		for i in range(part.mesh.get_surface_count()):
			var mat=part.mesh.surface_get_material(i)
			if mat is SpatialMaterial and mat.flags_transparent:
				mat.flags_transparent=false
				mat.params_use_alpha_scissor=true
				mat.params_alpha_scissor_threshold=0.25
				mat.params_cull_mode=SpatialMaterial.CULL_DISABLED
		for key in cells:
			var mm=MultiMesh.new()
			mm.transform_format=MultiMesh.TRANSFORM_3D
			mm.mesh=part.mesh
			mm.instance_count=cells[key].size()
			for i in range(mm.instance_count):mm.set_instance_transform(i,cells[key][i]*local)
			var batch=MultiMeshInstance.new()
			batch.multimesh=mm
			add_child(batch)
	source.free()
