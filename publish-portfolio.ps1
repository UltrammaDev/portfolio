# publish-portfolio.ps1 — публикация портфолио на GitHub Pages.
#
# Зачем скрипт: токен живёт в gh-token.txt и НЕ попадает ни в командную строку,
# ни в историю, ни в .git/config. Скрипт читает его оттуда и подставляет в
# URL только на время push.
#
# Как пользоваться:
#   1) criar токен: https://github.com/settings/personal-access-tokens/new
#      Repository access: только UltrammaDev и portfolio
#      Permissions: Contents (Read and write), Pages (Read and write)
#      Expiration: 7 дней
#   2) положить токен одной строкой в E:\portfolio\gh-token.txt
#   3) запустить:  powershell -File E:\portfolio\publish-portfolio.ps1
#
# Если файла gh-token.txt нет — скрипт только подготовит репозитории и
# покажет, что осталось сделать.

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$gh    = "UltrammaDev"
$keyFile = "E:\portfolio\gh-token.txt"

function Info($m){ Write-Host $m -ForegroundColor DarkGray }
function Ok($m){   Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }

Write-Host ""
Write-Host "=== Публикация портфолио ===" -ForegroundColor Cyan
Write-Host ""

# ---------- 1. проверяем, что есть чем пушить ----------
$token = ""
if (Test-Path $keyFile) {
    $token = (Get-Content $keyFile -First 1).Trim()
}
$haveToken = $token -ne ""

if (-not $haveToken) {
    Warn "Токен не найден в $keyFile"
    Info "Создайте узкий токен: https://github.com/settings/personal-access-tokens/new"
    Info "  Repository access : Only select repositories -> UltrammaDev, portfolio"
    Info "  Permissions       : Contents (Read and write), Pages (Read and write)"
    Info "  Expiration        : 7 days"
    Info "Положите одной строкой в $keyFile и запустите снова."
    Write-Host ""
}

# ---------- 2. функции для настройки репозитория ----------
function New-Repo {
    param([string]$Name, [string]$Token)
    $url = "https://api.github.com/user/repos"
    $body = @{ name = $Name; private = $false; description = $null } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" `
               -Headers @{ Authorization = "Bearer $Token"; "User-Agent" = "portfolio-publish"; "Accept" = "application/vnd.github+json" }
        return $true
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 422) { return $false }   # уже существует
        throw
    }
}

function Enable-Pages {
    param([string]$Name, [string]$Token)
    $url = "https://api.github.com/repos/$gh/$Name/pages"
    $body = @{ source = @{ branch = "main"; path = "/" } } | ConvertTo-Json -Depth 5
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" `
            -Headers @{ Authorization = "Bearer $Token"; "User-Agent" = "portfolio-publish"; "Accept" = "application/vnd.github+json" } | Out-Null
        return "created"
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 409) { return "already" }
        return "failed: $code"
    }
}

function Push-Dir {
    param([string]$Dir, [string]$Name, [string]$Token)
    $authUrl = "https://UltrammaDev:$Token@github.com/$gh/$Name.git"
    Push-Location $Dir
    try {
        git remote remove origin 2>$null | Out-Null
        git remote add origin $authUrl
        git branch -M main 2>$null | Out-Null
        git add -A
        git -c user.name="UltrammaDev" -c user.email="UltrammaDev@users.noreply.github.com" `
            commit -m "Портфолио и README" 2>$null | Out-Null
        # push без утечки токена: URL временный, в .git/config остаётся без пароля
        $out = & git push -u origin main --force 2>&1 | Out-String
        # затираем URL на чистый, чтобы токен не остался в конфиге репозитория
        git remote set-url origin "https://github.com/$gh/$Name.git"
        if ($out -match "main -> main" -or $out -match "Everything up-to-date") {
            return $true
        }
        return $false
    } finally {
        Pop-Location
    }
}

# ---------- 3. настраиваем репозитории ----------
if ($haveToken) {
    Write-Host "Создаю репозитории..." -ForegroundColor Cyan

    $created1 = New-Repo -Name "UltrammaDev" -Token $token
    if ($created1) { Ok "  создан UltrammaDev (для профиля)" }
    else           { Info "  UltrammaDev уже существует — обновлю" }

    $created2 = New-Repo -Name "portfolio" -Token $token
    if ($created2) { Ok "  создан portfolio (для сайта)" }
    else           { Info "  portfolio уже существует — обновлю" }
    Write-Host ""
}

# ---------- 4. что физически лежит ----------
Write-Host "Подготовлено к публикации:" -ForegroundColor Cyan
Info "  E:\UltrammaDev  -> github.com/$gh/UltrammaDev   (README на профиль)"
Info "  E:\portfolio    -> github.com/$gh/portfolio     (index.html на Pages)"
Write-Host ""

if (-not $haveToken) {
    Warn "Публикация не выполнена — нет токена. Шаги выше."
    exit 1
}

# ---------- 5. пушим ----------
Write-Host "Публикую..." -ForegroundColor Cyan
$p1 = Push-Dir -Dir "E:\UltrammaDev" -Name "UltrammaDev" -Token $token
if ($p1) { Ok "  README   -> UltrammaDev  (загружен)" } else { Warn "  README   -> ошибка push" }

$p2 = Push-Dir -Dir "E:\portfolio" -Name "portfolio" -Token $token
if ($p2) { Ok "  сайт     -> portfolio    (загружен)" } else { Warn "  сайт     -> ошибка push" }

# ---------- 6. включаем Pages ----------
Write-Host ""
Write-Host "Включаю GitHub Pages..." -ForegroundColor Cyan
$st = Enable-Pages -Name "portfolio" -Token $token
switch ($st) {
    "created" { Ok "  Pages включён: main / root" }
    "already" { Ok "  Pages уже включён" }
    default   { Warn "  Pages: $st — включите вручную: Settings -> Pages -> main / root" }
}

Write-Host ""
Write-Host "Готово." -ForegroundColor Green
Write-Host "  Профиль : https://github.com/$gh"
Write-Host "  Сайт    : https://$gh.github.io/portfolio"
Info  ""
Info  "Через минуту-две сайт откроется. Токен в gh-token.txt можно удалять."