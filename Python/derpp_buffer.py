from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Tuple

import numpy as np
import torch
import torch.nn.functional as F


@dataclass
class DERPlusPlusBuffer:
    capacity: int = 500
    alpha: float = 0.5
    beta: float = 0.5
    buffer: List[Tuple[np.ndarray, int, np.ndarray]] = field(default_factory=list)

    def add(self, x: np.ndarray, y: int, logits: np.ndarray) -> None:
        if len(self.buffer) >= self.capacity:
            self.buffer.pop(0)
        self.buffer.append((x.copy(), int(y), logits.copy()))

    def sample(self, batch_size: int) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        batch_size = min(batch_size, len(self.buffer))
        indices = np.random.choice(len(self.buffer), size=batch_size, replace=False)
        xs, ys, logits = zip(*(self.buffer[i] for i in indices))
        return np.stack(xs), np.asarray(ys, dtype=np.int64), np.stack(logits)

    def compute_derpp_loss(self, model, new_x, new_y, criterion, device: str):
        new_x_t = torch.tensor(new_x, dtype=torch.float32, device=device)
        new_y_t = torch.tensor(new_y, dtype=torch.long, device=device)
        logits_new = model(new_x_t)
        loss_ce = criterion(logits_new, new_y_t).mean()
        if len(self.buffer) < 16:
            return loss_ce

        buf_x, buf_y, buf_logits = self.sample(64)
        buf_x_t = torch.tensor(buf_x, dtype=torch.float32, device=device)
        buf_y_t = torch.tensor(buf_y, dtype=torch.long, device=device)
        buf_logits_t = torch.tensor(buf_logits, dtype=torch.float32, device=device)
        logits_replay = model(buf_x_t)
        loss_mse = F.mse_loss(logits_replay, buf_logits_t) * self.alpha
        loss_label = criterion(logits_replay, buf_y_t).mean() * self.beta
        return loss_ce + loss_mse + loss_label
