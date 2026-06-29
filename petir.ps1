# Setup Path
$env:PATH = "$env:PATH;C:\Program Files\GMT6\bin"

# I. Input tanggal dan buat file tanggal sementara untuk python
# =============================================================================

# Otomatis pindah direktori ke folder tempat script ini disimpan
Set-Location $PSScriptRoot

Write-Host "Isi tanggal awal hingga akhir dengan format YYYYMMDD yang dipisah koma"
Write-Host "(contoh: 20260203,20260209)"
$date = Read-Host "> "

# 2. Tulis input tanggal
Set-Content -Path "date_temp.csv" -Value $date

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 1/7] Disimpan ke: date_temp.csv" -ForegroundColor Green
Write-Host "---------------------------------------"

# II. Konfigurasi Ngecek Data Poligon Kecamatan
# =============================================================================

Write-Host "[CEK] Cek data poligon.."

# Lokasi folder utama
$SOURCE_DIR = "D:\TITIPAN_KITA\RAIHAN\Git\kerapatan-petir"

# Lokasi folder (Tanpa garis miring di belakang)
$SHP_DIR = "$SOURCE_DIR\SHP_File"
$KEC_DIR = "$SHP_DIR\Kecamatan"

# Ekstensi file dan namanya
$EXTENSIONS = @(".cpg", ".dbf", ".prj", ".qmd", ".shp", ".shx")
$NAME_KEC = "ADMINISTRASIKECAMATAN_AR"
$NAMES = @("Alor_Barat_Daya", "Alor_Barat_Laut", "Alor_Selatan", "Alor_Tengah_Utara", "Alor_Timur", "Alor_Timur_Laut", "Kabola", "Lembur", "Mataru", "Pantar", "Pantar_Barat", "Pantar_Barat_Laut", "Pantar_Tengah", "Pantar_Timur", "Pulau_Pura", "Pureman", "Telukmutiara")

# Reset angka file yang hilang
$MISSING_COUNT = 0

Write-Host "Checking directories:"
Write-Host "1. `"$SHP_DIR`""
Write-Host "2. `"$KEC_DIR`""
Write-Host "------------------------------------------"

# --- Logika Cek File Seluruh Kecamatan (Folder terpisah) ---
foreach ($E in $EXTENSIONS) {
    if (-Not (Test-Path "$KEC_DIR\$NAME_KEC$E")) {
        Write-Host "[ MISSING ] $NAME_KEC$E (in Kecamatan folder)"
        $MISSING_COUNT += 1 
    }
}

# --- Logika Cek File Lainnya (Folder Utama) ---
foreach ($N in $NAMES) {
    foreach ($E in $EXTENSIONS) {
        if (-Not (Test-Path "$SHP_DIR\$N$E")) {
            Write-Host "[ MISSING ] $N$E"
            $MISSING_COUNT += 1
        } 
    }
}

# Keputusan apakah lanjut ke pemetaan berdasarkan integritas filenya
if ($MISSING_COUNT -gt 0) {
    Write-Host "Gagal: Terdapat file yang hilang. Keluar dari script..."
    exit
}

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 2/7] 18 file Shapefile Aman!!" -ForegroundColor Green
Write-Host "------------------------------------------"

# III. Konversi Data DB3 dan Clipping dengan python
# =============================================================================
Write-Host "[RUNNING] Starting Python data processing..."
& "C:\Users\stage\miniconda3\Scripts\conda.exe" run -n hannn python "Pengolahan_Awal_Petir_Script_V2.py"
Write-Host "Pengolahan data dengan python selesai."

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 3/7] Pengolahan dengan python berhasil.." -ForegroundColor Green
Write-Host "---------------------------------------"

# IV. Pemetaan dengan GMT (Dasar Topografi Abu-Abu + Batas Kecamatan)
# =============================================================================
    
