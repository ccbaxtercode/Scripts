#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Performance comparison between sequential and parallel processing for AD password expiration monitoring.
.DESCRIPTION
    This script demonstrates the performance improvements achieved with parallel processing
    for large Active Directory environments.
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

function Test-SequentialProcessing {
    <#
    .SYNOPSIS
        Tests sequential processing performance
    #>
    param(
        [string]$DomainName,
        [string]$OUPath,
        [int]$UserCount
    )
    
    Write-Host "=== SEQUENTIAL PROCESSING TEST ===" -ForegroundColor Yellow
    $startTime = Get-Date
    
    try {
        # Simulate sequential processing
        $users = Get-ADUser -SearchBase $OUPath -Filter {Enabled -eq $true} -Properties @('DisplayName', 'SamAccountName', 'mail', 'msDS-UserPasswordExpiryTimeComputed') -Server $DomainName | Select-Object -First $UserCount
        
        $results = @()
        foreach ($user in $users) {
            # Simulate processing time
            Start-Sleep -Milliseconds 10
            
            if ($user.'msDS-UserPasswordExpiryTimeComputed' -ne $null) {
                $expiryDate = [DateTime]::FromFileTime($user.'msDS-UserPasswordExpiryTimeComputed')
                $daysRemaining = ($expiryDate.Date - (Get-Date).Date).Days
                
                if ($daysRemaining -gt 0 -and $daysRemaining -le 15) {
                    $results += [PSCustomObject]@{
                        SamAccountName = $user.SamAccountName
                        DaysRemaining = $daysRemaining
                    }
                }
            }
        }
        
        $endTime = Get-Date
        $processingTime = $endTime - $startTime
        
        Write-Host "Sequential Processing Results:" -ForegroundColor Green
        Write-Host "  Users Processed: $($users.Count)"
        Write-Host "  Results Found: $($results.Count)"
        Write-Host "  Processing Time: $($processingTime.TotalSeconds) seconds"
        Write-Host "  Average Time per User: $([Math]::Round($processingTime.TotalMilliseconds / $users.Count, 2)) ms"
        
        return @{
            ProcessingTime = $processingTime
            UserCount = $users.Count
            ResultCount = $results.Count
            Method = "Sequential"
        }
    }
    catch {
        Write-Host "Sequential processing error: $_" -ForegroundColor Red
        return $null
    }
}

function Test-ParallelProcessing {
    <#
    .SYNOPSIS
        Tests parallel processing performance
    #>
    param(
        [string]$DomainName,
        [string]$OUPath,
        [int]$UserCount,
        [int]$BatchSize,
        [int]$MaxConcurrentJobs
    )
    
    Write-Host "=== PARALLEL PROCESSING TEST ===" -ForegroundColor Yellow
    $startTime = Get-Date
    
    try {
        # Get all users first
        $users = Get-ADUser -SearchBase $OUPath -Filter {Enabled -eq $true} -Properties @('DisplayName', 'SamAccountName', 'mail', 'msDS-UserPasswordExpiryTimeComputed') -Server $DomainName | Select-Object -First $UserCount
        
        $results = @()
        $jobs = @()
        
        # Create batches
        $batches = [Math]::Ceiling($users.Count / $BatchSize)
        Write-Host "Creating $batches batches of $BatchSize users each..."
        
        for ($i = 0; $i -lt $batches; $i++) {
            $batchUsers = $users | Select-Object -Skip ($i * $BatchSize) -First $BatchSize
            
            # Start parallel job
            $job = Start-Job -ScriptBlock {
                param($BatchUsers, $DomainName)
                
                $batchResults = @()
                foreach ($user in $BatchUsers) {
                    # Simulate processing time
                    Start-Sleep -Milliseconds 10
                    
                    if ($user.'msDS-UserPasswordExpiryTimeComputed' -ne $null) {
                        $expiryDate = [DateTime]::FromFileTime($user.'msDS-UserPasswordExpiryTimeComputed')
                        $daysRemaining = ($expiryDate.Date - (Get-Date).Date).Days
                        
                        if ($daysRemaining -gt 0 -and $daysRemaining -le 15) {
                            $batchResults += [PSCustomObject]@{
                                SamAccountName = $user.SamAccountName
                                DaysRemaining = $daysRemaining
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
        
        Write-Host "Parallel Processing Results:" -ForegroundColor Green
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
            Method = "Parallel"
            Batches = $batches
            MaxConcurrentJobs = $MaxConcurrentJobs
        }
    }
    catch {
        Write-Host "Parallel processing error: $_" -ForegroundColor Red
        return $null
    }
}

function Show-PerformanceComparison {
    <#
    .SYNOPSIS
        Shows performance comparison between sequential and parallel processing
    #>
    param(
        [hashtable]$SequentialResults,
        [hashtable]$ParallelResults
    )
    
    if ($SequentialResults -and $ParallelResults) {
        $improvement = ($SequentialResults.ProcessingTime.TotalSeconds - $ParallelResults.ProcessingTime.TotalSeconds) / $SequentialResults.ProcessingTime.TotalSeconds * 100
        
        Write-Host "`n=== PERFORMANCE COMPARISON ===" -ForegroundColor Cyan
        Write-Host "Sequential Processing:" -ForegroundColor Yellow
        Write-Host "  Time: $($SequentialResults.ProcessingTime.TotalSeconds) seconds"
        Write-Host "  Users: $($SequentialResults.UserCount)"
        Write-Host "  Results: $($SequentialResults.ResultCount)"
        
        Write-Host "`nParallel Processing:" -ForegroundColor Yellow
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

# ============================================================
# MAIN EXECUTION
# ============================================================

Write-Host "Active Directory Password Expiration - Performance Comparison" -ForegroundColor Cyan
Write-Host "Domain: $TestDomain" -ForegroundColor White
Write-Host "OU: $TestOU" -ForegroundColor White
Write-Host "Test User Count: $TestUserCount" -ForegroundColor White
Write-Host "Batch Size: $BatchSize" -ForegroundColor White
Write-Host "Max Concurrent Jobs: $MaxConcurrentJobs" -ForegroundColor White
Write-Host ""

# Test sequential processing
$sequentialResults = Test-SequentialProcessing -DomainName $TestDomain -OUPath $TestOU -UserCount $TestUserCount

Write-Host ""

# Test parallel processing
$parallelResults = Test-ParallelProcessing -DomainName $TestDomain -OUPath $TestOU -UserCount $TestUserCount -BatchSize $BatchSize -MaxConcurrentJobs $MaxConcurrentJobs

# Show comparison
Show-PerformanceComparison -SequentialResults $sequentialResults -ParallelResults $parallelResults

Write-Host "`n=== RECOMMENDATIONS ===" -ForegroundColor Cyan
Write-Host "For optimal performance with large user bases:" -ForegroundColor White
Write-Host "• Use Batch Size: 50-200 users per batch" -ForegroundColor Green
Write-Host "• Use Max Concurrent Jobs: 3-8 (depending on server capacity)" -ForegroundColor Green
Write-Host "• Monitor memory usage during processing" -ForegroundColor Green
Write-Host "• Consider using PowerShell 7+ for better performance" -ForegroundColor Green
Write-Host "• Use -ThrottleLimit parameter for Get-ADUser in PowerShell 7+" -ForegroundColor Green
