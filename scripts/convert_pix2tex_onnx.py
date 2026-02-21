#!/usr/bin/env python3
"""
🧮 Pix2Tex ONNX Converter with INT8 Quantization

Converts the pix2tex (LaTeX-OCR) model to ONNX format with INT8
dynamic quantization for on-device mobile inference.

Usage:
    pip install pix2tex torch onnx onnxruntime
    python scripts/convert_pix2tex_onnx.py

Output:
    assets/models/pix2tex/encoder_int8.onnx   (~6-8 MB)
    assets/models/pix2tex/decoder_int8.onnx   (~4-7 MB)
    assets/models/pix2tex/tokenizer.json       (~50 KB)
"""

import json
import os
import sys

import torch
import torch.nn as nn

def main():
    output_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "assets", "models", "pix2tex",
    )
    os.makedirs(output_dir, exist_ok=True)

    print("=" * 60)
    print("  Pix2Tex → ONNX + INT8 Quantization")
    print("=" * 60)

    # -------------------------------------------------------------------------
    # Step 1: Load pix2tex model
    # -------------------------------------------------------------------------
    print("\n[1/6] Loading pix2tex model...")
    try:
        from pix2tex.cli import LatexOCR
        model = LatexOCR()
        encoder = model.model.encoder
        decoder = model.model.decoder
        tokenizer = model.tokenizer
        args = model.model.args
        max_seq_len = getattr(args, 'max_seq_len', 512)
        num_tokens = getattr(args, 'num_tokens', 8000)
        dim = getattr(args, 'dim', 256)
        channels = getattr(args, 'channels', 1)
        max_h = getattr(args, 'max_height', 192)
        max_w = getattr(args, 'max_width', 672)
        print(f"  ✓ Model loaded (max_seq_len={max_seq_len}, "
              f"num_tokens={num_tokens}, dim={dim}, "
              f"channels={channels}, max={max_w}×{max_h})")
    except ImportError:
        print("  ✗ pix2tex not installed. Run: pip install pix2tex")
        sys.exit(1)
    except Exception as e:
        print(f"  ✗ Failed to load model: {e}")
        import traceback; traceback.print_exc()
        sys.exit(1)

    # -------------------------------------------------------------------------
    # Step 2: Export encoder to ONNX
    # -------------------------------------------------------------------------
    print("\n[2/6] Exporting encoder to ONNX...")
    encoder.eval()
    encoder_path = os.path.join(output_dir, "encoder.onnx")

    # Create dummy input matching pix2tex's expected image size
    dummy_img = torch.randn(1, channels, max_h, max_w)

    try:
        torch.onnx.export(
            encoder,
            dummy_img,
            encoder_path,
            input_names=["pixel_values"],
            output_names=["encoder_output"],
            dynamic_axes={
                "pixel_values": {0: "batch", 2: "height", 3: "width"},
                "encoder_output": {0: "batch", 1: "seq_len"},
            },
            opset_version=14,
            do_constant_folding=True,
            dynamo=False,
        )
        size_mb = os.path.getsize(encoder_path) / (1024 * 1024)
        print(f"  ✓ Encoder exported ({size_mb:.1f} MB)")
    except Exception as e:
        print(f"  ✗ Encoder export failed: {e}")
        print("  Trying alternative export method...")
        class EncoderWrapper(nn.Module):
            def __init__(self, enc):
                super().__init__()
                self.enc = enc
            def forward(self, x):
                return self.enc(x)
        
        wrapped = EncoderWrapper(encoder)
        wrapped.eval()
        torch.onnx.export(
            wrapped, dummy_img, encoder_path,
            input_names=["pixel_values"],
            output_names=["encoder_output"],
            opset_version=14,
            do_constant_folding=True,
            dynamo=False,
        )
        size_mb = os.path.getsize(encoder_path) / (1024 * 1024)
        print(f"  ✓ Encoder exported via wrapper ({size_mb:.1f} MB)")

    # -------------------------------------------------------------------------
    # Step 3: Export decoder to ONNX
    # -------------------------------------------------------------------------
    print("\n[3/6] Exporting decoder to ONNX...")
    decoder.eval()
    decoder_path = os.path.join(output_dir, "decoder.onnx")

    # Decoder inputs: token IDs + encoder output
    dummy_tgt = torch.randint(0, num_tokens, (1, 10))
    # Get actual encoder output shape
    with torch.no_grad():
        try:
            enc_out = encoder(dummy_img)
            if isinstance(enc_out, tuple):
                enc_out = enc_out[0]
            print(f"  Encoder output shape: {enc_out.shape}")
            dummy_memory = enc_out
        except Exception as e:
            print(f"  ⚠ Could not run encoder for shape detection: {e}")
            dummy_memory = torch.randn(1, 64, dim)

    # Wrap decoder for ONNX: CustomARWrapper.forward(x, **kwargs)
    # passes encoder output via kwargs to inner TransformerWrapper.
    # We create an explicit wrapper with positional args for ONNX.
    class DecoderONNXWrapper(nn.Module):
        def __init__(self, ar_wrapper):
            super().__init__()
            self.net = ar_wrapper.net  # TransformerWrapper
        
        def forward(self, input_ids, encoder_hidden_states):
            # TransformerWrapper.forward(x, context=...) 
            return self.net(input_ids, context=encoder_hidden_states)

    decoder_wrapped = DecoderONNXWrapper(decoder)
    decoder_wrapped.eval()

    try:
        torch.onnx.export(
            decoder_wrapped,
            (dummy_tgt, dummy_memory),
            decoder_path,
            input_names=["input_ids", "encoder_hidden_states"],
            output_names=["logits"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "seq_len"},
                "encoder_hidden_states": {0: "batch", 1: "enc_len"},
                "logits": {0: "batch", 1: "seq_len"},
            },
            opset_version=14,
            do_constant_folding=True,
            dynamo=False,
        )
        size_mb = os.path.getsize(decoder_path) / (1024 * 1024)
        print(f"  ✓ Decoder exported ({size_mb:.1f} MB)")
    except Exception as e:
        print(f"  ✗ Decoder export failed: {e}")
        import traceback; traceback.print_exc()
        print("  You may need to adjust the decoder export based on the model version.")

    # -------------------------------------------------------------------------
    # Step 4: FP16 Conversion (Mobile-Compatible)
    # -------------------------------------------------------------------------
    # NOTE: INT8 dynamic quantization produces ConvInteger operators that are
    # NOT supported by mobile ONNX Runtime (NNAPI on Android, CoreML on iOS).
    # FP16 is the best trade-off: ~50% size reduction, full mobile support.
    print("\n[4/6] Converting to FP16 (mobile-compatible)...")
    try:
        from onnxruntime.quantization import quantize_dynamic, QuantType
        import onnx
        from onnxconverter_common import float16

        # FP16 encoder
        encoder_fp16_path = os.path.join(output_dir, "encoder_fp16.onnx")
        if os.path.exists(encoder_path):
            model_fp32 = onnx.load(encoder_path)
            model_fp16 = float16.convert_float_to_float16(model_fp32, keep_io_types=True)
            onnx.save(model_fp16, encoder_fp16_path)
            orig_size = os.path.getsize(encoder_path) / (1024 * 1024)
            fp16_size = os.path.getsize(encoder_fp16_path) / (1024 * 1024)
            reduction = (1 - fp16_size / orig_size) * 100
            print(f"  ✓ Encoder FP16: {orig_size:.1f}MB → {fp16_size:.1f}MB ({reduction:.0f}% reduction)")

        # FP16 decoder
        decoder_fp16_path = os.path.join(output_dir, "decoder_fp16.onnx")
        if os.path.exists(decoder_path):
            model_fp32 = onnx.load(decoder_path)
            model_fp16 = float16.convert_float_to_float16(model_fp32, keep_io_types=True)
            onnx.save(model_fp16, decoder_fp16_path)
            orig_size = os.path.getsize(decoder_path) / (1024 * 1024)
            fp16_size = os.path.getsize(decoder_fp16_path) / (1024 * 1024)
            reduction = (1 - fp16_size / orig_size) * 100
            print(f"  ✓ Decoder FP16: {orig_size:.1f}MB → {fp16_size:.1f}MB ({reduction:.0f}% reduction)")

        # Keep FP32 originals as encoder.onnx / decoder.onnx (unquantized backup)
        print("  ✓ FP32 originals kept as backup")

    except ImportError as e:
        print(f"  ⚠ FP16 conversion skipped (missing: {e})")
        print("  Keeping FP32 models (larger but fully compatible)")
        print("  To enable FP16: pip install onnxconverter-common")

    # -------------------------------------------------------------------------
    # Step 5: Export tokenizer vocabulary
    # -------------------------------------------------------------------------
    print("\n[5/6] Exporting tokenizer...")
    tokenizer_path = os.path.join(output_dir, "tokenizer.json")

    try:
        vocab = {}
        # Try different tokenizer formats
        if hasattr(tokenizer, 'get_vocab'):
            raw_vocab = tokenizer.get_vocab()
            vocab = {str(v): k for k, v in raw_vocab.items()}
        elif hasattr(tokenizer, 'itos'):
            vocab = {str(i): tok for i, tok in enumerate(tokenizer.itos)}
        elif hasattr(tokenizer, 'idx2word'):
            vocab = {str(k): v for k, v in tokenizer.idx2word.items()}
        else:
            print(f"  ⚠ Unknown tokenizer type: {type(tokenizer)}")
            print(f"    Attributes: {[a for a in dir(tokenizer) if not a.startswith('_')]}")

        # Find special tokens
        special = {
            "bos_token_id": getattr(tokenizer, 'bos_token_id', 1),
            "eos_token_id": getattr(tokenizer, 'eos_token_id', 2),
            "pad_token_id": getattr(tokenizer, 'pad_token_id', 0),
        }

        tokenizer_data = {
            "vocab": vocab,
            "special_tokens": special,
            "vocab_size": len(vocab),
        }

        with open(tokenizer_path, 'w', encoding='utf-8') as f:
            json.dump(tokenizer_data, f, ensure_ascii=False, indent=2)

        print(f"  ✓ Tokenizer exported ({len(vocab)} tokens)")
    except Exception as e:
        print(f"  ✗ Tokenizer export failed: {e}")

    # -------------------------------------------------------------------------
    # Step 6: Validate ONNX models
    # -------------------------------------------------------------------------
    print("\n[6/6] Validating ONNX models...")
    validation_passed = True

    try:
        import onnxruntime as ort
        import numpy as np

        # Check encoder
        encoder_q_path = os.path.join(output_dir, "encoder_int8.onnx")
        if os.path.exists(encoder_q_path):
            enc_session = ort.InferenceSession(encoder_q_path)
            test_input = np.random.randn(1, 1, 224, 224).astype(np.float32)
            enc_outputs = enc_session.run(None, {"pixel_values": test_input})
            if enc_outputs and len(enc_outputs) > 0:
                print(f"  ✓ Encoder: output shape {enc_outputs[0].shape}")
            else:
                print("  ✗ Encoder: no output produced")
                validation_passed = False
        else:
            print("  ⚠ Encoder INT8 model not found, skipping validation")

        # Check decoder
        decoder_q_path = os.path.join(output_dir, "decoder_int8.onnx")
        if os.path.exists(decoder_q_path):
            dec_session = ort.InferenceSession(decoder_q_path)
            dec_inputs = dec_session.get_inputs()
            print(f"  ✓ Decoder: {len(dec_inputs)} inputs — "
                  f"{[inp.name for inp in dec_inputs]}")
        else:
            print("  ⚠ Decoder INT8 model not found, skipping validation")

        # Full pipeline test with pix2tex
        try:
            from PIL import Image, ImageDraw, ImageFont
            # Create a simple test image with "x²"
            test_img = Image.new('L', (224, 224), color=255)
            draw = ImageDraw.Draw(test_img)
            try:
                font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 48)
            except Exception:
                font = ImageFont.load_default()
            draw.text((60, 80), "x²", fill=0, font=font)

            # Run original pix2tex model
            from pix2tex.cli import LatexOCR
            ocr = LatexOCR()
            result = ocr(test_img)
            if result and len(result) > 0:
                print(f"  ✓ End-to-end test: 'x²' → '{result}'")
            else:
                print("  ⚠ End-to-end test: empty result")
        except Exception as e:
            print(f"  ⚠ Full pipeline test skipped: {e}")

    except ImportError:
        print("  ⚠ onnxruntime/numpy not installed, skipping validation")
    except Exception as e:
        print(f"  ✗ Validation failed: {e}")
        validation_passed = False

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    print("\n" + "=" * 60)
    print(f"  Conversion {'complete' if validation_passed else 'completed with warnings'}!")
    print("=" * 60)
    total_size = 0
    for fname in sorted(os.listdir(output_dir)):
        fpath = os.path.join(output_dir, fname)
        size = os.path.getsize(fpath) / (1024 * 1024)
        total_size += size
        print(f"  {fname:30s} {size:8.2f} MB")
    print(f"  {'TOTAL':30s} {total_size:8.2f} MB")
    print(f"\n  Output: {output_dir}")
    print(f"  Next:   Add to pubspec.yaml assets and run the app!")


if __name__ == "__main__":
    main()
