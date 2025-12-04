"""Train lightweight transformer model for trading"""
import numpy as np
import pickle
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from torch.utils.data import TensorDataset, DataLoader
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    logger.error("PyTorch not available - install with: pip install torch")


class LightweightTransformer(nn.Module):
    """Lightweight transformer for trading"""
    
    def __init__(self, input_dim=20, d_model=64, nhead=4, num_layers=3):
        super().__init__()
        self.input_dim = input_dim
        self.d_model = d_model
        
        self.input_projection = nn.Linear(input_dim, d_model)
        self.positional_encoding = nn.Parameter(torch.randn(500, d_model) * 0.02)
        
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=nhead,
            dim_feedforward=d_model * 2,
            dropout=0.1,
            batch_first=True
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        
        # Output head for regression
        self.output_head = nn.Sequential(
            nn.Linear(d_model, 32),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(32, 1),
            nn.Tanh()  # Output in [-1, 1]
        )
        
    def forward(self, x):
        # x shape: (batch, input_dim) or (batch, seq_len, input_dim)
        if len(x.shape) == 2:
            x = x.unsqueeze(1)  # Add sequence dimension
        
        batch_size, seq_len, _ = x.shape
        
        x = self.input_projection(x)
        x = x + self.positional_encoding[:seq_len, :].unsqueeze(0)
        
        x = self.transformer(x)
        x = x[:, -1, :]  # Take last token
        
        output = self.output_head(x)
        
        return output


def generate_training_data(n_samples=10000):
    """Generate synthetic training data"""
    logger.info(f"Generating {n_samples} training samples...")
    
    # Generate features
    features = np.random.randn(n_samples, 20).astype(np.float32)
    
    # Generate continuous labels
    momentum = features[:, 1]
    trend = features[:, 4]
    volatility = features[:, 2]
    
    # Target: continuous signal in [-1, 1]
    labels = np.tanh(momentum * 3 + trend * 2 - volatility).astype(np.float32)
    
    return features, labels


def train_transformer_model(model, train_loader, val_loader, epochs=100):
    """Train transformer model"""
    logger.info("Training Transformer model...")
    
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    logger.info(f"Using device: {device}")
    
    model = model.to(device)
    
    criterion = nn.MSELoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=5)
    
    best_val_loss = float('inf')
    patience_counter = 0
    patience = 10
    
    for epoch in range(epochs):
        # Training
        model.train()
        train_loss = 0.0
        
        for batch_x, batch_y in train_loader:
            batch_x, batch_y = batch_x.to(device), batch_y.to(device)
            
            optimizer.zero_grad()
            outputs = model(batch_x)
            loss = criterion(outputs.squeeze(), batch_y)
            loss.backward()
            optimizer.step()
            
            train_loss += loss.item()
        
        train_loss /= len(train_loader)
        
        # Validation
        model.eval()
        val_loss = 0.0
        
        with torch.no_grad():
            for batch_x, batch_y in val_loader:
                batch_x, batch_y = batch_x.to(device), batch_y.to(device)
                outputs = model(batch_x)
                loss = criterion(outputs.squeeze(), batch_y)
                val_loss += loss.item()
        
        val_loss /= len(val_loader)
        
        # Learning rate scheduling
        scheduler.step(val_loss)
        
        # Logging
        if (epoch + 1) % 10 == 0:
            logger.info(f"Epoch {epoch+1}/{epochs} - Train Loss: {train_loss:.6f}, Val Loss: {val_loss:.6f}")
        
        # Early stopping
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            patience_counter = 0
        else:
            patience_counter += 1
            if patience_counter >= patience:
                logger.info(f"Early stopping at epoch {epoch+1}")
                break
    
    return model


def evaluate_model(model, test_loader):
    """Evaluate model performance"""
    logger.info("Evaluating model...")
    
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model = model.to(device)
    model.eval()
    
    all_preds = []
    all_labels = []
    
    with torch.no_grad():
        for batch_x, batch_y in test_loader:
            batch_x = batch_x.to(device)
            outputs = model(batch_x)
            all_preds.extend(outputs.squeeze().cpu().numpy())
            all_labels.extend(batch_y.numpy())
    
    all_preds = np.array(all_preds)
    all_labels = np.array(all_labels)
    
    # Calculate metrics
    mse = np.mean((all_preds - all_labels) ** 2)
    mae = np.mean(np.abs(all_preds - all_labels))
    correlation = np.corrcoef(all_preds, all_labels)[0, 1]
    
    logger.info(f"MSE: {mse:.6f}")
    logger.info(f"MAE: {mae:.6f}")
    logger.info(f"Correlation: {correlation:.6f}")
    
    return {'mse': mse, 'mae': mae, 'correlation': correlation}


def main():
    """Main training function"""
    if not TORCH_AVAILABLE:
        logger.error("PyTorch not available")
        return
    
    logger.info("="*60)
    logger.info("Transformer Model Training")
    logger.info("="*60)
    
    # Generate data
    X, y = generate_training_data(n_samples=10000)
    
    # Split data
    from sklearn.model_selection import train_test_split
    X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.3, random_state=42)
    X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.5, random_state=42)
    
    # Create DataLoaders
    train_dataset = TensorDataset(torch.FloatTensor(X_train), torch.FloatTensor(y_train))
    val_dataset = TensorDataset(torch.FloatTensor(X_val), torch.FloatTensor(y_val))
    test_dataset = TensorDataset(torch.FloatTensor(X_test), torch.FloatTensor(y_test))
    
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=32)
    test_loader = DataLoader(test_dataset, batch_size=32)
    
    logger.info(f"Train size: {len(X_train)}")
    logger.info(f"Val size: {len(X_val)}")
    logger.info(f"Test size: {len(X_test)}")
    
    # Create model
    model = LightweightTransformer(input_dim=20, d_model=64, nhead=4, num_layers=3)
    
    # Train
    model = train_transformer_model(model, train_loader, val_loader, epochs=100)
    
    # Evaluate
    metrics = evaluate_model(model, test_loader)
    
    # Save model
    model_dir = Path("../")
    model_dir.mkdir(exist_ok=True)
    
    model_path = model_dir / "transformer_small.pt"
    torch.save(model.state_dict(), model_path)
    
    logger.info(f"✅ Model saved to {model_path.absolute()}")
    logger.info("="*60)


if __name__ == "__main__":
    main()
