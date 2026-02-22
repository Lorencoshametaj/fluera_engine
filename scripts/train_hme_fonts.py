#!/usr/bin/env python3
"""
🧮 HME Attention Training v3 — Handwriting Fonts (100% Commercial Safe)

Uses Google Fonts handwriting fonts (Apache 2.0 / OFL licensed) to generate
realistic handwritten-looking math formulas. Zero legal risk for commercial use.

Fonts used: Caveat, Indie Flower, Patrick Hand, Kalam, Coming Soon,
            Gloria Hallelujah, Permanent Marker, Architects Daughter

Usage on Colab (T4 GPU):
  !pip install onnxscript scipy
  !python train_hme_fonts.py
"""

import json
import math
import os
import random
import time
import subprocess

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.models as models
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms

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
        self.pool = nn.AdaptiveAvgPool2d((1, None))
        self.proj = nn.Linear(512, d_model)

    def forward(self, x):
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        x = self.pool(x)
        x = x.squeeze(2)
        x = x.permute(0, 2, 1)
        x = self.proj(x)
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
        x = self.transformer_decoder(tgt=x, memory=memory, tgt_mask=self.causal_mask[:S, :S])
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
# GOOGLE FONTS DOWNLOAD
# ═══════════════════════════════════════════════════════════════════════════════

HANDWRITING_FONTS = {
    # Font name: Google Fonts download URL (all Apache 2.0 or OFL licensed)
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
}


def download_fonts(font_dir='hw_fonts'):
    """Download handwriting fonts from Google Fonts (Apache 2.0 / OFL)."""
    os.makedirs(font_dir, exist_ok=True)
    downloaded = []

    for name, url in HANDWRITING_FONTS.items():
        path = os.path.join(font_dir, f'{name}.ttf')
        if os.path.exists(path) and os.path.getsize(path) > 1000:
            downloaded.append(path)
            continue

        try:
            subprocess.run(['wget', '-q', '-O', path, url],
                           check=True, timeout=30)
            if os.path.getsize(path) > 1000:
                downloaded.append(path)
                print(f"   ✅ {name}")
            else:
                os.remove(path)
        except Exception as e:
            print(f"   ❌ {name}: {e}")

    # Also include system fonts as fallback
    system_fonts = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
    ]
    for p in system_fonts:
        if os.path.exists(p):
            downloaded.append(p)

    return downloaded


# ═══════════════════════════════════════════════════════════════════════════════
# FORMULA TEMPLATES (much more diverse than v1)
# ═══════════════════════════════════════════════════════════════════════════════

def _rv():
    """Random variable."""
    return random.choice('abcdefghijklmnopqrstuvwxyz')

def _rn(lo=0, hi=99):
    """Random number."""
    return str(random.randint(lo, hi))

def _rop():
    """Random operator."""
    return random.choice(['+', '-', '='])


