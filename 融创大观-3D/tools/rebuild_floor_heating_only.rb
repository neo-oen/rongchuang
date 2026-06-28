# -*- coding: utf-8 -*-
# 地暖 v6：避让墙体，盘管在房间净尺寸内，干管经门洞/过道

require 'json'

FH_FILTER = nil unless defined?(FH_FILTER)

model = Sketchup.active_model
model.start_operation('Floor heating wall-aware', true)

CFG_PATH = '/Users/neo/Desktop/cursor_project/rongchuang/融创大观-3D/模型/全屋/方案推敲/floor_heating.json'
CFG = JSON.parse(File.read(CFG_PATH))

Z_FH = CFG['floor_z']
LAYER = 'A2-MEP-FLOOR-HEAT'
CHASE_Y = CFG['south_chase_y']
PIPE_R = 0.45
SPACING = CFG.dig('coil', 'spacing') || 6.0
INSET = CFG.dig('coil', 'inset') || 4.0
MAX_COLS = CFG.dig('coil', 'max_cols') || 7
COIL_PATTERN = CFG.dig('coil', 'pattern') || 'hui'
FORBIDDEN_TRUNK_ROOMS = CFG['forbidden_trunk_rooms'] || ['客卫']
FORBIDDEN_TRUNK_DOORS = CFG['forbidden_trunk_doors'] || ['厨房_进客卫']

model.layers.add(LAYER) unless model.layers[LAYER]
mat = model.materials["A2_MEP_#{LAYER}"] || model.materials.add("A2_MEP_#{LAYER}")
mat.color = Sketchup::Color.new(140, 60, 180)

def collect_instances(entities, out)
  entities.each do |e|
    out << e if e.is_a?(Sketchup::ComponentInstance) && e.definition.name.to_s =~ /^R\d/
    collect_instances(e.entities, out) if e.respond_to?(:entities)
  end
end

def load_walls(mdl)
  walls = []
  collect_instances(mdl.active_entities, inst = [])
  inst.each do |e|
    b = e.bounds
    walls << { x0: b.min.x, x1: b.max.x, y0: b.min.y, y1: b.max.y, id: e.definition.name.split(' - ').first }
  end
  walls
end

def segment_intersects_rect?(a, b, r, margin = 0.5)
  ax, ay = a[0], a[1]
  bx, by = b[0], b[1]
  rx0, rx1, ry0, ry1 = r[:x0] + margin, r[:x1] - margin, r[:y0] + margin, r[:y1] - margin
  return false if rx1 <= rx0 || ry1 <= ry0
  if (ax - bx).abs < 0.01
    x = ax
    return false if x < rx0 || x > rx1
    y_min, y_max = [ay, by].min, [ay, by].max
    return y_max > ry0 && y_min < ry1
  end
  if (ay - by).abs < 0.01
    y = ay
    return false if y < ry0 || y > ry1
    x_min, x_max = [ax, bx].min, [ax, bx].max
    return x_max > rx0 && x_min < rx1
  end
  false
end

def near_door?(pt, doors, tol = 6.0)
  doors.any? { |d| (pt[0] - d['x']).abs <= tol && (pt[1] - d['y']).abs <= tol }
end

def segment_in_rect?(a, b, rect, margin = 0.5)
  rx0 = rect['x0'] + margin
  rx1 = rect['x1'] - margin
  ry0 = rect['y0'] + margin
  ry1 = rect['y1'] - margin
  return false if rx1 <= rx0 || ry1 <= ry0
  ax, ay = a[0], a[1]
  bx, by = b[0], b[1]
  if (ax - bx).abs < 0.01
    x = ax
    return false if x < rx0 || x > rx1
    y_min, y_max = [ay, by].min, [ay, by].max
    return y_max > ry0 && y_min < ry1
  end
  if (ay - by).abs < 0.01
    y = ay
    return false if y < ry0 || y > ry1
    x_min, x_max = [ax, bx].min, [ax, bx].max
    return x_max > rx0 && x_min < rx1
  end
  false
