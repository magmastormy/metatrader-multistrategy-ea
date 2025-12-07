# Add CommonTypes to all Core files
$coreFiles = Get-ChildItem -Path "Core" -Include "*.mqh" -Recurse -File

Write-Host "Adding CommonTypes to $($coreFiles.Count) Core files..."

foreach($file in $coreFiles) {
    $content = Get-Content $file.FullName -Raw
    
    # Skip if already includes CommonTypes
    if($content -match "CommonTypes\.mqh") {
        continue
    }
    
    # Find first #include line
    $firstInclude = $content.IndexOf("#include")
    if($firstInclude -gt -1) {
        $lineEnd = $content.IndexOf("`n", $firstInclude)
        if($lineEnd -gt -1) {
            $content = $content.Insert($lineEnd + 1, "`r`n#include \"CommonTypes.mqh\"`r`n")
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-Host "Added CommonTypes to: $($file.Name)"
        }
    }
}

Write-Host "CommonTypes addition complete!"
