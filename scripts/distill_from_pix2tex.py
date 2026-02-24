#!/usr/bin/env python3
"""
🧠 Knowledge Distillation: Pix2Tex → HME Model
================================================
Uses Pix2Tex (MIT, ~85% accuracy) as teacher to improve the small HME model.

Flow:
  1. Generate synthetic formula images (from existing training script)
  2. Label them with Pix2Tex (teacher)
  3. Map teacher tokens to student vocabulary
  4. Fine-tune student model on teacher labels
  5. Re-export ONNX

Usage:
  source .venv/bin/activate
  python scripts/distill_from_pix2tex.py
"""

import sys, os, io, time, random, math, pickle
sys.path.insert(0, '.')

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader
from PIL import Image
import numpy as np
from tqdm import tqdm

# Import from training script
from scripts.train_hme_top_tier import (
    HMEAttentionModel, TopTierDataset, VOCAB_SIZE, IMG_HEIGHT, IMG_WIDTH,
    MAX_SEQ_LEN, PAD_IDX, SOS_IDX, EOS_IDX, ALL_TOKENS,
    EncoderWrapper, DecoderWrapper, export_onnx, download_fonts
)

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════════════════════

DISTILL_EPOCHS = 30
DISTILL_LR = 1e-4
DISTILL_BATCH = 64
NUM_TEACHER_SAMPLES = 5_000   # Images to label with Pix2Tex (~2.5h)
TEMPERATURE = 3.0             # Soft label temperature
ALPHA = 0.5                   # 0=only teacher, 1=only hard labels

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Generate & label with Pix2Tex
# ═══════════════════════════════════════════════════════════════════════════════