end

def doors_for_loop(loop_id, door_map)
  forbidden = FORBIDDEN_TRUNK_DOORS
  forbidden = [] if loop_id == 'FH5'
  vals = door_map.values
  forbidden.each do |key|
    d = door_map[key]
    vals = vals.reject { |v| v['x'] == d['x'] && v['y'] == d['y'] } if d
  end
  vals
end

def trunk_segment_allowed?(a, b, walls, doors, loop_id, rooms)
  return false unless segment_allowed?(a, b, walls, doors)
  return true if loop_id == 'FH5'
  FORBIDDEN_TRUNK_ROOMS.each do |name|
    rect = rooms[name]
    next unless rect
    return false if segment_in_rect?(a, b, rect)
  end
  true
end

def segment_allowed?(a, b, walls, doors)
  az = a[2].to_f
  bz = b[2].to_f
  return true if (az - Z_FH).abs > 1.0 && (bz - Z_FH).abs > 1.0
  walls.each do |w|
    next unless segment_intersects_rect?(a, b, w)
    mid = [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, Z_FH]
    return false unless near_door?(a, doors) || near_door?(b, doors) || near_door?(mid, doors)
  end
  true
end

def collect_groups(entities, out)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group)
    out << e
    collect_groups(e.entities, out)
  end
end

def find_manifold(mdl)
  collect_groups(mdl.active_entities, gs = [])
  g = gs.find { |x| x.name.to_s.match?(/\A(地暖|fh_manifold)/) }
  raise 'fh_manifold not found' unless g
  b = g.bounds
  { cx: (b.min.x + b.max.x) / 2.0, cy: (b.min.y + b.max.y) / 2.0, x0: b.min.x, x1: b.max.x, y0: b.min.y, y1: b.max.y, z0: b.min.z, z1: b.max.z }
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

def validate_path(pts, walls, doors, label, loop_id: nil, rooms: nil, trunk: false)
  pts.each_cons(2) do |a, b|
    ax, ay, az = a.map(&:to_f)
    bx, by, bz = b.map(&:to_f)
    non = [(ax - bx).abs, (ay - by).abs, (az - bz).abs].count { |d| d > 0.01 }
    raise "diagonal in #{label}" if non > 1
    ok = if trunk && loop_id && rooms
           trunk_segment_allowed?(a, b, walls, doors, loop_id, rooms)
         else
           segment_allowed?(a, b, walls, doors)
         end
    raise "穿墙: #{label} #{a} -> #{b}" unless ok
  end
end

def draw_pipe_seg(ents, x0, y0, x1, y1, z, mat, walls, doors)
  return 0 if (x0 - x1).abs < 0.03 && (y0 - y1).abs < 0.03
  raise "diagonal seg [#{x0},#{y0}] -> [#{x1},#{y1}]" if (x0 - x1).abs > 0.01 && (y0 - y1).abs > 0.01
  a = [x0.to_f, y0.to_f, z.to_f]
  b = [x1.to_f, y1.to_f, z.to_f]
  return 0 unless segment_allowed?(a, b, walls, doors)
  pa = Geom::Point3d.new(*a)
  pb = Geom::Point3d.new(*b)
  vec = pb - pa
  len = vec.length
  return 0 if len < 0.03
  vec.normalize!
  up = Geom::Vector3d.new(0, 0, 1)
  vr = vec.cross(up)
  vr = Geom::Vector3d.new(1, 0, 0).cross(vec) if vr.length < 0.001
  vr.normalize!
  vt = vec.cross(vr)
  vt.normalize!
  circle = (0...8).map do |k|
    ang = 2.0 * Math::PI * k / 8
    o1 = vr.clone; o1.length = PIPE_R * Math.cos(ang)
    o2 = vt.clone; o2.length = PIPE_R * Math.sin(ang)
    pa.offset(o1).offset(o2)
  end
  face = ents.add_face(circle)
  return 0 unless face
  face.reverse! if face.normal.dot(vec) < 0
  face.pushpull(len)
  ents.each { |e| e.material = mat if e.respond_to?(:material=) }
  1
