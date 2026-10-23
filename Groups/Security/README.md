# Security Groups

Security groups are used to grant access or assign resources. A security group can use either **assigned (static)** membership or **dynamic** membership; “security” describes the group type/purpose, not how membership is maintained.

| Example group name | Common use |
|---|---|
| `SG-APP-<Application>-Users` | Grant approved users access to an enterprise application or application role. |
| `SG-APP-<Application>-Admins` | Assign application administration access to a small, explicitly approved set of administrators. |
| `SG-ROLE-Helpdesk` | Scope delegated help-desk access and operational tools to the support team. |
| `SG-ROLE-Endpoint-Admins` | Assign approved endpoint-management administration access; use least privilege and privileged access controls. |
| `SG-ROLE-Directory-Readers` | Provide read-only directory access where a role assignment is not appropriate or group-based assignment is supported. |
| `SG-LIC-<Service>-Users` | Assign a service license to an eligible, governed population when group-based licensing is used. |
| `SG-DATA-<Resource>-Readers` | Grant read-only access to a specific data resource. |
| `SG-DATA-<Resource>-Contributors` | Grant contribution access to a specific data resource, without broader administrative rights. |
| `SG-EXT-<Resource>-Guests` | Scope approved external/guest access to a particular resource and support periodic access reviews. |

## Security and governance guidance

- Grant access through the narrowest group or role that meets the requirement; avoid broad groups such as “everyone” for sensitive resources.
- Prefer role-appropriate Entra roles and Privileged Identity Management (PIM) for privileged access. A group name alone does not make access privileged or secure.
- Require an owner, documented purpose, approval process, and periodic membership/access review for access groups.
- Separate user access from administrator access, and do not use a single group for unrelated applications or permissions.
- Confirm that the target application or resource supports the chosen group-based assignment method.
