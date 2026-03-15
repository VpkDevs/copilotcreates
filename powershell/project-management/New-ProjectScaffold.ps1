#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive wizard to scaffold a new software project with common boilerplate.

.DESCRIPTION
    Prompts for project type, name and destination, then creates the folder
    structure, placeholder files, .gitignore, README, and optionally runs
    `git init`.

    Supported templates
    -------------------
    node-ts   Node.js + TypeScript (src/, tests/, tsconfig, eslint, jest)
    node-js   Node.js JavaScript (src/, tests/, eslint)
    python    Python package (src/, tests/, pyproject.toml, ruff config)
    react     Vite + React + TypeScript
    nextjs    Next.js 14+ app-router skeleton
    dotnet    .NET console app (dotnet new console)
    rust      Cargo binary (cargo new)
    go        Go module (go mod init)
    bash      Bash script repo with tests
    generic   Language-agnostic with README and .gitignore only

.PARAMETER RootDir
    Where to create the new project folder.  Defaults to the current directory.

.PARAMETER Name
    Project name (folder name).  Prompted if not supplied.

.PARAMETER Template
    One of the template IDs listed above.  Prompted if not supplied.

.PARAMETER NoGit
    Skip `git init`.

.EXAMPLE
    .\New-ProjectScaffold.ps1
    .\New-ProjectScaffold.ps1 -RootDir C:\Dev -Name my-app -Template react
