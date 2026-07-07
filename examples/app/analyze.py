"""Sample workload that proves third-party deps are available in the sandbox."""
import platform

import pandas as pd

df = pd.DataFrame({"n": [1, 2, 3, 4, 5]})

print(f"python {platform.python_version()} on {platform.machine()}")
print(f"pandas {pd.__version__}")
print(f"sum(n)  = {int(df['n'].sum())}")
print(f"mean(n) = {df['n'].mean()}")
