import argparse
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle


def rect_spiral_points(left, bottom, right, top, pitch):
    """
    生成一个从右下角进入、向内收缩的矩形螺旋折线。
    pitch 是单条螺旋自身间距；双螺旋时一般使用 2 * pipe_spacing。
    """
    if right <= left or top <= bottom:
        return []

    x, y = right, bottom
    pts = [(x, y)]

    l, b, r, t = left, bottom, right, top
    count = {"LEFT": 0, "UP": 0, "RIGHT": 0, "DOWN": 0}
    directions = ("LEFT", "UP", "RIGHT", "DOWN")

    while True:
        for d in directions:
            if d == "LEFT":
                if count[d] > 0:
                    l += pitch
                if l >= r:
                    return pts
                x = l

            elif d == "UP":
                if count[d] > 0:
                    t -= pitch
                if b >= t:
                    return pts
                y = t

            elif d == "RIGHT":
                if count[d] > 0:
                    r -= pitch
                if l >= r:
                    return pts
                x = r

            elif d == "DOWN":
                b += pitch
                if b >= t:
                    return pts
                y = b

            pts.append((x, y))
            count[d] += 1


def remove_duplicate_points(points):
    out = []
    for p in points:
        if not out or p != out[-1]:
            out.append(p)
    return out


def build_huizi_path(width, height, pipe_spacing=80, margin=None, tail=None):
    """
    生成“回字形 / 地暖盘管式”双螺旋路径。

    width, height:
        虚线框的大致宽高，单位自定，mm/cm/px 都可以，只要统一。

    pipe_spacing:
        最终相邻管线中心距。

    margin:
        管线距离虚线框边界的距离。

    tail:
        右侧伸出的进回水管长度。
    """
    if margin is None:
        margin = pipe_spacing * 1.2

    if tail is None:
        tail = pipe_spacing * 3.0

    if width <= 2 * margin + 4 * pipe_spacing or height <= 2 * margin + 4 * pipe_spacing:
        raise ValueError("长宽太小，放不下回字形。请增大 width/height，或减小 spacing/margin。")

    # 虚线框是 0,0,width,height
    # 管线在虚线框内部留 margin
    left = margin
    bottom = margin
    right = width - margin
    top = height - margin

    # A/B 两条交错螺旋。
    # 用 2 倍管距生成，合成后视觉上相邻间距就是 pipe_spacing。
    pitch = 2 * pipe_spacing

    spiral_a = rect_spiral_points(left, bottom, right, top, pitch)

    spiral_b = rect_spiral_points(
        left + pipe_spacing,
        bottom + pipe_spacing,
        right - pipe_spacing,
        top - pipe_spacing,
        pitch,
    )

    if len(spiral_a) < 2 or len(spiral_b) < 2:
        raise ValueError("参数组合导致路径太短，请增大长宽或减小管距。")

    pts = []

    # 进水尾管，从右侧进入外圈
    pts.append((width + tail, bottom))
    pts.extend(spiral_a)

    # 中心连接，把 A 的中心端接到 B 的中心端
    ax, ay = spiral_a[-1]
    bx, by = spiral_b[-1]

    if (ax, ay) != (bx, by):
        pts.append((bx, ay))
        pts.append((bx, by))

    # 回水路径：沿 B 螺旋反向绕出
    pts.extend(reversed(spiral_b[:-1]))

    # 回水尾管，从右侧出去
    pts.append((width + tail, bottom + pipe_spacing))

    return remove_duplicate_points(pts)


def draw_huizi(
    width=1600,
    height=1000,
    pipe_spacing=90,
    margin=None,
    tail=None,
    pipe_width=12,
    out="huizi.svg",
    show_border=True,
):
    pts = build_huizi_path(
        width=width,
        height=height,
        pipe_spacing=pipe_spacing,
        margin=margin,
        tail=tail,
    )

    if margin is None:
        margin = pipe_spacing * 1.2

    if tail is None:
        tail = pipe_spacing * 3.0

    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]

    fig_w = (width + tail + pipe_spacing * 2) / 180
    fig_h = (height + pipe_spacing * 2) / 180

    fig = plt.figure(figsize=(fig_w, fig_h), dpi=180)
    ax = plt.gca()
    ax.set_aspect("equal")
    ax.axis("off")

    # 虚线边框
    if show_border:
        ax.add_patch(
            Rectangle(
                (0, 0),
                width,
                height,
                fill=False,
                linewidth=1.8,
                linestyle=(0, (6, 6)),
                edgecolor="#333333",
            )
        )

    # 外描边
    ax.plot(
        xs,
        ys,
        linewidth=pipe_width + 5,
        color="#c82424",
        solid_capstyle="round",
        solid_joinstyle="round",
    )

    # 内部浅色，让它更像红色管线
    ax.plot(
        xs,
        ys,
        linewidth=pipe_width,
        color="#ff6b6b",
        solid_capstyle="round",
        solid_joinstyle="round",
    )

    pad = pipe_spacing
    ax.set_xlim(-pad, width + tail + pad)
    ax.set_ylim(-pad, height + pad)

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out, bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)

    print(f"已生成：{out}")


def main():
    parser = argparse.ArgumentParser(description="绘制回字形地暖/盘管示意图")

    parser.add_argument("--width", type=float, default=1600, help="虚线框宽度")
    parser.add_argument("--height", type=float, default=1000, help="虚线框高度")
    parser.add_argument("--spacing", type=float, default=90, help="相邻管线中心距")
    parser.add_argument("--margin", type=float, default=None, help="管线距离边框距离")
    parser.add_argument("--tail", type=float, default=None, help="右侧进回水尾管长度")
    parser.add_argument("--pipe-width", type=float, default=12, help="画出来的管线粗细")
    parser.add_argument("--out", type=str, default="huizi.svg", help="输出文件，支持 svg/png/pdf")
    parser.add_argument("--no-border", action="store_true", help="不画虚线边框")

    args = parser.parse_args()

    draw_huizi(
        width=args.width,
        height=args.height,
        pipe_spacing=args.spacing,
        margin=args.margin,
        tail=args.tail,
        pipe_width=args.pipe_width,
        out=args.out,
        show_border=not args.no_border,
    )


if __name__ == "__main__":
    main()
