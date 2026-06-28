# -*- coding: utf-8 -*-
# A2-MEP-WATER-HVAC v3
# · 冷水/热水/回水/空调水/地暖/RO 分色分高
# · 设备带接管口，管从设备引出
# · 两联供 [A] 与生活热水 [B] 南向设备带上下叠放

model = Sketchup.active_model
model.start_operation('A2 MEP Water HVAC v3', true)

Z_FL = 0.4
Z_EQ = 2.0
Z_COLD  = 105.0   # 软水冷水（吊顶）
Z_HOT   = 103.0   # 生活热水
Z_RET   = 101.0   # 热水回水
Z_AC    = 108.0   # 空调冷热水
Z_FH    = 2.8     # 地暖（地面层）
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
  'A2-MEP-SOFT-COLD' => [20, 100, 255],      # 冷水 蓝
  'A2-MEP-HOT' => [230, 30, 30],             # 热水 红
  'A2-MEP-HOT-RETURN' => [255, 120, 0],     # 回水 橙
  'A2-MEP-AC-WATER' => [30, 170, 90],        # 空调水 绿
  'A2-MEP-FLOOR-HEAT' => [140, 60, 180],     # 地暖 紫
  'A2-MEP-RO' => [200, 60, 200],
  'A2-MEP-FLOOR-L1' => [255, 200, 100],
  'A2-MEP-FLOOR-L2' => [100, 200, 255],
  'A2-MEP-FLOOR-L3' => [100, 255, 150],
  'A2-MEP-FLOOR-L4' => [255, 150, 200],
  'A2-MEP-LABEL' => [20, 20, 20]
}

LAYER_COLORS.each do |name, rgb|
  model.layers.add(name) unless model.layers[name]
  mat = model.materials["A2_MEP_#{name}"] || model.materials.add("A2_MEP_#{name}")
  mat.color = Sketchup::Color.new(*rgb)
end

$EQUIP = {}

def mat_for(model, layer)
  model.materials["A2_MEP_#{layer}"]
end

model.active_entities.to_a.each do |e|
  next unless e.is_a?(Sketchup::Group) && e.name == 'A2-MEP-WATER-HVAC'
  e.erase!
end

root = model.active_entities.add_group
root.name = 'A2-MEP-WATER-HVAC'
root.set_attribute('A2', 'version', '20260628_v03')

def add_label(parent, text, x, y, z)
  t = parent.entities.add_text(text, [x, y, z])
  t.layer = Sketchup.active_model.layers['A2-MEP-LABEL']
rescue
  nil
end

def reg_equip(id, x0, y0, x1, y1, z0, z1)
  $EQUIP[id] = {
    x0: x0, y0: y0, x1: x1, y1: y1, z0: z0, z1: z1,
    cx: (x0 + x1) / 2.0, cy: (y0 + y1) / 2.0,
    top: z1, north: y1, south: y0, east: x1, west: x0
  }
end

def port(id, face)
  e = $EQUIP[id]
  case face
  when :top then [e[:cx], e[:cy], e[:top]]
  when :north then [e[:cx], e[:north], e[:top] * 0.6]
  when :south then [e[:cx], e[:south], e[:top] * 0.6]
  when :east then [e[:east], e[:cy], e[:top] * 0.6]
  when :west then [e[:west], e[:cy], e[:top] * 0.6]
  end
end

def add_box(parent, layer, id, x0, y0, x1, y1, z0, z1, label=nil)
  g = parent.entities.add_group
  g.name = id.to_s
  g.layer = Sketchup.active_model.layers[layer]
  pts = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]]
  face = g.entities.add_face(pts)
  face.reverse! if face.normal.z < 0
  face.pushpull(z1 - z0)
  g.material = mat_for(Sketchup.active_model, layer)
  reg_equip(id, x0, y0, x1, y1, z0, z1)
  add_label(parent, label, (x0 + x1) / 2.0, (y0 + y1) / 2.0, z1 + 2.5) if label
  g
end

def add_floor(parent, layer, x0, y0, x1, y1, label)
  g = parent.entities.add_group
  g.layer = Sketchup.active_model.layers[layer]
  pts = [[x0, y0, Z_FL], [x1, y0, Z_FL], [x1, y1, Z_FL], [x0, y1, Z_FL]]
  face = g.entities.add_face(pts)
  face.reverse! if face.normal.z < 0
  m = mat_for(Sketchup.active_model, layer)
  g.material = m
  m.alpha = 0.32 if m.respond_to?(:alpha=)
  add_label(parent, label, (x0 + x1) / 2.0, (y0 + y1) / 2.0, Z_FL + 1.2)
  g
end

def dedupe_run(pts)
  out = []
  pts.each do |p|
    out << p if out.empty? || out.last != p
  end
  out
