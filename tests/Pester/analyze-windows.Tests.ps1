$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$analyzeScript = Join-Path $scriptRoot 'analyze\analyze-windows.ps1'

Describe 'analyze-windows.ps1' {
    BeforeAll {
        . $analyzeScript
    }

    Context 'Mock report generation' {
        It 'generates a valid mock report with DryRun' {
            $outFile = Join-Path $env:TEMP 'hw-report-test.json'
            $report = & $analyzeScript -DryRun -OutputPath $outFile
            $report | Should Not BeNullOrEmpty
            $report.schemaVersion | Should Be '1.0.0'
            Test-Path $outFile | Should Be $true
            Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        }

        It 'mock report contains required install recommendation' {
            $report = New-MockHardwareReport
            $report.install.canInstall | Should Be $true
            $report.install.targetDisk | Should Be 0
            $report.install.suggestedRootGiB | Should BeGreaterThan 50
        }

        It 'mock report has Intel GPU for gaming profile' {
            $report = New-MockHardwareReport
            $report.gpu[0].name | Should Match 'Intel'
            $report.profiles.gaming | Should Be $true
        }
    }

    Context 'Schema validation' {
        It 'validates a complete report' {
            $report = New-MockHardwareReport
            { Test-HardwareReportSchema -Report $report } | Should Not Throw
        }

        It 'rejects report missing schemaVersion' {
            $report = New-MockHardwareReport
            $report.Remove('schemaVersion')
            { Test-HardwareReportSchema -Report $report } | Should Throw 'schemaVersion'
        }

        It 'rejects invalid schemaVersion' {
            $report = New-MockHardwareReport
            $report.schemaVersion = '0.0.1'
            { Test-HardwareReportSchema -Report $report } | Should Throw 'schemaVersion invalide'
        }
    }

    Context 'Export' {
        It 'writes valid JSON file' {
            $path = Join-Path $env:TEMP 'export-test-hw.json'
            $report = New-MockHardwareReport
            Export-HardwareReport -Report $report -Path $path
            $content = Get-Content $path -Raw | ConvertFrom-Json
            $content.system.model | Should Be 'HGE-WX6'
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Display scale computation' {
        It 'computes 1.5 for MagicBook panel (2520 native / 1680 logical)' {
            Get-DisplayScale -NativeWidth 2520 -LogicalWidth 1680 | Should Be 1.5
        }

        It 'computes 1.25 for 125% scaling' {
            Get-DisplayScale -NativeWidth 1920 -LogicalWidth 1536 | Should Be 1.25
        }

        It 'returns 1.0 when no scaling' {
            Get-DisplayScale -NativeWidth 1920 -LogicalWidth 1920 | Should Be 1.0
        }

        It 'returns 1.0 on invalid input' {
            Get-DisplayScale -NativeWidth 0 -LogicalWidth 1920 | Should Be 1.0
            Get-DisplayScale -NativeWidth 1920 -LogicalWidth 0 | Should Be 1.0
        }

        It 'keeps raw ratio when far from a 25% step' {
            Get-DisplayScale -NativeWidth 2880 -LogicalWidth 2160 | Should Be 1.33
        }

        It 'mock report uses native panel resolution with 1.5 scale' {
            $report = New-MockHardwareReport
            $report.display.primary.width | Should Be 2520
            $report.display.primary.height | Should Be 1680
            $report.display.primary.scale | Should Be 1.5
            $report.display.primary.refreshHz | Should Be 60
        }
    }

    Context 'Report export encoding' {
        It 'writes JSON without UTF-8 BOM' {
            $path = Join-Path $env:TEMP 'bom-test-hw.json'
            Export-HardwareReport -Report (New-MockHardwareReport) -Path $path
            $bytes = [System.IO.File]::ReadAllBytes($path)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Helper functions' {
        It 'converts bytes to GiB correctly' {
            Get-BytesAsGiB -Bytes 1073741824 | Should Be 1
        }

        It 'recommends install when unallocated space is sufficient' {
            $layout = @(@{
                diskNumber = 0
                unallocatedGiB = 314
            })
            $rec = Get-InstallRecommendation -DiskLayout $layout
            $rec.canInstall | Should Be $true
            $rec.suggestedRootGiB | Should BeGreaterThan 50
        }

        It 'rejects install when unallocated space is insufficient' {
            $layout = @(@{
                diskNumber = 0
                unallocatedGiB = 20
            })
            $rec = Get-InstallRecommendation -DiskLayout $layout
            $rec.canInstall | Should Be $false
        }
    }
}
