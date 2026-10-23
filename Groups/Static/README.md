# Static (Assigned-Membership) Groups

Static groups use **assigned membership**: an owner or administrator adds and removes members directly. They are useful when membership needs human approval, a deliberately limited cohort, or an exception that cannot be reliably determined from directory attributes. Static groups may be security groups or Microsoft 365 groups; the examples here are intended primarily as security groups for access and policy assignment.

| Example group name | Common use |
|---|---|
| `SG-PILOT-<Policy>-Users` | Test user-targeted policies or applications with a small, approved pilot population before broader rollout. |
| `SG-PILOT-<Policy>-Devices` | Test device-targeted Intune policies on selected devices before broad deployment. |
| `SG-EXC-<Policy>-Approved` | Track explicitly approved exclusions from a policy; document the reason, approver, and expiry/review date. |
| `SG-ACCESS-<Application>-Users` | Maintain an approved list of users for application access when dynamic attributes are not suitable. |
| `SG-ACCESS-<Resource>-Admins` | Maintain a small, controlled administrative access population, with privileged access controls where available. |
| `SG-DEPLOY-<Application>-Users` | Stage application deployment to an approved cohort or deployment ring. |
| `SG-CHANGE-<Service>-Testers` | Scope pre-production or change-validation access to designated testers. |
| `SG-TEMP-<Purpose>-<Expiry>` | Manage short-lived access or exception membership; remove the group and access when the approved period ends. |

## Membership management

- Assign at least one accountable owner and document the purpose, approval source, and any access or policy assigned to the group.
- Keep pilot and exception groups small. Record an expiry or review date for temporary access and exclusions.
- Review membership regularly, remove members who no longer qualify, and audit changes for groups granting sensitive access.
- Use dynamic membership instead when a reliable attribute rule can safely and accurately maintain a stable population.
- Static membership does not replace access reviews, least privilege, or privileged access management.
