Add-Type -TypeDefinition @"
using System.ComponentModel;

public class LocalBranchInfo : INotifyPropertyChanged
{
    private string _wINumber, _parentBranch, _branch, _commit;

    public string ParentBranch
    {
        get { return _parentBranch; }
        set
        {
            if (_parentBranch != value)
            {
                _parentBranch = value;
                OnPropertyChanged("CanEdit");
                OnPropertyChanged("CanSearch");
                OnPropertyChanged("ParentBranch");
            }
        }
    }

    public string WINumber
    {
        get { return _wINumber; }
        set
        {
            if (_wINumber != value)
            {
                _wINumber = value;
                OnPropertyChanged("WINumber");
                OnPropertyChanged("CanEdit");
            }
        }
    }

    public string Branch
    {
        get { return _branch; }
        set
        {
            if (_branch != value)
            {
                _branch = value;
                OnPropertyChanged("Branch");
                OnPropertyChanged("CanEdit");
            }
        }
    }

    public string Commit
    {
        get { return _commit; }
        set
        {
            if (_commit != value)
            {
                _commit = value;
                OnPropertyChanged("Commit");
                OnPropertyChanged("CanEdit");
            }
        }
    }

    public bool CanSearch
    {
        get { return ParentBranch != null && ParentBranch.Trim().Length > 0; }
    }

    public bool CanEdit
    {
        get { return CanSearch && (Commit != null && Commit.Trim().Length > 0) && (Branch != null && Branch.Trim().Length > 0); }
    }

    public event PropertyChangedEventHandler PropertyChanged;

    protected virtual void OnPropertyChanged(string propertyName)
    {
        if(PropertyChanged != null)
            PropertyChanged(this, new PropertyChangedEventArgs(propertyName));
    }
}
"@

function Find-Iteration(
    [PSCustomObject] $node,
    [string] $iterationName
)
{
    if ($iterationName -like "*$($node.name)") {
        return $node
    }

    if (-not $node.hasChildren) {
        return $null
    }

    foreach ($ch in $node.children | ForEach-Object { $_ }) 
    {
        return Find-Iteration -node $ch -iterationName $iterationName
    }

    return $null
}

$localBranchInfo = New-Object LocalBranchInfo

function Get-Path-Hash
{
    $location = pwd | Select-Object | %{$_.ProviderPath}
	
	Write-Host "Working Directory: $location"
	
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($location)   
    return [Convert]::ToBase64String($bytes)
}

function Get-BranchNames {
    # Get the branch names from the remote repository using git command
    return git ls-remote --heads origin | Select-String -Pattern "refs/heads/(develop-.*|.*-develop|develop)$"  | ForEach-Object {  $($_ -replace ".*refs/heads", "").Substring(1)  }
}

function Get-Current
{
    $locationHash = Get-Path-Hash
    $keyPath = "HKCU:\Software\GitVars\$locationHash"
    $property = "FeatureBranch"
	
	Write-Host "Registry variable: $keyPath\$property"
	
	try {
		# Try to get the property
		return Get-ItemPropertyValue -Path $keyPath -Name $property -ErrorAction SilentlyContinue
	} catch {
		# If the property does not exist, create it with the fallback value
		New-ItemProperty -Path $keyPath -Name $property -Value '' -Type String -Force -ErrorAction SilentlyContinue		
		return $null		
	}
}

function Set-Current(
	[string] $branchName
)
{
    $locationHash = Get-Path-Hash
    $keyPath = "HKCU:\Software\GitVars\$locationHash"
    $property = "FeatureBranch"
	
	try
	{
		Set-ItemProperty -Path $keyPath -Name $property -Value $branchName -Force -ErrorAction Stop
	}
	catch
	{
		New-Item -Path $keyPath -Force -ErrorAction SilentlyContinue
		New-ItemProperty -Path $keyPath -Name $property -Value $branchName -Type String -Force -ErrorAction SilentlyContinue
	}
}

