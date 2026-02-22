#!/usr/bin/env python3
"""
🧮 HME Attention Training v5 — DEFINITIVE TOP TIER Edition

FEATURES:
  ✅ 2D spatial rendering (fractions, superscripts, matrices, radicals)
  ✅ Elastic distortion + perspective/affine augmentation
  ✅ 100+ formula templates covering ALL vocabulary tokens
  ✅ Mixed Precision (AMP) for 2x speed on T4
  ✅ Label Smoothing for robust generalization
  ✅ Beam Search decoding for accurate evaluation
  ✅ Linear Warmup + Cosine Decay scheduler
  ✅ Background textures (grid, ruled, dots, dark canvas, paper)
  ✅ 100% commercially safe (Google Fonts, Apache/OFL)

Usage on Colab (T4 GPU):
  !pip install onnxscript scipy tqdm
  !python train_hme_top_tier.py
"""

import json
import math
import os
import random
import subprocess
import time
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.models as models
from PIL import Image, ImageDraw, ImageFont, ImageFilter
try:
    from scipy.ndimage import gaussian_filter, map_coordinates
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False
    print("⚠️  scipy not found — elastic distortion disabled. Install: pip install scipy")
from torch.utils.data import Dataset, DataLoader
from torch.cuda.amp import autocast, GradScaler
from torchvision import transforms
try:
    from tqdm import tqdm
except ImportError:
    def tqdm(x, **kw): return x

# ═══════════════════════════════════════════════════════════════════════════════
# VOCABULARY
# ═══════════════════════════════════════════════════════════════════════════════

SPECIAL_TOKENS = ['<pad>', '<sos>', '<eos>']
MATH_TOKENS = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    r'\alpha', r'\beta', r'\gamma', r'\delta', r'\epsilon', r'\theta',
    r'\lambda', r'\mu', r'\pi', r'\sigma', r'\phi', r'\omega',
    r'\Delta', r'\Sigma', r'\Phi', r'\Omega',
    '+', '-', '=', r'\times', r'\div', r'\pm', r'\cdot',
    '<', '>', r'\leq', r'\geq', r'\neq', r'\approx',
    '(', ')', '[', ']', '{', '}', '|',
    '^', '_', r'\frac', r'\sqrt',
    r'\sin', r'\cos', r'\tan', r'\log', r'\ln', r'\lim',
    r'\sum', r'\prod', r'\int',
    r'\infty', r'\partial', ',', '.', '!', r'\ldots', ' ',
    r'\rightarrow', r'\leftarrow',
    r'\forall', r'\exists', r'\in', r'\cup', r'\cap',
]

ALL_TOKENS = SPECIAL_TOKENS + MATH_TOKENS
PAD_IDX, SOS_IDX, EOS_IDX = 0, 1, 2
TOKEN2IDX = {t: i for i, t in enumerate(ALL_TOKENS)}
IDX2TOKEN = {i: t for i, t in enumerate(ALL_TOKENS)}
VOCAB_SIZE = len(ALL_TOKENS)

IMG_HEIGHT = 128
IMG_WIDTH = 512
MAX_SEQ_LEN = 64

# Unicode display for Greek/operators (for rendering)
DISPLAY_MAP = {
    r'\alpha': 'α', r'\beta': 'β', r'\gamma': 'γ', r'\delta': 'δ',
    r'\epsilon': 'ε', r'\theta': 'θ', r'\lambda': 'λ', r'\mu': 'μ',
    r'\pi': 'π', r'\sigma': 'σ', r'\phi': 'φ', r'\omega': 'ω',
    r'\Delta': 'Δ', r'\Sigma': 'Σ', r'\Phi': 'Φ', r'\Omega': 'Ω',
    r'\times': '×', r'\div': '÷', r'\pm': '±', r'\cdot': '·',
    r'\leq': '≤', r'\geq': '≥', r'\neq': '≠', r'\approx': '≈',
    r'\infty': '∞', r'\partial': '∂', r'\ldots': '…',
    r'\rightarrow': '→', r'\leftarrow': '←',
    r'\forall': '∀', r'\exists': '∃', r'\in': '∈',
    r'\cup': '∪', r'\cap': '∩',
    r'\sin': 'sin', r'\cos': 'cos', r'\tan': 'tan',
    r'\log': 'log', r'\ln': 'ln', r'\lim': 'lim',
    r'\sum': '∑', r'\prod': '∏', r'\int': '∫',
}


# ═══════════════════════════════════════════════════════════════════════════════
# MODEL (identical architecture)
# ═══════════════════════════════════════════════════════════════════════════════


class HMEEncoder(nn.Module):
    def __init__(self, d_model=256):
        super().__init__()
        resnet = models.resnet18(weights=models.ResNet18_Weights.DEFAULT)
        self.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
        with torch.no_grad():
            self.conv1.weight.copy_(resnet.conv1.weight.mean(dim=1, keepdim=True))
        self.bn1 = resnet.bn1
        self.relu = resnet.relu
        self.maxpool = resnet.maxpool
        self.layer1 = resnet.layer1
        self.layer2 = resnet.layer2
        self.layer3 = resnet.layer3
        self.layer4 = resnet.layer4
        # 2D positional encoding: learned row/col embeddings
        # ResNet output at 128x512 input: 4x16 feature map
        self.row_embed = nn.Embedding(32, 512)   # max 32 rows
        self.col_embed = nn.Embedding(64, 512)   # max 64 cols
        self.proj = nn.Linear(512, d_model)
        self.proj_dropout = nn.Dropout(0.1)

    def forward(self, x):
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)  # [B, 512, H, W]
        B, C, H, W = x.shape
        # Add 2D position info (crucial for frac/sup/sub recognition)
        rows = torch.arange(H, device=x.device)
        cols = torch.arange(W, device=x.device)
        row_emb = self.row_embed(rows).unsqueeze(1).expand(-1, W, -1)  # [H,W,512]
        col_emb = self.col_embed(cols).unsqueeze(0).expand(H, -1, -1)  # [H,W,512]
        pos = (row_emb + col_emb).permute(2, 0, 1).unsqueeze(0)       # [1,512,H,W]
        x = x + pos
        # Flatten spatial dims → sequence
        x = x.flatten(2).permute(0, 2, 1)  # [B, H*W, 512]
        x = self.proj_dropout(self.proj(x))  # [B, H*W, d_model]
        return x


class PositionalEncoding(nn.Module):
    def __init__(self, d_model, max_len=256):
        super().__init__()
        pe = torch.zeros(max_len, d_model)
        pos = torch.arange(0, max_len, dtype=torch.float32).unsqueeze(1)
        div = torch.exp(torch.arange(0, d_model, 2, dtype=torch.float32) * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(pos * div)
        pe[:, 1::2] = torch.cos(pos * div)
        self.register_buffer('pe', pe.unsqueeze(0))

    def forward(self, x):
        return x + self.pe[:, :x.size(1)]


class HMEDecoder(nn.Module):
    def __init__(self, vocab_size, d_model=256, nhead=8, num_layers=3,
                 dim_feedforward=512, dropout=0.1, max_seq_len=MAX_SEQ_LEN):
        super().__init__()
        self.max_seq_len = max_seq_len
        self.embedding = nn.Embedding(vocab_size, d_model, padding_idx=PAD_IDX)
        self.pos_encoding = PositionalEncoding(d_model, max_len=max_seq_len + 10)
        self.embed_scale = math.sqrt(d_model)
        decoder_layer = nn.TransformerDecoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=dim_feedforward,
            dropout=dropout, batch_first=True)
        self.transformer_decoder = nn.TransformerDecoder(decoder_layer, num_layers=num_layers)
        self.output_proj = nn.Linear(d_model, vocab_size)
        causal_mask = torch.triu(torch.ones(max_seq_len, max_seq_len, dtype=torch.bool), diagonal=1)
        self.register_buffer('causal_mask', causal_mask)

    def forward(self, tgt_tokens, memory):
        S = tgt_tokens.size(1)
        x = self.embedding(tgt_tokens) * self.embed_scale
        x = self.pos_encoding(x)
        # Padding mask: True where token is PAD (decoder ignores those positions)
        tgt_key_padding_mask = (tgt_tokens == PAD_IDX)
        x = self.transformer_decoder(
            tgt=x, memory=memory,
            tgt_mask=self.causal_mask[:S, :S],
            tgt_key_padding_mask=tgt_key_padding_mask,
        )
        return self.output_proj(x)


class HMEAttentionModel(nn.Module):
    def __init__(self, vocab_size=VOCAB_SIZE, d_model=256):
        super().__init__()
        self.encoder = HMEEncoder(d_model=d_model)
        self.decoder = HMEDecoder(vocab_size=vocab_size, d_model=d_model)

    def forward(self, images, tgt_tokens):
        return self.decoder(tgt_tokens, self.encoder(images))


class EncoderWrapper(nn.Module):
    def __init__(self, e):
        super().__init__()
        self.encoder = e
    def forward(self, image):
        return self.encoder(image)


class DecoderWrapper(nn.Module):
    def __init__(self, d):
        super().__init__()
        self.decoder = d
    def forward(self, tokens, memory):
        return self.decoder(tokens, memory)


# ═══════════════════════════════════════════════════════════════════════════════
# GOOGLE FONTS
# ═══════════════════════════════════════════════════════════════════════════════

