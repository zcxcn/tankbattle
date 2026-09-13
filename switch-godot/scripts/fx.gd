extends Spatial
var age=0.0
var duration=2.3
var size=8.0
var sprite
var light
var plume=false

func setup(at, strength=1.0, muzzle=false, cookoff=false):
	translation=at
	size=(2.8 if muzzle else 9.0)*strength
	duration=0.18 if muzzle else (3.6 if cookoff else 2.3)
	plume=cookoff
	sprite=Sprite3D.new()
	sprite.texture=load("res://assets/fx/fluid/explosion.png")
	sprite.hframes=5
	sprite.vframes=5
	sprite.billboard=SpatialMaterial.BILLBOARD_ENABLED
	sprite.pixel_size=size/(sprite.texture.get_width()/5.0)
	sprite.translation.y=size*0.24
	sprite.no_depth_test=false
	sprite.shaded=false
	add_child(sprite)
	light=OmniLight.new()
	light.light_color=Color(1,0.55,0.15)
	light.light_energy=3.5
	light.omni_range=size*1.8
	add_child(light)

func _process(delta):
	age+=delta
	var progress=clamp(age/duration,0,1)
	sprite.frame=int(progress*24)
	sprite.opacity=1.0-smoothstep(0.75,1.0,progress)
	sprite.scale=Vector3.ONE*(0.65+min(progress*3,1)*0.5)
	if plume:
		sprite.translation.y=size*(0.2+progress*1.8)
		sprite.scale.y*=1.9
	light.light_energy=max(0,3.5-age*8)
	if age>=duration:queue_free()