end

def draw_segments(parent, segments, label, walls, doors, return_pipe: false)
  return 0 if segments.empty?
  mdl = Sketchup.active_model
  g = parent.entities.add_group
  g.name = label
  g.layer = mdl.layers[LAYER]
  m = mdl.materials["A2_MEP_#{LAYER}"]
  if return_pipe
    rk = "A2_MEP_#{LAYER}_RETURN"
    m = mdl.materials[rk] || mdl.materials.add(rk)
    m.color = Sketchup::Color.new(70, 120, 210)
  end
  n = segments.sum { |s| draw_pipe_seg(g.entities, s[0], s[1], s[2], s[3], Z_FH, m, walls, doors) }
  g.material = m
  n
end

def coil_segments_in_room(room, entry_pt)
  xi = room['x0'] + INSET
  yi = room['y0'] + INSET
  xa = room['x1'] - INSET
  ya = room['y1'] - INSET
  d = SPACING
  return { supply: [], return: [] } if xa - xi < 2 * d || ya - yi < 4 * d

  door_x, door_y = entry_pt[0], entry_pt[1]
  x_lo = xi + d
  x_hi = xa - d
  segs_sup = []
  segs_ret = []

  ys0 = yi + d
  yr0 = ys0 + d

  # 入口：双管平行（外管=供，内管=回，间距 d）
  segs_sup << [door_x, door_y, door_x, ys0]
  segs_ret << [door_x, door_y, door_x, yr0]

  rows = []
  east = true
  ys = ys0
  loop do
    yr = ys + d
    break if yr > ya - d + 0.01

    rows << { ys: ys, yr: yr, east: east }
    if east
      x0 = ys == ys0 ? door_x : x_lo
      segs_sup << [x0, ys, x_hi, ys]
      segs_ret << [x0, yr, x_hi, yr]
      wall = x_hi
    else
      segs_sup << [x_hi, ys, x_lo, ys]
      segs_ret << [x_hi, yr, x_lo, yr]
      wall = x_lo
    end

    ys_next = ys + 2 * d
    break if ys_next + d > ya - d + 0.01

    segs_sup << [wall, ys, wall, ys_next]
    segs_ret << [wall, yr, wall, ys_next + d]
    ys = ys_next
    east = !east
  end

  # 回程：平行双管沿各行反向蛇形回入口
  rows.reverse.each_with_index do |row, idx|
    ys = row[:ys]
    yr = row[:yr]
    to_door = idx == rows.length - 1
    if row[:east]
      x1 = to_door ? door_x : x_lo
      segs_sup << [x_hi, ys, x1, ys]
      segs_ret << [x_hi, yr, x1, yr]
    else
      x1 = to_door ? door_x : x_hi
      segs_sup << [x_lo, ys, x1, ys]
      segs_ret << [x_lo, yr, x1, yr]
    end
  end

  segs_sup << [door_x, ys0, door_x, door_y]
  segs_ret << [door_x, yr0, door_x, door_y]

  { supply: segs_sup, return: segs_ret }
end

def pipe_run(parent, points, label, walls, doors, loop_id: nil, rooms: nil, trunk: false)
  pts = expand_ortho(points)
  return if pts.length < 2
  validate_path(pts, walls, doors, label, loop_id: loop_id, rooms: rooms, trunk: trunk)
  mdl = Sketchup.active_model
  g = parent.entities.add_group
  g.name = label
  g.layer = mdl.layers[LAYER]
  m = mdl.materials["A2_MEP_#{LAYER}"]
  if label.include?('回') && !label.include?('干管')
    rk = "A2_MEP_#{LAYER}_RETURN"
    m = mdl.materials[rk] || mdl.materials.add(rk)
    m.color = Sketchup::Color.new(70, 120, 210)
  end
  pts.each_cons(2) do |a, b|
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
      o1 = vr.clone; o1.length = PIPE_R * Math.cos(ang)
      o2 = vt.clone; o2.length = PIPE_R * Math.sin(ang)
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

