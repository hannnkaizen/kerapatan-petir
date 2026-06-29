import os
import sys

# === ADD THESE LINES BEFORE IMPORTING PYGMT ===
# Adjust this path if your GMT installation is in another folder (e.g., C:\Program Files\GMT6\bin)
os.environ["GMT_LIBRARY_PATH"] = r"C:\Program Files\gmt6\bin" 
os.environ["PATH"] = r"C:\Program Files\gmt6\bin;" + os.environ["PATH"]

import pygmt
import sqlite3
import pandas as pd
import glob
from datetime import datetime

# =============================================================================
# Configuration Global
# =============================================================================
BASE_DIR = rf"D:\TITIPAN_KITA\RAIHAN\Git\kerapatan-petir"
#DB3_DIR = rf"D:\TITIPAN_KITA\RAIHAN\Kerapatan_Petir\Input Example"
DB3_DIR = rf"\\172.25.106.14\c\Data DB3"

ASSET_FILE = os.path.join(BASE_DIR, 'Assets/batas_jumlah_kerapatan_petir_assets.csv')
SHP_FOLDER = os.path.join(BASE_DIR, "SHP_File")
DATE_INPUT_FILE = os.path.join(BASE_DIR, "date_temp.csv")
DATE_OUTPUT_TXT = os.path.join(BASE_DIR, "date_temp.txt")

