# -*- coding: utf-8 -*-
# PIPES v5 — 生活水(cabinet起/无回水/RD) + 两联供二次侧(FP5+地暖5路回折盘管)
# 读取设备位置 + mep_topology.json

require 'json'

model = Sketchup.active_model
model.start_operation('Rebuild MEP pipes v5', true)

TOPO_PATH = '/Users/neo/Desktop/cursor_project/rongchuang/融创大观-3D/模型/全屋/方案推敲/mep_topology.json'
TOPO = JSON.parse(File.read(TOPO_PATH))

Z_COLD = TOPO['z_layers']['soft_cold']
Z_HOT  = TOPO['z_layers']['hot']
Z_AC_S = TOPO['z_layers']['ac_supply']
Z_AC_R = TOPO['z_layers']['ac_return']
Z_FH   = TOPO['z_layers']['floor_coil']
Z_RO   = TOPO['z_layers']['ro']
TRUNK_Y_S = TOPO['trunk']['south_y']
TRUNK_Y_N = TOPO['trunk']['north_y']
TRUNK_X_W = TOPO['trunk']['west_x']

PIPE_R = {
  'A2-MEP-SOFT-COLD' => 0.65,
  'A2-MEP-HOT' => 0.70,
  'A2-MEP-AC-WATER' => 0.60,
  'A2-MEP-FLOOR-HEAT' => 0.45,
  'A2-MEP-RO' => 0.35
}

LAYER_RGB = {
  'A2-MEP-SOFT-COLD' => [20, 100, 255],
  'A2-MEP-HOT' => [230, 30, 30],
  'A2-MEP-AC-WATER' => [30, 170, 90],
  'A2-MEP-FLOOR-HEAT' => [140, 60, 180],
  'A2-MEP-RO' => [200, 60, 200]
}

LAYER_RGB.each_key do |n|
  model.layers.add(n) unless model.layers[n]
  mat = model.materials["A2_MEP_#{n}"] || model.materials.add("A2_MEP_#{n}")
  mat.color = Sketchup::Color.new(*LAYER_RGB[n])
end

ENGLISH_IDS = %w[cabinet dhw ac_hp fh_manifold ro pipeline dhw_boost washer robot
                 fp_living fp_bed2 fp_master fp_study fp_kitchen].freeze

NAME_TO_ID = {
  'cabinet' => /\A(水柜|cabinet)/,
  'dhw' => /(\[B\].*生活热水|生活热水|^dhw$)/,
  'ac_hp' => /(\[A\].*两联供|两联供|^ac_hp$)/,
  'fh_manifold' => /\A(地暖|fh_manifold)/,
  'ro' => /\A(RO|^ro$)/,
  'pipeline' => /\A(管线机|pipeline)/,
  'dhw_boost' => /\A(主卫|dhw_boost)/,
  'washer' => /\A(洗衣机|washer)\z/,
  'robot' => /\A(扫地机|robot)/,
  'fp_living' => /(FP.*客厅|fp_living)/,
  'fp_bed2' => /(FP.*次卧|fp_bed2)/,
  'fp_master' => /(FP.*主卧|fp_master)/,
  'fp_study' => /(FP.*书房|fp_study)/,
  'fp_kitchen' => /(FP.*厨房|fp_kitchen)/
}.freeze

def mat_for(mdl, layer)
  mdl.materials["A2_MEP_#{layer}"] || mdl.materials.add("A2_MEP_#{layer}")
end

def resolve_id(name)
  n = name.to_s
  return n if ENGLISH_IDS.include?(n)
  NAME_TO_ID.each { |id, re| return id if n.match?(re) }
  nil
end

def collect_groups(entities, out)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group)
    out << e
    collect_groups(e.entities, out)
  end
end

def load_equip(mdl)
  h = {}
  collect_groups(mdl.active_entities, groups = [])
  groups.each do |g|
    id = resolve_id(g.name)
    next unless id && !h.key?(id)
    b = g.bounds
    h[id] = {
      cx: (b.min.x + b.max.x) / 2.0, cy: (b.min.y + b.max.y) / 2.0,
      x0: b.min.x, x1: b.max.x, y0: b.min.y, y1: b.max.y, z0: b.min.z, z1: b.max.z
    }
  end
  h
