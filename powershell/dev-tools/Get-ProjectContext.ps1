#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a rich, AI-ready context dump of a software project.

.DESCRIPTION
    Produces a single Markdown document containing:
      - Project metadata (name, stack detected, file counts)
      - Full directory tree (respecting .gitignore patterns)
      - Contents of key files: README, package.json / pyproject.toml /
        Cargo.toml / go.mod / *.sln, tsconfig, config files, etc.
      - Truncated contents of every source file under a configurable
        size limit (defaulting to 200 KB total output)

    The output is written to a file AND optionally copied to the clipboard,
    ready to paste into ChatGPT, Claude, Cursor, or any other AI assistant.

.PARAMETER ProjectPath
    Path to the project root.  Defaults to the current directory.

.PARAMETER OutputFile
    Where to write the Markdown dump.  Defaults to a temp file.

.PARAMETER MaxTotalKB
    Soft cap on total output size in KB (default 200).  Source files are
    truncated or skipped to stay within this limit.

.PARAMETER SkipPatterns
    Additional glob patterns for files/folders to exclude from source dump.

.PARAMETER Clipboard
    Copy the output to the clipboard after generation.

.PARAMETER Open
    Open the output file in the default Markdown viewer / editor.

.EXAMPLE
    .\Get-ProjectContext.ps1
    .\Get-ProjectContext.ps1 -ProjectPath C:\Dev\my-app -Clipboard
    .\Get-ProjectContext.ps1 -MaxTotalKB 50 -Open
#>
[CmdletBinding()]
param(
    [string]   $ProjectPath  = (Get-Location).Path,
    [string]   $OutputFile   = '',
    [int]      $MaxTotalKB   = 200,
    [string[]] $SkipPatterns = @(),
    [switch]   $Clipboard,
    [switch]   $Open
)

$ErrorActionPreference = 'Continue'

# ── Defaults ──────────────────────────────────────────────────────────────────
if (-not $OutputFile) {
    $safeName  = (Split-Path $ProjectPath -Leaf) -replace '[^\w]', '_'
    $OutputFile = Join-Path $env:TEMP "project_context_${safeName}.md"
}

$MaxBytes = $MaxTotalKB * 1024

# ── Patterns to always skip ───────────────────────────────────────────────────
$defaultSkip = @(
    '.git','node_modules','dist','build','.next','.nuxt','__pycache__',
    '.pytest_cache','.mypy_cache','.venv','venv','target','bin','obj',
    '.gradle','vendor','coverage','.nyc_output','.cache','.turbo',
    '*.min.js','*.min.css','*.map','*.lock','package-lock.json',
    'yarn.lock','pnpm-lock.yaml','Cargo.lock','*.png','*.jpg','*.jpeg',
    '*.gif','*.ico','*.svg','*.woff','*.woff2','*.ttf','*.eot',
    '*.zip','*.tar.gz','*.gz','*.exe','*.dll','*.so','*.dylib',
    '*.pdf','*.db','*.sqlite'
) + $SkipPatterns

function Should-Skip ([string]$path) {
    $name = Split-Path $path -Leaf
    foreach ($p in $defaultSkip) {
        if ($name -like $p) { return $true }
        if ($path -like "*\$p\*" -or $path -like "*/$p/*") { return $true }
    }
    return $false
}

# ── Source file extensions ────────────────────────────────────────────────────
$srcExtensions = @(
    '.ts','.tsx','.js','.jsx','.mjs','.cjs',
    '.py','.pyw',
    '.rs','.go','.cs','.fs','.vb',
    '.java','.kt','.scala',
    '.c','.h','.cpp','.hpp','.cc',
    '.rb','.php','.swift',
    '.sh','.bash','.zsh','.ps1','.psm1','.psd1',
    '.sql','.graphql','.proto',
    '.html','.vue','.svelte','.astro',
    '.css','.scss','.sass','.less',
    '.yaml','.yml','.toml','.json','.jsonc','.env',
    '.md','.mdx','.txt'
)

