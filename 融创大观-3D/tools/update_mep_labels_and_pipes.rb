# -*- coding: utf-8 -*-
# 从当前模型读取设备位置 → 加中文标签 → 重组 A2-MEP-WATER-HVAC → 重建管线路由

model = Sketchup.active_model
model.start_operation('Update MEP labels and pipes', true)

Z_COLD  = 105.0
Z_HOT   = 103.0
Z_RET   = 101.0
Z_AC    = 108.0
Z_FH    = 2.8
Y_SPLIT = 152.0

PIPE_R = {
  'A2-MEP-SOFT-COLD' => 0.65,
  'A2-MEP-HOT' => 0.70,
  'A2-MEP-HOT-RETURN' => 0.55,
  'A2-MEP-AC-WATER' => 0.60,
  'A2-MEP-FLOOR-HEAT' => 0.50,
  'A2-MEP-RO' => 0.35
}

LAYER_COLORS = {
  'A2-MEP-EQUIP' => [85, 85, 85],
  'A2-MEP-SOFT-COLD' => [20, 100, 255],
  'A2-MEP-HOT' => [230, 30, 30],
  'A2-MEP-HOT-RETURN' => [255, 120, 0],
  'A2-MEP-AC-WATER' => [30, 170, 90],
  'A2-MEP-FLOOR-HEAT' => [140, 60, 180],
  'A2-MEP-RO' => [200, 60, 200],
  'A2-MEP-LABEL' => [20, 20, 20]
}

LAYER_COLORS.each do |name, rgb|
  model.layers.add(name) unless model.layers[name]
  mat = model.materials["A2_MEP_#{name}"] || model.materials.add("A2_MEP_#{name}")
  mat.color = Sketchup::Color.new(*rgb)
end

EQUIP_LABELS = {
  'cabinet' => '水柜·前置+中净+中软',
  'dhw' => '[B] 生活热水空气能',
  'ac_hp' => '[A] 两联供+缓冲水箱',
  'fh_manifold' => '地暖分集水器',
  'ro' => 'RO纯水·厨下',
  'pipeline' => '管线机',
  'dhw_boost' => '主卫小厨宝·串热管',
  'washer' => '洗衣机',
  'robot' => '扫地机·上下水预留',
  'fp_living' => '风机盘管·客厅',
  'fp_bed2' => '风机盘管·次卧',
  'fp_master' => '风机盘管·主卧',
  'fp_study' => '风机盘管·书房',
  'fp_kitchen' => '风机盘管·厨房'
}

$EQUIP = {}

def mat_for(model, layer)
  model.materials["A2_MEP_#{layer}"]
end

def bounds_hash(g)
  b = g.bounds
  {
    x0: b.min.x, x1: b.max.x, y0: b.min.y, y1: b.max.y, z0: b.min.z, z1: b.max.z,
    cx: (b.min.x + b.max.x) / 2.0, cy: (b.min.y + b.max.y) / 2.0,
    cz: (b.min.z + b.max.z) / 2.0
  }
end

def port(e, face)
  case face
  when :top then [e[:cx], e[:cy], e[:z1]]
  when :north then [e[:cx], e[:y1], e[:z1] * 0.85]
  when :south then [e[:cx], e[:y0], e[:z1] * 0.85]
  when :east then [e[:x1], e[:cy], e[:z1] * 0.85]
  when :west then [e[:x0], e[:cy], e[:z1] * 0.85]
  end
end

def dedupe_run(pts)
  out = []
  pts.each { |p| out << p if out.empty? || out.last != p }
  out
end

def add_pipe_run(parent, layer, points, label=nil)
  pts = dedupe_run(points)
  return nil if pts.length < 2
  g = parent.entities.add_group
  g.name = label if label
  g.layer = model.layers[layer]
  m = mat_for(model, layer)
  r = PIPE_R[layer] || 0.5
  (0...(pts.length - 1)).each do |i|
    a = Geom::Point3d.new(*pts[i])
    b = Geom::Point3d.new(*pts[i + 1])
    vec = b - a
    len = vec.length
    next if len < 0.03
    vec.normalize!
    up = Geom::Vector3d.new(0, 0, 1)
    vr = vec.cross(up)
    vr = Geom::Vector3d.new(1, 0, 0).cross(vec) if vr.length < 0.001
    vr.normalize!
    vt = vec.cross(vr)
    vt.normalize!
    circle = (0...8).map do |k|
      ang = 2.0 * Math::PI * k / 8
      o1 = vr.clone; o1.length = r * Math.cos(ang)
      o2 = vt.clone; o2.length = r * Math.sin(ang)
      a.offset(o1).offset(o2)
    end
    face = g.entities.add_face(circle)
    next unless face
    face.reverse! if face.normal.dot(vec) < 0
    face.pushpull(len)
  end
  g.material = m
  g
end

def riser(z_ceil, z_floor, xy)
  x, y = xy
  [[x, y, z_floor], [x, y, z_ceil]]
end

def route(*pts)
  pts
end

