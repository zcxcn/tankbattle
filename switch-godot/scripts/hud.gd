extends Control
var game
var small
var normal
var title
const WHITE=Color("e7ece8")
const MUTED=Color("a0b6bc")
const GOLD=Color("efbf69")

func _ready():
	var data=load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	small=DynamicFont.new()
	small.font_data=data
	small.size=18
	normal=DynamicFont.new()
	normal.font_data=data
	normal.size=23
	title=DynamicFont.new()
	title.font_data=data
	title.size=46

func text(at,value,color=WHITE,font=null):
	draw_string(normal if font==null else font,at,str(value),color)

func panel(rect):
	draw_style_box(style(),rect)

func style():
	var box=StyleBoxFlat.new()
	box.bg_color=Color(0.025,0.055,0.065,0.91)
	box.border_color=Color(0.30,0.47,0.49,0.8)
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	return box

func bar(at,width,value,color):
	draw_rect(Rect2(at,Vector2(width,8)),Color("26373a"))
	draw_rect(Rect2(at,Vector2(width*clamp(value,0,1),8)),color)

func _draw():
	if game==null or normal==null:return
	if game.state=="play":
		panel(Rect2(24,20,440,102))
		text(Vector2(42,53),"无尽防线 · 第 %d 波"%game.wave if game.mode=="endless" else "%02d  %s"%[game.chapter+1,game.mission.name])
		text(Vector2(42,84),"剩余敌人 %d    击毁 %d"%[game.enemy_count()+game.pending,game.kills],MUTED,small)
		if game.mode=="endless":bar(Vector2(42,100),390,game.base_hp/1000.0,Color("69d7cd"))
		panel(Rect2(24,574,430,122))
		text(Vector2(42,607),"装甲 %d / %d"%[game.player.hp,game.player.max_hp])
		bar(Vector2(42,620),390,game.player.hp/game.player.max_hp,Color("72c79b"))
		text(Vector2(42,657),["120mm 穿甲弹","同轴机枪","高爆榴弹","制导火箭"][game.weapon],GOLD)
		text(Vector2(42,683),"装填 %.1fs  ·  地雷 %.0fs  ·  脉冲 %.0fs"%[game.player.cooldown,game.mine_cooldown,game.pulse_cooldown],MUTED,small)
		panel(Rect2(860,636,396,60))
		text(Vector2(878,662),"ZR 开火   L/R 换武器   X 切换视角",WHITE,small)
		text(Vector2(878,686),"Y 地雷   ZL 脉冲   − 音乐   + 暂停",MUTED,small)
		var center=Vector2(640,360)
		if not game.third_person:center=game.camera.unproject_position(game.aim_position)
		var color=GOLD if game.player.cooldown>0 else Color("94e8d3")
		for offset in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:draw_line(center+offset*8,center+offset*20,color,2)
		draw_circle(center,2,color)
		minimap()
		if game.mode=="campaign" and not game.objective_done:
			text(Vector2(420,152),"占领中继站：%d / %d 秒"%[game.objective_time,game.mission.objective_seconds] if game.mission.objective_type=="capture" else "摧毁燃料库：%d"%game.objective_hp,GOLD,small)
		if game.wave_wait>0:text(Vector2(480,185),"区域已清空 · 整备倒计时 %.0f"%game.wave_wait,GOLD)
		return
	draw_rect(Rect2(0,0,1280,720),Color(0.015,0.03,0.04,0.46))
	panel(Rect2(80,56,690,604))
	text(Vector2(118,122),"钢铁余烬",WHITE,title)
	text(Vector2(120,159),"IRON EMBERS  /  SWITCH 1  /  0.1.0",GOLD,small)
	var entries=[]
	match game.state:
		"menu":entries=["开始战役","无尽防线 · 巨怪来袭","青岚河谷 · 丘陵与河流","关卡  ‹ %s ›"%game.Missions.get_mission(game.selected_chapter).name,"战车  ‹ %s ›"%game.Vehicles.PLAYER_VEHICLES[game.selected_vehicle].name,"天气  ‹ %s ›"%["随机","晴天","雨天","雪天"][game.selected_weather],"退出至 hbmenu"]
		"pause":entries=["继续战斗","重新部署","返回主菜单"]
		"shop":
			text(Vector2(120,200),"第 %d 波完成 · 整备资金 %d"%[game.wave,game.credits],GOLD)
			entries=["火力 +15%%  [%d/6]   %d"%[game.upgrades[0],game.upgrade_cost(0)],"装填提速 10%%  [%d/6]   %d"%[game.upgrades[1],game.upgrade_cost(1)],"装甲升级 / 修复基地  [%d/6]   %d"%[game.upgrades[2],game.upgrade_cost(2)],"出发 · 第 %d 波"%(game.wave+1)]
		"victory":
			text(Vector2(120,200),"任务完成 · 指挥车已摧毁",GOLD)
			entries=["下一关" if game.chapter<6 else "再次挑战青岚河谷","返回主菜单"]
		"defeat":
			text(Vector2(120,200),"作战失败 · 调整策略后再战",GOLD)
			entries=["重新部署","返回主菜单"]
	var start=214 if game.state=="menu" else 255
	for i in range(entries.size()):
		var y=start+i*47
		if i==game.menu_index:
			draw_rect(Rect2(112,y-29,615,41),Color(0.21,0.33,0.32,0.85))
			draw_rect(Rect2(112,y-29,4,41),GOLD)
		text(Vector2(132,y),entries[i],WHITE if i==game.menu_index else MUTED)
	text(Vector2(120,610),"左摇杆：转向 / 行驶   右摇杆：瞄准",MUTED,small)
	text(Vector2(120,640),"方向键选择   A 确认   ←/→ 调整",MUTED,small)

func minimap():
	var rect=Rect2(1070,20,186,238)
	panel(rect)
	var scale=Vector2(170.0/288,216.0/384)
	var origin=Vector2(1078,30)
	var river_y=origin.y+(36+192)*scale.y
	draw_rect(Rect2(origin.x,river_y-8,170,16),Color("315d6c"))
	for actor in game.targets():
		if actor.dead:continue
		var p=origin+Vector2(actor.translation.x+144,actor.translation.z+192)*scale
		draw_circle(p,3.8 if actor.team==0 else 2.4,Color("7ae4d6") if actor.team==0 else Color("ef7756"))
	if game.mode=="campaign" and not game.objective_done:
		var p=origin+Vector2(game.mission.objective_position.x+144,game.mission.objective_position.z+192)*scale
		draw_circle(p,5,GOLD)