$keyFiles = @(
    'README.md','README.txt','readme.md',
    'package.json','tsconfig.json','tsconfig.base.json',
    'pyproject.toml','setup.py','setup.cfg','requirements.txt',
    'Cargo.toml','go.mod','go.sum',
    'composer.json','Gemfile','build.gradle',
    '.eslintrc.json','.eslintrc.js','.prettierrc','.prettierrc.json',
    'jest.config.js','jest.config.ts','vitest.config.ts',
    'vite.config.ts','vite.config.js',
    'next.config.js','next.config.ts',
    'tailwind.config.js','tailwind.config.ts',
    'Dockerfile','docker-compose.yml','docker-compose.yaml',
    '.env.example','.env.sample',
    'Makefile','Taskfile.yml',
    '*.sln','*.csproj'
)

# ── Detect project stack ──────────────────────────────────────────────────────
function Detect-Stack ([string]$root) {
    $stacks = @()
    if (Test-Path "$root/package.json") {
        $pkg = Get-Content "$root/package.json" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($pkg.dependencies.react -or $pkg.devDependencies.react) { $stacks += 'React' }
        if ($pkg.dependencies.next  -or $pkg.devDependencies.next)  { $stacks += 'Next.js' }
        if ($pkg.dependencies.vue   -or $pkg.devDependencies.vue)   { $stacks += 'Vue' }
        if ($pkg.dependencies.svelte -or $pkg.devDependencies.svelte){ $stacks += 'Svelte' }
        if (Test-Path "$root/tsconfig.json") { $stacks += 'TypeScript' } else { $stacks += 'JavaScript' }
        $stacks += 'Node.js'
    }
    if (Test-Path "$root/pyproject.toml") { $stacks += 'Python' }
    if (Test-Path "$root/Cargo.toml")     { $stacks += 'Rust' }
    if (Test-Path "$root/go.mod")         { $stacks += 'Go' }
    if (Get-ChildItem $root -Filter '*.csproj' -ErrorAction SilentlyContinue | Select-Object -First 1) { $stacks += '.NET' }
    if (Get-ChildItem $root -Filter '*.java'   -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1) { $stacks += 'Java' }
    if (Test-Path "$root/Dockerfile")     { $stacks += 'Docker' }
    if ($stacks.Count -eq 0) { $stacks += 'Unknown' }
    return $stacks -join ', '
}

# ── Build directory tree string ───────────────────────────────────────────────
function Get-Tree ([string]$path, [string]$indent = '', [int]$maxDepth = 4, [int]$depth = 0) {
    if ($depth -ge $maxDepth) { return }
    $items = Get-ChildItem $path -ErrorAction SilentlyContinue |
             Where-Object { -not (Should-Skip $_.FullName) } |
             Sort-Object { $_.PSIsContainer } -Descending |
             Sort-Object Name
    $i = 0
    foreach ($item in $items) {
        $i++
        $isLast    = ($i -eq $items.Count)
        $connector = if ($isLast) { '└── ' } else { '├── ' }
        $childIndent = if ($isLast) { "$indent    " } else { "$indent│   " }
        $icon = if ($item.PSIsContainer) { '📁 ' } else { '' }
        $script:treeLines += "$indent$connector$icon$($item.Name)"
        if ($item.PSIsContainer) {
            Get-Tree $item.FullName $childIndent $maxDepth ($depth + 1)
        }
    }
}

# ── File content reader ───────────────────────────────────────────────────────
function Read-FileSafe ([string]$path, [int]$maxChars = 8000) {
    try {
        $content = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop
        if ($content.Length -gt $maxChars) {
            return $content.Substring(0, $maxChars) + "`n`n... [TRUNCATED — $(($content.Length - $maxChars).ToString('N0')) chars omitted]"
        }
        return $content
    } catch {
        return "[Could not read file: $_]"
    }
}

