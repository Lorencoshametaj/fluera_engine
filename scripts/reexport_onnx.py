#!/usr/bin/env python3
"""Re-export HME decoder with FIXED seq_len to avoid ONNX reshape issues."""
import sys, os
sys.path.insert(0, '.')
import torch

from scripts.train_hme_top_tier import (
    HMEAttentionModel, VOCAB_SIZE, IMG_HEIGHT, IMG_WIDTH,
    EncoderWrapper, MAX_SEQ_LEN, PAD_IDX, SOS_IDX
)

device = torch.device('cpu')

# Load checkpoint
checkpoint_path = 'checkpoint_latest.pt'
if not os.path.exists(checkpoint_path):
    checkpoint_path = 'best_hme_top_tier.pt'

print(f"Loading checkpoint: {checkpoint_path}")
ckpt = torch.load(checkpoint_path, map_location=device)

model = HMEAttentionModel().to(device)
if 'ema_state' in ckpt:
    model.load_state_dict(ckpt['ema_state'], strict=False)
    print("Loaded EMA weights")
elif 'model_state' in ckpt:
    model.load_state_dict(ckpt['model_state'], strict=False)
else:
    model.load_state_dict(ckpt, strict=False)

model.eval()

output_dir = 'hme_attn_onnx'
os.makedirs(output_dir, exist_ok=True)

# 1. Export encoder (no changes needed)
print("Exporting encoder...")
dummy_img = torch.randn(1, 1, IMG_HEIGHT, IMG_WIDTH)
torch.onnx.export(
    EncoderWrapper(model.encoder), dummy_img,
    f'{output_dir}/hme_encoder.onnx', opset_version=14, dynamo=False,
    input_names=['image'], output_names=['features']
)
print(f"  ✅ Encoder: {os.path.getsize(f'{output_dir}/hme_encoder.onnx') / 1e6:.1f} MB")

# 2. Export decoder with FIXED seq_len=MAX_SEQ_LEN
#    The Dart side will pad tokens to MAX_SEQ_LEN and use the causal mask
print(f"Exporting decoder with FIXED seq_len={MAX_SEQ_LEN}...")
with torch.no_grad():
    feat = model.encoder(dummy_img)

# Dummy tokens: [SOS, PAD, PAD, ..., PAD] of length MAX_SEQ_LEN
dummy_tokens = torch.full((1, MAX_SEQ_LEN), PAD_IDX, dtype=torch.long)
dummy_tokens[0, 0] = SOS_IDX

torch.onnx.export(
    model.decoder,  # Use raw decoder, not wrapper
    (dummy_tokens, feat),
    f'{output_dir}/hme_decoder.onnx', opset_version=14, dynamo=False,
    input_names=['tokens', 'memory'], output_names=['logits'],
)
print(f"  ✅ Decoder: {os.path.getsize(f'{output_dir}/hme_decoder.onnx') / 1e6:.1f} MB")

# Verify with different "active" lengths (all padded to MAX_SEQ_LEN)
import onnxruntime as ort
import numpy as np
print(f"\nVerifying decoder (all padded to {MAX_SEQ_LEN})...")
session = ort.InferenceSession(f'{output_dir}/hme_decoder.onnx')
feat_np = feat.numpy()

for active_len in [1, 2, 5, 10, 20]:
    tokens = np.full((1, MAX_SEQ_LEN), PAD_IDX, dtype=np.int64)
    tokens[0, 0] = SOS_IDX
    for i in range(1, active_len):
        tokens[0, i] = 10  # some token
    try:
        out = session.run(None, {'tokens': tokens, 'memory': feat_np})
        # Check argmax of the active_len-th position
        logits_at_pos = out[0][0, active_len - 1]
        top_token = np.argmax(logits_at_pos)
        print(f"  ✅ active_len={active_len}: output shape {out[0].shape}, top token at pos {active_len-1}: {top_token}")
    except Exception as e:
        print(f"  ❌ active_len={active_len}: {e}")

# Copy to assets
import shutil
shutil.copy(f'{output_dir}/hme_encoder.onnx', 'assets/models/hme/hme_encoder.onnx')
shutil.copy(f'{output_dir}/hme_decoder.onnx', 'assets/models/hme/hme_decoder.onnx')
print(f"\n✅ Copied to assets/models/hme/")
print(f"📝 MAX_SEQ_LEN = {MAX_SEQ_LEN} — Dart decoder must pad tokens to this length!")