end

def pt(e, face)
  case face
  when :top then [e[:cx], e[:cy], e[:z1]]
  when :north then [e[:cx], e[:y1], e[:z1]]
  when :south then [e[:cx], e[:y0], e[:z0] + 1.0]
  when :east then [e[:x1], e[:cy], e[:z1]]
  when :west then [e[:x0], e[:cy], e[:z1]]
  end
end

def dedupe(pts)
  out = []
  pts.each { |p| out << p if out.empty? || out.last != p }
  out
end

def ortho_waypoints(a, b)
  ax, ay, az = a.map(&:to_f)
  bx, by, bz = b.map(&:to_f)
  return [] if [ax, ay, az] == [bx, by, bz]
  wps = []
  if bz > az + 0.01
    wps << [ax, ay, bz] if (az - bz).abs > 0.01
    wps << [bx, ay, bz] if (ax - bx).abs > 0.01
    wps << [bx, by, bz] if (ay - by).abs > 0.01
  else
    wps << [bx, ay, az] if (ax - bx).abs > 0.01
    wps << [bx, by, az] if (ay - by).abs > 0.01
    wps << [bx, by, bz] if (az - bz).abs > 0.01
  end
  wps
end

def expand_ortho(pts)
  flat = dedupe(pts)
  return flat if flat.length < 2
  out = [flat[0]]
  flat.each_cons(2) do |a, b|
    ortho_waypoints(a, b).each { |wp| out << wp if out.last != wp }
    out << b if out.last != b
  end
  dedupe(out)
end

def pipe_run(parent, layer, points, label = nil)
  pts = expand_ortho(points)
  return if pts.length < 2
  mdl = Sketchup.active_model
  g = parent.entities.add_group
  g.name = label if label
  g.layer = mdl.layers[layer]
  m = mat_for(mdl, layer)
  r = PIPE_R[layer] || 0.5
  pts.each_cons(2) do |a, b|
    ax, ay, az = a.map(&:to_f)
    bx, by, bz = b.map(&:to_f)
    non = [(ax - bx).abs, (ay - by).abs, (az - bz).abs].count { |d| d > 0.01 }
    raise "diagonal segment in #{label}: #{a} -> #{b}" if non > 1
    a = Geom::Point3d.new(*a)
    b = Geom::Point3d.new(*b)
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
end

def sub_group(parent, name)
  g = parent.entities.add_group
  g.name = name
  g
end

def riser(z_hi, z_lo, x, y)
  [[x, y, z_lo], [x, y, z_hi]]
end

# 回折型盘管示意（方案级 5~7 折，非施工图级满铺）
def serpentine_rect(x0, y0, x1, y1, z, spacing, inset)
  xi = x0 + inset
  yi = y0 + inset
  xa = x1 - inset
  ya = y1 - inset
  return [] if xa <= xi || ya <= yi
  width = xa - xi
  n_runs = [[(width / spacing).floor, 7].min, 4].max
  step = width / n_runs
  pts = []
  n_runs.times do |i|
    x = xi + step * i + step * 0.5
    pts << [x, (i.even? ? yi : ya), z]
    pts << [x, (i.even? ? ya : yi), z]
  end
  pts
end

# 狭长空间平行型（3 根）
def parallel_rect(x0, y0, x1, y1, z, inset, count = 3)
  xi = x0 + inset
  yi = y0 + inset
  xa = x1 - inset
  ya = y1 - inset
  return [] if xa <= xi || ya <= yi
  pts = []
  (0...count).each do |i|
    t = count == 1 ? 0.5 : i.to_f / (count - 1)
    xx = xi + (xa - xi) * t
    pts << [xx, yi, z]
    pts << [xx, ya, z]
  end
  pts
end