def process_daily_data(date_str):
    print(f"\n{'='*40}")
    print(f"Mulai: {date_str}")
    print(f"{'='*40}")

    # Setup lokasi file
    tempat_db3 = os.path.join(DB3_DIR, f"NGXDS_{date_str}.db3")
    csv_tekonversi = os.path.join(BASE_DIR, f"{date_str}_converted2csv_temp_1.csv")
    csv_digabung = os.path.join(BASE_DIR, f"{date_str}_Clipped_Merged_Regions_temp_2.csv")
    file_hasil = os.path.join(BASE_DIR, f"{date_str}_Lightning_Analysis_Result_temp_3.csv")
    
    # Return value default jika error (None)
    if not os.path.exists(tempat_db3):
        print(f"SKIPPING: DB3 file not found: {tempat_db3}")
        return None

    # -------------------------------------------------------------------------
    # I. Konversi DB3 ke CSV
    # -------------------------------------------------------------------------
    print(f"--- Langkah 1: Konversi DB3 ke CSV ---")
    try:
        conn = sqlite3.connect(tempat_db3)
        table_list = pd.read_sql_query("SELECT name FROM sqlite_master WHERE type='table';", conn)
        
        if not table_list.empty:
            target_table = table_list.iloc[0]['name']
            dfconv = pd.read_sql_query(f"SELECT * FROM {target_table}", conn)
            subset_df = dfconv.iloc[:, 2:6]
            subset_df.to_csv(csv_tekonversi, index=False)
            print(f"  Extracted table '{target_table}' to {csv_tekonversi}")
        else:
            print("  The database file is empty.")
            conn.close()
            return None
        conn.close()
    except Exception as e:
        print(f"  Error in Step 1: {e}")
        return None

    # -------------------------------------------------------------------------
    # II. Clip SHP Kecamatan
    # -------------------------------------------------------------------------
    print(f"--- Langkah 2: Clipping berdasarkan kecamatan ---")
    if not os.path.exists(csv_tekonversi):
        return None

    try:
        # FIXED: Read as string and use Row_ID bypass so PyGMT doesn't crash on dates
        df_original = pd.read_csv(csv_tekonversi, dtype={'datetime_utc': str})
        df_for_gmt = df_original[['longitude', 'latitude']].copy()
        df_for_gmt['Row_ID'] = df_original.index 
    except Exception as e:
        print(f"  Error membaca CSV: {e}")
        return None

    shp_files = glob.glob(os.path.join(SHP_FOLDER, "*.shp"))
    if not shp_files:
        print(f"  Tidak ada file .shp di {SHP_FOLDER}")
        return None

    semua_data_clip = []
    for shp_path in shp_files:
        shp_name = os.path.splitext(os.path.basename(shp_path))[0]
        try:
            # PyGMT only gets numbers now
            clipped_gmt = pygmt.select(data=df_for_gmt, polygon=shp_path)
            if not clipped_gmt.empty:
                # Pull original data including untouched datetime
                valid_indices = clipped_gmt.iloc[:, 2].astype(int)
                clipped_original = df_original.loc[valid_indices].copy()
                clipped_original["region"] = shp_name
                semua_data_clip.append(clipped_original)
        except Exception as e:
            pass

    if semua_data_clip:
        final_gabung = pd.concat(semua_data_clip, ignore_index=True)
        final_gabung = final_gabung[["datetime_utc", "latitude", "longitude", "type", "region"]]
        final_gabung.to_csv(csv_digabung, index=False)
    else:
        print("  Tidak ada kejadian dalam region.")
        return None

    # -------------------------------------------------------------------------
    # III. Analisis Harian (Ensuring All Kecamatan are Included)
    # -------------------------------------------------------------------------
    print(f"--- Langkah 3: Analisis Harian ---")

    try:
        # 1. Load the Target Data (Lightning strikes)
        if not os.path.exists(csv_digabung):
            print(f"  Target data file missing: {csv_digabung}")
            return None
            
        df_target = pd.read_csv(csv_digabung)
        df_target['type'] = pd.to_numeric(df_target['type'], errors='coerce')
        
        # 2. Handle missing ASSET_FILE scenario
        if not os.path.exists(ASSET_FILE):
            print(f"  Asset file missing. Filling output based on lightning regions with 'Safe'.")
            all_regions = df_target['region'].unique()
            df_final = pd.DataFrame({
                'region': all_regions,
                'CG-': [None] * len(all_regions),
                'CG+': [None] * len(all_regions),
                'Total': [None] * len(all_regions),
                'Category': 'Safe'
            })
            df_final.to_csv(file_hasil, index=False)
            return df_final

        # 3. Load Asset File as the Master List of Kecamatan
        df_assets = pd.read_csv(ASSET_FILE, delimiter=';')
        
        # 4. Count lightning per region from the target data
        def count_lightning_types(x):
            return pd.Series({
                'CG-': (x['type'] == 1).sum(),
                'CG+': (x['type'] == 0).sum(),
                'Total': (x['type'] == 1).sum() + (x['type'] == 0).sum()
            })
        df_counts = df_target.groupby('region').apply(count_lightning_types, include_groups=False).reset_index()

        # 5. Merge starting from df_assets (LEFT JOIN) to keep all Kecamatan
        # This ensures regions with 0 strikes are included
        df_merged = pd.merge(
            df_assets[['Kecamatan', 'Rendah-Sedang', 'Sedang-Tinggi']], 
            df_counts,
            left_on='Kecamatan', 
            right_on='region', 
            how='left'
        )

        # 6. Fill missing values for regions with 0 strikes
        df_merged['region'] = df_merged['region'].fillna(df_merged['Kecamatan'])
        df_merged['CG-'] = df_merged['CG-'].fillna(0).astype(int)
        df_merged['CG+'] = df_merged['CG+'].fillna(0).astype(int)
        df_merged['Total'] = df_merged['Total'].fillna(0).astype(int)

        def classify_density(row):
            total_val = row['Total']
            limit_low_med = row['Rendah-Sedang']
            limit_med_high = row['Sedang-Tinggi']
            
            if pd.isna(limit_low_med) or pd.isna(limit_med_high):
                return 'Undefined'
            
            # If there is no lightning data at all, you might want "Safe"
            if total_val == 0:
                return 'Safe'
                
            if total_val < limit_low_med:
                return 'Rendah'
            elif total_val < limit_med_high:
                return 'Sedang'
            else:
                return 'Tinggi'

        df_merged['Category'] = df_merged.apply(classify_density, axis=1)

        # 7. Final Formatting
        desired_columns = ['region', 'CG-', 'CG+', 'Total', 'Category']
        df_final = df_merged[desired_columns]
        df_for_accumulation = df_final.copy()

        # --- Output Harian with Summary ---
        '''summary_row = pd.DataFrame([{
            'region': 'TOTAL_HARI_INI',
            'CG-': df_final['CG-'].sum(),
            'CG+': df_final['CG+'].sum(),
            'Total': df_final['Total'].sum(),
            'Category': ''
        }])'''
        
        #df_final_with_summary = pd.concat([df_final, summary_row], ignore_index=True)
        df_final_with_summary = pd.concat([df_final], ignore_index=True)
        df_final_with_summary.to_csv(file_hasil, index=False)
        print(f"  Output Harian disimpan: {file_hasil} (Total rows: {len(df_final)})")

        return df_for_accumulation

    except Exception as e:
        print(f"  Error Analisis: {e}")
        return None

