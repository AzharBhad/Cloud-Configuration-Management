---
name: new-security-baseline
description: Create a Microsoft Intune security baseline profile (Windows 10 and later, Defender for Endpoint, Microsoft 365 Apps, Edge, Windows 365, HoloLens 2) or an Entra ID Conditional Access baseline (MFA, block legacy authentication) as an importable Microsoft Graph JSON file plus a README.md (purpose, policy summary, settings, prerequisites, step-by-step creation, Graph PowerShell import, assignment and conflicts, validation, troubleshooting, rollback, references), verified on Microsoft Learn, one folder per policy under "Security Baseline". Use whenever the user asks for a security baseline, a baseline profile, Microsoft-recommended hardening from the Endpoint security Security baselines page, a baseline version update, an Entra ID or identity baseline, or wants a baseline recreated from a screenshot or export, even if they only say "harden Windows with the Microsoft baseline" or "deploy the Edge baseline".
---

# New Intune security baseline

Create a Microsoft Intune **security baseline profile** for the user's tenant, as a folder in this
repository with a Graph JSON file and a README.

Task: the user's request (the text they typed with the skill, or their latest message).

> **Where to save the files.** When the user's repository is checked out, create the files at the
> paths below and commit as described. When there is no repository (for example in a claude.ai
> chat), create the same files with the same names and folder structure and give them to the user
> as downloadable files; skip the git steps.

If the request doesn't say which baseline, ask which one (list the types below). Everything else
has a sensible default: the latest version, Microsoft's recommended defaults, a pilot device group.

## What a security baseline is (and isn't)

A security baseline is a Microsoft-maintained **template of hundreds of recommended settings**
from one product team (Windows, Defender, Office, Edge, Windows 365). Admins create a **profile**
from it, keep the defaults or customize some values, and assign it. Knowing this shapes the work:

- **The baseline's defaults are the policy.** The deliverable records the baseline type and
  version, and **every setting the admin changed from the default** (with the reason). There's no
  value in copying hundreds of untouched defaults into the repo; link to the Learn reference page
  for them instead.
- **Versions matter.** Only the latest version can be used to create a new profile; older profiles
  become read-only and must be updated to the new version to change settings. Always check the
  current version on Microsoft Learn ("Use security baselines" > Available security baselines)
  instead of trusting memory, because Microsoft releases new versions several times a year.
- **Entra ID baselines are Conditional Access policies.** Intune baselines only configure devices.
  When the user asks for an Entra ID / identity baseline (MFA for all users, block legacy
  authentication, admin MFA, risky sign-ins), build **Conditional Access policies** instead, one
  folder each, following "Entra ID Conditional Access baseline" below. Microsoft documents the
  Conditional Access Graph schema fully, so these JSON files can be complete and importable.
- **Not this skill**: a single device setting (settings catalog policy - `new-configuration-policy`),
  checking devices for Conditional Access (compliance policy - `new-compliance-policy`), and
  Exchange/SharePoint/Teams tenant settings (say so; point to Microsoft Secure Score
  recommendations and Defender for Office 365 preset security policies).

## Steps

1. **Identify the baseline type and version** (see "Baseline types"). Confirm the latest version
   on Microsoft Learn and say which one you used.
2. **Gather the customizations.** From the request, a screenshot or an export: which settings
   differ from the baseline defaults. If none are given, keep all defaults and say so. Look up each
   customized setting on the baseline's Learn reference page (name, category, default) and its
   CSP page (meaning, allowed values, OS support).
3. **Check for conflicts** with what's already in the repo (see "Conflicts").
4. **Create the folder** (see "Where to put it").
5. **Write the JSON** (see "The JSON").
6. **Write `README.md`** (see "README.md").
7. **Check, commit and push** the new folder only (see "Before finishing").

## Baseline types

Verify names and versions on Learn every time; the table only maps request words to the right type.

