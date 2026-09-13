param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$ieImage = [System.Drawing.Image]::FromFile($Source)
$ieBitmap = [System.Drawing.Bitmap]::new(256,256,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$ieGraphics = [System.Drawing.Graphics]::FromImage($ieBitmap)
try {
    $ieGraphics.Clear([System.Drawing.Color]::FromArgb(20,32,36))
    $ieGraphics.DrawImage($ieImage,0,0,256,256)
    $ieBitmap.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Jpeg)
} finally {
    $ieGraphics.Dispose()
    $ieBitmap.Dispose()
    $ieImage.Dispose()
}