# -------------------------------------------------------------------------
# IV. Modul Rekapitulasi (Membaca file Harian _temp_3.csv)
# -------------------------------------------------------------------------
def summarize_all_regions(start_date, end_date):
    print("\n" + "="*50)
    print("--- Langkah 4: MENGHITUNG TOTAL SAMBARAN PER REGION (AKUMULASI) ---")
    print("="*50)

    date_range = pd.date_range(start=start_date, end=end_date)
    all_data = []

    for single_date in date_range:
        date_str = single_date.strftime("%Y%m%d")
        file_path = os.path.join(BASE_DIR, f"{date_str}_Lightning_Analysis_Result_temp_3.csv")
        
        if os.path.exists(file_path):
            try:
                df = pd.read_csv(file_path)
                # Abaikan baris "TOTAL_HARI_INI" agar tidak ikut terjumlah
                df = df[df['region'] != 'TOTAL_HARI_INI']
                all_data.append(df)
            except Exception as e:
                print(f"  Error membaca {file_path}: {e}")

    if not all_data:
        print("Tidak ada file harian yang ditemukan untuk direkap.")
        return

    df_combined = pd.concat(all_data, ignore_index=True)
    
    # Group by Region dan Sum (Jumlahkan CG-, CG+, Total)
    df_total_per_region = df_combined.groupby('region')[['CG-', 'CG+', 'Total']].sum().reset_index()
    
    # Load ulang assets untuk ambil threshold
    if os.path.exists(ASSET_FILE):
        df_assets = pd.read_csv(ASSET_FILE, delimiter=';')
        
        # Merge dengan hasil total
        df_final_summary = pd.merge(
            df_total_per_region,
            df_assets[['Kecamatan', 'Rendah-Sedang', 'Sedang-Tinggi']],
            left_on='region',
            right_on='Kecamatan',
            how='left'
        )
        
        # Logic Klasifikasi
        def classify_density(row):
            total_val = row['Total']
            limit_low_med = row['Rendah-Sedang']
            limit_med_high = row['Sedang-Tinggi']
            if pd.isna(limit_low_med) or pd.isna(limit_med_high): return 'Undefined'
            if total_val < limit_low_med: return 'Rendah'
            elif total_val < limit_med_high: return 'Sedang'
            else: return 'Tinggi'

        df_final_summary['Category'] = df_final_summary.apply(classify_density, axis=1)
        
        # Bersihkan kolom output
        cols_output = ['region', 'CG-', 'CG+', 'Total', 'Category']
        df_final_summary = df_final_summary[[c for c in cols_output if c in df_final_summary.columns]]
        
    else:
        # Jika asset file hilang, simpan angka saja
        df_final_summary = df_total_per_region

    # Tambahkan Baris Grand Total di paling bawah
    grand_total_cg_minus = df_final_summary['CG-'].sum()
    grand_total_cg_plus = df_final_summary['CG+'].sum()
    grand_total_all = df_final_summary['Total'].sum()
    
    summary_row = pd.DataFrame([{
        'region': 'z_Alor',
        'CG-': grand_total_cg_minus,
        'CG+': grand_total_cg_plus,
        'Total': grand_total_all,
        'Category': ''
    }])
    
    df_final_summary = pd.concat([df_final_summary, summary_row], ignore_index=True)

    # Simpan File Akhir
    output_file_total = os.path.join(BASE_DIR, f"Rekap_Total_Per_Region_{start_date}_sd_{end_date}_temp.csv")
    df_final_summary.to_csv(output_file_total, index=False)
    
    print(f"Sukses! File rekap per region disimpan di: {output_file_total}")
    print("-" * 50)
    print(df_final_summary.head(10)) # Preview di console


