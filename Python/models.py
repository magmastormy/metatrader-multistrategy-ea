import torch
import torch.nn as nn

N_FEATURES = 57
N_CLASSES = 3


class SequenceMLP(nn.Module):
    """
    Export-safe baseline model for MT5 ONNX runtime.
    Input:  (B, seq_len, N_FEATURES)
    Output: (B, N_CLASSES) raw logits
    """
    def __init__(self, seq_len=60, n_features=N_FEATURES,
                 hidden1=256, hidden2=128, dropout=0.10,
                 n_classes=N_CLASSES):
        super().__init__()
        in_features = seq_len * n_features
        self.net = nn.Sequential(
            nn.Flatten(),
            nn.LayerNorm(in_features),
            nn.Linear(in_features, hidden1),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden1, hidden2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden2, n_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


class PatchTST(nn.Module):
    """
    PatchTST for financial time series.
    Input:  (B, seq_len, N_FEATURES)
    Output: (B, N_CLASSES) raw logits
    """
    def __init__(self, seq_len=60, n_features=N_FEATURES,
                 patch_len=12, stride=6,
                 d_model=128, n_heads=8, n_layers=3,
                 dropout=0.1, n_classes=N_CLASSES):
        super().__init__()
        self.patch_len = patch_len
        self.stride = stride
        self.n_patches = (seq_len - patch_len) // stride + 1

        self.patch_embed = nn.Linear(patch_len, d_model)
        self.cls_token = nn.Parameter(torch.zeros(1, n_features, 1, d_model))
        self.pos_embed = nn.Parameter(torch.zeros(1, n_features, self.n_patches + 1, d_model))
        nn.init.trunc_normal_(self.cls_token, std=0.02)
        nn.init.trunc_normal_(self.pos_embed, std=0.02)

        enc_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=dropout, norm_first=True,
            batch_first=True
        )
        self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Linear(n_features * d_model, n_classes)
        self.drop = nn.Dropout(dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        batch_size, seq_len, n_features = x.shape
        x = x.permute(0, 2, 1)
        patches = x.unfold(-1, self.patch_len, self.stride)
        patches = self.patch_embed(patches)
        cls = self.cls_token.expand(batch_size, -1, -1, -1)
        patches = torch.cat([cls, patches], dim=2) + self.pos_embed
        b2, f2, n_patch, d_model = patches.shape
        patches = self.transformer(patches.reshape(b2 * f2, n_patch, d_model))
        patches = patches.reshape(b2, f2, n_patch, d_model)
        out = self.norm(patches[:, :, 0, :]).reshape(batch_size, -1)
        return self.head(self.drop(out))


class iTransformer(nn.Module):
    """
    iTransformer: attention over feature channels, not time steps.
    Input:  (B, seq_len, N_FEATURES)
    Output: (B, N_CLASSES) raw logits
    """
    def __init__(self, seq_len=60, n_features=N_FEATURES,
                 d_model=128, n_heads=8, n_layers=3,
                 dropout=0.1, n_classes=N_CLASSES):
        super().__init__()
        self.feat_embed = nn.Linear(seq_len, d_model)
        enc_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4,
            dropout=dropout, norm_first=True,
            batch_first=True
        )
        self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, n_classes)
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x.permute(0, 2, 1)
        x = self.feat_embed(x)
        x = self.transformer(x)
        x = self.norm(x).mean(dim=1)
        return self.head(x)