def room_rect(name, rooms)
  r = rooms[name]
  raise "room missing: #{name}" unless r
  r
end

def pt_add(pts, pt)
  pts << pt if pts.empty? || pts.last != pt
end

def bridge_to(pts, x, y, z)
  lx, ly = pts.last[0], pts.last[1]
  return if (lx - x).abs < 0.01 && (ly - y).abs < 0.01
  append_to(pts, x, ly, z) if (lx - x).abs > 0.01
  append_to(pts, x, y, z) if (ly - y).abs > 0.01
end

def append_to(pts, x, y, z)
  raise "diagonal step #{pts.last} -> [#{x}, #{y}]" if !pts.empty? && (pts.last[0] - x).abs > 0.01 && (pts.last[1] - y).abs > 0.01
  pt = [x.to_f, y.to_f, z.to_f]
  pt_add(pts, pt)
end

def seg_cross2d?(a, b, c, d)
  ax, ay = a[0], a[1]
  bx, by = b[0], b[1]
  cx, cy = c[0], c[1]
  dx, dy = d[0], d[1]
  return false if [a, b].include?(c) || [a, b].include?(d)
  return false if (ax - bx).abs < 0.01 && (cx - dx).abs < 0.01 && (ax - cx).abs < 0.01
  return false if (ay - by).abs < 0.01 && (cy - dy).abs < 0.01 && (ay - cy).abs < 0.01
  o = ->(p, q, r) { (q[0] - p[0]) * (r[1] - q[1]) - (q[1] - p[1]) * (r[0] - q[0]) }
  o1 = o.call(a, b, c)
  o2 = o.call(a, b, d)
  o3 = o.call(c, d, a)
  o4 = o.call(c, d, b)
  o1 * o2 < 0 && o3 * o4 < 0
end

def path_self_cross?(pts)
  segs = pts.each_cons(2).to_a
  segs.each_with_index do |(a, b), i|
    segs.each_with_index do |(c, d), j|
      next if (i - j).abs <= 1
      return [a, b, c, d] if seg_cross2d?(a, b, c, d)
    end
  end
  nil
end

def dual_lane_coils_in_room(room, entry_pt, z, walls, doors)
  xi = room['x0'] + INSET
  yi = room['y0'] + INSET
  xa = room['x1'] - INSET
  ya = room['y1'] - INSET
  d = SPACING
  return { supply: [], return: [] } if xa - xi < 2 * d || ya - yi < 3 * d

  door_x, door_y = entry_pt[0], entry_pt[1]
  x_lo = xi + d
  x_hi = xa - d
  supply = []
  ret = []

  append_to(supply, door_x, door_y, z)
  append_to(supply, door_x, yi + d, z)
  append_to(supply, x_hi, yi + d, z)
  append_to(supply, x_lo, yi + d, z)

  y = yi + d
  while y + 2 * d <= ya - d + 0.01
    y += 2 * d
    append_to(supply, supply.last[0], y, z) if (supply.last[1] - y).abs > 0.01
    if (supply.last[0] - x_lo).abs < 0.01
      append_to(supply, x_hi, y, z)
    else
      append_to(supply, x_lo, y, z)
    end
  end

  append_to(ret, x_hi, yi + d, z)
  append_to(ret, x_hi, yi + 2 * d, z)
  append_to(ret, x_lo, yi + 2 * d, z)
  y = yi + 2 * d
  at_lo = true
  loop do
    yn = y + 2 * d
    break if yn > ya - d + 0.01

    append_to(ret, ret.last[0], yn, z) if (ret.last[1] - yn).abs > 0.01
    bridge_to(ret, at_lo ? x_hi : x_lo, yn, z)
    at_lo = !at_lo
    y = yn
  end

  append_to(ret, x_lo, ret.last[1], z) if (ret.last[0] - x_lo).abs > 0.01
  ry = ret.last[1]
  while ry > yi + 2 * d
    ry -= 2 * d
    append_to(ret, x_lo, ry, z)
  end
  append_to(ret, x_lo, yi + d, z)
  append_to(ret, door_x, yi + d, z)
  append_to(ret, door_x, door_y, z)

  [supply, ret].each do |pts|
    cross = path_self_cross?(pts)
    raise "盘管自交叉: #{cross}" if cross
    pts.each_cons(2) do |a, b|
      raise "盘管穿墙: #{a} -> #{b}" unless segment_allowed?(a, b, walls, doors)
    end
  end
  { supply: supply, return: ret }
