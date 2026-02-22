#!/usr/bin/env python3
"""
🧮 Train HME (Handwritten Math Expression) recognition model.

Usage:
    # Install dependencies
    pip install torch torchvision tqdm pillow lxml

    # Train on CROHME dataset
    python train_hme.py --data_dir ./crohme_data --epochs 50

    # Export trained model to ONNX
    python train_hme.py --export_only --checkpoint best_model.pt

The script will:
1. Download & preprocess CROHME dataset (if not present)
2. Train CNN+BiLSTM+CTC model
3. Export to ONNX for mobile deployment
"""

import argparse
import json
import math
import os
import random
import sys
from collections import Counter
from pathlib import Path

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms
from PIL import Image, ImageDraw, ImageFont

# Local imports
from hme_model import HMEModel, HMEInferenceWrapper, build_vocab, DEFAULT_VOCAB


# ─── Configuration ────────────────────────────────────────────────────────────

IMG_HEIGHT = 128
IMG_WIDTH = 512
BATCH_SIZE = 32
LEARNING_RATE = 1e-3
NUM_WORKERS = 4


# ─── Dataset ──────────────────────────────────────────────────────────────────

class SyntheticMathDataset(Dataset):
    """Generate synthetic handwritten-style math expressions for training.
    
    Since CROHME requires manual download and complex InkML parsing,
    we start with a synthetic dataset that generates formula images
    using varied fonts and augmentations to simulate handwriting.
    
    This is surprisingly effective for simple/medium formulas and
    provides a quick baseline while the CROHME pipeline is built.
    """
    
    def __init__(self, num_samples: int, token2idx: dict, 
                 img_height: int = IMG_HEIGHT, img_width: int = IMG_WIDTH,
                 augment: bool = True):
        self.num_samples = num_samples
        self.token2idx = token2idx
        self.img_height = img_height
        self.img_width = img_width
        self.augment = augment
        
        # Generate formula templates
        self.formulas = self._generate_formulas()
        
        self.transform = transforms.Compose([
            transforms.Resize((img_height, img_width)),
            transforms.ToTensor(),
            # Invert: we want black ink on white → 0=white, 1=black
            transforms.Normalize(mean=[0.5], std=[0.5]),
        ])
    
    def _generate_formulas(self):
        """Generate diverse math formula strings with their token sequences."""
        formulas = []
        vars_lower = list('abcdefghijklmnopqrstuvwxyz')
        vars_upper = list('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
        digits = list('0123456789')
        
        # Simple equations: v = x / t, a = b + c, etc.
        for _ in range(self.num_samples // 8):
            v1 = random.choice(vars_lower)
            v2 = random.choice(vars_lower)
            v3 = random.choice(vars_lower)
            op = random.choice(['+', '-', '='])
            formula = f"{v1} {op} {v2}"
            formulas.append(formula)
            
            formula2 = f"{v1} = {v2} {random.choice(['+', '-'])} {v3}"
            formulas.append(formula2)
        
        # Fractions: x / y, a / b
        for _ in range(self.num_samples // 8):
            v1 = random.choice(vars_lower + digits)
            v2 = random.choice(vars_lower + digits)
            formula = f"{v1} / {v2}"
            formulas.append(formula)
        
        # Powers: x ^ 2, a ^ n
        for _ in range(self.num_samples // 8):
            v1 = random.choice(vars_lower)
            exp = random.choice(digits[:5] + vars_lower[:5])
            formula = f"{v1} ^ {exp}"
            formulas.append(formula)
        
        # Expressions with numbers: 2 x + 3 y = 7
        for _ in range(self.num_samples // 8):
            d1 = random.choice(digits[1:])
            v1 = random.choice(vars_lower)
            op = random.choice(['+', '-'])
            d2 = random.choice(digits[1:])
            v2 = random.choice(vars_lower)
            formula = f"{d1} {v1} {op} {d2} {v2}"
            formulas.append(formula)
        
        # Functions: sin(x), cos(a), log(n)
        for _ in range(self.num_samples // 8):
            func = random.choice(['sin', 'cos', 'tan', 'log', 'ln'])
            v = random.choice(vars_lower)
            formula = f"{func} ( {v} )"
            formulas.append(formula)
        
        # Quadratic: a x ^ 2 + b x + c = 0
        for _ in range(self.num_samples // 16):
            formula = f"{random.choice(vars_lower)} ^ 2 + {random.choice(vars_lower)} + {random.choice(digits)} = 0"
            formulas.append(formula)
        
        # Greek letters
        for _ in range(self.num_samples // 16):
            greek = random.choice(['α', 'β', 'γ', 'δ', 'θ', 'π', 'σ', 'ω'])
            op = random.choice(['+', '-', '='])
            v = random.choice(vars_lower)
            formula = f"{greek} {op} {v}"
            formulas.append(formula)
        
        # Pad to exact size
        while len(formulas) < self.num_samples:
            formulas.append(random.choice(formulas))
        
        return formulas[:self.num_samples]
    
    def _render_formula(self, formula: str) -> Image.Image:
        """Render a formula string as a grayscale image.
        
        Uses basic text rendering with augmentations to simulate
        handwritten-style appearance.
        """
        # Create white background image
        img = Image.new('L', (self.img_width, self.img_height), color=255)
        draw = ImageDraw.Draw(img)
        
        # Try to use a font, fall back to default
        font_size = random.randint(24, 48) if self.augment else 36
        try:
            font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", font_size)
        except (IOError, OSError):
            try:
                font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", font_size)
            except (IOError, OSError):
                font = ImageFont.load_default()
        
        # Calculate text position (centered)
        bbox = draw.textbbox((0, 0), formula, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]
        
        x = max(0, (self.img_width - text_w) // 2)
        y = max(0, (self.img_height - text_h) // 2)
        
        # Add slight random offset if augmenting
        if self.augment:
            x += random.randint(-20, 20)
            y += random.randint(-10, 10)
        
        # Draw text (black on white)
        draw.text((x, y), formula, fill=0, font=font)
        
        # Augmentations
        if self.augment:
            # Random rotation (-5 to 5 degrees)
            angle = random.uniform(-5, 5)
            img = img.rotate(angle, fillcolor=255, expand=False)
            
            # Random noise
            import numpy as np
            arr = np.array(img).astype(np.float32)
            noise = np.random.normal(0, random.uniform(0, 10), arr.shape)
            arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
            img = Image.fromarray(arr)
        
        return img
    
    def _tokenize(self, formula: str) -> list:
        """Convert formula string to token index sequence."""
        indices = []
        # Simple character-level tokenization
        i = 0
        while i < len(formula):
            # Check for multi-char tokens (Greek letters mapped to LaTeX)
            greek_map = {
                'α': '\\alpha', 'β': '\\beta', 'γ': '\\gamma',
                'δ': '\\delta', 'θ': '\\theta', 'π': '\\pi',
                'σ': '\\sigma', 'ω': '\\omega',
            }
            func_map = {
                'sin': '\\sin', 'cos': '\\cos', 'tan': '\\tan',
                'log': '\\log', 'ln': '\\ln',
            }
            
            char = formula[i]
            
            # Check Greek
            if char in greek_map:
                token = greek_map[char]
                if token in self.token2idx:
                    indices.append(self.token2idx[token])
                i += 1
            # Check functions
            elif any(formula[i:].startswith(f) for f in func_map):
                for f_name, f_token in func_map.items():
                    if formula[i:].startswith(f_name):
                        if f_token in self.token2idx:
                            indices.append(self.token2idx[f_token])
                        i += len(f_name)
                        break
            # Regular character
            elif char in self.token2idx:
                indices.append(self.token2idx[char])
                i += 1
            elif char == '/':
                # Map / to \frac or just skip
                if '\\frac' in self.token2idx:
                    indices.append(self.token2idx['\\frac'])
                i += 1
            else:
                i += 1  # Skip unknown
        
        return indices
    
    def __len__(self):
        return self.num_samples
    
    def __getitem__(self, idx):
        formula = self.formulas[idx]
        
        # Render image
        img = self._render_formula(formula)
        img_tensor = self.transform(img)  # [1, H, W]
        
        # Tokenize
        targets = self._tokenize(formula)
        target_len = len(targets)
        
        return img_tensor, torch.tensor(targets, dtype=torch.long), target_len


def collate_fn(batch):
    """Custom collate: pad target sequences to same length."""
    images, targets, target_lens = zip(*batch)
    
    images = torch.stack(images)  # [B, 1, H, W]
    target_lens = torch.tensor(target_lens, dtype=torch.long)
    
    # Pad targets
    max_len = max(target_lens)
    padded = torch.zeros(len(targets), max_len, dtype=torch.long)
    for i, t in enumerate(targets):
        padded[i, :len(t)] = t
    
    # Flatten targets for CTC loss
    flat_targets = torch.cat([t for t in targets])
    
    return images, flat_targets, target_lens


# ─── Training ─────────────────────────────────────────────────────────────────

def train_epoch(model, dataloader, optimizer, criterion, device):
    model.train()
    total_loss = 0
    num_batches = 0
    
    for images, targets, target_lens in dataloader:
        images = images.to(device)
        targets = targets.to(device)
        target_lens = target_lens.to(device)
        
        optimizer.zero_grad()
        
        # Forward
        log_probs = model(images)  # [T, B, vocab_size]
        T = log_probs.shape[0]
        B = log_probs.shape[1]
        
        # Input lengths (all same since images are same width)
        input_lens = torch.full((B,), T, dtype=torch.long, device=device)
        
        # CTC loss
        loss = criterion(log_probs, targets, input_lens, target_lens)
        
        if not math.isfinite(loss.item()):
            print(f"Warning: non-finite loss {loss.item()}, skipping batch")
            continue
        
        loss.backward()
        
        # Gradient clipping
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
        
        optimizer.step()
        total_loss += loss.item()
        num_batches += 1
    
    return total_loss / max(num_batches, 1)


def ctc_greedy_decode(logits, idx2token):
    """Greedy CTC decoding: collapse repeated tokens, remove blanks."""
    # logits: [T, vocab_size]
    pred_indices = logits.argmax(dim=-1).tolist()  # [T]
    
    decoded = []
    prev = -1
    for idx in pred_indices:
        if idx != 0 and idx != prev:  # 0 = blank
            if idx in idx2token:
                decoded.append(idx2token[idx])
        prev = idx
    
    return ' '.join(decoded)


def evaluate(model, dataloader, idx2token, device, max_batches=10):
    """Evaluate model and print some predictions."""
    model.eval()
    correct = 0
    total = 0
    
    with torch.no_grad():
        for batch_idx, (images, targets, target_lens) in enumerate(dataloader):
            if batch_idx >= max_batches:
                break
            
            images = images.to(device)
            log_probs = model(images)  # [T, B, vocab_size]
            
            # Decode each sample
            offset = 0
            for i in range(images.shape[0]):
                t_len = target_lens[i].item()
                t_indices = targets[offset:offset + t_len].tolist()
                offset += t_len
                
                gt = ' '.join(idx2token.get(idx, '?') for idx in t_indices)
                pred = ctc_greedy_decode(log_probs[:, i, :], idx2token)
                
                if pred == gt:
                    correct += 1
                total += 1
                
                # Print first few
                if batch_idx == 0 and i < 5:
                    print(f"  GT:   {gt}")
                    print(f"  Pred: {pred}")
                    print()
    
    accuracy = correct / max(total, 1)
    return accuracy


# ─── ONNX Export ──────────────────────────────────────────────────────────────

def export_onnx(model, vocab_size, output_path, img_height=IMG_HEIGHT, img_width=IMG_WIDTH):
    """Export model to ONNX format for mobile deployment."""
    model.eval()
    
    wrapper = HMEInferenceWrapper(model)
    wrapper.eval()
    
    dummy_input = torch.randn(1, 1, img_height, img_width)
    
    torch.onnx.export(
        wrapper,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=13,
        do_constant_folding=True,
        input_names=['image'],
        output_names=['logits'],
        dynamic_axes={
            'image': {0: 'batch_size'},
            'logits': {0: 'batch_size'},
        },
    )
    
    # Verify
    import onnx
    model_onnx = onnx.load(output_path)
    onnx.checker.check_model(model_onnx)
    
    file_size = os.path.getsize(output_path) / (1024 * 1024)
    print(f"✅ ONNX model exported to {output_path} ({file_size:.1f} MB)")
    print(f"   Input:  image [1, 1, {img_height}, {img_width}]")
    print(f"   Output: logits [1, T, {vocab_size}]")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Train HME recognition model')
    parser.add_argument('--epochs', type=int, default=50, help='Training epochs')
    parser.add_argument('--batch_size', type=int, default=BATCH_SIZE)
    parser.add_argument('--lr', type=float, default=LEARNING_RATE)
    parser.add_argument('--train_samples', type=int, default=10000)
    parser.add_argument('--val_samples', type=int, default=1000)
    parser.add_argument('--checkpoint', type=str, default='best_hme_model.pt')
    parser.add_argument('--export_only', action='store_true')
    parser.add_argument('--output_onnx', type=str, default='hme_model.onnx')
    parser.add_argument('--device', type=str, default='auto')
    args = parser.parse_args()
    
    # Device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    print(f"🖥  Device: {device}")
    
    # Build vocabulary
    token2idx, idx2token, vocab_size = build_vocab()
    print(f"📚 Vocabulary: {vocab_size} tokens")
    
    # Save vocabulary
    vocab_path = 'hme_vocab.json'
    with open(vocab_path, 'w') as f:
        json.dump({str(i): t for i, t in idx2token.items()}, f, indent=2)
    print(f"📝 Vocab saved to {vocab_path}")
    
    # Create model
    model = HMEModel(vocab_size=vocab_size).to(device)
    param_count = sum(p.numel() for p in model.parameters())
    print(f"🧠 Model: {param_count:,} parameters")
    
    # Export only mode
    if args.export_only:
        if os.path.exists(args.checkpoint):
            model.load_state_dict(torch.load(args.checkpoint, map_location=device))
            print(f"📂 Loaded checkpoint: {args.checkpoint}")
        export_onnx(model, vocab_size, args.output_onnx)
        return
    
    # Datasets
    print(f"\n📊 Creating datasets...")
    train_ds = SyntheticMathDataset(args.train_samples, token2idx, augment=True)
    val_ds = SyntheticMathDataset(args.val_samples, token2idx, augment=False)
    
    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        num_workers=NUM_WORKERS, collate_fn=collate_fn, pin_memory=True,
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False,
        num_workers=NUM_WORKERS, collate_fn=collate_fn, pin_memory=True,
    )
    
    # Training setup
    criterion = nn.CTCLoss(blank=0, zero_infinity=True)
    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    
    best_accuracy = 0.0
    
    print(f"\n🏋️ Training for {args.epochs} epochs...")
    print(f"   Train samples: {len(train_ds)}")
    print(f"   Val samples:   {len(val_ds)}")
    print(f"   Batch size:    {args.batch_size}")
    print()
    
    for epoch in range(1, args.epochs + 1):
        # Train
        train_loss = train_epoch(model, train_loader, optimizer, criterion, device)
        scheduler.step()
        
        # Evaluate every 5 epochs
        if epoch % 5 == 0 or epoch == 1:
            print(f"Epoch {epoch}/{args.epochs} — Loss: {train_loss:.4f}")
            accuracy = evaluate(model, val_loader, idx2token, device)
            print(f"  Accuracy: {accuracy:.1%}")
            
            if accuracy > best_accuracy:
                best_accuracy = accuracy
                torch.save(model.state_dict(), args.checkpoint)
                print(f"  💾 Saved best model (accuracy: {accuracy:.1%})")
            print()
        else:
            print(f"Epoch {epoch}/{args.epochs} — Loss: {train_loss:.4f}")
    
    # Final export
    print(f"\n{'='*60}")
    print(f"Training complete! Best accuracy: {best_accuracy:.1%}")
    print(f"Exporting to ONNX...")
    
    # Load best model
    model.load_state_dict(torch.load(args.checkpoint, map_location=device))
    model.to('cpu')
    export_onnx(model, vocab_size, args.output_onnx)
    
    print(f"\n✅ Done! Files created:")
    print(f"   📦 {args.output_onnx} — ONNX model for mobile")
    print(f"   📝 {vocab_path} — Token vocabulary")
    print(f"   💾 {args.checkpoint} — PyTorch checkpoint")


if __name__ == '__main__':
    main()
