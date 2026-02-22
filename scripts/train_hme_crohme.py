#!/usr/bin/env python3
"""
🧮 HME Attention Training v2 — CROHME Real Handwriting Dataset

This script trains the encoder-decoder attention model on the CROHME dataset
(real handwritten math formulas) for production-quality recognition.

Usage on Colab (T4 GPU):
  !pip install onnxscript scipy lxml
  !python train_hme_crohme.py

The script will:
  1. Download CROHME 2019 dataset (~364 MB)
  2. Parse InkML files → render strokes as images + extract LaTeX labels
  3. Train encoder-decoder model
  4. Export ONNX (encoder + decoder)
"""

import json
import math
import os
import random
import re
import time
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.models as models
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms

# ═══════════════════════════════════════════════════════════════════════════════
# VOCABULARY (same as train_hme_attention.py)
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
PAD_IDX = 0
SOS_IDX = 1
EOS_IDX = 2

TOKEN2IDX = {t: i for i, t in enumerate(ALL_TOKENS)}
IDX2TOKEN = {i: t for i, t in enumerate(ALL_TOKENS)}
VOCAB_SIZE = len(ALL_TOKENS)

IMG_HEIGHT = 128
IMG_WIDTH = 512
MAX_SEQ_LEN = 64

# ═══════════════════════════════════════════════════════════════════════════════
# MODEL (identical to train_hme_attention.py)
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
        position = torch.arange(0, max_len, dtype=torch.float32).unsqueeze(1)
        div_term = torch.exp(
            torch.arange(0, d_model, 2, dtype=torch.float32) * (-math.log(10000.0) / d_model)
        )
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        self.register_buffer('pe', pe.unsqueeze(0))

    def forward(self, x):
        return x + self.pe[:, :x.size(1)]


class HMEDecoder(nn.Module):
    def __init__(self, vocab_size, d_model=256, nhead=8, num_layers=3,
                 dim_feedforward=512, dropout=0.1, max_seq_len=MAX_SEQ_LEN):
        super().__init__()
        self.d_model = d_model
        self.max_seq_len = max_seq_len
        self.embedding = nn.Embedding(vocab_size, d_model, padding_idx=PAD_IDX)
        self.pos_encoding = PositionalEncoding(d_model, max_len=max_seq_len + 10)
        self.embed_scale = math.sqrt(d_model)

        decoder_layer = nn.TransformerDecoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=dim_feedforward,
            dropout=dropout, batch_first=True,
        )
        self.transformer_decoder = nn.TransformerDecoder(decoder_layer, num_layers=num_layers)
        self.output_proj = nn.Linear(d_model, vocab_size)
        causal_mask = torch.triu(torch.ones(max_seq_len, max_seq_len, dtype=torch.bool), diagonal=1)
        self.register_buffer('causal_mask', causal_mask)

    def forward(self, tgt_tokens, memory):
        S = tgt_tokens.size(1)
        x = self.embedding(tgt_tokens) * self.embed_scale
        x = self.pos_encoding(x)
        mask = self.causal_mask[:S, :S]
        x = self.transformer_decoder(tgt=x, memory=memory, tgt_mask=mask)
        return self.output_proj(x)


class HMEAttentionModel(nn.Module):
    def __init__(self, vocab_size=VOCAB_SIZE, d_model=256):
        super().__init__()
        self.encoder = HMEEncoder(d_model=d_model)
        self.decoder = HMEDecoder(vocab_size=vocab_size, d_model=d_model)

    def forward(self, images, tgt_tokens):
        features = self.encoder(images)
        return self.decoder(tgt_tokens, features)


class EncoderWrapper(nn.Module):
    def __init__(self, encoder):
        super().__init__()
        self.encoder = encoder
    def forward(self, image):
        return self.encoder(image)


class DecoderWrapper(nn.Module):
    def __init__(self, decoder):
        super().__init__()
        self.decoder = decoder
    def forward(self, tokens, memory):
        return self.decoder(tokens, memory)


# ═══════════════════════════════════════════════════════════════════════════════
# CROHME InkML PARSER
# ═══════════════════════════════════════════════════════════════════════════════


