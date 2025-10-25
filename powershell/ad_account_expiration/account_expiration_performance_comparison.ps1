#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Performance comparison between sequential and parallel processing for AD account expiration monitoring.
.DESCRIPTION
    This script demonstrates the performance improvements achieved with parallel processing
    for large Active Directory environments with account expiration monitoring.
.NOTES
    Author: AD Admin
    Date: 2025-01-27
#>

param(
    [string]$TestDomain = "domainA.local",
    [string]$TestOU = "OU=Users,DC=domainA,DC=local",
    [int]$TestUserCount = 1000,
    [int]$BatchSize = 100,
    [int]$MaxConcurrentJobs = 5
)

function Test-SequentialAccountExpirationProcessing {
    <#
    .SYNOPSIS
        Tests sequential processing performance for account expiration
    #>
    param(
        [string]$DomainName,
        [string]$OUPath,
        [int]$UserCount
    )
    
    Write-Host "=== SEQUENTIAL ACCOUNT EXPIRATION PROCESSING TEST ===" -ForegroundColor Yellow
    $startTime = Get-Date
    
    try {
        # Simulate sequential processing
        $users = Get-ADUser -SearchBase $OUPath -Filter {Enabled -eq $true -and AccountExpirationDate -ne $null} -Properties @('DisplayName', 'SamAccountName', 'mail', 'AccountExpirationDate', 'PasswordLastSet', 'LastLogonDate') -Server $DomainName | Select-Object -First $UserCount
        
        $results = @()
        foreach ($user in $users) {
            # Simulate processing time
            Start-Sleep -Milliseconds 10
            
            if ($user.AccountExpirationDate -ne $null) {
                $expiryDate = $user.AccountExpirationDate
                $daysRemaining = ($expiryDate.Date - (Get-Date).Date).Days
                
                if ($daysRemaining -gt 0 -and $daysRemaining -le 15) {
                    $results += [PSCustomObject]@{
                        SamAccountName = $user.SamAccountName
                        DaysRemaining = $daysRemaining
                        AccountExpirationDate = $expiryDate.ToString("dd.MM.yyyy")
                    }
                }
            }
        }
        
        $endTime = Get-Date
        $processingTime = $endTime - $startTime
        
        Write-Host "Sequential Account Expiration Processing Results:" -ForegroundColor Green
        Write-Host "  Users Processed: $($users.Count)"
        Write-Host "  Results Found: $($results.Count)"
        Write-Host "  Processing Time: $($processingTime.TotalSeconds) seconds"
        Write-Host "  Average Time per User: $([Math]::Round($processingTime.TotalMilliseconds / $users.Count, 2)) ms"
        
        return @{
            ProcessingTime = $processingTime
            UserCount = $users.Count
            ResultCount = $results.Count
            Method = "Sequential Account Expiration"
        }
    }
    catch {
        Write-Host "Sequential account expiration processing error: $_" -ForegroundColor Red
        return $null
    }
}