| Request mentions… | Baseline (admin center name) | Folder | Assign to |
|---|---|---|---|
| Windows, OS hardening, MDM baseline, CIS-like Windows settings | Security Baseline for Windows 10 and later | `Windows` | Device groups (most settings are device scope) |
| Defender, antivirus, ASR, EDR, Defender for Endpoint | Microsoft Defender for Endpoint baseline | `Defender for Endpoint` | Device groups of **physical** devices (Microsoft doesn't recommend it for VMs/VDI) |
| Office, Microsoft 365 Apps, macros, Word/Excel/Outlook | Microsoft 365 Apps for Enterprise (Office baseline) | `Microsoft 365 Apps` | User or device groups, depending on the settings' scope |
| Edge, browser | Microsoft Edge Baseline | `Microsoft Edge` | Device groups |
| Cloud PC, Windows 365 | Windows 365 Security Baseline | `Windows 365` | Device groups of Cloud PCs |
| HoloLens | HoloLens 2 - Standard / Advanced security baseline | `HoloLens 2` | Device groups |
| Entra ID, MFA, legacy authentication, sign-in risk, admin protection | Entra ID Conditional Access policies (not an Intune baseline) | `Entra ID` | User groups / all users, with emergency access exclusions |

Other baselines that appear on Learn (for example STIG audit for GCC High, preview baselines)
follow the same pattern: use their admin center name and a folder named after it.

## Where to put it

All baseline profiles live under `Security Baseline/` at the repo root (create it if missing),
one sub-folder per baseline type, then **one folder per baseline profile**:

```text
Security Baseline/
├── Windows/
│   └── Windows Baseline 25H2 Corporate Devices/
│       ├── Windows-Baseline-25H2-Corporate-Devices.json
│       └── README.md
├── Defender for Endpoint/
├── Microsoft 365 Apps/
├── Microsoft Edge/
├── Windows 365/
├── HoloLens 2/
└── Entra ID/
    └── Require MFA All Users/
        ├── Require-MFA-All-Users.json
        └── README.md
```

- Profile folder name: what the profile is for, in Title Case, including the baseline version
  (for example `Windows Baseline 25H2 Corporate Devices`, `Edge Baseline v139 Kiosks`), so two
  versions can sit side by side during an upgrade.
- Exactly two files: `<Folder-Name>.json` (spaces → `-`) and `README.md`.
- If the folder exists, ask before overwriting. For a **version upgrade**, create a new folder and
  leave the old one until the old profile is retired.

## The JSON

The JSON is the **Microsoft Graph request body** that creates the baseline profile:
`POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies`. Current baselines
(released May 2023 or later) are settings-catalog-style policies linked to a template from the
`baseline` template family.

```json
{
  "name": "WIN-SB-Windows Baseline 25H2 Corporate Devices",
  "description": "Security Baseline for Windows 10 and later, version 25H2, Microsoft defaults except the customizations listed in README.md.",
  "platforms": "windows10",
  "technologies": "mdm",
  "roleScopeTagIds": ["<scope-tag-id>"],
  "templateReference": {
    "templateId": "<baseline-template-id-from-tenant>"
  },
  "settings": []
}
```

- **Naming**: use the name from a screenshot or the user when given; otherwise
  `<PREFIX>-SB-<purpose>` with `WIN`, `MDE`, `M365APPS`, `EDGE`, `W365`, `HL2`.
- **Template ID**: Microsoft Learn doesn't publish baseline template IDs, and they change with each
  version. Use the placeholder and give the lookup in the README:
  `GET /beta/deviceManagement/configurationPolicyTemplates?$filter=templateFamily eq 'baseline'`
  (pick the template whose `displayName` and `displayVersion` match). `baseline` is a documented
  `deviceManagementConfigurationTemplateFamily` value.
- **Settings**: a baseline profile created through Graph needs **every** setting instance of the
  template, with Intune's setting definition and instance-template IDs, which aren't documented on
  Learn. Never invent them. Two honest options:
  1. **Metadata-only JSON** (default): `"settings": []`, and the README lists every customization
     for entry in the admin center, plus the export command to replace the JSON with the real body.
  2. **Full JSON from an export**: if the user provides an export of a profile from their tenant
     (`GET .../configurationPolicies/{id}?$expand=settings`), keep its `settings` as-is, apply the
     requested customizations only where the export already contains the matching
     `settingDefinitionId`, and remove read-only properties (`id`, `createdDateTime`,
     `lastModifiedDateTime`, `settingCount`, `isAssigned`, `creationSource`, `templateReference`
     display fields, `@odata.context`).
  Say in the summary which option you used.
- Valid JSON, two-space indentation, no comments, no assignments (they're a separate `/assign`
  call), no secrets.

## README.md

Write for an Intune admin who has never seen the profile. These sections, in this order, using
GitHub-flavored Markdown tables and `> [!NOTE]` / `> [!WARNING]` callouts where useful:

1. **Title + one-line summary**: baseline type, version, who it's for.
2. **Purpose**: the risk it reduces, why a baseline (not individual policies), Zero Trust link
   (device hardening + Entra ID Conditional Access "require compliant device" through a separate
   compliance policy), and any framework the user mentions (CIS, NIST, Essential Eight).
3. **Policy summary**: table with profile name, baseline type, **baseline version**, platform,
   Graph endpoint + `platforms`/`technologies` + template family `baseline`, file name, scope tags,
   recommended assignment, supported OS / app versions, JSON status (metadata-only or full export).
4. **Configuration settings**:
   - A statement that all settings use the **Microsoft defaults for this version** except those listed,
     with a link to the baseline's Learn reference page (with the version pivot).
   - **Customizations** table: Category, Setting (admin center name), Baseline default, **Configured
     value**, Reason / business justification, CSP link. Empty table → "None: Microsoft defaults".
   - **High-impact defaults to review** (5-10 settings from this baseline that commonly break things),
     each with its default and who it affects, so the pilot knows what to test. Look these up in the
     version's reference page; typical ones:
     - Windows: Credential Guard / VBS / LSA protection **with UEFI lock** (unassigning won't turn
       them off; removal needs a manual step per device), local accounts denied network and RDP
       sign-in (affects LAPS / break-glass local admin use), minimum SMB version, local password
       length, DMA protection blocking docks before sign-in, BitLocker write protection for removable
       drives.
     - Defender: ASR rules in Block, sample submission, cloud protection level, local admin merge.
     - Edge: extension block list `*` (blocks every extension not force-installed, including ones
       other policies rely on; plan an allow list first), Basic/Digest authentication blocked,
       IE mode reload restrictions.
     - Microsoft 365 Apps: macros from the internet blocked, legacy file formats blocked, add-in
       restrictions.
5. **Prerequisites**: licensing (Intune Plan 1; **Microsoft Defender for Endpoint** P1/P2 or Microsoft
   365 E5/Defender for Business for the Defender baseline; Microsoft 365 Apps licenses for the
   Office baseline; Windows 365 for Cloud PCs), supported OS/edition (Windows Pro/Enterprise/
   Education; Defender baseline on physical devices), enrollment (Intune-enrolled, Entra joined or
   hybrid joined), Entra ID groups for pilot and production, roles (Endpoint Security Manager or
   Intune Administrator), and dependencies (MDE onboarding for the Defender baseline).
6. **Step-by-step: create the security baseline profile** in the Intune admin center: **Endpoint
   security > Security baselines** > the baseline type > **Create policy** (or *Create profile*;
   confirm the button name on Learn) > **Basics** (Name, Description) > **Configuration settings**
   (expand each category; change only the customizations, in admin center order) > **Scope tags** >
   **Assignments** (include pilot group, exclusions) > **Review + create**.
7. **Step-by-step: import with Microsoft Graph PowerShell**: `Connect-MgGraph -Scopes
   "DeviceManagementConfiguration.ReadWrite.All"`; look up the template ID
   (`configurationPolicyTemplates?$filter=templateFamily eq 'baseline'`); replace placeholders;
   `Invoke-MgGraphRequest -Method POST -Uri .../beta/deviceManagement/configurationPolicies -Body
   (Get-Content <file> -Raw) -ContentType "application/json"` (works in Windows PowerShell 5.1 and 7);
   the `/assign` call with a group ID; and the **export** command to save the finished profile over
   the JSON. If the JSON is metadata-only, say clearly that importing it creates the profile shell
   and the settings must be set in the admin center or by importing a full export.
8. **Assignment & conflict guidance**:
   - User vs device groups (Learn: baselines are assigned to user **or** device groups based on the
     settings' scope, so mixed-scope needs may need two profiles). Use **Entra ID** groups: a pilot
     group first (5-10% of devices, including IT), then broader rings; dynamic device groups (for
     example `(device.deviceOSType -eq "Windows") and (device.deviceOwnership -eq "Company")`) and
     **assignment filters** to target corporate devices or exclude kiosks/VDI.
   - Conflicts: list settings in this repo that overlap (search results from step 3), other
     baselines (different baselines and versions can set the same setting with different defaults),
     endpoint security policies, settings catalog profiles and Group Policy. Explain the rule:
     **one setting, one owner**; set the same value everywhere or remove it from all but one policy.
     For hybrid devices mention GPO vs MDM (*ControlPolicyConflict / MDMWinsOverGP*).
   - Version upgrades: the update copies the profile **without assignments**; assign the new
     version to the pilot, then move groups from the old profile to the new one so a device never
     gets both.
9. **Validation**:
   - Admin center: the profile's **Device status**, **Per setting status**, **Device assignment
     status**; **Devices > All devices > device > Device configuration** for per-setting results.
     Data can take up to 24 hours after the first assignment and up to 6 hours after changes.
   - On the device: Settings > Accounts > Access work or school > Info > **Sync** and **Export
     management log files**; Event Viewer *DeviceManagement-Enterprise-Diagnostics-Provider > Admin*;
     `mdmdiagnosticstool.exe`; product checks (for example `Get-MpComputerStatus` for Defender,
     `msinfo32` for Device Guard/VBS, `edge://policy` for Edge, File > Account in Office apps).
   - **Microsoft 365 / Defender portal**: Microsoft Defender Vulnerability Management **Security
     baselines assessment** and **Microsoft Secure Score** to measure the security effect (when the
     tenant has those licenses).
10. **Troubleshooting**: table Symptom / Cause / Resolution: Pending (no check-in), Not applicable
    (wrong OS/edition/version), **Conflict** (setting owned by two policies; use Setting details >
    Source profiles), **Error** (CSP rejected the value; check OS support), settings needing a
    restart, the Defender baseline on VMs/VDI, read-only old version (update the profile), and
    user-vs-device assignment mistakes.
11. **Rollback**: unassign or delete the profile. Learn: when a baseline no longer applies, settings
    **might not revert** depending on each CSP. To roll back a specific setting, deploy the opposite
    value with a settings catalog policy, confirm, then remove it. For a version upgrade, move
    groups back to the previous profile (kept read-only, not deleted).
12. **References**: Microsoft Learn links only: "Use security baselines", "Manage security baseline
    profiles", "Monitor security baselines", the baseline's settings reference page (with version
    pivot), the CSPs of customized settings, the Graph `deviceManagementConfigurationPolicy` and
    `configurationPolicyTemplates` pages, and Entra ID dynamic groups / Intune filters when used.

Plain, practical language: short sentences, exact menu paths and values.

## Entra ID Conditional Access baseline

For identity baselines, each Conditional Access policy is its own folder under
`Security Baseline/Entra ID/`, with the same two files and the same README sections, adapted:

- **JSON**: the Graph body for `POST https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies`
  (`displayName`, `state`, `conditions`, `grantControls` / `sessionControls`). Verify every property
  and enum on the Microsoft Learn `conditionalAccessPolicy` resource page. Start with
  `"state": "enabledForReportingButNotEnforced"` (report-only). Use placeholders for object IDs
  (`"<emergency-access-group-object-id>"`) and never real user names.
- **Start from Microsoft's templates**: Entra admin center > Protection > Conditional Access >
  **Create new policy from templates** (for example *Require multifactor authentication for all
  users*, *Block legacy authentication*, *Require MFA for administrators*). Confirm template names
  and categories on Learn, and name the template the policy follows in the README.
- **Always exclude** at least two emergency access (break-glass) accounts, usually through a group,
  and service accounts that can't do MFA (for example the Entra Connect sync account, through the
  *Directory Synchronization Accounts* role). Say why in the README.
