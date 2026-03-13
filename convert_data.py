import sqlite3
import pandas as pd
import os

def convert_excel_to_sqlite(excel_path, db_path):
    print(f"Reading {excel_path}...")
    # Load with pandas for easier manipulation
    df = pd.read_excel(excel_path)
    
    # Clean column names (remove spaces)
    df.columns = [c.strip() for c in df.columns]
    
    # Fill NaN with empty strings to avoid issues in Tkinter
    df = df.fillna("")
    
    print(f"Connecting to {db_path}...")
    conn = sqlite3.connect(db_path)
    
    print("Writing to database...")
    df.to_sql("lawyers", conn, if_exists="replace", index=False)
    
    # Create indexes for fast searching
    cursor = conn.cursor()
    cursor.execute("CREATE INDEX idx_name ON lawyers (FullName)")
    cursor.execute("CREATE INDEX idx_city ON lawyers (City)")
    cursor.execute("CREATE INDEX idx_membership ON lawyers (Membership)")
    
    conn.commit()
    conn.close()
    print("Optimization complete!")

if __name__ == "__main__":
    EXCEL_FILE = r"دليل المحامين ارقام كامل .xlsx"
    DB_FILE = "lawyers.db"
    if os.path.exists(EXCEL_FILE):
        convert_excel_to_sqlite(EXCEL_FILE, DB_FILE)
    else:
        print(f"Error: {EXCEL_FILE} not found.")
