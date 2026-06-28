# -*- coding: utf-8 -*-
# 清除生活水 / 空调水 / 地暖 示意管线（保留设备、排水、燃气管）

model = Sketchup.active_model
model.start_operation('Clear MEP pipes', true)

ROOT_PIPE_RE = /\A(?:PIPES(?:-|$)|[1-6]-(?:生活水|两联供|空调))/
NESTED_PIPE_RE = /\A(?:软水|热水|RO|二次侧|干管|盘管|FH\d|AC\d)/

def collect_groups(entities, out)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group)
    out << e
    collect_groups(e.entities, out)
  end
end

all = []
collect_groups(model.active_entities, all)

to_erase = all.select do |g|
  next false unless g.valid?
  n = g.name.to_s
  n.match?(ROOT_PIPE_RE) || n.match?(NESTED_PIPE_RE) || n.start_with?('地暖')
end

names = to_erase.map { |g| g.valid? ? g.name.to_s : '?' }.uniq.sort

to_erase.each do |g|
  next unless g.valid?
  g.erase!
rescue StandardError
  nil
end

# 根级再扫一遍
model.active_entities.grep(Sketchup::Group).each do |g|
  next unless g.valid?
  n = g.name.to_s
  g.erase! if n.match?(ROOT_PIPE_RE)
rescue StandardError
  nil
end

model.commit_operation

# 清除客厅内 z≈0 手画示例线（地暖示意）
model.start_operation('Clear FH example edges', true)
ex_x0, ex_x1, ex_y0, ex_y1 = 93, 228, 157, 307
ex_tol = 0.6
to_erase_edges = []
model.active_entities.grep(Sketchup::Edge).each do |e|
  a = e.start.position
  b = e.end.position
  next unless a.z.abs <= ex_tol && b.z.abs <= ex_tol
  midx = (a.x + b.x) / 2.0
  midy = (a.y + b.y) / 2.0
  next unless midx >= ex_x0 - 5 && midx <= ex_x1 + 5 && midy >= ex_y0 - 5 && midy <= ex_y1 + 5
  to_erase_edges << e
end
ex_removed = to_erase_edges.length
to_erase_edges.each { |e| e.erase! if e.valid? }
model.commit_operation

left = []
collect_groups(model.active_entities, left)
{
  success: true,
  removed: names,
  example_edges_removed: ex_removed,
  remaining_pipe_like: left.select { |g| g.valid? }.map { |g| g.name.to_s }.select { |n| n =~ /软水|生活热水|热水回水|RO纯水|空调供水|空调回水|地暖|PIPES/i }
}.to_json
