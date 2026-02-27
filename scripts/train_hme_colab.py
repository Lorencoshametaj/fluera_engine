#!/usr/bin/env python3
"""
🧮 HME Training for Google Colab — GPU-accelerated, 200 epochs, 30K samples.

INSTRUCTIONS:
1. Open Google Colab: https://colab.research.google.com
2. Set runtime to GPU: Runtime → Change runtime type → T4 GPU
3. Upload this file + hme_model.py to Colab
4. Run the cells below

After training, download:
  - hme_model.onnx
  - hme_model.onnx.data  
  - hme_vocab.json
  - best_hme_model.pt

Then copy them to: fluera_engine/assets/models/hme/
"""

# %% [Cell 1] Install dependencies
# !pip install torch torchvision tqdm pillow onnx numpy

# %% [Cell 2] Imports
import json
import math
import os
import random
import string
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from tqdm import tqdm

# %% [Cell 3] Model definition (copy from hme_model.py or upload it)
import torchvision.models as models


class HMEEncoder(nn.Module):
    def __init__(self, output_channels=512):
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
        self.adaptive_pool = nn.AdaptiveAvgPool2d((1, None))
        self.output_channels = output_channels

    def forward(self, x):
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        x = self.adaptive_pool(x)
        x = x.squeeze(2)
        x = x.permute(0, 2, 1)
        return x


class HMEModel(nn.Module):
    def __init__(self, vocab_size, hidden_size=256, num_lstm_layers=2, dropout=0.3):
        super().__init__()
        self.encoder = HMEEncoder(output_channels=512)
        self.lstm = nn.LSTM(
            input_size=512, hidden_size=hidden_size,
            num_layers=num_lstm_layers, bidirectional=True,
            dropout=dropout if num_lstm_layers > 1 else 0,
            batch_first=True,
        )
        self.fc = nn.Linear(hidden_size * 2, vocab_size)
        self.log_softmax = nn.LogSoftmax(dim=2)

    def forward(self, x):
        features = self.encoder(x)
        lstm_out, _ = self.lstm(features)
        logits = self.fc(lstm_out)
        log_probs = self.log_softmax(logits)
        return log_probs.permute(1, 0, 2)

    def inference(self, x):
        features = self.encoder(x)
        lstm_out, _ = self.lstm(features)
        return self.fc(lstm_out)