end

def add_pipe_run(parent, layer, points, label=nil)
  pts = dedupe_run(points)
  return nil if pts.length < 2
  g = parent.entities.add_group
  g.name = label if label
  g.layer = Sketchup.active_model.layers[layer]
  m = mat_for(Sketchup.active_model, layer)
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

# 设备 → 吊顶：竖向引上/引下
def riser(z_ceil, z_equip, xy, layer)
  x, y = xy
  [[x, y, z_equip], [x, y, z_ceil]]
end

def route(*pts); pts; end

equip = root.entities.add_group
equip.name = 'EQUIPMENT'

# ===== 设备坐标（20260628 现场调整版 · 见 20260628_MEP设备位置.csv）=====
add_box(equip, 'A2-MEP-EQUIP', :cabinet, 82.0, 62.0, 118.0, 92.0, 2.0, 20.0,
        '水柜·前置+中净+中软')

# 两空气能：Z 向上下叠放（下 [A] 两联供，上 [B] 生活热水）
add_box(equip, 'A2-MEP-EQUIP', :ac_hp, 260.4, 21.08, 294.4, 32.08, 77.28, 89.28,
        '[A] 两联供+缓冲(下)')
add_box(equip, 'A2-MEP-EQUIP', :dhw, 260.4, 21.08, 294.4, 30.08, 89.28, 101.28,
        '[B] 生活热水(上)')
add_box(equip, 'A2-MEP-EQUIP', :fh_manifold, 262.44, 13.08, 287.44, 30.08, 46.42, 54.42,
        '地暖分集水器')

add_box(equip, 'A2-MEP-EQUIP', :ro, 108.0, 70.0, 118.0, 78.0, 2.0, 8.0, 'RO纯水·厨下')
add_box(equip, 'A2-MEP-EQUIP', :pipeline, 177.51, 71.41, 189.51, 85.41, 73.44, 83.44, '管线机')
add_box(equip, 'A2-MEP-EQUIP', :dhw_boost, 438.0, 70.0, 450.0, 78.0, 2.0, 6.0, '主卫小厨宝')
add_box(equip, 'A2-MEP-EQUIP', :washer, 24.0, 300.0, 40.0, 312.0, 2.0, 10.0, '洗衣机')
add_box(equip, 'A2-MEP-EQUIP', :robot, 42.0, 300.0, 58.0, 312.0, 2.0, 9.0, '扫地机·上下水')

add_box(equip, 'A2-MEP-EQUIP', :fp_living,  217.44, 247.21, 229.44, 264.21, 98.17, 114.17, 'FP·客厅')
add_box(equip, 'A2-MEP-EQUIP', :fp_bed2,   237.31, 234.93, 249.31, 251.93, 98.17, 114.17, 'FP·次卧')
add_box(equip, 'A2-MEP-EQUIP', :fp_master, 354.56, 236.8, 366.56, 253.8, 98.17, 114.17, 'FP·主卧')
add_box(equip, 'A2-MEP-EQUIP', :fp_study,  304.95, 78.44, 316.95, 95.44, 98.17, 114.17, 'FP·书房')
add_box(equip, 'A2-MEP-EQUIP', :fp_kitchen, 177.51, 84.54, 189.51, 96.54, 98.17, 114.17, 'FP·厨房')

# ===== 地暖色块 =====
floor_g = root.entities.add_group
floor_g.name = 'FLOOR-HEATING-ZONES'
add_floor(floor_g, 'A2-MEP-FLOOR-L1', 20.0, Y_SPLIT + 2, 226.0, 306.0, 'L1 客厅')
add_floor(floor_g, 'A2-MEP-FLOOR-L2', 234.0, Y_SPLIT + 2, 472.0, 306.0, 'L2 双卧')
add_floor(floor_g, 'A2-MEP-FLOOR-L3', 20.0, 5.0, 226.0, Y_SPLIT - 2, 'L3 玄关厨客卫')
add_floor(floor_g, 'A2-MEP-FLOOR-L4', 234.0, 5.0, 472.0, Y_SPLIT - 2, 'L4 书房主卫')
add_floor(floor_g, 'A2-MEP-FLOOR-L4', 20.0, Y_SPLIT + 2, 86.0, 306.0, 'L4 衣帽间')
add_floor(floor_g, 'A2-MEP-FLOOR-L4', 20.0, 308.0, 86.0, 350.0, 'L4 洗衣')
add_floor(floor_g, 'A2-MEP-FLOOR-L4', 20.0, 308.0, 472.0, 350.0, 'L4 北阳台')

pipes = root.entities.add_group
pipes.name = 'PIPES'

cab = port(:cabinet, :top)
dhw_p = port(:dhw, :north)
ac_p = port(:ac_hp, :north)
man_p = port(:fh_manifold, :east)

