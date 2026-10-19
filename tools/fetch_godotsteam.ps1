# 拉取 / 升级 GodotSteam GDExtension 到 addons/godotsteam/（可复现）
#
# 用法（Windows PowerShell）：
#   powershell -ExecutionPolicy Bypass -File tools\fetch_godotsteam.ps1
#   powershell -ExecutionPolicy Bypass -File tools\fetch_godotsteam.ps1 -Version 4.23.1
#
# 说明：仓库已内置对应版本的 addons/godotsteam/（全平台二进制），本脚本用于在升级或
# 重新克隆缺文件时重新拉取。它只做下载与解包，不参与游戏运行。

param(
	[string]$Version = "4.23.1"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$url = "https://codeberg.org/godotsteam/godotsteam/releases/download/v$Version/godotsteam-$Version-gdextension-plugin-4.4.zip.tar.xz"
$tmp = Join-Path $env:TEMP "godotsteam-$Version-dl"
$tarball = Join-Path $tmp "godotsteam-$Version.tar.xz"
$extract = Join-Path $tmp "extract"

Write-Host "拉取 GodotSteam GDExtension v$Version"
Write-Host "  来源: $url"

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $extract | Out-Null

curl.exe -sSL -A "Mozilla/5.0" $url -o $tarball
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tarball)) { throw "下载失败：$url" }
Write-Host ("  下载完成: " + (Get-Item $tarball).Length + " 字节")

# Windows 10+ 自带 bsdtar，支持 xz
tar -xJf $tarball -C $extract
if ($LASTEXITCODE -ne 0) { throw "解包失败（需要支持 xz 的 tar）" }

$src = Join-Path $extract "addons\godotsteam"
if (-not (Test-Path $src)) { throw "解包内容缺少 addons/godotsteam" }

$dst = Join-Path $root "addons\godotsteam"
Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $root "addons") | Out-Null
Copy-Item -Recurse -Force $src $dst

Write-Host "已安装到 $dst"
Write-Host "完成。"