end

def lane_serpentine_in_room(room, entry_pt, z, walls, doors)
  xi = room['x0'] + INSET
  yi = room['y0'] + INSET
  xa = room['x1'] - INSET
  ya = room['y1'] - INSET
  d = SPACING
  return [] if xa - xi < 2 * d || ya - yi < 2 * d

  door_x, door_y = entry_pt[0], entry_pt[1]
  x_lo = xi + d
  x_hi = xa - d
  pts = []

  append_to(pts, door_x, door_y, z)
  append_to(pts, door_x, yi + d, z)

  y = yi + d
  east = true
  while y <= ya - d + 0.01
    append_to(pts, east ? x_hi : x_lo, y, z)
    y_next = y + d
    break if y_next > ya - d + 0.01

    append_to(pts, pts.last[0], y_next, z)
    east = !east
    y = y_next
  end

  # 沿西缘回到入口，避免穿越已铺横管
  append_to(pts, x_lo, pts.last[1], z) if (pts.last[0] - x_lo).abs > 0.01
  append_to(pts, x_lo, yi + d, z)
  append_to(pts, door_x, yi + d, z)
  append_to(pts, door_x, door_y, z)

  cross = path_self_cross?(pts)
  raise "盘管自交叉: #{cross}" if cross

  pts.each_cons(2) do |a, b|
    raise "盘管穿墙: #{a} -> #{b}" unless segment_allowed?(a, b, walls, doors)
  end
  pts
end

def hui_spiral_in_room(room, entry_pt, z, walls, doors)
  xi = room['x0'] + INSET
  yi = room['y0'] + INSET
  xa = room['x1'] - INSET
  ya = room['y1'] - INSET
  d = SPACING
  min_span = 4 * d
  return [] if xa - xi < min_span || ya - yi < min_span

  door_x, door_y = entry_pt[0], entry_pt[1]
  x0, y0, x1, y1 = xi, yi, xa, ya
  pts = []

  # 入口 → 南缘 → 西侧起始，与用户示例线走向一致
  append_to(pts, door_x, door_y, z)
  append_to(pts, door_x, yi, z)
  append_to(pts, x0 + d, y0, z)

  # 每圈 7 段 U 形折返（供回相邻平行），圈距 2×管间距
  while x1 - x0 >= min_span && y1 - y0 >= min_span
    append_to(pts, x1 - d, y0, z)
    append_to(pts, x1 - d, y1 - d, z)
    append_to(pts, x1 - 2 * d, y1 - d, z)
    append_to(pts, x1 - 2 * d, y0 + d, z)
    append_to(pts, x0 + d, y0 + d, z)
    append_to(pts, x0 + d, y1 - 2 * d, z)
    append_to(pts, x1 - 3 * d, y1 - 2 * d, z)
    x0 += 2 * d
    y0 += 2 * d
    x1 -= 2 * d
    y1 -= 2 * d
  end

  cross = path_self_cross?(pts)
  raise "盘管自交叉: #{cross}" if cross

  pts.each_cons(2) do |a, b|
    raise "盘管穿墙: #{a} -> #{b}" unless segment_allowed?(a, b, walls, doors)
  end
  pts