# ===== 软水冷水（蓝 Z=105）从水柜顶引出 =====
cold_pts = route(
  *riser(Z_COLD, cab[2], [cab[0], cab[1]], 'A2-MEP-SOFT-COLD'),
  [cab[0], cab[1], Z_COLD],
  [cab[0], 74.0, Z_COLD],              # → 厨房水槽
  [port(:ro, :west)[0], 74.0, Z_COLD],
  *riser(Z_COLD, port(:ro, :top)[2], [port(:ro, :top)[0], port(:ro, :top)[1]], 'A2-MEP-SOFT-COLD'),
  [cab[0], 74.0, Z_COLD],
  [cab[0], 50.0, Z_COLD],              # 沿玄关南墙
  [218.0, 50.0, Z_COLD],               # → 客卫
  *riser(Z_COLD, port(:fp_study, :south)[2], [218.0, 76.0], 'A2-MEP-SOFT-COLD'),
  [218.0, 50.0, Z_COLD],
  [442.0, 50.0, Z_COLD],               # → 主卫
  *riser(Z_COLD, port(:dhw_boost, :south)[2], [442.0, 74.0], 'A2-MEP-SOFT-COLD'),
  [442.0, 50.0, Z_COLD],
  [472.0, 50.0, Z_COLD],
  [472.0, 148.0, Z_COLD],              # 东墙北上
  [28.0, 148.0, Z_COLD],               # 西向
  [28.0, 306.0, Z_COLD],               # → 洗衣区
  *riser(Z_COLD, port(:washer, :west)[2], [port(:washer, :west)[0], port(:washer, :west)[1]], 'A2-MEP-SOFT-COLD'),
  *riser(Z_COLD, port(:robot, :west)[2], [port(:robot, :west)[0], port(:robot, :west)[1]], 'A2-MEP-SOFT-COLD')
)
add_pipe_run(pipes, 'A2-MEP-SOFT-COLD', cold_pts, '软水冷水')

# ===== 生活热水（红 Z=103）从 [B] 引出 =====
hot_pts = route(
  *riser(Z_HOT, dhw_p[2], [dhw_p[0], dhw_p[1]], 'A2-MEP-HOT'),
  [255.0, 40.0, Z_HOT],                # 设备带出
  [218.0, 40.0, Z_HOT],                # 客卫
  *riser(Z_HOT, 76.0, [218.0, 76.0], 'A2-MEP-HOT'),
  [218.0, 40.0, Z_HOT],
  [113.0, 40.0, Z_HOT],                # 厨房
  *riser(Z_HOT, port(:fp_kitchen, :south)[2], [113.0, 144.0], 'A2-MEP-HOT'),
  [113.0, 40.0, Z_HOT],
  [442.0, 40.0, Z_HOT],                # 主卫（经小厨宝）
  *riser(Z_HOT, port(:dhw_boost, :north)[2], [442.0, 74.0], 'A2-MEP-HOT'),
  [442.0, 40.0, Z_HOT],
  [255.0, 40.0, Z_HOT],
  [255.0, 148.0, Z_HOT],
  [28.0, 148.0, Z_HOT],
  [28.0, 306.0, Z_HOT],
  *riser(Z_HOT, port(:washer, :north)[2], [port(:washer, :north)[0], port(:washer, :north)[1]], 'A2-MEP-HOT')
)
add_pipe_run(pipes, 'A2-MEP-HOT', hot_pts, '生活热水')

# ===== 热水回水（橙 Z=101）主卫 → [B] =====
ret_pts = route(
  *riser(Z_RET, port(:dhw_boost, :east)[2], [448.0, 74.0], 'A2-MEP-HOT-RETURN'),
  [448.0, 38.0, Z_RET],
  [255.0, 38.0, Z_RET],
  *riser(Z_RET, dhw_p[2], [255.0, 11.0], 'A2-MEP-HOT-RETURN')
)
add_pipe_run(pipes, 'A2-MEP-HOT-RETURN', ret_pts, '热水回水')

