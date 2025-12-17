DisableExpiredUsers:
This script is made to be put in Task Scheduler to be run every night, it's purpose is to disable user accounts when the accountExpires attribute (aka End Off) date has passed.(Because for some unknown reason, there is not any built-in functionalty for this.) There are two versions, the "-NoVerify" version does not verify that the disabled users actually are disabled after a set ammount of time. The configuration required before deploying is: Defining the log path at line 5, and making sure the account running the service can read the accountExpires attribute, as well as Write to the userAccountControl attribute, Copilot has put togheter a guide here:
1. Open ADUC
	* Launch Active Directory Users and Computers.
	* Right-click on the domain root (e.g., contoso.local) and select Delegate Control….
2. Start the Delegation Wizard
	* Click Next.
3. Add the User or Group
	* Click Add, select the account or group that should receive the permissions.
	* Click OK, then Next.
4. Choose "Create a custom task to delegate"
	* This option allows you to select specific objects and attributes.
	* Click Next.
5. Select Object Types
	* Choose Only the following objects in the folder.
	* Check User objects.
	* Click Next.
6. Select Permissions
	* Check Property-specific.
	* Scroll through the list and select:
		* Write userAccountControl (to disable accounts).
		* Read accountExpires (to read the account expiration date).
	* Click Next, then Finish.


EnableUsers:
This script is made to be put in Task Scheduler to be run every night, it's purpose is to enable user accounts based on information in a .txt file, it looks for the following format: user.name;yyyy-mm-dd and only activates users on the current date, so if a user has been disabled days after it being enabled by this script, it will not be enabled again if it remains in the list with the previous date.
The following configuration is required before running:
Set an example DN for documentation purposes at line 59, set default search base at line 62, set default input file path at line 65, and default log directory at line 68
The script is also prepared for sending emails to a given recipient if it encouters an error (only if it actually fails, not if it skips a user.) And that requires some configuration at lines 125-132
If you want the script to also remove any accountExpires attributes (End Off-date) when enabling a user, uncomment line 254.
The account running the script needs Write userAccountControl access to enable accounts, if you also want the script to remove accountExpires attributes, it also needs the following permissions:
* Write accountExpires
* Write accountRestriction
* Reset password
* Write lockoutTime
* Write general user attributes
* Create/delete objects
Use the guide for the DEU script to Delegate access.

RemoveUser:
This Script removes a Windows user account from a computer by using the Remove-CimInstance command. It prompts the user to enter a username, asks a second time before removing the user account.

Apart from removing the user from the computer and removing the account folder from C:\Users\ there is also an option to remove a folder if you have a seperate folder with the users username.