def zone_coil(zone, z, spacing, inset)
  x0, y0, x1, y1 = zone['x0'], zone['y0'], zone['x1'], zone['y1']
  pat = zone['pattern'] || 'serpentine'
  pat == 'parallel' ? parallel_rect(x0, y0, x1, y1, z, inset) : serpentine_rect(x0, y0, x1, y1, z, spacing, inset)
end

def trunk_to_zone(man_x, man_y, zone, z)
  cx = (zone['x0'] + zone['x1']) / 2.0
  cy = (zone['y0'] + zone['y1']) / 2.0
  entry_y = zone['y0'] + 4.0
  [[man_x, man_y, z], [cx, man_y, z], [cx, entry_y, z]]
end

def chain_zones(man_x, man_y, zones, z, spacing, inset)
  pts = []
  zones.each_with_index do |zone, idx|
    pts.concat(trunk_to_zone(man_x, man_y, zone, z)) if idx == 0
    pts.concat(zone_coil(zone, z, spacing, inset))
    next unless idx < zones.length - 1
    nxt = zones[idx + 1]
    pts << [(zone['x0'] + zone['x1']) / 2.0, zone['y1'] - inset, z]
    pts << [(nxt['x0'] + nxt['x1']) / 2.0, zone['y1'] - inset, z]
    pts << [(nxt['x0'] + nxt['x1']) / 2.0, nxt['y0'] + inset, z]
  end
  pts
end

def loop_length(pts)
  len = 0.0
  pts.each_cons(2) { |a, b| len += Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2) }
  len
end

def tree_names(g, depth = 0)
  pad = '  ' * depth
  rows = ["#{pad}#{g.name}"]
  g.entities.grep(Sketchup::Group).each { |c| rows.concat(tree_names(c, depth + 1)) }
  rows
end

# ── 主流程 ──
E = load_equip(model)
missing = ENGLISH_IDS - E.keys
raise "equipment missing: #{missing.join(', ')}" unless missing.empty?

collect_groups(model.active_entities, to_erase = [])
to_erase.each { |g| g.erase! if g.name =~ /\APIPES/ }

pipes = model.active_entities.add_group
pipes.name = 'PIPES'

G_SOFT = sub_group(pipes, '1-生活水·软水冷')
G_HOT  = sub_group(pipes, '2-生活水·热水')
G_RO   = sub_group(pipes, '3-生活水·RO纯水')
G_AC   = sub_group(pipes, '4-两联供·空调水')
G_FH   = sub_group(pipes, '5-两联供·地暖')

cab = E['cabinet']
dhw = E['dhw']
ac  = E['ac_hp']
man = E['fh_manifold']
boost = E['dhw_boost']

# ① 软水：cabinet.OUT → 主管 → RD + ro.IN
soft_pts = [pt(cab, :top), [cab[:cx], cab[:cy], Z_COLD], [cab[:cx], TRUNK_Y_S, Z_COLD]]
TOPO['room_drops'].each do |rd|
  next unless rd['cold']
  soft_pts << [rd['x'], TRUNK_Y_S, Z_COLD]
  soft_pts.concat(riser(Z_COLD, rd['z_riser'], rd['x'], rd['y']))
  soft_pts << [rd['x'], TRUNK_Y_S, Z_COLD]
end
soft_pts << [E['ro'][:cx], TRUNK_Y_S, Z_COLD]
soft_pts.concat(riser(Z_COLD, pt(E['ro'], :top)[2], E['ro'][:cx], E['ro'][:cy]))
pipe_run(G_SOFT, 'A2-MEP-SOFT-COLD', soft_pts, '软水主管+RD')

# ② 热水：dhw.OUT → 主管 → RD（主卫经小厨宝）
hot_pts = [pt(dhw, :south), [dhw[:cx], TRUNK_Y_S, Z_HOT], [dhw[:cx], TRUNK_Y_S + 2, Z_HOT]]
TOPO['room_drops'].each do |rd|
  next unless rd['hot']
  hot_pts << [rd['x'], TRUNK_Y_S + 2, Z_HOT]
  if rd['via_boost']
    hot_pts << pt(boost, :south)
    hot_pts << pt(boost, :north)
  end
  hot_pts.concat(riser(Z_HOT, rd['z_riser'], rd['x'], rd['y']))
  hot_pts << [rd['x'], TRUNK_Y_S + 2, Z_HOT]