# More diverse templates for complex formulas
FORMULA_TEMPLATES = [
    # ── Basic ──
    lambda: f"{_rv()} = {_rn()}",
    lambda: f"{_rv()} = {_rv()}",
    lambda: f"{_rv()} + {_rv()} = {_rv()}",
    lambda: f"{_rv()} - {_rv()} = {_rn()}",
    lambda: f"{_rn(1,9)} + {_rn(1,9)} = {_rn(2,18)}",
    lambda: f"{_rn(1,9)} - {_rn(1,9)} = {_rn(-8,8)}",
    lambda: f"{_rn(2,9)} x = {_rn(1,50)}",

    # ── Coefficients ──
    lambda: f"{_rn(2,9)} {_rv()} + {_rn(1,9)}",
    lambda: f"{_rn(2,9)} {_rv()} - {_rn(1,9)} = 0",
    lambda: f"{_rn(2,5)} {_rv()} + {_rn(2,5)} {_rv()} = {_rn(1,30)}",

    # ── Powers ──
    lambda: f"{_rv()} ^ {_rn(2,5)}",
    lambda: f"{_rv()} ^ 2 + {_rv()} ^ 2",
    lambda: f"{_rv()} ^ 2 + {_rv()} ^ 2 = {_rv()} ^ 2",
    lambda: f"{_rv()} ^ 2 + {_rn(1,9)} {_rv()} + {_rn(1,20)} = 0",
    lambda: f"{_rv()} ^ 2 - {_rn(1,9)} {_rv()} + {_rn(1,20)} = 0",
    lambda: f"( {_rv()} + {_rv()} ) ^ 2",
    lambda: f"( {_rv()} - {_rv()} ) ^ 2",
    lambda: f"{_rv()} ^ {{ {_rv()} + {_rn(1,5)} }}",
    lambda: f"2 ^ {{ {_rv()} }}",

    # ── Fractions ──
    lambda: f"{_rv()} / {_rv()}",
    lambda: f"v = {_rv()} / t",
    lambda: f"{{ {_rv()} + {_rv()} }} / {{ {_rv()} }}",
    lambda: f"{{ {_rn(1,9)} }} / {{ {_rn(1,9)} }}",
    lambda: f"{{ {_rv()} ^ 2 }} / {{ {_rv()} }}",

    # ── Trig functions ──
    lambda: f"sin ( {_rv()} )",
    lambda: f"cos ( {_rv()} )",
    lambda: f"tan ( {_rv()} )",
    lambda: f"{_rv()} = sin ( {_rv()} )",
    lambda: f"{_rv()} = cos ( {_rv()} )",
    lambda: f"sin ^ 2 ( {_rv()} ) + cos ^ 2 ( {_rv()} ) = 1",

    # ── Log / ln ──
    lambda: f"log ( {_rv()} )",
    lambda: f"ln ( {_rv()} )",
    lambda: f"log ( {_rv()} {_rv()} )",
    lambda: f"ln ( {_rv()} ^ {_rn(2,5)} )",

    # ── Famous formulas ──
    lambda: "E = m c ^ 2",
    lambda: "F = m a",
    lambda: "v = x / t",
    lambda: "y = m x + b",
    lambda: "a ^ 2 + b ^ 2 = c ^ 2",
    lambda: "A = l w",
    lambda: "P = 2 ( l + w )",
    lambda: "V = l w h",
    lambda: "A = p r ^ 2",
    lambda: "C = 2 p r",
    lambda: "d = v t",
    lambda: "F = k x",

    # ── Inequalities ──
    lambda: f"{_rv()} < {_rn(0,20)}",
    lambda: f"{_rv()} > {_rn(0,20)}",
    lambda: f"{_rv()} + {_rv()} < {_rn(1,30)}",

    # ── Multi-variable ──
    lambda: f"{_rv()} + {_rv()} - {_rv()} = {_rn(0,10)}",
    lambda: f"{_rv()} {_rop()} {_rv()} = {_rv()} {_rop()} {_rv()}",
    lambda: f"{{ {_rv()} + {_rv()} }} {{ {_rv()} - {_rv()} }}",

    # ── Subscripts ──
    lambda: f"{_rv()} _ {_rn(0,9)}",
    lambda: f"{_rv()} _ {{ {_rv()} }}",
    lambda: f"{_rv()} _ {_rn(1,5)} + {_rv()} _ {_rn(1,5)}",

    # ── Combined ──
    lambda: f"{_rn(2,9)} {_rv()} ^ 2 + {_rn(1,9)} {_rv()} - {_rn(1,20)}",
    lambda: f"( {_rv()} + {_rn(1,9)} ) ( {_rv()} - {_rn(1,9)} )",
    lambda: f"| {_rv()} - {_rn(1,9)} | < {_rn(1,10)}",
]


