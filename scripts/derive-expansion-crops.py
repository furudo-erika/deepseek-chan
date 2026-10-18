"""Derive runtime clip metadata only; never rewrites generated PNG pixels.

Find low-alpha paths between the 3x3 figures instead of cutting straight through
hair/props at mathematical thirds. Review production renders after running.
"""
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image


def seam(alpha, center):
    low = max(0, int(center - 70))
    high = min(alpha.shape[1], int(center + 70))
    pixels = alpha[:, low:high].astype(float) / 255
    distance = np.arange(low, high) - center
    energy = pixels * pixels * 100 + distance * distance * 0.00002
    cost = energy[0].copy()
    history = np.zeros(energy.shape, dtype=np.int8)
    offsets = range(-3, 4)
    for row in range(1, len(energy)):
        options = []
        for delta in offsets:
            shifted = np.full_like(cost, np.inf)
            if delta >= 0:
                shifted[:len(cost)-delta or None] = cost[delta:] + abs(delta)*0.02
            else:
                shifted[-delta:] = cost[:delta] + abs(delta)*0.02
            options.append(shifted)
        options = np.array(options)
        choice = options.argmin(axis=0)
        history[row] = choice - 3
        cost = energy[row] + options[choice, np.arange(len(cost))]
    path = np.empty(len(energy), dtype=int)
    x = int(cost.argmin())
    for row in range(len(energy)-1, -1, -1):
        path[row] = low + x
        x += int(history[row, x])
    return path


layouts = json.loads(Path('Assets/atlas-layout.json').read_text())
regions = {}
for file in sorted(list(Path('Assets/actions').glob('actions-extra-*.png')) + list(Path('Assets/actions').glob('actions-halloween-*.png'))):
    im = Image.open(file)
    assert im.mode == 'RGBA', file
    alpha = np.array(im)[:, :, 3]
    h, w = alpha.shape
    vertical = [np.zeros(h, dtype=int), seam(alpha, w/3), seam(alpha, 2*w/3), np.full(h, w)]
    horizontal = [np.zeros(w, dtype=int), seam(alpha.T, h/3), seam(alpha.T, 2*h/3), np.full(w, h)]
    y, x = np.indices((h, w))
    owner = np.zeros((h, w), dtype=np.uint8)
    for row in range(3):
        for col in range(3):
            inside = ((x >= vertical[col][:, None]) & (x < vertical[col+1][:, None])
                      & (y >= horizontal[row][None, :]) & (y < horizontal[row+1][None, :]))
            owner[inside] = row*3+col
    # Visually reviewed ownership corrections for interleaving curls/props.
    corrections = {
        'actions-extra-cafe': [(7, 665, 824, 735, 859)],
        'actions-extra-cozy': [(8, 1098, 837, 1165, 876)],
        'actions-extra-science': [(3, 390, 548, 453, 647)],
        'actions-extra-games': [(0, 309, 430, 405, 444)],
    }
    for cell, x0, y0, x1, y1 in corrections.get(file.stem, []):
        owner[y0:y1, x0:x1] = cell
    crops = []
    for row in range(3):
        for col in range(3):
            mask = owner == row*3+col
            yy, xx = np.where(mask & (alpha > 32))
            x0, x1 = max(0, int(xx.min())-3), min(w, int(xx.max())+4)
            y0, y1 = max(0, int(yy.min())-3), min(h, int(yy.max())+4)
            local = mask[y0:y1, x0:x1].astype(np.uint8)
            contours, _ = cv2.findContours(local, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            assert len(contours) == 1, (file, row, col)
            contour = cv2.approxPolyDP(contours[0], 0.65, True).reshape(-1, 2)
            crops.append([x0/w, y0/h, (x1-x0)/w, (y1-y0)/h])
            regions[f'{file.stem}:{row*3+col}'] = [[round(float(a)/(x1-x0), 7), round(float(b)/(y1-y0), 7)] for a,b in contour]
    layouts[file.stem] = crops
    print(file.stem, '9 separated display regions')
Path('Assets/atlas-layout.json').write_text(json.dumps(layouts, indent=2)+'\n')
Path('Assets/atlas-regions.json').write_text(json.dumps(regions, separators=(',', ':'))+'\n')