# ---------- 读取设备 ----------
ents = model.active_entities
missing = []
EQUIP_LABELS.each_key do |id|
  g = ents.grep(Sketchup::Group).find { |x| x.name == id }
  if g
    $EQUIP[id] = bounds_hash(g)
  else
    missing << id
  end
end

raise "缺少设备组: #{missing.join(', ')}" unless missing.empty?

# ---------- 重组父组 ----------
root = ents.grep(Sketchup::Group).find { |g| g.name == 'A2-MEP-WATER-HVAC' }
unless root
  root = ents.add_group
  root.name = 'A2-MEP-WATER-HVAC'
  root.set_attribute('A2', 'version', '20260628_v04')
end

['FLOOR-HEATING-ZONES', 'PIPES', 'LEGEND', 'EQUIP-LABELS'].each do |n|
  g = ents.grep(Sketchup::Group).find { |x| x.name == n && x.parent == model }
  next unless g
  inst = root.entities.add_instance(g.to_component, g.transformation)
  inst.name = n
  g.erase!
end

EQUIP_LABELS.each_key do |id|
  g = ents.grep(Sketchup::Group).find { |x| x.name == id && (x.parent == model || x.parent == root) }
  next unless g
  next if g.parent == root
  inst = root.entities.add_instance(g.to_component, g.transformation)
  inst.name = id
  g.erase!
  $EQUIP[id] = bounds_hash(inst)
end

# ---------- 中文标签 ----------
ents.grep(Sketchup::Group).each do |g|
  g.erase! if g.name == 'EQUIP-LABELS' && g.parent == root
end
labels_g = root.entities.add_group
labels_g.name = 'EQUIP-LABELS'
labels_g.layer = model.layers['A2-MEP-LABEL']

EQUIP_LABELS.each do |id, text|
  e = $EQUIP[id]
  next unless e
  z_label = e[:z1] + (e[:z1] > 50 ? 4.0 : 3.0)
  t = labels_g.entities.add_text(text, [e[:cx], e[:cy], z_label])
  t.layer = model.layers['A2-MEP-LABEL']
  leader = labels_g.entities.add_line([e[:cx], e[:cy], e[:z1]], [e[:cx], e[:cy], z_label - 0.5])
  leader.layer = model.layers['A2-MEP-LABEL']
end

# ---------- 重建 PIPES ----------
root.entities.grep(Sketchup::Group).each { |g| g.erase! if g.name == 'PIPES' }
pipes = root.entities.add_group
pipes.name = 'PIPES'

cab = $EQUIP['cabinet']
dhw = $EQUIP['dhw']
ac  = $EQUIP['ac_hp']
man = $EQUIP['fh_manifold']

cab_top = port(cab, :top)
dhw_p = port(dhw, :south)
ac_p  = port(ac, :north)

# 软水冷水
cold_pts = route(
  *riser(Z_COLD, cab_top[2], [cab_top[0], cab_top[1]]),
  [cab_top[0], cab_top[1], Z_COLD],
  [cab_top[0], 74.0, Z_COLD],
  [port($EQUIP['ro'], :west)[0], 74.0, Z_COLD],
  *riser(Z_COLD, port($EQUIP['ro'], :top)[2], [port($EQUIP['ro'], :top)[0], port($EQUIP['ro'], :top)[1]]),
  [cab_top[0], 50.0, Z_COLD],
  [218.0, 50.0, Z_COLD],
  *riser(Z_COLD, 76.0, [218.0, 76.0]),
  [218.0, 50.0, Z_COLD],
  [442.0, 50.0, Z_COLD],
  *riser(Z_COLD, port($EQUIP['dhw_boost'], :south)[2], [442.0, 74.0]),
  [472.0, 50.0, Z_COLD],
  [472.0, 148.0, Z_COLD],
  [28.0, 148.0, Z_COLD],
  [28.0, 306.0, Z_COLD],
  *riser(Z_COLD, port($EQUIP['washer'], :west)[2], [port($EQUIP['washer'], :west)[0], port($EQUIP['washer'], :west)[1]]),
  *riser(Z_COLD, port($EQUIP['robot'], :west)[2], [port($EQUIP['robot'], :west)[0], port($EQUIP['robot'], :west)[1]])
)
add_pipe_run(pipes, 'A2-MEP-SOFT-COLD', cold_pts, '软水冷水')

# 生活热水
hot_pts = route(
  *riser(Z_HOT, dhw_p[2], [dhw_p[0], dhw_p[1]]),
  [277.0, 42.0, Z_HOT],
  [218.0, 42.0, Z_HOT],
  *riser(Z_HOT, 76.0, [218.0, 76.0]),
  [port($EQUIP['fp_kitchen'], :south)[0], 42.0, Z_HOT],
  *riser(Z_HOT, port($EQUIP['fp_kitchen'], :south)[2], [port($EQUIP['fp_kitchen'], :south)[0], port($EQUIP['fp_kitchen'], :south)[1]]),
  [442.0, 42.0, Z_HOT],
  *riser(Z_HOT, port($EQUIP['dhw_boost'], :north)[2], [442.0, 74.0]),
  [277.0, 42.0, Z_HOT],
  [277.0, 148.0, Z_HOT],
  [28.0, 148.0, Z_HOT],
  [28.0, 306.0, Z_HOT],
  *riser(Z_HOT, port($EQUIP['washer'], :north)[2], [port($EQUIP['washer'], :north)[0], port($EQUIP['washer'], :north)[1]])
)
add_pipe_run(pipes, 'A2-MEP-HOT', hot_pts, '生活热水')

