#!/usr/bin/env python3
"""
🧮 HME Attention Model — Encoder-Decoder for Complex Math Formulas (ONNX-safe)

Architecture designed for clean ONNX export:
  - Encoder ONNX: image [1,1,H,W] → features [1,N,D]
  - Decoder ONNX: (features [1,N,D], tokens [1,S]) → logits [1,S,V]
  - Autoregressive loop runs in Dart, NOT in the model

Training on synthetic data first, designed for CROHME upgrade later.

Usage on Colab:
  !pip install torch torchvision tqdm pillow onnx scipy
  !python train_hme_attention.py
"""

import json
import math
import os
import random
import time

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.models as models
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
from tqdm import tqdm

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
    # Greek
    r'\alpha', r'\beta', r'\gamma', r'\delta', r'\epsilon', r'\theta',
    r'\lambda', r'\mu', r'\pi', r'\sigma', r'\phi', r'\omega',
    r'\Delta', r'\Sigma', r'\Phi', r'\Omega',
    # Operators
    '+', '-', '=', r'\times', r'\div', r'\pm', r'\cdot',
    '<', '>', r'\leq', r'\geq', r'\neq', r'\approx',
    # Brackets
    '(', ')', '[', ']', '{', '}', '|',
    # Structure
    '^', '_', r'\frac', r'\sqrt',
    # Functions
    r'\sin', r'\cos', r'\tan', r'\log', r'\ln', r'\lim',
    # Big operators
    r'\sum', r'\prod', r'\int',
    # Misc
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
# MODEL — Encoder (CNN → Feature Sequence)
# ═══════════════════════════════════════════════════════════════════════════════


class HMEEncoder(nn.Module):
    """CNN encoder: grayscale image → feature sequence.

    Output: [batch, seq_len, d_model] where seq_len = W/32.
    """

    def __init__(self, d_model=256):
        super().__init__()
        resnet = models.resnet18(weights=models.ResNet18_Weights.DEFAULT)

        # Adapt for grayscale input
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

        # Collapse height, keep width as sequence
        self.pool = nn.AdaptiveAvgPool2d((1, None))

        # Project 512 → d_model
        self.proj = nn.Linear(512, d_model)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """x: [B, 1, H, W] → features: [B, T, d_model]"""
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)       # [B, 512, H/32, W/32]
        x = self.pool(x)         # [B, 512, 1, W/32]
        x = x.squeeze(2)         # [B, 512, W/32]
        x = x.permute(0, 2, 1)   # [B, W/32, 512]
        x = self.proj(x)         # [B, W/32, d_model]
        return x


# ═══════════════════════════════════════════════════════════════════════════════
# MODEL — Decoder (Transformer Decoder with Cross-Attention)
# ═══════════════════════════════════════════════════════════════════════════════


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
        self.register_buffer('pe', pe.unsqueeze(0))  # [1, max_len, d_model]

    def forward(self, x):
        return x + self.pe[:, :x.size(1)]


class HMEDecoder(nn.Module):
    """Transformer decoder: features + token sequence → next-token logits.

    Designed for ONNX export:
    - No dynamic shapes (max_seq_len is fixed)
    - Causal mask is pre-registered as a buffer
    - Cross-attention to encoder features
    """

    def __init__(self, vocab_size, d_model=256, nhead=8, num_layers=3,
                 dim_feedforward=512, dropout=0.1, max_seq_len=MAX_SEQ_LEN):
        super().__init__()
        self.d_model = d_model
        self.max_seq_len = max_seq_len

        # Token embedding + positional encoding
        self.embedding = nn.Embedding(vocab_size, d_model, padding_idx=PAD_IDX)
        self.pos_encoding = PositionalEncoding(d_model, max_len=max_seq_len + 10)
        self.embed_scale = math.sqrt(d_model)

        # Transformer decoder layers
        decoder_layer = nn.TransformerDecoderLayer(
            d_model=d_model,
            nhead=nhead,
            dim_feedforward=dim_feedforward,
            dropout=dropout,
            batch_first=True,
        )
        self.transformer_decoder = nn.TransformerDecoder(
            decoder_layer, num_layers=num_layers,
        )

        # Output projection
        self.output_proj = nn.Linear(d_model, vocab_size)

        # Pre-register causal mask for ONNX (no torch.triu at runtime)
        causal_mask = torch.triu(
            torch.ones(max_seq_len, max_seq_len, dtype=torch.bool), diagonal=1
        )
        self.register_buffer('causal_mask', causal_mask)

    def forward(self, tgt_tokens: torch.Tensor, memory: torch.Tensor) -> torch.Tensor:
        """
        tgt_tokens: [B, S] token indices
        memory: [B, T, d_model] encoder features

        Returns: [B, S, vocab_size] logits
        """
        S = tgt_tokens.size(1)

        # Embed tokens
        x = self.embedding(tgt_tokens) * self.embed_scale  # [B, S, d_model]
        x = self.pos_encoding(x)

        # Use pre-registered causal mask (sliced to current seq length)
        mask = self.causal_mask[:S, :S]

        # Decode
        x = self.transformer_decoder(
            tgt=x,
            memory=memory,
            tgt_mask=mask,
        )

        # Project to vocab
        logits = self.output_proj(x)  # [B, S, vocab_size]
        return logits