function Search($a, $b)
{
    try 
    {
        $localBranchInfo.WINumber = $localBranchInfo.WINumber.Trim()

        if ($localBranchInfo.WINumber.Length -eq 0 -or $localBranchInfo.WINumber  -notmatch "^\d+$") { return; }

        $organization = "mcsystems"
        $project = "JN Bank"
        $workItemId = $localBranchInfo.WINumber
        $pat = "<PAT>"
        $patHeader = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        # Construct API URL
        $uri = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/${workItemId}"

        # Invoke REST API with Kerberos authentication
        $workItemInfo = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = $patHeader }
        $workItemNumber = $workItemInfo.id
        $workItemType = "$($workItemInfo.fields."System.WorkItemType")"
        $workItemTitle = $workItemInfo.fields."System.Title"
        $iterationPath = ($workItemInfo.fields."System.IterationPath") -split '\\', 2 | Select-Object -Last 1
        $sprintNumber = if ($iterationPath -match 'Sprint (\d+)') { $matches[1] } else { "-1" }


        $uri= "https://dev.azure.com/$organization/$project/_apis/wit/classificationnodes/Iterations/${iterationPath}?depth=2"
        
        $iterations = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = $patHeader }
        $targetIterationName = $workItemInfo.fields."System.IterationPath"
        $foundNode = Find-Iteration -node $iterations -iterationName $targetIterationName
        
        if ($foundNode) 
        {
            $startDate = $foundNode.attributes.startDate.ToDateTime($null).ToString('MMMdd')
            $finishDate = $foundNode.attributes.finishDate.ToDateTime($null).ToString('MMMdd')
            $localBranchInfo.Commit = (($workItemTitle  -replace '[''`\t]+', '-') -split '[:\-]', 2 | Select-Object -Last 1).Trim('-',' ')
            $branchName = ($localBranchInfo.Commit -replace '[^\w]+', '-').Trim('-',' ')
            $localBranchInfo.Branch = "sp$sprintNumber-$startDate-$finishDate/$workItemType-$workItemNumber-$branchName"
		}
    }
    catch 
    {
        $message = $_.Exception.Message
        try
        {
            $response = $_.Exception.Response
            if ($response -ne $null) {
                # Read the response stream
                $stream = [System.IO.Stream]$response.GetResponseStream()
                $streamReader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                $stream.Seek(0, 'Begin')
                $responseString = $streamReader.ReadToEnd() | ConvertFrom-Json

                # Now $responseString contains the content as a string
                [System.Windows.Forms.MessageBox]::Show($responseString.message, 'Server Error', 'OK', 'Error')
            }
            else {
                [System.Windows.Forms.MessageBox]::Show($message, 'App Error', 'OK', 'Error')
            }
        }
        catch
        {
            [System.Windows.Forms.MessageBox]::Show($message, 'App Error', 'OK', 'Error')
        }
    }
}