end
pipe_run(G_HOT, 'A2-MEP-HOT', hot_pts, '热水主管+RD')

# ③ RO 纯水
pipe_run(G_RO, 'A2-MEP-RO', [
  *riser(Z_RO, pt(E['ro'], :top)[2], E['ro'][:cx], E['ro'][:cy]),
  [E['ro'][:cx], 82, Z_RO],
  [E['pipeline'][:x0], 82, Z_RO],
  *riser(Z_RO, pt(E['pipeline'], :west)[2], E['pipeline'][:x0], E['pipeline'][:cy])
], 'RO→管线机')

# ④ 两联供二次侧 → FP×5 并联供回
fp_order = TOPO['ac_loops'].map { |x| x['fp'] }
ac_sup = [pt(ac, :north), [ac[:cx], TRUNK_Y_N, Z_AC_S]]
ac_ret = []
fp_order.each do |fp_id|
  fp = E[fp_id]
  side = fp[:cx] < 250 ? :west : :east
  sx = side == :west ? fp[:x0] : fp[:x1]
  ac_sup << [sx, TRUNK_Y_N, Z_AC_S]
  ac_sup.concat(riser(Z_AC_S, pt(fp, side)[2], sx, fp[:cy]))
  ac_sup << [sx, TRUNK_Y_N, Z_AC_S]
  ac_ret << pt(fp, side)
  ac_ret << [sx, TRUNK_Y_N - 4, Z_AC_R]
end
ac_ret << [ac[:cx], TRUNK_Y_N - 4, Z_AC_R]
ac_ret << pt(ac, :north)
pipe_run(G_AC, 'A2-MEP-AC-WATER', ac_sup, '二次侧·空调供水')
pipe_run(G_AC, 'A2-MEP-AC-WATER', ac_ret, '二次侧·空调回水')

# 二次侧 → 分集水器总口（并联，非串联 FP）
pipe_run(G_AC, 'A2-MEP-AC-WATER', [
  [ac[:x1], ac[:cy], ac[:z0] + 4],
  [man[:x0], man[:cy], man[:z1] + 2]
], '二次侧→分集水器')

# ⑤ 地暖 5 路：干管 + 回折盘管 + 回干管
mx = man[:x1]
my = man[:cy]
fh_lengths = {}

TOPO['floor_loops'].each_with_index do |loop, idx|
  port_dy = idx * 1.2
  man_s = [mx, my - port_dy, Z_FH]
  man_r = [mx - 2.0, my - port_dy, Z_FH]
  loop_g = sub_group(G_FH, "#{loop['id']}·#{loop['label']}")

  zones = loop['zones']
  spacing = loop['spacing']
  inset = loop['inset']

  coil_pts = chain_zones(mx, my - port_dy, zones, Z_FH, spacing, inset)
  full = [man_s] + coil_pts + [man_r]
  fh_lengths[loop['id']] = loop_length(full).round(1)

  pipe_run(loop_g, 'A2-MEP-FLOOR-HEAT', [man_s] + trunk_to_zone(mx, my - port_dy, zones[0], Z_FH), '干管·供') if zones.any?
  pipe_run(loop_g, 'A2-MEP-FLOOR-HEAT', coil_pts, '盘管·回折') unless coil_pts.empty?
  last = zones.last
  cx = (last['x0'] + last['x1']) / 2.0
  pipe_run(loop_g, 'A2-MEP-FLOOR-HEAT', [[cx, last['y1'] - inset, Z_FH], [man_r[0], man_r[1], Z_FH]], '干管·回')
end

model.commit_operation
{
  success: true,
  version: 'pipes_v5',
  message: '生活水+两联供5路空调5路地暖已生成',
  groups: tree_names(pipes),
  floor_loop_lengths_su: fh_lengths,
  note: '盘管长度为SU内部单位；×25≈mm，方案示意非满铺精度'
}.to_json