# ═══════════════════════════════════════════════════════════════════════════════
# Combined model for training
# ═══════════════════════════════════════════════════════════════════════════════


class HMEAttentionModel(nn.Module):
    """Full encoder-decoder for training. Split for ONNX export."""

    def __init__(self, vocab_size=VOCAB_SIZE, d_model=256):
        super().__init__()
        self.encoder = HMEEncoder(d_model=d_model)
        self.decoder = HMEDecoder(vocab_size=vocab_size, d_model=d_model)

    def forward(self, images, tgt_tokens):
        features = self.encoder(images)
        logits = self.decoder(tgt_tokens, features)
        return logits


# ═══════════════════════════════════════════════════════════════════════════════
# ONNX Export Wrappers
# ═══════════════════════════════════════════════════════════════════════════════


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
# DATASET
# ═══════════════════════════════════════════════════════════════════════════════


def tokenize_formula(formula: str) -> list[int]:
    """Convert formula string to token indices."""
    tokens = [SOS_IDX]
    i = 0
    while i < len(formula):
        # Try LaTeX commands (longest match first)
        matched = False
        if formula[i] == '\\':
            for length in range(10, 1, -1):
                candidate = formula[i:i + length]
                if candidate in TOKEN2IDX:
                    tokens.append(TOKEN2IDX[candidate])
                    i += length
                    matched = True
                    break

        if not matched:
            char = formula[i]
            if char in TOKEN2IDX:
                tokens.append(TOKEN2IDX[char])
            i += 1

    tokens.append(EOS_IDX)
    return tokens


