# Run after render_attack_preview.py. Uses native Windows image composition.
Add-Type -AssemblyName System.Drawing
$sheet = [System.Drawing.Bitmap]::new(2400, 640)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([System.Drawing.Color]::FromArgb(25, 29, 33))
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [System.Drawing.Font]::new('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$labels = @('Small single - 0.25 m', 'Medium twin - 0.40 m', 'Large twin - 0.60 m')
$sizes = @('small', 'medium', 'large')
try {
    for ($index = 0; $index -lt 3; $index++) {
        $source = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot "sawblade_tank_exhaust_$($sizes[$index]).png"))
        try { $graphics.DrawImage($source, [System.Drawing.Rectangle]::new($index * 800, 40, 800, 600)) }
        finally { $source.Dispose() }
        $graphics.DrawString($labels[$index], $font, [System.Drawing.Brushes]::White, $index * 800 + 20, 6)
    }
    $sheet.Save((Join-Path $PSScriptRoot 'sawblade_tank_exhaust_comparison.png'), [System.Drawing.Imaging.ImageFormat]::Png)
}
finally { $font.Dispose(); $graphics.Dispose(); $sheet.Dispose() }
