Add-Type -TypeDefinition @"
using System.ComponentModel;

public class LocalBranchInfo : INotifyPropertyChanged
{
    private string _branch;
    private string[] _branches;

    public string Branch
    {
        get { return _branch; }
        set
        {
            if (_branch != value)
            {
                _branch = value;
                OnPropertyChanged("Branch");
            }
        }
    }

    public string[] Branches
    {
        get { return _branches; }
        set
        {
            if (_branches != value)
            {
                _branches = value;
                OnPropertyChanged("Branches");
            }
        }
    }

    public event PropertyChangedEventHandler PropertyChanged;

    protected virtual void OnPropertyChanged(string propertyName)
    {
        if(PropertyChanged != null)
            PropertyChanged(this, new PropertyChangedEventArgs(propertyName));
    }
}
"@

$localBranchInfo = New-Object LocalBranchInfo

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

function Get-BranchNames {
    # Get the branch names from the remote repository using git command
    return git ls-remote --heads origin | Select-String -Pattern "refs/heads/(develop-.*|.*-develop|develop)$"  | ForEach-Object {  $($_ -replace ".*refs/heads", "").Substring(1)  }
}

function Show(){

    Add-Type -AssemblyName System.Windows.Forms
	
	$title = 'Set feature branch';
	
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.Size = New-Object System.Drawing.Size(615, 140)
    $form.Minimumsize = $form.MaximumSize = $form.Size
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $form.MinimizeBox = $false

    $control = New-Object System.Windows.Forms.Label
    $control.Location = New-Object System.Drawing.Point(10, 8)
    $control.Size = New-Object System.Drawing.Size(200, 18)
    $control.Text = "Develop branches:"

    $form.Controls.Add($control)

    $control = New-Object System.Windows.Forms.ComboBox
    $control.Location = New-Object System.Drawing.Point(10, 28)
    $control.Size = New-Object System.Drawing.Size(575, 32)
    $form.Controls.Add($control)
	
    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Location = New-Object System.Drawing.Point(538, 64)
    $okBtn.Size = New-Object System.Drawing.Size(45, 28)
    $okBtn.Text = "Set"
    $okBtn.DialogResult = 'Ok'
    # $okBtn.DataBindings.Add("Enabled", $localBranchInfo, "CanEdit") | Out-Null

    $form.Controls.Add($okBtn)

    $form.AcceptButton = $okBtn
	
	$form.add_Shown({
		$form.Text = "$title - Fetching branches..."
		$form.Enabled = $false
		$branchNames = Get-BranchNames
		$current = Get-Current
	
		Write-Host "Current feature branch is $current"
		
		$form.Text = $title
		
		$form.Enabled = $true
		$control.Items.Clear()
		$control.Items.AddRange($branchNames)
		
		if($current)
		{
			$control.SelectedIndex = $control.Items.IndexOf($current)
		}
	})

    [System.Windows.Forms.Application]::EnableVisualStyles()
	
    if ($form.ShowDialog() -eq 'Ok') 
    {
        try
        {
			echo $control.SelectedItem
			
			if($control.SelectedItem)
			{
				Set-Current $control.SelectedItem
			}
			else 
			{
				[System.Windows.Forms.MessageBox]::Show('No branch has been selected', 'App Error', 'OK', 'Error')
			}
        }
        catch
        {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'App Error', 'OK', 'Error')
        }
    }
}

Show