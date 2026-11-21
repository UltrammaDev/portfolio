# publish-portfolio.ps1 — заливка портфолио на GitHub Pages.
#
# Что делает: коммитит оба репозитория, пушит их в GitHub и включает Pages.
# Чего НЕ делает: не создаёт репозитории. Их нужно создать один раз руками —
# узкий токен (fine-grained) не имеет права создавать репозитории, это отдельное
# разрешение уровня аккаунта.
#
# ---------- Разовая подготовка (один раз, 2 минуты) ----------
#
# 1) Создать два ПУБЛИЧНЫХ репозитория (галочку «Add a README» НЕ ставить):
#       https://github.com/new   ->  имя: UltrammaDev
#       https://github.com/new   ->  имя: portfolio
#
# 2) Создать узкий токен: https://github.com/settings/personal-access-tokens/new
#       Repository access : Only select repositories -> UltrammaDev, portfolio
#       Permissions       :
#           Contents : Read and write
#           Pages    : Read and write
#       Expiration        : 7 days
#
# 3) Положить токен одной строкой в E:\portfolio\gh-token.txt
#
# 4) Запустить:
#       powershell -ExecutionPolicy Bypass -File E:\portfolio\publish-portfolio.ps1
#
# Без gh-token.txt скрипт просто покажет состояние и подсказки.

$ErrorActionPreference = "Stop"
$gh      = "UltrammaDev"
$keyFile = "E:\portfolio\gh-token.txt"
$ProgressPreference = "SilentlyContinue"   # иначе Invoke-WebRequest тормозит на HTTPS

function Info($m){ Write-Host $m -ForegroundColor DarkGray }
function Ok($m){   Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Head($m){ Write-Host $m -ForegroundColor Cyan }

# HTTP-запрос с разбором кода ответа. В PowerShell 5.1 исключение на 4xx/5xx —
# норма, поэтому код достаём из Exception.Response.
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

# ---------- 1. инструменты ----------
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
function Enable-Pages {
    param([string]$Name, [string]$Token)
    $h = @{ Authorization = "Bearer $Token"; "User-Agent" = "portfolio-publish"; "Accept" = "application/vnd.github+json" }
    $body = (@{ source = @{ branch = "main"; path = "/" } } | ConvertTo-Json -Depth 5)
    # сначала пробуем создать, при 409 — обновить существующий
    $r = Api -Method Post -Url "https://api.github.com/repos/$gh/$Name/pages" -Headers $h -Body $body
    if ($r.code -eq 201) { return "created" }
    if ($r.code -eq 409) {
        $u = Api -Method Put -Url "https://api.github.com/repos/$gh/$Name/pages" -Headers $h -Body $body
        if ($u.code -eq 204) { return "updated" }
        return "already"
    }
    return "failed($($r.code))"
}

function Push-Dir {
    param([string]$Dir, [string]$Name, [string]$Token)

    # ВНИМАНИЕ (грабли PowerShell 5.1): вывод git в stderr при
    # $ErrorActionPreference = "Stop" превращается в фатальную NativeCommandError.
    # Поэтому внутри функции глушим проверку ошибок у нативных команд.
    $ErrorActionPreference = "Continue"

    $authUrl  = "https://UltrammaDev:$Token@github.com/$gh/$Name.git"
    $cleanUrl = "https://github.com/$gh/$Name.git"

    Push-Location $Dir
    try {
        # remote с токеном — только на время push
        git remote remove origin 2>&1 | Out-Null
        git remote add origin $authUrl  2>&1 | Out-Null
        git branch -M main 2>&1 | Out-Null
        git add -A  2>&1 | Out-Null

        # коммит, только если есть что коммитить
        git -c user.name="UltrammaDev" -c user.email="UltrammaDev@users.noreply.github.com" `
            commit -m "Обновление" 2>&1 | Out-Null

        $out  = (& git push -u origin main --force 2>&1 | Out-String)
        $code = $LASTEXITCODE

        # ВАЖНО: сразу затираем URL — токен не должен остаться в .git/config
        git remote set-url origin $cleanUrl  2>&1 | Out-Null

        if ($code -eq 0 -or $out -match "main -> main" -or $out -match "up-to-date") {
            return $true
        }
        # прячем токен, если он попал в текст ошибки
        Write-Host ($out -replace [regex]::Escape($Token), "***") -ForegroundColor DarkGray
        return $false
    } finally {
        Pop-Location
    }
}

# ---------- 3. состояние ----------
Head "Куда заливаем:"
Info "  E:\UltrammaDev  ->  github.com/$gh/UltrammaDev   (README профиля)"
Info "  E:\portfolio    ->  github.com/$gh/portfolio     (index.html на Pages)"
Write-Host ""

if (-not $haveToken) {
    Warn "Токена нет — заливка не выполнена."
    Write-Host ""
    Head "Что сделать:"
    Info "  1) создать репозитории (если ещё нет): https://github.com/new"
    Info "       UltrammaDev  и  portfolio   — публичные, БЕЗ README"
    Info "  2) токен: https://github.com/settings/personal-access-tokens/new"
    Info "       Repository access : Only select repositories -> UltrammaDev, portfolio"
    Info "       Permissions       : Contents (Read and write), Pages (Read and write)"
    Info "       Expiration        : 7 days"
    Info "  3) положить токен одной строкой в $keyFile"
    exit 0
}

# ---------- 4. заливаем ----------
Head "Заливаю..."
$p1 = Push-Dir -Dir "E:\UltrammaDev" -Name "UltrammaDev" -Token $token
if ($p1) { Ok "  README -> UltrammaDev" } else { Warn "  README -> ошибка push" }

$p2 = Push-Dir -Dir "E:\portfolio" -Name "portfolio" -Token $token
if ($p2) { Ok "  сайт   -> portfolio" } else { Warn "  сайт   -> ошибка push" }

# ---------- 5. Pages ----------
Write-Host ""
Head "Включаю GitHub Pages..."
$st = Enable-Pages -Name "portfolio" -Token $token
switch ($st) {
    "created" { Ok "  Pages включён: ветка main, корень" }
    "updated" { Ok "  Pages настроен: ветка main, корень" }
    "already" { Ok "  Pages уже включён" }
    default   { Warn "  Pages: $st — включите вручную: Settings -> Pages -> main / root" }
}

Write-Host ""
Write-Host "Готово." -ForegroundColor Green
Write-Host "  Профиль : https://github.com/$gh"
Write-Host "  Сайт    : https://$gh.github.io/portfolio"
Info  ""
Info  "Сайт поднимется через минуту-две. Токен из gh-token.txt можно удалить."