class HMEInferenceWrapper(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        return self.model.inference(x)


# %% [Cell 4] Vocabulary
DEFAULT_VOCAB = [
    '<blank>',
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
    '^', '_',
    r'\frac', r'\sqrt',
    r'\sin', r'\cos', r'\tan', r'\log', r'\ln', r'\lim',
    r'\sum', r'\prod', r'\int',
    r'\infty', r'\partial',
    ',', '.', '!', r'\ldots',
    ' ',
    r'\rightarrow', r'\leftarrow',
    r'\forall', r'\exists', r'\in', r'\cup', r'\cap',
]


def build_vocab():
    token2idx = {t: i for i, t in enumerate(DEFAULT_VOCAB)}
    idx2token = {i: t for i, t in enumerate(DEFAULT_VOCAB)}
    return token2idx, idx2token, len(DEFAULT_VOCAB)


# %% [Cell 5] Enhanced Dataset with heavy augmentation

IMG_HEIGHT = 128
IMG_WIDTH = 512


def elastic_distort(image, alpha=30, sigma=4):
    """Apply elastic distortion to simulate handwriting variation."""
    arr = np.array(image, dtype=np.float32)
    h, w = arr.shape

    # Random displacement fields
    dx = np.random.uniform(-1, 1, (h, w)).astype(np.float32)
    dy = np.random.uniform(-1, 1, (h, w)).astype(np.float32)

    # Smooth with gaussian
    from scipy.ndimage import gaussian_filter
    dx = gaussian_filter(dx, sigma) * alpha
    dy = gaussian_filter(dy, sigma) * alpha

    # Create mesh grid
    x, y = np.meshgrid(np.arange(w), np.arange(h))
    x_new = np.clip(x + dx, 0, w - 1).astype(np.int32)
    y_new = np.clip(y + dy, 0, h - 1).astype(np.int32)

    return Image.fromarray(arr[y_new, x_new].astype(np.uint8))


class EnhancedMathDataset(Dataset):
    """
    100K+ synthetic math formulas with heavy augmentation.
    
    Generates diverse formulas and renders them with:
    - Multiple font sizes and styles
    - Random rotation, scaling, position
    - Elastic distortion (handwriting simulation)
    - Gaussian noise and blur
    - Variable stroke thickness
    """

    FORMULA_TEMPLATES = [
        # Simple equations
        lambda: f"{random.choice('abcdefghijklmnopqrstuvwxyz')} = "
                f"{random.choice('abcdefghijklmnopqrstuvwxyz')}",
        lambda: f"{random.choice('abcdefghijklmnopqrstuvwxyz')} = "
                f"{random.randint(0, 99)}",
        # Addition/subtraction
        lambda: f"{random.choice('abcdefghijklmnopqrstuvwxyz')} "
                f"{random.choice(['+', '-'])} "
                f"{random.choice('abcdefghijklmnopqrstuvwxyz')}",
        lambda: f"{random.choice('abcdefghijklmnopqrstuvwxyz')} = "
                f"{random.choice('abcdefghijklmnopqrstuvwxyz')} "
                f"{random.choice(['+', '-'])} "
                f"{random.choice('abcdefghijklmnopqrstuvwxyz')}",
        # With coefficients
        lambda: f"{random.randint(2, 9)} {random.choice('abcxyz')} "
                f"{random.choice(['+', '-'])} "
                f"{random.randint(1, 9)}",
        lambda: f"{random.randint(2, 9)} {random.choice('abcxyz')} "
                f"{random.choice(['+', '-'])} "
                f"{random.randint(2, 9)} {random.choice('abcxyz')} = "
                f"{random.randint(0, 20)}",
        # Division (as fraction notation)
        lambda: f"{random.choice('abcxyz')} / {random.choice('abcxyz')}",
        lambda: f"v = {random.choice('abcxyz')} / {random.choice('abcxyz')}",
        # Powers
        lambda: f"{random.choice('abcxyz')} ^ {random.randint(2, 5)}",
        lambda: f"{random.choice('abcxyz')} ^ 2 "
                f"{random.choice(['+', '-'])} "
                f"{random.choice('abcxyz')} ^ 2",
        # Quadratic
        lambda: f"{random.choice('abcxyz')} ^ 2 "
                f"{random.choice(['+', '-'])} "
                f"{random.randint(1, 9)} {random.choice('abcxyz')} "
                f"{random.choice(['+', '-'])} "
                f"{random.randint(1, 20)} = 0",
        # Functions  
        lambda: f"{random.choice(['sin', 'cos', 'tan', 'log', 'ln'])} "
                f"( {random.choice('abcxyz')} )",
        lambda: f"{random.choice('abcxyz')} = "
                f"{random.choice(['sin', 'cos'])} "
                f"( {random.choice('abcxyz')} )",
        # Specific formulas people write
        lambda: "v = x / t",
        lambda: "F = m a",
        lambda: "E = m c ^ 2",
        lambda: "a ^ 2 + b ^ 2 = c ^ 2",
        lambda: "y = m x + b",
        lambda: "A = l w",
        lambda: f"{random.randint(1, 9)} + {random.randint(1, 9)} = {random.randint(2, 18)}",
        lambda: f"{random.randint(1, 9)} - {random.randint(1, 9)} = {random.randint(-8, 8)}",
        lambda: f"{random.randint(1, 9)} x = {random.randint(1, 50)}",
        # Multi-variable
        lambda: f"{random.choice('abcxyz')} {random.choice(['+', '-'])} "
                f"{random.choice('abcxyz')} = "
                f"{random.choice('abcxyz')} {random.choice(['+', '-'])} "
                f"{random.choice('abcxyz')}",
        # Inequalities
        lambda: f"{random.choice('abcxyz')} "
                f"{random.choice(['<', '>', '='])} "
                f"{random.randint(0, 20)}",
    ]

    def __init__(self, num_samples, token2idx, augment=True, use_elastic=True):
        self.num_samples = num_samples
        self.token2idx = token2idx
        self.augment = augment
        self.use_elastic = use_elastic

        # Pre-generate formulas
        self.formulas = [
            self.FORMULA_TEMPLATES[random.randint(0, len(self.FORMULA_TEMPLATES) - 1)]()
            for _ in range(num_samples)
        ]

        self.transform = transforms.Compose([
            transforms.Resize((IMG_HEIGHT, IMG_WIDTH)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.5], std=[0.5]),
        ])

        # Try to find system fonts
        self.fonts = self._find_fonts()

    def _find_fonts(self):
        """Find available fonts on the system."""
        font_paths = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/TTF/DejaVuSerif.ttf",
        ]
        found = []
        for p in font_paths:
            if os.path.exists(p):
                found.append(p)
        return found if found else [None]

    def _render_formula(self, formula):
        """Render formula with augmentations to simulate handwriting."""
        img = Image.new('L', (IMG_WIDTH, IMG_HEIGHT), color=255)
        draw = ImageDraw.Draw(img)

        font_size = random.randint(20, 52) if self.augment else 36
        font_path = random.choice(self.fonts)

        try:
            font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()
        except (IOError, OSError):
            font = ImageFont.load_default()

        # Calculate text position
        bbox = draw.textbbox((0, 0), formula, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]

        x = max(0, (IMG_WIDTH - text_w) // 2)
        y = max(0, (IMG_HEIGHT - text_h) // 2)

        if self.augment:
            x += random.randint(-30, 30)
            y += random.randint(-15, 15)

        # Variable ink color (not always pure black)
        ink_color = random.randint(0, 60) if self.augment else 0
        draw.text((x, y), formula, fill=ink_color, font=font)

        if self.augment:
            # Random rotation
            angle = random.uniform(-8, 8)
            img = img.rotate(angle, fillcolor=255, expand=False)

            # Elastic distortion (simulate handwriting)
            if self.use_elastic and random.random() < 0.15:
                try:
                    img = elastic_distort(img,
                                         alpha=random.uniform(10, 40),
                                         sigma=random.uniform(3, 6))
                except ImportError:
                    pass  # scipy not available

            # Gaussian noise
            arr = np.array(img).astype(np.float32)
            noise_level = random.uniform(0, 15)
            noise = np.random.normal(0, noise_level, arr.shape)
            arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
            img = Image.fromarray(arr)

            # Slight blur (simulate pen)
            if random.random() < 0.3:
                img = img.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.5, 1.5)))

            # Random background brightness
            if random.random() < 0.3:
                arr = np.array(img).astype(np.float32)
                bg_shift = random.uniform(-20, 20)
                arr = np.clip(arr + bg_shift, 0, 255).astype(np.uint8)
                img = Image.fromarray(arr)

        return img

    def _tokenize(self, formula):
        """Convert formula to token indices."""
        indices = []
        i = 0
        func_map = {'sin': '\\sin', 'cos': '\\cos', 'tan': '\\tan',
                     'log': '\\log', 'ln': '\\ln'}

        while i < len(formula):
            matched = False
            # Check multi-char tokens
            for fname, ftoken in func_map.items():
                if formula[i:].startswith(fname):
                    if ftoken in self.token2idx:
                        indices.append(self.token2idx[ftoken])
                    i += len(fname)
                    matched = True
                    break

            if not matched:
                char = formula[i]
                if char == '/':
                    if '\\frac' in self.token2idx:
                        indices.append(self.token2idx['\\frac'])
                elif char in self.token2idx:
                    indices.append(self.token2idx[char])
                i += 1

        return indices

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        formula = self.formulas[idx]
        img = self._render_formula(formula)
        img_tensor = self.transform(img)
        targets = self._tokenize(formula)
        return img_tensor, torch.tensor(targets, dtype=torch.long), len(targets)