end

def coil_in_room(room, entry_key, door_map, _z, walls, doors)
  entry = door_pt(entry_key, door_map)
  coil_segments_in_room(room, entry)
end

def vertical_span_clear?(x, y_lo, y_hi, z, walls, doors)
  segment_allowed?([x, y_lo, z], [x, y_hi, z], walls, doors)
end

def serpentine_in_room(room, z, walls, doors)
  x0, y0, x1, y1 = room['x0'], room['y0'], room['x1'], room['y1']
  hot = room['hot_side'] || 'north'
  xi = x0 + INSET
  yi = y0 + INSET
  xa = x1 - INSET
  ya = y1 - INSET
  return [] if xa <= xi + 0.01 || ya <= yi + 0.01
  start_y = hot == 'north' ? ya : yi
  end_y = hot == 'north' ? yi : ya
  y_lo, y_hi = [yi, ya].min, [yi, ya].max
  width = xa - xi
  n_cols = [[(width / SPACING).floor, MAX_COLS].min, 4].max
  step = width / n_cols
  valid_xs = []
  n_cols.times do |i|
    x = xi + step * (i + 0.5)
    valid_xs << x if vertical_span_clear?(x, y_lo, y_hi, z, walls, doors)
  end
  if valid_xs.length < 3
    ((n_cols * 3)).times do |i|
      x = xi + (width / (n_cols * 3)) * (i + 0.5)
      next if valid_xs.any? { |vx| (vx - x).abs < step * 0.25 }
      valid_xs << x if vertical_span_clear?(x, y_lo, y_hi, z, walls, doors)
      break if valid_xs.length >= MAX_COLS
    end
  end
  valid_xs = valid_xs.sort.uniq.first(MAX_COLS)
  return [] if valid_xs.length < 2
  pts = []
  valid_xs.each_with_index do |x, i|
    y_from = i.even? ? start_y : end_y
    y_to = i.even? ? end_y : start_y
    pts << [x, y_from, z]
    pts << [x, y_to, z]
    next if i >= valid_xs.length - 1
    x_next = valid_xs[i + 1]
    next unless segment_allowed?([x, y_to, z], [x_next, y_to, z], walls, doors)
    pts << [x_next, y_to, z]
  end
  pts
end

def door_pt(key, doors)
  d = doors[key]
  raise "door missing: #{key}" unless d
  [d['x'], d['y'], Z_FH]
end

def coil_for_zones(zone_names, rooms, link, door_map, walls, doors, entry_door)
  supply = []
  return_pts = []
  zone_names.each_with_index do |name, idx|
    r = room_rect(name, rooms)
    door_key = idx.zero? ? entry_door : link['door']
    coils = coil_in_room(r, door_key, door_map, Z_FH, walls, doors)
    supply.concat(coils[:supply])
    return_pts.concat(coils[:return])
  end
  { supply: supply, return: return_pts }
end

def manifold_port(man, idx, supply: true)
  [man[:x1] + 1.5, man[:cy] - idx * 1.4, supply ? man[:z1] - 0.3 : man[:z0] + 0.5]
end

def manifold_floor_pt(man)
  [man[:cx], man[:cy], Z_FH]
end

def equip_door_pt(man)
  [man[:cx], 34.0, Z_FH]
end

def build_trunk(man, idx, loop_cfg, door_map)
  s = manifold_port(man, idx, supply: true)
  mf = manifold_floor_pt(man)
  equip = equip_door_pt(man)
  chase = door_pt('分集水器_出', door_map)
  via = loop_cfg['trunk_via'].map { |xy| [xy[0], xy[1], Z_FH] }
  entry = door_pt(loop_cfg['entry_door'], door_map)
  dedupe([s, mf, equip, chase] + via + [entry])