# Setup konfigurasi GMT
gmt set MAP_FRAME_TYPE plain 
gmt set FORMAT_GEO_MAP ddd.xG
gmt set MAP_ANNOT_ORTHO en
gmt set FONT_ANNOT_PRIMARY 4p,Helvetica,black
gmt set MAP_FRAME_PEN white

# --- MULAI SESI GMT UNTUK SATU MAP ---
gmt begin Peta_temp_base png

    # QUOTED ARGUMENTS TO PREVENT POWERSHELL PARSING ERRORS
    gmt basemap "-R123.8/125.2/-9.1/-7.7" "-JM9.4c" "-X1.5c" "-Y1.5c" "-B0"  
    gmt plot "D:\TITIPAN_KITA\RAIHAN\Kerapatan_Petir\SHP_File\Kecamatan\ADMINISTRASIKECAMATAN_AR.shp" "-Ggray" "-W0.2p,black"
    gmt plot "D:\TITIPAN_KITA\RAIHAN\Kerapatan_Petir\SHP_File\Alor_Barat_Daya.shp" "-Ggray" "-W0.2p,black"


gmt end

& magick Peta_temp_base.png -fuzz "1%" -transparent white -resize 1020x1020 -gravity center -background none -extent 1080x1440 Peta_temp_base_magick.png

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 4/7] Peta base telah dibuat!" -ForegroundColor Green
Write-Host "---------------------------------------" 

# V. Pemetaan dengan GMT (Looping Kerapatan Petir Kecamatan)
# =============================================================================

# Looping GMT
$csvFiles = Get-ChildItem -Filter "Rekap_Total_Per_Region_*.csv"
foreach ($F in $csvFiles) {
    # Membaca data CSV dan melompati baris pertama (header)
    $csvData = Get-Content $F.FullName | Select-Object -Skip 1
    
    foreach ($line in $csvData) {
        # Token 1 (A) dan 5 (B) karena delimiter koma dan array PowerShell dimulai dari 0
        $tokens = $line -split ','
        $A = $tokens[0]
        $B = $tokens[4]

        # Grand total gk digenerate
        if ($A -ne "GRAND_TOTAL_ALL_REGIONS") {
            Write-Host "Sedang memproses: $A ..."

            # --- TENTUKAN WARNA BERDASARKAN NILAI B ---
            $FILL_COLOR = "gray" 
            if ($B -eq "Rendah") { $FILL_COLOR = "green" } 
            if ($B -eq "Sedang") { $FILL_COLOR = "yellow" } 
            if ($B -eq "Tinggi") { $FILL_COLOR = "red" } 

            # --- MULAI SESI GMT UNTUK SATU MAP ---
            gmt begin "Peta_${A}_temp" png 

                # QUOTED ARGUMENTS TO PREVENT POWERSHELL PARSING ERRORS
                gmt basemap "-R123.8/125.2/-9.1/-7.7" "-JM9.4c" "-X1.5c" "-Y1.5c" "-B0"
                gmt plot "$SOURCE_DIR\SHP_File\${A}.shp" "-G$FILL_COLOR" "-W0.4p,black" "-t30"

            gmt end

            & magick "Peta_${A}_temp.png" -fuzz "1%" -transparent white -resize 1020x1020 -gravity center -background none -extent 1080x1440 "Peta_${A}_temp_magick.png"

            Write-Host "Selesai: Peta_${A}_temp.png"
        }
    }
}

# Gabungkan semua peta kecamatan dengan base map menggunakan ImageMagick
magick Peta_*_temp_magick.png -background none -layers merge Peta_z_Alor_temp_magick.png
Write-Host "Selesai: Peta_Alor_temp_magick.png"

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 5/7] 18 Peta Kecamatan telah dibuat!" -ForegroundColor Green
Write-Host "---------------------------------------" 

# VI. Pemetaan dengan ImageMagick (Looping Gabungkan Frame + Base + Overlay + Text)
# ==============================================================================
# Configuration
# ==============================================================================
# Read the date from the text file and trim any hidden spaces/newlines
$period = (Get-Content "date_temp.txt" -Raw).Trim()