function Test-ParallelAccountExpirationProcessing {
    <#
    .SYNOPSIS
        Tests parallel processing performance for account expiration
    #>
    param(
        [string]$DomainName,
        [string]$OUPath,
        [int]$UserCount,
        [int]$BatchSize,
        [int]$MaxConcurrentJobs
    )
    
    Write-Host "=== PARALLEL ACCOUNT EXPIRATION PROCESSING TEST ===" -ForegroundColor Yellow
    $startTime = Get-Date
    
    try {
        # Get all users first
        $users = Get-ADUser -SearchBase $OUPath -Filter {Enabled -eq $true -and AccountExpirationDate -ne $null} -Properties @('DisplayName', 'SamAccountName', 'mail', 'AccountExpirationDate', 'PasswordLastSet', 'LastLogonDate') -Server $DomainName | Select-Object -First $UserCount
        
        $results = @()
        $jobs = @()
        
        # Create batches
        $batches = [Math]::Ceiling($users.Count / $BatchSize)
        Write-Host "Creating $batches batches of $BatchSize users each for account expiration..."
        
        for ($i = 0; $i -lt $batches; $i++) {
            $batchUsers = $users | Select-Object -Skip ($i * $BatchSize) -First $BatchSize
            
            # Start parallel job
            $job = Start-Job -ScriptBlock {
                param($BatchUsers, $DomainName)
                
                $batchResults = @()
                foreach ($user in $BatchUsers) {
                    # Simulate processing time
                    Start-Sleep -Milliseconds 10
                    
                    if ($user.AccountExpirationDate -ne $null) {
                        $expiryDate = $user.AccountExpirationDate
                        $daysRemaining = ($expiryDate.Date - (Get-Date).Date).Days
                        
                        if ($daysRemaining -gt 0 -and $daysRemaining -le 15) {
                            $batchResults += [PSCustomObject]@{
                                SamAccountName = $user.SamAccountName
                                DaysRemaining = $daysRemaining
                                AccountExpirationDate = $expiryDate.ToString("dd.MM.yyyy")
                            }
                        }
                    }
                }
                return $batchResults
            } -ArgumentList $batchUsers, $DomainName
            
            $jobs += $job
            
            # Control concurrent jobs
            if ($jobs.Count -ge $MaxConcurrentJobs) {
                Write-Host "Waiting for jobs to complete (max concurrent: $MaxConcurrentJobs)..."
                
                $completedJobs = $jobs | Where-Object { $_.State -eq 'Completed' }
                foreach ($completedJob in $completedJobs) {
                    $jobResults = Receive-Job -Job $completedJob
                    $results += $jobResults
                    Remove-Job -Job $completedJob
                }
                
                $jobs = $jobs | Where-Object { $_.State -ne 'Completed' }
            }
        }
        
        # Wait for remaining jobs
        Write-Host "Waiting for remaining jobs..."
        $jobs | Wait-Job | Out-Null
        
        # Collect all results
        foreach ($job in $jobs) {
            $jobResults = Receive-Job -Job $job
            $results += $jobResults
            Remove-Job -Job $job
        }
        
        $endTime = Get-Date
        $processingTime = $endTime - $startTime
        
        Write-Host "Parallel Account Expiration Processing Results:" -ForegroundColor Green
        Write-Host "  Users Processed: $($users.Count)"
        Write-Host "  Results Found: $($results.Count)"
        Write-Host "  Processing Time: $($processingTime.TotalSeconds) seconds"
        Write-Host "  Average Time per User: $([Math]::Round($processingTime.TotalMilliseconds / $users.Count, 2)) ms"
        Write-Host "  Batches Created: $batches"
        Write-Host "  Max Concurrent Jobs: $MaxConcurrentJobs"
        
        return @{
            ProcessingTime = $processingTime
            UserCount = $users.Count
            ResultCount = $results.Count
            Method = "Parallel Account Expiration"
            Batches = $batches
            MaxConcurrentJobs = $MaxConcurrentJobs
        }
    }
    catch {
        Write-Host "Parallel account expiration processing error: $_" -ForegroundColor Red
        return $null
    }
}

function Show-AccountExpirationPerformanceComparison {
    <#
    .SYNOPSIS
        Shows performance comparison between sequential and parallel account expiration processing
    #>
    param(
        [hashtable]$SequentialResults,
        [hashtable]$ParallelResults
    )
    
    if ($SequentialResults -and $ParallelResults) {
        $improvement = ($SequentialResults.ProcessingTime.TotalSeconds - $ParallelResults.ProcessingTime.TotalSeconds) / $SequentialResults.ProcessingTime.TotalSeconds * 100
        
        Write-Host "`n=== ACCOUNT EXPIRATION PERFORMANCE COMPARISON ===" -ForegroundColor Cyan
        Write-Host "Sequential Account Expiration Processing:" -ForegroundColor Yellow
        Write-Host "  Time: $($SequentialResults.ProcessingTime.TotalSeconds) seconds"
        Write-Host "  Users: $($SequentialResults.UserCount)"
        Write-Host "  Results: $($SequentialResults.ResultCount)"
        
        Write-Host "`nParallel Account Expiration Processing:" -ForegroundColor Yellow
        Write-Host "  Time: $($ParallelResults.ProcessingTime.TotalSeconds) seconds"
        Write-Host "  Users: $($ParallelResults.UserCount)"
        Write-Host "  Results: $($ParallelResults.ResultCount)"
        Write-Host "  Batches: $($ParallelResults.Batches)"
        Write-Host "  Max Concurrent Jobs: $($ParallelResults.MaxConcurrentJobs)"
        
        Write-Host "`nPerformance Improvement:" -ForegroundColor Green
        Write-Host "  Time Saved: $([Math]::Round($SequentialResults.ProcessingTime.TotalSeconds - $ParallelResults.ProcessingTime.TotalSeconds, 2)) seconds"
        Write-Host "  Improvement: $([Math]::Round($improvement, 2))%"
        Write-Host "  Speed Multiplier: $([Math]::Round($SequentialResults.ProcessingTime.TotalSeconds / $ParallelResults.ProcessingTime.TotalSeconds, 2))x"
        
        # Calculate theoretical maximum improvement
        $theoreticalMax = $ParallelResults.MaxConcurrentJobs
        $actualImprovement = $SequentialResults.ProcessingTime.TotalSeconds / $ParallelResults.ProcessingTime.TotalSeconds
        $efficiency = ($actualImprovement / $theoreticalMax) * 100
        
        Write-Host "`nEfficiency Analysis:" -ForegroundColor Magenta
        Write-Host "  Theoretical Max Improvement: ${theoreticalMax}x"
        Write-Host "  Actual Improvement: ${actualImprovement}x"
        Write-Host "  Efficiency: $([Math]::Round($efficiency, 2))%"
    }
}

