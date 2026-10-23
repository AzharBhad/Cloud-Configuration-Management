When building a new Microsoft Entra ID (Azure AD), Microsoft 365, and Intune cloud environment, most enterprises create a combination of static groups (manually managed) and dynamic groups (rule-based). While naming standards differ, the group types are remarkably similar across organizations.

1. Core Static Groups

These are typically used for administrative access, support teams, exception handling, and licensing.

Administrative Groups
GRP-GlobalAdmins
GRP-PrivilegedRoleAdmins
GRP-HelpDesk
GRP-DesktopSupport
GRP-IdentityAdmins
GRP-SecurityAdmins
GRP-DeviceAdmins
GRP-IntuneAdmins


Purpose:

Assign Entra roles
PIM role activation
Tiered administration
Licensing Groups
LIC-M365-E5
LIC-M365-E3
LIC-EMS-E5
LIC-PowerBI-Pro
LIC-Project
LIC-Visio


Purpose:

Group-based licensing
Easier license management
Application Access Groups
APP-Salesforce-Users
APP-ServiceNow-Users
APP-VPN-Users
APP-Workday-Users
APP-Citrix-Users


Purpose:

Enterprise application assignments
SSO access control
Shared Resource Groups
SHR-Finance-Share
SHR-HR-Share
SHR-Engineering-Share
MAIL-Announcement-All


Purpose:

SharePoint permissions
File share permissions
Distribution lists
Special Exception Groups
EXC-MFA-Bypass
EXC-CA-Excluded
EXC-Device-Enrollment


Purpose:

Temporary exceptions
Conditional Access exclusions
2. Common Dynamic User Groups

Dynamic groups automatically update using user attributes.

All Employees
DYN-AllEmployees


Rule:

(user.accountEnabled -eq true)

Department-Based Groups
DYN-HR
DYN-Finance
DYN-Engineering
DYN-Sales
DYN-Marketing


Rule Example:

(user.department -eq "Finance")

Location-Based Groups
DYN-USA
DYN-Canada
DYN-Singapore
DYN-Europe


Rule Example:

(user.country -eq "United States")

Job Function Groups
DYN-Managers
DYN-Contractors
DYN-Interns
DYN-Executives


Rule Example:

(user.jobTitle -contains "Manager")

Company Groups

Useful in mergers or multiple entities.

DYN-HCL
DYN-Microsoft
DYN-Contoso


Rule:

(user.companyName -eq "HCL")

3. Common Dynamic Device Groups

These are extremely important for Intune and device management.

Windows Devices
DYN-Windows


Rule:

(device.deviceOSType -eq "Windows")

macOS Devices
DYN-macOS


Rule:

(device.deviceOSType -eq "MacMDM")

iOS/iPadOS Devices
DYN-iOS


Rule:

(device.deviceOSType -eq "iPhone")

Android Devices
DYN-Android


Rule:

(device.deviceOSType -eq "Android")

Linux Devices
DYN-Linux


Rule:

(device.deviceOSType -eq "Linux")

4. Entra Device Join-State Groups

Especially useful for reporting and Conditional Access.

Entra Joined
DYN-EntraJoined


Rule:

(device.trustType -eq "AzureAD")

Entra Hybrid Joined
DYN-HybridJoined


Rule:

(device.trustType -eq "ServerAD")

Entra Registered
DYN-EntraRegistered


Rule:

(device.trustType -eq "Workplace")

5. Endpoint Management Groups (Intune)

Most mature enterprises create deployment rings.

Pilot Ring
INT-Pilot


Purpose:

IT staff
First deployment targets
Early Adopters
INT-Ring1

Broad Deployment
INT-Ring2

Production
INT-Ring3


Used for:

Windows Update for Business
Configuration Profiles
Compliance Policies
Security Baselines
6. Security & Conditional Access Groups
MFA Groups
SEC-MFA-AllUsers
SEC-MFA-Admins

Authentication Groups
SEC-Passwordless
SEC-FIDO2
SEC-WindowsHello

Conditional Access Targeting
CA-AllUsers
CA-PrivilegedUsers
CA-RemoteWorkers
CA-GuestUsers
CA-ServiceAccounts

7. Guest and B2B Groups
DYN-Guests
DYN-Vendors
DYN-Partners


Rule Example:

(user.userType -eq "Guest")

Enterprise "Day 1" Baseline

If I were designing a greenfield Microsoft 365 environment today, I would start with:

User Groups
DYN-AllEmployees
DYN-Managers
DYN-Contractors
DYN-Guests

Device Groups
DYN-Windows
DYN-macOS
DYN-iOS
DYN-Android
DYN-EntraJoined
DYN-HybridJoined
DYN-EntraRegistered

Deployment Rings
INT-Pilot
INT-Ring1
INT-Ring2
INT-Ring3

Licensing
LIC-M365-E5
LIC-PowerBI
LIC-Visio
LIC-Project

Security
CA-AllUsers
CA-Admins
SEC-MFA
SEC-Passwordless


This structure scales well from a few hundred users to hundreds of thousands of users and aligns with common Microsoft 365, Entra ID, and Intune enterprise deployments.