end

def exit_room_to_door(last_pt, loop_cfg, door_map, rooms)
  entry = door_pt(loop_cfg['entry_door'], door_map)
  room = room_rect(loop_cfg['zones'].first, rooms)
  y_bound = room['hot_side'] == 'north' ? room['y0'] + INSET : room['y1'] - INSET
  dedupe([last_pt, [last_pt[0], y_bound, Z_FH], [entry[0], y_bound, Z_FH], entry])
end

def build_return(last_pt, loop_cfg, door_map, man, idx, rooms)
  entry = door_pt(loop_cfg['entry_door'], door_map)
  via = loop_cfg['trunk_via'].map { |xy| [xy[0], xy[1], Z_FH] }.reverse
  chase = door_pt('分集水器_出', door_map)
  equip = equip_door_pt(man)
  mf = manifold_floor_pt(man)
  r_port = manifold_port(man, idx, supply: false)
  near_entry = (last_pt[0] - entry[0]).abs < 1.0 && (last_pt[1] - entry[1]).abs < 1.0
  room_exit = near_entry ? [entry] : exit_room_to_door(last_pt, loop_cfg, door_map, rooms)
  dedupe(room_exit + via + [chase, equip, mf, r_port])
end

walls = load_walls(model)
door_list = CFG['doorways'].values
door_map = CFG['doorways']

rooms = CFG['rooms']

collect_groups(model.active_entities, all = [])
all.each { |g| g.erase! if g.name =~ /\APIPES/ }

man = find_manifold(model)
pipes = model.active_entities.add_group
pipes.name = 'PIPES'

loops = CFG['floor_loops']
if FH_FILTER
  loops = loops.select do |l|
    FH_FILTER == l['id'] || FH_FILTER == l['label'] || l['zones'].include?(FH_FILTER)
  end
  raise "loop not found: #{FH_FILTER}" if loops.empty?
end

fh_label = loops.length == 1 ? "地暖·#{loops.first['label']}" : '5-地暖'
G_FH = sub_group(pipes, fh_label)

lengths = {}
loops.each do |loop|
  idx = CFG['floor_loops'].index(loop)
  loop_doors = doors_for_loop(loop['id'], door_map)
  loop_g = sub_group(G_FH, "#{loop['id']}·#{loop['label']}")
  trunk = build_trunk(man, idx, loop, door_map)
  coils = coil_for_zones(loop['zones'], rooms, loop['zone_link'], door_map, walls, loop_doors, loop['entry_door'])
  r_port = manifold_port(man, idx, supply: false)

  pipe_run(loop_g, trunk, '干管·供', walls, loop_doors, loop_id: loop['id'], rooms: rooms, trunk: true) if trunk.length >= 2
  draw_segments(loop_g, coils[:supply], '盘管·供', walls, loop_doors) unless coils[:supply].empty?
  draw_segments(loop_g, coils[:return], '盘管·回', walls, loop_doors, return_pipe: true) unless coils[:return].empty?
  ret = build_return(door_pt(loop['entry_door'], door_map), loop, door_map, man, idx, rooms)
  pipe_run(loop_g, ret, '干管·回', walls, loop_doors, loop_id: loop['id'], rooms: rooms, trunk: true) if ret.length >= 2

  seg_len = ->(segs) { segs.sum { |s| Math.sqrt((s[0] - s[2])**2 + (s[1] - s[3])**2) } }
  trunk_len = trunk.each_cons(2).sum { |a, b| Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2) }
  ret_len = ret.each_cons(2).sum { |a, b| Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2) }
  lengths[loop['id']] = (trunk_len + seg_len.call(coils[:supply]) + seg_len.call(coils[:return]) + ret_len).round(1)
end

model.commit_operation
{ success: true, version: 'floor_v14b_parallel_pair', filter: FH_FILTER, loops: loops.length, lengths_su: lengths }.to_json