# ===== 空调水（绿 Z=108）从 [A] 引出 → 5台 FP =====
ac_pts = route(
  *riser(Z_AC, ac_p[2], [ac_p[0], ac_p[1]], 'A2-MEP-AC-WATER'),
  [255.0, 132.0, Z_AC],
  [30.0, 132.0, Z_AC],
  *riser(Z_AC, port(:fp_living, :west)[2], [port(:fp_living, :west)[0], port(:fp_living, :west)[1]], 'A2-MEP-AC-WATER'),
  [30.0, 132.0, Z_AC],
  [30.0, 243.0, Z_AC],
  *riser(Z_AC, port(:fp_living, :south)[2], [port(:fp_living, :south)[0], port(:fp_living, :south)[1]], 'A2-MEP-AC-WATER'),
  [291.0, 243.0, Z_AC],
  *riser(Z_AC, port(:fp_bed2, :west)[2], [port(:fp_bed2, :west)[0], port(:fp_bed2, :west)[1]], 'A2-MEP-AC-WATER'),
  [461.0, 243.0, Z_AC],
  *riser(Z_AC, port(:fp_master, :east)[2], [port(:fp_master, :east)[0], port(:fp_master, :west)[0]], 'A2-MEP-AC-WATER'),
  [354.0, 132.0, Z_AC],
  *riser(Z_AC, port(:fp_study, :east)[2], [port(:fp_study, :east)[0], port(:fp_study, :east)[1]], 'A2-MEP-AC-WATER'),
  [134.0, 132.0, Z_AC],
  *riser(Z_AC, port(:fp_kitchen, :north)[2], [port(:fp_kitchen, :north)[0], port(:fp_kitchen, :north)[1]], 'A2-MEP-AC-WATER'),
  [255.0, 132.0, Z_AC],
  *riser(Z_AC, ac_p[2], [255.0, 18.0], 'A2-MEP-AC-WATER')
)
add_pipe_run(pipes, 'A2-MEP-AC-WATER', ac_pts, '空调水')

# ===== 地暖（紫 Z=2.8 地面）分集水器 → 4 路 =====
fh_from = [man_p[0], man_p[1], Z_FH]
fh_l1 = route(fh_from, [280.0, 18.0, Z_FH], [280.0, 148.0, Z_FH], [120.0, 148.0, Z_FH], [120.0, 250.0, Z_FH])
fh_l2 = route(fh_from, [360.0, 18.0, Z_FH], [360.0, 148.0, Z_FH], [360.0, 250.0, Z_FH])
fh_l3 = route(fh_from, [180.0, 18.0, Z_FH], [180.0, 80.0, Z_FH], [80.0, 80.0, Z_FH], [80.0, 148.0, Z_FH])
fh_l4 = route(fh_from, [400.0, 18.0, Z_FH], [400.0, 80.0, Z_FH], [40.0, 80.0, Z_FH], [40.0, 250.0, Z_FH], [40.0, 330.0, Z_FH])
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', fh_l1, '地暖L1')
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', fh_l2, '地暖L2')
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', fh_l3, '地暖L3')
add_pipe_run(pipes, 'A2-MEP-FLOOR-HEAT', fh_l4, '地暖L4')

# 两联供 → 分集水器（空调侧热水供地暖，地面短管）
add_pipe_run(pipes, 'A2-MEP-AC-WATER', route(
  [272.0, 18.0, Z_EQ + 6], [285.0, 18.0, Z_EQ + 4], [285.0, 14.0, Z_FH + 1]
), '两联供→分集水器')

# ===== RO（粉 Z=97）RO → 管线机 =====
ro_pts = route(
  *riser(97.0, port(:ro, :top)[2], [port(:ro, :top)[0], port(:ro, :top)[1]], 'A2-MEP-RO'),
  [113.0, 82.0, 97.0],
  [113.0, 105.0, 97.0],
  *riser(97.0, port(:pipeline, :west)[2], [port(:pipeline, :west)[0], port(:pipeline, :west)[1]], 'A2-MEP-RO')
)
add_pipe_run(pipes, 'A2-MEP-RO', ro_pts, 'RO纯水')

# ===== 图例（加粗色条 + 说明）=====
legend = root.entities.add_group
legend.name = 'LEGEND'
items = [
  ['冷水(软水)', 'A2-MEP-SOFT-COLD'],
  ['生活热水', 'A2-MEP-HOT'],
  ['热水回水', 'A2-MEP-HOT-RETURN'],
  ['空调水', 'A2-MEP-AC-WATER'],
  ['地暖', 'A2-MEP-FLOOR-HEAT'],
  ['RO纯水', 'A2-MEP-RO']
]
items.each_with_index do |(txt, layer), i|
  y = 346.0 - i * 7.5
  r = PIPE_R[layer] || 0.5
  lg = legend.entities.add_group
  (0...8).each do |k|
    ang = 2.0 * Math::PI * k / 8
    lg.entities.add_line([18 + r * Math.cos(ang), y + r * Math.sin(ang), 3],
                         [26 + r * Math.cos(ang), y + r * Math.sin(ang), 3])
  end
  lg.material = mat_for(model, layer)
  add_label(legend, txt, 30, y - 1.5, 3)
end
add_label(legend, '两空气能：下[B]热水 上[A]两联供', 18, 318, 3)

model.commit_operation
{
  success: true,
  version: 'v03',
  entity_id: root.entityID,
  message: '分色分管+设备接管+空气能上下叠放'
}.to_json
