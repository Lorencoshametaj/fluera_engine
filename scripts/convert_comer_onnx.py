#!/usr/bin/env python3
"""Convert CoMER → ONNX (pre-patched, no pytorch-lightning)."""
import os, sys, json
import torch
import torch.nn as nn

OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "assets/models/comer"
COMER_DIR = "/tmp/CoMER"

# Patch pos_enc.py to fix self.device (PL provides this, nn.Module doesn't)
pos_enc_py = os.path.join(COMER_DIR, "comer", "model", "pos_enc.py")
with open(pos_enc_py) as f:
    src = f.read()
# Replace self.device with a method that gets device from parameters
src = src.replace("device=self.device", "device=next(self.parameters()).device")
with open(pos_enc_py, 'w') as f:
    f.write(src)

sys.path.insert(0, COMER_DIR)
from comer.model.encoder import Encoder
from comer.model.decoder import Decoder

print("[1/4] Building model...")
encoder = Encoder(d_model=256, growth_rate=24, num_layers=16)
# ARM is ESSENTIAL for model quality — without it, decoder produces garbage
decoder = Decoder(d_model=256, nhead=8, num_decoder_layers=3,
                  dim_feedforward=1024, dropout=0.3, dc=32,
                  cross_coverage=True, self_coverage=True)

print("[2/4] Loading checkpoint...")
ckpt_path = os.path.join(COMER_DIR, "lightning_logs", "version_0", "checkpoints")
ckpt_files = [f for f in os.listdir(ckpt_path) if f.endswith('.ckpt')]
ckpt_path = os.path.join(ckpt_path, ckpt_files[0])
print(f"  Checkpoint: {os.path.getsize(ckpt_path)/1024/1024:.1f} MB")

ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
state = ckpt["state_dict"]

# Keys are comer_model.encoder.XXX and comer_model.decoder.XXX
enc_sd = {k.replace("comer_model.encoder.", ""): v for k, v in state.items() if k.startswith("comer_model.encoder.")}
dec_sd = {k.replace("comer_model.decoder.", ""): v for k, v in state.items() if k.startswith("comer_model.decoder.")}
print(f"  Enc keys: {len(enc_sd)}, Dec keys: {len(dec_sd)}")

m1 = encoder.load_state_dict(enc_sd, strict=True)
# strict=False: ARM's BN1d→BN2d key mapping (compatible weights)
m2 = decoder.load_state_dict(dec_sd, strict=False)
if m2.missing_keys:
    print(f"  ⚠ Decoder missing: {m2.missing_keys[:5]}")
if m2.unexpected_keys:
    print(f"  ⓘ Decoder unexpected: {m2.unexpected_keys[:5]}")
encoder.eval(); decoder.eval()

ep = sum(p.numel() for p in encoder.parameters())
dp = sum(p.numel() for p in decoder.parameters())
print(f"  ✓ Encoder: {ep:,} params ({ep*4/1024/1024:.1f} MB)")
print(f"  ✓ Decoder: {dp:,} params ({dp*4/1024/1024:.1f} MB)")

print("\n[3/4] Exporting ONNX...")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# --- Encoder ---
class EncW(nn.Module):
    def __init__(self, e):
        super().__init__()
        self.e = e
    def forward(self, img, mask):
        # Cast mask to bool for ONNX compatibility (bitwise_not only works on bool)
        mask = mask.bool()
        f, m = self.e(img, mask)
        return f, m

ew = EncW(encoder); ew.eval()
# Use realistic CROHME image size (CROHME images are ~50-80px)
di = torch.randn(1, 1, 64, 64)
dm = torch.zeros(1, 64, 64, dtype=torch.long)
with torch.no_grad():
    tf, tm = ew(di, dm)
    print(f"  enc test: feature={tf.shape} mask={tm.shape}")

ep_path = os.path.join(OUTPUT_DIR, "encoder.onnx")
torch.onnx.export(ew, (di, dm), ep_path,
    input_names=["image", "image_mask"],
    output_names=["feature", "feature_mask"],
    dynamic_axes={
        "image": {0: "b", 2: "h", 3: "w"},
        "image_mask": {0: "b", 1: "h", 2: "w"},
        "feature": {0: "b", 1: "fh", 2: "fw"},
        "feature_mask": {0: "b", 1: "fh", 2: "fw"},
    },
    opset_version=14, do_constant_folding=True, dynamo=False)
es = os.path.getsize(ep_path) / 1024 / 1024
print(f"  ✓ encoder.onnx: {es:.1f} MB")

# --- Decoder ---
class DecW(nn.Module):
    def __init__(self, d):
        super().__init__()
        self.d = d
    def forward(self, f, fm, t):
        # Cast mask to bool (PyTorch 2.x requires bool for masked_fill)
        fm_bool = fm.bool() if fm.dtype != torch.bool else fm
        return self.d(f, fm_bool, t)

dw = DecW(decoder); dw.eval()
dt = torch.tensor([[1]], dtype=torch.long)
with torch.no_grad():
    tl = dw(tf, tm, dt)
    print(f"  dec test: logits={tl.shape}")

dp_path = os.path.join(OUTPUT_DIR, "decoder.onnx")
torch.onnx.export(dw, (tf, tm, dt), dp_path,
    input_names=["feature", "feature_mask", "tgt"],
    output_names=["logits"],
    dynamic_axes={
        "feature": {0: "b", 1: "fh", 2: "fw"},
        "feature_mask": {0: "b", 1: "fh", 2: "fw"},
        "tgt": {0: "b", 1: "s"},
        "logits": {0: "b", 1: "s"},
    },
    opset_version=14, do_constant_folding=True, dynamo=False)
ds = os.path.getsize(dp_path) / 1024 / 1024
print(f"  ✓ decoder.onnx: {ds:.1f} MB")

# --- Vocabulary ---
print("\n[4/4] Vocabulary...")
dict_path = os.path.join(COMER_DIR, "comer", "datamodule", "dictionary.txt")
vocab = {"0": "<pad>", "1": "<sos>", "2": "<eos>"}
with open(dict_path) as f:
    for line in f:
        w = line.strip()
        if w:
            vocab[str(len(vocab))] = w

vp = os.path.join(OUTPUT_DIR, "vocab.json")
with open(vp, 'w', encoding='utf-8') as fout:
    json.dump({
        "vocab": vocab,
        "special_tokens": {"pad_token_id": 0, "sos_token_id": 1, "eos_token_id": 2},
        "vocab_size": len(vocab),
    }, fout, ensure_ascii=False, indent=2)
print(f"  ✓ vocab.json: {len(vocab)} tokens")

# Print some sample tokens
for i in [0, 1, 2, 3, 10, 20, 50, len(vocab)-1]:
    print(f"    {i}: '{vocab[str(i)]}'")

print(f"\n{'='*50}")
print(f"  encoder.onnx: {es:.1f} MB")
print(f"  decoder.onnx: {ds:.1f} MB")
print(f"  TOTAL: {es+ds:.1f} MB FP32")
print(f"{'='*50}\n✓ Done!")
