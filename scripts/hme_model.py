"""
🧮 Handwritten Math Expression Recognition Model (CRNN + CTC)

Architecture:
  CNN Encoder (ResNet-18 backbone) → BiLSTM (2 layers) → Linear → CTC

Designed for clean ONNX export — no attention, no dynamic ops.
"""

import torch
import torch.nn as nn
import torchvision.models as models


class HMEEncoder(nn.Module):
    """CNN feature extractor based on ResNet-18.
    
    Takes grayscale images [B, 1, H, W] and produces feature sequences
    [B, T, C] where T = W // 32 (temporal steps for CTC).
    """
    
    def __init__(self, output_channels: int = 512):
        super().__init__()
        
        # Use ResNet-18 backbone (pretrained on ImageNet)
        resnet = models.resnet18(weights=models.ResNet18_Weights.DEFAULT)
        
        # Modify first conv to accept 1 channel (grayscale) instead of 3
        self.conv1 = nn.Conv2d(1, 64, kernel_size=7, stride=2, padding=3, bias=False)
        # Initialize from pretrained: average the 3-channel weights
        with torch.no_grad():
            self.conv1.weight.copy_(resnet.conv1.weight.mean(dim=1, keepdim=True))
        
        self.bn1 = resnet.bn1
        self.relu = resnet.relu
        self.maxpool = resnet.maxpool
        
        # ResNet layers (stride 2 each → total /32 height, /32 width)
        self.layer1 = resnet.layer1  # /4 → /4
        self.layer2 = resnet.layer2  # /4 → /8
        self.layer3 = resnet.layer3  # /8 → /16
        self.layer4 = resnet.layer4  # /16 → /32
        
        # Adaptive pooling to collapse height to 1
        self.adaptive_pool = nn.AdaptiveAvgPool2d((1, None))
        
        self.output_channels = output_channels
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: [B, 1, H, W] grayscale image
        Returns:
            features: [B, T, 512] sequence of feature vectors
        """
        # CNN feature extraction
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)  # [B, 512, H/32, W/32]
        
        # Collapse height dimension
        x = self.adaptive_pool(x)  # [B, 512, 1, W/32]
        x = x.squeeze(2)           # [B, 512, W/32]
        x = x.permute(0, 2, 1)     # [B, T, 512] where T = W/32
        
        return x


class HMEModel(nn.Module):
    """Full CRNN model: CNN encoder + BiLSTM + CTC head.
    
    Input:  [B, 1, 128, 512] grayscale image
    Output: [T, B, vocab_size] log-probabilities for CTC
    """
    
    def __init__(self, vocab_size: int, hidden_size: int = 256,
                 num_lstm_layers: int = 2, dropout: float = 0.3):
        super().__init__()
        
        self.encoder = HMEEncoder(output_channels=512)
        
        self.lstm = nn.LSTM(
            input_size=512,
            hidden_size=hidden_size,
            num_layers=num_lstm_layers,
            bidirectional=True,
            dropout=dropout if num_lstm_layers > 1 else 0,
            batch_first=True,
        )
        
        # BiLSTM output is 2 * hidden_size
        self.fc = nn.Linear(hidden_size * 2, vocab_size)
        self.log_softmax = nn.LogSoftmax(dim=2)
        
        self.vocab_size = vocab_size
        self.hidden_size = hidden_size
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: [B, 1, 128, 512] grayscale image (black ink on white bg)
        Returns:
            log_probs: [T, B, vocab_size] for CTC loss
        """
        # CNN features: [B, T, 512]
        features = self.encoder(x)
        
        # BiLSTM: [B, T, hidden*2]
        lstm_out, _ = self.lstm(features)
        
        # Project to vocabulary: [B, T, vocab_size]
        logits = self.fc(lstm_out)
        
        # Log-softmax for CTC: [T, B, vocab_size]
        log_probs = self.log_softmax(logits)
        log_probs = log_probs.permute(1, 0, 2)  # CTC expects [T, B, C]
        
        return log_probs
    
    def inference(self, x: torch.Tensor) -> torch.Tensor:
        """Run inference and return raw logits [B, T, vocab_size].
        
        This is the method exported to ONNX — CTC decoding happens
        in Dart/native code.
        """
        features = self.encoder(x)
        lstm_out, _ = self.lstm(features)
        logits = self.fc(lstm_out)  # [B, T, vocab_size]
        return logits


class HMEInferenceWrapper(nn.Module):
    """Thin wrapper for ONNX export — returns logits [B, T, vocab_size]."""
    
    def __init__(self, model: HMEModel):
        super().__init__()
        self.model = model
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.model.inference(x)


# ─── Vocabulary Builder ──────────────────────────────────────────────────────

# Standard LaTeX math tokens for handwritten recognition
DEFAULT_VOCAB = [
    '<blank>',  # CTC blank token (index 0)
    # Digits
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    # Latin letters (lowercase)
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    # Latin letters (uppercase)
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    # Greek letters
    '\\alpha', '\\beta', '\\gamma', '\\delta', '\\epsilon', '\\theta',
    '\\lambda', '\\mu', '\\pi', '\\sigma', '\\phi', '\\omega',
    '\\Delta', '\\Sigma', '\\Phi', '\\Omega',
    # Operators
    '+', '-', '=', '\\times', '\\div', '\\pm', '\\cdot',
    '<', '>', '\\leq', '\\geq', '\\neq', '\\approx',
    # Grouping & structure
    '(', ')', '[', ']', '{', '}', '|',
    '^', '_',  # superscript, subscript
    '\\frac', '\\sqrt',
    # Functions
    '\\sin', '\\cos', '\\tan', '\\log', '\\ln', '\\lim',
    '\\sum', '\\prod', '\\int',
    '\\infty', '\\partial',
    # Punctuation
    ',', '.', '!', '\\ldots',
    # Spacing
    ' ',
    # Special
    '\\rightarrow', '\\leftarrow',
    '\\forall', '\\exists', '\\in', '\\cup', '\\cap',
]


def build_vocab(extra_tokens=None):
    """Build token-to-index and index-to-token mappings."""
    tokens = list(DEFAULT_VOCAB)
    if extra_tokens:
        for t in extra_tokens:
            if t not in tokens:
                tokens.append(t)
    
    token2idx = {t: i for i, t in enumerate(tokens)}
    idx2token = {i: t for i, t in enumerate(tokens)}
    
    return token2idx, idx2token, len(tokens)


if __name__ == '__main__':
    # Quick sanity check
    token2idx, idx2token, vocab_size = build_vocab()
    print(f"Vocabulary size: {vocab_size}")
    
    model = HMEModel(vocab_size=vocab_size)
    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")
    
    # Test forward pass
    dummy = torch.randn(1, 1, 128, 512)
    log_probs = model(dummy)
    print(f"Input shape:  {dummy.shape}")
    print(f"Output shape: {log_probs.shape}")  # [T, B, vocab_size]
    print(f"T (time steps): {log_probs.shape[0]}")
    
    # Test ONNX export
    wrapper = HMEInferenceWrapper(model)
    wrapper.eval()
    logits = wrapper(dummy)
    print(f"Inference logits: {logits.shape}")  # [B, T, vocab_size]
