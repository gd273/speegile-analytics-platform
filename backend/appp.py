import pandas as pd

# Simulate a date that's in your file
test_dates = ["15-03-2026", "03-05-2026", "01-04-2026"]
df_test = pd.DataFrame({"BillDate": test_dates})

print("=== WITHOUT dayfirst (production behaviour) ===")
result_old = pd.to_datetime(df_test['BillDate'], errors='coerce')
print(result_old)
print("NaT count:", result_old.isna().sum())

print("\n=== WITH dayfirst=True (local/fix behaviour) ===")
result_new = pd.to_datetime(df_test['BillDate'], dayfirst=True, errors='coerce')
print(result_new)
print("NaT count:", result_new.isna().sum())