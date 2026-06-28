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


def rect_spiral(left, bottom, right, top, pitch, start="rb", order="LURD"):
    """
    生成矩形螺旋折线路径。

    参数：
    - left, bottom, right, top : 边界
    - pitch : 每绕一圈收缩量
    - start : 起点角
        rb = 右下, lb = 左下, lt = 左上, rt = 右上
    - order : 行进方向顺序
        例如 LURD = 左 -> 上 -> 右 -> 下
    """
    if right <= left or top <= bottom:
        return []

    pos_map = {
        "rb": (right, bottom),
        "lb": (left, bottom),
        "lt": (left, top),
        "rt": (right, top),
    }

    x, y = pos_map[start]
    pts = [(x, y)]

    l, b, r, t = left, bottom, right, top
    count = {d: 0 for d in "LURD"}

    while True:
        for d in order:
            if d == "L":
                if count[d] > 0:
                    l += pitch
                if l >= r:
                    return dedupe_points(pts)
                x = l

            elif d == "U":
                if count[d] > 0:
                    t -= pitch
                if b >= t:
                    return dedupe_points(pts)
                y = t

            elif d == "R":
                if count[d] > 0:
                    r -= pitch
                if l >= r:
                    return dedupe_points(pts)
                x = r

            elif d == "D":
                b += pitch
                if b >= t:
                    return dedupe_points(pts)
                y = b

            pts.append((x, y))
            count[d] += 1


def build_single_huizi_path(width, height, spacing=90, margin=90, tail=260):
    """
    构造单条连续中心线路径：
    进水尾巴 -> 外螺旋(往里) -> 中心U回头 -> 内螺旋(往外) -> 回水尾巴
    """
    if width <= 2 * margin + 4 * spacing or height <= 2 * margin + 4 * spacing:
        raise ValueError("尺寸太小，无法生成图形，请增大 width/height 或减小 spacing/margin。")

    # 外边界
    left = margin
    bottom = margin
    right = width - margin
    top = height - margin

    # 因为去程和回程是交错排布的，
    # 所以单个螺旋自己的收缩步距是 2 * spacing
    pitch = 2 * spacing

    # 去程：从右下进入，一路向内
    go_path = rect_spiral(
        left, bottom, right, top,
        pitch=pitch,
        start="rb",
        order="LURD",
    )

    # 回程：使用内缩一个 spacing 的边界，
    # 但为了让中心连接更自然，方向顺序换成 ULDR
    return_path = rect_spiral(
        left + spacing,
        bottom + spacing,
        right - spacing,
        top - spacing,
        pitch=pitch,
        start="rb",
        order="ULDR",
    )

    if not go_path or not return_path:
        raise ValueError("路径生成失败，请检查参数。")

    path = []

    # 1) 进水尾巴
    path.append((right + tail, bottom))

    # 2) 去程螺旋
    path.extend(go_path)

    # 3) 中心短U回头（关键）
    gx, gy = go_path[-1]
    rx, ry = return_path[-1]

    # 这里故意只做一个很短的折返连接，
    # 看起来就是一条管在中心掉头
    if (gx, gy) != (rx, ry):
        path.append((rx, gy))
        path.append((rx, ry))

    # 4) 回程螺旋（反向走出来）
    path.extend(reversed(return_path[:-1]))

    # 5) 回水尾巴
    path.append((right + tail, bottom + spacing))

    return dedupe_points(path)


def draw_pipe(ax, points, outer_lw=18, inner_lw=11,
              outer_color="#d82323", inner_color="#f77777"):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]

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


def draw_huizi(width=1600, height=1000, spacing=90, margin=90, tail=260,
               out="huizi_single_path.png", show_border=True):
    path = build_single_huizi_path(
        width=width,
        height=height,
        spacing=spacing,
        margin=margin,
        tail=tail,
    )

    fig_w = (width + tail + 120) / 180
    fig_h = (height + 120) / 180

    fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=180)
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
                edgecolor="#555555",
                linewidth=1.6,
                linestyle=(0, (7, 7)),
            )
        )

    draw_pipe(ax, path)

    pad = 60
    ax.set_xlim(-pad, width + tail + pad)
    ax.set_ylim(-pad, height + pad)

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out, bbox_inches="tight", pad_inches=0.04)
    plt.close(fig)

    print(f"已生成: {out}")


def main():
    parser = argparse.ArgumentParser(description="绘制单路径回字形线条")
    parser.add_argument("--width", type=float, default=1600, help="虚线框宽度")
    parser.add_argument("--height", type=float, default=1000, help="虚线框高度")
    parser.add_argument("--spacing", type=float, default=90, help="相邻线条中心距")
    parser.add_argument("--margin", type=float, default=90, help="离边框留白")
    parser.add_argument("--tail", type=float, default=260, help="右侧伸出尾巴长度")
    parser.add_argument("--out", type=str, default="huizi_single_path.png", help="输出文件")
    parser.add_argument("--no-border", action="store_true", help="不画虚线框")

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
