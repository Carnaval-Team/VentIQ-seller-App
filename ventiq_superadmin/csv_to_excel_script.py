import pandas as pd

# Load the CSV
csv_file = "C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_superadmin/Supabase Snippet Count Products Sold Since Date.csv"
excel_file = "C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_superadmin/Reporte_Productos_Vendidos.xlsx"

try:
    # Read CSV
    df = pd.read_csv(csv_file)
    
    # Save to Excel
    df.to_excel(excel_file, index=False, engine='openpyxl')
    print(f"Successfully converted {csv_file} to {excel_file}")

except Exception as e:
    print(f"Error: {e}")