# =============================================================================
# TEMPAT LOOP
# =============================================================================
if __name__ == "__main__":
    
    # --- AUTOMATION INPUT DATES ---
    # 1. Cek keberadaan file
    if not os.path.exists(DATE_INPUT_FILE):
        print(f"CRITICAL ERROR: Input file '{DATE_INPUT_FILE}' not found!")
        print("Please create the file with start_date and end_date (Format: YYYYMMDD).")
        print("Aborting script.")
        sys.exit() # type: ignore # Hentikan script
            
    try:
        # 2. Baca file
        # header=None karena asumsi file hanya berisi data mentah: 20260201,20260201
        df_dates = pd.read_csv(DATE_INPUT_FILE, header=None, dtype=str)
        
        if df_dates.empty:
            print(f"CRITICAL ERROR: '{DATE_INPUT_FILE}' is empty!")
            sys.exit() # type: ignore

        # Ambil baris pertama, kolom 0 dan kolom 1
        start_date = df_dates.iloc[0, 0]
        end_date = df_dates.iloc[0, 1]
        
        # Validasi sederhana apakah data terbaca
        if pd.isna(start_date) or pd.isna(end_date):
            print("CRITICAL ERROR: Could not read dates from file (NaN values detected).")
            sys.exit() # type: ignore
            
        print(f"Loaded dates from {DATE_INPUT_FILE}: {start_date} -> {end_date}")

    except Exception as e:
        print(f"CRITICAL ERROR reading '{DATE_INPUT_FILE}': {e}")
        print("Aborting script.")
        sys.exit() # type: ignore
    # ------------------------------

    # --- MODUL TAMBAHAN: KONVERSI YYYYMMDD KE TANGGAL BULAN TAHUN ---
    import datetime
    try:
        # Convert YYYYMMDD strings to Datetime objects, then format to DD Month YYYY
        formatted_start = datetime.datetime.strptime(str(start_date).strip(), "%Y%m%d").strftime("%d %B %Y")
        formatted_end = datetime.datetime.strptime(str(end_date).strip(), "%Y%m%d").strftime("%d %B %Y")
        
        # Write to txt file separated by a comma
        with open(DATE_OUTPUT_TXT, "w") as txt_file:
            txt_file.write(f"{formatted_start} - {formatted_end}\n")
            
        print(f"Successfully converted dates and saved to '{DATE_OUTPUT_TXT}'.")
    except Exception as e:
        print(f"Warning: Failed to convert and save dates to text file: {e}")
    # ---------------------------------------------------------

    # 3. Proses Loop Utama
    try:
        date_range = pd.date_range(start=start_date, end=end_date)
        print(f"Proses dari {start_date} s.d. {end_date}...")
    except Exception as e:
        print(f"Error creating date range: {e}")
        print("Please check format in date_temp.csv (Should be YYYYMMDD)")
        sys.exit() # type: ignore
    
    for single_date in date_range:
        current_date_str = single_date.strftime("%Y%m%d")
        
        # Jalankan proses harian, Modul IV akan membaca file-filenya nanti
        process_daily_data(current_date_str)

    # Panggil Modul IV untuk rekapitulasi semua file harian
    summarize_all_regions(start_date, end_date)

    print("\nSelesai!")