class SyntheticMathDataset(Dataset):
    """Generates diverse math formulas as images with LaTeX labels."""

    TEMPLATES = [
        # Simple
        lambda: f"{random.choice('abcxyz')} = {random.randint(0, 99)}",
        lambda: f"{random.choice('abcxyz')} = {random.choice('abcxyz')}",
        lambda: f"{random.choice('abcxyz')} + {random.choice('abcxyz')} = {random.choice('abcxyz')}",
        lambda: f"{random.choice('abcxyz')} - {random.choice('abcxyz')} = {random.choice('abcxyz')}",
        # With numbers
        lambda: f"{random.randint(1, 9)} + {random.randint(1, 9)} = {random.randint(2, 18)}",
        lambda: f"{random.randint(1, 9)} x = {random.randint(1, 50)}",
        lambda: f"{random.randint(2, 9)} {random.choice('abcxyz')} + {random.randint(1, 9)}",
        lambda: f"{random.randint(2, 9)} {random.choice('abcxyz')} - {random.randint(1, 9)} = 0",
        # Powers
        lambda: f"{random.choice('abcxyz')} ^ {random.randint(2, 5)}",
        lambda: f"{random.choice('abcxyz')} ^ 2 + {random.choice('abcxyz')} ^ 2 = {random.choice('abcxyz')} ^ 2",
        lambda: f"{random.choice('abcxyz')} ^ 2 + {random.randint(1, 9)} {random.choice('abcxyz')} + {random.randint(1, 20)} = 0",
        # Division
        lambda: f"{random.choice('abcxyz')} / {random.choice('abcxyz')}",
        lambda: f"v = {random.choice('abcxyz')} / t",
        # Functions
        lambda: f"sin ( {random.choice('abcxyz')} )",
        lambda: f"cos ( {random.choice('abcxyz')} )",
        lambda: f"log ( {random.choice('abcxyz')} )",
        lambda: f"{random.choice('abcxyz')} = sin ( {random.choice('abcxyz')} )",
        # Famous formulas
        lambda: "E = m c ^ 2",
        lambda: "F = m a",
        lambda: "v = x / t",
        lambda: "y = m x + b",
        lambda: "a ^ 2 + b ^ 2 = c ^ 2",
        lambda: "A = l w",
        # Inequalities
        lambda: f"{random.choice('abcxyz')} < {random.randint(0, 20)}",
        lambda: f"{random.choice('abcxyz')} > {random.randint(0, 20)}",
        # Multi-term
        lambda: f"{random.choice('abcxyz')} + {random.choice('abcxyz')} - {random.choice('abcxyz')} = {random.randint(0, 10)}",
        lambda: f"{random.randint(2, 5)} {random.choice('abcxyz')} + {random.randint(2, 5)} {random.choice('abcxyz')} = {random.randint(1, 30)}",
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
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        ]
        found = [p for p in paths if os.path.exists(p)]
        return found if found else [None]

    def _render(self, formula):
        img = Image.new('L', (IMG_WIDTH, IMG_HEIGHT), color=255)
        draw = ImageDraw.Draw(img)
        font_size = random.randint(22, 48) if self.augment else 36
        font_path = random.choice(self.fonts)
        try:
            font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()
        except (IOError, OSError):
            font = ImageFont.load_default()

        bbox = draw.textbbox((0, 0), formula, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = max(0, (IMG_WIDTH - tw) // 2) + (random.randint(-25, 25) if self.augment else 0)
        y = max(0, (IMG_HEIGHT - th) // 2) + (random.randint(-10, 10) if self.augment else 0)

        ink = random.randint(0, 50) if self.augment else 0
        draw.text((x, y), formula, fill=ink, font=font)

        if self.augment:
            img = img.rotate(random.uniform(-5, 5), fillcolor=255)
            arr = np.array(img, dtype=np.float32)
            arr += np.random.normal(0, random.uniform(0, 10), arr.shape)
            img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
            if random.random() < 0.3:
                img = img.filter(ImageFilter.GaussianBlur(radius=random.uniform(0.3, 1.0)))

        return img

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        formula = self.formulas[idx]
        img = self._render(formula)
        img_tensor = self.transform(img)
        tokens = tokenize_formula(formula)

        # Pad/truncate to MAX_SEQ_LEN
        if len(tokens) > MAX_SEQ_LEN:
            tokens = tokens[:MAX_SEQ_LEN - 1] + [EOS_IDX]
        else:
            tokens += [PAD_IDX] * (MAX_SEQ_LEN - len(tokens))

        return img_tensor, torch.tensor(tokens, dtype=torch.long)


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

        # Teacher forcing: input = tokens[:-1], target = tokens[1:]
        tgt_input = tokens[:, :-1]   # [B, S-1]
        tgt_output = tokens[:, 1:]   # [B, S-1]

        logits = model(images, tgt_input)  # [B, S-1, V]

        # Reshape for cross-entropy
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
    """Autoregressive greedy decoding (mirrors what Dart will do)."""
    model.eval()
    with torch.no_grad():
        features = model.encoder(image.to(device))  # [1, T, D]
        tokens = [SOS_IDX]

        for _ in range(max_len):
            tgt = torch.tensor([tokens], dtype=torch.long, device=device)
            logits = model.decoder(tgt, features)  # [1, S, V]
            next_token = logits[0, -1].argmax().item()

            if next_token == EOS_IDX:
                break
            tokens.append(next_token)

        return tokens[1:]  # Remove SOS


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

                # Ground truth (remove SOS, PAD, stop at EOS)
                gt_tokens = []
                for t in tokens[i].tolist():
                    if t == SOS_IDX:
                        continue
                    if t == EOS_IDX or t == PAD_IDX:
                        break
                    gt_tokens.append(t)

                # Predict
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


def export_onnx(model, output_dir='.'):
    """Export encoder and decoder as separate ONNX models."""
    model.eval()
    model_cpu = model.cpu()

    os.makedirs(output_dir, exist_ok=True)

    # ── Encoder ──
    enc_wrapper = EncoderWrapper(model_cpu.encoder)
    enc_wrapper.eval()
    dummy_img = torch.randn(1, 1, IMG_HEIGHT, IMG_WIDTH)

    enc_path = os.path.join(output_dir, 'hme_encoder.onnx')
    torch.onnx.export(
        enc_wrapper, dummy_img, enc_path,
        opset_version=14,
        input_names=['image'],
        output_names=['features'],
        export_params=True,
        do_constant_folding=True,
    )
    enc_size = os.path.getsize(enc_path) / (1024 * 1024)
    enc_data = enc_path + '.data'
    if os.path.exists(enc_data):
        enc_size += os.path.getsize(enc_data) / (1024 * 1024)
    print(f"  ✅ Encoder: {enc_size:.1f} MB")

    # ── Decoder ──
    dec_wrapper = DecoderWrapper(model_cpu.decoder)
    dec_wrapper.eval()

    # Get encoder output shape for dummy
    with torch.no_grad():
        dummy_features = model_cpu.encoder(dummy_img)
    dummy_tokens = torch.tensor([[SOS_IDX, 1, 2]], dtype=torch.long)

    dec_path = os.path.join(output_dir, 'hme_decoder.onnx')
    torch.onnx.export(
        dec_wrapper,
        (dummy_tokens, dummy_features),
        dec_path,
        opset_version=14,
        input_names=['tokens', 'memory'],
        output_names=['logits'],
        export_params=True,
        do_constant_folding=True,
        dynamic_axes={
            'tokens': {1: 'seq_len'},
            'logits': {1: 'seq_len'},
        },
    )
    dec_size = os.path.getsize(dec_path) / (1024 * 1024)
    dec_data = dec_path + '.data'
    if os.path.exists(dec_data):
        dec_size += os.path.getsize(dec_data) / (1024 * 1024)
    print(f"  ✅ Decoder: {dec_size:.1f} MB")

    return model.to(device)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    EPOCHS = 200
    TRAIN_SAMPLES = 30_000
    VAL_SAMPLES = 2_000
    BATCH_SIZE = 128
    LR = 3e-4

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"🖥  Device: {device}")
    if device.type == 'cuda':
        print(f"   GPU: {torch.cuda.get_device_name()}")
        print(f"   Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")

    print(f"📚 Vocabulary: {VOCAB_SIZE} tokens (with SOS/EOS/PAD)")

    # Save vocab
    vocab = {'token2idx': TOKEN2IDX, 'idx2token': {str(k): v for k, v in IDX2TOKEN.items()}}
    with open('hme_attn_vocab.json', 'w') as f:
        json.dump(vocab, f, indent=2)

    # Model
    model = HMEAttentionModel(vocab_size=VOCAB_SIZE, d_model=256).to(device)
    params = sum(p.numel() for p in model.parameters())
    enc_params = sum(p.numel() for p in model.encoder.parameters())
    dec_params = sum(p.numel() for p in model.decoder.parameters())
    print(f"🧠 Model: {params:,} total ({enc_params:,} enc + {dec_params:,} dec)")

    # Resume checkpoint
    CHECKPOINT = 'best_hme_attn.pt'
    if os.path.exists(CHECKPOINT):
        model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
        print(f"📂 Resumed from {CHECKPOINT}")

    # Data
    print(f"\n📊 Creating datasets ({TRAIN_SAMPLES:,} train, {VAL_SAMPLES:,} val)...")
    train_ds = SyntheticMathDataset(TRAIN_SAMPLES, augment=True)
    val_ds = SyntheticMathDataset(VAL_SAMPLES, augment=False)

    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=True,
                              num_workers=4, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False,
                            num_workers=4, pin_memory=True)

    # Training
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
            print(f"\n📦 Exporting ONNX at epoch {epoch}...")
            export_onnx(model, f'onnx_ep{epoch}')

    # Final
    print(f"\n{'='*60}")
    print(f"Training complete! Best accuracy: {best_acc:.1%}")
    print(f"Exporting final ONNX...")

    model.load_state_dict(torch.load(CHECKPOINT, map_location=device))
    export_onnx(model, 'hme_attn_onnx')

    print(f"\n✅ Files to download:")
    print(f"   📦 hme_attn_onnx/hme_encoder.onnx (+.data if present)")
    print(f"   📦 hme_attn_onnx/hme_decoder.onnx (+.data if present)")
    print(f"   📝 hme_attn_vocab.json")
    print(f"   💾 {CHECKPOINT}")
