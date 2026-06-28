import argparse
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle


def dedupe_points(points):
    out = []
    for p in points:
        if not out or out[-1] != p:
            out.append(p)
    return out


def build_rect_spiral(left, bottom, right, top, pitch, tail=0):
    """
    生成一个不会自重叠的矩形螺旋。

    参数：
    - left, bottom, right, top : 螺旋所在边界
    - pitch : 每绕一圈向内收缩的步距
    - tail : 右侧伸出去的直线长度
    """
    if right <= left or top <= bottom:
        return []

    pts = [
        (right + tail, bottom),  # 右侧外部尾巴
        (right, bottom),         # 进入边界
        (left, bottom),          # 向左
        (left, top),             # 向上
    ]

    l, b, r, t = left, bottom, right, top

    while True:
        # 向右
        pts.append((r, t))

        # 向下（先缩底边）
        b += pitch
        if b >= t:
            break
        pts.append((r, b))

        # 向左（先缩左边）
        l += pitch
        if l >= r:
            break
        pts.append((l, b))

        # 向上（先缩顶边）
        t -= pitch
        if b >= t:
            break
        pts.append((l, t))

        # 缩右边，下一轮继续向右
        r -= pitch
        if l >= r:
            break

    return dedupe_points(pts)


def draw_pipe(ax, pts, outer_lw=16, inner_lw=10,
              outer_color="#cf2626", inner_color="#ff7d7d"):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]

    # 外描边
    ax.plot(
        xs, ys,
        color=outer_color,
        linewidth=outer_lw,
        solid_capstyle="round",
        solid_joinstyle="round",
    )

    # 内部浅色
    ax.plot(
        xs, ys,
        color=inner_color,
        linewidth=inner_lw,
        solid_capstyle="round",
        solid_joinstyle="round",
    )


def draw_huizi(
    width=1600,
    height=1000,
    spacing=90,
    margin=90,
    tail=260,
    out="huizi_fixed.png",
    show_border=True,
):
    """
    画“回字形”双线条示意图（不会中心重叠变粗）
    """

    # 外圈和内圈之间的间距
    # 两条螺旋交错排布，所以每条螺旋自己的收缩步距是 2 * spacing
    pitch = 2 * spacing

    # 外螺旋边界
    outer_left = margin
    outer_bottom = margin
    outer_right = width - margin
    outer_top = height - margin

    # 内螺旋边界（整体再内缩一个 spacing）
    inner_left = margin + spacing
    inner_bottom = margin + spacing
    inner_right = width - margin - spacing
    inner_top = height - margin - spacing

    if inner_right <= inner_left or inner_top <= inner_bottom:
        raise ValueError("尺寸太小，无法生成图形，请增大 width/height 或减小 spacing/margin。")

    outer_pts = build_rect_spiral(
        outer_left, outer_bottom, outer_right, outer_top,
        pitch=pitch,
        tail=tail
    )

    inner_pts = build_rect_spiral(
        inner_left, inner_bottom, inner_right, inner_top,
        pitch=pitch,
        tail=tail
    )

    fig_w = (width + tail + 120) / 180
    fig_h = (height + 120) / 180

    fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=180)
    ax.set_aspect("equal")
    ax.axis("off")

    # 背景虚线框
    if show_border:
        ax.add_patch(
            Rectangle(
                (0, 0), width, height,
                fill=False,
                edgecolor="#444444",
                linewidth=1.5,
                linestyle=(0, (6, 6))
            )
        )

    # 先画外圈，再画内圈
    draw_pipe(ax, outer_pts)
    draw_pipe(ax, inner_pts)

    pad = 60
    ax.set_xlim(-pad, width + tail + pad)
    ax.set_ylim(-pad, height + pad)

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)

    print(f"已生成：{out}")


def main():
    parser = argparse.ArgumentParser(description="画回字形线条（修正版，无中心重叠）")
    parser.add_argument("--width", type=float, default=1600, help="虚线框宽度")
    parser.add_argument("--height", type=float, default=1000, help="虚线框高度")
    parser.add_argument("--spacing", type=float, default=90, help="线条间距")
    parser.add_argument("--margin", type=float, default=90, help="离边框留白")
    parser.add_argument("--tail", type=float, default=260, help="右侧伸出长度")
    parser.add_argument("--out", type=str, default="huizi_fixed.png", help="输出文件")
    parser.add_argument("--no-border", action="store_true", help="不显示虚线框")
    args = parser.parse_args()

    draw_huizi(
        width=args.width,
        height=args.height,
        spacing=args.spacing,
        margin=args.margin,
        tail=args.tail,
        out=args.out,
        show_border=not args.no_border,
    )


if __name__ == "__main__":
    main()
