#!/usr/bin/env python3
"""Convert CoMER → PyTorch Mobile (TorchScript)."""
import os, sys, json
import torch
import torch.nn as nn
from torch.utils.mobile_optimizer import optimize_for_mobile

OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "assets/models/comer"
COMER_DIR = "/tmp/CoMER"

# Patch pos_enc.py to use x.device (parameter independent)
pos_enc_py = os.path.join(COMER_DIR, "comer", "model", "pos_enc.py")
with open(pos_enc_py) as f:
    src = f.read()
src = src.replace("device=self.device", "device=x.device")
with open(pos_enc_py, 'w') as f:
    f.write(src)

sys.path.insert(0, COMER_DIR)
from comer.model.encoder import Encoder
from comer.model.decoder import Decoder

print("[1/4] Building model...")
encoder = Encoder(d_model=256, growth_rate=24, num_layers=16)
decoder = Decoder(d_model=256, nhead=8, num_decoder_layers=3,
                  dim_feedforward=1024, dropout=0.3, dc=32,
                  cross_coverage=True, self_coverage=True)

print("[2/4] Loading checkpoint...")
ckpt_path = os.path.join(COMER_DIR, "lightning_logs", "version_0", "checkpoints")
ckpt_files = [f for f in os.listdir(ckpt_path) if f.endswith('.ckpt')]
ckpt_path = os.path.join(ckpt_path, ckpt_files[0])

# Load weights (CPU mapped)
ckpt = torch.load(ckpt_path, map_location='cpu', weights_only=False)
state = ckpt['state_dict']
enc_sd = {k.replace("comer_model.encoder.", ""): v for k, v in state.items() if k.startswith("comer_model.encoder.")}
dec_sd = {k.replace("comer_model.decoder.", ""): v for k, v in state.items() if k.startswith("comer_model.decoder.")}

# Load the weights (strict=True since we are taking ARM as well)
encoder.load_state_dict(enc_sd, strict=True)
decoder.load_state_dict(dec_sd, strict=True)
encoder.eval(); decoder.eval()

print("\n[3/4] Exporting to PyTorch Mobile (TorchScript)...")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# --- Encoder ---
class EncW(nn.Module):
    def __init__(self, e): super().__init__(); self.e = e
    def forward(self, img, mask):
        # Mask needs to be bool for PyTorch
        return self.e(img, mask.bool())

ew = EncW(encoder).eval()
# Dummy input for tracing.
# Note: TorchScript tracing records operations. Unlike ONNX, operations like
# x[mask] keep their dynamic shape properties when traced!
di = torch.randn(1, 1, 64, 64)
dm = torch.zeros(1, 64, 64, dtype=torch.long)

print("  Tracing Encoder...")
with torch.no_grad():
    traced_enc = torch.jit.trace(ew, (di, dm))
    optimized_enc = optimize_for_mobile(traced_enc)
    
ep_path = os.path.join(OUTPUT_DIR, "encoder.ptl")
optimized_enc._save_for_lite_interpreter(ep_path)
print(f"  ✓ encoder.ptl: {os.path.getsize(ep_path)/1024/1024:.1f} MB")

# --- Decoder ---
class DecW(nn.Module):
    def __init__(self, d): super().__init__(); self.d = d
    def forward(self, f, fm, t):
        fm_bool = fm.bool() if fm.dtype != torch.bool else fm
        return self.d(f, fm_bool, t)

dw = DecW(decoder).eval()
with torch.no_grad():
    tf, tm = ew(di, dm)
    dt = torch.tensor([[1]], dtype=torch.long) # SOS token
    
    print("  Tracing Decoder (with ARM)...")
    traced_dec = torch.jit.trace(dw, (tf, tm, dt))
    optimized_dec = optimize_for_mobile(traced_dec)

dp_path = os.path.join(OUTPUT_DIR, "decoder.ptl")
optimized_dec._save_for_lite_interpreter(dp_path)
print(f"  ✓ decoder.ptl: {os.path.getsize(dp_path)/1024/1024:.1f} MB")

print("\n[4/4] Extracting Vocabulary...")
from comer.datamodule import vocab
vdict = {i: c for c, i in vocab.word2idx.items()}
vocab_file = os.path.join(OUTPUT_DIR, "vocab.json")
with open(vocab_file, "w") as f:
    json.dump({"vocab": vdict}, f, indent=2, ensure_ascii=False)
print(f"  ✓ vocab.json: {len(vdict)} tokens")

print("\n✓ Done! PTL models are ready in", OUTPUT_DIR)