HANDWRITING_FONTS = {
    # ── Original 10 fonts ──
    'Caveat': 'https://github.com/google/fonts/raw/main/ofl/caveat/Caveat%5Bwght%5D.ttf',
    'IndieFlower': 'https://github.com/google/fonts/raw/main/ofl/indieflower/IndieFlower-Regular.ttf',
    'PatrickHand': 'https://github.com/google/fonts/raw/main/ofl/patrickhand/PatrickHand-Regular.ttf',
    'Kalam': 'https://github.com/google/fonts/raw/main/ofl/kalam/Kalam-Regular.ttf',
    'KalamBold': 'https://github.com/google/fonts/raw/main/ofl/kalam/Kalam-Bold.ttf',
    'ComingSoon': 'https://github.com/google/fonts/raw/main/apache/comingsoon/ComingSoon-Regular.ttf',
    'GloriaHallelujah': 'https://github.com/google/fonts/raw/main/ofl/gloriahallelujah/GloriaHallelujah-Regular.ttf',
    'ArchitectsDaughter': 'https://github.com/google/fonts/raw/main/apache/architectsdaughter/ArchitectsDaughter-Regular.ttf',
    'ShadowsIntoLight': 'https://github.com/google/fonts/raw/main/ofl/shadowsintolight/ShadowsIntoLight.ttf',
    'Handlee': 'https://github.com/google/fonts/raw/main/ofl/handlee/Handlee-Regular.ttf',
    # ── 12 NEW fonts for more handwriting diversity ──
    'DancingScript': 'https://github.com/google/fonts/raw/main/ofl/dancingscript/DancingScript%5Bwght%5D.ttf',
    'Pacifico': 'https://github.com/google/fonts/raw/main/ofl/pacifico/Pacifico-Regular.ttf',
    'RockSalt': 'https://github.com/google/fonts/raw/main/apache/rocksalt/RockSalt-Regular.ttf',
    'Neucha': 'https://github.com/google/fonts/raw/main/ofl/neucha/Neucha-Regular.ttf',
    'JustAnotherHand': 'https://github.com/google/fonts/raw/main/apache/justanotherhand/JustAnotherHand-Regular.ttf',
    'CedarvilleCursive': 'https://github.com/google/fonts/raw/main/ofl/cedarvillecursive/CedarvilleCursive.ttf',
    'Schoolbell': 'https://github.com/google/fonts/raw/main/apache/schoolbell/Schoolbell-Regular.ttf',
    'Pangolin': 'https://github.com/google/fonts/raw/main/ofl/pangolin/Pangolin-Regular.ttf',
    'BethEllen': 'https://github.com/google/fonts/raw/main/ofl/bethellen/BethEllen-Regular.ttf',
    'KaushanScript': 'https://github.com/google/fonts/raw/main/ofl/kaushanscript/KaushanScript-Regular.ttf',
    'ReenieBeanieReg': 'https://github.com/google/fonts/raw/main/apache/reeniebeanie/ReenieBeanie-Regular.ttf',
    'LiuJianMaoCao': 'https://github.com/google/fonts/raw/main/ofl/liujianmaocao/LiuJianMaoCao-Regular.ttf',
}


def download_fonts(font_dir='hw_fonts'):
    os.makedirs(font_dir, exist_ok=True)
    downloaded = []
    for name, url in HANDWRITING_FONTS.items():
        path = os.path.join(font_dir, f'{name}.ttf')
        if os.path.exists(path) and os.path.getsize(path) > 1000:
            downloaded.append(path)
            continue
        try:
            subprocess.run(['wget', '-q', '-O', path, url], check=True, timeout=30)
            if os.path.getsize(path) > 1000:
                downloaded.append(path)
                print(f"   ✅ {name}")
        except Exception as e:
            print(f"   ❌ {name}: {e}")

    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"]:
        if os.path.exists(p):
            downloaded.append(p)
    return downloaded


# ═══════════════════════════════════════════════════════════════════════════════
# 2D FORMULA TREE + RENDERER
#
# Instead of rendering flat text, we build a TREE that represents the spatial
# structure of the formula, then render it with proper 2D layout.
# ═══════════════════════════════════════════════════════════════════════════════


@dataclass
class FNode:
    """Formula tree node."""
    kind: str  # 'text', 'frac', 'sup', 'sub', 'sqrt', 'group', 'big_op', 'matrix'
    text: str = ''
    children: List['FNode'] = field(default_factory=list)
    tokens: List[str] = field(default_factory=list)  # LaTeX tokens for this node


@dataclass
class RenderBox:
    """Bounding box of a rendered formula element."""
    width: float
    height: float
    ascent: float  # distance from baseline to top
    descent: float  # distance from baseline to bottom