def generate_teacher_labels(num_samples):
    """Generate formula images and label them with Pix2Tex."""
    from pix2tex.cli import LatexOCR
    
    print("📚 Loading Pix2Tex teacher model...")
    teacher = LatexOCR()
    print("✅ Teacher loaded")
    
    # Download fonts and generate synthetic images
    print("🖊  Downloading fonts...")
    fonts = download_fonts()
    print(f"   {len(fonts)} fonts available")
    
    dataset = TopTierDataset(num_samples, fonts, augment=True)
    dataset.set_epoch(50)  # Use moderate augmentation
    
    teacher_data = []
    skipped = 0
    
    print(f"🏭 Generating {num_samples} images & labeling with Pix2Tex...")
    for i in tqdm(range(num_samples), desc="Labeling"):
        try:
            img_tensor, original_tokens = dataset[i]
            
            # Convert tensor to PIL Image for Pix2Tex
            # img_tensor is [1, H, W], normalized to [-1, 1]
            img_np = ((img_tensor[0].numpy() * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)
            pil_img = Image.fromarray(img_np, mode='L').convert('RGB')
            
            # Get teacher prediction
            teacher_latex = teacher(pil_img)
            
            if teacher_latex and len(teacher_latex.strip()) > 0:
                # Map teacher LaTeX to student token IDs
                student_tokens = map_latex_to_tokens(teacher_latex)
                if student_tokens and len(student_tokens) >= 2:
                    teacher_data.append((img_tensor, student_tokens, original_tokens))
                else:
                    # Fall back to original tokens
                    teacher_data.append((img_tensor, original_tokens, original_tokens))
            else:
                # Fall back to original tokens
                teacher_data.append((img_tensor, original_tokens, original_tokens))
                skipped += 1
                
        except Exception as e:
            if i < 3:
                print(f"  ⚠️ Error on sample {i}: {e}")
            teacher_data.append((img_tensor, original_tokens, original_tokens))
            skipped += 1
    
    print(f"✅ Teacher-labeled: {len(teacher_data)} samples ({skipped} fell back to original)")
    
    # Save cache
    cache_path = 'teacher_data_cache.pkl'
    print(f"💾 Saving teacher data cache to {cache_path}...")
    with open(cache_path, 'wb') as f:
        pickle.dump(teacher_data, f)
    
    return teacher_data


def map_latex_to_tokens(latex_str):
    """Map a LaTeX string from Pix2Tex to student token IDs."""
    # Build token lookup
    token2idx = {t: i for i, t in enumerate(ALL_TOKENS)}
    
    tokens = [SOS_IDX]
    
    # Simple tokenizer: split by spaces and try to match
    parts = latex_str.replace('{', ' { ').replace('}', ' } ')
    parts = parts.replace('(', ' ( ').replace(')', ' ) ')
    parts = parts.replace('[', ' [ ').replace(']', ' ] ')
    parts = parts.replace('+', ' + ').replace('-', ' - ').replace('=', ' = ')
    parts = parts.replace('^', ' ^ ').replace('_', ' _ ')
    parts = parts.replace(',', ' , ').replace('.', ' . ')
    parts = parts.replace('!', ' ! ').replace('|', ' | ')
    parts = parts.replace('<', ' < ').replace('>', ' > ')
    
    words = parts.split()
    
    for word in words:
        word = word.strip()
        if not word:
            continue
        
        # Direct match
        if word in token2idx:
            tokens.append(token2idx[word])
            continue
        
        # Try with backslash
        if not word.startswith('\\') and f'\\{word}' in token2idx:
            tokens.append(token2idx[f'\\{word}'])
            continue
            
        # Character by character for unrecognized words
        for ch in word:
            if ch in token2idx:
                tokens.append(token2idx[ch])
    
    tokens.append(EOS_IDX)
    
    # Truncate to MAX_SEQ_LEN
    if len(tokens) > MAX_SEQ_LEN:
        tokens = tokens[:MAX_SEQ_LEN - 1] + [EOS_IDX]
    
    return tokens


# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Distillation Training
# ═══════════════════════════════════════════════════════════════════════════════

class DistillDataset(torch.utils.data.Dataset):
    """Dataset with teacher labels."""
    def __init__(self, teacher_data):
        self.data = teacher_data
    
    def __len__(self):
        return len(self.data)
    
    def __getitem__(self, idx):
        img, teacher_tokens, original_tokens = self.data[idx]
        
        # Use teacher tokens with probability, original otherwise (mixed)
        if random.random() < (1 - ALPHA):
            tgt = teacher_tokens
        else:
            tgt = original_tokens
        
        # Ensure it's a list of ints
        if isinstance(tgt, torch.Tensor):
            tgt = tgt.tolist()
        
        # Pad to MAX_SEQ_LEN
        padded = tgt + [PAD_IDX] * (MAX_SEQ_LEN - len(tgt))
        padded = padded[:MAX_SEQ_LEN]
        
        return img, torch.tensor(padded, dtype=torch.long)


def distill_train(model, teacher_data, device):
    """Fine-tune the student model on teacher-labeled data."""
    dataset = DistillDataset(teacher_data)
    loader = DataLoader(dataset, batch_size=DISTILL_BATCH, shuffle=True,
                       num_workers=0, pin_memory=True, drop_last=True)
    
    optimizer = torch.optim.AdamW(model.parameters(), lr=DISTILL_LR, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, DISTILL_EPOCHS)
    criterion = nn.CrossEntropyLoss(ignore_index=PAD_IDX, label_smoothing=0.1)
    scaler = torch.amp.GradScaler('cuda', enabled=device.type == 'cuda')
    
    print(f"\n🎓 Starting distillation training ({DISTILL_EPOCHS} epochs, {len(dataset)} samples)")
    
    best_loss = float('inf')
    
    for epoch in range(1, DISTILL_EPOCHS + 1):
        model.train()
        total_loss = 0
        num_batches = 0
        t0 = time.time()
        
        for imgs, tgts in loader:
            imgs, tgts = imgs.to(device), tgts.to(device)
            
            # Teacher forcing: input is tgt[:-1], target is tgt[1:]
            tgt_input = tgts[:, :-1]
            tgt_output = tgts[:, 1:]
            
            optimizer.zero_grad(set_to_none=True)
            
            with torch.amp.autocast('cuda', enabled=device.type == 'cuda'):
                logits = model(imgs, tgt_input)
                loss = criterion(
                    logits.reshape(-1, VOCAB_SIZE),
                    tgt_output.reshape(-1)
                )
            
            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            scaler.step(optimizer)
            scaler.update()
            
            total_loss += loss.item()
            num_batches += 1
        
        scheduler.step()
        avg_loss = total_loss / max(num_batches, 1)
        elapsed = time.time() - t0
        
        if avg_loss < best_loss:
            best_loss = avg_loss
            torch.save({
                'model_state': model.state_dict(),
                'epoch': epoch,
                'loss': avg_loss,
            }, 'best_distilled.pt')
            saved = " 💾 Saved best"
        else:
            saved = ""
        
        print(f"  Epoch {epoch}/{DISTILL_EPOCHS} — Loss: {avg_loss:.4f} | "
              f"LR: {scheduler.get_last_lr()[0]:.6f} | {elapsed:.0f}s{saved}")
    
    # Load best
    ckpt = torch.load('best_distilled.pt', map_location=device)
    model.load_state_dict(ckpt['model_state'])
    print(f"\n✅ Distillation complete! Best loss: {ckpt['loss']:.4f}")
    
    return model


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"🖥  Device: {device}")
    
    # Load the pre-trained student model
    print("📦 Loading student model...")
    model = HMEAttentionModel().to(device)
    
    ckpt_path = 'checkpoint_latest.pt'
    if not os.path.exists(ckpt_path):
        ckpt_path = 'best_hme_top_tier.pt'
    
    ckpt = torch.load(ckpt_path, map_location=device)
    if 'ema_state' in ckpt:
        model.load_state_dict(ckpt['ema_state'], strict=False)
        print("  Loaded EMA weights")
    elif 'model_state' in ckpt:
        model.load_state_dict(ckpt['model_state'], strict=False)
    else:
        model.load_state_dict(ckpt, strict=False)
    print("  ✅ Student loaded")
    
    # Step 1: Generate teacher labels (or load from cache)
    cache_path = 'teacher_data_cache.pkl'
    if os.path.exists(cache_path):
        print(f"📦 Loading cached teacher data from {cache_path}...")
        with open(cache_path, 'rb') as f:
            teacher_data = pickle.load(f)
        print(f"  ✅ Loaded {len(teacher_data)} cached samples")
    else:
        teacher_data = generate_teacher_labels(NUM_TEACHER_SAMPLES)
    
    # Step 2: Distillation training
    model = distill_train(model, teacher_data, device)
    
    # Step 3: Export ONNX
    print("\n📦 Exporting ONNX...")
    model = export_onnx(model, device, 'hme_attn_onnx')
    
    # Re-export with fixed seq_len (matching what the Flutter app expects)
    print("\n🔧 Re-exporting decoder with fixed seq_len=64...")
    os.system(f'source .venv/bin/activate && python scripts/reexport_onnx.py')
    
    print("\n" + "=" * 60)
    print("🎉 DISTILLATION COMPLETE!")
    print("=" * 60)
    print(f"  Models saved to: hme_attn_onnx/")
    print(f"  Assets updated:  assets/models/hme/")
    print(f"  Run 'flutter run' to test on device!")