def collate_fn(batch):
    images, targets, target_lens = zip(*batch)
    images = torch.stack(images)
    target_lens = torch.tensor(target_lens, dtype=torch.long)
    flat_targets = torch.cat([t for t in targets])
    return images, flat_targets, target_lens


# %% [Cell 6] Training functions

def train_epoch(model, dataloader, optimizer, criterion, device):
    model.train()
    total_loss = 0
    num_batches = 0

    for images, targets, target_lens in dataloader:
        images = images.to(device)
        targets = targets.to(device)
        target_lens = target_lens.to(device)

        optimizer.zero_grad()
        log_probs = model(images)
        T, B = log_probs.shape[0], log_probs.shape[1]
        input_lens = torch.full((B,), T, dtype=torch.long, device=device)

        loss = criterion(log_probs, targets, input_lens, target_lens)
        if not math.isfinite(loss.item()):
            continue

        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
        optimizer.step()
        total_loss += loss.item()
        num_batches += 1

    return total_loss / max(num_batches, 1)


def ctc_greedy_decode(logits, idx2token):
    pred_indices = logits.argmax(dim=-1).tolist()
    decoded = []
    prev = -1
    for idx in pred_indices:
        if idx != 0 and idx != prev:
            if idx in idx2token:
                decoded.append(idx2token[idx])
        prev = idx
    return ' '.join(decoded)


