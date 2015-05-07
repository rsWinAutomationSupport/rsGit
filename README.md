# rsGit

rsGit DSC resource can be used to interact with a remote GitHub repository. It currently only works for the following use-cases:

- **Clone** (default) - disregard any local changes and ensure that local repo is always in sync with origin
- **CopyOnly** - Clone remote repo if it does not exist and keep local changes without syncing again. If repo config changes, local change will be removed and repo will be synced again.
- Merge/push operations are not implemented at this time.

Usage Examples:

Clone a remote repository and keep it in sync. This configuration will result in any local changes to local repository and its contents to always be reset to match remote:

    rsGit Git
    {
    	Name = "rsGit"
    	Source = "https://github.com/rsWinAutomationSupport/rsGit.git"
    	Destination = "C:\Program Files\WindowsPowerShell\Modules\"
    	Branch = "master"
    	Ensure = "Present"
    }
    rsGit Git1_0
    {
    	Name = "rsGit_1_0"
    	Source = "https://github.com/rsWinAutomationSupport/rsGit.git"
    	Destination = "C:\Program Files\WindowsPowerShell\Modules\1.0\"
    	Branch = "v1.0"
    	Ensure = "Present"
    	Mode = "Clone"
    }

Clone the repo and keep its settings consistent with DSC configuration, but any local content changes will remain in place. Changes will not, however, be committed  to remote repository. Changes made to the local repository settings or DSC configuration will force as re-sync and all local change will be lost: 

    rsGit GitZip
    {
    	Name = "Git_Zip"
    	Source = "https://github.com/rsWinAutomationSupport/rsGit.git"
    	Destination = "C:\Program Files\WindowsPowerShell\Modules\"
    	DestinationZip = "C:\Program Files\WindowsPowerShell\DscService\Modules"
    	Branch = "v1.0"
    	Ensure = "Present"
    	Mode = "Clone"
    }