# 热水回水
ret_pts = route(
  *riser(Z_RET, port($EQUIP['dhw_boost'], :east)[2], [448.0, 74.0]),
  [277.0, 38.0, Z_RET],
  *riser(Z_RET, dhw_p[2], [277.0, 25.0])
)
add_pipe_run(pipes, 'A2-MEP-HOT-RETURN', ret_pts, '热水回水')

# 空调水 → 5台 FP
ac_pts = route(
  *riser(Z_AC, ac_p[2], [ac_p[0], ac_p[1]]),
  [277.0, 132.0, Z_AC],
  [port($EQUIP['fp_living'], :west)[0], 132.0, Z_AC],
  *riser(Z_AC, port($EQUIP['fp_living'], :west)[2], [port($EQUIP['fp_living'], :west)[0], port($EQUIP['fp_living'], :cy]]),
  [port($EQUIP['fp_bed2'], :west)[0], 132.0, Z_AC],
  *riser(Z_AC, port($EQUIP['fp_bed2'], :west)[2], [port($EQUIP['fp_bed2'], :west)[0], port($EQUIP['fp_bed2'], :cy]]),
  [port($EQUIP['fp_master'], :east)[0], 132.0, Z_AC],
  *riser(Z_AC, port($EQUIP['fp_master'], :east)[2], [port($EQUIP['fp_master'], :east)[0], port($EQUIP['fp_master'], :cy]]),
  [port($EQUIP['fp_study'], :east)[0], 132.0, Z_AC],
  *riser(Z_AC, port($EQUIP['fp_study'], :east)[2], [port($EQUIP['fp_study'], :east)[0], port($EQUIP['fp_study'], :cy]]),
  [port($EQUIP['fp_kitchen'], :north)[0], 132.0, Z_AC],
  *riser(Z_AC, port($EQUIP['fp_kitchen'], :north)[2], [port($EQUIP['fp_kitchen'], :north)[0], port($EQUIP['fp_kitchen'], :cy]]),
  [277.0, 132.0, Z_AC],
  *riser(Z_AC, ac_p[2], [ac_p[0], ac_p[1]])
)
add_pipe_run(pipes, 'A2-MEP-AC-WATER', ac_pts, '空调水')

# 地暖
man_e = port(man, :east)
fh_from = [man_e[0], man_e[1], Z_FH]
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', route(fh_from, [280.0, 18.0, Z_FH], [280.0, 148.0, Z_FH], [120.0, 148.0, Z_FH], [120.0, 250.0, Z_FH]), '地暖L1')
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', route(fh_from, [360.0, 18.0, Z_FH], [360.0, 148.0, Z_FH], [360.0, 250.0, Z_FH]), '地暖L2')
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', route(fh_from, [180.0, 18.0, Z_FH], [180.0, 80.0, Z_FH], [80.0, 80.0, Z_FH], [80.0, 148.0, Z_FH]), '地暖L3')
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', route(fh_from, [400.0, 18.0, Z_FH], [400.0, 80.0, Z_FH], [40.0, 80.0, Z_FH], [40.0, 250.0, Z_FH], [40.0, 330.0, Z_FH]), '地暖L4')
add_pipe_run(pipes, 'A2-MEP-AC-WATER', route([ac[:x1], ac[:cy], ac[:cz]], [man[:x0], man[:cy], man[:z1]], [man_e[0], man_e[1], Z_FH + 1]), '两联供→分集水器')

# RO
ro_pts = route(
  *riser(97.0, port($EQUIP['ro'], :top)[2], [port($EQUIP['ro'], :top)[0], port($EQUIP['ro'], :top)[1]]),
  [port($EQUIP['ro'], :top)[0], 82.0, 97.0],
  [port($EQUIP['pipeline'], :west)[0], 82.0, 97.0],
  *riser(97.0, port($EQUIP['pipeline'], :west)[2], [port($EQUIP['pipeline'], :west)[0], port($EQUIP['pipeline'], :cy]])
)
add_pipe_run(pipes, 'A2-MEP-RO', ro_pts, 'RO纯水')

# 导出坐标 JSON 到属性
positions = $EQUIP.transform_values do |e|
  { x0: e[:x0].round(2), x1: e[:x1].round(2), y0: e[:y0].round(2), y1: e[:y1].round(2),
    z0: e[:z0].round(2), z1: e[:z1].round(2), cx: e[:cx].round(2), cy: e[:cy].round(2) }
end
root.set_attribute('A2', 'equip_positions', positions.to_json)

model.commit_operation
{
  success: true,
  version: 'v04',
  labels: EQUIP_LABELS.length,
  positions: positions,
  message: '已更新标签、重组层级、重建管线路由'
}.to_json