def evaluate(model, dataloader, idx2token, device, max_batches=20):
    model.eval()
    correct = 0
    total = 0
    char_correct = 0
    char_total = 0

    with torch.no_grad():
        for batch_idx, (images, targets, target_lens) in enumerate(dataloader):
            if batch_idx >= max_batches:
                break

            images = images.to(device)
            log_probs = model(images)

            offset = 0
            for i in range(images.shape[0]):
                t_len = target_lens[i].item()
                t_indices = targets[offset:offset + t_len].tolist()
                offset += t_len

                gt_tokens = [idx2token.get(idx, '?') for idx in t_indices]
                gt = ' '.join(gt_tokens)
                pred = ctc_greedy_decode(log_probs[:, i, :], idx2token)

                # Exact match
                if pred == gt:
                    correct += 1
                total += 1

                # Character-level accuracy
                gt_chars = gt.replace(' ', '')
                pred_chars = pred.replace(' ', '')
                for j in range(min(len(gt_chars), len(pred_chars))):
                    if gt_chars[j] == pred_chars[j]:
                        char_correct += 1
                char_total += max(len(gt_chars), len(pred_chars))

                # Print samples
                if batch_idx == 0 and i < 8:
                    match = "✅" if pred == gt else "❌"
                    print(f"  {match} GT:   {gt}")
                    print(f"     Pred: {pred}")

    expr_acc = correct / max(total, 1)
    char_acc = char_correct / max(char_total, 1)
    return expr_acc, char_acc


# %% [Cell 7] ONNX Export

def export_onnx(model, vocab_size, output_path):
    """Export to ONNX with weights embedded (no external .data file)."""
    model.eval()
    model_cpu = model.cpu()
    wrapper = HMEInferenceWrapper(model_cpu)
    wrapper.eval()

    dummy = torch.randn(1, 1, IMG_HEIGHT, IMG_WIDTH)

    # Use opset_version=14 for good compatibility
    torch.onnx.export(
        wrapper, dummy, output_path,
        opset_version=14,
        input_names=['image'],
        output_names=['logits'],
        export_params=True,
        do_constant_folding=True,
    )

    # Check for external data file
    data_path = output_path + '.data'
    onnx_size = os.path.getsize(output_path) / (1024 * 1024)
    
    if os.path.exists(data_path):
        data_size = os.path.getsize(data_path) / (1024 * 1024)
        print(f"✅ ONNX exported: {output_path} ({onnx_size:.1f} MB) + .data ({data_size:.1f} MB)")
    else:
        print(f"✅ ONNX exported: {output_path} ({onnx_size:.1f} MB, self-contained)")

    return model.to(device)


# %% [Cell 8] MAIN TRAINING LOOP

