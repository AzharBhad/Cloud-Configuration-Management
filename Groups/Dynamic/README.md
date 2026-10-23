# Dynamic Groups

Dynamic groups use Microsoft Entra ID membership rules to add or remove users and devices automatically when their attributes change. The examples below are common starting points; adjust attributes and rules to match your directory data and assignment strategy.

| Example group name | Typical membership | Common use |
|---|---|---|
| `DG-USER-All-Employees` | Users with employee-type attributes identifying active employees | Assign baseline user apps, licenses, and user-targeted policies. Exclude privileged or special populations when necessary. |
| `DG-USER-Department-<Name>` | Users whose department attribute matches a department | Target department-specific applications and resources. |
| `DG-USER-Region-<Name>` | Users whose country or region attribute matches a value | Apply location-specific apps, policies, or communications. |
| `DG-USER-Contractors` | Users marked as contractors or another non-employee type | Assign contractor-specific access and policies; keep access limited and review source attributes. |
| `DG-DEVICE-Windows` | Windows devices, based on a reliable platform/device attribute | Target Windows configuration, compliance, and applications in Intune. |
| `DG-DEVICE-macOS` | macOS devices identified by device attributes | Target macOS-specific configuration, compliance, and apps. |
| `DG-DEVICE-iOS-iPadOS` | iOS and iPadOS devices | Target mobile device policies and apps. |
| `DG-DEVICE-Android` | Android devices | Target Android configuration, compliance, and apps. |
| `DG-DEVICE-Corporate-Owned` | Devices identified as corporate-owned | Assign corporate-device policies distinct from personally owned/BYOD policies. |
| `DG-DEVICE-Autopilot` | Windows devices identified as registered with Windows Autopilot | Scope provisioning and enrollment-related assignments. |

## Implementation notes

- Choose a naming convention and use it consistently; `DG` here means dynamic group.
- Build rules from attributes that are populated, governed, and kept current. Test each rule against expected membership before using it for broad assignments.
- Use separate groups for users and devices; avoid mixing object types in a group intended for a specific assignment.
- Dynamic membership requires the applicable Microsoft Entra licensing. Group processing is asynchronous, so membership changes may not take effect immediately.
- These are examples, not a requirement to create every group. Keep groups aligned with actual assignments and avoid overlapping policies with conflicting settings.