def parse_inkml(filepath):
    """Parse an InkML file → (strokes, latex_label).

    Returns:
        strokes: list of traces, each trace is list of (x, y) tuples
        label: LaTeX string (ground truth)
    """
    try:
        tree = ET.parse(filepath)
    except ET.ParseError:
        return None, None

    root = tree.getroot()

    # Handle InkML namespace
    ns = {'ink': 'http://www.w3.org/2003/InkML'}

    # Try with namespace first, then without
    traces = root.findall('.//ink:trace', ns)
    if not traces:
        traces = root.findall('.//trace')

    if not traces:
        return None, None

    strokes = []
    for trace in traces:
        text = trace.text
        if not text:
            continue
        points = []
        for point_str in text.strip().split(','):
            parts = point_str.strip().split()
            if len(parts) >= 2:
                try:
                    x, y = float(parts[0]), float(parts[1])
                    points.append((x, y))
                except ValueError:
                    continue
        if points:
            strokes.append(points)

    # Extract label
    label = None

    # Try annotation with type="truth"
    for ann in root.findall('.//ink:annotation', ns) + root.findall('.//annotation'):
        ann_type = ann.get('type', '')
        if ann_type == 'truth':
            label = ann.text
            break

    # Try annotationXML
    if label is None:
        for ann_xml in root.findall('.//ink:annotationXML', ns) + root.findall('.//annotationXML'):
            href = ann_xml.get('href', '')
            if href:
                label = href
                break

    if label:
        label = label.strip()
        # Remove $ delimiters if present
        label = label.strip('$').strip()

    return strokes, label


def render_strokes_to_image(strokes, width=IMG_WIDTH, height=IMG_HEIGHT, padding=10):
    """Render list of strokes (coordinate traces) to a PIL grayscale image."""
    if not strokes:
        return None

    # Find bounding box
    all_x = [p[0] for s in strokes for p in s]
    all_y = [p[1] for s in strokes for p in s]

    if not all_x or not all_y:
        return None

    min_x, max_x = min(all_x), max(all_x)
    min_y, max_y = min(all_y), max(all_y)

    # Handle degenerate cases
    w = max_x - min_x
    h = max_y - min_y
    if w < 1:
        w = 1
    if h < 1:
        h = 1

    # Scale to fit image with padding
    draw_w = width - 2 * padding
    draw_h = height - 2 * padding

    # Maintain aspect ratio
    scale = min(draw_w / w, draw_h / h)
    offset_x = padding + (draw_w - w * scale) / 2
    offset_y = padding + (draw_h - h * scale) / 2

    img = Image.new('L', (width, height), color=255)
    draw = ImageDraw.Draw(img)

    for stroke in strokes:
        if len(stroke) < 2:
            if len(stroke) == 1:
                # Single point — draw a dot
                x = (stroke[0][0] - min_x) * scale + offset_x
                y = (stroke[0][1] - min_y) * scale + offset_y
                draw.ellipse([x - 1, y - 1, x + 1, y + 1], fill=0)
            continue

        # Draw connected lines
        points = []
        for px, py in stroke:
            x = (px - min_x) * scale + offset_x
            y = (py - min_y) * scale + offset_y
            points.append((x, y))

        for i in range(len(points) - 1):
            draw.line([points[i], points[i + 1]], fill=0, width=2)

    return img


def tokenize_latex(latex_str):
    """Convert LaTeX string to token indices."""
    tokens = [SOS_IDX]
    i = 0

    while i < len(latex_str):
        # Skip whitespace
        if latex_str[i] == ' ':
            # Add space token
            if ' ' in TOKEN2IDX:
                tokens.append(TOKEN2IDX[' '])
            i += 1
            continue

        # Try LaTeX commands (\alpha, \frac, etc.)
        if latex_str[i] == '\\':
            # Find end of command
            j = i + 1
            while j < len(latex_str) and latex_str[j].isalpha():
                j += 1

            cmd = latex_str[i:j]
            if cmd in TOKEN2IDX:
                tokens.append(TOKEN2IDX[cmd])
                i = j
                continue
            else:
                # Unknown command — skip
                i = j
                continue

        # Single character
        char = latex_str[i]
        if char in TOKEN2IDX:
            tokens.append(TOKEN2IDX[char])
        # else: skip unknown character

        i += 1

    tokens.append(EOS_IDX)
    return tokens


# ═══════════════════════════════════════════════════════════════════════════════
# CROHME DATASET
# ═══════════════════════════════════════════════════════════════════════════════