# Input filename for the base map (must exist in this folder)
$baseMap = "Peta_temp_base_magick.png"

# ==============================================================================
# Main Loop
# ==============================================================================

# Find all CSV files matching the pattern
$csvFiles = Get-ChildItem -Filter Rekap*.csv

if (-not $csvFiles) {
    Write-Error "No files matching 'Rekap*.csv' were found."
    return
}

if (-not (Test-Path $baseMap)) {
    Write-Error "The base map file '$baseMap' was not found. Please ensure it exists."
    return
}

foreach ($file in $csvFiles) {
    Write-Host "Processing CSV: $($file.Name)" -ForegroundColor Green
    $csvData = Import-Csv $file.FullName
    
    foreach ($row in $csvData) {
        # Extract the metrics
        $cgMinus = $row.'CG-'
        $cgPlus  = $row.'CG+'
        $total   = $row.total
        
        # 1. GET THE ROW NAME AND REPLACE UNDERSCORES WITH SPACES
        # The region name used for text labels
        $rowName = $row.region -replace '_', ' '
        
        # If the row name is empty, skip this row to avoid errors
        if ([string]::IsNullOrWhiteSpace($rowName)) { continue }

        # 2. SANITIZE THE FILENAME
        $safeRowName = $rowName -replace '[\\/:*?"<>| ]', '_'
        
        # Determine specific input/output filenames
        $regionMap = "Peta_${safeRowName}_temp_magick.png"
        $outName = "${safeRowName}_temp_4.png"
        $frame = "Assets\frame_assets.png"  # Ensure this file exists in the specified path

        # font size and styling for text layers
        $poppins = "C:/Users/stage/AppData/Local/Microsoft/Windows/Fonts" # Adjust this path if your fonts are located elsewhere
        $font = "$poppins/Poppins-Regular.ttf"  # Ensure this font file is in the same directory or provide full path
        $fontbold = "$poppins/Poppins-Bold.ttf"  # Ensure this font file is in the same directory or provide full path

        # Verify the region-specific map exists
        if (-not (Test-Path $regionMap)) {
            Write-Warning "Specific map '$regionMap' not found for '$rowName'. Skipping row."
            continue
        }

        # 3. CREATE THE SUMMARY SENTENCE
        $summaryText = "Selama periode $period `nterdapat $total petir di wilayah $rowName"

        # 4. BUILD THE IMAGEMAGICK COMMAND ARGUMENTS
        $magickArgs = @(
            # --- 1. START WITH THE FRAME (Most Bottom Layer) ---
            $frame,
            
            # -> FIX: Force full color space IMMEDIATELY after loading the first image <-
            "-colorspace", "sRGB",
            
            # --- 2. COMPOSITE BASE MAP ---
            # This stacks on top of the frame
            $baseMap,"-geometry", "+15+110", "-composite",
            
            # --- 3. COMPOSITE REGION-SPECIFIC MAP OVERLAY ---
            # This stacks on top of the base map
            $regionMap,"-geometry", "+15+110", "-composite",
            
            # --- 4. COMPOSITE TEXT LAYERS ---
            
            # Layer 4: Region Name
            #"(", "-background", "none", "-fill", "white", "-font", $fontbold, "-pointsize", "28", "-size", "700x60", "-gravity", "West", "label:Kec. $rowName", ")", 
            #"-geometry", "+70-212", "-composite",            
            
            # Layer 4.5: Special Case for z_Alor
            "(", "-background", "none", "-fill", "white", "-font", $fontbold, "-pointsize", "28", "-size", "700x60", "-gravity", "West", "label:$($rowName -replace 'z Alor', 'Kabupaten Alor')", ")", 
            "-geometry", "+70-212", "-composite",

            # Layer 5: CG-
            "(", "-background", "none", "-fill", "white", "-font", $font, "-pointsize", "22", "-size", "700x60", "-gravity", "Center", "label:$cgMinus", ")", 
            "-geometry", "+0-190", "-composite",
            
            # Layer 6: CG+
            "(", "-background", "none", "-fill", "white", "-font", $font, "-pointsize", "22", "-size", "700x60", "-gravity", "Center", "label:$cgPlus", ")", 
            "-geometry", "+198-190", "-composite",
            
            # Layer 7: Total
            "(", "-background", "none", "-fill", "white", "-font", $font, "-pointsize", "22", "-size", "700x60", "-gravity", "Center", "label:$total", ")", 
            "-geometry", "+400-190", "-composite",
            
            # Layer 8: Summary Sentence (Using 'Poppins' family name for Pango)
            #"(", "-background", "none", "-fill", "white", "-font", "Poppins", "-pointsize", "22", "-size", "800x", "-define", "pango:justify=true", "pango:$summaryText", ")", 
            #"-geometry", "-105+348", "-composite",
            "(", "-background", "none", "-fill", "white", "-font", $font, "-pointsize", "22", "-size", "700x300", "-gravity", "West", "label:$summaryText", ")", 
            "-geometry", "+68+360", "-composite",
            
            # --- OUTPUT FILE ---
            $outName
        )
        
        # 5. EXECUTE IMAGEMAGICK
        & magick $magickArgs
        
        Write-Host "    -> Generated merged image: $outName" -ForegroundColor Cyan
    }
}

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 6/7] Desain telah digabungkan!" -ForegroundColor Green
Write-Host "---------------------------------------" 