- **Prerequisites**: Microsoft Entra ID P1 (P2 for sign-in/user risk conditions); security defaults
  must be turned off before Conditional Access is used; check existing Microsoft-managed policies
  to avoid duplicates; roles Conditional Access Administrator or Security Administrator.
- **Validation**: report-only results in the **Sign-in logs** (Conditional Access / Report-only
  tab) and the **Conditional Access insights and reporting** workbook, then switch `state` to
  `enabled`. The **What If** tool tests a user and app before enforcing.
- **Rollback**: set `state` to `disabled` (or back to report-only); the change is immediate and
  nothing is left on devices.
- Graph PowerShell scope: `Policy.ReadWrite.ConditionalAccess` (plus `Policy.Read.All`).

## Conflicts

Before writing anything, search the repo for every customized setting and for the baseline's
high-impact settings:

```bash
grep -ril "<setting name or CSP node>" Configuration/ Compliance/ "Security Baseline/"
```

Report overlaps in the README's conflict section (policy folder, setting, value). Common overlaps
in this kind of repo: Defender Antivirus / ASR / Firewall / BitLocker endpoint security policies vs
the Windows and Defender baselines; Edge configuration profiles vs the Edge baseline; LAPS and
local admin settings vs the Windows baseline.

## Batch requests

When one request asks for several baselines (for example "Windows, Defender and Edge baselines for
our laptops"): list the plan first (baseline, version, folder, assignment), check the set for
overlapping settings between the baselines themselves (Windows and Defender baselines both touch
Defender/firewall settings), build each in its own folder, make **one commit per folder**, push
once, and finish with **one** summary table.

## Before finishing

- `python3 -m json.tool <file>.json` passes; no invented template or setting IDs; no secrets.
- The README has the 12 sections, states the baseline version, and its customizations match the JSON
  (or the JSON is explicitly metadata-only).
- The folder is `Security Baseline/<baseline type>/<profile name>/` with exactly the JSON and README.
- Commit only the new folder with a clear message plus the session's commit trailer, then push with
  `git push -u origin <branch>`. Don't include skill files in the commit.
- Tell the user: baseline type and version (and where you confirmed it), customizations, whether the
  JSON is metadata-only or from an export, conflicts found, recommended assignment, and anything that
  couldn't be verified.