function Show-AccountExpirationGuidelines {
    <#
    .SYNOPSIS
        Shows guidelines for account expiration monitoring
    #>
    
    Write-Host "`n=== ACCOUNT EXPIRATION MONITORING GUIDELINES ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Account Expiration vs Password Expiration:" -ForegroundColor Yellow
    Write-Host "• Account Expiration: Kullanıcı hesabının tamamen sona ermesi"
    Write-Host "• Password Expiration: Sadece parolanın sona ermesi"
    Write-Host "• Account Expiration daha kritik - hesap tamamen kilitlenir"
    Write-Host ""
    
    Write-Host "Monitoring Best Practices:" -ForegroundColor Green
    Write-Host "• 30 gün önceden uyarı verin"
    Write-Host "• 15 gün önceden hatırlatma gönderin"
    Write-Host "• 7 gün önceden son uyarı"
    Write-Host "• 1 gün önceden kritik uyarı"
    Write-Host ""
    
    Write-Host "BatchSize Seçimi (Account Expiration):" -ForegroundColor Yellow
    Write-Host "• 25-50:   Küçük sistemler, düşük RAM"
    Write-Host "• 100-150:  Standart sistemler (ÖNERİLEN)"
    Write-Host "• 200-300: Yüksek performanslı sistemler"
    Write-Host "• 500+:    Sadece çok güçlü sistemler"
    Write-Host ""
    
    Write-Host "MaxConcurrentJobs Seçimi (Account Expiration):" -ForegroundColor Yellow
    Write-Host "• 2-3:     Düşük özellikli sistemler"
    Write-Host "• 4-6:     Standart sistemler (ÖNERİLEN)"
    Write-Host "• 7-10:    Yüksek performanslı sistemler"
    Write-Host "• 10+:     Sadece çok güçlü sistemler"
    Write-Host ""
    
    Write-Host "Account Expiration İpuçları:" -ForegroundColor Magenta
    Write-Host "• Account expiration tarihi olmayan kullanıcılar filtrelenir"
    Write-Host "• Sadece aktif hesaplar kontrol edilir"
    Write-Host "• Son giriş tarihi bilgisi de toplanır"
    Write-Host "• Parola son değişim tarihi bilgisi de toplanır"
    Write-Host ""
    
    Write-Host "Test Önerileri:" -ForegroundColor Magenta
    Write-Host "1. Küçük değerlerle başlayın"
    Write-Host "2. Sistem kaynaklarını izleyin"
    Write-Host "3. Performansı ölçün"
    Write-Host "4. Değerleri kademeli olarak artırın"
    Write-Host "5. Optimum noktayı bulun"
}

# ============================================================
# MAIN EXECUTION
# ============================================================

Write-Host "Active Directory Account Expiration - Performance Comparison" -ForegroundColor Cyan
Write-Host "Domain: $TestDomain" -ForegroundColor White
Write-Host "OU: $TestOU" -ForegroundColor White
Write-Host "Test User Count: $TestUserCount" -ForegroundColor White
Write-Host "Batch Size: $BatchSize" -ForegroundColor White
Write-Host "Max Concurrent Jobs: $MaxConcurrentJobs" -ForegroundColor White
Write-Host ""

# Test sequential processing
$sequentialResults = Test-SequentialAccountExpirationProcessing -DomainName $TestDomain -OUPath $TestOU -UserCount $TestUserCount

Write-Host ""

# Test parallel processing
$parallelResults = Test-ParallelAccountExpirationProcessing -DomainName $TestDomain -OUPath $TestOU -UserCount $TestUserCount -BatchSize $BatchSize -MaxConcurrentJobs $MaxConcurrentJobs

# Show comparison
Show-AccountExpirationPerformanceComparison -SequentialResults $sequentialResults -ParallelResults $parallelResults

# Show guidelines
Show-AccountExpirationGuidelines

Write-Host "`n=== RECOMMENDATIONS FOR ACCOUNT EXPIRATION ===" -ForegroundColor Cyan
Write-Host "For optimal account expiration monitoring:" -ForegroundColor White
Write-Host "• Use Batch Size: 50-200 users per batch" -ForegroundColor Green
Write-Host "• Use Max Concurrent Jobs: 3-8 (depending on server capacity)" -ForegroundColor Green
Write-Host "• Monitor memory usage during processing" -ForegroundColor Green
Write-Host "• Consider using PowerShell 7+ for better performance" -ForegroundColor Green
Write-Host "• Set up automated monitoring schedules" -ForegroundColor Green
Write-Host "• Implement email notifications for critical accounts" -ForegroundColor Green