function Show(){

    Add-Type -AssemblyName System.Windows.Forms
	
	$title = 'Configure your branch info'

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.Size = New-Object System.Drawing.Size(595, 275)
    $form.Minimumsize = $form.MaximumSize = $form.Size
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $form.MinimizeBox = $false

    $control = New-Object System.Windows.Forms.Label
    $control.Location = New-Object System.Drawing.Point(10, 8)
    $control.Size = New-Object System.Drawing.Size(200, 18)
    $control.Text = "Parent branch:"

    $form.Controls.Add($control)

    $parentBranch = New-Object System.Windows.Forms.ComboBox
    $parentBranch.Location = New-Object System.Drawing.Point(10, 28)
    $parentBranch.Size = New-Object System.Drawing.Size(560, 32)
    $parentBranch.DataBindings.Add("Text", $localBranchInfo, "ParentBranch") | Out-Null
	
    $form.Controls.Add($parentBranch)	
	
	$featureBranch = ""
	
	$parentBranch.add_SelectedIndexChanged({
		
		$localBranchInfo.ParentBranch = $parentBranch.Text

		Set-Current $localBranchInfo.ParentBranch
			
		Write-Host "Current feature branch is '$($localBranchInfo.ParentBranch)'"
	})
	
	$form.add_Shown({
		$form.Text = "$title - Fetching branches..."
		$form.Enabled = $false
		$branchNames = Get-BranchNames
		
		$form.Text = $title
		
		$form.Enabled = $true
		$parentBranch.Items.Clear()
		$parentBranch.Items.AddRange($branchNames)
		
		if(($featureBranch = Get-Current))
		{
			$parentBranch.SelectedIndex = $parentBranch.Items.IndexOf($featureBranch)
			
			$localBranchInfo.ParentBranch = $featureBranch
			
			Write-Host "Current feature branch is '$($localBranchInfo.ParentBranch)'"
		}
	})

    $control = New-Object System.Windows.Forms.Label
    $control.Location = New-Object System.Drawing.Point(10, 54)
    $control.Size = New-Object System.Drawing.Size(200, 18)
    $control.Text = "Work Item Number:"
    $control.DataBindings.Add("Enabled", $localBranchInfo, "CanSearch") | Out-Null

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.TextBox
    $control.Location = New-Object System.Drawing.Point(10, 74)
    $control.Size = New-Object System.Drawing.Size(68, 32)
    $control.DataBindings.Add("Text", $localBranchInfo, "WINumber") | Out-Null
    $control.DataBindings.Add("Enabled", $localBranchInfo, "CanSearch") | Out-Null

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.Button
    $control.Location = New-Object System.Drawing.Point(84, 72)
    $control.Size = New-Object System.Drawing.Size(64, 24)
    $control.Text = "Search"
    $control.DataBindings.Add("Enabled", $localBranchInfo, "CanSearch") | Out-Null

    $control.add_Click({ 		
		$form.Text = "$title - Getting info...";
		$form.Enabled = $false
		
		Search;
		
		$form.Enabled = $true		
		$form.Text = $title
	})

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.Label
    $control.Location = New-Object System.Drawing.Point(10, 100)
    $control.Size = New-Object System.Drawing.Size(260, 20)
    $control.Text = "Branch Name:"

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.TextBox
    $control.Location = New-Object System.Drawing.Point(10, 120)
    $control.Size = New-Object System.Drawing.Size(560, 30)
    $control.DataBindings.Add("Text", $localBranchInfo, "Branch") | Out-Null
    $control.DataBindings.Add("Enabled", $localBranchInfo, "CanEdit") | Out-Null

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.Label
    $control.Location = New-Object System.Drawing.Point(10, 150)
    $control.Size = New-Object System.Drawing.Size(260, 20)
    $control.Text = "Commit message:"

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.TextBox
    $control.Location = New-Object System.Drawing.Point(10, 170)
    $control.Size = New-Object System.Drawing.Size(560, 30)
    $control.DataBindings.Add("Text", $localBranchInfo, "Commit") | Out-Null
    $control.DataBindings.Add("Enabled", $localBranchInfo, "CanEdit") | Out-Null

    $form.Controls.Add($control)

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Location = New-Object System.Drawing.Point(475, 198)
    $okBtn.Size = New-Object System.Drawing.Size(97, 28)
    $okBtn.Text = "Create branch"
    $okBtn.DialogResult = 'Ok'
    $okBtn.DataBindings.Add("Enabled", $localBranchInfo, "CanEdit") | Out-Null

    $form.Controls.Add($okBtn)

    $form.AcceptButton = $okBtn  

    [System.Windows.Forms.Application]::EnableVisualStyles()

    if ($form.ShowDialog() -eq 'Ok' -and $localBranchInfo.ParentBranch) 
    {
		# if($localBranchInfo.ParentBranch -ne $featureBranch)
		# {
			# Set-Current $localBranchInfo.ParentBranch
			# Write-Host "Changed parent branch from $featureBranch to " $localBranchInfo.ParentBranch
		# }
        try
        {
            git checkout -b $localBranchInfo.Branch $localBranchInfo.ParentBranch
			git pull origin --rebase --autostash $localBranchInfo.ParentBranch
            git commit -m  ($localBranchInfo.Commit + "


#$($localBranchInfo.WINumber)")
        }
        catch
        {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'App Error', 'OK', 'Error')
        }
    }
}

Show