def download_crohme(data_dir='crohme_data'):
    """Download and extract CROHME dataset.

    Checks for existing extracted data first — if InkML files are already
    present, skips download entirely.
    """
    os.makedirs(data_dir, exist_ok=True)

    # Check if data is already extracted (e.g. manually from Google Drive)
    extract_dir = os.path.join(data_dir, 'extracted')
    if os.path.exists(extract_dir):
        # Count existing InkML files
        count = 0
        for dirpath, _, filenames in os.walk(extract_dir):
            count += sum(1 for f in filenames if f.endswith('.inkml'))
        if count > 10:
            print(f"   ✅ Found {count} existing InkML files in {extract_dir}")
            return extract_dir

    zip_path = os.path.join(data_dir, 'crohme2019.zip')

    if not os.path.exists(zip_path):
        print("📥 Downloading CROHME 2019...")
        print("   If automatic download fails, manually download from:")
        print("   https://tc11.cvc.uab.es/datasets/ICDAR2019-CROHME-TDF_1")
        print("   and place it as crohme_data/crohme2019.zip")
        print()

        urls = [
            "https://tc11.cvc.uab.es/datasets/ICDAR2019-CROHME-TDF_1/TC11_package_CROHME2019.zip",
        ]

        downloaded = False
        for url in urls:
            try:
                import urllib.request
                print(f"   Trying: {url}")
                urllib.request.urlretrieve(url, zip_path)
                downloaded = True
                print("   ✅ Downloaded!")
                break
            except Exception as e:
                print(f"   ❌ Failed: {e}")

        if not downloaded:
            print("\n⚠️  Could not auto-download CROHME.")
            print("   Falling back to synthetic data + augmentation.")
            return None

    # Extract
    if not os.path.exists(extract_dir):
        print("📦 Extracting...")
        with zipfile.ZipFile(zip_path, 'r') as z:
            z.extractall(extract_dir)
        print("   ✅ Extracted!")

    return extract_dir


def find_inkml_files(root_dir):
    """Recursively find all .inkml files."""
    inkml_files = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for f in filenames:
            if f.endswith('.inkml'):
                inkml_files.append(os.path.join(dirpath, f))
    return sorted(inkml_files)


def load_crohme_dataset(data_dir, max_samples=None):
    """Load CROHME dataset: parse InkML → (image, token_sequence) pairs."""
    inkml_files = find_inkml_files(data_dir)
    print(f"   Found {len(inkml_files)} InkML files")

    samples = []
    skipped = 0

    for filepath in inkml_files:
        if max_samples and len(samples) >= max_samples:
            break

        strokes, label = parse_inkml(filepath)

        if not strokes or not label:
            skipped += 1
            continue

        # Tokenize
        tokens = tokenize_latex(label)
        if len(tokens) <= 2:  # Only SOS + EOS
            skipped += 1
            continue
        if len(tokens) > MAX_SEQ_LEN:
            skipped += 1
            continue

        # Render
        img = render_strokes_to_image(strokes)
        if img is None:
            skipped += 1
            continue

        samples.append((img, tokens, label))

    print(f"   Loaded {len(samples)} samples, skipped {skipped}")
    return samples


class CROHMEDataset(Dataset):
    """Dataset from parsed CROHME samples with augmentation."""

    def __init__(self, samples, augment=True):
        self.samples = samples
        self.augment = augment
        self.transform = transforms.Compose([
            transforms.Resize((IMG_HEIGHT, IMG_WIDTH)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.5], std=[0.5]),
        ])

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        img, tokens, _ = self.samples[idx]

        # Augmentation
        if self.augment:
            img = img.copy()
            # Rotation
            img = img.rotate(random.uniform(-5, 5), fillcolor=255)
            # Noise
            arr = np.array(img, dtype=np.float32)
            arr += np.random.normal(0, random.uniform(0, 8), arr.shape)
            img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
            # Blur
            if random.random() < 0.2:
                img = img.filter(ImageFilter.GaussianBlur(
                    radius=random.uniform(0.3, 0.8)))

        img_tensor = self.transform(img)

        # Pad tokens to MAX_SEQ_LEN
        padded = tokens + [PAD_IDX] * (MAX_SEQ_LEN - len(tokens))
        padded = padded[:MAX_SEQ_LEN]

        return img_tensor, torch.tensor(padded, dtype=torch.long)


# ═══════════════════════════════════════════════════════════════════════════════
# SYNTHETIC FALLBACK (in case CROHME download fails)
# ═══════════════════════════════════════════════════════════════════════════════