function Get-LangTag ([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    $map = @{
        '.ts'=>'typescript'; '.tsx'=>'tsx'; '.js'=>'javascript'; '.jsx'=>'jsx'
        '.py'=>'python'; '.rs'=>'rust'; '.go'=>'go'; '.cs'=>'csharp'
        '.java'=>'java'; '.kt'=>'kotlin'; '.rb'=>'ruby'; '.php'=>'php'
        '.sh'=>'bash'; '.bash'=>'bash'; '.ps1'=>'powershell'
        '.html'=>'html'; '.css'=>'css'; '.scss'=>'scss'
        '.json'=>'json'; '.yaml'=>'yaml'; '.yml'=>'yaml'; '.toml'=>'toml'
        '.md'=>'markdown'; '.sql'=>'sql'; '.graphql'=>'graphql'
        '.c'=>'c'; '.h'=>'c'; '.cpp'=>'cpp'; '.hpp'=>'cpp'
        '.vue'=>'vue'; '.svelte'=>'svelte'
    }
    if ($map.ContainsKey($ext)) { return $map[$ext] }
    return ''
}

# ── Main generation ───────────────────────────────────────────────────────────
$projectName = Split-Path $ProjectPath -Leaf
$stack       = Detect-Stack $ProjectPath

$allFiles    = Get-ChildItem $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object { -not (Should-Skip $_.FullName) }

$totalFiles  = $allFiles.Count
$srcFiles    = $allFiles | Where-Object { $_.Extension.ToLower() -in $srcExtensions }

Write-Host "Generating context for: $projectName ($stack)" -ForegroundColor Cyan
Write-Host "  Files found: $totalFiles  Source files: $($srcFiles.Count)" -ForegroundColor DarkGray

$sb = [System.Text.StringBuilder]::new()

$null = $sb.AppendLine("# Project Context: $projectName")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $sb.AppendLine("**Path:** $ProjectPath")
$null = $sb.AppendLine("**Stack:** $stack")
$null = $sb.AppendLine("**Total files:** $totalFiles  |  **Source files:** $($srcFiles.Count)")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("---")
$null = $sb.AppendLine("")

# Directory tree
$null = $sb.AppendLine("## Directory Tree")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("```")
$null = $sb.AppendLine($projectName)
$script:treeLines = @()
Get-Tree $ProjectPath
$script:treeLines | ForEach-Object { $null = $sb.AppendLine($_) }
$null = $sb.AppendLine("```")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("---")
$null = $sb.AppendLine("")

# Key files section
$null = $sb.AppendLine("## Key Configuration Files")
$null = $sb.AppendLine("")

foreach ($pattern in $keyFiles) {
    $matches = Get-ChildItem $ProjectPath -Filter $pattern -Depth 1 -ErrorAction SilentlyContinue
    foreach ($f in $matches) {
        if (Should-Skip $f.FullName) { continue }
        $lang    = Get-LangTag $f.FullName
        $content = Read-FileSafe $f.FullName 6000
        $null = $sb.AppendLine("### $($f.Name)")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("``````$lang")
        $null = $sb.AppendLine($content)
        $null = $sb.AppendLine("``````")
        $null = $sb.AppendLine("")
    }
}

$null = $sb.AppendLine("---")
$null = $sb.AppendLine("")

# Source files
$null = $sb.AppendLine("## Source Files")
$null = $sb.AppendLine("")

$bytesUsed   = [System.Text.Encoding]::UTF8.GetByteCount($sb.ToString())
$srcPriority = $srcFiles | Sort-Object {
    # prioritise files closer to project root and smaller files
    $depth = ($_.FullName.Substring($ProjectPath.Length) -split '[/\\]').Count
    $depth * 10000 + $_.Length
}

foreach ($file in $srcPriority) {
    if ($bytesUsed -ge $MaxBytes) {
        $null = $sb.AppendLine("> ⚠ Output size limit reached — $($srcPriority.Count) remaining source files omitted.")
        break
    }
    $relPath = $file.FullName.Substring($ProjectPath.Length).TrimStart('/\')
    $lang    = Get-LangTag $file.FullName
    $perFileMax = [Math]::Min(6000, $MaxBytes - $bytesUsed)
    $content = Read-FileSafe $file.FullName $perFileMax

    $block = "### $relPath`n`n``````$lang`n$content`n``````n`n"
    $null = $sb.AppendLine("### $relPath")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("``````$lang")
    $null = $sb.AppendLine($content)
    $null = $sb.AppendLine("``````")
    $null = $sb.AppendLine("")

    $bytesUsed = [System.Text.Encoding]::UTF8.GetByteCount($sb.ToString())
}

$output = $sb.ToString()

# Write file
Set-Content $OutputFile $output -Encoding UTF8 -NoNewline
$sizeKB = [math]::Round($output.Length / 1024, 1)

Write-Host "  Output: $OutputFile  ($sizeKB KB)" -ForegroundColor Green

if ($Clipboard) {
    Set-Clipboard $output
    Write-Host '  ✓ Copied to clipboard' -ForegroundColor Green
}

if ($Open) {
    Start-Process $OutputFile
}

Write-Host ''
Write-Host '  ✅ Done! Paste the file contents into your AI assistant.' -ForegroundColor Cyan
Write-Host ''