#>
[CmdletBinding()]
param(
    [string] $RootDir  = (Get-Location).Path,
    [string] $Name     = '',
    [ValidateSet('node-ts','node-js','python','react','nextjs','dotnet','rust','go','bash','generic')]
    [string] $Template = '',
    [switch] $NoGit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Colour helpers ────────────────────────────────────────────────────────────
function Write-Step  ([string]$msg) { Write-Host "  ▶ $msg" -ForegroundColor Cyan }
function Write-Done  ([string]$msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Info  ([string]$msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Write-Warn  ([string]$msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Err   ([string]$msg) { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Ask ([string]$prompt, [string]$default = '') {
    $hint = if ($default) { " [$default]" } else { '' }
    $ans  = Read-Host "$prompt$hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
    return $ans.Trim()
}

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  ┌─────────────────────────────────────────┐' -ForegroundColor DarkCyan
Write-Host '  │         New Project Scaffold Wizard      │' -ForegroundColor Cyan
Write-Host '  └─────────────────────────────────────────┘' -ForegroundColor DarkCyan
Write-Host ''

# ── Gather inputs ─────────────────────────────────────────────────────────────
if (-not $Name) {
    $Name = Ask 'Project name (folder name)'
    if (-not $Name) { Write-Err 'Project name is required.'; exit 1 }
}
$Name = $Name -replace '[^\w\-\.]', '-'

if (-not $Template) {
    Write-Host ''
    Write-Host '  Templates:' -ForegroundColor DarkGray
    @(
        '    node-ts   Node.js + TypeScript'
        '    node-js   Node.js JavaScript'
        '    python    Python package'
        '    react     Vite + React + TypeScript'
        '    nextjs    Next.js 14 (app router)'
        '    dotnet    .NET console app'
        '    rust      Rust binary (cargo)'
        '    go        Go module'
        '    bash      Bash script repo'
        '    generic   Generic (README + .gitignore only)'
    ) | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    Write-Host ''
    $Template = Ask 'Template' 'generic'
}

$projectPath = Join-Path $RootDir $Name

if (Test-Path $projectPath) {
    Write-Err "Directory already exists: $projectPath"
    exit 1
}

$gitName  = (git config --global user.name  2>$null) ?? $env:USERNAME
$gitEmail = (git config --global user.email 2>$null) ?? ''
$year     = (Get-Date).Year

# ── Generic files ─────────────────────────────────────────────────────────────
$commonGitignore = @"
# OS
.DS_Store
Thumbs.db
desktop.ini

# Editors
.vscode/
.idea/
*.suo
*.user

# Env
.env
.env.local
.env.*.local
"@

$readmeMd = @"
# $Name

> _TODO: Add a one-liner description here._

## Getting Started

```sh
# clone
git clone <repo-url>
cd $Name
```

## Contributing

Pull requests welcome!

## License

MIT © $year $gitName
"@

$mitLicense = @"
MIT License

Copyright (c) $year $gitName

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"@

# ── Template factories ────────────────────────────────────────────────────────
function Scaffold-Generic {
    New-Item -ItemType Directory -Path $projectPath | Out-Null
    Set-Content (Join-Path $projectPath 'README.md')    $readmeMd   -Encoding UTF8
    Set-Content (Join-Path $projectPath '.gitignore')   $commonGitignore -Encoding UTF8
    Set-Content (Join-Path $projectPath 'LICENSE')      $mitLicense -Encoding UTF8
}

function Scaffold-NodeTs {
    Scaffold-Generic
    $src = Join-Path $projectPath 'src'; New-Item -ItemType Directory $src | Out-Null
    $tests = Join-Path $projectPath 'tests'; New-Item -ItemType Directory $tests | Out-Null

    Set-Content (Join-Path $src 'index.ts') @"
export function greet(name: string): string {
  return `Hello, \${name}!`;
}
"@ -Encoding UTF8

    Set-Content (Join-Path $tests 'index.test.ts') @"
import { greet } from '../src/index';

test('greet returns hello', () => {
  expect(greet('World')).toBe('Hello, World!');
});
"@ -Encoding UTF8

    Set-Content (Join-Path $projectPath 'tsconfig.json') @"
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
"@ -Encoding UTF8

    Set-Content (Join-Path $projectPath 'package.json') @"
{
  "name": "$Name",
  "version": "0.1.0",
  "description": "",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "test": "jest",
    "lint": "eslint src --ext .ts",
    "dev": "ts-node src/index.ts"
  },
  "keywords": [],
  "author": "$gitName",
  "license": "MIT",
  "devDependencies": {
    "@types/jest": "^29.5.12",
    "@types/node": "^20.11.0",
    "@typescript-eslint/eslint-plugin": "^7.0.0",
    "@typescript-eslint/parser": "^7.0.0",
    "eslint": "^8.57.0",
    "jest": "^29.7.0",
    "ts-jest": "^29.1.2",
    "ts-node": "^10.9.2",
    "typescript": "^5.4.0"
  }
}
"@ -Encoding UTF8

    Add-Content (Join-Path $projectPath '.gitignore') "`ndist/`nnode_modules/`n*.tsbuildinfo`n.eslintcache"
}

function Scaffold-NodeJs {
    Scaffold-Generic
    $src = Join-Path $projectPath 'src'; New-Item -ItemType Directory $src | Out-Null
    $tests = Join-Path $projectPath 'tests'; New-Item -ItemType Directory $tests | Out-Null

    Set-Content (Join-Path $src 'index.js') @"
'use strict';

function greet(name) {
  return `Hello, \${name}!`;
}

module.exports = { greet };
"@ -Encoding UTF8

    Set-Content (Join-Path $projectPath 'package.json') @"
{
  "name": "$Name",
  "version": "0.1.0",
  "description": "",
  "main": "src/index.js",
  "scripts": {
    "test": "jest",
    "lint": "eslint src"
  },
  "author": "$gitName",
  "license": "MIT",
  "devDependencies": {
    "eslint": "^8.57.0",
    "jest": "^29.7.0"
  }
}
"@ -Encoding UTF8

    Add-Content (Join-Path $projectPath '.gitignore') "`nnode_modules/"
}

function Scaffold-Python {
    Scaffold-Generic
    $pkg = $Name -replace '-', '_'
    $srcPkg = Join-Path $projectPath "src/$pkg"
    New-Item -ItemType Directory $srcPkg | Out-Null
    New-Item -ItemType Directory (Join-Path $projectPath 'tests') | Out-Null

    Set-Content (Join-Path $srcPkg '__init__.py') "\"\"\"$Name package.\"\"\"`n" -Encoding UTF8
    Set-Content (Join-Path $srcPkg 'main.py') @"
def greet(name: str) -> str:
    return f"Hello, {name}!"


if __name__ == "__main__":
    print(greet("World"))
"@ -Encoding UTF8
    Set-Content (Join-Path $projectPath 'tests/__init__.py') '' -Encoding UTF8
    Set-Content (Join-Path $projectPath 'tests/test_main.py') @"
from $pkg.main import greet


def test_greet():
    assert greet("World") == "Hello, World!"
"@ -Encoding UTF8

    Set-Content (Join-Path $projectPath 'pyproject.toml') @"
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "$Name"
version = "0.1.0"
description = ""
authors = [{name = "$gitName", email = "$gitEmail"}]
license = {text = "MIT"}
requires-python = ">=3.11"
dependencies = []

[project.optional-dependencies]
dev = ["pytest", "ruff", "mypy"]

[tool.ruff]
line-length = 88
target-version = "py311"

[tool.pytest.ini_options]
testpaths = ["tests"]
"@ -Encoding UTF8

    Add-Content (Join-Path $projectPath '.gitignore') "`n__pycache__/`n*.pyc`n*.pyo`n.venv/`nvenv/`ndist/`nbuild/`n*.egg-info/`n.pytest_cache/`n.ruff_cache/`n.mypy_cache/"
}

function Scaffold-React {
    Write-Step 'Creating Vite + React + TypeScript app (requires Node.js & npm)'
    Scaffold-Generic
    Push-Location $RootDir
    $result = & npm create vite@latest $Name -- --template react-ts 2>&1
    Pop-Location
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm create vite failed — created basic scaffold only"
        Write-Info ($result -join "`n")
    }
}

function Scaffold-Nextjs {
    Write-Step 'Creating Next.js app (requires Node.js & npm)'
    Scaffold-Generic
    Push-Location $RootDir
    $result = & npx create-next-app@latest $Name --typescript --tailwind --app --eslint 2>&1
    Pop-Location
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "create-next-app failed — created basic scaffold only"
    }
}

function Scaffold-Dotnet {
    Write-Step 'Creating .NET console app (requires .NET SDK)'
    New-Item -ItemType Directory $projectPath | Out-Null
    & dotnet new console -n $Name -o $projectPath | Out-Null
    Set-Content (Join-Path $projectPath 'README.md') $readmeMd -Encoding UTF8
    Add-Content (Join-Path $projectPath '.gitignore') (& dotnet new gitignore --dry-run 2>$null | Out-String)
}

function Scaffold-Rust {
    Write-Step 'Creating Rust binary (requires Cargo)'
    Push-Location $RootDir
    & cargo new $Name 2>&1 | Out-Null
    Pop-Location
    Set-Content (Join-Path $projectPath 'README.md') $readmeMd -Encoding UTF8
}

function Scaffold-Go {
    $moduleName = Ask 'Go module name' "github.com/$(($gitName).ToLower() -replace ' ','-')/$Name"
    Write-Step 'Creating Go module'
    New-Item -ItemType Directory $projectPath | Out-Null
    Push-Location $projectPath
    & go mod init $moduleName | Out-Null
    Pop-Location

    Set-Content (Join-Path $projectPath 'main.go') @"
package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
"@ -Encoding UTF8

    Set-Content (Join-Path $projectPath 'README.md') $readmeMd -Encoding UTF8
    Add-Content (Join-Path $projectPath '.gitignore') "`n/dist`n*.exe"
}

function Scaffold-Bash {
    Scaffold-Generic
    New-Item -ItemType Directory (Join-Path $projectPath 'bin') | Out-Null
    New-Item -ItemType Directory (Join-Path $projectPath 'tests') | Out-Null

    $entryScript = Join-Path $projectPath "bin/$Name.sh"
    Set-Content $entryScript @"
#!/usr/bin/env bash
set -euo pipefail

main() {
    echo "Hello from $Name!"
}

main "`$@"
"@ -Encoding UTF8

    Set-Content (Join-Path $projectPath 'tests/test_main.sh') @"
#!/usr/bin/env bash
set -euo pipefail

source "``dirname "`$0"``/../bin/$Name.sh"

test_greet() {
    output=`$(main)
    [[ "`$output" == *"Hello"* ]] || { echo "FAIL: unexpected output: `$output"; exit 1; }
    echo "PASS: test_greet"
}

test_greet
"@ -Encoding UTF8
}

# ── Run scaffold ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Step "Scaffolding '$Name' as '$Template' in $RootDir"
Write-Host ''

switch ($Template) {
    'node-ts' { Scaffold-NodeTs }
    'node-js' { Scaffold-NodeJs }
    'python'  { Scaffold-Python }
    'react'   { Scaffold-React }
    'nextjs'  { Scaffold-Nextjs }
    'dotnet'  { Scaffold-Dotnet }
    'rust'    { Scaffold-Rust }
    'go'      { Scaffold-Go }
    'bash'    { Scaffold-Bash }
    default   { Scaffold-Generic }
}

Write-Done "Project created at $projectPath"

# ── Git init ──────────────────────────────────────────────────────────────────
if (-not $NoGit -and (Test-Path $projectPath)) {
    $doGit = (Ask 'Initialise git repo? (y/n)' 'y') -eq 'y'
    if ($doGit) {
        Write-Step 'Running git init'
        Push-Location $projectPath
        git init | Out-Null
        git add . | Out-Null
        git commit -m 'chore: initial scaffold' | Out-Null
        Pop-Location
        Write-Done 'git init and initial commit done'
    }
}

# ── Open in VS Code ───────────────────────────────────────────────────────────
$openCode = (Ask 'Open in VS Code? (y/n)' 'y') -eq 'y'
if ($openCode) {
    Start-Process 'code' $projectPath -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '  ✅  All done! Happy building.' -ForegroundColor Green
Write-Host ''
