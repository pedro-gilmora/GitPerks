function Get-Path-Hash
{
    $location = pwd | Select-Object | %{$_.ProviderPath}
	
	Write-Host "Working Directory: $location"
	
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($location)   
    return [Convert]::ToBase64String($bytes)
}

function Get-Current
{
    $locationHash = Get-Path-Hash
    $keyPath = "HKCU:\Software\GitVars\$locationHash"
    $property = "FeatureBranch"
	
	Write-Host "Registry variable: $keyPath\$property"

    try
    {
        return Get-ItemPropertyValue -Path $keyPath -Name $property -ErrorAction SilentlyContinue
    }
    catch
    {
        New-Item -Path $keyPath -Force
        New-ItemProperty -Path $keyPath -Name $property -Value '' -Type String -Force
        Write-Host "$keyPath created successfully"
        return $null
    }
}

function Check-PullOut
(
	[string] $pullOutput
)
{
	# Check if there were any conflicts
	while ($pullOutput -match 'CONFLICT') 
	{
		Write-Host "Conflicts detected. You should resolve them before continuing."
	
		Read-Host "Waiting for conflicts to be solved"
		
		$pullOutput = git rebase --continue
		
		# Check if the rebase was successful
		if ($LASTEXITCODE -ne 0) 
		{
			Write-Host "An error occurred while attempting to continue the rebase. Please resolve any remaining conflicts and try again."
			break
		}
	}
}

$current = Get-Current



if($current)
{	
	if ((Test-Path ".git/rebase-merge") -or (Test-Path ".git/rebase-apply")) 
	{
		Write-Host "A rebase is currently in progress. Please complete it before pulling."
		
		$pullOutput = git rebase --continue
		
		Check-PullOut $pullOutput
	}
	else
	{
		Write-Host "Perform pull rebase"

		$pullOutput = git pull origin $current --rebase --autostash

		Check-PullOut $pullOutput
	}		
	
	Read-Host "Wait"
}
else
{
    Write-Host "No feature branch was set"
}