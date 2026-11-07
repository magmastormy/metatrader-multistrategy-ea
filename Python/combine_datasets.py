import pandas as pd
from pathlib import Path
import sys

def combine_csvs(file_paths, output_path):
    all_dfs = []
    print(f"Combining {len(file_paths)} files...")
    
    for p in file_paths:
        path = Path(p)
        if not path.exists():
            print(f"Warning: {p} not found skipping.")
            continue
            
        print(f"Loading {path.name}...")
        df = pd.read_csv(path)
        # Ensure date is datetime
        df['date'] = pd.to_datetime(df['date'])
        all_dfs.append(df)
    
    if not all_dfs:
        print("No data to combine.")
        return
        
    combined = pd.concat(all_dfs, ignore_index=True)
    
    # Sort by symbol and date
    combined = combined.sort_values(['symbol', 'date'])
    
    # Remove duplicates
    initial_len = len(combined)
    combined = combined.drop_duplicates(subset=['symbol', 'date'])
    removed = initial_len - len(combined)
    
    print(f"Combined dataset size: {len(combined)} rows ({removed} duplicates removed).")
    
    combined.to_csv(output_path, index=False)
    print(f"Saved to {output_path}")

if __name__ == "__main__":
    inputs = [
        "Python/data/AITraining_OHLCV_M15.csv",
        "Python/data/AITraining_OHLCV_M30.csv",
        "Python/data/AITraining_OHLCV_H1.csv"
    ]
    output = "Python/data/UNIVERSAL_TRAINING_SET.csv"
    combine_csvs(inputs, output)