# VII. Pemetaan dengan FFmpeg (Overlay Animasi ke Base Video)
# =============================================================================
# --- CONFIGURATION ---
$baseVideo = "D:\TITIPAN_KITA\RAIHAN\Kerapatan_Petir\Assets\base.mp4"       # Update this to your base.mp4 path if it's in another folder
$imgSuffix = "*_temp_4.png"   
$output    = "$period.mp4"

# Set exact timing in seconds
$overlayStart = 5.47
$overlayEnd   = 41.02

# 1. Get the images
$images = Get-ChildItem $imgSuffix | Sort-Object Name
$imgCount = $images.Count

if ($imgCount -eq 0) { 
    Write-Host "Error: No images found with suffix $imgSuffix" -ForegroundColor Red
    pause; exit 
}

# 2. Calculate exact duration per image to fit the time window perfectly
$totalAnimTime = $overlayEnd - $overlayStart
$perImageDuration = $totalAnimTime / $imgCount 

# 3. Generate images_temp.txt 
$content = foreach ($img in $images) {
    "file '$($img.Name)'"
    "duration $($perImageDuration.ToString([cultureinfo]::InvariantCulture))"
}
$content += "file '$($images[-1].Name)'"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines("$PWD\images_temp.txt", $content, $utf8NoBom)

# 4. Run FFmpeg to overlay directly
ffmpeg -i $baseVideo -f concat -safe 0 -i images_temp.txt `
-filter_complex "[1:v]scale=1080:1440,setsar=1,setpts=PTS+$overlayStart/TB[fg]; [0:v][fg]overlay=enable='between(t,$overlayStart,$overlayEnd)':eof_action=pass[v]" `
-map "[v]" -map 0:a? -c:a copy -fps_mode vfr -pix_fmt yuv420p -y $output

Write-Host "`nSuccess! Your final merged video is saved as $output"

Write-Host "---------------------------------------"
Write-Host "[BERHASIL 7/7] Video animasi telah dibuat!" -ForegroundColor Green
Write-Host "---------------------------------------" 

# VIII. Cleanup File Temporary
# =============================================================================
Write-Host "Membersihkan file temporary (*temp*)..."
Get-ChildItem -Filter "*temp*" -File | Remove-Item -Force
Get-ChildItem -Filter "*gmt*" -File | Remove-Item -Force

Write-Host "Semua proses selesai!"