def tokenize_latex(latex_str):
    tokens = [SOS_IDX]
    i = 0
    while i < len(latex_str):
        if latex_str[i] == ' ':
            if ' ' in TOKEN2IDX:
                tokens.append(TOKEN2IDX[' '])
            i += 1
            continue
        if latex_str[i] == '\\':
            j = i + 1
            while j < len(latex_str) and latex_str[j].isalpha():
                j += 1
            cmd = latex_str[i:j]
            if cmd in TOKEN2IDX:
                tokens.append(TOKEN2IDX[cmd])
            i = j
            continue
        char = latex_str[i]
        if char in TOKEN2IDX:
            tokens.append(TOKEN2IDX[char])
        i += 1
    tokens.append(EOS_IDX)
    return tokens


# ═══════════════════════════════════════════════════════════════════════════════
# DATASET WITH HANDWRITING FONTS + HEAVY AUGMENTATION
# ═══════════════════════════════════════════════════════════════════════════════


class HandwritingFontDataset(Dataset):
    """Renders formulas with handwriting fonts + heavy augmentation.

    Augmentations simulate real handwriting:
    - Per-character jitter (wobble)
    - Variable stroke thickness
    - Rotation, skew
    - Noise, blur
    - Ink color variation
    - Background texture
    """

    def __init__(self, num_samples, fonts, augment=True):
        self.num_samples = num_samples
        self.fonts = fonts
        self.augment = augment
        self.formulas = [random.choice(FORMULA_TEMPLATES)() for _ in range(num_samples)]
        self.transform = transforms.Compose([
            transforms.Resize((IMG_HEIGHT, IMG_WIDTH)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.5], std=[0.5]),
        ])

    def _render_with_jitter(self, formula, font_path, font_size):
        """Render formula with per-character position jitter (simulates handwriting)."""
        img = Image.new('L', (IMG_WIDTH, IMG_HEIGHT), color=255)
        draw = ImageDraw.Draw(img)

        try:
            font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()
        except (IOError, OSError):
            font = ImageFont.load_default()

        # Measure total width
        total_w = 0
        char_widths = []
        for ch in formula:
            bbox = draw.textbbox((0, 0), ch, font=font)
            w = bbox[2] - bbox[0]
            char_widths.append(w)
            total_w += w

        # Starting position (centered)
        x = max(5, (IMG_WIDTH - total_w) // 2)
        base_y = max(5, (IMG_HEIGHT - font_size) // 2)

        ink = random.randint(0, 50) if self.augment else 0

        # Draw char by char with jitter
        for i, ch in enumerate(formula):
            if self.augment:
                jitter_x = random.uniform(-2, 2)
                jitter_y = random.uniform(-3, 3)
            else:
                jitter_x, jitter_y = 0, 0

            draw.text((x + jitter_x, base_y + jitter_y), ch, fill=ink, font=font)
            x += char_widths[i] + random.uniform(-1, 1) if self.augment else char_widths[i]

        return img

    def _augment_image(self, img):
        """Apply heavy augmentation to simulate real handwriting."""
        # Random rotation
        angle = random.uniform(-8, 8)
        img = img.rotate(angle, fillcolor=255, expand=False)

        # Elastic-like distortion (simpler, no scipy needed)
        arr = np.array(img, dtype=np.float32)

        # Line-level vertical shift
        for row in range(0, arr.shape[0], random.randint(3, 8)):
            shift = random.randint(-2, 2)
            if shift != 0:
                arr[row] = np.roll(arr[row], shift)

        # Gaussian noise
        noise = np.random.normal(0, random.uniform(3, 15), arr.shape)
        arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
        img = Image.fromarray(arr)

        # Blur
        if random.random() < 0.4:
            img = img.filter(ImageFilter.GaussianBlur(
                radius=random.uniform(0.3, 1.2)))

        # Background brightness variation
        if random.random() < 0.3:
            arr = np.array(img, dtype=np.float32)
            arr += random.uniform(-15, 15)
            img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

        # Random erosion/dilation (thicker/thinner strokes)
        if random.random() < 0.3:
            from PIL import ImageFilter as IF
            if random.random() < 0.5:
                img = img.filter(IF.MinFilter(3))  # thicker
            else:
                img = img.filter(IF.MaxFilter(3))  # thinner

        return img

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        formula = self.formulas[idx]
        font_path = random.choice(self.fonts)
        font_size = random.randint(20, 48) if self.augment else 32

        img = self._render_with_jitter(formula, font_path, font_size)

        if self.augment:
            img = self._augment_image(img)

        img_tensor = self.transform(img)
        tokens = tokenize_latex(formula)
        padded = tokens + [PAD_IDX] * (MAX_SEQ_LEN - len(tokens))
        return img_tensor, torch.tensor(padded[:MAX_SEQ_LEN], dtype=torch.long)


# ═══════════════════════════════════════════════════════════════════════════════
# TRAINING
# ═══════════════════════════════════════════════════════════════════════════════


def train_epoch(model, loader, optimizer, criterion, device):
    model.train()
    total_loss, n = 0, 0
    for images, tokens in loader:
        images, tokens = images.to(device), tokens.to(device)
        logits = model(images, tokens[:, :-1])
        B, S, V = logits.shape
        loss = criterion(logits.reshape(B * S, V), tokens[:, 1:].reshape(B * S))
        if not math.isfinite(loss.item()):
            continue
        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
        optimizer.step()
        total_loss += loss.item()
        n += 1
    return total_loss / max(n, 1)


def greedy_decode(model, image, device):
    model.eval()
    with torch.no_grad():
        features = model.encoder(image.to(device))
        tokens = [SOS_IDX]
        for _ in range(MAX_SEQ_LEN):
            tgt = torch.tensor([tokens], dtype=torch.long, device=device)
            logits = model.decoder(tgt, features)
            next_tok = logits[0, -1].argmax().item()
            if next_tok == EOS_IDX:
                break
            tokens.append(next_tok)
        return tokens[1:]


def tokens_to_latex(ids):
    return ' '.join(IDX2TOKEN.get(i, '?') for i in ids)


def evaluate(model, loader, device, max_samples=200):
    model.eval()
    correct, total, printed = 0, 0, 0
    with torch.no_grad():
        for images, tokens in loader:
            for i in range(images.size(0)):
                if total >= max_samples:
                    return correct / max(total, 1)
                gt = [t for t in tokens[i].tolist() if t not in (SOS_IDX,)]
                gt = gt[:gt.index(EOS_IDX)] if EOS_IDX in gt else [t for t in gt if t != PAD_IDX]
                pred = greedy_decode(model, images[i:i+1], device)
                gt_s, pred_s = tokens_to_latex(gt), tokens_to_latex(pred)
                if pred_s == gt_s:
                    correct += 1
                total += 1
                if printed < 8:
                    print(f"  {'✅' if pred_s == gt_s else '❌'} GT:   {gt_s}")
                    print(f"     Pred: {pred_s}")
                    printed += 1
    return correct / max(total, 1)


def export_onnx(model, output_dir='hme_attn_onnx'):
    model.eval()
    m = model.cpu()
    os.makedirs(output_dir, exist_ok=True)
    dummy = torch.randn(1, 1, IMG_HEIGHT, IMG_WIDTH)

    torch.onnx.export(EncoderWrapper(m.encoder), dummy,
        f'{output_dir}/hme_encoder.onnx', opset_version=14, dynamo=False,
        input_names=['image'], output_names=['features'])
    print(f"  ✅ Encoder: {os.path.getsize(f'{output_dir}/hme_encoder.onnx')/1e6:.1f} MB")

    with torch.no_grad():
        feat = m.encoder(dummy)
    torch.onnx.export(DecoderWrapper(m.decoder),
        (torch.tensor([[1,10,20]], dtype=torch.long), feat),
        f'{output_dir}/hme_decoder.onnx', opset_version=14, dynamo=False,
        input_names=['tokens','memory'], output_names=['logits'],
        dynamic_axes={'tokens':{1:'seq_len'},'logits':{1:'seq_len'}})
    print(f"  ✅ Decoder: {os.path.getsize(f'{output_dir}/hme_decoder.onnx')/1e6:.1f} MB")
    return model.to(device)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    EPOCHS = 200
    TRAIN_SAMPLES = 50_000
    VAL_SAMPLES = 3_000
    BATCH_SIZE = 64
    LR = 3e-4
    CHECKPOINT = 'best_hme_fonts.pt'

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"🖥  Device: {device}")
    if device.type == 'cuda':
        print(f"   GPU: {torch.cuda.get_device_name()}")

    print(f"📚 Vocabulary: {VOCAB_SIZE} tokens")
    print(f"📝 Formula templates: {len(FORMULA_TEMPLATES)}")

    # Save vocab
    vocab = {'token2idx': TOKEN2IDX, 'idx2token': {str(k): v for k, v in IDX2TOKEN.items()}}
    with open('hme_attn_vocab.json', 'w') as f:
        json.dump(vocab, f, indent=2)

    # Download handwriting fonts
    print("\n🖊  Downloading handwriting fonts...")
    fonts = download_fonts()
    print(f"   {len(fonts)} fonts available")

    if not fonts:
        print("❌ No fonts found! Cannot train.")
        exit(1)

    # Datasets
    print(f"\n📊 Creating datasets ({TRAIN_SAMPLES:,} train, {VAL_SAMPLES:,} val)...")
    train_ds = HandwritingFontDataset(TRAIN_SAMPLES, fonts, augment=True)
    val_ds = HandwritingFontDataset(VAL_SAMPLES, fonts, augment=False)

    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True,
                              num_workers=2, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False,
                            num_workers=2, pin_memory=True)

    # Model
    model = HMEAttentionModel(vocab_size=VOCAB_SIZE, d_model=256).to(device)
    params = sum(p.numel() for p in model.parameters())
    print(f"🧠 Model: {params:,} parameters")

    # Resume from CROHME pre-training if available
    for ckpt in ['best_hme_crohme.pt', 'best_hme_attn.pt', CHECKPOINT]:
        if os.path.exists(ckpt):
            model.load_state_dict(torch.load(ckpt, map_location=device))
            print(f"📂 Loaded weights from {ckpt}")
            break

    criterion = nn.CrossEntropyLoss(ignore_index=PAD_IDX)
    optimizer = optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingWarmRestarts(optimizer, T_0=20, T_mult=2)

    best_acc = 0.0
    print(f"\n🏋️ Training for {EPOCHS} epochs...\n")

    for epoch in range(1, EPOCHS + 1):
        t0 = time.time()
        loss = train_epoch(model, train_loader, optimizer, criterion, device)
        scheduler.step()
        elapsed = time.time() - t0

        if epoch % 10 == 0 or epoch <= 5:
            acc = evaluate(model, val_loader, device)
            lr = optimizer.param_groups[0]['lr']
            print(f"\nEpoch {epoch}/{EPOCHS} — Loss: {loss:.4f} | "
                  f"Acc: {acc:.1%} | LR: {lr:.6f} | {elapsed:.0f}s")
            if acc > best_acc:
                best_acc = acc
                torch.save(model.state_dict(), CHECKPOINT)
                print(f"  💾 Saved best (acc: {best_acc:.1%})")
            print()
        else:
            if epoch % 5 == 0:
                print(f"Epoch {epoch}/{EPOCHS} — Loss: {loss:.4f} | {elapsed:.0f}s")

        if epoch % 50 == 0:
            export_onnx(model, f'onnx_ep{epoch}')

    print(f"\n{'='*60}")
    print(f"Training complete! Best accuracy: {best_acc:.1%}")
    model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
    export_onnx(model, 'hme_attn_onnx')

    print(f"\n✅ Files to download (100% commercial safe!):")
    print(f"   📦 hme_attn_onnx/hme_encoder.onnx")
    print(f"   📦 hme_attn_onnx/hme_decoder.onnx")
    print(f"   📝 hme_attn_vocab.json")
    print(f"\n   Fonts used: Apache 2.0 / OFL licensed (Google Fonts)")
    print(f"   ✅ Safe for commercial use!")
