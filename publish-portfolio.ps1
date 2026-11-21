# publish-portfolio.ps1 — публикация портфолио на GitHub Pages.
#
# Зачем скрипт: токен живёт в gh-token.txt и НЕ попадает ни в командную строку,
# ни в историю консоли, ни в .git/config. Скрипт читает его оттуда и подставляет
# в URL только на время push, после чего возвращает чистый URL.
#
# Как пользоваться:
#   1) создать узкий токен: https://github.com/settings/personal-access-tokens/new
#        Repository access : Only select repositories -> UltrammaDev, portfolio
#        Permissions       : Contents (Read and write), Pages (Read and write)
#        Expiration        : 7 days
#   2) положить токен одной строкой в E:\portfolio\gh-token.txt
#   3) запустить:  powershell -ExecutionPolicy Bypass -File E:\portfolio\publish-portfolio.ps1
#
# Если файла gh-token.txt нет — скрипт только покажет, что осталось сделать.

$ErrorActionPreference = "Stop"
$gh      = "UltrammaDev"
$keyFile = "E:\portfolio\gh-token.txt"
$ProgressPreference = "SilentlyContinue"   # иначе Invoke-WebRequest тормозит на HTTPS

function Info($m){ Write-Host $m -ForegroundColor DarkGray }
function Ok($m){   Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Head($m){ Write-Host $m -ForegroundColor Cyan }

# HTTP-запрос с разбором кода ответа. В PowerShell 5.1 исключение при 4xx/5xx —
# это норма, поэтому код достаём из Exception.Response.
function Api {
    param([string]$Method, [string]$Url, [hashtable]$Headers, [string]$Body)
    try {
        if ($Body) {
            $r = Invoke-WebRequest -Uri $Url -Method $Method -Body $Body `
                   -ContentType "application/json" -Headers $Headers -UseBasicParsing
        } else {
            $r = Invoke-WebRequest -Uri $Url -Method $Method -Headers $Headers -UseBasicParsing
        }
        return @{ code = [int]$r.StatusCode; json = $r.Content }
    } catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        return @{ code = $code; json = ""; error = $_.Exception.Message }
    }
}

Write-Host ""
Write-Host "=== Публикация портфолио ===" -ForegroundColor Cyan
Write-Host ""

# ---------- 1. проверяем инструменты ----------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git не найден в PATH." -ForegroundColor Red
    Info  "Установите:  winget install Git.Git"
    exit 1
}

$token = ""
if (Test-Path $keyFile) {
    $token = (Get-Content $keyFile -TotalCount 1).Trim()
}
$haveToken = ($token -ne "")

# ---------- 2. функции ----------
function New-Repo {
    param([string]$Name, [string]$Token)
    $h = @{ Authorization = "Bearer $Token"; "User-Agent" = "portfolio-publish"; "Accept" = "application/vnd.github+json" }
    $body = (@{ name = $Name; private = $false } | ConvertTo-Json)
    $r = Api -Method Post -Url "https://api.github.com/user/repos" -Headers $h -Body $body
    if ($r.code -eq 201) { return "created" }
    if ($r.code -eq 422) { return "exists" }     # имя занято
    return "failed($($r.code))"
}

function Enable-Pages {
    param([string]$Name, [string]$Token)
    $h = @{ Authorization = "Bearer $Token"; "User-Agent" = "portfolio-publish"; "Accept" = "application/vnd.github+json" }
    $body = (@{ source = @{ branch = "main"; path = "/" } } | ConvertTo-Json -Depth 5)
    $r = Api -Method Post -Url "https://api.github.com/repos/$gh/$Name/pages" -Headers $h -Body $body
    if ($r.code -eq 201) { return "created" }
    if ($r.code -eq 409) { return "already" }    # уже включён
    return "failed($($r.code))"
}

function Push-Dir {
    param([string]$Dir, [string]$Name, [string]$Token)

    $authUrl  = "https://UltrammaDev:$Token@github.com/$gh/$Name.git"
    $cleanUrl = "https://github.com/$gh/$Name.git"

    Push-Location $Dir
    try {
        # remote ставим с токеном только на время push
        git remote remove origin 2>$null | Out-Null
        git remote add origin $authUrl
        git branch -M main 2>$null | Out-Null
        git add -A

        # коммит, только если есть что коммитить
        git -c user.name="UltrammaDev" -c user.email="UltrammaDev@users.noreply.github.com" `
            commit -m "Обновление" 2>$null | Out-Null

        $out = (& git push -u origin main --force 2>&1 | Out-String)

        # ВАЖНО: сразу затираем URL — токен не должен остаться в .git/config
        git remote set-url origin $cleanUrl

        if ($out -match "main -> main" -or $out -match "up-to-date" -or $LASTEXITCODE -eq 0) {
            return $true
        }
        Write-Host $out -ForegroundColor DarkGray
        return $false
    } finally {
        Pop-Location
    }
}

# ---------- 3. что публикуем ----------
Head "Состав репозиториев:"
Info "  E:\UltrammaDev  ->  github.com/$gh/UltrammaDev   (README профиля)"
Info "  E:\portfolio    ->  github.com/$gh/portfolio     (index.html на Pages)"
Write-Host ""

if (-not $haveToken) {
    Warn "Токена нет — публикация не выполнена."
    Write-Host ""
    Info "Создайте узкий токен: https://github.com/settings/personal-access-tokens/new"
    Info "  Repository access : Only select repositories -> UltrammaDev, portfolio"
    Info "  Permissions       : Contents (Read and write), Pages (Read and write)"
    Info "  Expiration        : 7 days"
    Info "Положите его одной строкой в $keyFile и запустите скрипт снова."
    exit 0
}

# ---------- 4. создаём репозитории ----------
Head "Создаю репозитории..."
$r1 = New-Repo -Name "UltrammaDev" -Token $token
if ($r1 -eq "created") { Ok "  UltrammaDev — создан" }
elseif ($r1 -eq "exists") { Info "  UltrammaDev — уже есть, обновлю" }
else { Warn "  UltrammaDev — ошибка $r1" }

$r2 = New-Repo -Name "portfolio" -Token $token
if ($r2 -eq "created") { Ok "  portfolio — создан" }
elseif ($r2 -eq "exists") { Info "  portfolio — уже есть, обновлю" }
else { Warn "  portfolio — ошибка $r2" }
Write-Host ""

# ---------- 5. заливаем ----------
Head "Заливаю файлы..."
$p1 = Push-Dir -Dir "E:\UltrammaDev" -Name "UltrammaDev" -Token $token
if ($p1) { Ok "  README -> UltrammaDev" } else { Warn "  README -> ошибка push" }

$p2 = Push-Dir -Dir "E:\portfolio" -Name "portfolio" -Token $token
if ($p2) { Ok "  сайт   -> portfolio" } else { Warn "  сайт   -> ошибка push" }

# ---------- 6. включаем Pages ----------
Write-Host ""
Head "Включаю GitHub Pages..."
$st = Enable-Pages -Name "portfolio" -Token $token
switch ($st) {
    "created" { Ok "  Pages включён: ветка main, корень" }
    "already" { Ok "  Pages уже включён" }
    default   { Warn "  Pages: $st — включите вручную: Settings -> Pages -> main / root" }
}

Write-Host ""
Write-Host "Готово." -ForegroundColor Green
Write-Host "  Профиль : https://github.com/$gh"
Write-Host "  Сайт    : https://$gh.github.io/portfolio"
Info  ""
Info  "Сайт поднимется через минуту-две. Токен из gh-token.txt можно удалить."