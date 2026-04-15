$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pngPath = Join-Path $scriptDir "fhplayer-icon-256.png"
$icoPath = Join-Path $scriptDir "fhplayer.ico"

Add-Type -AssemblyName System.Drawing

$size = 256
$bitmap = New-Object System.Drawing.Bitmap $size, $size
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

$blueDark = [System.Drawing.Color]::FromArgb(12, 48, 122)
$blue = [System.Drawing.Color]::FromArgb(14, 98, 214)
$orange = [System.Drawing.Color]::FromArgb(255, 140, 0)
$orangeLight = [System.Drawing.Color]::FromArgb(255, 189, 46)
$white = [System.Drawing.Color]::FromArgb(255, 255, 255)
$redOrange = [System.Drawing.Color]::FromArgb(226, 66, 18)

$circleRect = New-Object System.Drawing.RectangleF 28, 20, 164, 164
$graphics.FillEllipse((New-Object System.Drawing.SolidBrush $blue), $circleRect)
$graphics.DrawEllipse((New-Object System.Drawing.Pen $blueDark, 10), $circleRect)

$ringPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$ringPath.AddArc(12, 44, 220, 160, 210, 210)
$graphics.DrawPath((New-Object System.Drawing.Pen $blueDark, 16), $ringPath)
$graphics.DrawArc((New-Object System.Drawing.Pen $orange, 16), 80, 42, 154, 148, 318, 166)
$graphics.DrawArc((New-Object System.Drawing.Pen $redOrange, 12), 82, 144, 136, 74, 15, 160)

$barBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  (New-Object System.Drawing.Point 0, 168),
  (New-Object System.Drawing.Point 0, 72),
  $redOrange,
  $orangeLight
)
$graphics.FillRectangle($barBrush, 84, 112, 18, 52)
$graphics.FillRectangle($barBrush, 108, 92, 18, 72)
$graphics.FillRectangle($barBrush, 132, 70, 18, 94)
$graphics.FillRectangle($barBrush, 156, 98, 18, 66)

$triangle = New-Object System.Drawing.Drawing2D.GraphicsPath
$triangle.AddPolygon(@(
  (New-Object System.Drawing.PointF 106, 74),
  (New-Object System.Drawing.PointF 106, 170),
  (New-Object System.Drawing.PointF 176, 122)
))
$graphics.FillPath((New-Object System.Drawing.SolidBrush $white), $triangle)

$bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

$pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
$memory = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter($memory)
$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]1)
$writer.Write([byte]0)
$writer.Write([byte]0)
$writer.Write([byte]0)
$writer.Write([byte]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]32)
$writer.Write([UInt32]$pngBytes.Length)
$writer.Write([UInt32]22)
$writer.Write($pngBytes)
$writer.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $memory.ToArray())

$writer.Dispose()
$memory.Dispose()
$barBrush.Dispose()
$triangle.Dispose()
$ringPath.Dispose()
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Generated $pngPath"
Write-Host "Generated $icoPath"
