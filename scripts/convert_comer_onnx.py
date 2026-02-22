#!/usr/bin/env python3
"""Convert CoMER → ONNX (pre-patched, no pytorch-lightning)."""
import os, sys, json
import torch
import torch.nn as nn

OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "assets/models/comer"
COMER_DIR = "/tmp/CoMER"

# Patch pos_enc.py to fix self.device (PL provides this, nn.Module doesn't)
# ImgPosEnc has no trainable parameters, so next(self.parameters()) raises
# StopIteration. Use x.device from the forward() input instead.
pos_enc_py = os.path.join(COMER_DIR, "comer", "model", "pos_enc.py")
with open(pos_enc_py) as f:
    src = f.read()
src = src.replace("device=self.device", "device=x.device")
with open(pos_enc_py, 'w') as f:
    f.write(src)

sys.path.insert(0, COMER_DIR)

# --- MONKEY PATCH ARM FOR ONNX COMPATIBILITY ---
import comer.model.transformer.arm as arm_module
class ONNXSafeMaskBatchNorm2d(nn.Module):
    def __init__(self, num_features: int):
        super().__init__()
        # PyTorch BatchNorm2d does exactly what we want without boolean indexing!
        self.bn = nn.BatchNorm2d(num_features)

    def forward(self, x: torch.Tensor, mask: torch.Tensor) -> torch.Tensor:
        # x is [b, d, h, w], mask is [b, 1, h, w] (bool: True where padded)
        # In eval mode, BN is just (x - mean)/sqrt(var)*w + b.
        # We can apply it everywhere, then zero out the padded regions.
        out = self.bn(x)
        out = out.masked_fill(mask, 0.0)
        return out

arm_module.MaskBatchNorm2d = ONNXSafeMaskBatchNorm2d
# -----------------------------------------------

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

# ----- ARM weight key remapping -----
# The checkpoint may use slightly different key names for ARM's BatchNorm
# layers (e.g. bn1d vs bn, or flattened vs nested). We auto-remap to
# match the decoder's expected keys.
dec_expected = set(decoder.state_dict().keys())
dec_provided = set(dec_sd.keys())

missing = dec_expected - dec_provided
unexpected = dec_provided - dec_expected

if missing or unexpected:
    print(f"  ⚠ Key mismatch detected — remapping ARM weights...")
    print(f"    Missing ({len(missing)}):    {sorted(missing)[:10]}")
    print(f"    Unexpected ({len(unexpected)}): {sorted(unexpected)[:10]}")

    # Build mapping: for each missing key, try to find a matching unexpected key
    # by comparing the suffix after the last differing segment.
    remapped = {}
    used_unexpected = set()
    for mkey in sorted(missing):
        # Try exact shape match among unexpected keys with similar suffix
        m_parts = mkey.split('.')
        m_suffix = '.'.join(m_parts[-2:])  # e.g. "bn.weight", "running_mean"
        m_shape = decoder.state_dict()[mkey].shape

        for ukey in sorted(unexpected):
            if ukey in used_unexpected:
                continue
            u_parts = ukey.split('.')
            u_suffix = '.'.join(u_parts[-2:])

            # Match by suffix similarity and identical tensor shape
            if m_suffix == u_suffix or m_parts[-1] == u_parts[-1]:
                if dec_sd[ukey].shape == m_shape:
                    remapped[mkey] = ukey
                    used_unexpected.add(ukey)
                    print(f"    ✓ Remap: {ukey} → {mkey}")
                    break

    # Apply remapping
    for new_key, old_key in remapped.items():
        dec_sd[new_key] = dec_sd.pop(old_key)

    still_missing = dec_expected - set(dec_sd.keys())
    if still_missing:
        print(f"  ⚠ Still missing after remap: {sorted(still_missing)[:10]}")
        print(f"    Loading with strict=False as fallback")
        m2 = decoder.load_state_dict(dec_sd, strict=False)
        if m2.missing_keys:
            print(f"    Final missing: {m2.missing_keys}")
    else:
        print(f"  ✓ All keys remapped successfully — loading with strict=True")
        m2 = decoder.load_state_dict(dec_sd, strict=True)
else:
    print(f"  ✓ All decoder keys match — loading with strict=True")
    m2 = decoder.load_state_dict(dec_sd, strict=True)

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

# --- Post-export sanity check ---
print("\n[5/5] Sanity check...")
with torch.no_grad():
    # Run encoder on a small test image
    test_img = torch.randn(1, 1, 64, 128)
    test_mask = torch.zeros(1, 64, 128, dtype=torch.long)
    feat, feat_mask = ew(test_img, test_mask)

    # Run decoder for a few steps (greedy decode)
    sos_id = 1
    eos_id = 2
    generated = [sos_id]
    for step in range(20):
        tgt = torch.tensor([generated], dtype=torch.long)
        logits = dw(feat, feat_mask, tgt)
        next_id = logits[0, -1, :].argmax().item()
        if next_id == eos_id:
            break
        generated.append(next_id)

    # Decode with vocab
    tokens = []
    for tid in generated[1:]:  # skip SOS
        tok = vocab.get(str(tid), f"<{tid}>")
        tokens.append(tok)

    decoded = ' '.join(tokens)
    print(f"  Test decode (20 steps): {decoded}")

    # Check for excessive repetition (symptom of broken ARM)
    if len(generated) > 5:
        unique_ratio = len(set(generated[1:])) / len(generated[1:])
        if unique_ratio < 0.3:
            print(f"  ⚠ WARNING: Low token diversity ({unique_ratio:.1%}) — ARM may not be loaded correctly!")
            print(f"    The decoder is producing repetitive garbage. Check ARM weight mapping.")
        else:
            print(f"  ✓ Token diversity OK ({unique_ratio:.1%})")

print(f"\n{'='*50}")
print(f"  encoder.onnx: {es:.1f} MB")
print(f"  decoder.onnx: {ds:.1f} MB")
print(f"  TOTAL: {es+ds:.1f} MB FP32")
print(f"{'='*50}\n✓ Done!")

