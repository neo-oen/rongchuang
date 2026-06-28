# -*- coding: utf-8 -*-
# 轻量更新：读取当前设备位置 → 加/刷新中文标签 → 写入组属性

model = Sketchup.active_model
model.start_operation('MEP labels update', true)

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

model.layers.add('A2-MEP-LABEL') unless model.layers['A2-MEP-LABEL']

# 删除旧标签组
model.active_entities.grep(Sketchup::Group).each do |g|
  g.erase! if g.name == 'EQUIP-LABELS'
end

labels_g = model.active_entities.add_group
labels_g.name = 'EQUIP-LABELS'
labels_g.layer = model.layers['A2-MEP-LABEL']

positions = {}
missing = []

EQUIP_LABELS.each do |id, text|
  g = model.active_entities.grep(Sketchup::Group).find { |x| x.name == id }
  unless g
    missing << id
    next
  end
  b = g.bounds
  positions[id] = {
    x0: b.min.x.round(2), x1: b.max.x.round(2),
    y0: b.min.y.round(2), y1: b.max.y.round(2),
    z0: b.min.z.round(2), z1: b.max.z.round(2),
    cx: ((b.min.x + b.max.x) / 2.0).round(2),
    cy: ((b.min.y + b.max.y) / 2.0).round(2)
  }
  cx = (b.min.x + b.max.x) / 2.0
  cy = (b.min.y + b.max.y) / 2.0
  z_label = b.max.z + (b.max.z > 50 ? 5.0 : 3.5)
  t = labels_g.entities.add_text(text, [cx, cy, z_label])
  t.layer = model.layers['A2-MEP-LABEL']
  g.set_attribute('A2', 'label', text)
end

labels_g.set_attribute('A2', 'equip_positions', positions.to_json)

model.commit_operation
{
  success: missing.empty?,
  labels_added: positions.length,
  missing: missing,
  positions: positions
}.to_json