if __name__ == '__main__':
    # ── Config ──
    EPOCHS = 200
    TRAIN_SAMPLES = 30_000
    VAL_SAMPLES = 2_000
    BATCH_SIZE = 128
    LR = 3e-4
    CHECKPOINT = 'best_hme_model.pt'
    ONNX_PATH = 'hme_model.onnx'

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"🖥  Device: {device}")
    if device.type == 'cuda':
        print(f"   GPU: {torch.cuda.get_device_name()}")
        print(f"   Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")

    # Vocab
    token2idx, idx2token, vocab_size = build_vocab()
    print(f"📚 Vocabulary: {vocab_size} tokens")

    vocab_path = 'hme_vocab.json'
    with open(vocab_path, 'w') as f:
        json.dump({str(i): t for i, t in idx2token.items()}, f, indent=2)

    # Model
    model = HMEModel(vocab_size=vocab_size).to(device)
    params = sum(p.numel() for p in model.parameters())
    print(f"🧠 Model: {params:,} parameters")

    # Check for existing checkpoint
    if os.path.exists(CHECKPOINT):
        model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
        print(f"📂 Resumed from checkpoint: {CHECKPOINT}")

    # Datasets
    print(f"\n📊 Creating datasets ({TRAIN_SAMPLES:,} train, {VAL_SAMPLES:,} val)...")
    
    # Check if scipy is available for elastic distortion
    try:
        from scipy.ndimage import gaussian_filter
        use_elastic = True
        print("   ✓ Elastic distortion enabled (scipy found)")
    except ImportError:
        use_elastic = False
        print("   ✗ Elastic distortion disabled (pip install scipy)")

    train_ds = EnhancedMathDataset(TRAIN_SAMPLES, token2idx, augment=True, use_elastic=use_elastic)
    val_ds = EnhancedMathDataset(VAL_SAMPLES, token2idx, augment=False, use_elastic=False)

    train_loader = DataLoader(
        train_ds, batch_size=BATCH_SIZE, shuffle=True,
        num_workers=4, collate_fn=collate_fn, pin_memory=True,
    )
    val_loader = DataLoader(
        val_ds, batch_size=BATCH_SIZE, shuffle=False,
        num_workers=2, collate_fn=collate_fn, pin_memory=True,
    )

    # Training setup
    criterion = nn.CTCLoss(blank=0, zero_infinity=True)
    optimizer = optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingWarmRestarts(optimizer, T_0=20, T_mult=2)

    best_accuracy = 0.0
    best_char_acc = 0.0

    print(f"\n🏋️ Training for {EPOCHS} epochs...")
    print(f"   Batch size: {BATCH_SIZE}")
    print(f"   Learning rate: {LR}")
    print(f"   Scheduler: CosineAnnealingWarmRestarts (T_0=20)")
    print()

    for epoch in range(1, EPOCHS + 1):
        t0 = time.time()
        train_loss = train_epoch(model, train_loader, optimizer, criterion, device)
        scheduler.step()
        elapsed = time.time() - t0

        # Evaluate every 10 epochs
        if epoch % 10 == 0 or epoch <= 5:
            expr_acc, char_acc = evaluate(model, val_loader, idx2token, device)
            lr = optimizer.param_groups[0]['lr']
            print(f"\nEpoch {epoch}/{EPOCHS} — Loss: {train_loss:.4f} | "
                  f"Expr: {expr_acc:.1%} | Char: {char_acc:.1%} | "
                  f"LR: {lr:.6f} | {elapsed:.0f}s")

            improved = False
            if expr_acc > best_accuracy:
                best_accuracy = expr_acc
                improved = True
            if char_acc > best_char_acc:
                best_char_acc = char_acc
                improved = True

            if improved:
                torch.save(model.state_dict(), CHECKPOINT)
                print(f"  💾 Saved best model (expr: {best_accuracy:.1%}, char: {best_char_acc:.1%})")
            print()
        else:
            if epoch % 5 == 0:
                lr = optimizer.param_groups[0]['lr']
                print(f"Epoch {epoch}/{EPOCHS} — Loss: {train_loss:.4f} | LR: {lr:.6f} | {elapsed:.0f}s")

        # Export every 50 epochs
        if epoch % 50 == 0:
            print(f"\n📦 Exporting ONNX at epoch {epoch}...")
            export_onnx(model, vocab_size, f'hme_model_ep{epoch}.onnx')

    # Final export
    print(f"\n{'='*60}")
    print(f"Training complete!")
    print(f"  Best expression accuracy: {best_accuracy:.1%}")
    print(f"  Best character accuracy:  {best_char_acc:.1%}")
    print(f"\nExporting final model...")

    model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
    export_onnx(model, vocab_size, ONNX_PATH)

    print(f"\n✅ Done! Files to download:")
    print(f"   📦 {ONNX_PATH}")
    if os.path.exists(ONNX_PATH + '.data'):
        print(f"   📦 {ONNX_PATH}.data")
    print(f"   📝 {vocab_path}")
    print(f"   💾 {CHECKPOINT}")
    print(f"\nCopy these to: fluera_engine/assets/models/hme/")