class Formula2DRenderer:
    """Renders formula trees with proper 2D spatial layout.

    Fractions are stacked vertically, superscripts are raised,
    subscripts are lowered, sqrt has a radical sign, etc.
    """

    def __init__(self, fonts, augment=True):
        self.fonts = fonts
        self.augment = augment
        self._font_cache = {}

    def _get_font(self, size):
        path = random.choice(self.fonts)
        key = (path, size)
        if key not in self._font_cache:
            try:
                self._font_cache[key] = ImageFont.truetype(path, size)
            except (IOError, OSError):
                self._font_cache[key] = ImageFont.load_default()
        return self._font_cache[key]

    def render(self, node: FNode, base_size=32) -> Image.Image:
        """Render a formula tree to an image."""
        # First pass: measure
        box = self._measure(node, base_size)

        # Create image with margin
        margin = 15
        w = int(box.width + 2 * margin)
        h = int(box.height + 2 * margin)
        w = max(w, 64)
        h = max(h, 32)

        img = Image.new('L', (w, h), color=255)
        draw = ImageDraw.Draw(img)

        # Ink color
        ink = random.randint(0, 50) if self.augment else 0

        # Draw at baseline
        baseline_y = margin + box.ascent
        self._draw(draw, node, margin, baseline_y, base_size, ink)

        # ── GLOBAL SLANT (italic handwriting) ──
        if self.augment and random.random() < 0.3:
            slant = random.uniform(-0.15, 0.25)  # rightward bias
            img = img.transform(img.size, Image.AFFINE,
                                (1, slant, -slant * h / 2, 0, 1, 0),
                                Image.BICUBIC, fillcolor=255)

        # ── ASPECT-RATIO PRESERVING RESIZE ──
        # Instead of squashing wide formulas, pad to maintain proportions
        img = self._resize_with_padding(img, IMG_WIDTH, IMG_HEIGHT)
        return img

    def _resize_with_padding(self, img, target_w, target_h):
        """Resize preserving aspect ratio, pad remainder with white."""
        src_w, src_h = img.size
        src_ratio = src_w / max(src_h, 1)
        tgt_ratio = target_w / max(target_h, 1)

        if abs(src_ratio - tgt_ratio) < 0.3:
            # Close enough — just resize
            return img.resize((target_w, target_h), Image.LANCZOS)

        if src_ratio > tgt_ratio:
            # Formula is too wide → fit to width, pad top/bottom
            new_w = target_w
            new_h = max(1, int(target_w / src_ratio))
        else:
            # Formula is too tall → fit to height, pad left/right
            new_h = target_h
            new_w = max(1, int(target_h * src_ratio))

        resized = img.resize((new_w, new_h), Image.LANCZOS)
        padded = Image.new('L', (target_w, target_h), color=255)
        paste_x = (target_w - new_w) // 2
        paste_y = (target_h - new_h) // 2
        padded.paste(resized, (paste_x, paste_y))
        return padded

    def _draw_pressure_line(self, draw, pts, ink, base_width=2):
        """Draw a line with variable thickness simulating pen pressure.

        Draws overlapping circles with varying radius —
        thin at endpoints, thick in the middle (sine curve).
        """
        if len(pts) < 2:
            return
        n_steps = max(int(sum(
            math.hypot(pts[i+1][0]-pts[i][0], pts[i+1][1]-pts[i][1])
            for i in range(len(pts)-1)
        ) / 2), 4)
        for step in range(n_steps + 1):
            t = step / max(n_steps, 1)
            # Interpolate position along the polyline
            total_len = sum(
                math.hypot(pts[i+1][0]-pts[i][0], pts[i+1][1]-pts[i][1])
                for i in range(len(pts)-1)
            )
            target = t * total_len
            accum = 0
            px, py = pts[0]
            for i in range(len(pts)-1):
                seg = math.hypot(pts[i+1][0]-pts[i][0], pts[i+1][1]-pts[i][1])
                if accum + seg >= target and seg > 0:
                    frac_t = (target - accum) / seg
                    px = pts[i][0] + frac_t * (pts[i+1][0] - pts[i][0])
                    py = pts[i][1] + frac_t * (pts[i+1][1] - pts[i][1])
                    break
                accum += seg
            # Pressure: thin→thick→thin (sine curve)
            pressure = 0.5 + 0.5 * math.sin(t * math.pi)
            r = max(1, int(base_width * (0.4 + 0.8 * pressure)))
            draw.ellipse([(px-r, py-r), (px+r, py+r)], fill=ink)

    def _measure(self, node: FNode, size: int) -> RenderBox:
        font = self._get_font(size)

        if node.kind == 'text':
            display = self._display_text(node.text)
            bbox = font.getbbox(display)
            w = bbox[2] - bbox[0]
            h = bbox[3] - bbox[1]
            return RenderBox(w + 2, h, h * 0.7, h * 0.3)

        elif node.kind == 'frac':
            num_box = self._measure(node.children[0], int(size * 0.8))
            den_box = self._measure(node.children[1], int(size * 0.8))
            w = max(num_box.width, den_box.width) + 6
            gap = 4
            h = num_box.height + den_box.height + gap
            return RenderBox(w, h, num_box.height + gap // 2, den_box.height + gap // 2)

        elif node.kind == 'sup':
            base_box = self._measure(node.children[0], size)
            sup_box = self._measure(node.children[1], int(size * 0.65))
            w = base_box.width + sup_box.width
            asc = max(base_box.ascent, sup_box.height + base_box.ascent * 0.3)
            return RenderBox(w, asc + base_box.descent, asc, base_box.descent)

        elif node.kind == 'sub':
            base_box = self._measure(node.children[0], size)
            sub_box = self._measure(node.children[1], int(size * 0.65))
            w = base_box.width + sub_box.width
            desc = max(base_box.descent, sub_box.height - base_box.descent * 0.3)
            return RenderBox(w, base_box.ascent + desc, base_box.ascent, desc)

        elif node.kind == 'sqrt':
            inner_box = self._measure(node.children[0], size)
            w = inner_box.width + size * 0.5
            h = inner_box.height + 4
            return RenderBox(w, h, inner_box.ascent + 4, inner_box.descent)

        elif node.kind == 'big_op':
            # Sum/Prod/Int with optional limits
            sym_h = int(size * 1.4)
            w = size * 0.8
            if len(node.children) >= 2:
                lo_box = self._measure(node.children[0], int(size * 0.5))
                hi_box = self._measure(node.children[1], int(size * 0.5))
                w = max(w, lo_box.width, hi_box.width)
                h = sym_h + lo_box.height + hi_box.height
                return RenderBox(w, h, hi_box.height + sym_h * 0.6, lo_box.height + sym_h * 0.4)
            return RenderBox(w, sym_h, sym_h * 0.6, sym_h * 0.4)

        elif node.kind == 'matrix':
            # Grid layout: children are rows, each row is a group
            rows = node.children
            ncols = max(len(r.children) for r in rows) if rows else 1
            cell_size = int(size * 0.75)
            cell_boxes = []
            max_cell_w = 0
            max_cell_h = 0
            for row in rows:
                row_boxes = []
                for child in row.children:
                    cb = self._measure(child, cell_size)
                    max_cell_w = max(max_cell_w, cb.width)
                    max_cell_h = max(max_cell_h, cb.height)
                    row_boxes.append(cb)
                cell_boxes.append(row_boxes)
            gap = 6
            total_w = ncols * max_cell_w + (ncols - 1) * gap + size * 0.6  # +brackets
            total_h = len(rows) * max_cell_h + (len(rows) - 1) * gap
            return RenderBox(total_w, total_h, total_h * 0.55, total_h * 0.45)

        elif node.kind == 'group':
            total_w = 0
            max_asc = 0
            max_desc = 0
            for child in node.children:
                cbox = self._measure(child, size)
                total_w += cbox.width
                max_asc = max(max_asc, cbox.ascent)
                max_desc = max(max_desc, cbox.descent)
            sp = 2 * (len(node.children) - 1) if len(node.children) > 1 else 0
            return RenderBox(total_w + sp, max_asc + max_desc, max_asc, max_desc)

        return RenderBox(10, 10, 7, 3)

    def _draw(self, draw: ImageDraw, node: FNode, x: float, baseline_y: float,
              size: int, ink: int):
        font = self._get_font(size)

        # Jitter for handwriting effect
        jx = random.uniform(-1.5, 1.5) if self.augment else 0
        jy = random.uniform(-1.5, 1.5) if self.augment else 0

        # Baseline wander: sinusoidal drift across the formula
        if self.augment:
            wander_amp = random.uniform(0.5, 2.0)  # pixels of drift
            wander_freq = random.uniform(0.01, 0.04)  # wave frequency
            jy += wander_amp * math.sin(x * wander_freq)

        if node.kind == 'text':
            display = self._display_text(node.text)
            bbox = font.getbbox(display)
            h = bbox[3] - bbox[1]
            ty = baseline_y - h * 0.7
            # Per-character ink opacity variation
            char_ink = ink
            if self.augment:
                char_ink = max(0, min(255, ink + random.randint(-15, 15)))
            draw.text((x + jx, ty + jy), display, fill=char_ink, font=font)

        elif node.kind == 'frac':
            num_box = self._measure(node.children[0], int(size * 0.8))
            den_box = self._measure(node.children[1], int(size * 0.8))
            total_w = max(num_box.width, den_box.width) + 6
            gap = 4

            # Numerator (centered above baseline)
            num_x = x + (total_w - num_box.width) / 2
            num_baseline = baseline_y - gap // 2 - den_box.height * 0.1
            self._draw(draw, node.children[0], num_x, num_baseline - num_box.descent,
                       int(size * 0.8), ink)

            # Fraction line
            line_y = baseline_y + jy
            line_w = random.randint(1, 3) if self.augment else 2
            if self.augment and random.random() < 0.5:
                # Variable pressure line
                self._draw_pressure_line(
                    draw,
                    [(x + jx, line_y), (x + total_w + jx, line_y)],
                    ink, base_width=line_w)
            else:
                draw.line([(x + jx, line_y), (x + total_w + jx, line_y)],
                          fill=ink, width=line_w)

            # Denominator (centered below baseline)
            den_x = x + (total_w - den_box.width) / 2
            den_baseline = baseline_y + gap // 2 + den_box.ascent + 2
            self._draw(draw, node.children[1], den_x, den_baseline,
                       int(size * 0.8), ink)

        elif node.kind == 'sup':
            base_box = self._measure(node.children[0], size)
            self._draw(draw, node.children[0], x, baseline_y, size, ink)
            # Superscript: raised and smaller
            sup_y = baseline_y - base_box.ascent * 0.6
            self._draw(draw, node.children[1], x + base_box.width,
                       sup_y, int(size * 0.65), ink)

        elif node.kind == 'sub':
            base_box = self._measure(node.children[0], size)
            self._draw(draw, node.children[0], x, baseline_y, size, ink)
            sub_y = baseline_y + base_box.descent * 0.8
            self._draw(draw, node.children[1], x + base_box.width,
                       sub_y, int(size * 0.65), ink)

        elif node.kind == 'sqrt':
            inner_box = self._measure(node.children[0], size)
            rad_w = size * 0.35
            # Draw radical sign
            pts = [
                (x + jx, baseline_y - inner_box.ascent * 0.3 + jy),
                (x + rad_w * 0.4 + jx, baseline_y + inner_box.descent + jy),
                (x + rad_w + jx, baseline_y - inner_box.ascent - 3 + jy),
                (x + rad_w + inner_box.width + 4 + jx,
                 baseline_y - inner_box.ascent - 3 + jy),
            ]
            lw = random.randint(1, 3) if self.augment else 2
            if self.augment and random.random() < 0.5:
                self._draw_pressure_line(draw, pts, ink, base_width=lw)
            else:
                for i in range(len(pts) - 1):
                    draw.line([pts[i], pts[i + 1]], fill=ink, width=lw)
            self._draw(draw, node.children[0], x + rad_w + 2, baseline_y, size, ink)

        elif node.kind == 'big_op':
            display = DISPLAY_MAP.get(node.text, node.text)
            big_font = self._get_font(int(size * 1.4))
            bbox = big_font.getbbox(display)
            sym_h = bbox[3] - bbox[1]
            sym_w = bbox[2] - bbox[0]
            draw.text((x + jx, baseline_y - sym_h * 0.6 + jy), display,
                      fill=ink, font=big_font)

            if len(node.children) >= 2:
                small_size = int(size * 0.5)
                # Lower limit
                lo_box = self._measure(node.children[0], small_size)
                lo_x = x + (sym_w - lo_box.width) / 2
                self._draw(draw, node.children[0], lo_x,
                           baseline_y + sym_h * 0.5, small_size, ink)
                # Upper limit
                hi_box = self._measure(node.children[1], small_size)
                hi_x = x + (sym_w - hi_box.width) / 2
                self._draw(draw, node.children[1], hi_x,
                           baseline_y - sym_h * 0.7, small_size, ink)

        elif node.kind == 'matrix':
            rows = node.children
            ncols = max(len(r.children) for r in rows) if rows else 1
            cell_size = int(size * 0.75)
            # Measure cells
            max_cell_w, max_cell_h = 0, 0
            for row in rows:
                for child in row.children:
                    cb = self._measure(child, cell_size)
                    max_cell_w = max(max_cell_w, cb.width)
                    max_cell_h = max(max_cell_h, cb.height)
            gap = 6
            bracket_w = size * 0.15
            total_h = len(rows) * max_cell_h + (len(rows) - 1) * gap
            # Draw left bracket
            top_y = baseline_y - total_h * 0.55
            lw = random.randint(1, 2) if self.augment else 2
            draw.line([(x + bracket_w, top_y), (x, top_y), (x, top_y + total_h),
                       (x + bracket_w, top_y + total_h)], fill=ink, width=lw)
            # Draw cells
            for ri, row in enumerate(rows):
                for ci, child in enumerate(row.children):
                    cx = x + bracket_w + 4 + ci * (max_cell_w + gap)
                    cy = top_y + ri * (max_cell_h + gap) + max_cell_h * 0.6
                    self._draw(draw, child, cx, cy, cell_size, ink)
            # Draw right bracket
            right_x = x + bracket_w + 4 + ncols * (max_cell_w + gap)
            draw.line([(right_x - bracket_w, top_y), (right_x, top_y),
                       (right_x, top_y + total_h),
                       (right_x - bracket_w, top_y + total_h)], fill=ink, width=lw)

        elif node.kind == 'group':
            cx = x
            for child in node.children:
                cbox = self._measure(child, size)
                self._draw(draw, child, cx, baseline_y, size, ink)
                cx += cbox.width + 2

    def _display_text(self, text):
        """Convert token to display character."""
        return DISPLAY_MAP.get(text, text)


# ═══════════════════════════════════════════════════════════════════════════════
# FORMULA GENERATOR (builds formula TREES, not flat strings)
# ═══════════════════════════════════════════════════════════════════════════════

def _rv():
    return random.choice('abcdefghijklmnopqrstuvwxyz')

def _RV():
    return random.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ')

def _rn(lo=0, hi=9):
    return str(random.randint(lo, hi))

def _var():
    """Random variable node (20% chance uppercase for full vocab coverage)."""
    v = _RV() if random.random() < 0.2 else _rv()
    return FNode('text', v, tokens=[v])

def _num(lo=0, hi=9):
    n = _rn(lo, hi)
    return FNode('text', n, tokens=list(n))

def _numwide(lo=0, hi=99):
    n = _rn(lo, hi)
    return FNode('text', n, tokens=list(n))

def _op():
    op = random.choice(['+', '-', '='])
    return FNode('text', op, tokens=[op])

def _greek():
    g = random.choice([r'\alpha', r'\beta', r'\gamma', r'\theta', r'\pi',
                        r'\sigma', r'\phi', r'\omega', r'\lambda', r'\mu'])
    return FNode('text', g, tokens=[g])

def _trig():
    f = random.choice([r'\sin', r'\cos', r'\tan'])
    return FNode('text', f, tokens=[f])


def text(s, tokens=None):
    """Create a text node."""
    if tokens is None:
        tokens = list(s) if len(s) <= 2 else [s]
    return FNode('text', s, tokens=tokens)


def frac(num: FNode, den: FNode) -> FNode:
    """Create a fraction node (2D stacked)."""
    toks = [r'\frac', '{'] + num.tokens + ['}', '{'] + den.tokens + ['}']
    return FNode('frac', children=[num, den], tokens=toks)


def sup(base: FNode, exp: FNode) -> FNode:
    """Create a superscript node."""
    if len(exp.tokens) == 1:
        toks = base.tokens + ['^'] + exp.tokens
    else:
        toks = base.tokens + ['^', '{'] + exp.tokens + ['}']
    return FNode('sup', children=[base, exp], tokens=toks)


def sub(base: FNode, subscript: FNode) -> FNode:
    """Create a subscript node."""
    if len(subscript.tokens) == 1:
        toks = base.tokens + ['_'] + subscript.tokens
    else:
        toks = base.tokens + ['_', '{'] + subscript.tokens + ['}']
    return FNode('sub', children=[base, subscript], tokens=toks)


def sqrt_node(inner: FNode) -> FNode:
    toks = [r'\sqrt', '{'] + inner.tokens + ['}']
    return FNode('sqrt', children=[inner], tokens=toks)


def big_op(sym: str, lo: Optional[FNode] = None, hi: Optional[FNode] = None) -> FNode:
    toks = [sym]
    children = []
    if lo:
        toks += ['_', '{'] + lo.tokens + ['}']
        children.append(lo)
    if hi:
        toks += ['^', '{'] + hi.tokens + ['}']
        children.append(hi)
    return FNode('big_op', text=sym, children=children, tokens=toks)


def matrix_node(rows: list) -> FNode:
    """Create a matrix node. rows = list of list of FNode."""
    toks = ['[']  # Use brackets for matrix token
    row_nodes = []
    for ri, row in enumerate(rows):
        row_group = FNode('group', children=row, tokens=[])
        row_toks = []
        for ci, cell in enumerate(row):
            if ci > 0:
                row_toks.append(',')
            row_toks.extend(cell.tokens)
        row_group.tokens = row_toks
        row_nodes.append(row_group)
        toks.extend(row_toks)
        if ri < len(rows) - 1:
            toks.append(' ')
    toks.append(']')
    return FNode('matrix', children=row_nodes, tokens=toks)


def group(*nodes: FNode) -> FNode:
    toks = []
    for i, n in enumerate(nodes):
        if i > 0:
            toks.append(' ')
        toks.extend(n.tokens)
    return FNode('group', children=list(nodes), tokens=toks)


def parens(inner: FNode) -> FNode:
    toks = ['('] + inner.tokens + [')']
    inner_with_parens = FNode('group', children=[
        text('(', ['(']), inner, text(')', [')'])
    ], tokens=toks)
    return inner_with_parens


# ─── Formula generators ──────────────────────────────────────────────────────

FORMULA_GENERATORS = [
    # ── Basic equations ──
    lambda: group(_var(), text('='), _numwide(0, 99)),
    lambda: group(_var(), text('+'), _var(), text('='), _var()),
    lambda: group(_var(), text('-'), _var(), text('='), _numwide()),
    lambda: group(_numwide(1, 9), _var(), text('+'), _numwide(1, 9)),
    lambda: group(_numwide(2, 9), _var(), text('-'), _numwide(1, 9), text('='), text('0')),
    lambda: group(_numwide(2, 5), _var(), text('+'), _numwide(2, 5), _var(),
                  text('='), _numwide(1, 30)),

    # ── Powers (spatial superscript) ──
    lambda: sup(_var(), _num(2, 5)),
    lambda: group(sup(_var(), text('2')), text('+'), sup(_var(), text('2'))),
    lambda: group(sup(_var(), text('2')), text('+'), sup(_var(), text('2')),
                  text('='), sup(_var(), text('2'))),
    lambda: group(sup(_var(), text('2')), text('+'), _numwide(1, 9), _var(),
                  text('+'), _numwide(1, 20), text('='), text('0')),
    lambda: sup(parens(group(_var(), text('+'), _var())), text('2')),
    lambda: sup(text('2'), FNode('text', _rv(), tokens=[_rv()])),
    lambda: sup(_var(), group(_var(), text('+'), _num(1, 5))),

    # ── Fractions (2D stacked!) ──
    lambda: frac(_var(), _var()),
    lambda: frac(_numwide(1, 9), _numwide(1, 9)),
    lambda: frac(group(_var(), text('+'), _var()), _var()),
    lambda: frac(group(_var(), text('-'), _var()), group(_var(), text('+'), _num())),
    lambda: frac(sup(_var(), text('2')), _numwide(2, 9)),
    lambda: group(text('='), frac(_num(1, 9), _num(1, 9))),
    lambda: group(_var(), text('='), frac(_var(), _var())),

    # ── Nested fractions ──
    lambda: frac(frac(_var(), _var()), _var()),
    lambda: frac(_var(), frac(_var(), _var())),
    lambda: frac(group(_var(), text('+'), frac(_num(), _num())), _var()),

    # ── Square roots (with radical sign) ──
    lambda: sqrt_node(_var()),
    lambda: sqrt_node(_numwide(1, 99)),
    lambda: sqrt_node(group(_var(), text('+'), _var())),
    lambda: sqrt_node(group(sup(_var(), text('2')), text('+'), sup(_var(), text('2')))),
    lambda: group(text('='), sqrt_node(group(sup(_var(), text('2')), text('+'),
                                             sup(_var(), text('2'))))),

    # ── Trig functions with argument ──
    lambda: group(_trig(), parens(_var())),
    lambda: group(_var(), text('='), _trig(), parens(_var())),
    lambda: group(sup(_trig(), text('2')), parens(_var()), text('+'),
                  sup(text('cos', [r'\cos']), text('2')), parens(_var()),
                  text('='), text('1')),
    lambda: group(_trig(), parens(group(_numwide(2, 5), _var()))),

    # ── Log / ln ──
    lambda: group(text('log', [r'\log']), parens(_var())),
    lambda: group(text('ln', [r'\ln']), parens(_var())),
    lambda: group(text('ln', [r'\ln']), parens(sup(_var(), _num(2, 5)))),

    # ── Subscripts ──
    lambda: sub(_var(), _num(0, 9)),
    lambda: sub(_var(), _var()),
    lambda: group(sub(_var(), _num(1, 5)), text('+'), sub(_var(), _num(1, 5))),

    # ── Big operators (sum/prod/int with limits) ──
    lambda: big_op(r'\sum', _num(0, 1), _var()),
    lambda: big_op(r'\sum', group(text('i'), text('='), text('0')),
                   _var()),
    lambda: group(big_op(r'\sum', group(text('i'), text('='), text('1')),
                         text('n')), sub(_var(), text('i'))),
    lambda: big_op(r'\int', _num(0, 1), _var()),
    lambda: group(big_op(r'\int', text('0'), text('1')),
                  _var(), text('d'), _var()),
    lambda: group(big_op(r'\int', text('0'), text('∞', [r'\infty'])),
                  sup(text('e'), group(text('-'), _var())),
                  text('d'), _var()),
    lambda: big_op(r'\prod', group(text('i'), text('='), text('1')), text('n')),

    # ── Famous formulas ──
    lambda: group(text('E'), text('='), text('m'), sup(text('c'), text('2'))),
    lambda: group(text('F'), text('='), text('m'), text('a')),
    lambda: group(text('v'), text('='), frac(text('x'), text('t'))),
    lambda: group(text('y'), text('='), text('m'), text('x'), text('+'), text('b')),
    lambda: group(sup(text('a'), text('2')), text('+'), sup(text('b'), text('2')),
                  text('='), sup(text('c'), text('2'))),
    lambda: group(text('A'), text('='), text('π', [r'\pi']), sup(text('r'), text('2'))),
    lambda: group(text('C'), text('='), text('2'), text('π', [r'\pi']), text('r')),
    lambda: group(text('F'), text('='), text('G'), frac(
        group(sub(text('m'), text('1')), sub(text('m'), text('2'))),
        sup(text('r'), text('2')))),

    # ── Inequalities ──
    lambda: group(_var(), text('<'), _numwide(0, 20)),
    lambda: group(_var(), text('>'), _numwide(0, 20)),
    lambda: group(_var(), text('≤', [r'\leq']), _numwide(0, 20)),
    lambda: group(_var(), text('≥', [r'\geq']), _numwide(0, 20)),
    lambda: group(_var(), text('≠', [r'\neq']), _numwide(0, 20)),
    lambda: group(_var(), text('≈', [r'\approx']), _numwide(0, 20)),

    # ── Greek letters ──
    lambda: group(_greek(), text('='), _numwide(0, 99)),
    lambda: group(_greek(), text('+'), _greek(), text('='), _numwide()),
    lambda: frac(_greek(), _greek()),
    lambda: sup(_greek(), text('2')),
    lambda: group(text('ε', [r'\epsilon']), text('>'), text('0')),
    lambda: group(text('δ', [r'\delta']), text('='), frac(text('ε', [r'\epsilon']), _num(2, 5))),
    lambda: group(text('Δ', [r'\Delta']), _var(), text('='), _var(), text('-'), _var()),
    lambda: group(text('Σ', [r'\Sigma']), text('='), text('{'), _var(), text(','), _var(), text('}')),
    lambda: group(text('Φ', [r'\Phi']), parens(_var())),
    lambda: group(text('Ω', [r'\Omega']), text('='), _numwide(1, 50)),

    # ── Limits: lim_{x→a} f(x) ──
    lambda: group(sub(text('lim', [r'\lim']),
                      group(_var(), text('→', [r'\rightarrow']), _num())),
                  _var()),
    lambda: group(sub(text('lim', [r'\lim']),
                      group(_var(), text('→', [r'\rightarrow']), text('∞', [r'\infty']))),
                  frac(text('1'), _var())),

    # ── Partial derivatives ──
    lambda: frac(text('∂', [r'\partial']), group(text('∂', [r'\partial']), _var())),
    lambda: group(frac(text('∂', [r'\partial']), group(text('∂', [r'\partial']), _var())),
                  parens(group(sup(_var(), text('2')), text('+'), _var()))),
    lambda: group(frac(group(text('∂', [r'\partial']), _var()),
                       group(text('∂', [r'\partial']), _var())),
                  text('='), _numwide(0, 9)),

    # ── Set theory / logic (∀, ∃, ∈, ∪, ∩) ──
    lambda: group(text('∀', [r'\forall']), _var(), text('∈', [r'\in']),
                  text('A', ['A'])),
    lambda: group(text('∃', [r'\exists']), _var(), text('>'), text('0')),
    lambda: group(text('A'), text('∪', [r'\cup']), text('B')),
    lambda: group(text('A'), text('∩', [r'\cap']), text('B'), text('='),
                  text('∅', ['{']), text('}', ['}'])),
    lambda: group(text('∀', [r'\forall']), text('ε', [r'\epsilon']), text('>'), text('0'),
                  text(','), text('∃', [r'\exists']), text('δ', [r'\delta']), text('>'), text('0')),

    # ── Arrows ──
    lambda: group(_var(), text('→', [r'\rightarrow']), _var()),
    lambda: group(_var(), text('←', [r'\leftarrow']), _var()),
    lambda: group(text('f'), text(':'), text('A'), text('→', [r'\rightarrow']), text('B')),

    # ── Misc tokens: dots, factorial, abs value, pipes ──
    lambda: group(_var(), text('!'), text('='), _numwide(1, 99)),
    lambda: group(_numwide(1, 9), text('!')),
    lambda: group(text('|'), _var(), text('-'), _num(), text('|'), text('<'),
                  text('ε', [r'\epsilon'])),
    lambda: group(_var(), text('·', [r'\cdot']), _var()),
    lambda: group(_var(), text('±', [r'\pm']), _var()),
    lambda: group(text('1'), text(','), text('2'), text(','),
                  text('…', [r'\ldots']), text(','), _var()),
    lambda: group(_var(), text('.'), _numwide(0, 9)),
    lambda: group(text('×', [r'\times']), _numwide(1, 9)),
    lambda: group(_numwide(1, 9), text('÷', [r'\div']), _numwide(1, 9)),

    # ── Complex expressions ──
    lambda: group(frac(group(text('-'), text('b'), text('±', [r'\pm']),
                       sqrt_node(group(sup(text('b'), text('2')),
                                       text('-'), text('4'), text('a'), text('c')))),
                       group(text('2'), text('a')))),
    lambda: group(text('d'), text('='), sqrt_node(
        group(sup(parens(group(sub(text('x'), text('2')), text('-'),
                               sub(text('x'), text('1')))), text('2')),
              text('+'),
              sup(parens(group(sub(text('y'), text('2')), text('-'),
                               sub(text('y'), text('1')))), text('2'))))),
    lambda: group(text('='), frac(text('1'),
                                  sqrt_node(group(text('2'), text('π', [r'\pi']))))),

    # ── Matrices (2D grid) ──
    lambda: matrix_node([[_var(), _var()], [_var(), _var()]]),
    lambda: matrix_node([[_num(1, 9), _num(0, 9)], [_num(0, 9), _num(1, 9)]]),
    lambda: matrix_node([[_var(), text('0')], [text('0'), _var()]]),
    lambda: group(text('A'), text('='), matrix_node([[_var(), _var()], [_var(), _var()]])),
    lambda: matrix_node([[_num(), _num(), _num()], [_num(), _num(), _num()]]),

    # ═══════════════════════════════════════════════════════════════════════
    # ADVANCED PHYSICS FORMULAS
    # ═══════════════════════════════════════════════════════════════════════

    # ── Combined superscript + subscript (x_i^2) ──
    lambda: sup(sub(_var(), text('i')), text('2')),
    lambda: sup(sub(_var(), _num()), _num(2, 5)),
    lambda: group(big_op(r'\sum', group(text('i'), text('='), text('1')), text('n')),
                  sup(sub(_var(), text('i')), text('2'))),

    # ── Euler's identity ──
    lambda: group(sup(text('e'), group(text('i'), text('π', [r'\pi']))),
                  text('+'), text('1'), text('='), text('0')),

    # ── Gaussian / Normal distribution ──
    lambda: group(text('f'), parens(_var()), text('='),
                  frac(text('1'),
                       sqrt_node(group(text('2'), text('π', [r'\pi'])))),
                  sup(text('e'), group(text('-'),
                      frac(sup(_var(), text('2')), text('2'))))),

    # ── Kinetic energy ──
    lambda: group(sub(text('E'), text('k')), text('='),
                  frac(text('1'), text('2')), text('m'), sup(text('v'), text('2'))),

    # ── Potential energy ──
    lambda: group(sub(text('E'), text('p')), text('='), text('m'), text('g'), text('h')),

    # ── Coulomb's law ──
    lambda: group(text('F'), text('='), text('k'),
                  frac(group(sub(text('q'), text('1')),
                             sub(text('q'), text('2'))),
                       sup(text('r'), text('2')))),

    # ── Ohm's law variants ──
    lambda: group(text('V'), text('='), text('I'), text('R')),
    lambda: group(text('P'), text('='), text('I'), text('V')),
    lambda: group(text('P'), text('='), sup(text('I'), text('2')), text('R')),

    # ── Wave equation ──
    lambda: group(text('v'), text('='), text('f'), text('λ', [r'\lambda'])),
    lambda: group(text('T'), text('='), frac(text('1'), text('f'))),

    # ── Entropy (Boltzmann) ──
    lambda: group(text('S'), text('='), text('k'), text('ln', [r'\ln']),
                  parens(text('Ω', [r'\Omega']))),

    # ── Snell's law ──
    lambda: group(sub(text('n'), text('1')), text('sin', [r'\sin']),
                  parens(sub(text('θ', [r'\theta']), text('1'))),
                  text('='), sub(text('n'), text('2')), text('sin', [r'\sin']),
                  parens(sub(text('θ', [r'\theta']), text('2')))),

    # ── Newton's law of cooling ──
    lambda: group(frac(group(text('d'), text('T')),
                       group(text('d'), text('t'))),
                  text('='), text('-'), text('k'),
                  parens(group(text('T'), text('-'), sub(text('T'), text('0'))))),

    # ═══════════════════════════════════════════════════════════════════════
    # ADVANCED MATH FORMULAS
    # ═══════════════════════════════════════════════════════════════════════

    # ── Taylor series (partial) ──
    lambda: group(text('f'), parens(_var()), text('='),
                  big_op(r'\sum', group(text('n'), text('='), text('0')),
                         text('∞', [r'\infty'])),
                  frac(group(sup(text('f'), parens(text('n')))),
                       group(text('n'), text('!')))),

    # ── Chain rule ──
    lambda: group(frac(group(text('d'), text('y')),
                       group(text('d'), _var())),
                  text('='),
                  frac(group(text('d'), text('y')),
                       group(text('d'), text('u'))),
                  text('·', [r'\cdot']),
                  frac(group(text('d'), text('u')),
                       group(text('d'), _var()))),

    # ── Product rule ──
    lambda: group(parens(group(text('f'), text('g'))), text('='),
                  text('f'), text('g'), text('+'), text('f'), text('g')),

    # ── Integration by parts ──
    lambda: group(big_op(r'\int'), text('u'), text('d'), text('v'),
                  text('='), text('u'), text('v'), text('-'),
                  big_op(r'\int'), text('v'), text('d'), text('u')),

    # ── Double integral ──
    lambda: group(big_op(r'\int'), big_op(r'\int'),
                  text('f'), parens(group(_var(), text(','), _var())),
                  text('d'), _var(), text('d'), _var()),

    # ── Eigenvalue equation ──
    lambda: group(text('A'), _var(), text('='), text('λ', [r'\lambda']), _var()),

    # ── Determinant ──
    lambda: group(text('|'), text('A'), text('|'), text('='),
                  group(sub(_var(), text('1')), sub(_var(), text('2')),
                        text('-'), sub(_var(), text('3')), sub(_var(), text('4')))),

    # ── Complex number forms ──
    lambda: group(_var(), text('='), _var(), text('+'), _var(), text('i')),
    lambda: group(_var(), text('='), _var(),
                  sup(text('e'), group(text('i'), text('θ', [r'\theta'])))),

    # ── Geometric series ──
    lambda: group(big_op(r'\sum', group(text('n'), text('='), text('0')),
                         text('∞', [r'\infty'])),
                  sup(_var(), text('n')), text('='),
                  frac(text('1'), group(text('1'), text('-'), _var()))),

    # ── Power series ──
    lambda: group(big_op(r'\sum', group(text('n'), text('='), text('0')),
                         text('∞', [r'\infty'])),
                  sub(_var(), text('n')),
                  sup(_var(), text('n'))),

    # ── Binomial coefficient (using frac) ──
    lambda: group(parens(frac(text('n'), text('k'))), text('='),
                  frac(group(text('n'), text('!')),
                       group(text('k'), text('!'),
                             parens(group(text('n'), text('-'), text('k'))),
                             text('!')))),

    # ── L'Hôpital's rule ──
    lambda: group(sub(text('lim', [r'\lim']),
                      group(_var(), text('→', [r'\rightarrow']), _var())),
                  frac(text('f'), parens(_var())),
                  text('='),
                  sub(text('lim', [r'\lim']),
                      group(_var(), text('→', [r'\rightarrow']), _var())),
                  frac(text('f'), text('g'))),

    # ── Mean value theorem ──
    lambda: group(text('f'), parens(text('c')), text('='),
                  frac(group(text('f'), parens(text('b')),
                             text('-'), text('f'), parens(text('a'))),
                       group(text('b'), text('-'), text('a')))),

    # ── Definite integral evaluation ──
    lambda: group(big_op(r'\int', _var(), _var()),
                  text('f'), parens(_var()), text('d'), _var(),
                  text('='), text('F'), parens(_var()),
                  text('-'), text('F'), parens(_var())),

    # ── Logarithm rules ──
    lambda: group(text('log', [r'\log']), parens(group(_var(), text('·', [r'\cdot']), _var())),
                  text('='), text('log', [r'\log']), parens(_var()),
                  text('+'), text('log', [r'\log']), parens(_var())),

    # ── Exponential rules ──
    lambda: group(sup(_var(), _var()), text('·', [r'\cdot']),
                  sup(_var(), _var()), text('='),
                  sup(_var(), group(_var(), text('+'), _var()))),

    # ── Trigonometric identities ──
    lambda: group(text('sin', [r'\sin']), parens(group(_var(), text('+'), _var())),
                  text('='), text('sin', [r'\sin']), parens(_var()),
                  text('cos', [r'\cos']), parens(_var()),
                  text('+'), text('cos', [r'\cos']), parens(_var()),
                  text('sin', [r'\sin']), parens(_var())),
    lambda: group(text('tan', [r'\tan']), parens(_var()), text('='),
                  frac(group(text('sin', [r'\sin']), parens(_var())),
                       group(text('cos', [r'\cos']), parens(_var())))),

    # ── Multi-level nesting ──
    lambda: frac(big_op(r'\sum', text('i'), text('n')),
                 sqrt_node(group(text('1'), text('+'), sup(_var(), text('2'))))),
    lambda: sqrt_node(frac(group(_var(), text('+'), _var()),
                           group(_var(), text('-'), _var()))),
    lambda: sup(parens(frac(_var(), _var())), _num(2, 4)),
]


# ═══════════════════════════════════════════════════════════════════════════════
# COMPOSITIONAL FORMULA GENERATOR
#
# Instead of relying only on 137 fixed templates, this generates formulas by
# recursively combining atoms with structural operators — producing INFINITE
# unique structures the model has never seen before.
# ═══════════════════════════════════════════════════════════════════════════════


# Rare tokens that need boosting (appear in vocab but in few templates)
RARE_TOKENS = [
    (r'\partial', '∂'), (r'\forall', '∀'), (r'\exists', '∃'),
    (r'\in', '∈'), (r'\cup', '∪'), (r'\cap', '∩'),
    (r'\Omega', 'Ω'), (r'\Phi', 'Φ'), (r'\Delta', 'Δ'), (r'\Sigma', 'Σ'),
    (r'\leftarrow', '←'), (r'\rightarrow', '→'),
    (r'\neq', '≠'), (r'\approx', '≈'),
    (r'\ldots', '…'), (r'\pm', '±'), (r'\div', '÷'),
    (r'\epsilon', 'ε'), (r'\delta', 'δ'),
]


def _random_atom():
    """Generate a random atomic element with rare-token boosting.

    15% of the time, forces a rare token to ensure the model
    sees symbols like ∂, ∀, ∃, Ω enough times to learn them.
    """
    # ── LEXICAL BOOSTING: inject rare tokens ──
    if random.random() < 0.15:
        tok, display = random.choice(RARE_TOKENS)
        return FNode('text', display, tokens=[tok])

    kind = random.choices(
        ['var', 'num', 'numwide', 'greek'],
        weights=[50, 25, 15, 10],
    )[0]
    if kind == 'var':
        return _var()
    elif kind == 'num':
        return _num()
    elif kind == 'numwide':
        return _numwide()
    else:
        return _greek()


def _random_expr(depth=0, max_depth=3, budget=None, parent_kind=None):
    """Recursively generate a random expression with guardrails.

    Args:
        depth: current recursion depth
        max_depth: maximum allowed depth (hard stop)
        budget: mutable list [remaining_complex_nodes] — prevents runaway
                nesting by limiting total structural nodes (frac/sqrt/big_op)
        parent_kind: the kind of the parent node — prevents same-type nesting
                     (no frac-in-frac-in-frac)
    """
    if budget is None:
        budget = [3]  # Max 3 complex structures per formula

    if depth >= max_depth or budget[0] <= 0:
        return _random_atom()

    # The deeper we go, the MORE likely we pick an atom (steep falloff)
    atom_prob = 0.35 + depth * 0.25  # depth 0→0.35, 1→0.6, 2→0.85

    if random.random() < atom_prob:
        return _random_atom()

    # Build available operations, EXCLUDING parent_kind to prevent same-type
    # nesting (e.g., frac inside frac inside frac)
    ops =    ['binop', 'frac', 'sup', 'sub', 'sqrt', 'parens',
              'func',  'big_op', 'supsub']
    weights = [30,      15,     15,    10,    8,      7,
               6,       5,       4]

    # Remove parent_kind to prevent pathological nesting
    if parent_kind in ops:
        idx = ops.index(parent_kind)
        ops.pop(idx)
        weights.pop(idx)

    kind = random.choices(ops, weights=weights)[0]

    # Complex structures consume budget
    if kind in ('frac', 'sqrt', 'big_op'):
        budget[0] -= 1

    if kind == 'binop':
        op_tok = random.choice(['+', '-', '=', r'\times', r'\cdot'])
        op_display = DISPLAY_MAP.get(op_tok, op_tok)
        left = _random_expr(depth + 1, max_depth, budget, 'binop')
        right = _random_expr(depth + 1, max_depth, budget, 'binop')
        return group(left, text(op_display, [op_tok]), right)

    elif kind == 'frac':
        num = _random_expr(depth + 1, max_depth, budget, 'frac')
        den = _random_expr(depth + 1, max_depth, budget, 'frac')
        return frac(num, den)

    elif kind == 'sup':
        base = _random_expr(depth + 1, max_depth, budget, 'sup')
        exp = _random_atom()  # Exponents always simple
        return sup(base, exp)

    elif kind == 'sub':
        base = _random_expr(depth + 1, max_depth, budget, 'sub')
        idx = _random_atom()
        return sub(base, idx)

    elif kind == 'supsub':
        base = _random_atom()
        subscr = _random_atom()
        superscr = _random_atom()
        return sup(sub(base, subscr), superscr)

    elif kind == 'sqrt':
        inner = _random_expr(depth + 1, max_depth, budget, 'sqrt')
        return sqrt_node(inner)

    elif kind == 'parens':
        inner = _random_expr(depth + 1, max_depth, budget, 'parens')
        return parens(inner)

    elif kind == 'func':
        fn = random.choice([
            (r'\sin', 'sin'), (r'\cos', 'cos'), (r'\tan', 'tan'),
            (r'\log', 'log'), (r'\ln', 'ln'),
        ])
        arg = _random_expr(depth + 1, max_depth, budget, 'func')
        return group(text(fn[1], [fn[0]]), parens(arg))

    elif kind == 'big_op':
        sym = random.choice([r'\sum', r'\int', r'\prod'])
        lo = _random_atom()
        hi = _random_atom()
        body = _random_expr(depth + 1, max_depth, budget, 'big_op')
        return group(big_op(sym, lo, hi), body)

    return _random_atom()


def _random_equation():
    """Generate a complete random equation: LHS = RHS."""
    lhs = _random_expr(depth=0, max_depth=2)
    rhs = _random_expr(depth=0, max_depth=2)
    rel = random.choices(
        ['=', '<', '>', r'\leq', r'\geq'],
        weights=[60, 10, 10, 10, 10],
    )[0]
    rel_display = DISPLAY_MAP.get(rel, rel)
    return group(lhs, text(rel_display, [rel]), rhs)


def _random_definition():
    """Generate random definition: var = expr."""
    v = _var()
    expr = _random_expr(depth=0, max_depth=random.randint(2, 3))
    return group(v, text('='), expr)


def generate_compositional():
    """Generate a compositionally-random formula with guardrails."""
    kind = random.choices(
        ['equation', 'definition', 'expression'],
        weights=[40, 35, 25],
    )[0]
    if kind == 'equation':
        return _random_equation()
    elif kind == 'definition':
        return _random_definition()
    else:
        return _random_expr(depth=0, max_depth=random.randint(2, 3))


def generate_formula():
    """Generate a random formula tree.

    60% from 137 curated templates (reliable, human-like formulas)
    40% from compositional generator (novel structures, guardrailed)
    """
    if random.random() < 0.4:
        # Compositional: generate a random formula
        try:
            f = generate_compositional()
            toks = tokenize_from_tree(f)
            if 4 <= len(toks) <= MAX_SEQ_LEN:  # Reject too-short & too-long
                return f
        except Exception:
            pass

    # Curated template
    gen = random.choice(FORMULA_GENERATORS)
    try:
        return gen()
    except Exception:
        return group(_var(), text('='), _numwide())


def tokenize_from_tree(node: FNode):
    """Get token indices from formula tree."""
    toks = [SOS_IDX]
    for t in node.tokens:
        if t in TOKEN2IDX:
            toks.append(TOKEN2IDX[t])
    toks.append(EOS_IDX)
    return toks


# ═══════════════════════════════════════════════════════════════════════════════
# DATASET
# ═══════════════════════════════════════════════════════════════════════════════


class TopTierDataset(Dataset):
    """2D formula rendering with handwriting fonts + heavy augmentation."""

    def __init__(self, num_samples, fonts, augment=True):
        self.num_samples = num_samples
        self.renderer = Formula2DRenderer(fonts, augment=augment)
        self.augment = augment
        self.transform = transforms.Compose([
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.5], std=[0.5]),
        ])
        # Pre-generate formulas
        self.formulas = []
        for _ in range(num_samples):
            f = generate_formula()
            toks = tokenize_from_tree(f)
            if len(toks) <= MAX_SEQ_LEN:
                self.formulas.append(f)
            else:
                self.formulas.append(group(_var(), text('='), _numwide()))

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        node = self.formulas[idx]
        base_size = random.randint(24, 44) if self.augment else 32
        img = self.renderer.render(node, base_size=base_size)

        # Extra augmentation
        if self.augment:
            img = self._augment(img)

        img_tensor = self.transform(img)
        tokens = tokenize_from_tree(node)
        padded = tokens + [PAD_IDX] * (MAX_SEQ_LEN - len(tokens))
        return img_tensor, torch.tensor(padded[:MAX_SEQ_LEN], dtype=torch.long)

    def _augment(self, img):
        # Rotation
        img = img.rotate(random.uniform(-6, 6), fillcolor=255)

        # ── PERSPECTIVE / AFFINE TRANSFORM (tablet at angle) ──
        if random.random() < 0.3:
            img = self._perspective_transform(img)

        arr = np.array(img, dtype=np.float32)

        # ── 1. ELASTIC DISTORTION (the ink secret) ──
        if HAS_SCIPY and random.random() < 0.5:
            alpha = random.uniform(15, 35)
            sigma = random.uniform(3, 5)
            h, w = arr.shape
            dx = gaussian_filter(np.random.randn(h, w) * alpha, sigma)
            dy = gaussian_filter(np.random.randn(h, w) * alpha, sigma)
            y_grid, x_grid = np.meshgrid(np.arange(h), np.arange(w), indexing='ij')
            indices = [np.clip(y_grid + dy, 0, h - 1), np.clip(x_grid + dx, 0, w - 1)]
            arr = map_coordinates(arr, indices, order=1, mode='constant', cval=255)

        # Noise
        arr += np.random.normal(0, random.uniform(3, 12), arr.shape)
        arr = np.clip(arr, 0, 255)

        # Line jitter (simulates shaky hand)
        for row in range(0, arr.shape[0], random.randint(4, 10)):
            shift = random.randint(-1, 1)
            if shift:
                arr[row] = np.roll(arr[row], shift)

        img = Image.fromarray(arr.astype(np.uint8))

        # Blur
        if random.random() < 0.35:
            img = img.filter(ImageFilter.GaussianBlur(random.uniform(0.3, 1.0)))

        # Brightness variation
        if random.random() < 0.25:
            arr = np.array(img, dtype=np.float32) + random.uniform(-12, 12)
            img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

        # Erosion/dilation (stroke thickness)
        if random.random() < 0.25:
            if random.random() < 0.5:
                img = img.filter(ImageFilter.MinFilter(3))
            else:
                img = img.filter(ImageFilter.MaxFilter(3))

        # ── RANDOM ERASING (simulates occlusion / finger covering part) ──
        if random.random() < 0.2:
            arr2 = np.array(img, dtype=np.float32)
            h, w = arr2.shape
            eh = random.randint(h // 8, h // 3)
            ew = random.randint(w // 8, w // 3)
            ey = random.randint(0, h - eh)
            ex = random.randint(0, w - ew)
            arr2[ey:ey+eh, ex:ex+ew] = 255  # white rectangle
            img = Image.fromarray(arr2.astype(np.uint8))

        # ── BACKGROUND TEXTURES (grid, paper, dark canvas) ──
        if random.random() < 0.4:
            img = self._add_background(img)

        return img

    def _perspective_transform(self, img):
        """Apply random perspective/affine distortion (simulates tablet angle)."""
        w, h = img.size
        # Random quad (slight perspective warp)
        margin = random.uniform(0.02, 0.08)
        mw, mh = w * margin, h * margin
        # Source corners
        coeffs = [
            random.uniform(-mw, mw), random.uniform(-mh, mh),   # top-left
            w + random.uniform(-mw, mw), random.uniform(-mh, mh),  # top-right
            w + random.uniform(-mw, mw), h + random.uniform(-mh, mh),  # bottom-right
            random.uniform(-mw, mw), h + random.uniform(-mh, mh),  # bottom-left
        ]
        # Compute perspective transform coefficients
        try:
            img = img.transform((w, h), Image.PERSPECTIVE,
                                self._find_coeffs(
                                    [(0, 0), (w, 0), (w, h), (0, h)],
                                    [(coeffs[0], coeffs[1]), (coeffs[2], coeffs[3]),
                                     (coeffs[4], coeffs[5]), (coeffs[6], coeffs[7])]),
                                Image.BICUBIC, fillcolor=255)
        except Exception:
            pass  # Skip if transform fails
        return img

    @staticmethod
    def _find_coeffs(source_coords, target_coords):
        """Compute perspective transform coefficients."""
        matrix = []
        for s, t in zip(source_coords, target_coords):
            matrix.append([t[0], t[1], 1, 0, 0, 0, -s[0]*t[0], -s[0]*t[1]])
            matrix.append([0, 0, 0, t[0], t[1], 1, -s[1]*t[0], -s[1]*t[1]])
        A = np.matrix(matrix, dtype=np.float64)
        B = np.array([c for p in source_coords for c in p]).reshape(8)
        res = np.dot(np.linalg.inv(A.T * A) * A.T, B)
        return np.array(res).reshape(8).tolist()

    def _add_background(self, img):
        """Simulate grid paper, ruled lines, or dark canvas backgrounds."""
        arr = np.array(img, dtype=np.float32)
        h, w = arr.shape
        bg_type = random.choice(['grid', 'ruled', 'dots', 'dark', 'paper'])

        if bg_type == 'grid':
            # Square grid (graph paper)
            spacing = random.randint(12, 24)
            grid_color = random.uniform(210, 235)
            for y in range(0, h, spacing):
                arr[y, :] = np.minimum(arr[y, :], grid_color)
            for x in range(0, w, spacing):
                arr[:, x] = np.minimum(arr[:, x], grid_color)

        elif bg_type == 'ruled':
            # Horizontal ruled lines (notebook)
            spacing = random.randint(14, 26)
            line_color = random.uniform(200, 230)
            for y in range(spacing, h, spacing):
                arr[y, :] = np.minimum(arr[y, :], line_color)

        elif bg_type == 'dots':
            # Dot grid
            spacing = random.randint(12, 22)
            dot_color = random.uniform(200, 230)
            for y in range(spacing, h, spacing):
                for x in range(spacing, w, spacing):
                    if 0 <= y < h and 0 <= x < w:
                        arr[y, x] = min(arr[y, x], dot_color)

        elif bg_type == 'dark':
            # Dark canvas (invert: white ink on dark background)
            arr = 255 - arr
            arr = np.clip(arr + random.uniform(-20, 20), 0, 255)

        elif bg_type == 'paper':
            # Paper texture (light noise on background)
            paper_noise = np.random.normal(0, random.uniform(3, 8), arr.shape)
            bg_mask = arr > 200  # only affect background pixels
            arr[bg_mask] += paper_noise[bg_mask]
            arr = np.clip(arr, 0, 255)

        return Image.fromarray(arr.astype(np.uint8))


# ═══════════════════════════════════════════════════════════════════════════════
# TRAINING
# ═══════════════════════════════════════════════════════════════════════════════


def train_epoch(model, loader, optimizer, criterion, device, scaler=None):
    """Train one epoch with optional AMP and GPU OOM protection."""
    model.train()
    total_loss, n = 0, 0
    for images, tokens in tqdm(loader, desc='  Train', leave=False):
        images, tokens = images.to(device), tokens.to(device)

        try:
            optimizer.zero_grad()
            if scaler is not None:  # AMP enabled
                with autocast(device_type='cuda', dtype=torch.float16):
                    logits = model(images, tokens[:, :-1])
                    B, S, V = logits.shape
                    loss = criterion(logits.reshape(B * S, V), tokens[:, 1:].reshape(B * S))
                if not math.isfinite(loss.item()):
                    continue
                scaler.scale(loss).backward()
                scaler.unscale_(optimizer)
                torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
                scaler.step(optimizer)
                scaler.update()
            else:  # CPU or no AMP
                logits = model(images, tokens[:, :-1])
                B, S, V = logits.shape
                loss = criterion(logits.reshape(B * S, V), tokens[:, 1:].reshape(B * S))
                if not math.isfinite(loss.item()):
                    continue
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
                optimizer.step()

            total_loss += loss.item()
            n += 1
        except RuntimeError as e:
            if 'out of memory' in str(e):
                print('⚠️  GPU OOM — skipping batch')
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                continue
            raise
    return total_loss / max(n, 1)


def greedy_decode(model, image, device):
    model.eval()
    with torch.no_grad():
        features = model.encoder(image.to(device))
        tokens = [SOS_IDX]
        for _ in range(MAX_SEQ_LEN):
            tgt = torch.tensor([tokens], dtype=torch.long, device=device)
            logits = model.decoder(tgt, features)
            t = logits[0, -1].argmax().item()
            if t == EOS_IDX:
                break
            tokens.append(t)
        return tokens[1:]


def beam_search_decode(model, image, device, beam_width=5, length_penalty=0.6):
    """Beam search with length normalization for accurate evaluation.

    Length penalty prevents bias toward shorter sequences (critical for
    complex formulas like quadratics, Taylor series, etc.).
    """
    model.eval()
    with torch.no_grad():
        features = model.encoder(image.to(device))

        # Each beam: (raw_log_prob, token_list)
        beams = [(0.0, [SOS_IDX])]

        for step in range(MAX_SEQ_LEN):
            new_beams = []
            for score, tokens in beams:
                if tokens[-1] == EOS_IDX:
                    new_beams.append((score, tokens))
                    continue
                tgt = torch.tensor([tokens], dtype=torch.long, device=device)
                logits = model.decoder(tgt, features)
                log_probs = torch.log_softmax(logits[0, -1], dim=-1)
                top_k = log_probs.topk(beam_width)
                for i in range(beam_width):
                    new_score = score + top_k.values[i].item()
                    new_tokens = tokens + [top_k.indices[i].item()]
                    new_beams.append((new_score, new_tokens))

            # Sort by LENGTH-NORMALIZED score (prevents short-sequence bias)
            def normalized_score(beam):
                score, tokens = beam
                length = len(tokens) - 1  # exclude SOS
                return score / (length ** length_penalty) if length > 0 else score

            new_beams.sort(key=normalized_score, reverse=True)
            beams = new_beams[:beam_width]

            # Early stop if all beams ended
            if all(b[1][-1] == EOS_IDX for b in beams):
                break

        best = beams[0][1]
        result = [t for t in best[1:] if t != EOS_IDX]
        return result


def tokens_to_latex(ids):
    return ' '.join(IDX2TOKEN.get(i, '?') for i in ids)


def _levenshtein(s1, s2):
    """Compute Levenshtein (edit) distance between two lists."""
    if len(s1) < len(s2):
        return _levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    prev = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        curr = [i + 1]
        for j, c2 in enumerate(s2):
            curr.append(min(prev[j + 1] + 1, curr[j] + 1,
                            prev[j] + (0 if c1 == c2 else 1)))
        prev = curr
    return prev[-1]


def evaluate(model, loader, device, max_samples=200, use_beam=True):
    """Evaluate with both exact match accuracy AND Character Error Rate (CER)."""
    model.eval()
    correct, total, printed = 0, 0, 0
    total_cer_num, total_cer_den = 0, 0  # CER numerator/denominator
    decode_fn = (lambda img: beam_search_decode(model, img, device, beam_width=5)) \
        if use_beam else (lambda img: greedy_decode(model, img, device))
    with torch.no_grad():
        for images, tokens in loader:
            for i in range(images.size(0)):
                if total >= max_samples:
                    break
                gt = [t for t in tokens[i].tolist() if t != SOS_IDX]
                gt = gt[:gt.index(EOS_IDX)] if EOS_IDX in gt else [t for t in gt if t != PAD_IDX]
                pred = decode_fn(images[i:i + 1])
                gs, ps = tokens_to_latex(gt), tokens_to_latex(pred)
                if ps == gs:
                    correct += 1
                # CER: edit_distance / gt_length
                edit_dist = _levenshtein(gt, pred)
                total_cer_num += edit_dist
                total_cer_den += max(len(gt), 1)
                total += 1
                if printed < 8:
                    print(f"  {'✅' if ps == gs else '❌'} GT:   {gs}")
                    print(f"     Pred: {ps}")
                    printed += 1
            if total >= max_samples:
                break
    acc = correct / max(total, 1)
    cer = total_cer_num / max(total_cer_den, 1)
    return acc, cer


def export_onnx(model, output_dir='hme_attn_onnx'):
    model.eval()
    m = model.cpu()
    os.makedirs(output_dir, exist_ok=True)
    dummy = torch.randn(1, 1, IMG_HEIGHT, IMG_WIDTH)
    torch.onnx.export(EncoderWrapper(m.encoder), dummy,
                      f'{output_dir}/hme_encoder.onnx', opset_version=14, dynamo=False,
                      input_names=['image'], output_names=['features'])
    print(f"  ✅ Encoder: {os.path.getsize(f'{output_dir}/hme_encoder.onnx') / 1e6:.1f} MB")
    with torch.no_grad():
        feat = m.encoder(dummy)
    torch.onnx.export(DecoderWrapper(m.decoder),
                      (torch.tensor([[1, 10, 20]], dtype=torch.long), feat),
                      f'{output_dir}/hme_decoder.onnx', opset_version=14, dynamo=False,
                      input_names=['tokens', 'memory'], output_names=['logits'],
                      dynamic_axes={'tokens': {1: 'seq_len'}, 'logits': {1: 'seq_len'}})
    print(f"  ✅ Decoder: {os.path.getsize(f'{output_dir}/hme_decoder.onnx') / 1e6:.1f} MB")
    return model.to(device)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    EPOCHS = 200
    TRAIN_SAMPLES = 60_000
    VAL_SAMPLES = 3_000
    BATCH_SIZE = 64
    LR = 3e-4
    CHECKPOINT = 'best_hme_top_tier.pt'

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"🖥  Device: {device}")
    if device.type == 'cuda':
        print(f"   GPU: {torch.cuda.get_device_name()}")

    print(f"📚 Vocabulary: {VOCAB_SIZE} tokens")
    print(f"📝 Formula generators: {len(FORMULA_GENERATORS)}")

    vocab = {'token2idx': TOKEN2IDX, 'idx2token': {str(k): v for k, v in IDX2TOKEN.items()}}
    with open('hme_attn_vocab.json', 'w') as f:
        json.dump(vocab, f, indent=2)

    print("\n🖊  Downloading handwriting fonts...")
    fonts = download_fonts()
    print(f"   {len(fonts)} fonts available")
    if not fonts:
        print("❌ No fonts!")
        exit(1)

    print(f"\n📊 Creating 2D formula datasets ({TRAIN_SAMPLES:,} train, {VAL_SAMPLES:,} val)...")
    train_ds = TopTierDataset(TRAIN_SAMPLES, fonts, augment=True)
    val_ds = TopTierDataset(VAL_SAMPLES, fonts, augment=False)
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True,
                              num_workers=2, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False,
                            num_workers=2, pin_memory=True)

    model = HMEAttentionModel(vocab_size=VOCAB_SIZE, d_model=256).to(device)
    params = sum(p.numel() for p in model.parameters())
    print(f"🧠 Model: {params:,} parameters")

    # ⚠️  ONLY load from OUR OWN checkpoint (100% commercial safe)
    # DO NOT load from CROHME/academic checkpoints — their license is research-only!
    if os.path.exists(CHECKPOINT):
        try:
            model.load_state_dict(torch.load(CHECKPOINT, map_location=device), strict=False)
            print(f"📂 Resumed from {CHECKPOINT}")
        except Exception as e:
            print(f"⚠️  Could not load {CHECKPOINT}: {e}")
    else:
        print("🆕 Training from scratch (no prior checkpoint)")

    # ── EMA (Exponential Moving Average) for better generalization ──
    ema_decay = 0.999
    ema_state = {k: v.clone() for k, v in model.state_dict().items()}

    def update_ema():
        with torch.no_grad():
            for k, v in model.state_dict().items():
                ema_state[k].mul_(ema_decay).add_(v, alpha=1 - ema_decay)

    def apply_ema():
        """Swap model weights with EMA weights for evaluation."""
        backup = {k: v.clone() for k, v in model.state_dict().items()}
        model.load_state_dict(ema_state)
        return backup

    def restore_from_ema(backup):
        model.load_state_dict(backup)

    # ── LABEL SMOOTHING ──
    criterion = nn.CrossEntropyLoss(ignore_index=PAD_IDX, label_smoothing=0.1)
    optimizer = optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4)

    # ── AMP (Mixed Precision) — 2x speed on T4 ──
    use_amp = device.type == 'cuda'
    scaler = GradScaler() if use_amp else None
    if use_amp:
        print("⚡ AMP enabled (float16 mixed precision)")

    # ── LINEAR WARMUP + COSINE DECAY ──
    WARMUP_EPOCHS = 5

    def lr_lambda(epoch):
        if epoch < WARMUP_EPOCHS:
            return epoch / max(WARMUP_EPOCHS, 1)
        progress = (epoch - WARMUP_EPOCHS) / max(EPOCHS - WARMUP_EPOCHS, 1)
        return 0.5 * (1 + math.cos(math.pi * progress))

    scheduler = optim.lr_scheduler.LambdaLR(optimizer, lr_lambda)

    best_acc = 0.0
    patience_counter = 0
    PATIENCE = 20  # Early stopping: stop if no improvement for 20 eval cycles

    print(f"\n🏋️ Training for {EPOCHS} epochs (DEFINITIVE TOP TIER)...")
    print(f"   Features: 2D rendering, elastic distortion, perspective, warmup,")
    print(f"   label smoothing, AMP, beam search, EMA, backgrounds, {len(FORMULA_GENERATORS)} templates")
    print(f"   Early stopping patience: {PATIENCE} eval cycles\n")

    for epoch in range(1, EPOCHS + 1):
        t0 = time.time()
        loss = train_epoch(model, train_loader, optimizer, criterion, device, scaler)
        scheduler.step()
        update_ema()  # Update EMA weights
        elapsed = time.time() - t0

        if epoch % 10 == 0 or epoch <= 5:
            # Evaluate with EMA weights
            backup = apply_ema()
            acc, cer = evaluate(model, val_loader, device)
            restore_from_ema(backup)

            lr = optimizer.param_groups[0]['lr']
            print(f"\nEpoch {epoch}/{EPOCHS} — Loss: {loss:.4f} | "
                  f"Acc: {acc:.1%} | CER: {cer:.3f} | LR: {lr:.6f} | {elapsed:.0f}s")
            if acc > best_acc:
                best_acc = acc
                patience_counter = 0
                # Save EMA weights (better for inference)
                torch.save(ema_state, CHECKPOINT)
                print(f"  💾 Saved best EMA (acc: {best_acc:.1%}, CER: {cer:.3f})")
            else:
                patience_counter += 1
                if patience_counter >= PATIENCE:
                    print(f"\n⏹  Early stopping! No improvement for {PATIENCE} eval cycles.")
                    break
            print()
        else:
            if epoch % 5 == 0:
                print(f"Epoch {epoch}/{EPOCHS} — Loss: {loss:.4f} | {elapsed:.0f}s")
        if epoch % 50 == 0:
            export_onnx(model, f'onnx_ep{epoch}')

    print(f"\n{'=' * 60}")
    print(f"Training complete! Best accuracy: {best_acc:.1%}")
    model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
    export_onnx(model, 'hme_attn_onnx')

    # ── ONNX INT8 QUANTIZATION (mobile-ready) ──
    try:
        from onnxruntime.quantization import quantize_dynamic, QuantType
        print("\n📉 Quantizing models to Int8 for mobile...")
        quantize_dynamic(
            'hme_attn_onnx/hme_encoder.onnx',
            'hme_attn_onnx/hme_encoder_int8.onnx',
            weight_type=QuantType.QUInt8)
        quantize_dynamic(
            'hme_attn_onnx/hme_decoder.onnx',
            'hme_attn_onnx/hme_decoder_int8.onnx',
            weight_type=QuantType.QUInt8)
        enc_mb = os.path.getsize('hme_attn_onnx/hme_encoder_int8.onnx') / 1e6
        dec_mb = os.path.getsize('hme_attn_onnx/hme_decoder_int8.onnx') / 1e6
        print(f"  ✅ Encoder Int8: {enc_mb:.1f} MB")
        print(f"  ✅ Decoder Int8: {dec_mb:.1f} MB")
    except ImportError:
        print("\n⚠️  onnxruntime.quantization not found — skip quantization")
        print("   Install: pip install onnxruntime")

    print(f"\n✅ Files to download (100% commercial safe!):")
    print(f"   📦 hme_attn_onnx/hme_encoder.onnx (float32)")
    print(f"   📦 hme_attn_onnx/hme_decoder.onnx (float32)")
    print(f"   📦 hme_attn_onnx/hme_encoder_int8.onnx (quantized!)")
    print(f"   📦 hme_attn_onnx/hme_decoder_int8.onnx (quantized!)")
    print(f"   📝 hme_attn_vocab.json")
    print(f"\n   🛡️  All fonts Apache 2.0 / OFL licensed")
    print(f"   🏆 DEFINITIVE TOP TIER — 2D, elastic, pressure, quantized!")