class SyntheticFallbackDataset(Dataset):
    """Same synthetic dataset as train_hme_attention.py — used as fallback."""

    TEMPLATES = [
        lambda: f"{random.choice('abcxyz')} = {random.randint(0, 99)}",
        lambda: f"{random.choice('abcxyz')} + {random.choice('abcxyz')} = {random.choice('abcxyz')}",
        lambda: f"{random.choice('abcxyz')} - {random.choice('abcxyz')} = {random.choice('abcxyz')}",
        lambda: f"{random.randint(2, 9)} {random.choice('abcxyz')} + {random.randint(1, 9)}",
        lambda: f"{random.choice('abcxyz')} ^ {random.randint(2, 5)}",
        lambda: f"{random.choice('abcxyz')} ^ 2 + {random.choice('abcxyz')} ^ 2",
        lambda: "E = m c ^ 2",
        lambda: "F = m a",
        lambda: "v = x / t",
        lambda: "y = m x + b",
        lambda: f"sin ( {random.choice('abcxyz')} )",
        lambda: f"cos ( {random.choice('abcxyz')} )",
        lambda: f"{random.choice('abcxyz')} < {random.randint(0, 20)}",
    ]

    def __init__(self, num_samples, augment=True):
        self.num_samples = num_samples
        self.augment = augment
        self.formulas = [random.choice(self.TEMPLATES)() for _ in range(num_samples)]
        self.fonts = self._find_fonts()
        self.transform = transforms.Compose([
            transforms.Resize((IMG_HEIGHT, IMG_WIDTH)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.5], std=[0.5]),
        ])

    def _find_fonts(self):
        paths = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        ]
        return [p for p in paths if os.path.exists(p)] or [None]

    def _render(self, formula):
        img = Image.new('L', (IMG_WIDTH, IMG_HEIGHT), color=255)
        draw = ImageDraw.Draw(img)
        font_path = random.choice(self.fonts)
        font_size = random.randint(24, 44)
        try:
            font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()
        except (IOError, OSError):
            font = ImageFont.load_default()
        bbox = draw.textbbox((0, 0), formula, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = max(0, (IMG_WIDTH - tw) // 2) + random.randint(-20, 20)
        y = max(0, (IMG_HEIGHT - th) // 2) + random.randint(-8, 8)
        draw.text((x, y), formula, fill=random.randint(0, 40), font=font)
        if self.augment:
            img = img.rotate(random.uniform(-4, 4), fillcolor=255)
        return img

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        formula = self.formulas[idx]
        img = self._render(formula)
        img_tensor = self.transform(img)
        tokens = tokenize_latex(formula)
        padded = tokens + [PAD_IDX] * (MAX_SEQ_LEN - len(tokens))
        return img_tensor, torch.tensor(padded[:MAX_SEQ_LEN], dtype=torch.long)


# ═══════════════════════════════════════════════════════════════════════════════
# TRAINING
# ═══════════════════════════════════════════════════════════════════════════════


def train_epoch(model, loader, optimizer, criterion, device):
    model.train()
    total_loss = 0
    n = 0
    for images, tokens in loader:
        images = images.to(device)
        tokens = tokens.to(device)
        tgt_input = tokens[:, :-1]
        tgt_output = tokens[:, 1:]
        logits = model(images, tgt_input)
        B, S, V = logits.shape
        loss = criterion(logits.reshape(B * S, V), tgt_output.reshape(B * S))
        if not math.isfinite(loss.item()):
            continue
        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
        optimizer.step()
        total_loss += loss.item()
        n += 1
    return total_loss / max(n, 1)


def greedy_decode(model, image, device, max_len=MAX_SEQ_LEN):
    model.eval()
    with torch.no_grad():
        features = model.encoder(image.to(device))
        tokens = [SOS_IDX]
        for _ in range(max_len):
            tgt = torch.tensor([tokens], dtype=torch.long, device=device)
            logits = model.decoder(tgt, features)
            next_token = logits[0, -1].argmax().item()
            if next_token == EOS_IDX:
                break
            tokens.append(next_token)
        return tokens[1:]


def tokens_to_latex(token_ids):
    return ' '.join(IDX2TOKEN.get(i, '?') for i in token_ids)


def evaluate(model, loader, device, max_samples=200):
    model.eval()
    correct = 0
    total = 0
    printed = 0

    with torch.no_grad():
        for images, tokens in loader:
            for i in range(images.size(0)):
                if total >= max_samples:
                    return correct / max(total, 1)
                gt_tokens = []
                for t in tokens[i].tolist():
                    if t == SOS_IDX: continue
                    if t == EOS_IDX or t == PAD_IDX: break
                    gt_tokens.append(t)

                pred_tokens = greedy_decode(model, images[i:i+1], device)
                gt = tokens_to_latex(gt_tokens)
                pred = tokens_to_latex(pred_tokens)
                if pred == gt:
                    correct += 1
                total += 1

                if printed < 8:
                    match = "✅" if pred == gt else "❌"
                    print(f"  {match} GT:   {gt}")
                    print(f"     Pred: {pred}")
                    printed += 1

    return correct / max(total, 1)


# ═══════════════════════════════════════════════════════════════════════════════
# ONNX EXPORT
# ═══════════════════════════════════════════════════════════════════════════════


def export_onnx(model, output_dir='hme_attn_onnx'):
    model.eval()
    model_cpu = model.cpu()
    os.makedirs(output_dir, exist_ok=True)

    dummy_img = torch.randn(1, 1, IMG_HEIGHT, IMG_WIDTH)

    enc_path = os.path.join(output_dir, 'hme_encoder.onnx')
    torch.onnx.export(
        EncoderWrapper(model_cpu.encoder), dummy_img, enc_path,
        opset_version=14, dynamo=False,
        input_names=['image'], output_names=['features'],
    )
    print(f"  ✅ Encoder exported: {os.path.getsize(enc_path) / 1e6:.1f} MB")

    with torch.no_grad():
        dummy_features = model_cpu.encoder(dummy_img)
    dummy_tokens = torch.tensor([[SOS_IDX, 10, 20]], dtype=torch.long)

    dec_path = os.path.join(output_dir, 'hme_decoder.onnx')
    torch.onnx.export(
        DecoderWrapper(model_cpu.decoder),
        (dummy_tokens, dummy_features), dec_path,
        opset_version=14, dynamo=False,
        input_names=['tokens', 'memory'], output_names=['logits'],
        dynamic_axes={'tokens': {1: 'seq_len'}, 'logits': {1: 'seq_len'}},
    )
    print(f"  ✅ Decoder exported: {os.path.getsize(dec_path) / 1e6:.1f} MB")

    return model.to(device)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    EPOCHS = 200
    BATCH_SIZE = 64
    LR = 3e-4
    CHECKPOINT = 'best_hme_crohme.pt'

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"🖥  Device: {device}")
    if device.type == 'cuda':
        print(f"   GPU: {torch.cuda.get_device_name()}")

    print(f"📚 Vocabulary: {VOCAB_SIZE} tokens")

    # Save vocab
    vocab = {
        'token2idx': TOKEN2IDX,
        'idx2token': {str(k): v for k, v in IDX2TOKEN.items()},
    }
    with open('hme_attn_vocab.json', 'w') as f:
        json.dump(vocab, f, indent=2)

    # ── Try CROHME, fallback to synthetic ──
    print("\n📊 Loading dataset...")
    crohme_dir = download_crohme()

    use_crohme = False
    if crohme_dir:
        samples = load_crohme_dataset(crohme_dir)
        if len(samples) >= 100:
            use_crohme = True
            # Split: 90% train, 10% val
            random.shuffle(samples)
            split = int(0.9 * len(samples))
            train_ds = CROHMEDataset(samples[:split], augment=True)
            val_ds = CROHMEDataset(samples[split:], augment=False)
            print(f"   Using CROHME: {len(train_ds)} train, {len(val_ds)} val")
        else:
            print(f"   Only {len(samples)} CROHME samples — too few, using synthetic")

    if not use_crohme:
        print("   Using synthetic dataset (30K train, 2K val)")
        train_ds = SyntheticFallbackDataset(30_000, augment=True)
        val_ds = SyntheticFallbackDataset(2_000, augment=False)

    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True,
                              num_workers=4, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False,
                            num_workers=4, pin_memory=True)

    # Model
    model = HMEAttentionModel(vocab_size=VOCAB_SIZE, d_model=256).to(device)
    params = sum(p.numel() for p in model.parameters())
    print(f"🧠 Model: {params:,} parameters")

    # Resume checkpoint from synthetic pre-training
    if os.path.exists('best_hme_attn.pt'):
        model.load_state_dict(torch.load('best_hme_attn.pt', map_location=device))
        print("📂 Loaded pre-trained weights from best_hme_attn.pt")
    elif os.path.exists(CHECKPOINT):
        model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
        print(f"📂 Resumed from {CHECKPOINT}")

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

    # Final
    print(f"\n{'='*60}")
    print(f"Training complete! Best accuracy: {best_acc:.1%}")
    model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
    export_onnx(model, 'hme_attn_onnx')

    print(f"\n✅ Files to download:")
    print(f"   📦 hme_attn_onnx/hme_encoder.onnx")
    print(f"   📦 hme_attn_onnx/hme_decoder.onnx")
    print(f"   📝 hme_attn_vocab.json")
